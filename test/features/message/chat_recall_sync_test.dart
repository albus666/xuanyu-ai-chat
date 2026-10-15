import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_recall.dart';
import 'package:xuanyu/features/message/chat_message_sync.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);
  Map<String, dynamic> message({
    Duration age = const Duration(seconds: 60),
    String type = 'text',
    int sender = 7,
  }) =>
      {
        'id': 1,
        'senderId': sender,
        'type': type,
        'createdAt': now.subtract(age).toIso8601String(),
        'content': '原内容',
      };
  test('两分钟含边界，超过一微秒拒绝，未来时间拒绝', () {
    expect(
      canRecallChatMessage(
        message(age: const Duration(minutes: 2)),
        7,
        now: now,
      ),
      isTrue,
    );
    expect(
      canRecallChatMessage(
        message(age: const Duration(minutes: 2, microseconds: 1)),
        7,
        now: now,
      ),
      isFalse,
    );
    expect(
      canRecallChatMessage(
        message(age: const Duration(microseconds: -1)),
        7,
        now: now,
      ),
      isFalse,
    );
  });
  test('文字图片视频语音拍一拍与分享消息可撤回，交易系统消息不可撤回', () {
    for (final type in [
      'text',
      'image',
      'video',
      'voice',
      'post',
      'profile',
      'voice_room',
      'nudge',
    ]) {
      expect(
        canRecallChatMessage(message(type: type), 7, now: now),
        isTrue,
        reason: type,
      );
    }
    for (final type in [
      'gift',
      'style_order',
      'call',
      'system',
      'recalled',
      'unknown',
    ]) {
      expect(
        canRecallChatMessage(message(type: type), 7, now: now),
        isFalse,
        reason: type,
      );
    }
  });
  test('他人未发送时间异常及已撤回消息均拒绝', () {
    for (final row in [
      message(sender: 8),
      message()..['id'] = null,
      message()..['id'] = -1,
      message()..['createdAt'] = 'invalid',
      message()..['recalled'] = true,
    ]) {
      expect(canRecallChatMessage(row, 7, now: now), isFalse);
    }
    expect(canRecallChatMessage(message(), null, now: now), isFalse);
  });
  test('引用原消息ID也参与校准，去重后处理撤回不改变正常消息', () {
    final rows = [
      message()..['quote'] = {'messageId': 9, 'content': '旧引用'},
      {...message(), 'id': 2, 'content': '普通文字'},
    ];
    expect(chatReconciliationIds(rows), {1, 2, 9});
    redactRecalledChatMessages(rows, {9});
    expect((rows[0]['quote'] as Map)['content'], '该消息已撤回');
    expect(rows[1]['content'], '普通文字');
    rows[0]['localPath'] = '/fake/private.png';
    redactRecalledChatMessages(rows, {1});
    expect(rows[0]['content'], '');
    expect(rows[0]['quote'], isNull);
    expect(rows[0].containsKey('localPath'), isFalse);
  });

  test('超过100个缓存ID分批校准且不混入额外分页内容', () async {
    final client = Dio();
    final calls = <RequestOptions>[];
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          calls.add(r);
          final ids = r.queryParameters['reconciliation_ids']
              .toString()
              .split(',')
              .map(int.parse)
              .toList();
          h.resolve(
            Response(
              requestOptions: r,
              data: {
                'code': 0,
                'data': {
                  'list': [message()..['id'] = calls.length == 1 ? 251 : 999],
                  'hasMore': false,
                  'recalledIds': [ids.first],
                },
              },
            ),
          );
        },
      ),
    );
    final data = await ChatMessageSync(
      client,
      42,
    ).refresh(knownIds: List.generate(250, (i) => i + 1));
    expect(calls, hasLength(3));
    expect(calls.map((r) => r.queryParameters['page_size']), [50, 1, 1]);
    expect(
      calls.map(
        (r) => r.queryParameters['reconciliation_ids']
            .toString()
            .split(',')
            .length,
      ),
      [100, 100, 50],
    );
    expect(data['recalledIds'], [1, 101, 201]);
    expect((data['list'] as List).map((e) => e['id']), [251]);
  });
  test('读取业务失败不覆盖消息为假空列表', () async {
    final client = Dio();
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) => h.resolve(
          Response(
            requestOptions: r,
            data: {
              'code': 403,
              'message': '已退出会话',
              'data': {'list': []},
            },
          ),
        ),
      ),
    );
    await expectLater(
      ChatMessageSync(client, 42).page(),
      throwsA(isA<ImWorkflowFailure>()),
    );
  });
  test('切号后的消息同步不借新账号发请求', () async {
    final client = Dio();
    var calls = 0;
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          calls++;
          h.resolve(
            Response(
              requestOptions: r,
              data: {
                'code': 0,
                'data': {'list': []},
              },
            ),
          );
        },
      ),
    );
    final sync = ChatMessageSync(client, 42);
    apiSessionChanges.value++;
    await expectLater(
      sync.refresh(knownIds: [1]),
      throwsA(isA<ImWorkflowFailure>()),
    );
    expect(calls, 0);
  });
  test('请求中途切号丢弃旧消息结果', () async {
    final client = Dio();
    final started = Completer<void>();
    late RequestInterceptorHandler handler;
    late RequestOptions request;
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          request = r;
          handler = h;
          started.complete();
        },
      ),
    );
    final result = ChatMessageSync(client, 42).page();
    final assertion = expectLater(result, throwsA(isA<ImWorkflowFailure>()));
    await started.future;
    apiSessionChanges.value++;
    handler.resolve(
      Response(
        requestOptions: request,
        data: {
          'code': 0,
          'data': {
            'list': [message()],
          },
        },
      ),
    );
    await assertion;
  });
}
