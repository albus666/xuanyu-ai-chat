import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import 'voice_plaza_room_page.dart';
import 'voice_room_overlay_controller.dart';

final VoiceRoomBackNavigatorObserver voiceRoomBackNavigatorObserver =
    VoiceRoomBackNavigatorObserver();

/// 将语音房返回拦截注册到根 Navigator 当前路由，覆盖不同 Android 返回实现。
class VoiceRoomBackNavigatorObserver extends NavigatorObserver {
  VoiceRoomBackNavigatorObserver()
      : _entry = _VoiceRoomRootPopEntry(VoiceRoomOverlayController.instance);

  final _VoiceRoomRootPopEntry _entry;
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

class _VoiceRoomRootPopEntry extends PopEntry<Object?> {
  _VoiceRoomRootPopEntry(this.controller) {
    controller.addListener(_sync);
    _sync();
  }

  final VoiceRoomOverlayController controller;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);

  void _sync() {
    canPopNotifier.value = !controller.hasActiveRoom || controller.minimized;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && controller.hasActiveRoom && !controller.minimized) {
      unawaited(controller.handleSystemBack());
    }
  }
}

/// 放在根 Navigator 之上，让语音房缩小后仍能在 App 内持续播放。
class VoiceRoomOverlayHost extends StatefulWidget {
  const VoiceRoomOverlayHost({
    super.key,
    required this.child,
    this.roomBuilder,
  });

  final Widget child;
  final Widget Function(int roomId)? roomBuilder;

  @override
  State<VoiceRoomOverlayHost> createState() => _VoiceRoomOverlayHostState();
}

