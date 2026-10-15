import 'dart:convert';

String conversationPreview(String raw) {
  if (raw.isEmpty) return '暂无消息';
  if (RegExp(r'''^\s*\{\s*["'](?:roomId|roomNo)["']\s*:''').hasMatch(raw)) {
    return '邀请你加入派对';
  }
  try {
    final data = jsonDecode(raw);
    if (data is Map) {
      if (data.containsKey('roomId') || data.containsKey('roomNo')) {
        return '邀请你加入派对';
      }
      if (data.containsKey('postId')) return '[帖子]';
      if (data.containsKey('userId')) return '[个人主页]';
      if (data.containsKey('giftCode')) return '[礼物]';
    }
  } catch (_) {}
  return raw;
}

String callMessageLabel(String raw) => raw
    .replaceFirst(RegExp(r'^【(?:语音|视频)通话】\s*'), '')
    .replaceAll('发起方', '')
    .trim();
