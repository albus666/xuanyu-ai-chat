/// The server independently enforces ownership and the two-minute window.
bool canRecallChatMessage(Map message, int? userId, {DateTime? now}) {
  const types = {
    'text',
    'image',
    'video',
    'voice',
    'post',
    'profile',
    'voice_room',
    'nudge'
  };
  if (userId == null ||
      message['senderId'] != userId ||
      message['id'] is! num ||
      (message['id'] as num) <= 0 ||
      isChatMessageRecalled(message) ||
      !types.contains(message['type'])) {
    return false;
  }
  final createdAt = DateTime.tryParse(message['createdAt']?.toString() ?? '');
  if (createdAt == null) return false;
  final age = (now ?? DateTime.now()).difference(createdAt);
  return !age.isNegative && age <= const Duration(minutes: 2);
}

bool isChatMessageRecalled(Map message) =>
    message['recalled'] == true || message['type'] == 'recalled';

Set<int> chatReconciliationIds(Iterable<Map> messages) => {
      for (final message in messages) ...[
        if (message['id'] is num) (message['id'] as num).toInt(),
        if (message['quote'] is Map && message['quote']['messageId'] is num)
          (message['quote']['messageId'] as num).toInt(),
      ],
    };

/// Preserve map identity, but never restore recalled content from late pages.
void redactRecalledChatMessages(
    Iterable<Map<String, dynamic>> messages, Set<int> recalledIds) {
  for (final message in messages) {
    if (isChatMessageRecalled(message) || recalledIds.contains(message['id'])) {
      message.addAll(
          {'recalled': true, 'type': 'recalled', 'content': '', 'quote': null});
      message.remove('localPath');
    } else if (message['quote'] case final Map quote) {
      if (isChatMessageRecalled(quote) ||
          recalledIds.contains(quote['messageId'])) {
        message['quote'] = {
          'messageId': quote['messageId'],
          'senderId': quote['senderId'],
          'nickname': quote['nickname'],
          'type': 'recalled',
          'content': '该消息已撤回',
          'recalled': true,
        };
      }
    }
  }
}
