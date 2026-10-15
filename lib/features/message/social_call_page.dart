import '../../core/utils/call_background_audio.dart';
import '../../shared/widgets/draggable_video_preview.dart';
import '../../shared/widgets/call_back_choice.dart';
import '../../core/utils/rtc_speech.dart';
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'social_call_sound.dart';

import '../../core/constants/agora_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../consultation/voice_room_overlay_controller.dart';

class SocialCallPage extends StatefulWidget {
  const SocialCallPage({
    super.key,
    required this.callId,
    this.initialCall,
    this.engineFactory,
    this.requestMicrophone,
    this.requestCamera,
    this.onMinimize,
    this.onBackReady,
    this.onClose,
    this.onSessionEnded,
    this.onEndReady,
  });

  final VoidCallback? onMinimize;
  final void Function(Future<void> Function() callback)? onBackReady;
  final VoidCallback? onClose;
  final VoidCallback? onSessionEnded;
  final void Function(Future<void> Function(BuildContext) callback)? onEndReady;
  final int callId;
  final Map<String, dynamic>? initialCall;
  final RtcEngine Function()? engineFactory;
  final Future<bool> Function()? requestMicrophone;
  final Future<bool> Function()? requestCamera;

  @override
  State<SocialCallPage> createState() => _SocialCallPageState();
}

