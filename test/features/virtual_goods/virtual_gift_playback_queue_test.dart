import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_playback_queue.dart';

Map<String, dynamic> gift(int order, {String? name}) => {
      'orderId': order,
      'orderNo': 'VG$order',
      'giftName': name ?? '星光礼物',
      'quantity': 3,
    };

Map<String, dynamic> message(int id,
        {int? order, String type = 'gift', bool isMe = false}) =>
    {
      'id': id,
      'type': type,
      'nickname': isMe ? '本人' : '赠送者',
      'isMe': isMe,
      'content': jsonEncode(gift(order ?? id)),
    };

Map<String, dynamic> comboGift(int order,
        {int sender = 1, int receiver = 2, String code = 'stars'}) =>
    {
      ...gift(order),
      'senderId': sender,
      'receiverUserId': receiver,
      'giftCode': code,
    };

void main() {
  test('首次加载只建基线，后续双方新礼物按消息顺序播放', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([message(10), message(11)]);
    expect(queue.active, isNull);
    queue.observeMessages([message(13, isMe: true), message(11), message(12)]);
    expect(queue.active?['orderNo'], 'VG12');
    expect(queue.active?['senderName'], '赠送者');
    expect(queue.active?['quantity'], 3);
    queue.complete(queue.active!);
    expect(queue.active?['orderNo'], 'VG13');
    expect(queue.active?['senderName'], '本人');
  });

  test('初始空会话收到第一份礼物也播放', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([]);
    queue.observeMessages([message(1)]);
    expect(queue.active?['orderNo'], 'VG1');
  });

  test('API 回执先到，消息回流和再次刷新不重复播放', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([]);
    queue.enqueue(gift(9));
    queue.observeMessages([message(33, order: 9, isMe: true)]);
    expect(queue.pendingCount, 0);
    queue.complete(queue.active!);
    queue.observeMessages([message(33, order: 9, isMe: true)]);
    expect(queue.active, isNull);
  });

  test('消息先于 API 回执到达也只播放一次，记录订单别名', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([]);
    final row = message(2, order: 77);
    final payload = gift(77)..remove('orderNo');
    row['content'] = payload;
    queue.observeMessages([row]);
    expect(queue.enqueue(gift(77)), isFalse);
    queue.complete(queue.active!);
    expect(queue.enqueue({'orderNo': 'VG77'}), isFalse);
    expect(queue.active, isNull);
  });

  test('翻到历史和重复 ID 不触发重播，即使旧消息没有订单字段', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([message(40, type: 'text')]);
    queue.observeMessages([message(12), message(40, type: 'text')]);
    expect(queue.active, isNull);
    final row = message(41)..['content'] = {'giftName': '历史兼容礼物'};
    queue.observeMessages([row]);
    queue.complete(queue.active!);
    queue.observeMessages([row]);
    expect(queue.active, isNull);
  });

  test('队列有上限，保留当前播放和最新等待礼物', () {
    final queue = VirtualGiftPlaybackQueue(maxPending: 2);
    for (var i = 1; i <= 5; i++) {
      queue.enqueue(gift(i));
    }
    expect(queue.active?['orderNo'], 'VG1');
    expect(queue.pendingCount, 2);
    queue.complete(queue.active!);
    expect(queue.active?['orderNo'], 'VG4');
    queue.complete(queue.active!);
    expect(queue.active?['orderNo'], 'VG5');
    expect(queue.enqueue(gift(2)), isFalse);
  });

  test('慢加载没有父级超时，重复/过期完成回调不能跳过下一份', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.enqueue(gift(1));
    final first = queue.active!;
    queue.enqueue(gift(2));
    expect(identical(queue.active, first), isTrue);
    queue.complete(first);
    final second = queue.active!;
    queue.complete(first);
    expect(identical(queue.active, second), isTrue);
    queue.complete(second);
    expect(queue.active, isNull);
  });

  test('退出/切号清空在播、队列、身份缓存和历史基线', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([]);
    queue.enqueue(gift(1));
    final stale = queue.active!;
    queue.enqueue(gift(2));
    queue.clear();
    queue.complete(stale);
    expect(queue.active, isNull);
    expect(queue.pendingCount, 0);
    queue.observeMessages([message(50)]);
    expect(queue.active, isNull);
    expect(queue.enqueue(gift(1)), isTrue);
  });

  test('房间入场特效保留，聊天不播放入场事件', () {
    final room = VirtualGiftPlaybackQueue()..observeMessages([]);
    final chat = VirtualGiftPlaybackQueue()..observeMessages([]);
    final row = message(8, type: 'entry');
    room.observeMessages([row], includeEntries: true);
    chat.observeMessages([row]);
    expect(room.active?['nickname'], '赠送者');
    expect(chat.active, isNull);
  });

  test('无效/撤回内容跳过，数量缺失回退 1 且不篡改原数据', () {
    final queue = VirtualGiftPlaybackQueue()..observeMessages([]);
    queue.observeMessages([
      message(1)..['content'] = 'broken json',
      message(2)..['recalled'] = true,
      message(3)..['content'] = '[]',
    ]);
    expect(queue.active, isNull);
    final payload = gift(4)..['quantity'] = 0;
    queue.enqueue(payload);
    expect(payload['quantity'], 0);
    expect(queue.active?['quantity'], 1);
  });

  test('仅等待队尾同双方同礼物不同订单合并，当前播放和原订单不变', () {
    final queue = VirtualGiftPlaybackQueue();
    final first = comboGift(1);
    final second = comboGift(2);
    final third = comboGift(3)..['quantity'] = 8;
    queue.enqueue(first);
    final playing = queue.active!;
    queue.enqueue(second);
    queue.enqueue(third);
    expect(queue.pendingCount, 1);
    expect(identical(queue.active, playing), isTrue);
    expect(queue.active?['quantity'], 3);
    expect(queue.active?['comboCount'], 1);
    expect(second['quantity'], 3);
    expect(third['quantity'], 8);
    expect(second.containsKey('comboCount'), isFalse);
    queue.complete(playing);
    expect(queue.active?['comboCount'], 2);
    expect(queue.active?['quantity'], 11);
  });

  test('合并后的回执/消息重复不会重复累计，历史订单也不参与连击', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.observeMessages([message(5)..['content'] = comboGift(50)]);
    queue.enqueue(comboGift(1));
    queue.enqueue(comboGift(2));
    queue.enqueue(comboGift(3));
    queue.observeMessages([
      message(6)..['content'] = comboGift(2),
      message(7)..['content'] = comboGift(3),
    ]);
    expect(queue.enqueue(comboGift(50)), isFalse);
    expect(queue.pendingCount, 1);
    queue.complete(queue.active!);
    expect(queue.active?['comboCount'], 2);
    expect(queue.active?['quantity'], 6);
  });

  test('不同赠送者、接收者、礼物以及不相邻订单不合并', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.enqueue(comboGift(1));
    queue.enqueue(comboGift(2));
    queue.enqueue(comboGift(3, sender: 9));
    queue.enqueue(comboGift(4, receiver: 9));
    queue.enqueue(comboGift(5, code: 'flower'));
    queue.enqueue(comboGift(6));
    expect(queue.pendingCount, 5);
    for (var order = 1; order <= 6; order++) {
      expect(queue.active?['orderId'], order);
      expect(queue.active?['comboCount'], 1);
      queue.complete(queue.active!);
    }
  });

  test('缺少明确身份/订单、冲突别名、入场消息一律不合并', () {
    final invalid = [
      comboGift(3)..remove('senderId'),
      comboGift(3)..remove('receiverUserId'),
      comboGift(3)..remove('giftCode'),
      comboGift(3)..['senderUserId'] = 88,
      comboGift(3)..['receiverId'] = 88,
      comboGift(3)..['effectName'] = '入场',
      comboGift(3)..['type'] = 'entry',
      comboGift(3)
        ..remove('orderNo')
        ..remove('orderId'),
    ];
    for (final payload in invalid) {
      final queue = VirtualGiftPlaybackQueue();
      queue.enqueue(comboGift(1));
      queue.enqueue(comboGift(2));
      queue.enqueue(payload);
      expect(queue.pendingCount, 2, reason: '$payload');
    }
    final room = VirtualGiftPlaybackQueue()..observeMessages([]);
    room.enqueue(comboGift(1));
    room.enqueue(comboGift(2));
    room.observeMessages(
        [message(3, type: 'entry')..['content'] = comboGift(3)],
        includeEntries: true);
    expect(room.pendingCount, 2);
  });

  test('已明确的数字/字符串身份及字段别名可以识别同一人', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.enqueue(comboGift(1));
    queue.enqueue(comboGift(2));
    queue.enqueue({
      ...gift(3),
      'senderUserId': '1',
      'receiverId': '2',
      'giftCode': 'stars',
      'comboCount': 999,
    });
    queue.complete(queue.active!);
    expect(queue.active?['comboCount'], 2);
    expect(queue.active?['quantity'], 6);
  });

  test('连击每条最多10单，队列仍最多8条，不无限累积等待', () {
    final queue = VirtualGiftPlaybackQueue();
    for (var order = 1; order <= 95; order++) {
      queue.enqueue(comboGift(order));
    }
    expect(queue.pendingCount, 8);
    expect(queue.active?['orderId'], 1);
    queue.complete(queue.active!);
    expect(queue.active?['orderId'], 22);
    while (queue.active != null) {
      expect(queue.active?['comboCount'], lessThanOrEqualTo(10));
      expect(queue.active?['quantity'], lessThanOrEqualTo(30));
      queue.complete(queue.active!);
    }
  });

  test('无法比较的订单号/订单ID不得猜测不同订单并合并', () {
    final queue = VirtualGiftPlaybackQueue();
    queue.enqueue(comboGift(1));
    queue.enqueue(comboGift(2)..remove('orderNo'));
    queue.enqueue(comboGift(3)..remove('orderId'));
    expect(queue.pendingCount, 2);
  });
}
