import '../../core/utils/call_background_audio.dart';
import '../../shared/widgets/call_back_choice.dart';
import '../../core/utils/rtc_speech.dart';
import 'consultation_call_overlay.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/agora_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/payment/apple_iap_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../community/user_profile_page.dart';
import '../profile/recharge_page.dart';
import 'consultation_payment_setting_page.dart';
import 'private_line_checkout_page.dart';
import 'voice_room_backgrounds.dart';
import 'voice_room_overlay_controller.dart';
import 'voice_room_profile_page.dart';
import 'voice_room_share.dart';
import 'voice_room_design.dart';
import 'room_chart_sheet.dart';
import '../virtual_goods/virtual_gift_sheet.dart';
import '../virtual_goods/virtual_gift_playback_queue.dart';
import '../message/im_workflow_request.dart';
import 'room_message_recall.dart';

int? _voiceRoomRtcUid(Map<String, dynamic> member) {
  final userId = (member['userId'] as num?)?.toInt();
  if (userId == null || userId <= 0) return null;
  return (userId % 4294967295) == 0 ? 1 : userId % 4294967295;
}

class VoicePlazaRoomPage extends StatefulWidget {
  const VoicePlazaRoomPage({
    super.key,
    required this.roomId,
    this.rtcEngineFactory,
    this.roomEventsConnector,
    this.audioServiceUpdater,
  });
  final int roomId;
  @visibleForTesting
  final RtcEngine Function()? rtcEngineFactory;
  @visibleForTesting
  final Future<WebSocket> Function(String url, Map<String, dynamic> headers)?
      roomEventsConnector;
  @visibleForTesting
  final Future<void> Function(bool active, bool microphone)?
      audioServiceUpdater;

  @override
  State<VoicePlazaRoomPage> createState() => _VoicePlazaRoomPageState();
}

