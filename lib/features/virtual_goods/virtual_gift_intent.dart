import 'dart:convert';
import 'dart:math';

import '../../core/local/account_preference_scope.dart';
import '../../core/network/api_session_scope.dart';

/// A durable, account-owned purchase intent. An uncertain network response must
/// be retried with the same immutable request, even after closing the sheet.
class VirtualGiftIntent {
  VirtualGiftIntent(
      {required Map<String, dynamic> request,
      required this.giftName,
      required this.receiverName})
      : request = Map.unmodifiable(request);

  final Map<String, dynamic> request;
  final String giftName;
  final String receiverName;
  String get requestKey => request['requestKey'] as String;
  int get quantity => request['quantity'] as int;
  double get total => double.parse(request['expectedTotal'] as String);
  String get giftCode => request['giftCode'] as String;
  int get receiverId => request['receiverUserId'] as int;

  bool matchesReceipt(Map<dynamic, dynamic> receipt) {
    final amount = double.tryParse('${receipt['totalAmount']}');
    return receipt['orderNo'] is String &&
        (receipt['orderNo'] as String).isNotEmpty &&
        receipt['giftCode'] == giftCode &&
        receipt['quantity'] == quantity &&
        receipt['receiverUserId'] == receiverId &&
        receipt['roomId'] == request['roomId'] &&
        receipt['conversationId'] == request['conversationId'] &&
        amount != null &&
        amount.isFinite &&
        amount.toStringAsFixed(4) == request['expectedTotal'];
  }

  factory VirtualGiftIntent.create(
      {required String giftCode,
      required String giftName,
      required int receiverId,
      required String receiverName,
      required int quantity,
      required double total,
      int? roomId,
      int? conversationId}) {
    if (quantity < 1 ||
        quantity > 999 ||
        giftCode.trim().isEmpty ||
        receiverId <= 0 ||
        !total.isFinite ||
        total < 0 ||
        (roomId == null) == (conversationId == null)) {
      throw ArgumentError('Invalid gift intent');
    }
    final random = Random.secure();
    final key = List.generate(
            24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    return VirtualGiftIntent(request: {
      'requestKey': key,
      'giftCode': giftCode,
      'quantity': quantity,
      'receiverUserId': receiverId,
      'roomId': roomId,
      'conversationId': conversationId,
      'expectedTotal': total.toStringAsFixed(4),
    }, giftName: giftName, receiverName: receiverName);
  }

  Map<String, dynamic> toJson() => {
        'request': request,
        'giftName': giftName,
        'receiverName': receiverName,
      };

  factory VirtualGiftIntent.fromJson(Map<String, dynamic> value) {
    final raw = value['request'];
    if (raw is! Map) throw const FormatException('Invalid pending gift');
    final request = Map<String, dynamic>.from(raw);
    final quantity = request['quantity'];
    final total = double.tryParse('${request['expectedTotal']}');
    final key = request['requestKey'];
    final receiver = request['receiverUserId'];
    final room = request['roomId'];
    final chat = request['conversationId'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 64 ||
        request['giftCode'] is! String ||
        quantity is! int ||
        quantity < 1 ||
        quantity > 999 ||
        receiver is! int ||
        receiver <= 0 ||
        total == null ||
        !total.isFinite ||
        total < 0 ||
        (room == null) == (chat == null) ||
        (room != null && (room is! int || room <= 0)) ||
        (chat != null && (chat is! int || chat <= 0))) {
      throw const FormatException('Invalid pending gift');
    }
    request['expectedTotal'] = total.toStringAsFixed(4);
    return VirtualGiftIntent(
        request: request,
        giftName: '${value['giftName'] ?? '礼物'}',
        receiverName: '${value['receiverName'] ?? '对方'}');
  }
}

class VirtualGiftIntentStore {
  VirtualGiftIntentStore._(this._owner, this._roomId, this._conversationId);
  final AccountPreferenceScope _owner;
  final int? _roomId;
  final int? _conversationId;
  String get _key => _owner.key(
      'pending_gift_v1_${_roomId != null ? 'room_$_roomId' : 'chat_$_conversationId'}');
  bool get current => _owner.current;

  static Future<VirtualGiftIntentStore> open(
      {required ApiSessionScope session,
      int? roomId,
      int? conversationId}) async {
    final owner = await AccountPreferenceScope.capture(session: session);
    if (!session.authenticated ||
        owner.userId == null ||
        (roomId == null) == (conversationId == null)) {
      throw StateError('请登录后重新进入赠送页面');
    }
    return VirtualGiftIntentStore._(owner, roomId, conversationId);
  }

  VirtualGiftIntent? read() {
    _owner.ensureCurrent();
    final raw = _owner.prefs.getString(_key);
    if (raw == null) return null;
    final parsed = jsonDecode(raw);
    if (parsed is! Map) throw const FormatException('Invalid pending gift');
    final intent =
        VirtualGiftIntent.fromJson(Map<String, dynamic>.from(parsed));
    if (intent.request['roomId'] != _roomId ||
        intent.request['conversationId'] != _conversationId) {
      throw const FormatException('Gift scene mismatch');
    }
    return intent;
  }

  Future<void> save(VirtualGiftIntent intent) async {
    _owner.ensureCurrent();
    if (intent.request['roomId'] != _roomId ||
        intent.request['conversationId'] != _conversationId) {
      throw const FormatException('Gift scene mismatch');
    }
    final existing = read();
    if (existing != null && existing.requestKey != intent.requestKey) {
      throw StateError('请先确认上一笔礼物的赠送结果');
    }
    if (!await _owner.prefs.setString(_key, jsonEncode(intent.toJson()))) {
      throw StateError('无法保存赠送请求，请稍后重试');
    }
    _owner.ensureCurrent();
  }

  Future<void> resolve(VirtualGiftIntent intent) async {
    _owner.ensureCurrent();
    if (read()?.requestKey == intent.requestKey &&
        !await _owner.prefs.remove(_key)) {
      throw StateError('赠送结果已确认，但本地记录更新失败，请重试确认');
    }
    _owner.ensureCurrent();
  }
}
