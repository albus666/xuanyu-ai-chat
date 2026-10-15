import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InterceptorsWrapper fake;
  late List<Map<String, dynamic>> rows;
  late Map<String, dynamic> recallResult;
  final calls = <RequestOptions>[];
  Completer<void>? hold;
  Set<int> recalledIds = {};
  Map<String, dynamic> message(int id,
          {int sender = 7, String type = 'text', int age = 30}) =>
      {
        'id': id,
        'senderId': sender,
        'nickname': '测试用户',
        'avatarUrl': '',
        'type': type,
        'content': '待撤回内容$id',
        'createdAt': DateTime.now()
            .toUtc()
            .subtract(Duration(seconds: age))
            .toIso8601String(),
      };
  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    setupApiClientToken(null);
    calls.clear();
    hold = null;
    recalledIds = {};
    rows = [message(1)];
    recallResult = {
      'code': 0,
      'data': {'messageId': 1, 'recalled': true}
    };
    fake = InterceptorsWrapper(onRequest: (r, h) async {
      calls.add(r);
      Map<String, dynamic> result = {'code': 0, 'data': <String, dynamic>{}};
      if (r.path.endsWith('/messages')) {
        result['data'] = {
          'list': rows.map((e) => Map<String, dynamic>.from(e)).toList(),
          'hasMore': false,
          'recalledIds': recalledIds.toList()
        };
      } else if (r.path.endsWith('/recall')) {
        if (hold != null) await hold!.future;
        result = recallResult;
      } else if (r.path.endsWith('/messages/favorite') ||
          r.path.endsWith('/messages/delete')) {
        result = {'code': 403, 'message': '模拟拒绝操作'};
      }
      h.resolve(Response(requestOptions: r, data: result));
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ChatPage(conversationId: 42, title: '测试聊天')));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.longPress(find.text('待撤回内容1').first);
    await tester.pumpAndSettle();
  }

  testWidgets('自己两分钟内的普通消息显示撤回', (tester) async {
    await open(tester);
    await menu(tester);
    expect(find.text('撤回'), findsOneWidget);
  });
  testWidgets('别人的消息不能撤回', (tester) async {
    rows = [message(1, sender: 8)];
    await open(tester);
    await menu(tester);
    expect(find.text('撤回'), findsNothing);
  });
  testWidgets('超过两分钟不显示撤回', (tester) async {
    rows = [message(1, age: 121)];
    await open(tester);
    await menu(tester);
    expect(find.text('撤回'), findsNothing);
  });
  testWidgets('撤回成功清理引用草稿，旧刷新不能复活', (tester) async {
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();
    await menu(tester);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(find.text('你撤回了一条消息'), findsOneWidget);
    expect(find.textContaining('待撤回内容1'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('你撤回了一条消息'), findsOneWidget);
    expect(find.textContaining('待撤回内容1'), findsNothing);
    expect(calls.where((r) => r.path.endsWith('/recall')), hasLength(1));
  });
  testWidgets('业务失败不隐藏原消息', (tester) async {
    recallResult = {'code': 400, 'message': '消息发送超过两分钟，无法撤回'};
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(find.text('待撤回内容1'), findsOneWidget);
    expect(find.text('你撤回了一条消息'), findsNothing);
    expect(find.text('消息发送超过两分钟，无法撤回'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('异常成功体不能假装撤回', (tester) async {
    recallResult = {
      'code': 0,
      'data': {'messageId': 2, 'recalled': true}
    };
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(find.text('待撤回内容1'), findsOneWidget);
    expect(find.text('你撤回了一条消息'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('菜单期间切换账号不发送撤回请求', (tester) async {
    await open(tester);
    await menu(tester);
    setupApiClientToken(null);
    await tester.pump();
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path.endsWith('/recall')), isEmpty);
    expect(find.textContaining('待撤回内容1'), findsNothing);
  });
  testWidgets('正在撤回时重复操作只发一次，切号迟到结果无效', (tester) async {
    hold = Completer<void>();
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('待撤回内容1'));
    await tester.pumpAndSettle();
    expect(find.text('撤回'), findsNothing);
    expect(calls.where((r) => r.path.endsWith('/recall')), hasLength(1));
    setupApiClientToken(null);
    await tester.pump();
    hold!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('待撤回内容1'), findsNothing);
    expect(find.text('你撤回了一条消息'), findsNothing);
  });
  testWidgets('收到对方撤回占位不显示原文或消息菜单', (tester) async {
    rows = [
      {
        ...message(1, sender: 8),
        'recalled': true,
        'type': 'recalled',
        'content': ''
      }
    ];
    await open(tester);
    expect(find.text('对方撤回了一条消息'), findsOneWidget);
    await tester.longPress(find.text('对方撤回了一条消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });
  testWidgets('服务端撤回ID清理已加载引用快照', (tester) async {
    rows = [
      message(2, sender: 8)
        ..['quote'] = {'messageId': 1, 'nickname': '测试用户', 'content': '引用敏感原文'}
    ];
    await open(tester);
    expect(find.textContaining('引用敏感原文'), findsOneWidget);
    recalledIds = {1};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('引用敏感原文'), findsNothing);
    expect(find.textContaining('该消息已撤回'), findsOneWidget);
  });
  testWidgets('收藏业务失败不假装成功', (tester) async {
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已收藏'), findsNothing);
    expect(find.text('模拟拒绝操作'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('删除确认期间切号不删除旧账号消息', (tester) async {
    await open(tester);
    await menu(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    setupApiClientToken(null);
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path.endsWith('/messages/delete')), isEmpty);
  });
}