class _VoicePlazaRoomPageState extends State<VoicePlazaRoomPage>
    with WidgetsBindingObserver {
  static const _maxRetainedMessages = 300;
  final _messageController = TextEditingController();
  final _messageScrollController = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  final _messageScope = ImWorkflowRequest();
  Map<String, dynamic>? _room;
  RtcEngine? _engine;
  Timer? _pollTimer;
  WebSocket? _roomEventsSocket;
  Timer? _roomEventsReconnectTimer;
  Timer? _roomEventsRefreshTimer;
  bool _loading = true;
  bool _publisher = false;
  bool _muted = true;
  bool _hostMuted = false;
  bool _speaker = true;
  bool _leaving = false;
  bool _forcedExit = false;
  bool _heartbeatInFlight = false;
  Future<bool>? _refreshTask;
  bool _refreshPending = false;
  bool _roomEventsConnecting = false;
  bool _rtcConnecting = false;
  bool _rtcSyncPending = false;
  bool _resumeInFlight = false;
  bool _joinedRoom = false;
  bool _audioSuspended = false;
  int _roomEventsGeneration = 0;
  int? _overlayGeneration;
  bool _micPermissionBlocked = false;
  bool _followBusy = false;
  final _virtualEffects = VirtualGiftPlaybackQueue();
  final Map<int, Timer> _voiceActivityTimers = {};
  final Set<int> _activeRtcUids = {};
  final Set<int> _rtcMutedUids = {};
  final ValueNotifier<int> _voiceActivityRevision = ValueNotifier(0);
  final Set<String> _busyActions = {};
  int? _localRtcUid;
  int _lastMessageId = 0;
  int _roomEventsReconnectAttempt = 0;
  int _rtcGeneration = 0;
  bool _rtcConnected = false;
  bool _tokenRenewInFlight = false;
  bool _publicRtcReadySent = false;
  bool _stickToLatestMessage = true;
  String _backgroundValue = '';
  ImageProvider<Object>? _backgroundImage;
  String? _error;
  String? _joinPassword;
  final _overlayController = VoiceRoomOverlayController.instance;

  bool get _ownsOverlay =>
      _overlayGeneration != null &&
      _overlayController.generation == _overlayGeneration &&
      _overlayController.isActiveRoom(widget.roomId);
  bool get _current =>
      mounted &&
      _messageScope.current &&
      !_forcedExit &&
      (_overlayGeneration == null || _ownsOverlay);
  bool get _available => _current && !_leaving;
  bool get _audioAvailable => _available && !_audioSuspended;
  bool get _mayStopAudioService =>
      !_overlayController.hasActiveRoom || _ownsOverlay;

  void _closeOwnedOverlay() {
    if (_ownsOverlay) _overlayController.didClose(widget.roomId);
  }

  @override
  void initState() {
    super.initState();
    if (_overlayController.isActiveRoom(widget.roomId)) {
      _overlayGeneration = _overlayController.generation;
    }
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_clearMessagesOnAccountChange);
    _overlayController.attach(
      widget.roomId,
      VoiceRoomOverlayCallbacks(
        onClose: _leave,
        onToggleMute: _toggleLocalMute,
        onSuspendAudio: _suspendRoomAudio,
        onResumeAudio: _resumeRoomAudio,
      ),
    );
    _messageScrollController.addListener(_trackMessageScrollPosition);
    _enter();
    // WebSocket 负责及时刷新；低频轮询只在网络切换或推送不可用时兜底。
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_clearMessagesOnAccountChange);
    if (_ownsOverlay) _overlayController.detach(widget.roomId);
    _pollTimer?.cancel();
    _disconnectRoomEvents();
    _virtualEffects.clear();
    for (final timer in _voiceActivityTimers.values) {
      timer.cancel();
    }
    _voiceActivityTimers.clear();
    _messageController.dispose();
    _messageScrollController.dispose();
    _voiceActivityRevision.dispose();
    _rtcGeneration += 1;
    final engine = _engine;
    _engine = null;
    unawaited(_setVoiceRoomAudioService(false));
    unawaited(_disposeEngine(engine));
    super.dispose();
  }

  void _clearMessagesOnAccountChange() {
    if (!mounted || _messageScope.current) return;
    unawaited(_exitBecause(imSessionChangedMessage));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverRtcAfterResume());
    }
  }

  Future<void> _enter() async {
    try {
      final fresh = await _refresh();
      if (fresh &&
          _audioAvailable &&
          ['live', 'paused'].contains(_room?['status'])) {
        await _connect();
        // 加入接口落库后立即取回自己的成员身份，不等待下一次兜底轮询。
        await _refresh();
        unawaited(_connectRoomEvents());
      }
    } catch (_) {
      if (_available && _room == null) _error = '房间暂时无法打开，请稍后重试';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollMessagesToLatest(animated: false);
      }
    }
  }

  bool _deepEquals(dynamic left, dynamic right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_deepEquals(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }

  void _syncBackground(Map<String, dynamic>? room) {
    final raw = room?['coverUrl']?.toString().trim() ?? '';
    final value = raw.isEmpty ? voiceRoomDefaultBackground.coverValue : raw;
    if (_backgroundValue == value && _backgroundImage != null) return;
    _backgroundValue = value;
    _backgroundImage = voiceRoomBackgroundImage(value);
    final provider = _backgroundImage;
    if (provider != null) {
      unawaited(precacheImage(provider, context).catchError((_) {}));
    }
  }

  void _trackMessageScrollPosition() {
    if (!_messageScrollController.hasClients) return;
    final position = _messageScrollController.position;
    _stickToLatestMessage = position.maxScrollExtent - position.pixels <= 72;
  }

  void _scrollMessagesToLatest({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScrollController.hasClients) return;
      final target = _messageScrollController.position.maxScrollExtent;
      if (animated) {
        _messageScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _messageScrollController.jumpTo(target);
      }
    });
  }

  Future<bool> _refresh() {
    if (!_available) return Future.value(false);
    final inFlight = _refreshTask;
    if (inFlight != null) {
      _refreshPending = true;
      return inFlight;
    }
    final completion = Completer<bool>();
    _refreshTask = completion.future;
    unawaited(() async {
      var fresh = false;
      try {
        // 慢网时15秒轮询可能每轮都置pending；一次调用最多追赶一轮，
        // 保证enter/resume最终拿到本批权威结果，其余变更交后续事件/轮询。
        for (var pass = 0; pass < 2; pass++) {
          _refreshPending = false;
          fresh = await _refreshOnce();
          if (!_refreshPending || !_available) break;
        }
        completion.complete(fresh && _available);
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _refreshPending = false;
        _refreshTask = null;
      }
    }());
    return completion.future;
  }

  Future<bool> _refreshOnce() async {
    try {
      final roomRaw =
          await _messageScope.get('/api/consultation/rooms/${widget.roomId}');
      if (!_available) return false;
      if (['ended', 'closed'].contains(roomRaw['status'])) {
        await _exitBecause('本场语音房已结束');
        return false;
      }
      if (_joinedRoom && _myMember(roomRaw) == null) {
        await _exitBecause('您已离开该房间');
        return false;
      }
      final messagesRaw = <Map<String, dynamic>>[];
      final revokedIds = <int>{};
      var messagesFetched = false;
      try {
        var cursor = _lastMessageId;
        // 服务端每页最多100条；恢复时补页，单次最多1000条防止无限追赶。
        for (var page = 0; page < 10 && _available; page++) {
          final messageData = await _messageScope
              .get('/api/consultation/rooms/${widget.roomId}/messages', query: {
            'after_id': cursor,
            'known_ids': _messages.map((row) => row['id']).join(','),
          });
          final pageRows = imResponseList(messageData);
          messagesFetched = true;
          messagesRaw.addAll(pageRows);
          revokedIds.addAll((messageData['revokedIds'] as List? ?? [])
              .whereType<num>()
              .map((id) => id.toInt()));
          var next = cursor;
          for (final row in pageRows) {
            final id = (row['id'] as num?)?.toInt() ?? 0;
            if (id > next) next = id;
          }
          if (pageRows.length < 100 || next <= cursor) break;
          cursor = next;
        }
      } catch (error) {
        if (_joinedRoom &&
            [401, 403, 404, 410].contains(imFailureStatus(error))) {
          if (_available) await _exitBecause('您已无法访问该房间');
          return false;
        }
      }
      if (!_available) return false;
      final nextRoom = roomRaw;
      final roomChanged = !_deepEquals(_room, nextRoom);
      final newMessages = <Map<String, dynamic>>[];
      {
        for (final item in messagesRaw) {
          final value = Map<String, dynamic>.from(item);
          if (_messages.every((m) => m['id'] != value['id']) &&
              newMessages.every((m) => m['id'] != value['id'])) {
            newMessages.add(value);
          }
          final id = (value['id'] as num?)?.toInt() ?? 0;
          if (id > _lastMessageId) _lastMessageId = id;
        }
      }
      final mergedMessages =
          mergeRoomMessages(_messages, newMessages, revokedIds)
              .where((message) => !['entry', 'entry_effect', 'relationship']
                  .contains(message['type']))
              .toList();
      final messagesChanged = !_deepEquals(_messages, mergedMessages);
      final previousEffect = _virtualEffects.active;
      if (messagesFetched) {
        _virtualEffects.observeMessages(
          messagesRaw.where((row) => !revokedIds.contains(row['id'])),
          includeEntries: true,
        );
      }
      final effectChanged = !identical(previousEffect, _virtualEffects.active);
      if (roomChanged || messagesChanged || effectChanged) {
        final shouldFollowMessages = _loading || _stickToLatestMessage;
        setState(() {
          if (roomChanged) {
            _room = nextRoom;
            _syncBackground(nextRoom);
          }
          if (messagesChanged) {
            _messages
              ..clear()
              ..addAll(mergedMessages);
            if (_messages.length > _maxRetainedMessages) {
              _messages.removeRange(0, _messages.length - _maxRetainedMessages);
            }
          }
        });
        if (newMessages.isNotEmpty && shouldFollowMessages) {
          _scrollMessagesToLatest(animated: !_loading);
        }
      }
      final me = _myMember(nextRoom);
      final shouldPublish = me?['role'] == 'owner' ||
          ['speaker', 'admin'].contains(me?['role']) &&
              me?['micStatus'] == 'speaking';
      if (shouldPublish != _publisher &&
          _engine != null &&
          !_micPermissionBlocked) {
        await _connect(force: true);
      }
      final serverMuted = me?['muted'] == true;
      if (!_available) return false;
      if (_publisher && serverMuted && !_hostMuted) {
        await _engine?.muteLocalAudioStream(true);
        if (mounted && _available) {
          setState(() {
            _hostMuted = true;
            _muted = true;
          });
          showAppToast(context, '房主已将你禁麦');
        }
      } else if (mounted && _hostMuted && !serverMuted && _available) {
        setState(() {
          _hostMuted = false;
          _muted = true;
        });
        showAppToast(context, '房主已解除禁麦，请点击麦克风恢复发言');
      }
      if (me?['micStatus'] == 'accepted' &&
          !_busyActions.contains('start_mic')) {
        unawaited(_startMic());
      }
      final mySession = nextRoom['mySession'];
      if (mySession is Map && mySession['status'] == 'active') {
        unawaited(_heartbeatSession(Map<String, dynamic>.from(mySession)));
      }
      _publishOverlaySnapshot(nextRoom);
      return true;
    } catch (error) {
      if (!_available) return false;
      if ([401, 403, 404, 410].contains(imFailureStatus(error))) {
        await _exitBecause(imFailureMessage(error, '您已无法访问该房间'));
      } else {
        setState(() => _error = imFailureMessage(error, '房间状态同步失败，请重试'));
      }
      return false;
    }
  }

  Uri _roomEventsUri() {
    final base = Uri.parse(apiClient.options.baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/ws/consultation/rooms/${widget.roomId}',
      query: null,
      fragment: null,
    );
  }

  Future<void> _connectRoomEvents() async {
    if (!_available ||
        _roomEventsConnecting ||
        _roomEventsSocket != null ||
        !['live', 'paused'].contains(_room?['status'])) {
      return;
    }
    final authorization =
        _messageScope.options.headers?['Authorization']?.toString() ?? '';
    if (!authorization.startsWith('Bearer ')) return;
    _roomEventsConnecting = true;
    final generation = _roomEventsGeneration;
    try {
      final headers = <String, dynamic>{'Authorization': authorization};
      final socket = await (widget.roomEventsConnector
              ?.call(_roomEventsUri().toString(), headers) ??
          WebSocket.connect(_roomEventsUri().toString(), headers: headers));
      if (!_available || generation != _roomEventsGeneration) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      socket.pingInterval = const Duration(seconds: 25);
      _roomEventsReconnectTimer?.cancel();
      _roomEventsReconnectAttempt = 0;
      _roomEventsSocket = socket;
      socket.listen(
        (raw) {
          if (_available && identical(_roomEventsSocket, socket)) {
            _handleRoomEvent(raw);
          }
        },
        onDone: () => _handleRoomEventsDisconnected(socket),
        onError: (_) => _handleRoomEventsDisconnected(socket),
        cancelOnError: true,
      );
      // 推送只有变更通知，无消息重放；每次建连成功都用REST追赶断线缺口。
      unawaited(_refresh());
    } catch (_) {
      if (generation == _roomEventsGeneration) _scheduleRoomEventsReconnect();
    } finally {
      _roomEventsConnecting = false;
    }
  }

  void _handleRoomEvent(dynamic raw) {
    if (!_available) return;
    try {
      final decoded = jsonDecode(raw?.toString() ?? '');
      if (decoded is! Map ||
          decoded['type'] != 'room.changed' ||
          (decoded['roomId'] as num?)?.toInt() != widget.roomId) {
        return;
      }
      // 短时间内连续的麦序、成员和消息事件合并成一次权威 REST 刷新。
      _roomEventsRefreshTimer?.cancel();
      _roomEventsRefreshTimer = Timer(
        const Duration(milliseconds: 100),
        () => unawaited(_refresh()),
      );
    } catch (_) {}
  }

  void _handleRoomEventsDisconnected(WebSocket socket) {
    if (!identical(_roomEventsSocket, socket)) return;
    _roomEventsSocket = null;
    _scheduleRoomEventsReconnect();
  }

  void _scheduleRoomEventsReconnect() {
    if (!_available ||
        _roomEventsReconnectTimer?.isActive == true ||
        !['live', 'paused'].contains(_room?['status'])) {
      return;
    }
    const delays = <int>[1, 2, 4, 8, 15];
    final delay =
        delays[_roomEventsReconnectAttempt.clamp(0, delays.length - 1).toInt()];
    _roomEventsReconnectAttempt++;
    _roomEventsReconnectTimer = Timer(
      Duration(seconds: delay),
      () => unawaited(_connectRoomEvents()),
    );
  }

  void _disconnectRoomEvents() {
    _roomEventsGeneration++;
    _roomEventsReconnectTimer?.cancel();
    _roomEventsRefreshTimer?.cancel();
    final socket = _roomEventsSocket;
    _roomEventsSocket = null;
    if (socket != null) {
      unawaited(socket.close(WebSocketStatus.normalClosure));
    }
  }

  Map<String, dynamic>? _decodeVirtualPayload(dynamic content) {
    try {
      final decoded = jsonDecode(content?.toString() ?? '');
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _playVirtualEffect(Map<String, dynamic> payload) {
    if (!_available) return;
    setState(() => _virtualEffects.enqueue(payload));
  }

  void _completeVirtualEffect(Map<String, dynamic> effect) {
    if (!_current) return;
    setState(() => _virtualEffects.complete(effect));
  }

  Future<void> _openGiftSheet() async {
    if (!_available) return;
    final room = _room;
    if (room == null) return;
    final members = room['members'] is List
        ? (room['members'] as List).whereType<Map>()
        : const Iterable<Map>.empty();
    final targets = members
        .where((member) => member['isMe'] != true)
        .map((member) => VirtualGiftTarget(
              userId: (member['userId'] as num).toInt(),
              nickname: member['nickname']?.toString() ?? '房间用户',
              roomId: widget.roomId,
            ))
        .toList();
    final me = _myMember(room);
    if (me?['role'] == 'owner' && me?['userId'] is num) {
      targets.insert(
        0,
        VirtualGiftTarget(
          userId: (me!['userId'] as num).toInt(),
          nickname: '全场',
          roomId: widget.roomId,
        ),
      );
    }
    if (targets.isEmpty) {
      showAppToast(context, '房间里还没有可以赠送礼物的人');
      return;
    }
    final result = await showVirtualGiftSheet(context, targets: targets);
    if (result != null && mounted && _available) {
      _playVirtualEffect(result);
      showAppToast(context, '礼物已送出');
    }
  }

  Future<void> _exitBecause(String message) async {
    if (_forcedExit) return;
    _forcedExit = true;
    _pollTimer?.cancel();
    _disconnectRoomEvents();
    _virtualEffects.clear();
    if (mounted) {
      _messageController.clear();
      setState(() {
        _room = null;
        _messages.clear();
        _lastMessageId = 0;
        _error = message;
        _loading = false;
      });
    }
    _closeOwnedOverlay();
    await _releaseRtcEngine();
    if (mounted) showAppToast(context, message);
  }

  Future<void> _heartbeatSession(Map<String, dynamic> session) async {
    if (_heartbeatInFlight || !_available) return;
    final sessionId = (session['id'] as num?)?.toInt();
    if (sessionId == null) return;
    _heartbeatInFlight = true;
    try {
      final data = await _messageScope
          .post('/api/consultation/sessions/$sessionId/heartbeat');
      if (!_available) return;
      if (data['shouldEnd'] == true) {
        await _messageScope.post('/api/consultation/sessions/$sessionId/end',
            data: {'reason': 'balance_exhausted'});
        if (mounted && _available) showAppToast(context, '余额已用完，本次连麦已结束');
        await _refresh();
      }
    } catch (_) {
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Map<String, dynamic>? _myMember(Map<String, dynamic>? room) {
    final members = room?['members'];
    if (members is! List) return null;
    for (final item in members.whereType<Map>()) {
      if (item['isMe'] == true) return Map<String, dynamic>.from(item);
    }
    return null;
  }

  void _publishOverlaySnapshot(Map<String, dynamic>? room) {
    if (room == null || !_available || !_ownsOverlay) return;
    final owner = room['owner'] is Map ? room['owner'] as Map : const {};
    final me = _myMember(room);
    final session = room['mySession'] is Map ? room['mySession'] as Map : null;
    final sessionStatus = session?['status']?.toString();
    final paidActive = sessionStatus == 'active';
    String subtitle;
    if (paidActive) {
      final seconds = (session?['billedSeconds'] as num?)?.toInt() ?? 0;
      subtitle = '计费中 · ${_clock(seconds)}';
    } else if (me?['micStatus'] == 'queued') {
      subtitle = '上麦申请中 · 等待不收费';
    } else if (me?['micStatus'] == 'accepted') {
      subtitle = '房主已同意 · 点击返回开麦';
    } else if (_publisher) {
      subtitle = _hostMuted
          ? '已被房主禁麦'
          : _muted
              ? '已闭麦'
              : '麦克风已开启';
    } else {
      subtitle = room['roomType'] == 'master' ? '房间内' : '免费收听中';
    }
    _overlayController.updateSnapshot(
      widget.roomId,
      VoiceRoomMiniSnapshot(
        title: room['title']?.toString() ?? '语音房',
        subtitle: subtitle,
        avatarUrl: owner['avatarUrl']?.toString() ?? '',
        canMute: _publisher,
        muted: _muted || _hostMuted,
        paidActive: paidActive,
      ),
    );
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  void _markVoiceActivity(AudioVolumeInfo info) {
    if (!mounted) return;
    final rawUid = info.uid ?? 0;
    final rtcUid = rawUid == 0 ? _localRtcUid : rawUid;
    if (rtcUid == null || rtcUid <= 0) return;
    final local = rawUid == 0;
    final audible = (info.volume ?? 0) >= 18 &&
        (!local || (!_muted && !_hostMuted)) &&
        !_rtcMutedUids.contains(rtcUid);
    if (!audible) return;
    _voiceActivityTimers.remove(rtcUid)?.cancel();
    if (_activeRtcUids.add(rtcUid)) _voiceActivityRevision.value++;
    _voiceActivityTimers[rtcUid] = Timer(const Duration(milliseconds: 620), () {
      _voiceActivityTimers.remove(rtcUid);
      if (mounted && _activeRtcUids.remove(rtcUid)) {
        _voiceActivityRevision.value++;
      }
    });
  }

  void _clearVoiceActivity(int? rtcUid) {
    if (rtcUid == null) return;
    _voiceActivityTimers.remove(rtcUid)?.cancel();
    if (mounted && _activeRtcUids.remove(rtcUid)) {
      _voiceActivityRevision.value++;
    }
  }

  Future<void> _toggleLocalMute() async {
    if (!_publisher || _engine == null || !_beginAction('local_mute')) return;
    if (_hostMuted) {
      if (mounted) showAppToast(context, '房主尚未解除禁麦');
      _endAction('local_mute');
      return;
    }
    try {
      final next = !_muted;
      await _engine?.muteLocalAudioStream(next);
      if (!mounted) return;
      setState(() => _muted = next);
      if (next) _clearVoiceActivity(_localRtcUid);
      _publishOverlaySnapshot(_room);
    } finally {
      _endAction('local_mute');
    }
  }

  Future<void> _startMic() async {
    if (!_beginAction('start_mic')) return;
    try {
      final microphone = await Permission.microphone.request();
      if (!microphone.isGranted) {
        try {
          await apiClient
              .post('/api/consultation/rooms/${widget.roomId}/mic/cancel');
          await _refresh();
        } catch (_) {}
        if (mounted) showAppToast(context, '未获得麦克风权限，已释放麦位');
        return;
      }
      try {
        await apiClient
            .post('/api/consultation/rooms/${widget.roomId}/mic/start');
        if (mounted) {
          setState(() {
            _micPermissionBlocked = false;
            _muted = false;
          });
        }
        await _refresh();
      } on DioException catch (e) {
        if (mounted) {
          showAppToast(
            context,
            (e.response?.data as Map?)?['message']?.toString() ?? '开麦失败',
          );
        }
      }
    } finally {
      _endAction('start_mic');
    }
  }

  bool _beginAction(String key) {
    if (!_available || _busyActions.contains(key)) return false;
    _busyActions.add(key);
    return true;
  }

  void _endAction(String key) => _busyActions.remove(key);

  Future<void> _connect({bool force = false}) async {
    if (!_audioAvailable) return;
    if (_rtcConnecting) {
      _rtcSyncPending = true;
      return;
    }
    _rtcConnecting = true;
    try {
      await _connectInternal(force: force);
    } finally {
      _rtcConnecting = false;
      if (_rtcSyncPending && _audioAvailable) {
        _rtcSyncPending = false;
        unawaited(_syncRtcWithRoom());
      }
    }
  }

  Future<void> _syncRtcWithRoom() async {
    if (!_audioAvailable) return;
    final localMember = _myMember(_room);
    final shouldPublish = localMember?['role'] == 'owner' ||
        ['speaker', 'admin'].contains(localMember?['role']) &&
            localMember?['micStatus'] == 'speaking';
    if (_engine == null) {
      await _connect();
    } else if (shouldPublish != _publisher && !_micPermissionBlocked) {
      await _connect(force: true);
    }
  }

  Future<void> _connectInternal({bool force = false}) async {
    if (!_audioAvailable || (!force && _engine != null)) return;
    final requestGeneration = _rtcGeneration;
    try {
      final localMember = _myMember(_room);
      final expectsPublisher = localMember?['role'] == 'owner' ||
          ['speaker', 'admin'].contains(localMember?['role']) &&
              localMember?['micStatus'] == 'speaking';
      if (expectsPublisher) {
        final microphone = await Permission.microphone.request();
        if (!_audioAvailable || requestGeneration != _rtcGeneration) return;
        if (!microphone.isGranted) {
          if (mounted) {
            setState(() {
              _micPermissionBlocked = true;
              _error = '需要麦克风权限才能上麦';
            });
            showAppToast(context, '请允许麦克风权限后再上麦');
          }
          return;
        }
        _micPermissionBlocked = false;
      }
      if (!_audioAvailable || requestGeneration != _rtcGeneration) return;
      final data = await _messageScope.post(
          '/api/consultation/rooms/${widget.roomId}/join',
          data: <String, dynamic>{
            if (_joinPassword != null) 'password': _joinPassword,
            if (_room?['roomType'] == 'master' && expectsPublisher)
              'deferredReady': true,
          });
      if (!_audioAvailable || requestGeneration != _rtcGeneration) return;
      final token = data['rtcToken']?.toString();
      final channel = data['channel']?.toString();
      final uid = (data['uid'] as num?)?.toInt() ?? 0;
      final publisher = data['publisher'] == true;
      if (token == null || channel == null || uid <= 0) {
        throw const FormatException();
      }
      _joinedRoom = true;
      if (force && _engine != null) {
        final currentEngine = _engine!;
        try {
          // 上下麦只更新当前频道身份，避免退出/重进引起画面频闪和音频空窗。
          await currentEngine.renewToken(token);
          _ensureRtcCurrent(currentEngine);
          await _configureRoomAudio(currentEngine);
          await currentEngine.muteAllRemoteAudioStreams(false);
          _ensureRtcCurrent(currentEngine);
          await _applyRoomPublisherRole(currentEngine, publisher);
          if (_audioAvailable && identical(_engine, currentEngine)) {
            setState(() {
              _publisher = publisher;
              _rtcConnected = true;
              _error = null;
            });
          }
          if (!_audioAvailable || !identical(_engine, currentEngine)) return;
          await _setVoiceRoomAudioService(true, microphone: publisher);
          if (!publisher) _clearVoiceActivity(_localRtcUid);
          if (publisher) {
            await _markPublicRtcReady();
          } else {
            _publicRtcReadySent = false;
          }
          _publishOverlaySnapshot(_room);
          return;
        } catch (_) {
          if (!_audioAvailable) return;
          // 极少数设备不支持频道内切换时，仅回退一次完整重连。
          await _releaseRtcEngine();
        }
      }
      if (!_audioAvailable) return;
      if (_engine != null) return;
      if (publisher && !expectsPublisher) {
        final microphone = await Permission.microphone.request();
        if (!_audioAvailable) return;
        if (!microphone.isGranted) {
          final session = _room?['mySession'];
          final sessionId =
              session is Map ? (session['id'] as num?)?.toInt() : null;
          if (sessionId != null) {
            await _messageScope.post(
                '/api/consultation/sessions/$sessionId/end',
                data: {'reason': 'microphone_permission_denied'});
          }
          throw const FormatException('需要麦克风权限才能上麦');
        }
      }
      final engine = (widget.rtcEngineFactory ?? createAgoraRtcEngine)();
      _engine = engine;
      _localRtcUid = uid;
      final generation = ++_rtcGeneration;
      if (mounted) {
        setState(() {
          _rtcConnected = false;
          _error = null;
        });
      }
      await engine.initialize(RtcEngineContext(
        appId: data['appId']?.toString() ?? AgoraConstants.appId,
        audioScenario: AudioScenarioType.audioScenarioMeeting,
      ));
      _ensureRtcCurrent(engine);
      await engine
          .setChannelProfile(ChannelProfileType.channelProfileLiveBroadcasting);
      _ensureRtcCurrent(engine);
      await engine.setClientRole(
          role: publisher
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience);
      _ensureRtcCurrent(engine);
      await _configureRoomAudio(engine);
      await engine.enableAudioVolumeIndication(
          interval: 250, smooth: 3, reportVad: true);
      _ensureRtcCurrent(engine);
      engine.registerEventHandler(RtcEngineEventHandler(
        onAudioRoutingChanged: (_) {
          if (_audioAvailable &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            unawaited(restoreRtcSpeechProcessing(engine));
          }
        },
        onJoinChannelSuccess: (_, __) {
          if (_audioAvailable &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            setState(() {
              _publisher = publisher;
              _rtcConnected = true;
              _error = null;
            });
            unawaited(_applyJoinedAudioRoute(engine, generation));
            _publishOverlaySnapshot(_room);
            if (publisher) unawaited(_markPublicRtcReady());
          }
        },
        onError: (_, message) {
          if (_audioAvailable &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            setState(() => _error = message.isEmpty ? '语音连接异常' : message);
          }
        },
        onConnectionStateChanged: (_, state, __) {
          if (!_audioAvailable ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          final connected =
              state == ConnectionStateType.connectionStateConnected;
          final failed = state == ConnectionStateType.connectionStateFailed;
          final reconnecting =
              state == ConnectionStateType.connectionStateReconnecting;
          if (_rtcConnected != connected || failed || reconnecting) {
            setState(() {
              _rtcConnected = connected;
              if (connected) {
                _error = null;
              } else if (failed) {
                _error = '语音连接失败，点击重新连接';
              } else if (reconnecting) {
                _error = '网络波动，正在恢复语音连接…';
              }
            });
          }
        },
        onLocalAudioStateChanged: (_, state, reason) {
          if (_audioAvailable &&
              generation == _rtcGeneration &&
              identical(_engine, engine) &&
              state == LocalAudioStreamState.localAudioStreamStateFailed) {
            setState(() => _error = '麦克风收音失败，请检查权限后重新连接');
          }
        },
        onRemoteAudioStateChanged: (_, __, state, reason, ___) {
          if (_audioAvailable &&
              generation == _rtcGeneration &&
              identical(_engine, engine) &&
              state == RemoteAudioState.remoteAudioStateFailed) {
            setState(() => _error = '接收语音失败，请重新连接');
          }
        },
        onTokenPrivilegeWillExpire: (_, __) {
          unawaited(_renewRoomRtcToken(engine, generation));
        },
        onRequestToken: (_) {
          unawaited(_renewRoomRtcToken(engine, generation));
        },
        onAudioVolumeIndication: (_, speakers, __, ___) {
          if (!_audioAvailable ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          for (final speaker in speakers) {
            _markVoiceActivity(speaker);
          }
        },
        onUserMuteAudio: (_, remoteUid, muted) {
          if (!_audioAvailable ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          if (muted) {
            _rtcMutedUids.add(remoteUid);
          } else {
            _rtcMutedUids.remove(remoteUid);
          }
          _voiceActivityRevision.value++;
          if (muted) _clearVoiceActivity(remoteUid);
        },
        onUserOffline: (_, remoteUid, __) {
          if (!_audioAvailable ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          _voiceActivityTimers.remove(remoteUid)?.cancel();
          _activeRtcUids.remove(remoteUid);
          _rtcMutedUids.remove(remoteUid);
          _voiceActivityRevision.value++;
        },
      ));
      await engine.enableLocalAudio(publisher);
      _ensureRtcCurrent(engine);
      await engine.muteLocalAudioStream(!publisher || _muted || _hostMuted);
      _ensureRtcCurrent(engine);
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: ChannelMediaOptions(
          clientRoleType: publisher
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: publisher,
          autoSubscribeAudio: true,
        ),
      );
      _ensureRtcCurrent(engine);
      if (_audioAvailable &&
          generation == _rtcGeneration &&
          identical(_engine, engine)) {
        setState(() {
          _publisher = publisher;
          _error = null;
        });
        _publishOverlaySnapshot(_room);
      }
      if (!_audioAvailable ||
          generation != _rtcGeneration ||
          !identical(_engine, engine)) {
        return;
      }
      await _setVoiceRoomAudioService(true, microphone: publisher);
      if (publisher) await _markPublicRtcReady();
    } on DioException catch (e) {
      if (!_audioAvailable) return;
      if (e.response?.statusCode == 423) {
        final password = await _requestRoomPassword();
        if (password != null && _audioAvailable) {
          _joinPassword = password;
          await _connectInternal(force: force);
        } else if (_audioAvailable) {
          setState(() {
            _rtcConnected = false;
            _error = '尚未进入语音房，点击重试并输入房间口令';
          });
        }
        return;
      }
      final message =
          (e.response?.data as Map?)?['message']?.toString() ?? '进入房间失败';
      if (mounted) setState(() => _error = message);
    } catch (error) {
      if (!_audioAvailable) return;
      await _releaseRtcEngine();
      if (_audioAvailable) {
        setState(() => _error = error is FormatException
            ? error.message.toString()
            : imFailureMessage(error, '语音服务连接失败'));
      }
    }
  }

  void _ensureRtcCurrent(RtcEngine engine) {
    if (!_audioAvailable || !identical(_engine, engine)) {
      throw StateError('Room audio connection superseded');
    }
  }

  Future<void> _applyJoinedAudioRoute(RtcEngine engine, int generation) async {
    try {
      if (!_audioAvailable ||
          generation != _rtcGeneration ||
          !identical(_engine, engine)) {
        return;
      }
      await engine.muteLocalAudioStream(!_publisher || _muted || _hostMuted);
      await engine.setEnableSpeakerphone(_speaker);
    } catch (_) {
      // The default speaker route is already configured before joining.
      // An unsupported route override must not disconnect the channel.
    }
  }

  Future<void> _configureRoomAudio(RtcEngine engine) async {
    _ensureRtcCurrent(engine);
    await engine.enableAudio();
    _ensureRtcCurrent(engine);
    await configureRtcSpeech(engine);
    _ensureRtcCurrent(engine);
    await engine.setDefaultAudioRouteToSpeakerphone(_speaker);
    _ensureRtcCurrent(engine);
    await engine.muteAllRemoteAudioStreams(false);
    _ensureRtcCurrent(engine);
    await engine.adjustPlaybackSignalVolume(100);
    _ensureRtcCurrent(engine);
    await engine.adjustRecordingSignalVolume(100);
    _ensureRtcCurrent(engine);
    await restoreRtcSpeechProcessing(engine);
    _ensureRtcCurrent(engine);
  }

  Future<void> _applyRoomPublisherRole(RtcEngine engine, bool publisher) async {
    _ensureRtcCurrent(engine);
    await engine.setClientRole(
      role: publisher
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
    );
    _ensureRtcCurrent(engine);
    await engine.enableLocalAudio(publisher);
    _ensureRtcCurrent(engine);
    await engine.updateChannelMediaOptions(ChannelMediaOptions(
      clientRoleType: publisher
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      publishMicrophoneTrack: publisher,
      autoSubscribeAudio: true,
    ));
    _ensureRtcCurrent(engine);
    await engine.muteLocalAudioStream(!publisher || _muted || _hostMuted);
    _ensureRtcCurrent(engine);
  }

  Future<void> _renewRoomRtcToken(
    RtcEngine engine,
    int generation,
  ) async {
    if (_tokenRenewInFlight ||
        !_audioAvailable ||
        generation != _rtcGeneration ||
        !identical(_engine, engine)) {
      return;
    }
    _tokenRenewInFlight = true;
    try {
      final data = await _messageScope.post(
        '/api/consultation/rooms/${widget.roomId}/join',
        data: <String, dynamic>{
          if (_joinPassword != null) 'password': _joinPassword,
          if (_room?['roomType'] == 'master' && _publisher)
            'deferredReady': true,
        },
      );
      final token = data['rtcToken']?.toString();
      if (token == null || token.isEmpty) throw const FormatException();
      if (_audioAvailable &&
          generation == _rtcGeneration &&
          identical(_engine, engine)) {
        await engine.renewToken(token);
        if (!_audioAvailable ||
            generation != _rtcGeneration ||
            !identical(_engine, engine)) {
          return;
        }
        final publisher = data['publisher'] == true;
        if (publisher != _publisher) {
          if (publisher) {
            // 上麦仍经过现有连接流程检查麦克风权限。
            await _connect(force: true);
          } else {
            // 付费会话到期后，续期的听众凭证也必须同步停采集和停发流。
            await _applyRoomPublisherRole(engine, false);
            if (!_audioAvailable ||
                generation != _rtcGeneration ||
                !identical(_engine, engine)) {
              return;
            }
            setState(() {
              _publisher = false;
              _publicRtcReadySent = false;
            });
            await _setVoiceRoomAudioService(true, microphone: false);
            if (!_audioAvailable ||
                generation != _rtcGeneration ||
                !identical(_engine, engine)) {
              return;
            }
            _clearVoiceActivity(_localRtcUid);
            _publishOverlaySnapshot(_room);
          }
        }
      }
    } catch (_) {
      if (_audioAvailable && generation == _rtcGeneration) {
        setState(() => _error = '语音凭证续期失败，正在重新连接…');
        await _connect(force: true);
      }
    } finally {
      _tokenRenewInFlight = false;
    }
  }

  Future<void> _markPublicRtcReady() async {
    if (!_audioAvailable ||
        _publicRtcReadySent ||
        !_publisher ||
        !_rtcConnected ||
        _room?['roomType'] != 'master') {
      return;
    }
    final session = _room?['mySession'];
    final sessionId = session is Map ? (session['id'] as num?)?.toInt() : null;
    if (sessionId == null) return;
    _publicRtcReadySent = true;
    final generation = _rtcGeneration;
    try {
      await _messageScope.post('/api/consultation/sessions/$sessionId/ready');
      if (_audioAvailable && generation == _rtcGeneration) {
        unawaited(_refresh());
      }
    } catch (_) {
      if (_audioAvailable && generation == _rtcGeneration) {
        _publicRtcReadySent = false;
        setState(() => _error = '连麦状态同步失败，正在自动重试');
      }
    }
  }

  Future<void> _disposeEngine(RtcEngine? engine) async {
    await releaseRtcEngine(engine);
  }

  Future<void> _releaseRtcEngine() async {
    final engine = _engine;
    _engine = null;
    _rtcGeneration += 1;
    for (final timer in _voiceActivityTimers.values) {
      timer.cancel();
    }
    _voiceActivityTimers.clear();
    _activeRtcUids.clear();
    _rtcMutedUids.clear();
    if (mounted) _voiceActivityRevision.value++;
    _localRtcUid = null;
    _rtcConnected = false;
    _publicRtcReadySent = false;
    // 先同步清理旧连接状态；不能等release完成后覆盖期间新建的RTC状态。
    final stoppingService = _setVoiceRoomAudioService(false);
    await _disposeEngine(engine);
    await stoppingService;
  }

  Future<void> _setVoiceRoomAudioService(
    bool active, {
    bool microphone = false,
  }) async {
    if (active && !_audioAvailable) return;
    final testUpdater = widget.audioServiceUpdater;
    if (testUpdater != null) {
      if (!active && !_mayStopAudioService) return;
      await testUpdater(active, microphone);
      return;
    }
    await CallBackgroundAudio.update(
        'room:${widget.roomId}:${identityHashCode(this)}', active,
        title: _room?['title']?.toString() ?? '语音房进行中', microphone: microphone);
  }

  Future<void> _recoverRtcAfterResume() async {
    if (_resumeInFlight || !_available) return;
    _resumeInFlight = true;
    try {
      final fresh = await _refresh();
      if (!fresh ||
          !_available ||
          !['live', 'paused'].contains(_room?['status'])) {
        return;
      }
      unawaited(_connectRoomEvents());
      if (!_audioAvailable) return;
      final engine = _engine;
      if (engine == null) {
        await _connect();
        return;
      }
      await engine.enableAudio();
      _ensureRtcCurrent(engine);
      await engine.setEnableSpeakerphone(_speaker);
      _ensureRtcCurrent(engine);
      await engine.muteAllRemoteAudioStreams(false);
      _ensureRtcCurrent(engine);
      await engine.setClientRole(
        role: _publisher
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
      );
      _ensureRtcCurrent(engine);
      await engine.enableLocalAudio(_publisher);
      _ensureRtcCurrent(engine);
      await engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          clientRoleType: _publisher
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: _publisher,
          autoSubscribeAudio: true,
        ),
      );
      _ensureRtcCurrent(engine);
      if (_publisher) {
        await engine.muteLocalAudioStream(_muted || _hostMuted);
      }
      await _setVoiceRoomAudioService(true, microphone: _publisher);
    } catch (_) {
      // 前后台切换时音频设备可能被系统短暂占用，回退一次受控重连。
      if (_audioAvailable) {
        await _connect(force: true);
      }
    } finally {
      _resumeInFlight = false;
    }
  }

  Future<String?> _requestRoomPassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入房间口令'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          maxLength: 16,
          decoration: const InputDecoration(
            hintText: '请输入4—16位房间口令',
            counterText: '',
          ),
          onSubmitted: (text) => Navigator.pop(dialogContext, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('进入'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.isEmpty == true ? null : value;
  }

  Future<void> _openRoomProfile() async {
    if (!_available) return;
    final room = _room;
    if (room == null) return;
    final updated = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VoiceRoomProfilePage(
        room: Map<String, dynamic>.from(room),
        isOwner: _myMember(room)?['role'] == 'owner',
      ),
    ));
    if (updated != null) await _refresh();
  }

  void _openMemberProfile(Map<String, dynamic> member) {
    if (!_available) return;
    final userId = (member['userId'] as num?)?.toInt();
    if (userId == null) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserProfilePage(userId: userId)));
  }

  Future<void> _handleMemberTap(Map<String, dynamic> member) async {
    if (member['isMe'] == true) {
      await _showSelfMicActions();
      return;
    }
    final canManage = ['owner', 'admin'].contains(_myMember(_room)?['role']);
    if (canManage && member['role'] != 'owner') {
      await _showMicActions(member);
      return;
    }
    _openMemberProfile(member);
  }

  Future<void> _suspendRoomAudio() async {
    if (!_available) return;
    _audioSuspended = true;
    await _releaseRtcEngine();
    if (mounted) setState(() => _publisher = false);
  }

  Future<void> _resumeRoomAudio() async {
    if (!_available) return;
    _audioSuspended = false;
    if (_engine != null) return;
    final fresh = await _refresh();
    if (fresh &&
        _audioAvailable &&
        ['live', 'paused'].contains(_room?['status'])) {
      await _connect();
      unawaited(_connectRoomEvents());
    }
  }

  Future<void> _openPrivateLine(Map<String, dynamic> room) async {
    final session = room['mySession'];
    if (session is Map &&
        session['mode'] == 'public_mic' &&
        const {'accepted', 'connecting', 'active'}
            .contains(session['status'])) {
      showAppToast(context, '您正在公开咨询中，请下麦后点击。');
      return;
    }
    final owner = room['owner'];
    final teacherId = (room['ownerId'] as num?)?.toInt();
    if (owner is! Map || teacherId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PrivateLineCheckoutPage(
        teacherId: teacherId,
        roomId: widget.roomId,
        mode: 'private_mic',
        teacher: {
          ...Map<String, dynamic>.from(owner),
          'serviceStatus': 'online',
          'privatePricePerMin': owner['privatePricePerMin'] ?? 0,
          'serviceNotice': '私人专线仅双方可听，双方音频接通后开始计费。',
        },
      ),
    ));
  }

  Future<void> _toggleFollowOwner() async {
    final room = _room;
    final owner = room?['owner'];
    final ownerId = (room?['ownerId'] as num?)?.toInt();
    if (owner is! Map ||
        ownerId == null ||
        owner['isSelf'] == true ||
        _followBusy) {
      return;
    }
    final previous = owner['following'] == true;
    setState(() {
      _followBusy = true;
      owner['following'] = !previous;
    });
    try {
      final response =
          await apiClient.post('/api/community/user/$ownerId/follow');
      final data = (response.data as Map?)?['data'];
      if (mounted && data is Map) {
        setState(() {
          owner['following'] = data['following'] == true;
          owner['mutualFollow'] = data['mutual'] == true;
        });
      }
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() => owner['following'] = previous);
      showAppToast(context, '关注操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _inviteFriends() async {
    final room = _room;
    if (room == null) return;
    await showVoiceRoomInviteSheet(context, room);
  }

  Future<void> _openRoomCharts() async {
    final room = _room;
    if (room == null) return;
    final members = room['members'] is List
        ? (room['members'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    await showRoomChartSheet(context, roomId: widget.roomId, members: members);
  }

  Future<bool> _updateRoomSettings(Map<String, dynamic> values) async {
    if (!_beginAction('room_settings')) return false;
    try {
      await apiClient.put(
        '/api/consultation/rooms/${widget.roomId}',
        data: values,
      );
      await _refresh();
      return true;
    } on DioException catch (error) {
      if (mounted) {
        showAppToast(
          context,
          (error.response?.data as Map?)?['message']?.toString() ?? '房间设置保存失败',
        );
      }
      return false;
    } finally {
      _endAction('room_settings');
    }
  }

  Future<void> _showOwnerManagement({
    required List<Map<String, dynamic>> queue,
    required List<Map<String, dynamic>> privateRequests,
    required List<Map<String, dynamic>> members,
  }) async {
    final room = _room;
    if (room == null || _myMember(room)?['role'] != 'owner') return;
    final master = room['roomType'] == 'master';
    var allMuted = room['allMuted'] == true;
    var autonomousMic = room['autonomousMic'] == true;
    var switchBusy = false;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7FAFA),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const VoiceRoomSheetHandle(),
              const SizedBox(height: 16),
              const Text('管理中心',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              const Text('用户管理',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  _RoomActionButton(
                    icon: Icons.headset_mic_rounded,
                    label: '连麦管理',
                    badge: queue.length + privateRequests.length,
                    onTap: () => Navigator.pop(sheetContext, 'mic'),
                  ),
                  _RoomActionButton(
                    icon: Icons.people_alt_outlined,
                    label: '成员管理',
                    onTap: () => Navigator.pop(sheetContext, 'members'),
                  ),
                  _RoomActionButton(
                    icon: Icons.tune_rounded,
                    label: '成员权限',
                    onTap: () => Navigator.pop(sheetContext, 'restrictions'),
                  ),
                  _RoomActionButton(
                    icon: Icons.grid_view_rounded,
                    label: '房间命盘',
                    onTap: () => Navigator.pop(sheetContext, 'charts'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile.adaptive(
                  value: allMuted,
                  activeTrackColor: AppColors.primary,
                  title: const Text('全员禁言',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  subtitle:
                      Text(allMuted ? '已开启，所有麦上成员同步闭麦' : '已关闭，成员可按麦位状态发言'),
                  secondary: Icon(
                    allMuted
                        ? Icons.volume_off_rounded
                        : Icons.graphic_eq_rounded,
                    color:
                        allMuted ? const Color(0xFFD78178) : AppColors.primary,
                  ),
                  onChanged: switchBusy
                      ? null
                      : (value) async {
                          setSheetState(() {
                            switchBusy = true;
                            allMuted = value;
                          });
                          final saved =
                              await _updateRoomSettings({'allMuted': value});
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            switchBusy = false;
                            if (!saved) allMuted = !value;
                          });
                        },
                ),
              ),
              const SizedBox(height: 22),
              const Text('房间管理',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  _RoomActionButton(
                    icon: Icons.edit_note_rounded,
                    label: '房间资料',
                    onTap: () => Navigator.pop(sheetContext, 'profile'),
                  ),
                  _RoomActionButton(
                    icon: Icons.auto_awesome_rounded,
                    label: '房间等级',
                    onTap: () => Navigator.pop(sheetContext, 'level'),
                  ),
                  _RoomActionButton(
                    icon: Icons.ios_share_rounded,
                    label: '邀请分享',
                    onTap: () => Navigator.pop(sheetContext, 'invite'),
                  ),
                  _RoomActionButton(
                    icon: Icons.wallpaper_rounded,
                    label: '氛围背景',
                    onTap: () => Navigator.pop(sheetContext, 'profile'),
                  ),
                  _RoomActionButton(
                    icon: Icons.insights_outlined,
                    label: '本场数据',
                    onTap: () => Navigator.pop(sheetContext, 'summary'),
                  ),
                  _RoomActionButton(
                    icon: Icons.power_settings_new_rounded,
                    label: '关闭房间',
                    danger: true,
                    onTap: () => Navigator.pop(sheetContext, 'close'),
                  ),
                ],
              ),
              if (!master) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SwitchListTile.adaptive(
                    value: autonomousMic,
                    activeTrackColor: AppColors.primary,
                    secondary: const Icon(Icons.mic_external_on_outlined,
                        color: AppColors.primary),
                    title: const Text('自主上麦',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle:
                        Text(autonomousMic ? '成员申请后可直接获得麦位' : '成员上麦需要房主同意'),
                    onChanged: switchBusy
                        ? null
                        : (value) async {
                            setSheetState(() {
                              switchBusy = true;
                              autonomousMic = value;
                            });
                            final saved = await _updateRoomSettings(
                                {'autonomousMic': value});
                            if (!sheetContext.mounted) return;
                            setSheetState(() {
                              switchBusy = false;
                              if (!saved) autonomousMic = !value;
                            });
                          },
                  ),
                ),
              ],
              if (master) ...[
                const SizedBox(height: 18),
                const _PaidSeatProtectionNotice(),
              ],
            ]),
          ),
        ),
      ),
    );
    if (!_available || action == null) return;
    switch (action) {
      case 'mic':
        await _showPendingRequests(
            queue: queue, privateRequests: privateRequests);
        break;
      case 'members':
        await _showMembers(members);
        break;
      case 'charts':
        await _openRoomCharts();
        break;
      case 'restrictions':
        await _showMembers(members);
        break;
      case 'all_mute_on':
        await _updateRoomSettings({'allMuted': true});
        break;
      case 'all_mute_off':
        await _updateRoomSettings({'allMuted': false});
        break;
      case 'events':
        if (_messageScrollController.hasClients) {
          _messageScrollController.animateTo(0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut);
        }
        break;
      case 'profile':
        await _openRoomProfile();
        break;
      case 'autonomous_on':
        await _updateRoomSettings({'autonomousMic': true});
        break;
      case 'autonomous_off':
        await _updateRoomSettings({'autonomousMic': false});
        break;
      case 'level':
        await _showRoomLevel();
        break;
      case 'invite':
        await _inviteFriends();
        break;
      case 'summary':
        await _showRoomSummary();
        break;
      case 'close':
        await _leave();
        break;
    }
  }

  Future<void> _showMemberMore(List<Map<String, dynamic>> members) async {
    final room = _room;
    if (room == null) return;
    final owner = room['owner'] is Map ? room['owner'] as Map : const {};
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('在线成员'),
            onTap: () => Navigator.pop(sheetContext, 'members'),
          ),
          if (owner['isSelf'] != true)
            ListTile(
              leading: const ReferenceActionGlyph(
                type: ReferenceActionIconType.follow,
                size: 24,
              ),
              title: Text(owner['following'] == true ? '取消关注房主' : '关注房主'),
              onTap: () => Navigator.pop(sheetContext, 'follow'),
            ),
          ListTile(
            leading: Icon(
                _speaker ? Icons.hearing_rounded : Icons.volume_up_rounded),
            title: Text(_speaker ? '切换到听筒' : '打开扬声器'),
            onTap: () => Navigator.pop(sheetContext, 'speaker'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('房间资料与举报'),
            onTap: () => Navigator.pop(sheetContext, 'profile'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('邀请好友'),
            onTap: () => Navigator.pop(sheetContext, 'invite'),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: const Text('房间命盘'),
            subtitle: const Text('查看案例、专业盘面和发布范围'),
            onTap: () => Navigator.pop(sheetContext, 'charts'),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFE65F5A)),
            title: const Text('退出房间'),
            onTap: () => Navigator.pop(sheetContext, 'leave'),
          ),
        ])),
      ),
    );
    if (!_available || action == null) return;
    if (action == 'members') await _showMembers(members);
    if (action == 'follow') await _toggleFollowOwner();
    if (action == 'speaker') {
      await _engine?.setEnableSpeakerphone(!_speaker);
      if (mounted) setState(() => _speaker = !_speaker);
    }
    if (action == 'profile') await _openRoomProfile();
    if (action == 'invite') await _inviteFriends();
    if (action == 'charts') await _openRoomCharts();
    if (action == 'leave') await _leave();
  }

  Future<void> _showMembers(List<Map<String, dynamic>> members) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FBFA),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .76),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          const VoiceRoomSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
            child: Row(children: [
              Text('在线成员 ${members.length}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final member = members[index];
                final avatar = member['avatarUrl']?.toString() ?? '';
                final me = member['isMe'] == true;
                final canManage =
                    ['owner', 'admin'].contains(_myMember(_room)?['role']) &&
                        member['role'] != 'owner';
                final relation = member['mutualFollow'] == true
                    ? '互相关注'
                    : member['following'] == true
                        ? '已关注'
                        : member['followsMe'] == true
                            ? '关注了你'
                            : '';
                return ListTile(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (canManage && !me) {
                      unawaited(_showMicActions(member));
                    } else {
                      unawaited(_handleMemberTap(member));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundImage:
                        avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  title: Row(children: [
                    Flexible(
                        child: Text(member['nickname']?.toString() ?? '用户')),
                    if (member['role'] == 'owner') const _MemberTag('房主'),
                    if (member['role'] == 'admin') const _MemberTag('管理员'),
                    if (relation.isNotEmpty)
                      _MemberTag(relation, relation: true),
                  ]),
                  subtitle: Text(member['micStatus'] == 'speaking'
                      ? '正在麦上发言'
                      : member['micStatus'] == 'queued'
                          ? '正在等待上麦'
                          : '正在房间内'),
                  trailing: me
                      ? const Text('我',
                          style: TextStyle(color: AppColors.textHint))
                      : PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'profile') {
                              _openMemberProfile(member);
                            }
                            if (value == 'follow') {
                              await _toggleFollowMember(member);
                            }
                            if (value == 'greet') await _greetMember(member);
                            if (value == 'manage') {
                              await _showMicActions(member);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'profile', child: Text('查看主页')),
                            PopupMenuItem(
                              value: 'follow',
                              child: Text(
                                  member['following'] == true ? '取消关注' : '关注'),
                            ),
                            if (member['following'] == true ||
                                member['mutualFollow'] == true)
                              const PopupMenuItem(
                                  value: 'greet', child: Text('打个招呼')),
                            if (['owner', 'admin']
                                .contains(_myMember(_room)?['role']))
                              const PopupMenuItem(
                                  value: 'manage', child: Text('成员管理')),
                          ],
                        ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _toggleFollowMember(Map<String, dynamic> member) async {
    final userId = (member['userId'] as num?)?.toInt();
    if (userId == null) return;
    try {
      final response =
          await apiClient.post('/api/community/user/$userId/follow');
      final data = (response.data as Map?)?['data'];
      if (data is Map && mounted) {
        member['following'] = data['following'] == true;
        member['mutualFollow'] = data['mutual'] == true;
        showAppToast(context, data['following'] == true ? '已关注' : '已取消关注');
      }
      await _refresh();
    } on DioException catch (_) {
      if (mounted) showAppToast(context, '关注操作失败，请稍后重试');
    }
  }

  Future<void> _greetMember(Map<String, dynamic> member) async {
    final name = member['nickname']?.toString() ?? '朋友';
    _messageController.text = '@$name 你好呀，很高兴在这里遇见你';
    await _sendMessage();
  }

  Future<void> _showRoomLevel() async {
    final level = _room?['roomLevel'];
    final data =
        level is Map ? Map<String, dynamic>.from(level) : <String, dynamic>{};
    final value = (data['level'] as num?)?.toInt() ?? 1;
    final progress = (data['progress'] as num?)?.toDouble() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            VoiceRoomLevelBadge(level: value),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFD1A653),
              backgroundColor: const Color(0xFFF1E8D6),
            ),
            const SizedBox(height: 10),
            Text('${data['exp'] ?? 0} / ${data['nextLevelExp'] ?? 0} 成长值'),
            const SizedBox(height: 12),
            const Text('真诚聊天、成员参与、上麦交流与建立新关系都会带来成长；付费金额不会直接提高房间等级。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Future<void> _showRoomSummary() async {
    try {
      final response = await apiClient
          .get('/api/consultation/rooms/${widget.roomId}/summary');
      final raw = (response.data as Map?)?['data'];
      if (!mounted || raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('本场房间数据',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _SummaryMetric('累计来访', '${data['visitors'] ?? 0}人'),
                _SummaryMetric('峰值在线', '${data['peakOnlineCount'] ?? 0}人'),
                _SummaryMetric('聊天消息', '${data['messageCount'] ?? 0}条'),
                _SummaryMetric('新关系', '${data['newRelationships'] ?? 0}次'),
                if ((_room?['roomType'] == 'master'))
                  _SummaryMetric('付费连线', '${data['paidCalls'] ?? 0}次'),
              ]),
            ]),
          ),
        ),
      );
    } on DioException catch (_) {
      if (mounted) showAppToast(context, '本场数据加载失败');
    }
  }

  Future<void> _managePrivateRequest(
      Map<String, dynamic> request, String action) async {
    final sessionId = (request['sessionId'] as num?)?.toInt();
    if (sessionId == null) return;
    try {
      await apiClient.post('/api/consultation/sessions/$sessionId/$action');
      if (action == 'accept') {
        if (!mounted) return;
        await ConsultationCallOverlay.instance.open(sessionId);
      } else {
        await _refresh();
      }
    } on DioException catch (e) {
      if (mounted) {
        showAppToast(
          context,
          (e.response?.data as Map?)?['message']?.toString() ?? '操作失败',
        );
      }
    }
  }

  Future<void> _showMicActions(Map<String, dynamic> member) async {
    if (!['owner', 'admin'].contains(_myMember(_room)?['role']) ||
        member['role'] == 'owner') {
      return;
    }
    final userId = (member['userId'] as num?)?.toInt();
    if (userId == null) return;
    final master = _room?['roomType'] == 'master';
    var current = Map<String, dynamic>.from(member);
    var actionBusy = false;
    var removed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FBFA),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          Future<void> perform(String action) async {
            if (actionBusy) return;
            if (['kick', 'blacklist', 'transfer_owner'].contains(action)) {
              final confirmed = await showDialog<bool>(
                    context: sheetContext,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(action == 'transfer_owner'
                          ? '确认移交房主？'
                          : action == 'blacklist'
                              ? '确认加入黑名单？'
                              : '确认移出房间？'),
                      content: Text(action == 'transfer_owner'
                          ? '移交后对方成为新房主，你将成为管理员。'
                          : action == 'blacklist'
                              ? '该用户将被立即移出，并且不能再次进入本房间。'
                              : '该用户会立即退出本房间。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  ) ==
                  true;
              if (!confirmed || !sheetContext.mounted) return;
            }
            setSheetState(() => actionBusy = true);
            final success = await _manageMic(userId, action);
            if (!sheetContext.mounted) return;
            if (success) {
              final latest = _findManagedMember(userId);
              if (latest != null) current = latest;
              if (action == 'kick' || action == 'blacklist') removed = true;
            }
            setSheetState(() => actionBusy = false);
          }

          final myRole = _myMember(_room)?['role'];
          final canStillManage =
              ['owner', 'admin'].contains(myRole) && current['role'] != 'owner';
          final onMic = ['speaker', 'admin'].contains(current['role']) &&
              ['accepted', 'speaking'].contains(current['micStatus']);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const VoiceRoomSheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 2, 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${current['nickname'] ?? '成员'} · 成员管理',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
                if (actionBusy) const LinearProgressIndicator(minHeight: 2),
                if (removed)
                  const ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('该用户已移出房间'),
                    subtitle: Text('管理框会保留，点击右上角关闭'),
                  )
                else if (canStillManage) ...[
                  if (current['roomBanned'] == true)
                    ListTile(
                      leading: const Icon(Icons.lock_open_rounded),
                      title: const Text('解除房间黑名单'),
                      subtitle: const Text('解除后用户可以再次进入本房间'),
                      onTap: actionBusy ? null : () => perform('unblacklist'),
                    )
                  else ...[
                    if (onMic)
                      ListTile(
                        leading: const Icon(Icons.call_end_rounded,
                            color: Colors.redAccent),
                        title: Text(master
                            ? '结束 ${current['nickname'] ?? '该用户'} 的付费连线'
                            : '抱 ${current['nickname'] ?? '该用户'} 下麦'),
                        subtitle: Text(
                            master ? '会立即停止计费并按实际有效时长结算' : '用户回到听众席，可再次申请上麦'),
                        onTap: actionBusy ? null : () => perform('finish'),
                      ),
                    if (!onMic && !master)
                      ListTile(
                        leading: const Icon(Icons.record_voice_over_outlined),
                        title: Text('邀请 ${current['nickname'] ?? '该用户'} 上麦'),
                        subtitle: const Text('对方点击麦克风后开始讲话'),
                        onTap: actionBusy ? null : () => perform('invite'),
                      ),
                    if (onMic)
                      ListTile(
                        leading: Icon(current['muted'] == true
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded),
                        title: Text(current['muted'] == true ? '解除禁麦' : '禁麦'),
                        subtitle: current['muted'] == true
                            ? const Text('解除后仍需用户自己点击开麦')
                            : null,
                        onTap: actionBusy
                            ? null
                            : () => perform(
                                current['muted'] == true ? 'unmute' : 'mute'),
                      ),
                    if (myRole == 'owner')
                      ListTile(
                        leading:
                            const Icon(Icons.admin_panel_settings_outlined),
                        title: Text(
                            current['role'] == 'admin' ? '取消管理员' : '设为管理员'),
                        onTap: actionBusy
                            ? null
                            : () => perform(current['role'] == 'admin'
                                ? 'remove_admin'
                                : 'set_admin'),
                      ),
                    SwitchListTile.adaptive(
                      value: current['chatMuted'] != true,
                      title: const Text('允许发送消息'),
                      subtitle: Text(
                          current['chatMuted'] == true ? '当前已禁言' : '当前可正常聊天'),
                      secondary: const Icon(Icons.chat_bubble_outline_rounded),
                      activeTrackColor: AppColors.primary,
                      onChanged: actionBusy
                          ? null
                          : (enabled) =>
                              perform(enabled ? 'unban_chat' : 'ban_chat'),
                    ),
                    SwitchListTile.adaptive(
                      value: current['micBlocked'] != true,
                      title: const Text('允许申请上麦'),
                      subtitle: Text(current['micBlocked'] == true
                          ? '当前禁止上麦'
                          : '当前拥有上麦权限'),
                      secondary: const Icon(Icons.mic_none_rounded),
                      activeTrackColor: AppColors.primary,
                      onChanged: actionBusy
                          ? null
                          : (enabled) =>
                              perform(enabled ? 'unblock_mic' : 'block_mic'),
                    ),
                    if (myRole == 'owner' && !master)
                      ListTile(
                        leading: const Icon(Icons.swap_horiz_rounded),
                        title: const Text('移交房主'),
                        subtitle: const Text('移交后你将成为管理员'),
                        onTap:
                            actionBusy ? null : () => perform('transfer_owner'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.person_remove_outlined,
                          color: Colors.redAccent),
                      title: const Text('移出房间'),
                      onTap: actionBusy ? null : () => perform('kick'),
                    ),
                    if (myRole == 'owner')
                      ListTile(
                        leading: const Icon(Icons.block_rounded,
                            color: Colors.redAccent),
                        title: const Text('加入本房间黑名单'),
                        subtitle: const Text('移出后将无法再次进入本房间'),
                        onTap: actionBusy ? null : () => perform('blacklist'),
                      ),
                  ],
                ],
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: const Text('查看主页'),
                  onTap: () => _openMemberProfile(current),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Map<String, dynamic>? _findManagedMember(int userId) {
    final room = _room;
    if (room == null) return null;
    for (final key in const ['members', 'restrictedMembers']) {
      final values = room[key];
      if (values is! List) continue;
      for (final value in values.whereType<Map>()) {
        if ((value['userId'] as num?)?.toInt() == userId) {
          return Map<String, dynamic>.from(value);
        }
      }
    }
    return null;
  }

  Future<void> _showSelfMicActions() async {
    final master = _room?['roomType'] == 'master';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(_muted ? Icons.mic_rounded : Icons.mic_off_rounded),
            title: Text(_muted ? '打开麦克风' : '关闭麦克风'),
            onTap: () => Navigator.pop(sheetContext, 'mute'),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_arrow_down_rounded),
            title: Text(master ? '结束付费连线并下麦' : '下麦'),
            subtitle: master ? const Text('下麦后立即停止计费并按实际时长结算') : null,
            onTap: () => Navigator.pop(sheetContext, 'leave_mic'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('分享房间'),
            onTap: () => Navigator.pop(sheetContext, 'share'),
          ),
        ]),
      ),
    );
    if (!_available || action == null) return;
    if (action == 'mute') await _toggleLocalMute();
    if (action == 'share') await _inviteFriends();
    if (action == 'leave_mic') {
      if (!mounted) return;
      final confirmed = !master ||
          await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('结束付费连线？'),
                  content: const Text('确认后立即停止计费，并按音频实际接通时长结算。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('继续连线')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('结束并下麦')),
                  ],
                ),
              ) ==
              true;
      if (!confirmed) return;
      try {
        await apiClient
            .post('/api/consultation/rooms/${widget.roomId}/mic/cancel');
        await _refresh();
      } on DioException catch (_) {
        if (mounted) showAppToast(context, '下麦失败，请稍后重试');
      }
    }
  }

  Future<void> _applyMic() async {
    if (!_beginAction('apply_mic')) return;
    try {
      final me = _myMember(_room);
      if (me?['micStatus'] == 'queued') {
        await apiClient
            .post('/api/consultation/rooms/${widget.roomId}/mic/cancel');
        await _refresh();
        return;
      }
      final paymentMethod =
          _room?['roomType'] == 'master' ? await _confirmPublicMic() : null;
      if (_room?['roomType'] == 'master' && paymentMethod == null) return;
      try {
        final response = await apiClient
            .post('/api/consultation/rooms/${widget.roomId}/mic/apply', data: {
          if (paymentMethod != null) 'paymentMethod': paymentMethod,
          if (paymentMethod != null) 'agreementAccepted': true,
        });
        final data = (response.data as Map?)?['data'];
        if (data is Map && data['direct'] == true) {
          if (mounted) showAppToast(context, '麦位已为你打开，请确认麦克风权限');
          await _startMic();
          return;
        }
        if (mounted) {
          showAppToast(context,
              '已进入麦序${data is Map && data['queueNo'] != null ? '，当前第${data['queueNo']}位' : ''}');
        }
        await _refresh();
      } on DioException catch (e) {
        final message =
            (e.response?.data as Map?)?['message']?.toString() ?? '申请上麦失败';
        if (!mounted) return;
        if (e.response?.statusCode == 402) {
          final go = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                      title: const Text('玄遇币余额不足'),
                      content: const Text('名师公开连麦需要先冻结前几分钟费用。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('去充值'))
                      ]));
          if (go == true && mounted) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RechargePage()));
          }
        } else if (e.response?.statusCode == 428) {
          final enabled = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
                builder: (_) => const ConsultationPaymentSettingPage()),
          );
          if (enabled == true && mounted) showAppToast(context, '已开通，请重新申请连麦');
        } else {
          showAppToast(context, message);
        }
      }
    } finally {
      _endAction('apply_mic');
    }
  }

  Future<String?> _confirmPublicMic() async {
    var coinEnabled = false;
    var alipayAvailable = false;
    var alipaySigned = false;
    var paymentMethod = 'coin';
    var balance = 0.0;
    var freezeMinutes = 5;
    var notice = '';
    try {
      final responses = await Future.wait([
        apiClient.get('/api/consultation/payment-setting'),
        apiClient.get('/api/auth/wallet/balance'),
        apiClient.get('/api/consultation/config'),
      ]);
      final setting = (responses[0].data as Map?)?['data'];
      final wallet = (responses[1].data as Map?)?['data'];
      final config = (responses[2].data as Map?)?['data'];
      coinEnabled = setting is Map &&
          (setting['coinEnabled'] == true || setting['enabled'] == true);
      final alipay = setting is Map ? setting['alipay'] : null;
      alipayAvailable = alipay is Map && alipay['available'] == true;
      alipaySigned = alipay is Map && alipay['signed'] == true;
      paymentMethod = !usesAppleIap &&
              setting is Map &&
              setting['preferredMethod'] == 'alipay' &&
              alipaySigned
          ? 'alipay'
          : 'coin';
      balance =
          double.tryParse('${wallet is Map ? wallet['balance'] : 0}') ?? 0;
      freezeMinutes = config is Map
          ? ((config['freezeMinutes'] as num?)?.toInt() ?? 5).clamp(5, 60)
          : 5;
      notice = config is Map ? config['publicMicNotice']?.toString() ?? '' : '';
    } on DioException catch (_) {}
    if (!mounted) return null;
    final price = (_room?['pricePerMin'] as num?)?.toDouble() ?? 0;
    final requiredAmount = price * freezeMinutes;
    var agreed = false;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F5EE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('申请公开连麦', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 13),
                  _PaidMicRow(
                      label: '计费标准',
                      value:
                          '${price.toStringAsFixed(2)}${paymentMethod == 'coin' ? '玄遇币' : '元'}/分钟'),
                  const _PaidMicRow(label: '开始计费', value: '老师接受且音频接通后'),
                  const _PaidMicRow(label: '排队等待', value: '免费'),
                  const _PaidMicRow(label: '沟通范围', value: '房间内所有听众可听'),
                  const SizedBox(height: 14),
                  Text('结算方式', style: AppTextStyles.titleSmall),
                  if (!usesAppleIap)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          paymentMethod == 'alipay'
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: const Color(0xFF1677FF)),
                      onTap: () =>
                          setSheetState(() => paymentMethod = 'alipay'),
                      title: const Text('支付宝免密支付'),
                      subtitle: Text(!alipayAvailable
                          ? '商户能力开通后可用'
                          : alipaySigned
                              ? '已签约，结束后按实际时长扣款'
                              : '尚未签约'),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        paymentMethod == 'coin'
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: const Color(0xFFB6812D)),
                    onTap: () => setSheetState(() => paymentMethod = 'coin'),
                    title: const Text('玄遇币支付'),
                    subtitle: Text(
                        '余额${balance.toStringAsFixed(2)}，连接需${requiredAmount.toStringAsFixed(2)}（至少$freezeMinutes分钟）'),
                  ),
                  const Divider(height: 24),
                  Text('连麦须知', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 8),
                  ...((notice.isNotEmpty
                              ? notice.split('\n')
                              : const [
                                  '公开连麦内容可被房间内所有用户听见。',
                                  '排队、等待老师接受和连接期间不收费。',
                                  '请勿透露隐私信息或进行线下交易。',
                                ])
                          .where((line) => line.trim().isNotEmpty))
                      .map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• ${line.trim()}',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.5)),
                          )),
                  CheckboxListTile(
                    value: agreed,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setSheetState(() => agreed = value == true),
                    title: const Text('我已阅读并同意连麦须知与计费规则，授权按有效时长扣费'),
                  ),
                  FilledButton(
                    onPressed: agreed
                        ? () => Navigator.pop(sheetContext, paymentMethod)
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.primaryDark,
                    ),
                    child: const Text('确认进入麦序'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return null;
    if (selected == 'alipay' && !alipaySigned) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ConsultationPaymentSettingPage()));
      return null;
    }
    if (selected == 'coin' && !coinEnabled) {
      try {
        await apiClient.put('/api/consultation/payment-setting', data: {
          'coinEnabled': true,
          'enabled': true,
          'preferredMethod': 'coin',
          'agreed': true,
        });
      } on DioException {
        if (mounted) showAppToast(context, '扣费授权未成功，请重试');
        return null;
      }
    }
    if (!mounted) return null;
    if (selected == 'coin' && balance < requiredAmount) {
      final recharge = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('玄遇币余额不足'),
              content: Text(
                  '公开连麦需至少准备$freezeMinutes分钟费用，共${requiredAmount.toStringAsFixed(2)}玄遇币。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('去充值')),
              ],
            ),
          ) ==
          true;
      if (recharge && mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const RechargePage()));
      }
      return null;
    }
    return usesAppleIap ? 'coin' : selected;
  }

  Future<bool> _manageMic(int userId, String action) async {
    final key = 'manage_mic:$userId:$action';
    if (!_beginAction(key)) return false;
    try {
      await apiClient
          .post('/api/consultation/rooms/${widget.roomId}/mic/$userId/$action');
      await _refresh();
      return true;
    } on DioException catch (e) {
      if (mounted) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '操作失败');
      }
      return false;
    } finally {
      _endAction(key);
    }
  }

  Future<void> _sendMessage() async {
    if (!_messageScope.current) {
      if (mounted) showAppToast(context, imSessionChangedMessage);
      return;
    }
    if (!_beginAction('send_message')) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      _endAction('send_message');
      return;
    }
    try {
      await _messageScope.post(
          '/api/consultation/rooms/${widget.roomId}/messages',
          data: {'content': text});
      if (!mounted || !_messageScope.current) return;
      if (_messageController.text.trim() == text) {
        _messageController.clear();
      }
      await _refresh();
    } catch (e) {
      if (mounted && _messageScope.current) {
        showAppToast(context, imFailureMessage(e, '发送失败'));
      }
    } finally {
      _endAction('send_message');
    }
  }

  Future<void> _recallMessage(Map<String, dynamic> message) async {
    if (!_messageScope.current) return;
    final id = (message['id'] as num?)?.toInt();
    if (id == null || !canRecallRoomMessage(message)) {
      if (mounted) showAppToast(context, '消息超过两分钟，不能撤回');
      return;
    }
    final action = 'recall_message:$id';
    if (!_beginAction(action)) return;
    try {
      final data = await _messageScope
          .post('/api/consultation/rooms/${widget.roomId}/messages/$id/revoke');
      if (!mounted || !_messageScope.current) return;
      if (data['revoked'] != true || data['id'] != id) {
        throw const ImWorkflowFailure('撤回结果待确认，请稍后刷新');
      }
      setState(() {
        final updated = mergeRoomMessages(_messages, const [], {id});
        _messages
          ..clear()
          ..addAll(updated);
      });
      await _refresh();
    } catch (error) {
      if (mounted && _messageScope.current) {
        showAppToast(context, imFailureMessage(error, '撤回失败，请稍后重试'));
      }
    } finally {
      _endAction(action);
    }
  }

  bool _backPrompt = false;
  Future<void> _confirmBack() async {
    if (_backPrompt || _leaving || !mounted) return;
    _backPrompt = true;
    try {
      final end = await showCallBackChoice(context);
      if (!mounted || _leaving) return;
      if (end == true) {
        await _leave();
      } else if (end == false) {
        minimizeCallToHome(_overlayController.minimize);
      }
    } finally {
      _backPrompt = false;
    }
  }

  Future<void> _leave() async {
    if (!_current || _leaving) return;
    _leaving = true;
    final me = _myMember(_room);
    final isOwner = me?['role'] == 'owner';
    final mySession = _room?['mySession'];
    final paidActive = mySession is Map && mySession['status'] == 'active';
    var endRoom = false;
    if (isOwner) {
      endRoom = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                      title: const Text('结束房间？'),
                      content: const Text('房主离开将结束本场语音房。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('继续直播')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('结束'))
                      ])) ==
          true;
      if (!endRoom) {
        _leaving = false;
        return;
      }
    } else if (paidActive) {
      final endLine = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('结束公开连线并退出？'),
              content: const Text('结束后将立即停止计费，并按实际有效时长结算。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续连线'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('结束并退出'),
                ),
              ],
            ),
          ) ==
          true;
      if (!endLine) {
        _leaving = false;
        return;
      }
    }
    if (!_current) return;
    try {
      await _messageScope.post('/api/consultation/rooms/${widget.roomId}/leave',
          data: {'endRoom': endRoom});
    } catch (error) {
      _leaving = false;
      if (mounted && _available) {
        showAppToast(context,
            imFailureMessage(error, isOwner ? '结束直播失败，请重试' : '退出房间失败，请重试'));
      }
      return;
    }
    if (!_current) return;
    await _exitBecause('已退出房间');
  }

  Future<void> _showPendingRequests({
    required List<Map<String, dynamic>> queue,
    required List<Map<String, dynamic>> privateRequests,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FBFA),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .68,
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('待处理申请',
                  style: TextStyle(
                      color: Color(0xFF173F3B),
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${privateRequests.length + queue.length}人',
                  style:
                      const TextStyle(color: Color(0xFF78908D), fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final request in privateRequests)
                    _PendingRequestTile(
                      title: '私人专线 · ${request['nickname'] ?? '用户'}',
                      subtitle: '仅双方可听，接受后进入私人通话',
                      onAccept: () {
                        Navigator.pop(sheetContext);
                        _managePrivateRequest(request, 'accept');
                      },
                      onReject: () {
                        Navigator.pop(sheetContext);
                        _managePrivateRequest(request, 'reject');
                      },
                    ),
                  for (final request in queue)
                    _PendingRequestTile(
                      title:
                          '${request['queueNo'] ?? '-'}号 · ${request['nickname'] ?? '用户'}',
                      subtitle: '公开连线，接受后用户主动开麦',
                      onAccept: () {
                        Navigator.pop(sheetContext);
                        _manageMic(
                            (request['userId'] as num).toInt(), 'accept');
                      },
                      onReject: () {
                        Navigator.pop(sheetContext);
                        _manageMic(
                            (request['userId'] as num).toInt(), 'reject');
                      },
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_room == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _closeOwnedOverlay,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: Center(
            child: ImWorkflowRetry(
          message: _error ?? '房间不存在',
          onRetry: _available
              ? () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  unawaited(_enter());
                }
              : null,
        )),
      );
    }
    final room = _room!;
    final me = _myMember(room);
    final isOwner = me?['role'] == 'owner';
    final canManageRoom = ['owner', 'admin'].contains(me?['role']);
    final master = room['roomType'] == 'master';
    final members = room['members'] is List
        ? (room['members'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final restrictedMembers = room['restrictedMembers'] is List
        ? (room['restrictedMembers'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final managedMembers = <Map<String, dynamic>>[...members];
    for (final restricted in restrictedMembers) {
      if (managedMembers
          .every((member) => member['userId'] != restricted['userId'])) {
        managedMembers.add(restricted);
      }
    }
    final queue = room['queue'] is List
        ? (room['queue'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final privateRequests = room['privateRequests'] is List
        ? (room['privateRequests'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final micUsers = members.where((m) {
      if (m['role'] == 'owner') return true;
      return ['admin', 'speaker'].contains(m['role']) &&
          m['micStatus'] == 'speaking';
    }).toList();
    final publicCallers = micUsers
        .where((member) => member['role'] != 'owner')
        .toList(growable: false);
    final currentPublicCaller =
        publicCallers.isEmpty ? null : publicCallers.first;
    final audienceUsers = members
        .where((member) => member['role'] == 'listener')
        .toList(growable: false);
    final mySession = room['mySession'] is Map
        ? Map<String, dynamic>.from(room['mySession'])
        : null;
    final owner = room['owner'] is Map ? room['owner'] as Map : const {};
    final roomLevelRaw = room['roomLevel'];
    final roomLevel =
        roomLevelRaw is Map ? (roomLevelRaw['level'] as num?)?.toInt() ?? 1 : 1;
    final autonomousMic = !master && room['autonomousMic'] == true;
    final privatePrice = (owner['privatePricePerMin'] as num?)?.toDouble() ?? 0;
    final publicPrice = (room['pricePerMin'] as num?)?.toDouble() ?? 0;
    final micStatus = me?['micStatus']?.toString() ?? 'none';
    final micActionLabel = _publisher
        ? (_muted ? '开麦' : '闭麦')
        : micStatus == 'accepted'
            ? '开始讲话'
            : micStatus == 'queued'
                ? '取消申请'
                : master
                    ? '申请连线'
                    : autonomousMic
                        ? '直接上麦'
                        : '申请上麦';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaving) unawaited(_confirmBack());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFF071F36),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_backgroundImage != null)
              Image(
                image: _backgroundImage!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) =>
                    _AuroraRoomBackground(master: master),
              )
            else
              _AuroraRoomBackground(master: master),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: master
                      ? const [
                          Color(0x4D0A3D48),
                          Color(0x730B3844),
                          Color(0xC9072029),
                        ]
                      : const [
                          Color(0x45515EB9),
                          Color(0x6E635FBD),
                          Color(0xC720254F),
                        ],
                  stops: const [0, .52, 1],
                ),
              ),
            ),
            SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 5, 10, 8),
                  child: Row(children: [
                    InkWell(
                      onTap: _openRoomProfile,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: master
                                  ? const Color(0xFFE4C57E)
                                  : const Color(0xFF8BE9E1),
                              width: 1.5),
                        ),
                        child: CircleAvatar(
                          backgroundColor: const Color(0x6632BFB8),
                          backgroundImage:
                              (owner['avatarUrl']?.toString() ?? '').isNotEmpty
                                  ? NetworkImage(owner['avatarUrl'].toString())
                                  : null,
                          child: (owner['avatarUrl']?.toString() ?? '').isEmpty
                              ? const Icon(Icons.person_rounded,
                                  color: Colors.white, size: 22)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(room['title']?.toString() ?? '语音房',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                              child: Text(
                                owner['nickname']?.toString() ??
                                    (master ? '认证老师' : '房主'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                            ),
                            if (master) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.verified_rounded,
                                  size: 12, color: Color(0xFFE4C57E)),
                            ],
                            const SizedBox(width: 5),
                            Text(
                              '· ${room['onlineCount'] ?? 0}人${'在线'}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 10),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _openRoomCharts,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.grid_view_rounded, size: 19),
                      label: const Text(
                        '命盘',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _overlayController.minimize,
                      tooltip: '缩小房间',
                      color: Colors.white,
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 22),
                    ),
                    IconButton(
                      tooltip: isOwner ? '管理中心' : '更多',
                      color: Colors.white,
                      onPressed: () => isOwner
                          ? _showOwnerManagement(
                              queue: queue,
                              privateRequests: privateRequests,
                              members: managedMembers,
                            )
                          : _showMemberMore(members),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ]),
                ),
                if (_error != null || !_rtcConnected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: InkWell(
                      onTap: _rtcConnecting
                          ? null
                          : () => unawaited(_connect(force: true)),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xB34A3340),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(children: [
                          if (_rtcConnecting)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.8, color: Colors.white70),
                            )
                          else
                            const Icon(Icons.wifi_tethering_error_rounded,
                                size: 16, color: Color(0xFFFFC2B8)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _error ?? '正在连接语音…',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5),
                            ),
                          ),
                          if (!_rtcConnecting)
                            const Text('重试',
                                style: TextStyle(
                                    color: Color(0xFF8BE9E1),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                  child: Row(children: [
                    InkWell(
                      onTap: _showRoomLevel,
                      borderRadius: BorderRadius.circular(20),
                      child:
                          VoiceRoomLevelBadge(level: roomLevel, compact: true),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x4D102E4A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department_rounded,
                            size: 13, color: Color(0xFFFFB572)),
                        Text(' ${room['heatScore'] ?? 0}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 9.5)),
                      ]),
                    ),
                    if (autonomousMic) ...[
                      const Spacer(),
                      const _RoomStatusPill(
                        icon: Icons.mic_external_on_rounded,
                        label: '自主上麦已开启',
                      ),
                    ],
                  ]),
                ),
                if ((room['notice']?.toString() ?? '').isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 2, 14, 9),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x45102E4A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.campaign_outlined,
                          size: 17, color: Color(0xFF6BE5DD)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(room['notice'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.4)),
                      ),
                    ]),
                  ),
                if (mySession != null &&
                    ['waiting', 'accepted', 'connecting', 'active']
                        .contains(mySession['status']))
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xA3126274),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x661AC4C4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.timelapse_rounded,
                          size: 17, color: Color(0xFF6BE5DD)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mySession['status'] == 'active'
                              ? mySession['paymentMethod'] == 'alipay'
                                  ? '公开连麦中 · ${mySession['billedSeconds'] ?? 0}秒 · 支付宝结束后结算'
                                  : '公开连麦中 · ${mySession['billedSeconds'] ?? 0}秒 · 余额约${mySession['walletRemainingSeconds'] ?? mySession['remainingSeconds'] ?? 0}秒'
                              : '已进入麦序，老师接受前不收费',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ]),
                  ),
                if (mySession != null &&
                    mySession['status'] == 'active' &&
                    mySession['paymentMethod'] != 'alipay' &&
                    mySession['viewerRole'] != 'teacher' &&
                    ((mySession['walletRemainingSeconds'] ??
                                mySession['remainingSeconds']) as num? ??
                            121) <=
                        120)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                    child: Row(children: [
                      const Expanded(
                        child: Text('余额不足两分钟，请及时充值',
                            style: TextStyle(color: Color(0xFFFFD6A0))),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RechargePage()),
                        ),
                        child: const Text('充值'),
                      ),
                    ]),
                  ),
                if (canManageRoom &&
                    (privateRequests.isNotEmpty || queue.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                    child: InkWell(
                      onTap: () => _showPendingRequests(
                        queue: queue,
                        privateRequests: privateRequests,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x73102E4A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x441AC4C4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.notifications_active_outlined,
                              size: 17, color: Color(0xFF8BE9E1)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '${queue.length}人申请公开连线 · ${privateRequests.length}人申请私人专线',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5),
                            ),
                          ),
                          const Text('处理',
                              style: TextStyle(
                                  color: Color(0xFFE4C57E),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                          const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFFE4C57E), size: 18),
                        ]),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 3),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(children: [
                              if (master)
                                _MasterRoomStage(
                                  owner: owner,
                                  currentCaller: currentPublicCaller,
                                  audienceCount: audienceUsers.length,
                                  queueCount: queue.length,
                                  onOwnerTap: _openRoomProfile,
                                  onCallerTap: currentPublicCaller == null
                                      ? null
                                      : () =>
                                          _handleMemberTap(currentPublicCaller),
                                )
                              else
                                _FreeRoomFocus(
                                  title: room['category']?.toString() ?? '聊天交流',
                                  onlineCount: members.length,
                                  autonomousMic: autonomousMic,
                                ),
                              const SizedBox(height: 9),
                              Expanded(
                                child: ListView.builder(
                                  controller: _messageScrollController,
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 8, 2, 12),
                                  itemCount: _messages.length + 1,
                                  itemBuilder: (_, i) {
                                    if (i == 0) {
                                      return const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: Text(
                                          '系统：请文明交流，勿线下交易；咨询内容未经授权不得传播。',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                              height: 1.5),
                                        ),
                                      );
                                    }
                                    final message = _messages[i - 1];
                                    if (message['type'] == 'mic_request') {
                                      final requestUserId =
                                          (message['userId'] as num?)?.toInt();
                                      final active = requestUserId != null &&
                                          queue.any((item) =>
                                              item['userId'] == requestUserId &&
                                              item['micStatus'] == 'queued');
                                      return _MicRequestMessage(
                                        message: message,
                                        active: active,
                                        canManage: canManageRoom,
                                        onAccept: requestUserId == null
                                            ? null
                                            : () => _manageMic(
                                                requestUserId, 'accept'),
                                        onReject: requestUserId == null
                                            ? null
                                            : () => _manageMic(
                                                requestUserId, 'reject'),
                                      );
                                    }
                                    if (['relationship', 'mic_event']
                                        .contains(message['type'])) {
                                      final payload = _decodeVirtualPayload(
                                              message['content']) ??
                                          const <String, dynamic>{};
                                      return _RoomEventMessage(
                                        type: message['type']?.toString() ??
                                            'system',
                                        payload: payload,
                                        nickname:
                                            message['nickname']?.toString() ??
                                                '用户',
                                      );
                                    }
                                    if (['gift', 'entry']
                                        .contains(message['type'])) {
                                      final payload = _decodeVirtualPayload(
                                              message['content']) ??
                                          const <String, dynamic>{};
                                      final isGift = message['type'] == 'gift';
                                      Map<String, dynamic>? entryMember;
                                      if (!isGift) {
                                        final entryUserId =
                                            (message['userId'] as num?)
                                                ?.toInt();
                                        for (final candidate in members) {
                                          if ((candidate['userId'] as num?)
                                                  ?.toInt() ==
                                              entryUserId) {
                                            entryMember = candidate;
                                            break;
                                          }
                                        }
                                      }
                                      final canGreet = entryMember != null &&
                                          entryMember['isMe'] != true &&
                                          (entryMember['following'] == true ||
                                              entryMember['mutualFollow'] ==
                                                  true);
                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 11, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isGift
                                              ? const Color(0x554F3A73)
                                              : const Color(0x551AC4C4),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                          border: Border.all(
                                              color: isGift
                                                  ? const Color(0x668E74C9)
                                                  : const Color(0x551AC4C4)),
                                        ),
                                        child: Row(children: [
                                          Icon(
                                            isGift
                                                ? Icons.redeem_rounded
                                                : Icons.auto_awesome_rounded,
                                            color: isGift
                                                ? const Color(0xFFE2C37E)
                                                : const Color(0xFF6BE5DD),
                                            size: 17,
                                          ),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Text(
                                              isGift
                                                  ? '${message['nickname'] ?? '用户'} 送出 ${payload['giftName'] ?? '一份心意'} ×${payload['quantity'] ?? 1}'
                                                  : (payload['effectName']
                                                              ?.toString()
                                                              .isNotEmpty ==
                                                          true
                                                      ? '${payload['nickname'] ?? message['nickname'] ?? '一位旅人'} 携「${payload['effectName']}」来到房间'
                                                      : '${payload['nickname'] ?? message['nickname'] ?? '一位用户'} 进入了房间'),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  height: 1.35),
                                            ),
                                          ),
                                          if (canGreet)
                                            TextButton(
                                              onPressed: () =>
                                                  _greetMember(entryMember!),
                                              child: const Text('打招呼'),
                                            ),
                                        ]),
                                      );
                                    }
                                    return RoomChatMessage(
                                      key: ValueKey(
                                          'room-message-${message['id']}'),
                                      message: message,
                                      onRecall: _messageScope.current &&
                                              canRecallRoomMessage(message)
                                          ? () => _recallMessage(message)
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 4),
                          ValueListenableBuilder<int>(
                            valueListenable: _voiceActivityRevision,
                            builder: (_, __, ___) => _RightMicRail(
                              members: micUsers,
                              master: master,
                              queueCount: queue.length,
                              activeRtcUids: _activeRtcUids,
                              rtcMutedUids: _rtcMutedUids,
                              localMuted: _muted || _hostMuted,
                              onInvite: _inviteFriends,
                              onMemberTap: _handleMemberTap,
                              onMemberLongPress: _showMicActions,
                            ),
                          ),
                        ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: '说点什么…',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xB3102E4A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    IconButton.filled(
                      onPressed: _sendMessage,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 20),
                    ),
                    const SizedBox(width: 5),
                    IconButton.filled(
                      tooltip: '赠送礼物',
                      onPressed: _openGiftSheet,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFD8B36C),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.redeem_rounded, size: 20),
                    ),
                    if (master && !isOwner) ...[
                      const SizedBox(width: 5),
                      IconButton.filled(
                        tooltip: '私人专线',
                        onPressed: () => _openPrivateLine(room),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFE1C273),
                          foregroundColor: const Color(0xFF173F3B),
                        ),
                        icon: const Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                    ],
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 47,
                      height: 47,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: micStatus == 'queued'
                              ? null
                              : AppColors.primaryGradient,
                          color: micStatus == 'queued'
                              ? const Color(0xFFD78178)
                              : null,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x551AC4C4),
                              blurRadius: 13,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: IconButton(
                          tooltip: micActionLabel,
                          color: Colors.white,
                          onPressed: () {
                            if (_publisher) {
                              _toggleLocalMute();
                            } else if (micStatus == 'accepted') {
                              _startMic();
                            } else if (micStatus == 'speaking') {
                              setState(() => _micPermissionBlocked = false);
                              _connect(force: true);
                            } else {
                              _applyMic();
                            }
                          },
                          icon: Icon(
                            _publisher
                                ? (_muted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded)
                                : micStatus == 'queued'
                                    ? Icons.close_rounded
                                    : micStatus == 'accepted'
                                        ? Icons.mic_rounded
                                        : Icons.mic_off_rounded,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                if (master)
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x52102E4A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.call_outlined,
                          size: 16, color: Color(0xFF6BE5DD)),
                      const SizedBox(width: 7),
                      const Text('公开连线 ',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 10.5)),
                      Text('${publicPrice.toStringAsFixed(2)}币/分钟',
                          style: const TextStyle(
                              color: Color(0xFFFFB572),
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child:
                            Text('·', style: TextStyle(color: Colors.white38)),
                      ),
                      const Icon(Icons.lock_outline_rounded,
                          size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      const Text('私人专线 ',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 10.5)),
                      Expanded(
                        child: Text(
                          '${privatePrice.toStringAsFixed(2)}币/分钟',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFFFB572),
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
            if (_virtualEffects.active case final effect?)
              Positioned.fill(
                child: VirtualGiftEffect(
                  key: ObjectKey(effect),
                  payload: effect,
                  onCompleted: () => _completeVirtualEffect(effect),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuroraRoomBackground extends StatelessWidget {
  const _AuroraRoomBackground({required this.master});
  final bool master;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: master
                    ? const [
                        Color(0xFF0B4450),
                        Color(0xFF126B72),
                        Color(0xFF1D596D),
                        Color(0xFF09242E),
                      ]
                    : const [
                        Color(0xFF435DAA),
                        Color(0xFF756BC4),
                        Color(0xFF4E78BA),
                        Color(0xFF20264E),
                      ],
              ),
            ),
          ),
          const Positioned(
            left: -110,
            top: 70,
            child: _RoomGlow(size: 310, color: Color(0x886BE5DD)),
          ),
          const Positioned(
            right: -120,
            top: 250,
            child: _RoomGlow(size: 340, color: Color(0x668DA4F1)),
          ),
          const Positioned(
            left: 40,
            bottom: -170,
            child: _RoomGlow(size: 390, color: Color(0x551AC4C4)),
          ),
        ],
      );
}

