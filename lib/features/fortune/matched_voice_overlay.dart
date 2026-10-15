import 'dart:async';
import '../../shared/widgets/draggable_call_bubble.dart';
import '../main/main_shell_page.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../core/network/api_client.dart';
import 'voice_room_page.dart';
import '../community/user_profile_page.dart';
import '../consultation/voice_room_overlay_controller.dart';

class MatchedVoiceOverlay extends ChangeNotifier {
  static final instance = MatchedVoiceOverlay();
  String? roomId;
  String? peerAvatar;
  bool minimized = false;
  Completer<void>? _completion;
  Future<void> Function()? handleBack;
  Future<void> Function(BuildContext)? confirmEnd;

  Future<void> open(String id) {
    if (roomId != null && roomId != id) {
      throw StateError('请先结束当前语音匹配通话');
    }
    if (roomId == id) {
      restore();
      return _completion!.future;
    }
    roomId = id;
    minimized = false;
    _completion = Completer<void>();
    VoiceRoomOverlayController.instance.minimize();
    notifyListeners();
    return _completion!.future;
  }

  void minimize() {
    minimized = true;
    notifyListeners();
  }

  void restore() {
    minimized = false;
    notifyListeners();
  }

  void updatePeer(String? avatar) {
    peerAvatar = avatar;
    notifyListeners();
  }

  void close() {
    if (roomId == null) return;
    roomId = null;
    handleBack = null;
    confirmEnd = null;
    peerAvatar = null;
    minimized = false;
    _completion?.complete();
    _completion = null;
    notifyListeners();
  }
}

class MatchedVoiceOverlayHost extends StatefulWidget {
  const MatchedVoiceOverlayHost(
      {super.key,
      required this.child,
      required this.rootNavigatorKey,
      this.engineFactory,
      this.requestMicrophone});
  final Widget child;
  final GlobalKey<NavigatorState> rootNavigatorKey;
  final RtcEngine Function()? engineFactory;
  final Future<bool> Function()? requestMicrophone;
  @override
  State<MatchedVoiceOverlayHost> createState() =>
      _MatchedVoiceOverlayHostState();
}

class _MatchedVoiceOverlayHostState extends State<MatchedVoiceOverlayHost> {
  final controller = MatchedVoiceOverlay.instance;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  String? visibleSessionId;
  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (controller.roomId != null) controller.close();
  }

  Future<void> _back() async {
    await controller.handleBack?.call();
  }

  void _openProfile(int id) {
    final navigator = widget.rootNavigatorKey.currentState;
    if (navigator == null) return;
    // Keep the call visible until the profile's first frame is ready.
    navigator.push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => UserProfilePage(userId: id)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.roomId != null) controller.minimize();
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    controller.handleBack = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final active = controller.roomId != null;
          if (visibleSessionId != controller.roomId) {
            visibleSessionId = controller.roomId;
            navigatorKey = GlobalKey<NavigatorState>();
          }
          return PopScope(
            canPop: !active || controller.minimized,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && active) _back();
            },
            child: Stack(fit: StackFit.expand, children: [
              widget.child,
              if (active)
                Positioned.fill(
                    child: Offstage(
                  offstage: controller.minimized,
                  child: KeyedSubtree(
                    key: ValueKey('matched-call-${controller.roomId}'),
                    child: HeroControllerScope.none(
                        child: Navigator(
                      key: navigatorKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => VoiceRoomPage(
                                engineFactory: widget.engineFactory,
                                requestMicrophone: widget.requestMicrophone,
                                roomId: controller.roomId!,
                                onMinimize: () {
                                  controller.minimize();
                                  MainShellPage.showHome();
                                  widget.rootNavigatorKey.currentState
                                      ?.popUntil((route) => route.isFirst);
                                },
                                onEndReady: (callback) =>
                                    controller.confirmEnd = callback,
                                onClose: controller.close,
                                onPeerChanged: controller.updatePeer,
                                onOpenProfile: _openProfile,
                                onBackReady: (callback) =>
                                    controller.handleBack = callback,
                              )),
                    )),
                  ),
                )),
              if (active && controller.minimized)
                DraggableCallBubble(
                  onTap: controller.restore,
                  onDismiss: () async {
                    final context =
                        widget.rootNavigatorKey.currentState?.overlay?.context;
                    if (context != null) {
                      await controller.confirmEnd?.call(context);
                    }
                  },
                  child: Material(
                    color: const Color(0xFF16BEBB),
                    shape: const CircleBorder(),
                    elevation: 6,
                    child: SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(alignment: Alignment.center, children: [
                          CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFF16BEBB),
                              backgroundImage:
                                  controller.peerAvatar?.isNotEmpty == true
                                      ? NetworkImage(controller.peerAvatar!)
                                      : null,
                              child: controller.peerAvatar?.isNotEmpty == true
                                  ? null
                                  : const Icon(Icons.phone_in_talk,
                                      color: Colors.white)),
                          const Positioned(
                              right: 0,
                              bottom: 0,
                              child: Icon(Icons.phone_in_talk,
                                  color: Colors.white, size: 18)),
                        ])),
                  ),
                ),
            ]),
          );
        },
      );
}

/// 将语音房返回拦截注册到根 Navigator 当前路由，覆盖不同 Android 返回实现。
class MatchedVoiceBackNavigatorObserver extends NavigatorObserver {
  MatchedVoiceBackNavigatorObserver()
      : _entry = _MatchedVoiceRootPopEntry(MatchedVoiceOverlay.instance);

  final _MatchedVoiceRootPopEntry _entry;
  ModalRoute<Object?>? _currentRoute;

  void _track(Route<dynamic>? route) {
    final next = route is ModalRoute<Object?> ? route : null;
    if (identical(next, _currentRoute)) return;
    _currentRoute?.unregisterPopEntry(_entry);
    _currentRoute = next;
    _currentRoute?.registerPopEntry(_entry);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _currentRoute)) _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, _currentRoute) || newRoute != null) {
      _track(newRoute);
    }
  }
}

class _MatchedVoiceRootPopEntry extends PopEntry<Object?> {
  _MatchedVoiceRootPopEntry(this.controller) {
    controller.addListener(_sync);
    _sync();
  }

  final MatchedVoiceOverlay controller;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);

  void _sync() {
    canPopNotifier.value = !(controller.roomId != null) || controller.minimized;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && (controller.roomId != null) && !controller.minimized) {
      unawaited(controller.handleBack?.call());
    }
  }
}
