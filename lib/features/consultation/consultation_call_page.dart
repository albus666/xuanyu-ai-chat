import '../../core/utils/call_background_audio.dart';
import '../../shared/widgets/call_back_choice.dart';
import 'package:get/get.dart';
import '../profile/recharge_page.dart';
import '../../core/utils/rtc_speech.dart';
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/agora_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import 'room_chart_sheet.dart';
import 'voice_room_overlay_controller.dart';

class ConsultationCallPage extends StatefulWidget {
  const ConsultationCallPage({
    super.key,
    required this.sessionId,
    this.onMinimize,
    this.onBackReady,
    this.onClose,
    this.onSessionEnded,
    this.onEndReady,
    this.engineFactory,
    this.requestMicrophone,
  });
  final int sessionId;
  final VoidCallback? onMinimize;
  final void Function(Future<void> Function() callback)? onBackReady;
  final VoidCallback? onClose;
  final VoidCallback? onSessionEnded;
  final void Function(Future<void> Function(BuildContext) callback)? onEndReady;
  final RtcEngine Function()? engineFactory;
  final Future<bool> Function()? requestMicrophone;

  @override
  State<ConsultationCallPage> createState() => _ConsultationCallPageState();
}

class _ConsultationCallPageState extends State<ConsultationCallPage>
    with WidgetsBindingObserver {
  final _scope = ApiSessionScope();
  Map<String, dynamic>? _session;
  RtcEngine? _engine;
  Future<void> _rtcCleanup = Future<void>.value();
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _rtcConnectTimer;
  bool _preparing = true;
  bool _joiningRtc = false;
  bool _joinedRtc = false;
  bool _remoteJoined = false;
  bool _remoteAudioPlaying = false;
  bool _rtcReadySent = false;
  bool _rtcBlocked = false;
  bool _roomAudioSuspended = false;
  bool _muted = false;
  bool _speaker = false;
  bool _ending = false;
  bool _lowBalanceAlerted = false;
  bool _endRequested = false;
  bool _peerHungUp = false;
  bool _refreshInFlight = false;
  bool _refreshPending = false;
  bool _tokenRenewInFlight = false;
  bool _resumeInFlight = false;
  int _rtcGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.onBackReady?.call(_confirmBack);
    widget.onEndReady?.call(_confirmEnd);
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_accountChanged);
    _prepareCall();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _prepareCall() async {
    try {
      _roomAudioSuspended =
          await VoiceRoomOverlayController.instance.suspendAudio();
      if (!mounted || !_scope.current) {
        if (_roomAudioSuspended && _scope.current) {
          await VoiceRoomOverlayController.instance.resumeAudio();
        }
        _roomAudioSuspended = false;
        return;
      }
    } catch (_) {
      if (mounted && _scope.current) setState(() => _error = '语音初始化失败，请重试');
    } finally {
      _preparing = false;
    }
    if (mounted && _scope.current) await _refresh();
  }

  void _accountChanged() {
    if (!mounted || _scope.current) return;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rtcConnectTimer?.cancel();
    _roomAudioSuspended = false;
    _rtcGeneration++;
    final engine = _engine;
    _engine = null;
    setState(() {
      _session = null;
      _joinedRtc = false;
      _joiningRtc = false;
      _error = apiSessionChangedMessage;
    });
    unawaited(_disposeAudioResources(engine, false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_accountChanged);
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rtcConnectTimer?.cancel();
    _rtcGeneration += 1;
    final engine = _engine;
    _engine = null;
    unawaited(_disposeAudioResources(engine, _roomAudioSuspended));
    super.dispose();
  }

  Future<void> _disposeAudioResources(
    RtcEngine? engine,
    bool resumeRoom,
  ) async {
    await _rtcCleanup;
    await releaseRtcEngine(engine);
    await _setCallAudioService(false);
    if (resumeRoom && _scope.current) {
      await VoiceRoomOverlayController.instance.resumeAudio();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverRtcAfterResume());
    }
  }

  Future<void> _refresh() async {
    if ((!mounted || !_scope.current) || _ending || _preparing) return;
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }
    _refreshInFlight = true;
    try {
      final response =
          await _scope.get('/api/consultation/sessions/${widget.sessionId}');
      final raw = (response.data as Map?)?['data'];
      if (raw is! Map || (!mounted || !_scope.current)) return;
      var next = Map<String, dynamic>.from(raw);
      if (next['viewerRole'] == 'teacher' &&
          next['isCaller'] != true &&
          next['status'] == 'waiting') {
        final accepted = await _scope
            .post('/api/consultation/sessions/${widget.sessionId}/accept');
        if (!mounted || !_scope.current) return;
        final data = (accepted.data as Map?)?['data'];
        if (data is Map) next = Map<String, dynamic>.from(data);
      }
      final firstLoad = _session == null;
      if (!_deepEquals(_session, next)) {
        setState(() {
          _session = next;
          if (firstLoad) _error = null;
        });
      }
      _checkLowBalance(next);
      final state = next['status']?.toString();
      if ((state == 'accepted' || state == 'connecting' || state == 'active') &&
          !_joinedRtc &&
          !_joiningRtc &&
          !_endRequested &&
          !_rtcBlocked) {
        await _joinRtc();
      }
      if (_joinedRtc && !_rtcReadySent && !endedState(state)) {
        await _markRtcReady();
      }
      if (state == 'ended' ||
          state == 'cancelled' ||
          state == 'rejected' ||
          state == 'refunded') {
        if (state == 'ended' &&
            !_endRequested &&
            const {'user_ended', 'peer_ended'}.contains(next['endReason'])) {
          _peerHungUp = true;
        }
        widget.onSessionEnded?.call();
        if ((mounted && _scope.current)) setState(() => _error = null);
        _pollTimer?.cancel();
        _heartbeatTimer?.cancel();
        _rtcConnectTimer?.cancel();
        await _releaseRtc();
      }
    } on ApiSessionChangedException {
      return;
    } on DioException catch (e) {
      if (mounted &&
          _scope.current &&
          const {403, 404, 410}.contains(e.response?.statusCode) &&
          widget.onClose != null) {
        widget.onClose!();
        return;
      }
      if ((mounted && _scope.current) && _session == null) {
        setState(() => _error =
            (e.response?.data as Map?)?['message']?.toString() ?? '咨询状态加载失败');
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshPending && (mounted && _scope.current) && !_ending) {
        _refreshPending = false;
        unawaited(_refresh());
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
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  bool endedState(String? state) =>
      const {'ended', 'cancelled', 'rejected', 'refunded'}.contains(state);

  Future<void> _joinRtc() async {
    if ((!mounted || !_scope.current) || _endRequested) return;
    if (_joiningRtc) return;
    _joiningRtc = true;
    try {
      if (_engine != null) {
        await _releaseRtc();
        if (!mounted || !_scope.current || _endRequested) return;
        _joiningRtc = true;
      }
      final granted = await (widget.requestMicrophone?.call() ??
          Permission.microphone.request().then((value) => value.isGranted));
      if ((!mounted || !_scope.current) || _endRequested) return;
      if (!granted) {
        throw const FormatException('需要麦克风权限才能语音咨询');
      }
      final response = await _scope
          .post('/api/consultation/sessions/${widget.sessionId}/join', data: {
        'deferredReady': true,
      });
      final data = (response.data as Map?)?['data'];
      if ((!mounted || !_scope.current) || _endRequested) return;
      if (data is! Map) throw const FormatException('语音参数不完整');
      final token = data['rtcToken']?.toString();
      final channel = data['channel']?.toString();
      final uid = (data['uid'] as num?)?.toInt() ?? 0;
      if (token == null || channel == null || uid <= 0) {
        throw const FormatException('语音参数不完整');
      }
      final engine = widget.engineFactory?.call() ?? createAgoraRtcEngine();
      _engine = engine;
      await _setCallAudioService(true);
      final generation = ++_rtcGeneration;
      await engine.initialize(RtcEngineContext(
        appId: data['appId']?.toString().isNotEmpty == true
            ? data['appId'].toString()
            : AgoraConstants.appId,
        audioScenario: AudioScenarioType.audioScenarioMeeting,
      ));
      await engine
          .setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await engine.enableAudio();
      await configureRtcSpeech(engine);
      await engine.setDefaultAudioRouteToSpeakerphone(_speaker);
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (_, __) {
          if ((!mounted || !_scope.current) ||
              _endRequested ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          setState(() {
            _joinedRtc = true;
            _joiningRtc = false;
            _error = null;
          });
          _rtcConnectTimer?.cancel();
          _rtcConnectTimer = Timer(const Duration(seconds: 15), () {
            if ((mounted && _scope.current) &&
                !_endRequested &&
                !_remoteJoined) {
              setState(() => _error = '暂未检测到对方语音，可点击重新连接');
            }
          });
          Future.microtask(() async {
            try {
              if ((!mounted || !_scope.current) ||
                  _endRequested ||
                  !identical(_engine, engine)) {
                return;
              }
              try {
                await engine.setEnableSpeakerphone(_speaker);
              } catch (_) {}
              await engine.adjustPlaybackSignalVolume(100);
              await engine.adjustRecordingSignalVolume(100);
              await engine.muteAllRemoteAudioStreams(false);
              await _markRtcReady();
            } catch (_) {}
          });
          _heartbeatTimer ??=
              Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
          unawaited(_setCallAudioService(true));
        },
        onUserJoined: (_, __, ___) {
          _rtcConnectTimer?.cancel();
          if ((mounted && _scope.current) &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            setState(() {
              _remoteJoined = true;
              _error = null;
            });
          }
        },
        onRemoteAudioStateChanged: (_, __, state, ___, ____) {
          if ((!mounted || !_scope.current) ||
              generation != _rtcGeneration ||
              !identical(_engine, engine)) {
            return;
          }
          setState(() {
            _remoteAudioPlaying =
                state == RemoteAudioState.remoteAudioStateDecoding;
          });
        },
        onUserOffline: (_, __, reason) {
          if ((mounted && _scope.current) &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            setState(() {
              _remoteJoined = false;
              _remoteAudioPlaying = false;
              _peerHungUp = reason == UserOfflineReasonType.userOfflineQuit;
              _error = _peerHungUp ? null : '对方网络中断，正在等待重连';
            });
            if (_peerHungUp) unawaited(_end('peer_ended'));
          }
        },
        onError: (_, message) {
          if ((mounted && _scope.current) &&
              generation == _rtcGeneration &&
              identical(_engine, engine)) {
            setState(() {
              _joiningRtc = false;
              _error = message.isEmpty ? '语音连接失败' : message;
            });
          }
        },
        onAudioRoutingChanged: (_) {
          if (identical(_engine, engine)) {
            unawaited(
                restoreRtcSpeechProcessing(engine).catchError((Object _) {}));
          }
        },
        onTokenPrivilegeWillExpire: (_, __) {
          unawaited(_renewRtcToken(engine, generation));
        },
        onRequestToken: (_) {
          unawaited(_renewRtcToken(engine, generation));
        },
      ));
      if ((!mounted || !_scope.current) ||
          _endRequested ||
          generation != _rtcGeneration ||
          !identical(_engine, engine)) {
        return;
      }
      await engine.enableLocalAudio(true);
      if ((!mounted || !_scope.current) ||
          _endRequested ||
          generation != _rtcGeneration ||
          !identical(_engine, engine)) {
        return;
      }
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
          enableAudioRecordingOrPlayout: true,
        ),
      );
    } catch (error) {
      await _releaseRtc();
      if ((mounted && _scope.current) && !_endRequested) {
        setState(() {
          _joiningRtc = false;
          _joinedRtc = false;
          _rtcBlocked = error is FormatException &&
              error.message.toString().contains('麦克风权限');
          _error = error is FormatException ? error.message : '语音连接失败，请重试';
        });
      }
    }
  }

  Future<void> _renewRtcToken(RtcEngine engine, int generation) async {
    if (_tokenRenewInFlight ||
        (!mounted || !_scope.current) ||
        _endRequested ||
        generation != _rtcGeneration ||
        !identical(_engine, engine)) {
      return;
    }
    _tokenRenewInFlight = true;
    try {
      final response = await _scope.post(
        '/api/consultation/sessions/${widget.sessionId}/join',
        data: {'deferredReady': true},
      );
      final data = (response.data as Map?)?['data'];
      final token = data is Map ? data['rtcToken']?.toString() : null;
      if (token == null || token.isEmpty) throw const FormatException();
      if ((mounted && _scope.current) &&
          !_endRequested &&
          generation == _rtcGeneration &&
          identical(_engine, engine)) {
        await engine.renewToken(token);
      }
    } catch (_) {
      if ((mounted && _scope.current) && generation == _rtcGeneration) {
        setState(() => _error = '语音凭证续期失败，请点击重新连接');
      }
    } finally {
      _tokenRenewInFlight = false;
    }
  }

  Future<void> _recoverRtcAfterResume() async {
    if ((!mounted || !_scope.current) ||
        _endRequested ||
        _resumeInFlight ||
        _ending ||
        endedState(_session?['status']?.toString())) {
      return;
    }
    _resumeInFlight = true;
    try {
      final engine = _engine;
      if (engine == null || !_joinedRtc) {
        await _retryRtc();
        return;
      }
      await engine.enableAudio();
      await engine.enableLocalAudio(true);
      await engine.muteLocalAudioStream(_muted);
      await engine.muteAllRemoteAudioStreams(false);
      await engine.setEnableSpeakerphone(_speaker);
      await _setCallAudioService(true);
    } catch (_) {
      if ((mounted && _scope.current)) await _retryRtc();
    } finally {
      _resumeInFlight = false;
    }
  }

  Future<void> _setCallAudioService(bool active) async {
    if (active && ((!mounted || !_scope.current) || _endRequested)) return;
    await CallBackgroundAudio.update(
        'private:${widget.sessionId}:${identityHashCode(this)}', active,
        title: '私人专线进行中');
  }

  Future<void> _releaseRtc() async {
    final engine = _engine;
    _engine = null;
    _rtcGeneration += 1;
    _rtcConnectTimer?.cancel();
    _rtcCleanup = _rtcCleanup.then((_) async {
      await releaseRtcEngine(engine);
      await _setCallAudioService(false);
    });
    await _rtcCleanup;
    if (mounted) {
      setState(() {
        _joiningRtc = false;
        _joinedRtc = false;
        _remoteJoined = false;
        _remoteAudioPlaying = false;
      });
    }
  }

  Future<void> _markRtcReady() async {
    if ((!mounted || !_scope.current) ||
        _endRequested ||
        _rtcReadySent ||
        !_joinedRtc ||
        _ending) {
      return;
    }
    _rtcReadySent = true;
    try {
      final response = await _scope
          .post('/api/consultation/sessions/${widget.sessionId}/ready');
      final raw = (response.data as Map?)?['data'];
      if (raw is Map && (mounted && _scope.current) && !_endRequested) {
        setState(() => _session = Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      _rtcReadySent = false;
      if ((mounted && _scope.current) && !_endRequested) {
        setState(() => _error = '语音状态同步失败，正在自动重试');
      }
    }
  }

  Future<void> _retryRtc() async {
    if ((!mounted || !_scope.current) || _endRequested) return;
    _rtcConnectTimer?.cancel();
    await _releaseRtc();
    if ((!mounted || !_scope.current) || _endRequested) return;
    setState(() {
      _rtcBlocked = false;
      _joiningRtc = false;
      _joinedRtc = false;
      _remoteJoined = false;
      _remoteAudioPlaying = false;
      _rtcReadySent = false;
      _error = null;
    });
    await _joinRtc();
  }

  Future<void> _submitReview() async {
    if ((!mounted || !_scope.current)) return;
    var rating = 5;
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('评价本次服务'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  onPressed: () => setDialogState(() => rating = index + 1),
                  icon: Icon(index < rating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFD4B06B)),
                ),
              ),
            ),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '说说本次服务感受（选填）'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('以后再说')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('提交评价')),
          ],
        ),
      ),
    );
    final content = controller.text.trim();
    controller.dispose();
    if (submitted != true || (!mounted || !_scope.current)) return;
    try {
      await _scope.post(
        '/api/consultation/sessions/${widget.sessionId}/review',
        data: {
          'rating': rating,
          'professionalism': rating,
          'patience': rating,
          'helpfulness': rating,
          'content': content,
          'anonymous': true,
        },
      );
      if ((mounted && _scope.current)) showAppToast(context, '评价已提交');
    } on ApiSessionChangedException {
      return;
    } on DioException catch (e) {
      if ((mounted && _scope.current)) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '评价提交失败');
      }
    }
  }

  Future<void> _report() async {
    if ((!mounted || !_scope.current)) return;
    await showReportSheet(
      context,
      targetType: 'consultation',
      targetId: widget.sessionId,
      title: '举报咨询服务',
    );
  }

  void _recharge() {
    widget.onMinimize?.call();
    Get.key.currentState
        ?.push(MaterialPageRoute(builder: (_) => const RechargePage()));
  }

  void _checkLowBalance(Map<String, dynamic> session) {
    final remaining = (session['walletRemainingSeconds'] ??
        session['remainingSeconds']) as num?;
    if (remaining == null || remaining > 120) {
      _lowBalanceAlerted = false;
      return;
    }
    if (_lowBalanceAlerted ||
        session['status'] != 'active' ||
        session['viewerRole'] == 'teacher' ||
        session['paymentMethod'] == 'alipay') {
      return;
    }
    _lowBalanceAlerted = true;
    final promptContext = Get.key.currentState?.overlay?.context ?? context;
    ScaffoldMessenger.maybeOf(promptContext)?.showSnackBar(SnackBar(
      content: const Text('余额不足两分钟，请及时充值'),
      action: SnackBarAction(label: '充值', onPressed: _recharge),
    ));
  }

  Future<void> _heartbeat() async {
    if ((!mounted || !_scope.current) || _endRequested || _ending) return;
    try {
      final response = await _scope
          .post('/api/consultation/sessions/${widget.sessionId}/heartbeat');
      final raw = (response.data as Map?)?['data'];
      if (raw is Map && (mounted && _scope.current) && !_endRequested) {
        final next = Map<String, dynamic>.from(raw);
        setState(() => _session = next);
        _checkLowBalance(next);
        if (next['shouldEnd'] == true) {
          showAppToast(
              context,
              (next['paymentMethod'] ?? 'coin') == 'coin'
                  ? '玄遇币余额已用完，咨询将自动结束'
                  : '咨询将自动结束并按实际时长结算');
          await _end('balance_exhausted');
        }
      }
    } catch (_) {}
  }

  Future<void> _answerIncoming(bool accept) async {
    if (_ending || !_scope.current) return;
    setState(() => _ending = true);
    try {
      await _scope.post(
          '/api/consultation/sessions/${widget.sessionId}/${accept ? 'accept' : 'reject'}');
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '处理失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) {
        setState(() => _ending = false);
        await _refresh();
      }
    }
  }

  Future<void> _end(String reason) async {
    if ((!mounted || !_scope.current) || _ending) return;
    setState(() {
      _ending = true;
      _endRequested = true;
    });
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _rtcConnectTimer?.cancel();
    unawaited(_releaseRtc());
    if ((!mounted || !_scope.current)) return;
    try {
      final action = (_session?['status'] == 'waiting') ? 'cancel' : 'end';
      final response = await _scope.post(
          '/api/consultation/sessions/${widget.sessionId}/$action',
          data: {'reason': reason});
      final body = response.data;
      if (body is! Map || body['code'] != 0) throw const FormatException();
      if ((!mounted || !_scope.current)) return;
      final raw = body['data'];
      setState(() {
        if (raw is Map) _session = Map<String, dynamic>.from(raw);
        _error = endedState(_session?['status']?.toString())
            ? null
            : '已停止本地语音，正在确认结束状态';
      });
    } catch (_) {
      if ((mounted && _scope.current)) {
        setState(() => _error = '结束请求未确认，请检查网络并重试结束');
      }
    } finally {
      if ((mounted && _scope.current)) {
        setState(() => _ending = false);
        await _refresh();
      }
    }
  }

  bool _backPrompt = false;
  Future<void> _confirmBack() async {
    if (_backPrompt || !mounted || !_scope.current) return;
    if (endedState(_session?['status']?.toString())) {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    _backPrompt = true;
    try {
      final end = await showCallBackChoice(context);
      if (!mounted || !_scope.current) return;
      if (end == true) {
        await _end('user_ended');
      } else if (end == false) {
        widget.onMinimize?.call();
      }
    } finally {
      _backPrompt = false;
    }
  }

  Future<void> _confirmEnd([BuildContext? dialogContext]) async {
    if ((!mounted || !_scope.current) || _ending) return;
    if (_endRequested) {
      await _end('user_ended');
      return;
    }
    final coinPayment = (_session?['paymentMethod'] ?? 'coin') == 'coin';
    final ok = await showDialog<bool>(
        context: dialogContext ?? context,
        builder: (promptContext) => AlertDialog(
              title: Text(_session?['status'] == 'waiting' ? '取消呼叫？' : '结束咨询？'),
              content: Text(_session?['status'] == 'waiting'
                  ? coinPayment
                      ? '等待期间不收费，取消后预留的玄遇币会自动释放。'
                      : '等待期间不收费，取消后不会产生支付宝扣款。'
                  : '结束后系统会按实际有效时长结算。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(promptContext, false),
                    child: const Text('继续')),
                FilledButton(
                    onPressed: () => Navigator.pop(promptContext, true),
                    child: const Text('确认结束'))
              ],
            ));
    if (ok == true && (mounted && _scope.current)) await _end('user_ended');
  }

  Future<void> _shareBazi() async {
    if ((!mounted || !_scope.current)) return;
    final record = await showModalBottomSheet<RoomChartArchive>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RoomChartSheet(
        roomId: 0,
        members: const [],
        onChooseArchive: (record) => Navigator.of(sheetContext).pop(record),
      ),
    );
    if (record == null || (!mounted || !_scope.current)) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('授权本次咨询使用命盘'),
              content: const Text('仅当前专线老师可见，默认24小时后失效。不会向公开房间或其他用户展示。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认授权'))
              ],
            ));
    if (confirmed != true || (!mounted || !_scope.current)) return;
    try {
      await _scope.post(
          '/api/consultation/sessions/${widget.sessionId}/bazi-share',
          data: {
            'chartType': record.kind.code,
            'displayName': record.name,
            'snapshot': record.snapshot,
          });
      if ((mounted && _scope.current)) {
        showAppToast(context, '${record.kind.label}已授权给当前老师');
        await _viewBazi();
      }
    } on ApiSessionChangedException {
      return;
    } on DioException catch (e) {
      if ((mounted && _scope.current)) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '命盘授权失败');
      }
    }
  }

  Future<void> _viewBazi() async {
    if ((!mounted || !_scope.current)) return;
    try {
      final response = await _scope
          .get('/api/consultation/sessions/${widget.sessionId}/bazi-share');
      final data = (response.data as Map?)?['data'];
      if ((!mounted || !_scope.current)) return;
      if (data is! Map) {
        showAppToast(context, '用户尚未授权命盘');
        return;
      }
      final snapshot = data['snapshot'] is Map
          ? Map<String, dynamic>.from(data['snapshot'])
          : <String, dynamic>{};
      await showRoomChartSnapshot(
        context,
        kind: RoomChartKind.fromCode(data['chartType']?.toString()),
        snapshot: snapshot,
        title: data['displayName']?.toString() ?? '咨询命盘',
      );
    } on ApiSessionChangedException {
      return;
    } on DioException catch (e) {
      if ((mounted && _scope.current)) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '命盘加载失败');
      }
    }
  }

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _retryPayment() async {
    if ((!mounted || !_scope.current) || _ending) return;
    setState(() => _ending = true);
    try {
      final response = await _scope
          .post('/api/consultation/sessions/${widget.sessionId}/repay');
      final raw = (response.data as Map?)?['data'];
      if ((!mounted || !_scope.current)) return;
      if (raw is Map) {
        setState(() => _session = Map<String, dynamic>.from(raw));
      }
      showAppToast(context, '支付已完成');
    } on ApiSessionChangedException {
      return;
    } on DioException catch (e) {
      if ((mounted && _scope.current)) {
        showAppToast(
            context,
            (e.response?.data as Map?)?['message']?.toString() ??
                '支付未完成，请稍后重试');
      }
    } finally {
      if ((mounted && _scope.current)) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('私人专线')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }
    final s = _session;
    if (s == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('私人专线')),
          body: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!)));
    }
    final state = s['status']?.toString() ?? 'waiting';
    final ended =
        ['ended', 'cancelled', 'rejected', 'refunded'].contains(state);
    final teacherView = s['viewerRole'] == 'teacher';
    final seconds = (s['billedSeconds'] as num?)?.toInt() ?? 0;
    final rate = (s['ratePerMin'] as num?)?.toDouble() ?? 0;
    final paymentMethod = s['paymentMethod']?.toString() ?? 'coin';
    final coinPayment = paymentMethod == 'coin';
    final paymentNeedsAction =
        s['paymentStatus'] == 'failed' || s['paymentStatus'] == 'processing';
    final currentCost = state == 'active'
        ? rate * seconds / 60
        : (s['chargedAmount'] as num?)?.toDouble() ?? 0;
    return PopScope(
      canPop: ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (ended && widget.onClose != null) {
            widget.onClose!();
          } else if (widget.onMinimize != null) {
            unawaited(_confirmBack());
          } else {
            _confirmEnd();
          }
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFFF5FBFA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFF173F3B),
          elevation: 0,
          leading: widget.onClose == null
              ? null
              : IconButton(
                  icon: Icon(ended ? Icons.arrow_back : Icons.fullscreen_exit),
                  tooltip: ended ? '关闭专线' : '缩成浮窗',
                  onPressed: ended ? widget.onClose : widget.onMinimize),
          title: Text(teacherView ? '咨询服务中' : '私人专线'),
          actions: [
            if (!ended)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F7F5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Row(children: [
                  Icon(Icons.shield_outlined,
                      size: 15, color: Color(0xFF1A8D86)),
                  SizedBox(width: 4),
                  Text('号码已隐藏',
                      style: TextStyle(
                          color: Color(0xFF176762),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'view') _viewBazi();
                if (value == 'share') _shareBazi();
                if (value == 'report') _report();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: teacherView ? 'view' : 'share',
                  child: Text(teacherView ? '查看授权命盘' : '授权本次命盘'),
                ),
                if (!teacherView) ...[
                  const PopupMenuItem(value: 'view', child: Text('查看已授权命盘')),
                  const PopupMenuItem(value: 'report', child: Text('举报异常')),
                ],
              ],
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _PrivateCallBackground(),
            SafeArea(
              child: Column(children: [
                const SizedBox(height: 50),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x4D82DAD4))),
                  child: Row(children: [
                    _CallStat(_duration(seconds), '有效时长'),
                    _CallStat(
                        '${currentCost.toStringAsFixed(2)}${coinPayment ? '玄遇币' : '元'}',
                        '当前消费'),
                    coinPayment
                        ? _CallStat(
                            _duration((s['walletRemainingSeconds'] as num? ??
                                        s['remainingSeconds'] as num?)
                                    ?.toInt() ??
                                0),
                            '余额可用')
                        : _CallStat(paymentNeedsAction ? '待确认' : '免密',
                            paymentNeedsAction ? '支付状态' : '结束后结算'),
                  ]),
                ),
                if (!teacherView &&
                    coinPayment &&
                    !ended &&
                    state == 'active' &&
                    ((s['walletRemainingSeconds'] ?? s['remainingSeconds'])
                                as num? ??
                            0) <=
                        120)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('余额不足两分钟，请及时充值'),
                    TextButton(onPressed: _recharge, child: const Text('充值')),
                  ]),
                Expanded(
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 132,
                    height: 132,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFBDF3EE), Color(0xFF48CFC7)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1AC4C4).withValues(alpha: .2),
                          blurRadius: 34,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                        backgroundColor: const Color(0xFFE5F7F5),
                        backgroundImage: (s['peer'] is Map &&
                                (s['peer']['avatarUrl']?.toString() ?? '')
                                    .isNotEmpty)
                            ? NetworkImage(s['peer']['avatarUrl'].toString())
                            : null,
                        child: (s['peer'] is! Map ||
                                (s['peer']['avatarUrl']?.toString() ?? '')
                                    .isEmpty)
                            ? const Icon(Icons.person_rounded,
                                size: 58, color: Color(0xFF176762))
                            : null),
                  ),
                  const SizedBox(height: 18),
                  Text(
                      s['peer'] is Map
                          ? s['peer']['nickname']?.toString() ?? '咨询对象'
                          : '咨询对象',
                      style: AppTextStyles.titleLarge
                          .copyWith(color: const Color(0xFF173F3B))),
                  const SizedBox(height: 8),
                  Text(_peerHungUp ? '对方已经挂断' : _stateLabel(state),
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: const Color(0xFF5E7E7A))),
                  if (_error != null && !_peerHungUp) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Color(0xFFB6635F))),
                    if (!ended && !_endRequested && state != 'waiting') ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _joiningRtc ? null : _retryRtc,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF176762),
                            side: const BorderSide(color: Color(0xFF82DAD4))),
                        child: const Text('重新连接'),
                      ),
                    ],
                  ],
                ]))),
                if (!ended)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                    child: Column(children: [
                      if (state == 'waiting' &&
                          s['canAnswer'] == true &&
                          !teacherView)
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              OutlinedButton(
                                  onPressed: _ending
                                      ? null
                                      : () => _answerIncoming(false),
                                  child: const Text('拒绝')),
                              FilledButton(
                                  onPressed: _ending
                                      ? null
                                      : () => _answerIncoming(true),
                                  child: const Text('接听')),
                            ])
                      else
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _CallAction(
                                  icon: _muted
                                      ? Icons.mic_off_rounded
                                      : Icons.mic_rounded,
                                  label: _muted ? '取消静音' : '静音',
                                  onTap: () {
                                    _engine?.muteLocalAudioStream(!_muted);
                                    setState(() => _muted = !_muted);
                                  }),
                              _CallAction(
                                  icon: _speaker
                                      ? Icons.volume_up_rounded
                                      : Icons.hearing_rounded,
                                  label: _speaker ? '扬声器' : '听筒',
                                  onTap: () {
                                    _engine?.setEnableSpeakerphone(!_speaker);
                                    setState(() => _speaker = !_speaker);
                                  }),
                              _CallAction(
                                  icon: Icons.grid_view_rounded,
                                  label: teacherView ? '查看命盘' : '命盘',
                                  onTap: teacherView ? _viewBazi : _shareBazi),
                              _CallAction(
                                  icon: Icons.call_end_rounded,
                                  label: _ending
                                      ? '正在结束'
                                      : _endRequested
                                          ? '重试结束'
                                          : state == 'waiting'
                                              ? '取消'
                                              : '结束',
                                  danger: true,
                                  onTap: _confirmEnd),
                            ]),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x3D82DAD4)),
                        ),
                        child: Text(
                            '号码隐藏 · ${rate.toStringAsFixed(2)}${coinPayment ? '玄遇币' : '元'}/分钟 · 等待不收费',
                            style: const TextStyle(
                                color: Color(0xFF5E7E7A), fontSize: 11)),
                      ),
                    ]),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      if (!teacherView && paymentNeedsAction) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFEEE9),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Text('支付宝扣款尚未确认，请继续完成本次账单。',
                              style: TextStyle(color: Color(0xFF9A4E45))),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _ending ? null : _retryPayment,
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1677FF),
                              minimumSize: const Size.fromHeight(44)),
                          icon:
                              const Icon(Icons.account_balance_wallet_rounded),
                          label: const Text('继续完成支付'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (!teacherView && state == 'ended') ...[
                        OutlinedButton.icon(
                          onPressed: _submitReview,
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF176762),
                              side: const BorderSide(color: Color(0xFF82DAD4)),
                              minimumSize: const Size.fromHeight(44)),
                          icon: const Icon(Icons.star_outline_rounded),
                          label: const Text('评价本次服务'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1AC4C4),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48)),
                          child: const Text('完成')),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(String state) => switch (state) {
        'waiting' => _session?['initiatorRole'] == 'teacher'
            ? (_session?['isCaller'] == true
                ? '正在等待用户接听，等待期间不收费'
                : '老师邀请您接听私人专线')
            : _session?['viewerRole'] == 'teacher'
                ? '等待接听用户的咨询'
                : '正在等待老师接听，等待期间不收费',
        'accepted' || 'connecting' => _joinedRtc
            ? (_remoteJoined ? '双方已进入，正在接通声音' : '已接入，等待对方进入')
            : '老师已接听，正在建立安全语音连接',
        'active' => _remoteAudioPlaying
            ? '通话中'
            : (_remoteJoined ? '双方已连接，对方暂未讲话' : '正在等待对方音频'),
        'ended' => '咨询已结束，账单已按实际时长结算',
        'rejected' => '老师暂时无法接听，本次未产生费用',
        'cancelled' => '呼叫已取消，本次未产生费用',
        'refunded' => '订单已退款',
        _ => '正在更新咨询状态',
      };
}