class _MasterRoomStage extends StatelessWidget {
  const _MasterRoomStage({
    required this.owner,
    required this.currentCaller,
    required this.audienceCount,
    required this.queueCount,
    required this.onOwnerTap,
    this.onCallerTap,
  });

  final Map owner;
  final Map<String, dynamic>? currentCaller;
  final int audienceCount;
  final int queueCount;
  final VoidCallback onOwnerTap;
  final VoidCallback? onCallerTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 126,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: Column(children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StagePerson(
                    avatar: owner['avatarUrl']?.toString() ?? '',
                    name: owner['nickname']?.toString() ?? '认证老师',
                    label: '老师讲解中',
                    prominent: true,
                    verified: true,
                    onTap: onOwnerTap,
                  ),
                  Container(
                    width: 42,
                    height: 1,
                    margin: const EdgeInsets.fromLTRB(5, 0, 5, 25),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color(0x008BE9E1),
                        Color(0xFF8BE9E1),
                        Color(0x008BE9E1),
                      ]),
                    ),
                  ),
                  currentCaller == null
                      ? const _EmptyCaller()
                      : _StagePerson(
                          avatar: currentCaller!['avatarUrl']?.toString() ?? '',
                          name:
                              currentCaller!['nickname']?.toString() ?? '连线用户',
                          label: '当前公开连线',
                          onTap: onCallerTap,
                        ),
                ],
              ),
            ),
            Text(
              '$audienceCount人在线  ·  ${currentCaller == null ? 0 : 1}人连线  ·  $queueCount人排队',
              style: const TextStyle(
                color: Color(0xFF8BE9E1),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      );
}

