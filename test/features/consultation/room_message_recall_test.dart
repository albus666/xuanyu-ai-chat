import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/room_message_recall.dart';
import 'package:xuanyu/features/consultation/voice_plaza_room_page.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 10);
  Map<String, dynamic> message(
          {int age = 10, String type = 'text', bool mine = true}) =>
      {
        'id': 7,
        'isMe': mine,
        'type': type,
        'content': '测试消息',
        'nickname': '测试用户',
        'status': 'visible',
        'createdAt': now.subtract(Duration(seconds: age)).toIso8601String(),
      };
  test('两分钟边界允许，超时未来时间禁止', () {
    expect(canRecallRoomMessage(message(age: 120), now: now), isTrue);
    expect(canRecallRoomMessage(message(age: 121), now: now), isFalse);
    expect(canRecallRoomMessage(message(age: -1), now: now), isFalse);
  });
  test('对方礼物系统不可撤回，自己图片允许', () {
    expect(canRecallRoomMessage(message(mine: false), now: now), isFalse);
    for (final type in [
      'gift',
      'entry',
      'mic_request',
      'mic_event',
      'relationship',
      'system'
    ]) {
      expect(canRecallRoomMessage(message(type: type), now: now), isFalse);
    }
    expect(canRecallRoomMessage(message(type: 'image'), now: now), isTrue);
  });
  test('时间缺失不提供撤回', () {
    expect(canRecallRoomMessage(message()..remove('createdAt'), now: now),
        isFalse);
  });
  test('撤回清除原文且旧响应不能还原', () {
    final original = message();
    final revoked = mergeRoomMessages([original], [], {7});
    final delayed = mergeRoomMessages(revoked, [original], {});
    expect(delayed.single['status'], 'revoked');
    expect(delayed.single['content'], '');
    expect(canRecallRoomMessage(delayed.single, now: now), isFalse);
  });
  test('新增去重且不影响其它消息', () {
    final newRow = {...message(), 'id': 8};
    final rows = mergeRoomMessages([message()], [newRow, newRow], {7});
    expect(rows.length, 2);
    expect(rows[0]['content'], '');
    expect(rows[1]['content'], '测试消息');
  });
  testWidgets('撤回占位不展示原文', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoomChatMessage(message: recalledRoomMessage(message())))));
    expect(find.text('你撤回了一条消息'), findsOneWidget);
    expect(find.textContaining('测试消息'), findsNothing);
  });
  testWidgets('消息上方菜单回调', (tester) async {
    var recalled = 0;
    final row = message()..['createdAt'] = DateTime.now().toIso8601String();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.only(top: 240),
                child: RoomChatMessage(
                    message: row, onRecall: () => recalled++)))));
    await tester.tap(find.byType(RoomChatMessage));
    await tester.pumpAndSettle();
    expect(find.text('撤回'), findsOneWidget);
    expect(tester.getTopLeft(find.text('撤回')).dy,
        lessThan(tester.getTopLeft(find.byType(RoomChatMessage)).dy));
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(recalled, 1);
  });

  group('实际房间页面模拟接口', () {
    late InterceptorsWrapper interceptor;
    late void Function(RequestOptions, RequestInterceptorHandler) recall;
    final calls = <RequestOptions>[];
    Set<int> revokedIds = {};
    bool sent = false;
    void ok(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
        h.resolve(Response(
            requestOptions: r,
            statusCode: 200,
            data: {'code': 0, 'data': data}));
    setUp(() {
      calls.clear();
      revokedIds = {};
      sent = false;
      apiClient.options.headers['Authorization'] = 'room-test-account-a';
      recall = (r, h) => ok(r, h, {'id': 7, 'revoked': true});
      interceptor = InterceptorsWrapper(onRequest: (r, h) {
        calls.add(r);
        if (r.path.endsWith('/revoke')) return recall(r, h);
        if (r.path.endsWith('/messages')) {
          final row = message()
            ..['createdAt'] = DateTime.now()
                .subtract(const Duration(seconds: 10))
                .toIso8601String();
          final list = sent ? <Map<String, dynamic>>[] : [row];
          sent = true;
          return ok(r, h, {'list': list, 'revokedIds': revokedIds.toList()});
        }
        ok(r, h, {
          'id': 1,
          'status': 'waiting',
          'title': '模拟房间',
          'roomType': 'party',
          'members': <dynamic>[],
          'owner': {'nickname': '房主'}
        });
      });
      apiClient.interceptors.insert(0, interceptor);
    });
    tearDown(() {
      apiClient.interceptors.remove(interceptor);
      apiClient.options.headers.remove('Authorization');
    });
    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: VoicePlazaRoomPage(roomId: 1)));
      await frames(tester);
      expect(find.byKey(const ValueKey('room-message-7')), findsOneWidget,
          reason: '已拦截请求: ${calls.map((request) => request.path).join(', ')}');
    }

    Future<void> menu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('room-message-7')));
      await frames(tester);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('真实回调发撤回请求并替换占位', (tester) async {
      await open(tester);
      await menu(tester);
      await tester.tap(find.text('撤回'));
      await frames(tester);
      expect(find.text('你撤回了一条消息'), findsOneWidget);
      final request = calls.singleWhere((r) => r.path.endsWith('/revoke'));
      expect(request.headers['Authorization'], 'room-test-account-a');
      await finish(tester);
    });
    testWidgets('业务拒绝不显示撤回成功且原文保留', (tester) async {
      recall = (r, h) => h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': 403, 'message': '本次拒绝撤回'}));
      await open(tester);
      await menu(tester);
      await tester.tap(find.text('撤回'));
      await frames(tester);
      expect(find.text('你撤回了一条消息'), findsNothing);
      expect(find.textContaining('测试消息', findRichText: true), findsOneWidget);
      await finish(tester);
    });
    testWidgets('菜单打开后切号不提交旧消息操作', (tester) async {
      await open(tester);
      await menu(tester);
      apiClient.options.headers['Authorization'] = 'room-test-account-b';
      apiSessionChanges.value++;
      await tester.tap(find.text('撤回'));
      await frames(tester);
      expect(calls.where((r) => r.path.endsWith('/revoke')), isEmpty);
      expect(find.byKey(const ValueKey('room-message-7')), findsNothing);
      await finish(tester);
    });
    testWidgets('请求期间切号丢弃迟到成功响应', (tester) async {
      RequestOptions? pendingRequest;
      RequestInterceptorHandler? pending;
      recall = (r, h) {
        pendingRequest = r;
        pending = h;
      };
      await open(tester);
      await menu(tester);
      await tester.tap(find.text('撤回'));
      await frames(tester);
      expect(pending, isNotNull);
      apiClient.options.headers['Authorization'] = 'room-test-account-b';
      apiSessionChanges.value++;
      ok(pendingRequest!, pending!, {'id': 7, 'revoked': true});
      await frames(tester);
      expect(find.text('你撤回了一条消息'), findsNothing);
      expect(find.byKey(const ValueKey('room-message-7')), findsNothing);
      await finish(tester);
    });
    testWidgets('撤回提交期间重复点菜单不重复发送', (tester) async {
      RequestOptions? pendingRequest;
      RequestInterceptorHandler? pending;
      recall = (r, h) {
        pendingRequest = r;
        pending = h;
      };
      await open(tester);
      await menu(tester);
      await tester.tap(find.text('撤回'));
      await frames(tester);
      await menu(tester);
      await tester.tap(find.text('撤回'));
      await frames(tester);
      expect(calls.where((r) => r.path.endsWith('/revoke')).length, 1);
      ok(pendingRequest!, pending!, {'id': 7, 'revoked': true});
      await frames(tester);
      expect(find.text('你撤回了一条消息'), findsOneWidget);
      await finish(tester);
    });
    testWidgets('轮询同步已显示旧消息撤回', (tester) async {
      await open(tester);
      revokedIds = {7};
      await tester.pump(const Duration(seconds: 15));
      await frames(tester);
      expect(find.text('你撤回了一条消息'), findsOneWidget);
      expect(
          calls
              .where((r) => r.path.endsWith('/messages'))
              .last
              .queryParameters['known_ids'],
          '7');
      await finish(tester);
    });
  });
}
