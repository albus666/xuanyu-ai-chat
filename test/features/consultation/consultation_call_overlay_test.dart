import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/consultation_call_overlay.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';

void main() {
  test('旧专线结束后可以进入新的专线', () async {
    final calls = ConsultationCallOverlay();
    final old = calls.open(42);
    calls.ended = true;
    final next = calls.open(43);
    await old;
    expect(calls.sessionId, 43);
    expect(calls.ended, isFalse);
    calls.close();
    await next;
    calls.dispose();
  });
  test('私人专线缩小恢复不结束服务，同一订单共享完成状态', () async {
    final calls = ConsultationCallOverlay();
    final room = VoiceRoomOverlayController.instance;
    room.open(901);
    addTearDown(() => room.didClose(901));
    var completed = false;
    final first = calls.open(42);
    first.then((_) => completed = true);
    expect(room.minimized, isTrue);
    calls.minimize();
    expect(calls.sessionId, 42);
    final restored = calls.open(42);
    expect(identical(first, restored), isTrue);
    expect(calls.minimized, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(() => calls.open(43), throwsStateError);
    calls.close();
    await first;
    expect(completed, isTrue);
    expect(calls.sessionId, isNull);
    calls.dispose();
  });
}
