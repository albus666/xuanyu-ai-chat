import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final room = VoiceRoomOverlayController.instance;
  setUp(() =>
      SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7}));
  tearDown(() {
    if (room.roomId != null) room.didClose(room.roomId!);
  });
  test('取消退出语音房时不能切走账号', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthState(prefs);
    room.open(42);
    var closed = false;
    room.attach(
        42,
        VoiceRoomOverlayCallbacks(
          onClose: () async {
            closed = true;
          },
          onToggleMute: () async {},
          onSuspendAudio: () async {},
          onResumeAudio: () async {},
        ));
    await auth.prepareAddAccount();
    expect(closed, isTrue);
    expect(prefs.getInt(AppConstants.keyUserId), 7);
    expect(room.hasActiveRoom, isTrue);
  });
  test('退出语音房成功后才清除账号', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthState(prefs);
    room.open(42);
    room.attach(
        42,
        VoiceRoomOverlayCallbacks(
          onClose: () async {
            expect(prefs.getInt(AppConstants.keyUserId), 7);
            room.didClose(42);
          },
          onToggleMute: () async {},
          onSuspendAudio: () async {},
          onResumeAudio: () async {},
        ));
    await auth.prepareAddAccount();
    expect(room.hasActiveRoom, isFalse);
    expect(prefs.getInt(AppConstants.keyUserId), isNull);
  });
  testWidgets('会话失效后旧账号的悬浮房间不再驻留', (tester) async {
    setupApiClientToken('synthetic-room-session');
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => VoiceRoomOverlayHost(
        roomBuilder: (_) => const Scaffold(body: Text('隔离测试房间')),
        child: child!,
      ),
      home: const Scaffold(),
    ));
    room.open(42);
    await tester.pumpAndSettle();
    setupApiClientToken(null);
    await tester.pumpAndSettle();
    expect(room.hasActiveRoom, isFalse);
    expect(find.text('隔离测试房间'), findsNothing);
  });
}
