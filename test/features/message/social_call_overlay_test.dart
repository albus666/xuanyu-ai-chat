import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/social_call_overlay.dart';

void main() {
  test('缩小与恢复共享通话，关闭清空浮窗并允许下一通', () async {
    final overlay = SocialCallOverlay();
    final first = overlay.open(12, call: {'status': 'accepted'});
    overlay.minimize();
    expect(overlay.callId, 12);
    expect(overlay.minimized, isTrue);
    expect(identical(overlay.open(12), first), isTrue);
    expect(overlay.minimized, isFalse);
    overlay.close();
    await first;
    expect(overlay.callId, isNull);
    expect(overlay.minimized, isFalse);
    final next = overlay.open(13);
    overlay.close();
    await next;
    overlay.dispose();
  });

  test('已结束通话不能重新生成残留浮窗', () async {
    final overlay = SocialCallOverlay();
    for (final status in ['ended', 'cancelled', 'rejected', 'missed']) {
      await overlay.open(12, call: {'status': status});
      expect(overlay.callId, isNull);
    }
    overlay.dispose();
  });
}
