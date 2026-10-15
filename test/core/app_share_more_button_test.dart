import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:xuanyu/shared/widgets/tool_share_preview.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/tool_share_message.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/widgets/app_share_more_button.dart';

void main() {
  final calls = <RequestOptions>[];
  late InterceptorsWrapper interceptor;
  late Object? originalAuth;
  late int originalSession;
  bool failSend = false;
  bool failRecent = false;
  bool groups = false;
  int? failConversation;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final externalCalls = <MethodCall>[];

  setUp(() {
    calls.clear();
    externalCalls.clear();
    failSend = false;
    failRecent = false;
    groups = false;
    failConversation = null;
    originalAuth = apiClient.options.headers['Authorization'];
    originalSession = apiSessionChanges.value;
    apiClient.options.headers['Authorization'] = 'share-test-account';
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      Object data = <String, Object?>{};
      int code = 0;
      if (request.path.endsWith('/conversations')) {
        code = failRecent ? 500 : 0;
        data = {
          'list': [
            {
              'conversationId': 7,
              'type': groups ? 'group' : 'single',
              'title': groups ? '测试群聊' : '测试好友'
            }
          ]
        };
      } else if (request.path.endsWith('/following-list')) {
        data = {
          'list': [
            {'userId': 12, 'nickname': '其他好友'}
          ]
        };
      } else if (request.path.endsWith('/single')) {
        data = {'conversationId': 8};
      } else if (request.path.endsWith('/message')) {
        code = failSend || request.path.endsWith('/$failConversation/message')
            ? 500
            : 0;
      } else if (request.path.endsWith('/upload')) {
        data = {'url': '/media/share.png'};
      }
      handler.resolve(Response<dynamic>(
          requestOptions: request,
          statusCode: 200,
          data: {'code': code, 'message': '测试失败', 'data': data}));
    });
    apiClient.interceptors.insert(0, interceptor);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      externalCalls.add(call);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    apiClient.options.headers['Authorization'] = originalAuth;
    apiSessionChanges.value = originalSession;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> open(WidgetTester tester,
      {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            appBar: AppBar(actions: const [
      AppShareMoreButton(
          title: '紫微斗数', shareText: '查看专业命盘工具', toolRoute: '/home_ziwei'),
    ]))));
    await tester.tap(find.byKey(const ValueKey('app-share-more-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('三点展开好友群聊与六个渠道，删除复制菜单且窄屏可滚动', (tester) async {
    await open(tester, size: const Size(280, 480));
    expect(find.text('分享至好友'), findsOneWidget);
    expect(find.text('测试好友'), findsOneWidget);
    expect(find.text('更多好友'), findsOneWidget);
    expect(find.text('复制分享文案'), findsNothing);
    expect(find.byType(ReferenceShareBrandIcon), findsNWidgets(5));
    for (final label in ['微信', '朋友圈', 'QQ', 'QQ空间', '微博', '更多']) {
      expect(find.byKey(ValueKey('app-share-channel-$label')), findsOneWidget);
    }
    await tester
        .ensureVisible(find.byKey(const ValueKey('app-share-channel-更多')));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('发送工具给好友先确认，发送可打开工具的文本卡片', (tester) async {
    await open(tester);
    await tester.tap(find.text('测试好友'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path.endsWith('/message')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('app-share-confirm-send')));
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((r) => r.path.endsWith('/message'));
    expect(sent.path, '/api/im/conversation/7/message');
    expect(sent.data['type'], 'text');
    expect(
        ToolShareMessage.tryParse(sent.data['content'])?.route, '/home_ziwei');
    expect(find.text('分享至好友'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('群聊可直接发送，服务器拒绝时保留面板供重试', (tester) async {
    groups = true;
    failSend = true;
    await open(tester);
    await tester.tap(find.text('测试群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-share-confirm-send')));
    await tester.pumpAndSettle();
    expect(find.text('分享至好友'), findsOneWidget);
    failSend = false;
    await tester.tap(find.text('测试群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-share-confirm-send')));
    await tester.pumpAndSettle();
    expect(find.text('分享至好友'), findsNothing);
    expect(calls.where((r) => r.path.endsWith('/message')), hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('更多好友复用好友群聊选择器并发送支持的消息类型', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('app-share-more-friends')));
    await tester.pumpAndSettle();
    expect(find.text('其他好友'), findsOneWidget);
    await tester.tap(find.text('其他好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享(1)'));
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((r) => r.path.endsWith('/message'));
    expect(sent.path, '/api/im/conversation/8/message');
    expect(ToolShareMessage.tryParse(sent.data['content'])?.title, '紫微斗数');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('部分发送失败时只重试失败对象，不向成功好友重复发送', (tester) async {
    groups = true;
    failConversation = 7;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('app-share-more-friends')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他好友'));
    await tester.tap(find.text('群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享(2)'));
    await tester.pumpAndSettle();
    expect(find.text('分享(1)'), findsOneWidget);
    failConversation = null;
    await tester.tap(find.text('分享(1)'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path == '/api/im/conversation/8/message'),
        hasLength(1));
    expect(calls.where((r) => r.path == '/api/im/conversation/7/message'),
        hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号切换关闭好友面板和确认框，不发送旧账号内容', (tester) async {
    await open(tester);
    await tester.tap(find.text('测试好友'));
    await tester.pumpAndSettle();
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('测试好友'), findsNothing);
    expect(find.byKey(const ValueKey('app-share-confirm-send')), findsNothing);
    expect(calls.where((r) => r.path.endsWith('/message')), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('面板首帧前切号不读取新账号会话', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AppShareMoreButton(title: '旧账号工具', shareText: '工具介绍'))));
    await tester.tap(find.byKey(const ValueKey('app-share-more-button')));
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('分享至好友'), findsNothing);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('好友加载失败可重试，更多渠道仅打开一次系统分享', (tester) async {
    failRecent = true;
    await open(tester);
    expect(find.text('好友加载失败，点击重试'), findsOneWidget);
    failRecent = false;
    await tester.tap(find.text('好友加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('测试好友'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-share-channel-更多')));
    await tester.pumpAndSettle();
    expect(externalCalls, hasLength(1));
    expect(externalCalls.single.arguments['text'], contains('查看专业命盘工具'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('分享图片给好友保留图片上传及图片消息', (tester) async {
    final file = File('${Directory.systemTemp.path}/xuanyu-share-test.png');
    file.writeAsBytesSync([137, 80, 78, 71]);
    addTearDown(() => file.deleteSync());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showAppShareSheet(context,
                          title: '生肖印记',
                          shareText: '图片介绍',
                          imageBuilder: () async => XFile(file.path)),
                      child: const Text('打开'),
                    )))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-share-confirm-send')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    await tester.pumpAndSettle();
    final sent = calls.singleWhere((r) => r.path.endsWith('/message'));
    expect(sent.data['type'], 'image');
    expect(sent.data['content'], endsWith('/media/share.png'));
    expect(calls.where((r) => r.path.endsWith('/upload')), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('工具消息卡片可以打开对应工具入口', (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(
          body: ToolSharePreview(
              message: ToolShareMessage(
                  title: '紫微斗数', text: '工具介绍', route: '/home_ziwei'))),
      getPages: [
        GetPage(
            name: '/home_ziwei',
            page: () => const Scaffold(body: Text('工具已打开')))
      ],
    ));
    await tester.tap(find.byKey(const ValueKey('chat-tool-share-card')));
    await tester.pumpAndSettle();
    expect(find.text('工具已打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('工具卡片只解析已支持路由，普通文本和伪造路由保持普通消息', () {
    expect(ToolShareMessage.tryParse('普通消息'), isNull);
    expect(
        ToolShareMessage.tryParse(
            '【玄遇工具】灵宠心语\n工具介绍\nxuanyu://tool/pet_insight'),
        isNull);
    expect(
        ToolShareMessage.tryParse('【玄遇工具】工具\n文字\nxuanyu://tool/system_login'),
        isNull);
    expect(ToolShareMessage.tryParse('【玄遇工具】工具\n文字\nhttps://tool/home_ziwei'),
        isNull);
    expect(
        ToolShareMessage.tryParse(
            '【玄遇工具】工具\n文字\nxuanyu://tool/home_ziwei?other=data'),
        isNull);
  });

  test('主要内容页均接入统一分享入口', () {
    const files = [
      'lib/features/fortune/partner_portrait/partner_portrait_page.dart',
      'lib/features/community/team_home_page.dart',
      'lib/features/community/topic_feed_page.dart',
      'lib/features/shop/shop_product_detail_page.dart',
      'lib/features/consultation/teacher_detail_page.dart',
      'lib/features/fortune/paipan/paipan_result_host_page.dart',
      'lib/features/fortune/ziwei/ziwei_chart_page.dart',
      'lib/features/fortune/astrology/astrology_page.dart',
      'lib/features/fortune/qizheng/qizheng_page.dart',
    ];

    for (final path in files) {
      expect(File(path).readAsStringSync(), contains('AppShareMoreButton'));
    }
    expect(
      File('lib/features/profile/settings_page.dart').readAsStringSync(),
      contains('showAppShareSheet'),
    );
  });
}
