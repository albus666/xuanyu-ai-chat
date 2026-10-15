import '../../shared/widgets/call_back_choice.dart';
import 'dart:async';
import 'package:get/get.dart';
import '../../shared/widgets/draggable_call_bubble.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import 'consultation_call_page.dart';
import 'voice_room_overlay_controller.dart';

class ConsultationCallOverlay extends ChangeNotifier {
  static final instance = ConsultationCallOverlay();
  int? sessionId;
  bool minimized = false;
  bool ended = false;
  Completer<void>? _completion;
  Future<void> Function()? handleBack;
  Future<void> Function(BuildContext)? confirmEnd;

  Future<void> open(int id) {
    if (sessionId != null && sessionId != id && !ended) {
      throw StateError('请先结束当前私人专线');
    }
    if (sessionId == id) {
      restore();
      return _completion!.future;
    }
    if (sessionId != null) close();
    sessionId = id;
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
    if (sessionId == null) return;
    confirmEnd = null;
    sessionId = null;
    ended = false;
    minimized = false;
    _completion?.complete();
    _completion = null;
    notifyListeners();
  }
}

class ConsultationCallOverlayHost extends StatefulWidget {
  const ConsultationCallOverlayHost({super.key, required this.child});
  final Widget child;
  @override
  State<ConsultationCallOverlayHost> createState() =>
      _ConsultationCallOverlayHostState();
}

class _ConsultationCallOverlayHostState
    extends State<ConsultationCallOverlayHost> {
  final controller = ConsultationCallOverlay.instance;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  int? visibleSessionId;
  Future<void> Function()? _pageBack;
  @override
  void initState() {
    super.initState();
    controller.handleBack = _back;
    apiSessionChanges.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (controller.sessionId != null) controller.close();
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
          final active = controller.sessionId != null;
          if (visibleSessionId != controller.sessionId) {
            visibleSessionId = controller.sessionId;
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
                    key: ValueKey('private-call-${controller.sessionId}'),
                    child: HeroControllerScope.none(
                        child: Navigator(
                      key: navigatorKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => ConsultationCallPage(
                                sessionId: controller.sessionId!,
                                onMinimize: () =>
                                    minimizeCallToHome(controller.minimize),
                                onBackReady: (callback) => _pageBack = callback,
                                onClose: controller.close,
                                onEndReady: (callback) =>
                                    controller.confirmEnd = callback,
                                onSessionEnded: () {
                                  controller.close();
                                },
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
class ConsultationBackNavigatorObserver extends NavigatorObserver {
  ConsultationBackNavigatorObserver()
      : _entry = _ConsultationRootPopEntry(ConsultationCallOverlay.instance);

  final _ConsultationRootPopEntry _entry;
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

class _ConsultationRootPopEntry extends PopEntry<Object?> {
  _ConsultationRootPopEntry(this.controller) {
    controller.addListener(_sync);
    _sync();
  }

  final ConsultationCallOverlay controller;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);

  void _sync() {
    canPopNotifier.value =
        !(controller.sessionId != null) || controller.minimized;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && (controller.sessionId != null) && !controller.minimized) {
      unawaited(controller.handleBack?.call());
    }
  }
}
