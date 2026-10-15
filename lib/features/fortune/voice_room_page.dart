import '../../core/utils/rtc_speech.dart';
import '../../core/utils/call_background_audio.dart';
import '../../core/utils/app_toast.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../core/constants/agora_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/user_profile_page.dart';
import '../consultation/voice_room_overlay_controller.dart';
import '../../core/network/account_profile_requests.dart';

/// 一对一语音房间：匹配成功后进入，实时语音聊天
class VoiceRoomPage extends StatefulWidget {
  const VoiceRoomPage({
    super.key,
    required this.roomId,
    this.engineFactory,
    this.requestMicrophone,
    this.onMinimize,
    this.onClose,
    this.onOpenProfile,
    this.onPeerChanged,
    this.onBackReady,
    this.onEndReady,
  });

  final RtcEngine Function()? engineFactory;
  final Future<bool> Function()? requestMicrophone;

  final String roomId;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final void Function(int userId)? onOpenProfile;
  final void Function(String? avatar)? onPeerChanged;
  final void Function(Future<void> Function() callback)? onBackReady;
  final void Function(Future<void> Function(BuildContext) callback)? onEndReady;

  @override
  State<VoiceRoomPage> createState() => _VoiceRoomPageState();
}

class _VoiceRoomPageState extends State<VoiceRoomPage> {
  RtcEngine? _engine;
  bool _joined = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _following = false;
  bool _relationshipBusy = false;
  Map<String, dynamic>? _self;
  bool _confirmingExit = false;
  bool _audioControlBusy = false;
  bool _peerLeft = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _peer;
  final _scope = ApiSessionScope();
  int _generation = 0;
  int? _remoteUid;
  bool _leaving = false;
  bool _roomAudioSuspended = false;
  bool _polling = false;
  bool _renewing = false;
  bool _reconnecting = false;
  int _callSeconds = 0;
  Timer? _callTimer;
  Timer? _joinTimeout;
  Timer? _statusTimer;

