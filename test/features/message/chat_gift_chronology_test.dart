import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/chat_page.dart';

void main() {
  test('历史礼物错误时区不将旧消息放到最新位置，待发送消息仍在末尾', () {
    final messages = <Map<String, dynamic>>[
      {'id': 0, 'createdAt': '2026-10-10T12:02:00Z'},
      {'id': 101, 'type': 'text', 'createdAt': '2026-10-10T12:00:00Z'},
      {'id': 99, 'type': 'gift', 'createdAt': '2026-10-10T19:59:00Z'},
      {'id': 102, 'type': 'text', 'createdAt': '2026-10-10T12:01:00Z'},
    ]..sort(compareChatMessages);
    expect(messages.map((m) => m['id']), [99, 101, 102, 0]);
  });
}
