import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/matched_voice_overlay.dart';

enum VoiceMatchState { idle, matching }

class VoiceMatchController extends GetxController {
  VoiceMatchController({this.requestMicrophone, this.openRoom});
  final Future<bool> Function()? requestMicrophone;
  final Future<void> Function(String)? openRoom;
  final _scope = ApiSessionScope();
  VoiceMatchState state = VoiceMatchState.idle;
  bool loading = false;
  String? error;
  Timer? _pollTimer;
  Timer? _matchingTimer;
  int matchingSeconds = 0;
  int _generation = 0;
  bool _openingRoom = false;
  bool _joining = false;
  bool _polling = false;
  String myAvatarUrl = '';
  String myDisplayName = '我';

  bool _current(int generation) =>
      !isClosed && _scope.current && generation == _generation;

  @override
  void onInit() {
    super.onInit();
    apiSessionChanges.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_scope.current || isClosed) return;
    ++_generation;
    _stopTimers();
    state = VoiceMatchState.idle;
    loading = false;
    error = apiSessionChangedMessage;
    update(['voice_match']);
  }

  @override
  void onReady() {
    super.onReady();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await _scope.get('/api/auth/me');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data == null || isClosed) return;
      myDisplayName = data['nickname']?.toString().trim() ?? '我';
      myAvatarUrl = data['avatarUrl']?.toString().trim() ?? '';
      update(['voice_match']);
    } catch (_) {}
  }

  Future<void> startMatch() async {
    if (loading ||
        _joining ||
        _openingRoom ||
        state == VoiceMatchState.matching) {
      return;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    update(['voice_match']);
    try {
      final allowed = await (requestMicrophone?.call() ??
          Permission.microphone.request().then((s) => s.isGranted));
      if (!_current(generation)) return;
      if (!allowed) throw const FormatException('需要麦克风权限才能语音匹配，请在系统设置中允许');
      _joining = true;
      final response = await _scope.post('/api/voice-match/join');
      if (!_current(generation)) {
        // A late join response must not resurrect matching after the user exits.
        if (_scope.current) await _scope.post('/api/voice-match/cancel');
        return;
      }
      final data = (response.data as Map?)?['data'] as Map?;
      loading = false;
      await _handleStatus(data, generation, joining: true);
    } catch (e) {
      if (_current(generation)) {
        state = VoiceMatchState.idle;
        error = _message(e, '加入匹配失败，请重试');
      }
    } finally {
      _joining = false;
      if (_current(generation)) {
        loading = false;
        update(['voice_match']);
      }
    }
  }

  String _message(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      return (e.response!.data as Map)['message']?.toString() ?? fallback;
    }
    if (e is FormatException) return e.message;
    if (e is ApiSessionChangedException) return apiSessionChangedMessage;
    return fallback;
  }

  Future<void> _handleStatus(
    Map? data,
    int generation, {
    bool joining = false,
  }) async {
    if (!_current(generation)) return;
    final status = data?['status']?.toString();
    if (status == 'matched') {
      final roomId = data?['roomId']?.toString() ?? '';
      if (roomId.isEmpty) throw const FormatException('匹配结果缺少房间，请重新开始');
      if (_openingRoom) return;
      _openingRoom = true;
      _stopTimers();
      state = VoiceMatchState.idle;
      update(['voice_match']);
      try {
        if (openRoom != null) {
          await openRoom!(roomId);
        } else {
          await MatchedVoiceOverlay.instance.open(roomId);
        }
        if (_current(generation)) await _scope.post('/api/voice-match/cancel');
      } finally {
        _openingRoom = false;
      }
      return;
    }
    if (status == 'waiting') {
      error = null;
      state = VoiceMatchState.matching;
      if (joining) {
        matchingSeconds = 0;
        _matchingTimer?.cancel();
        _matchingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!_current(generation)) return;
          matchingSeconds++;
          update(['voice_match']);
        });
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(
          const Duration(milliseconds: 1500),
          (_) => pollStatus(),
        );
      }
    } else {
      _stopTimers();
      state = VoiceMatchState.idle;
      error = data?['message']?.toString() ??
          switch (status) {
            'no_gender' => '请完善个人资料后重新匹配',
            'minor_mode' => '未成年人模式暂不支持语音匹配',
            _ => '匹配已结束，请重新开始',
          };
    }
    update(['voice_match']);
  }

  Future<void> pollStatus() async {
    if (_polling || state != VoiceMatchState.matching || isClosed) return;
    final generation = _generation;
    _polling = true;
    try {
      final res = await _scope.get('/api/voice-match/status');
      await _handleStatus((res.data as Map?)?['data'] as Map?, generation);
    } catch (e) {
      if (_current(generation)) {
        error = _message(e, '暂时无法连接匹配服务，正在重试…');
        if (e is DioException &&
            const [401, 403, 404].contains(e.response?.statusCode)) {
          _stopTimers();
          state = VoiceMatchState.idle;
        }
        update(['voice_match']);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> cancelMatch() async {
    ++_generation;
    _stopTimers();
    state = VoiceMatchState.idle;
    loading = false;
    try {
      await _scope.post('/api/voice-match/cancel');
      error = null;
    } catch (e) {
      error = _message(e, '退出请求未送达，请重试');
    }
    if (!isClosed) update(['voice_match']);
  }

  Future<void> exitPage() async {
    if (state == VoiceMatchState.matching || loading) await cancelMatch();
    if (Get.key.currentState?.canPop() ?? false) Get.back();
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _matchingTimer?.cancel();
    matchingSeconds = 0;
  }

  String get matchingDuration =>
      '${(matchingSeconds ~/ 60).toString().padLeft(2, '0')}:${(matchingSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void onClose() {
    apiSessionChanges.removeListener(_sessionChanged);
    final cancel =
        !_openingRoom && (state == VoiceMatchState.matching || _joining);
    ++_generation;
    _stopTimers();
    if (cancel && _scope.current) {
      unawaited(
        _scope
            .post('/api/voice-match/cancel')
            .then<void>((_) {}, onError: (_) {}),
      );
    }
    super.onClose();
  }
}
