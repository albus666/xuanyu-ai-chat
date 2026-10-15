import '../../shared/widgets/call_back_choice.dart';
import 'dart:async';
import 'package:get/get.dart';
import '../../shared/widgets/draggable_call_bubble.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import 'social_call_page.dart';
import '../consultation/voice_room_overlay_controller.dart';

class SocialCallOverlay extends ChangeNotifier {
  static final instance = SocialCallOverlay();
  int? callId;
  Map<String, dynamic>? initialCall;
  bool minimized = false;
  bool ended = false;
  Completer<void>? _completion;
  Future<void> Function()? handleBack;
  Future<void> Function(BuildContext)? confirmEnd;

  Future<void> open(int id, {Map<String, dynamic>? call}) {
    if (const {'ended', 'cancelled', 'rejected', 'missed'}
        .contains(call?['status'])) {
      return Future<void>.value();
    }
    if (callId != null && callId != id && !ended) {
      throw StateError('请先结束当前聊天通话');
    }
    if (callId == id) {
      restore();
      return _completion!.future;
    }
    if (callId != null) close();
    callId = id;
    initialCall = call;
    ended = false;
    minimized = false;
    _completion = Completer<void>();
    VoiceRoomOverlayController.instance.minimize();
    notifyListeners();
    return _completion!.future;
  }

  void minimize() {
    if (ended) {
      close();
      return;
    }
    minimized = true;
    notifyListeners();
  }

  void restore() {
    minimized = false;
    notifyListeners();
  }

  void close() {
    if (callId == null) return;
    confirmEnd = null;
    callId = null;
    initialCall = null;
    ended = false;
    minimized = false;
    _completion?.complete();
    _completion = null;
    notifyListeners();
  }
}

class SocialCallOverlayHost extends StatefulWidget {
  const SocialCallOverlayHost({super.key, required this.child});
  final Widget child;
  @override
  State<SocialCallOverlayHost> createState() => _SocialCallOverlayHostState();
}

class _SocialCallOverlayHostState extends State<SocialCallOverlayHost> {
  final controller = SocialCallOverlay.instance;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  int? visibleCallId;
  Future<void> Function()? _pageBack;
  @override
  void initState() {
    super.initState();
    controller.handleBack = _back;
    apiSessionChanges.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (controller.callId != null) controller.close();
  }

  Future<void> _back() async {
    if (controller.minimized) {
      controller.restore();
      return;
    }
    if (navigatorKey.currentState?.canPop() == true) {
      await navigatorKey.currentState!.maybePop();
    } else {
      await _pageBack?.call();
    }
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
          final active = controller.callId != null;
          if (visibleCallId != controller.callId) {
            visibleCallId = controller.callId;
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
                    key: ValueKey('social-call-${controller.callId}'),
                    child: HeroControllerScope.none(
                        child: Navigator(
                      key: navigatorKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => SocialCallPage(
                                callId: controller.callId!,
                                initialCall: controller.initialCall,
                                onMinimize: () =>
                                    minimizeCallToHome(controller.minimize),
                                onBackReady: (callback) => _pageBack = callback,
                                onClose: controller.close,
                                onEndReady: (callback) =>
                                    controller.confirmEnd = callback,
                                onSessionEnded: controller.close,
                              )),
                    )),
                  ),
                )),
              if (active && controller.minimized)
                DraggableCallBubble(
                  onTap: controller.restore,
                  onDismiss: () async {
                    final context = Get.key.currentState?.overlay?.context;
                    if (context != null) {
                      await controller.confirmEnd?.call(context);
                    }
                  },
                  child: const Material(
                    color: Color(0xFF16BEBB),
                    shape: CircleBorder(),
                    elevation: 6,
                    child: SizedBox(
                        width: 60,
                        height: 60,
                        child: Center(
                            child: Icon(Icons.phone_in_talk,
                                color: Colors.white, size: 28))),
                  ),
                ),
            ]),
          );
        },
      );
}

/// 将语音房返回拦截注册到根 Navigator 当前路由，覆盖不同 Android 返回实现。
class SocialCallBackNavigatorObserver extends NavigatorObserver {
  SocialCallBackNavigatorObserver()
      : _entry = _SocialRootPopEntry(SocialCallOverlay.instance);

  final _SocialRootPopEntry _entry;
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

class _SocialRootPopEntry extends PopEntry<Object?> {
  _SocialRootPopEntry(this.controller) {
    controller.addListener(_sync);
    _sync();
  }

  final SocialCallOverlay controller;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);

  void _sync() {
    canPopNotifier.value = !(controller.callId != null) || controller.minimized;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && (controller.callId != null) && !controller.minimized) {
      unawaited(controller.handleBack?.call());
    }
  }
}