class _StagePerson extends StatelessWidget {
  const _StagePerson({
    required this.avatar,
    required this.name,
    required this.label,
    required this.onTap,
    this.prominent = false,
    this.verified = false,
  });

  final String avatar;
  final String name;
  final String label;
  final VoidCallback? onTap;
  final bool prominent;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final radius = prominent ? 35.0 : 28.0;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: prominent ? 92 : 80,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: prominent
                    ? const Color(0xFF1AC4C4)
                    : const Color(0xFFE4C57E),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x551AC4C4), blurRadius: 16),
              ],
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: const Color(0x6632BFB8),
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? const Icon(Icons.person_rounded,
                      color: Colors.white, size: 26)
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700)),
            ),
            if (verified) ...[
              const SizedBox(width: 2),
              const Icon(Icons.verified_rounded,
                  size: 10, color: Color(0xFFE4C57E)),
            ],
          ]),
          Text(label,
              maxLines: 1,
              style: const TextStyle(color: Colors.white54, fontSize: 8)),
        ]),
      ),
    );
  }
}

class _EmptyCaller extends StatelessWidget {
  const _EmptyCaller();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 80,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Color(0x331AC4C4),
            child:
                Icon(Icons.mic_none_rounded, color: Colors.white54, size: 25),
          ),
          SizedBox(height: 5),
          Text('等待连线', style: TextStyle(color: Colors.white54, fontSize: 9)),
        ]),
      );
}