class _VoiceRoomOverlayHostState extends State<VoiceRoomOverlayHost> {
  final _controller = VoiceRoomOverlayController.instance;
  final _roomNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _controller.attachSystemBackHandler(this, _handleSystemBack);
    apiSessionChanges.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    // 登录失效也必须释放旧房间，不能将旧账号音频连接留给新会话。
    final roomId = _controller.roomId;
    if (roomId != null) _controller.didClose(roomId);
  }

  @override
  void dispose() {
    _controller.detachSystemBackHandler(this);
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _handleSystemBack() async {
    if (_controller.minimized) {
      final rootNavigator = Get.key.currentState;
      if (rootNavigator != null && rootNavigator.canPop()) {
        rootNavigator.pop();
      } else {
        _controller.restore();
      }
      return;
    }
    final handled = await _roomNavigatorKey.currentState?.maybePop() ?? false;
    if (!handled && _controller.hasActiveRoom && !_controller.minimized) {
      _controller.minimize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final active = _controller.hasActiveRoom;
        return PopScope(
          canPop: !active || _controller.minimized,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && active && !_controller.minimized) {
              _handleSystemBack();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (active)
                Positioned.fill(
                  child: Offstage(
                    offstage: _controller.minimized,
                    child: KeyedSubtree(
                      key: ValueKey(_controller.generation),
                      child: HeroControllerScope.none(
                        child: Navigator(
                          key: _roomNavigatorKey,
                          onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (_) =>
                                widget.roomBuilder?.call(_controller.roomId!) ??
                                VoicePlazaRoomPage(
                                  roomId: _controller.roomId!,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (active && _controller.minimized)
                Positioned.fill(
                  child: _DraggableMiniRoom(controller: _controller),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 将拖动状态隔离在悬浮层，拖动时不重建背后的房间 Navigator，避免卡顿。
class _DraggableMiniRoom extends StatefulWidget {
  const _DraggableMiniRoom({required this.controller});

  final VoiceRoomOverlayController controller;

  @override
  State<_DraggableMiniRoom> createState() => _DraggableMiniRoomState();
}

class _DraggableMiniRoomState extends State<_DraggableMiniRoom>
    with SingleTickerProviderStateMixin {
  static const _miniWidth = 58.0;
  static const _miniHeight = 58.0;
  static const _closeHeight = 104.0;

  final ValueNotifier<Offset?> _position = ValueNotifier<Offset?>(null);
  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  bool _dragging = false;
  bool _overCloseTarget = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _snapAnimation;
        if (animation != null) _position.value = animation.value;
      });
  }

  @override
  void dispose() {
    _snapController.dispose();
    _position.dispose();
    super.dispose();
  }

  Offset _clamp(Offset value, BoxConstraints constraints) => Offset(
        value.dx.clamp(
            8.0,
            (constraints.maxWidth - _miniWidth - 8)
                .clamp(8.0, double.infinity)),
        value.dy.clamp(
            8.0,
            (constraints.maxHeight - _miniHeight - 8)
                .clamp(8.0, double.infinity)),
      );

  Future<void> _close() async {
    widget.controller.restore();
    await Future<void>.delayed(Duration.zero);
    await widget.controller.requestClose();
  }

  void _snapToSide(Offset from, BoxConstraints constraints) {
    final right = constraints.maxWidth - _miniWidth - 10;
    final target = _clamp(
      Offset(from.dx + _miniWidth / 2 < constraints.maxWidth / 2 ? 10 : right,
          from.dy),
      constraints,
    );
    _snapAnimation = Tween<Offset>(begin: from, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bottomSafe = MediaQuery.paddingOf(context).bottom;
      final initial = Offset(
        constraints.maxWidth - _miniWidth - 12,
        constraints.maxHeight - _miniHeight - bottomSafe - 74,
      );
      return Stack(children: [
        if (_dragging)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _closeHeight + bottomSafe,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _overCloseTarget
                      ? const [Color(0xFFF05D55), Color(0xFFD93C3C)]
                      : const [Color(0xFFE96B64), Color(0xFFD94B47)],
                ),
              ),
              padding: EdgeInsets.only(bottom: bottomSafe),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _overCloseTarget
                        ? Icons.close_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.controller.snapshot.paidActive
                        ? '松手结束连线并停止计费'
                        : '拖到这里退出房间',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ValueListenableBuilder<Offset?>(
          valueListenable: _position,
          child: RepaintBoundary(
            child: _MiniRoomCard(
              snapshot: widget.controller.snapshot,
            ),
          ),
          builder: (context, rawPosition, child) {
            final position = _clamp(rawPosition ?? initial, constraints);
            return Positioned(
              left: position.dx,
              top: position.dy,
              width: _miniWidth,
              height: _miniHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.controller.restore,
                onPanStart: (_) {
                  _snapController.stop();
                  _position.value = position;
                  setState(() {
                    _dragging = true;
                    _overCloseTarget = false;
                  });
                },
                onPanUpdate: (details) {
                  // 始终在最新位置上累加位移，不依赖上一帧 build 捕获的旧位置。
                  final base = _position.value ?? position;
                  final next = _clamp(base + details.delta, constraints);
                  _position.value = next;
                  final overTarget = next.dy + _miniHeight >=
                      constraints.maxHeight - bottomSafe - _closeHeight;
                  if (overTarget != _overCloseTarget) {
                    setState(() => _overCloseTarget = overTarget);
                  }
                },
                onPanCancel: () {
                  final current = _position.value ?? position;
                  setState(() {
                    _dragging = false;
                    _overCloseTarget = false;
                  });
                  _snapToSide(current, constraints);
                },
                onPanEnd: (_) {
                  final current = _position.value ?? position;
                  final shouldClose = _overCloseTarget;
                  setState(() {
                    _dragging = false;
                    _overCloseTarget = false;
                  });
                  if (shouldClose) {
                    _close();
                  } else {
                    _snapToSide(current, constraints);
                  }
                },
                child: child,
              ),
            );
          },
        ),
      ]);
    });
  }
}

class _MiniRoomCard extends StatelessWidget {
  const _MiniRoomCard({required this.snapshot});

  final VoiceRoomMiniSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final avatar = snapshot.avatarUrl;
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xF20B3650),
              shape: BoxShape.circle,
              border: Border.all(
                color: snapshot.paidActive
                    ? const Color(0xFFE4C57E)
                    : const Color(0xFF37D4CB),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 10),
              ],
            ),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: const Color(0xFF123E52),
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? const Icon(Icons.graphic_eq_rounded,
                      color: AppColors.primary, size: 24)
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: snapshot.muted
                    ? const Color(0xFFE06C67)
                    : const Color(0xFF14BDB8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(
                snapshot.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