class _SocialCallPageState extends State<SocialCallPage>
    with WidgetsBindingObserver {
  final _scope = ApiSessionScope();
  Map<String, dynamic>? _call;
  RtcEngine? _engine;
  Future<RtcEngine>? _enginePreparation;
  final _sound = SocialCallSound();
  bool _previewReady = false;
  bool _rtcFailed = false;
  bool _endFailed = false;
  bool _leaveConfirmed = false;
  Timer? _joinTimeout;
  Future<void> _releaseQueue = Future<void>.value();
  Timer? _pollTimer;
  bool _refreshing = false;
  bool _joining = false;
  bool _joined = false;
  bool _muted = false;
  bool _speaker = true;
  bool _cameraEnabled = true;
  bool _localVideoFullScreen = false;
  bool _ending = false;
  bool _roomAudioSuspended = false;
  int? _remoteUid;
  String? _channel;
  String? _error;

  bool get _video => _call?['mode'] == 'video';
  bool get _caller => _call?['isCaller'] == true;
  String get _status => _call?['status']?.toString() ?? 'ringing';
  bool get _finished =>
      const {'ended', 'cancelled', 'rejected', 'missed'}.contains(_status);

  @override
  void initState() {
    super.initState();
    widget.onBackReady?.call(_confirmBack);
    widget.onEndReady?.call(_confirmHangUp);
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_accountChanged);
    _call = widget.initialCall == null
        ? null
        : Map<String, dynamic>.from(widget.initialCall!);
    unawaited(_prepare());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _prepare() async {
    _roomAudioSuspended =
        await VoiceRoomOverlayController.instance.suspendAudio();
    if (!mounted || !_scope.current) return;
    if (_caller && _status == 'ringing') _sound.start(incoming: false);
    await _refresh();
  }

  void _accountChanged() {
    if (!mounted || _scope.current) return;
    _pollTimer?.cancel();
    _joinTimeout?.cancel();
    unawaited(_sound.stop());
    _roomAudioSuspended = false;
    final engine = _engine;
    _engine = null;
    setState(() {
      _call = null;
      _joined = false;
      _joining = false;
      _remoteUid = null;
    });
    unawaited(_release(engine));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_accountChanged);
    _pollTimer?.cancel();
    _joinTimeout?.cancel();
    unawaited(_sound.dispose());
    final engine = _engine;
    _engine = null;
    unawaited(_release(engine));
    super.dispose();
  }

  Future<void> _release(RtcEngine? engine) =>
      _releaseQueue = _releaseQueue.then((_) => _releaseEngine(engine));

  Future<void> _releaseEngine(RtcEngine? engine) async {
    if (engine != null) {
      await CallBackgroundAudio.update(
          'social:${identityHashCode(engine)}', false);
    }
    await releaseRtcEngine(engine);
    if (_roomAudioSuspended && _scope.current) {
      _roomAudioSuspended = false;
      try {
        await VoiceRoomOverlayController.instance.resumeAudio();
      } catch (_) {}
    }
  }

  Future<void> _refresh() async {
    if ((!mounted || !_scope.current) || _refreshing || _ending || _endFailed) {
      return;
    }
    _refreshing = true;
    try {
      final response = await _scope.get('/api/im/social-call/${widget.callId}');
      final raw = (response.data as Map?)?['data'];
      if (raw is! Map || (!mounted || !_scope.current)) return;
      final next = Map<String, dynamic>.from(raw);
      if (_call.toString() != next.toString()) setState(() => _call = next);
      if (next['status'] != 'ringing') await _sound.stop();
      if (_video && next['status'] == 'ringing' && !_rtcFailed) {
        try {
          await (_enginePreparation ??= _initializeEngine(next));
        } catch (_) {
          if (mounted && _scope.current) {
            setState(() {
              _rtcFailed = true;
              _error = '相机预览不可用，请检查相机权限';
            });
          }
        }
      }
      if (next['status'] == 'accepted' &&
          !_joined &&
          !_joining &&
          !_rtcFailed) {
        await _joinRtc(next);
      }
      if (const {'ended', 'cancelled', 'rejected', 'missed'}
          .contains(next['status'])) {
        _pollTimer?.cancel();
        final engine = _engine;
        _engine = null;
        unawaited(_release(engine));
        if (!mounted || !_scope.current) return;
        if (widget.onSessionEnded != null) {
          widget.onSessionEnded!();
          return;
        }
        if (mounted) {
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if ((mounted && _scope.current)) Navigator.of(context).maybePop();
          });
        }
      }
    } on ApiSessionChangedException {
      return;
    } on DioException catch (error) {
      if (mounted &&
          _scope.current &&
          const {403, 404, 410}.contains(error.response?.statusCode) &&
          widget.onClose != null) {
        widget.onClose!();
        return;
      }
      if ((mounted && _scope.current) && _call == null) {
        setState(() => _error =
            (error.response?.data as Map?)?['message']?.toString() ??
                '通话状态加载失败');
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<RtcEngine> _initializeEngine(Map<String, dynamic> data) async {
    if (_video) {
      final granted = await (widget.requestCamera?.call() ??
          Permission.camera.request().then((value) => value.isGranted));
      if (!granted) throw const FormatException('需要相机权限');
    }
    if (!mounted || !_scope.current || _ending) {
      throw const FormatException('通话已结束');
    }
    final engine = widget.engineFactory?.call() ?? createAgoraRtcEngine();
    _engine = engine;
    await CallBackgroundAudio.update('social:${identityHashCode(engine)}', true,
        title: _video ? '视频通话进行中' : '语音通话进行中', camera: _video);
    try {
      await engine.initialize(RtcEngineContext(
        appId: data['appId']?.toString().isNotEmpty == true
            ? data['appId'].toString()
            : AgoraConstants.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        audioScenario: AudioScenarioType.audioScenarioMeeting,
      ));
      if (!mounted ||
          !_scope.current ||
          _ending ||
          !identical(_engine, engine)) {
        throw const FormatException('通话已结束');
      }
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (_, __) {
          if (mounted &&
              _scope.current &&
              identical(_engine, engine) &&
              !_ending) {
            _joinTimeout?.cancel();
            unawaited(engine
                .setEnableSpeakerphone(_speaker)
                .catchError((Object _) {}));
            setState(() {
              _joined = true;
              _joining = false;
              _error = null;
            });
          }
        },
        onUserJoined: (_, uid, __) {
          if (mounted && _scope.current && identical(_engine, engine)) {
            setState(() => _remoteUid = uid);
          }
        },
        onUserOffline: (_, uid, reason) {
          if (mounted &&
              _scope.current &&
              identical(_engine, engine) &&
              _remoteUid == uid) {
            setState(() {
              _remoteUid = null;
              if (reason == UserOfflineReasonType.userOfflineQuit) {
                _error = '对方已经挂断';
                _rtcFailed = false;
              }
            });
            if (reason == UserOfflineReasonType.userOfflineQuit) {
              unawaited(_refresh());
            }
          }
        },
        onError: (_, __) {
          unawaited(_connectionFailed(engine));
        },
        onConnectionStateChanged: (_, state, __) {
          if (state == ConnectionStateType.connectionStateFailed) {
            unawaited(_connectionFailed(engine));
          }
        },
        onAudioRoutingChanged: (_) {
          if (identical(_engine, engine)) {
            unawaited(
                restoreRtcSpeechProcessing(engine).catchError((Object _) {}));
          }
        },
        onTokenPrivilegeWillExpire: (_, __) {
          unawaited(_renewToken(engine));
        },
      ));
      if (_video) {
        await engine.enableVideo();
        await engine.startPreview();
        if (mounted && _scope.current && identical(_engine, engine)) {
          setState(() => _previewReady = true);
        }
      }
      await engine.setDefaultAudioRouteToSpeakerphone(_video);
      _speaker = _video;
      return engine;
    } catch (_) {
      if (identical(_engine, engine)) _engine = null;
      await _release(engine);
      rethrow;
    }
  }

  Future<void> _renewToken(RtcEngine engine) async {
    try {
      final response = await _scope.get('/api/im/social-call/${widget.callId}');
      final data = (response.data as Map?)?['data'];
      if (mounted &&
          _scope.current &&
          identical(_engine, engine) &&
          data is Map &&
          data['status'] == 'accepted') {
        final token = data['rtcToken']?.toString() ?? '';
        if (token.isNotEmpty) await engine.renewToken(token);
      }
    } catch (_) {
      await _connectionFailed(engine);
    }
  }

  Future<void> _connectionFailed(RtcEngine engine) async {
    if (!mounted || !_scope.current || !identical(_engine, engine) || _ending) {
      return;
    }
    _joinTimeout?.cancel();
    _engine = null;
    _enginePreparation = null;
    setState(() {
      _joining = false;
      _joined = false;
      _previewReady = false;
      _rtcFailed = true;
      _remoteUid = null;
      _error = '音视频连接失败，请检查网络或权限后重试';
    });
    await _release(engine);
  }

  Future<void> _retryConnection() async {
    if (_ending || _endFailed || _finished) return;
    final engine = _engine;
    _engine = null;
    _enginePreparation = null;
    await _release(engine);
    if (!mounted || !_scope.current) return;
    _roomAudioSuspended =
        await VoiceRoomOverlayController.instance.suspendAudio();
    if (!mounted || !_scope.current) return;
    setState(() {
      _rtcFailed = false;
      _previewReady = false;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _joinRtc(Map<String, dynamic> data) async {
    if (!mounted || !_scope.current || _ending) return;
    _joining = true;
    try {
      await _sound.stop();
      final granted = await (widget.requestMicrophone?.call() ??
          Permission.microphone.request().then((value) => value.isGranted));
      if (!granted) throw const FormatException('需要麦克风权限');
      final token = data['rtcToken']?.toString() ?? '';
      final channel = data['channel']?.toString() ?? '';
      final uid = (data['uid'] as num?)?.toInt() ?? 0;
      if (token.isEmpty || channel.isEmpty || uid <= 0) {
        throw const FormatException('通话参数不完整');
      }
      final engine = await (_enginePreparation ??= _initializeEngine(data));
      if (!mounted ||
          !_scope.current ||
          _ending ||
          !identical(_engine, engine)) {
        return;
      }
      _channel = channel;
      await engine.enableAudio();
      await configureRtcSpeech(engine);
      await engine.enableLocalAudio(true);
      await engine.muteLocalAudioStream(_muted);
      await engine.muteAllRemoteAudioStreams(false);
      _joinTimeout = Timer(const Duration(seconds: 20), () {
        if (!_joined) unawaited(_connectionFailed(engine));
      });
      await engine.joinChannel(
          token: token,
          channelId: channel,
          uid: uid,
          options: ChannelMediaOptions(
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            publishMicrophoneTrack: true,
            publishCameraTrack: _video,
            autoSubscribeAudio: true,
            autoSubscribeVideo: _video,
            enableAudioRecordingOrPlayout: true,
          ));
    } catch (error) {
      final engine = _engine;
      _engine = null;
      _enginePreparation = null;
      _joinTimeout?.cancel();
      if (mounted && _scope.current) {
        setState(() {
          _joining = false;
          _previewReady = false;
          _rtcFailed = true;
          _error = error is FormatException
              ? error.message.toString()
              : '通话连接失败，请重试';
        });
      }
      await _release(engine);
    }
  }

  Future<void> _hangUp() async {
    if ((!mounted || !_scope.current) || _ending) return;
    setState(() => _ending = true);
    _joinTimeout?.cancel();
    await _sound.stop();
    final engine = _engine;
    _engine = null;
    _enginePreparation = null;
    unawaited(_release(engine));
    try {
      final action =
          _status == 'ringing' && _caller && !_endFailed ? 'cancel' : 'end';
      await _scope.post('/api/im/social-call/${widget.callId}/$action');
      if (!mounted || !_scope.current) return;
      setState(() {
        _leaveConfirmed = true;
        _endFailed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scope.current) {
          if (widget.onClose != null) {
            widget.onClose!();
          } else {
            Navigator.of(context).pop();
          }
        }
      });
    } catch (_) {
      if (mounted && _scope.current) {
        setState(() {
          _ending = false;
          _endFailed = true;
          _joined = false;
          _previewReady = false;
          _error = '挂断尚未确认，请检查网络后重试挂断';
        });
      }
    }
  }

  bool _backPrompt = false;
  Future<void> _confirmBack() async {
    if (_backPrompt || !mounted || !_scope.current) return;
    if (_finished || _leaveConfirmed) {
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
        await _hangUp();
      } else if (end == false) {
        widget.onMinimize?.call();
      }
    } finally {
      _backPrompt = false;
    }
  }

  Future<void> _confirmHangUp(BuildContext promptContext) async {
    if (_ending || !_scope.current) return;
    final confirmed = await showDialog<bool>(
        context: promptContext,
        builder: (ctx) => AlertDialog(title: const Text('是否挂断通话？'), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续通话')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('挂断'))
            ]));
    if (confirmed == true && mounted && _scope.current) await _hangUp();
  }

  Future<void> _switchCamera() async {
    if (!_video || !_previewReady || _engine == null) return;
    try {
      await _engine!.switchCamera();
    } catch (_) {
      if (mounted && _scope.current) setState(() => _error = '摄像头切换失败，请稍后再试');
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _engine?.muteLocalAudioStream(next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    await _engine?.setEnableSpeakerphone(next);
    if (mounted) setState(() => _speaker = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraEnabled;
    await _engine?.enableLocalVideo(next);
    if (mounted) setState(() => _cameraEnabled = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('通话')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }
    final peer = _call?['peer'] is Map
        ? Map<String, dynamic>.from(_call!['peer'] as Map)
        : const <String, dynamic>{};
    final nickname = peer['nickname']?.toString() ?? '好友';
    final avatarUrl = peer['avatarUrl']?.toString() ?? '';
    final statusText = switch (_status) {
      'accepted' => _remoteUid == null ? '等待对方接入…' : '通话中',
      'rejected' => '对方已拒接',
      'cancelled' => '通话已取消',
      'missed' => '无人接听',
      'ended' => '通话已结束',
      _ => _caller ? '正在呼叫…' : '正在接通…',
    };
    return PopScope(
      canPop: _finished || _leaveConfirmed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (widget.onMinimize != null) {
            unawaited(_confirmBack());
          } else {
            unawaited(_hangUp());
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF11282D),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_video && _previewReady) _videoLayer(),
            if (!_video || !_previewReady)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF31535B), Color(0xFF10262B)],
                  ),
                ),
              ),
            if (!_finished)
              Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 12,
                  child: Row(children: [
                    if (_video && _previewReady)
                      IconButton(
                          tooltip: '翻转摄像头',
                          onPressed: _switchCamera,
                          icon: const Icon(Icons.cameraswitch_rounded,
                              color: Colors.white)),
                    if (widget.onMinimize != null)
                      IconButton(
                          tooltip: '缩小为浮窗',
                          onPressed: widget.onMinimize,
                          icon: const Icon(Icons.fullscreen_exit_rounded,
                              color: Colors.white)),
                  ])),
            Positioned(
                left: 12,
                top: MediaQuery.paddingOf(context).top + 8,
                child: IconButton(
                    tooltip: '返回',
                    onPressed: _confirmBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 36),
                child: Column(
                  children: [
                    if (!_video || !_previewReady) ...[
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.isEmpty
                            ? Text(nickname.isEmpty ? '?' : nickname[0],
                                style: const TextStyle(fontSize: 34))
                            : null,
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(nickname,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(_error ?? statusText,
                        style: TextStyle(
                            color: _error == null
                                ? Colors.white70
                                : Colors.orangeAccent,
                            fontSize: 15)),
                    if (_rtcFailed && !_endFailed && !_finished)
                      TextButton(
                          onPressed: _retryConnection,
                          child: const Text('重新连接',
                              style: TextStyle(color: Colors.white))),
                    const Spacer(),
                    if (_status == 'accepted')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _control(
                            _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            _muted ? '已静音' : '麦克风',
                            _toggleMute,
                          ),
                          _control(
                            _speaker
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            _speaker ? '扬声器' : '听筒',
                            _toggleSpeaker,
                          ),
                          if (_video)
                            _control(
                              _cameraEnabled
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              _cameraEnabled ? '摄像头' : '已关闭',
                              _toggleCamera,
                            ),
                        ],
                      ),
                    const SizedBox(height: 30),
                    InkWell(
                      onTap: _ending ? null : _hangUp,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF5964),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call_end_rounded,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(_endFailed ? '重试挂断' : '挂断',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoLayer() {
    final engine = _engine;
    final channel = _channel;
    if (engine == null) return const SizedBox.shrink();
    final local = _cameraEnabled
        ? AgoraVideoView(
            key: const ValueKey('local-video'),
            controller: VideoViewController(
                rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))
        : const ColoredBox(
            color: Color(0xFF11282D),
            child: Icon(Icons.videocam_off_rounded, color: Colors.white54));
    final remote = _remoteUid != null && channel != null
        ? AgoraVideoView(
            key: ValueKey('remote-video-$_remoteUid'),
            controller: VideoViewController.remote(
                rtcEngine: engine,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(channelId: channel)))
        : null;
    return Stack(fit: StackFit.expand, children: [
      _localVideoFullScreen || remote == null ? local : remote,
      if (remote != null)
        DraggableVideoPreview(
            onTap: () =>
                setState(() => _localVideoFullScreen = !_localVideoFullScreen),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _localVideoFullScreen ? remote : local)),
    ]);
  }

  Widget _control(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 27),
          ),
          const SizedBox(height: 7),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