class _PendingRequestTile extends StatelessWidget {
  const _PendingRequestTile({
    required this.title,
    required this.subtitle,
    required this.onAccept,
    required this.onReject,
  });

  final String title;
  final String subtitle;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0x3382DAD4)),
        ),
        child: Row(children: [
          const CircleAvatar(
            radius: 19,
            backgroundColor: Color(0xFFE5F7F5),
            child:
                Icon(Icons.person_rounded, color: Color(0xFF176762), size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF173F3B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF78908D), fontSize: 9.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: '拒绝',
            onPressed: onReject,
            icon: const Icon(Icons.close_rounded,
                color: Color(0xFFB6635F), size: 21),
          ),
          IconButton(
            tooltip: '同意',
            onPressed: onAccept,
            icon: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF1AC4C4), size: 23),
          ),
        ]),
      );
}

class _RoomGlow extends StatelessWidget {
  const _RoomGlow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}

class _PaidMicRow extends StatelessWidget {
  const _PaidMicRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value,
              style: AppTextStyles.bodySmall
                  .copyWith(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _MicRequestMessage extends StatelessWidget {
  const _MicRequestMessage({
    required this.message,
    required this.active,
    required this.canManage,
    this.onAccept,
    this.onReject,
  });

  final Map<String, dynamic> message;
  final bool active;
  final bool canManage;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0x441AC4C4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x661AC4C4)),
        ),
        child: Row(children: [
          const Icon(Icons.mic_none_rounded,
              size: 17, color: Color(0xFF6BE5DD)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${message['nickname'] ?? '用户'} 申请上麦',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          if (canManage && active) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '同意',
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle_rounded,
                  color: AppColors.primary, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '拒绝',
              onPressed: onReject,
              icon: const Icon(Icons.cancel_rounded,
                  color: Color(0xFFD78178), size: 20),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                active ? '等待处理' : '已处理',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ),
        ]),
      );
}