class _CallStat extends StatelessWidget {
  const _CallStat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: const TextStyle(
                color: Color(0xFF173F3B),
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(color: Color(0xFF78908D), fontSize: 10))
      ]));
}

class _CallAction extends StatelessWidget {
  const _CallAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Column(children: [
        Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                color: danger
                    ? const Color(0xFFF05D57)
                    : Colors.white.withValues(alpha: .88),
                shape: BoxShape.circle,
                border:
                    danger ? null : Border.all(color: const Color(0x4D82DAD4)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14176362),
                      blurRadius: 16,
                      offset: Offset(0, 7)),
                ]),
            child: Icon(icon,
                color: danger ? Colors.white : const Color(0xFF176762))),
        const SizedBox(height: 7),
        Text(label,
            style: const TextStyle(color: Color(0xFF466B67), fontSize: 11))
      ]));
}

class _PrivateCallBackground extends StatelessWidget {
  const _PrivateCallBackground();

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF9FCFB),
                  Color(0xFFE7F8F6),
                  Color(0xFFF1F1FB),
                ],
              ),
            ),
          ),
          Positioned(
            left: -80,
            top: 120,
            child: _PrivateCallGlow(
              size: 260,
              color: const Color(0xFF82E2DC).withValues(alpha: .28),
            ),
          ),
          Positioned(
            right: -100,
            bottom: 80,
            child: _PrivateCallGlow(
              size: 300,
              color: const Color(0xFFAAA0DD).withValues(alpha: .2),
            ),
          ),
        ],
      );
}

class _PrivateCallGlow extends StatelessWidget {
  const _PrivateCallGlow({required this.size, required this.color});
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
