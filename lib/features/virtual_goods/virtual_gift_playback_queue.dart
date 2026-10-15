import 'dart:collection';
import 'dart:convert';

/// One queue per chat/room session. The effect owns its playback clock;
/// callers advance only after the effect has completed or been skipped.
class VirtualGiftPlaybackQueue {
  VirtualGiftPlaybackQueue({
    this.maxPending = 8,
    this.maxRemembered = 2048,
    this.maxComboCount = 10,
  })  : assert(maxPending > 0),
        assert(maxRemembered > 0),
        assert(maxComboCount > 0);

  final int maxPending;
  final int maxRemembered;
  final int maxComboCount;
  final Queue<Map<String, dynamic>> _pending = Queue();
  final LinkedHashSet<String> _seen = LinkedHashSet();
  Map<String, dynamic>? _active;
  bool _hasMessageBaseline = false;
  int _latestMessageId = 0;

  Map<String, dynamic>? get active => _active;
  int get pendingCount => _pending.length;

  Iterable<String> _identities(Map<String, dynamic> payload) sync* {
    for (final key in ['orderNo', 'orderId', '_messageId']) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != '0') yield '$key:$value';
    }
  }

  bool _remember(Map<String, dynamic> payload) {
    final identities = _identities(payload).toList();
    final duplicate = identities.any(_seen.contains);
    // Remember all aliases even on duplicates, so an API receipt and its
    // message can subsequently be recognized by either order ID or number.
    _seen.addAll(identities);
    while (_seen.length > maxRemembered) {
      _seen.remove(_seen.first);
    }
    return duplicate;
  }

  bool enqueue(Map<String, dynamic> payload) {
    final snapshot = Map<String, dynamic>.from(payload);
    if (_remember(snapshot)) return false;
    final quantity = int.tryParse('${snapshot['quantity'] ?? 1}') ?? 1;
    snapshot['quantity'] = quantity > 0 ? quantity : 1;
    // Combo metadata describes local presentation, never a billed order.
    snapshot['comboCount'] = 1;
    if (_active == null) {
      _active = snapshot;
    } else if (_pending.isNotEmpty && _canCombine(_pending.last, snapshot)) {
      final previous = _pending.removeLast();
      _pending.addLast({
        ...previous,
        'quantity':
            (previous['quantity'] as int) + (snapshot['quantity'] as int),
        'comboCount': (previous['comboCount'] as int) + 1,
      });
    } else {
      if (_pending.length >= maxPending) _pending.removeFirst();
      _pending.addLast(snapshot);
    }
    return true;
  }

  int? _userIdentity(Map<String, dynamic> payload, String key, String alias) {
    final value = int.tryParse('${payload[key] ?? payload[alias] ?? ''}');
    if (value == null || value <= 0) return null;
    // Conflicting aliases are not sufficient evidence of the same person.
    if (payload[key] != null &&
        payload[alias] != null &&
        int.tryParse('${payload[alias]}') != value) {
      return null;
    }
    return value;
  }

  bool _canCombine(Map<String, dynamic> previous, Map<String, dynamic> next) {
    if (previous['_messageType'] == 'entry' ||
        next['_messageType'] == 'entry' ||
        previous['type'] == 'entry' ||
        next['type'] == 'entry' ||
        previous['effectName'] != null ||
        next['effectName'] != null ||
        (previous['comboCount'] as int) >= maxComboCount) {
      return false;
    }
    final code = previous['giftCode']?.toString().trim() ?? '';
    final sender = _userIdentity(previous, 'senderId', 'senderUserId');
    final receiver = _userIdentity(previous, 'receiverId', 'receiverUserId');
    if (code.isEmpty ||
        code != (next['giftCode']?.toString().trim() ?? '') ||
        sender == null ||
        receiver == null ||
        sender != _userIdentity(next, 'senderId', 'senderUserId') ||
        receiver != _userIdentity(next, 'receiverId', 'receiverUserId')) {
      return false;
    }
    // Missing/mismatched identifier forms do not prove distinct orders.
    for (final key in ['orderNo', 'orderId']) {
      final before = previous[key]?.toString().trim() ?? '';
      final after = next[key]?.toString().trim() ?? '';
      if (before.isNotEmpty &&
          after.isNotEmpty &&
          before != '0' &&
          after != '0' &&
          before != after) {
        return true;
      }
    }
    return false;
  }

  /// The first successful refresh records history without replaying it.
  /// Later refreshes only play genuinely new IDs, including one's own gifts
  /// sent on another device. Older history pages never cause animations.
  void observeMessages(Iterable<Map<String, dynamic>> messages,
      {bool includeEntries = false}) {
    final rows = messages.toList()
      ..sort((a, b) => _messageId(a).compareTo(_messageId(b)));
    final previousLatest = _latestMessageId;
    for (final message in rows) {
      final id = _messageId(message);
      if (id > _latestMessageId) _latestMessageId = id;
      if (id <= 0 ||
          message['recalled'] == true ||
          message['type'] != 'gift' &&
              !(includeEntries && message['type'] == 'entry')) {
        continue;
      }
      final payload = _decode(message['content']);
      if (payload == null) continue;
      payload['_messageId'] = id;
      payload['_messageType'] = message['type'];
      final nickname = message['nickname'] ?? message['senderName'];
      if ((payload['senderName']?.toString().trim() ?? '').isEmpty &&
          nickname != null) {
        payload['senderName'] = nickname.toString();
      }
      if (nickname != null) payload['nickname'] = nickname.toString();
      if (!_hasMessageBaseline || id <= previousLatest) {
        _remember(payload);
      } else {
        enqueue(payload);
      }
    }
    _hasMessageBaseline = true;
  }

  int _messageId(Map<String, dynamic> message) =>
      int.tryParse('${message['id'] ?? 0}') ?? 0;

  Map<String, dynamic>? _decode(Object? content) {
    try {
      final value = content is Map ? content : jsonDecode('$content');
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  void complete(Map<String, dynamic> expected) {
    if (!identical(_active, expected)) return;
    _active = _pending.isEmpty ? null : _pending.removeFirst();
  }

  void clear() {
    _active = null;
    _pending.clear();
    _seen.clear();
    _hasMessageBaseline = false;
    _latestMessageId = 0;
  }
}