class _FreeRoomFocus extends StatelessWidget {
  const _FreeRoomFocus({
    required this.title,
    required this.onlineCount,
    required this.autonomousMic,
  });

  final String title;
  final int onlineCount;
  final bool autonomousMic;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 62,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 5),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const VoiceActivityBars(size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
            const Spacer(),
            Text(
              '$onlineCount人正在聊天 · ${autonomousMic ? '可自主上麦' : '申请后上麦'}',
              style: const TextStyle(color: Colors.white60, fontSize: 9.5),
            ),
          ]),
        ),
      );
}

class _RightMicRail extends StatelessWidget {
  const _RightMicRail({
    required this.members,
    required this.master,
    required this.queueCount,
    required this.activeRtcUids,
    required this.rtcMutedUids,
    required this.localMuted,
    required this.onInvite,
    required this.onMemberTap,
    required this.onMemberLongPress,
  });

  final List<Map<String, dynamic>> members;
  final bool master;
  final int queueCount;
  final Set<int> activeRtcUids;
  final Set<int> rtcMutedUids;
  final bool localMuted;
  final VoidCallback onInvite;
  final ValueChanged<Map<String, dynamic>> onMemberTap;
  final ValueChanged<Map<String, dynamic>> onMemberLongPress;

  @override
  Widget build(BuildContext context) {
    final bySeat = <int, Map<String, dynamic>>{};
    final pending = <Map<String, dynamic>>[];
    for (final member in members) {
      final seat = (member['seatNo'] as num?)?.toInt();
      if (seat != null && seat >= 1) {
        bySeat[seat] = member;
      } else {
        pending.add(member);
      }
    }
    for (var seat = 1; pending.isNotEmpty; seat++) {
      if (bySeat.containsKey(seat)) continue;
      bySeat[seat] = pending.removeAt(0);
    }
    final visibleSeats = bySeat.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return SizedBox(
      width: 82,
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final entry in visibleSeats)
            _RailSeat(
              seatNo: entry.key,
              member: entry.value,
              ownerLabel: master ? '名\n师' : '群\n主',
              speaking: activeRtcUids.contains(_voiceRoomRtcUid(entry.value)),
              closed: entry.value['muted'] == true ||
                  rtcMutedUids.contains(_voiceRoomRtcUid(entry.value)) ||
                  (entry.value['isMe'] == true && localMuted),
              onTap: () => onMemberTap(entry.value),
              onLongPress: () => onMemberLongPress(entry.value),
            ),
          if (queueCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x75101C2D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('麦序 $queueCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x75101C2D),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('${visibleSeats.length}人',
                style: const TextStyle(color: Colors.white, fontSize: 9)),
          ),
          InkWell(
            onTap: onInvite,
            borderRadius: BorderRadius.circular(26),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x80101828),
                ),
                child: const Icon(Icons.reply_rounded,
                    textDirection: TextDirection.rtl,
                    color: Colors.white,
                    size: 28),
              ),
              const SizedBox(height: 3),
              const Text('邀请',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      height: 1.2,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 5),
        ]),
      ),
    );
  }
}

