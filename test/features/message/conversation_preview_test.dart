import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/message/conversation_preview.dart';

void main() {
  test('派对邀请字段顺序和空格不同也不会显示原始 JSON', () {
    expect(conversationPreview('{"roomId":134,"roomNo":"R123"}'), '邀请你加入派对');
    expect(
        conversationPreview('{ "roomNo": "R123", "roomId": 134 }'), '邀请你加入派对');
    expect(conversationPreview('{"roomId":118,"roomNo":"R1009...'), '邀请你加入派对');
    expect(conversationPreview('{"postId": 2}'), '[帖子]');
    expect(conversationPreview('你好'), '你好');
  });
  test('通话文案仅保留结果，去掉通话类型和发起方', () {
    expect(callMessageLabel('【视频通话】发起方已取消'), '已取消');
    expect(callMessageLabel('【语音通话】 发起方'), '');
  });
}
