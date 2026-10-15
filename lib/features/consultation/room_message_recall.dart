import 'package:flutter/material.dart';

bool canRecallRoomMessage(Map<String, dynamic> message, {DateTime? now}) {
  if (message['isMe'] != true ||
      !['text', 'image'].contains(message['type']) ||
      message['status'] == 'revoked') {
    return false;
  }
  final created = DateTime.tryParse(message['createdAt']?.toString() ?? '');
  if (created == null) return false;
  final age = (now ?? DateTime.now()).difference(created);
  return !age.isNegative && age <= const Duration(minutes: 2);
}

Map<String, dynamic> recalledRoomMessage(Map<String, dynamic> message) =>
    {...message, 'type': 'revoked', 'status': 'revoked', 'content': ''};

/// Incremental responses may be older than a confirmed recall. Never restore it.
List<Map<String, dynamic>> mergeRoomMessages(List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> incoming, Set<int> revokedIds) {
  final merged = {for (final row in current) row['id']: row};
  for (final row in incoming) {
    final old = merged[row['id']];
    merged[row['id']] = old?['status'] == 'revoked' ? old! : row;
  }
  return merged.values
      .map((row) => revokedIds.contains(row['id']) || row['status'] == 'revoked'
          ? recalledRoomMessage(row)
          : row)
      .toList();
}

class RoomChatMessage extends StatelessWidget {
  const RoomChatMessage({super.key, required this.message, this.onRecall});
  final Map<String, dynamic> message;
  final VoidCallback? onRecall;

  Future<void> _showActions(BuildContext context) async {
    if (onRecall == null || !canRecallRoomMessage(message)) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selection = await showMenu<String>(
      context: context,
      color: const Color(0xFF173F48),
      position: RelativeRect.fromLTRB(
          origin.dx,
          (origin.dy - 60).clamp(0, overlay.size.height).toDouble(),
          (overlay.size.width - origin.dx - box.size.width)
              .clamp(0, overlay.size.width)
              .toDouble(),
          0),
      items: const [
        PopupMenuItem(
            value: 'recall',
            child: Text('撤回', style: TextStyle(color: Colors.white)))
      ],
    );
    if (context.mounted && selection == 'recall') onRecall?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (message['status'] == 'revoked' || message['type'] == 'revoked') {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
              message['isMe'] == true
                  ? '你撤回了一条消息'
                  : '${message['nickname'] ?? '用户'}撤回了一条消息',
              style: const TextStyle(color: Colors.white60, fontSize: 11)));
    }
    return Builder(
        builder: (bubbleContext) => GestureDetector(
              onTap:
                  onRecall == null ? null : () => _showActions(bubbleContext),
              onLongPress:
                  onRecall == null ? null : () => _showActions(bubbleContext),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0x451AC4C4),
                    borderRadius: BorderRadius.circular(11)),
                child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${message['nickname'] ?? '用户'}  ',
                          style: const TextStyle(
                              color: Color(0xFF6BE5DD),
                              fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: message['content']?.toString() ?? '',
                          style: const TextStyle(
                              color: Colors.white, height: 1.35)),
                    ]),
                    style: const TextStyle(fontSize: 11)),
              ),
            ));
  }
}