class _RailSeat extends StatelessWidget {
  const _RailSeat({
    required this.seatNo,
    required this.member,
    required this.ownerLabel,
    required this.speaking,
    required this.closed,
    this.onTap,
    this.onLongPress,
  });

  final int seatNo;
  final Map<String, dynamic> member;
  final String ownerLabel;
  final bool speaking;
  final bool closed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final avatar = member['avatarUrl']?.toString() ?? '';
    final owner = member['role'] == 'owner';
    final active = speaking && !closed;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? owner
                          ? const Color(0xFF54E6D8)
                          : Colors.white
                      : Colors.white24,
                  width: active ? 2.4 : 1.2,
                ),
              ),
              child: CircleAvatar(
                backgroundColor: const Color(0x4DFFFFFF),
                backgroundImage:
                    avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isNotEmpty
                    ? null
                    : const Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
              ),
            ),
            if (owner)
              const Positioned(
                left: -3,
                top: -6,
                child: Icon(Icons.workspace_premium_rounded,
                    size: 17, color: Color(0xFFFFCA58)),
              ),
          ]),
          const SizedBox(width: 4),
          Container(
            width: 28,
            height: 48,
            decoration: BoxDecoration(
              color: owner ? const Color(0xE51AC4C4) : const Color(0x73101828),
              borderRadius: BorderRadius.circular(15),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                  owner
                      ? ownerLabel
                      : member['role'] == 'admin'
                          ? '管理\n员'
                          : '$seatNo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      height: 1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              if (active)
                const VoiceActivityBars(size: 13, color: Colors.white)
              else
                Icon(
                  closed ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  color: closed ? Colors.white : Colors.white70,
                  size: 14,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoomActionButton extends StatelessWidget {
  const _RoomActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 66) / 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: danger ? const Color(0xFFFFECEB) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x0D102D2A), blurRadius: 10),
                  ],
                ),
                child: Icon(icon,
                    color: danger
                        ? const Color(0xFFE65F5A)
                        : const Color(0xFF315A56)),
              ),
              if (badge > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5F65),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text('$badge',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 8)),
                  ),
                ),
            ]),
            const SizedBox(height: 7),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: danger
                      ? const Color(0xFFE65F5A)
                      : const Color(0xFF455E5B),
                  fontSize: 10,
                )),
          ]),
        ),
      );
}

