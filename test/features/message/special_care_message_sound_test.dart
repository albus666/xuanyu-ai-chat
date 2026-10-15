import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/special_care_message_sound_host.dart';

Map<String, Object> conversation(
  int message, {
  bool incoming = true,
  bool enabled = true,
  bool mute = false,
  String tone = 'gentle',
}) =>
    {
      'conversationId': 1,
      'lastMessageId': message,
      'lastMessageIncoming': incoming,
      'specialCare': enabled,
      'mute': mute,
      'specialCareSound': tone,
      'unreadCount': 0,
    };

void main() {
  test('不播放历史消息，已读的新来信播放一次，自己的消息不播放', () {
    final tracker = SpecialCareMessageTracker();
    expect(tracker.observe([conversation(10)]), isEmpty);
    expect(tracker.observe([conversation(11)]), ['gentle']);
    expect(tracker.observe([conversation(11)]), isEmpty);
    expect(tracker.observe([conversation(12, incoming: false)]), isEmpty);
    expect(tracker.observe([conversation(13, tone: 'clear')]), ['clear']);
  });

  test('免打扰、未关心、静音音效和勿扰时段不会补播', () {
    final tracker = SpecialCareMessageTracker();
    tracker.observe([conversation(1)]);
    expect(tracker.observe([conversation(2, mute: true)]), isEmpty);
    expect(tracker.observe([conversation(3, enabled: false)]), isEmpty);
    expect(tracker.observe([conversation(4, tone: 'silent')]), isEmpty);
    expect(tracker.observe([conversation(5)], quiet: true), isEmpty);
    expect(tracker.observe([conversation(5)]), isEmpty);
    expect(tracker.observe([conversation(6)]), ['gentle']);
  });

  test('勿扰时间支持跨午夜并正确处理结束边界', () {
    expect(messageQuietHours(DateTime(2026, 10, 11, 23), '22:00', '08:00'),
        isTrue);
    expect(
        messageQuietHours(DateTime(2026, 10, 11, 7), '22:00', '08:00'), isTrue);
    expect(messageQuietHours(DateTime(2026, 10, 11, 8), '22:00', '08:00'),
        isFalse);
  });
}