  bool _current(int generation) =>
      mounted && !_leaving && generation == _generation && _scope.current;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    widget.onBackReady?.call(_confirmExit);
    widget.onEndReady?.call(_confirmExit);
    unawaited(_loadSelf());
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      _roomAudioSuspended =
          await VoiceRoomOverlayController.instance.suspendAudio();
      if (!mounted || _leaving) {
        await _resumeRoomAudio();
        return;
      }
      if (_scope.current) await _joinRoom();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '语音初始化失败，请重试';
        });
      }
    }
  }

  Future<void> _resumeRoomAudio() async {
    if (!_roomAudioSuspended) return;
    _roomAudioSuspended = false;
    if (_scope.current) {
      try {
        await VoiceRoomOverlayController.instance.resumeAudio();
      } catch (_) {}
    }
  }

  void _sessionChanged() {
    if (!_scope.current) {
      _generation++;
      _stopTimers();
      unawaited(_releaseEngine());
      if (mounted) {
        setState(() {
          _loading = false;
          _error = apiSessionChangedMessage;
        });
      }
    }
  }

  void _stopTimers() {
    _joinTimeout?.cancel();
    _callTimer?.cancel();
    _statusTimer?.cancel();
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    await CallBackgroundAudio.update(
        'matched:${identityHashCode(engine)}', false);
    await releaseRtcEngine(engine);
  }

  void _fail(int generation, String message) {
    if (!_current(generation)) return;
    _stopTimers();
    _generation++;
    unawaited(_releaseEngine());
    setState(() {
      _loading = false;
      _joined = false;
      _error = message;
    });
  }

  Future<void> _joinRoom() async {
    final generation = ++_generation;
    _stopTimers();
    await _releaseEngine();
    if (!_current(generation)) return;
    setState(() {
      _loading = true;
      _error = null;
      _joined = false;
      _remoteUid = null;
      _peerLeft = false;
      _reconnecting = false;
    });
    _joinTimeout = Timer(
      const Duration(seconds: 20),
      () => _fail(generation, '连接超时，请检查网络后重试'),
    );
    try {
      final allowed = await (widget.requestMicrophone?.call() ??
          Permission.microphone.request().then((value) => value.isGranted));
      if (!_current(generation)) return;
      if (!allowed) {
        _fail(generation, '请允许麦克风权限后重试');
        return;
      }
      final res = await _scope.get(
        '/api/voice-room/join',
        queryParameters: {'room_id': widget.roomId},
      );
      if (!_current(generation)) return;
      final data = (res.data as Map?)?['data'] as Map?;
      if (data == null) throw const FormatException('获取房间信息失败');
      final token = (data['rtcToken'] ?? data['rtc_token'])?.toString() ?? '';
      final channel = (data['channel'] ?? data['channelId'])?.toString() ?? '';
      final uid = (data['uid'] as num?)?.toInt() ?? 0;
      final appId = data['appId']?.toString() ?? AgoraConstants.appId;
      if (token.isEmpty || channel.isEmpty || uid <= 0 || appId.isEmpty) {
        throw const FormatException('缺少通话参数，请重新匹配');
      }
      _peer =
          data['peer'] == null ? null : Map<String, dynamic>.from(data['peer']);
      widget.onPeerChanged?.call(_peerAvatar);
      unawaited(_loadRelationship());
      final engine = (widget.engineFactory ?? createAgoraRtcEngine)();
      _engine = engine;
      await CallBackgroundAudio.update(
          'matched:${identityHashCode(engine)}', true,
          title: '语音匹配通话中');
      await engine.initialize(RtcEngineContext(
          appId: appId, audioScenario: AudioScenarioType.audioScenarioMeeting));
      if (!_current(generation)) return;
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (conn, elapsed) {
            if (!_current(generation)) return;
            _joinTimeout?.cancel();
            unawaited(
                engine.setEnableSpeakerphone(_speakerOn).catchError((Object _) {
              if (mounted && _current(generation)) {
                showAppToast(context, '播放设备切换失败');
              }
            }));
            setState(() {
              _joined = true;
              _loading = false;
              _reconnecting = false;
            });
          },
          onUserJoined: (conn, uid, elapsed) {
            if (!_current(generation) || uid == conn.localUid) return;
            setState(() {
              _remoteUid = uid;
              _peerLeft = false;
            });
            _startCallTimer();
          },
          onUserOffline: (conn, uid, reason) {
            if (!_current(generation) || uid != _remoteUid) return;
            _callTimer?.cancel();
            setState(() {
              _remoteUid = null;
              _peerLeft = true;
            });
          },
          onConnectionStateChanged: (conn, state, reason) {
            if (!_current(generation)) return;
            if (state == ConnectionStateType.connectionStateFailed) {
              _fail(generation, '语音连接失败，请检查网络后重试');
            } else {
              setState(
                () => _reconnecting =
                    state != ConnectionStateType.connectionStateConnected,
              );
            }
          },
          onError: (err, msg) => _fail(generation, '语音连接异常，请重试（$err）'),
          onLocalAudioStateChanged: (_, state, reason) {
            if (state == LocalAudioStreamState.localAudioStreamStateFailed) {
              _fail(generation, '麦克风收音失败，请检查权限后重试');
            }
          },
          onRemoteAudioStateChanged: (_, __, state, reason, ___) {
            if (state == RemoteAudioState.remoteAudioStateFailed) {
              _fail(generation, '接收语音失败，请重新连接');
            }
          },
          onAudioRoutingChanged: (_) {
            if (_current(generation)) unawaited(_configureEchoControl(engine));
          },
          onTokenPrivilegeWillExpire: (conn, token) => _renewToken(generation),
          onRequestToken: (conn) => _renewToken(generation),
        ),
      );
      await engine.enableAudio();
      await engine.setChannelProfile(
        ChannelProfileType.channelProfileCommunication,
      );
      await configureRtcSpeech(engine);
      await engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
      await engine.adjustPlaybackSignalVolume(100);
      await engine.adjustRecordingSignalVolume(100);
      await engine.muteAllRemoteAudioStreams(false);
      await engine.enableLocalAudio(true);
      await engine.muteLocalAudioStream(_muted);
      if (!_current(generation)) return;
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          publishCameraTrack: false,
          autoSubscribeVideo: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      if (!_current(generation)) return;
      _statusTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkRoom(generation),
      );
    } on DioException catch (e) {
      final message = e.response?.data is Map
          ? e.response!.data['message']?.toString()
          : null;
      _fail(generation, message ?? '加入房间失败，请检查网络后重试');
    } on FormatException catch (e) {
      _fail(generation, e.message);
    } catch (_) {
      _fail(generation, '连接异常，请重试');
    }
  }

  Future<void> _renewToken(int generation) async {
    if (_renewing || !_current(generation)) return;
    _renewing = true;
    try {
      final res = await _scope.get(
        '/api/voice-room/join',
        queryParameters: {'room_id': widget.roomId},
      );
      if (!_current(generation)) return;
      final data = res.data['data'];
      final token = (data['rtcToken'] ?? data['rtc_token'])?.toString() ?? '';
      if (token.isEmpty) throw const FormatException();
      await _engine?.renewToken(token);
    } catch (_) {
      _fail(generation, '通话认证更新失败，请重试');
    } finally {
      _renewing = false;
    }
  }

  Future<void> _checkRoom(int generation) async {
    if (_polling || !_current(generation)) return;
    _polling = true;
    try {
      final res = await _scope.get(
        '/api/voice-room/status',
        queryParameters: {'room_id': widget.roomId},
      );
      if (_current(generation) && res.data['data']['status'] != 'ongoing') {
        _fail(generation, '对方已结束通话，请返回重新匹配');
      }
    } on DioException catch (e) {
      if ([401, 403, 404].contains(e.response?.statusCode)) {
        _fail(generation, '通话已结束，请返回重新匹配');
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    _generation++;
    _stopTimers();
    final release = _releaseEngine();
    widget.onClose?.call();
    try {
      await _scope.post(
        '/api/voice-room/leave',
        data: {'room_id': widget.roomId},
      );
    } catch (_) {}
    await release;
    await _resumeRoomAudio();
  }

  Future<void> _leave() async {
    await _finish();
    if (mounted) {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _configureEchoControl(RtcEngine engine) =>
      restoreRtcSpeechProcessing(engine);

  Future<void> _loadSelf() async {
    try {
      final response = await AccountProfileRequests.fetch(_scope);
      final data = response.data['data'];
      if (mounted && _scope.current && data is Map) {
        setState(() => _self = Map<String, dynamic>.from(data));
      }
    } catch (_) {}
  }

  String get _nickname =>
      (_peer?['nickname'] ?? _peer?['nickName'] ?? '对方').toString();
  String? get _peerAvatar =>
      (_peer?['avatarUrl'] ?? _peer?['avatar_url'])?.toString();

  Future<void> _confirmExit([BuildContext? dialogContext]) async {
    if (_confirmingExit || _leaving) return;
    _confirmingExit = true;
    final confirmed = await showDialog<bool>(
        context: dialogContext ?? context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('是否退出语音聊天？'),
              content: const Text('退出后将结束本次通话。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('继续通话')),
                FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('退出')),
              ],
            ));
    _confirmingExit = false;
    if (confirmed == true && mounted) await _leave();
    if (confirmed == false && mounted) widget.onMinimize?.call();
  }

  void _openProfile(int id) {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!(id);
    } else {
      Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => UserProfilePage(userId: id)));
    }
  }

  Future<void> _toggleMute() async {
    if (_engine == null || _audioControlBusy) return;
    _audioControlBusy = true;
    final target = !_muted;
    try {
      await _engine!.muteLocalAudioStream(target);
      if (mounted && !_leaving) setState(() => _muted = target);
    } catch (_) {
      if (mounted) showAppToast(context, '麦克风切换失败，请重试');
    } finally {
      _audioControlBusy = false;
    }
  }

  int? get _peerId => (_peer?['user_id'] ?? _peer?['userId']) is num
      ? ((_peer?['user_id'] ?? _peer?['userId']) as num).toInt()
      : null;

  Future<void> _loadRelationship() async {
    final id = _peerId;
    if (id == null) return;
    try {
      final response = await _scope.get('/api/community/user/$id/profile');
      if (!mounted || !_scope.current) return;
      final data = response.data['data'];
      if (data is Map) setState(() => _following = data['following'] == true);
    } catch (_) {}
  }

  Future<void> _followPeer() async {
    final id = _peerId;
    if (id == null || _relationshipBusy || !_scope.current) return;
    setState(() => _relationshipBusy = true);
    try {
      final response = await _scope.post('/api/community/user/$id/follow');
      if (!mounted || !_scope.current) return;
      final data = response.data['data'];
      if (data is! Map || data['following'] is! bool) {
        throw const FormatException();
      }
      setState(() => _following = data['following'] == true);
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '关注操作失败，请重试');
    } finally {
      if (mounted && _scope.current) setState(() => _relationshipBusy = false);
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_engine == null || _audioControlBusy) return;
    _audioControlBusy = true;
    final target = !_speakerOn;
    try {
      await _engine!.setEnableSpeakerphone(target);
      await _configureEchoControl(_engine!);
      if (mounted && !_leaving) setState(() => _speakerOn = target);
    } catch (_) {
      if (mounted) showAppToast(context, '播放设备切换失败，请重试');
    } finally {
      _audioControlBusy = false;
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_joined || _remoteUid == null || _reconnecting) return;
      setState(() => _callSeconds += 1);
    });
  }

  String get _callDurationText {
    final m = (_callSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    unawaited(_finish());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_confirmExit());
        },
        child: _buildBody(context),
      );

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('语音通话', style: AppTextStyles.titleMedium),
          leading: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: _confirmExit),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('语音通话', style: AppTextStyles.titleMedium),
          leading: IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: _confirmExit),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textHint,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton(onPressed: _leave, child: const Text('返回')),
              ],
            ),
          ),
        ),
      );
    }

    final selfId = (_self?['userId'] ?? _self?['user_id']) as num?;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FCFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmExit),
        title: Text(_nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium),
        actions: [
          if (_peerId != null)
            TextButton(
                onPressed: _relationshipBusy ? null : _followPeer,
                child: Text(_following ? '已关注' : '关注')),
          if (widget.onMinimize != null)
            IconButton(
                tooltip: '浮窗',
                onPressed: widget.onMinimize,
                icon: const Icon(Icons.fullscreen_exit_rounded)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
              child: Center(
                  child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(children: [
              Expanded(
                  child: _participant(
                      '我',
                      (_self?['avatarUrl'] ?? _self?['avatar_url'])?.toString(),
                      selfId == null
                          ? null
                          : () => _openProfile(selfId.toInt()))),
              Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Text(
                    _peerLeft
                        ? '对方已离开或掉线'
                        : (_reconnecting
                            ? '网络中断，正在重连…'
                            : (_joined && _remoteUid != null
                                ? '通话中 $_callDurationText'
                                : '等待对方接通…')),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ])),
              Expanded(
                  child: _participant(_nickname, _peerAvatar,
                      _peerId == null ? null : () => _openProfile(_peerId!))),
            ]),
          ))),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                        _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        _speakerOn ? '免提开' : '免提关',
                        _speakerOn
                            ? AppColors.primary.withValues(alpha: .15)
                            : const Color(0xFFF2F2F2),
                        _speakerOn ? AppColors.primary : AppColors.textPrimary,
                        _toggleSpeaker),
                    _buildActionButton(
                        _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        _muted ? '开麦' : '闭麦',
                        _muted
                            ? AppColors.primary.withValues(alpha: .15)
                            : const Color(0xFFF2F2F2),
                        _muted ? AppColors.primary : AppColors.textPrimary,
                        _toggleMute),
                    _buildActionButton(Icons.call_end_rounded, '挂断',
                        AppColors.primary, Colors.white, _confirmExit),
                  ])),
        ]),
      ),
    );
  }

  Widget _participant(String name, String? avatar, VoidCallback? onTap) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
              button: true,
              label: '$name的主页',
              child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withValues(alpha: .15),
                      backgroundImage: avatar?.isNotEmpty == true
                          ? NetworkImage(avatar!)
                          : null,
                      child: avatar?.isNotEmpty == true
                          ? null
                          : const Icon(Icons.person,
                              size: 40, color: AppColors.primary)))),
          const SizedBox(height: 16),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium),
        ],
      );

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
