import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_host.dart';

void main() {
  final controller = VoiceRoomOverlayController.instance;

  tearDown(() {
    final roomId = controller.roomId;
    if (roomId != null) controller.didClose(roomId);
  });

  test('同一时间只允许一个房间并可缩小恢复', () {
    expect(controller.open(101), isTrue);
    expect(controller.open(202), isFalse);

    controller.minimize();
    expect(controller.minimized, isTrue);

    controller.restore();
    expect(controller.minimized, isFalse);
    expect(controller.roomId, 101);
  });

  test('悬浮态可调用麦克风和退出回调', () async {
    var muteCalls = 0;
    var closeCalls = 0;
    var suspendCalls = 0;
    var resumeCalls = 0;
    expect(controller.open(303), isTrue);
    controller.attach(
      303,
      VoiceRoomOverlayCallbacks(
        onClose: () async {
          closeCalls += 1;
        },
        onToggleMute: () async {
          muteCalls += 1;
        },
        onSuspendAudio: () async {
          suspendCalls += 1;
        },
        onResumeAudio: () async {
          resumeCalls += 1;
        },
      ),
    );

    controller.updateSnapshot(
      303,
      const VoiceRoomMiniSnapshot(
        title: '测试房间',
        subtitle: '麦克风已开启',
        canMute: true,
      ),
    );
    await controller.toggleMute();
    expect(await controller.suspendAudio(), isTrue);
    await controller.resumeAudio();
    await controller.requestClose();

    expect(controller.snapshot.title, '测试房间');
    expect(muteCalls, 1);
    expect(suspendCalls, 1);
    expect(resumeCalls, 1);
    expect(closeCalls, 1);
  });

  test('相同悬浮快照不会重复通知重建', () {
    var notifications = 0;
    void listener() => notifications += 1;
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));

    expect(controller.open(304), isTrue);
    final afterOpen = notifications;
    const snapshot = VoiceRoomMiniSnapshot(
      title: '测试房间',
      subtitle: '免费收听中',
      avatarUrl: 'avatar',
    );
    controller.updateSnapshot(304, snapshot);
    expect(notifications, afterOpen + 1);

    controller.updateSnapshot(304, snapshot);
    expect(notifications, afterOpen + 1);
  });

  test('页面回调丢失时关闭请求仍会清理孤儿悬浮窗', () async {
    expect(controller.open(305), isTrue);
    await controller.requestClose();
    expect(controller.hasActiveRoom, isFalse);
  });

  testWidgets('房间缩成浮窗后系统返回可退出底层二级页', (tester) async {
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [voiceRoomBackNavigatorObserver],
        builder: (context, child) => VoiceRoomOverlayHost(
            child: child!,
            roomBuilder: (_) => const Scaffold(body: Text('floating-room'))),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('open-page'),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const Scaffold(
                                body: Text('history-page')))))))));
    await tester.tap(find.text('open-page'));
    await tester.pumpAndSettle();
    controller.open(505);
    controller.minimize();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('history-page'), findsNothing);
    expect(controller.roomId, 505);
    expect(controller.minimized, isTrue);
    controller.didClose(505);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('语音房打开时系统返回键只缩小房间而不退出应用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [voiceRoomBackNavigatorObserver],
        builder: (context, child) => VoiceRoomOverlayHost(
          child: child ?? const SizedBox.shrink(),
          roomBuilder: (_) => const Scaffold(body: Text('语音房')),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('底层二级页')),
                ),
              ),
              child: const Text('进入二级页'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('进入二级页'));
    await tester.pumpAndSettle();
    expect(find.text('底层二级页'), findsOneWidget);

    expect(controller.open(404), isTrue);
    await tester.pump();
    expect(controller.minimized, isFalse);

    final handled = await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, isTrue);
    expect(controller.minimized, isTrue);
    expect(find.text('底层二级页'), findsOneWidget);

    controller.didClose(404);
    await tester.pump();
  });
}