class _PaidSeatProtectionNotice extends StatelessWidget {
  const _PaidSeatProtectionNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E8),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Row(children: [
          Icon(Icons.verified_user_outlined,
              color: Color(0xFFB6812D), size: 20),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '名师付费麦位受平台保护：排队免费，双方音频接通后才开始计费，自主上麦不会作用于该麦位。',
              style: TextStyle(
                  color: Color(0xFF806238), fontSize: 10.5, height: 1.45),
            ),
          ),
        ]),
      );
}

class _RoomStatusPill extends StatelessWidget {
  const _RoomStatusPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x4D1AC4C4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF8BE9E1)),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 8.5)),
        ]),
      );
}

class _MemberTag extends StatelessWidget {
  const _MemberTag(this.label, {this.relation = false});
  final String label;
  final bool relation;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 5),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: relation ? const Color(0xFFE6FAF7) : const Color(0xFFF1ECF7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              color: relation ? AppColors.primaryDark : const Color(0xFF806A9D),
              fontSize: 8.5,
            )),
      );
}

class _RoomEventMessage extends StatelessWidget {
  const _RoomEventMessage({
    required this.type,
    required this.payload,
    required this.nickname,
  });

  final String type;
  final Map<String, dynamic> payload;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    String text;
    IconData? icon;
    if (type == 'relationship') {
      text = voiceRoomRelationshipText(payload);
      icon = payload['action'] == 'mutual'
          ? Icons.favorite_rounded
          : Icons.person_add_alt_1_rounded;
    } else {
      text = switch (payload['action']) {
        'direct_accepted' => '$nickname 已自主上麦',
        'started' => '$nickname 开始发言',
        'accept' => '$nickname 的上麦申请已通过',
        'invite' => '$nickname 已收到上麦邀请',
        'reject' => '$nickname 的上麦申请未通过',
        'finish' => '$nickname 已下麦',
        'self_finish' => '$nickname 已主动下麦',
        'mute' => '$nickname 已被闭麦',
        'unmute' => '$nickname 已解除闭麦',
        'kick' => '$nickname 已离开房间',
        'blacklist' => '$nickname 已被移出房间',
        'block_mic' => '$nickname 已被限制上麦',
        'unblock_mic' => '$nickname 已恢复上麦权限',
        _ => '$nickname 的麦位状态已更新',
      };
      icon = null;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x554F3A73),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: const Color(0xFFFFB5CF), size: 16),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 10.5)),
        ),
      ]),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: (MediaQuery.sizeOf(context).width - 50) / 2,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8F7),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ]),
      );
}
