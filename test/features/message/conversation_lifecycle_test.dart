import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_info_page.dart';
import 'package:xuanyu/features/message/create_group_page.dart';
import 'package:xuanyu/features/message/create_team_page.dart';
import 'package:xuanyu/features/message/single_chat_settings_page.dart';
import 'package:xuanyu/features/community/user_list_page.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';
import 'package:xuanyu/shared/widgets/app_text_field.dart';

void lifecycleTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pump(const Duration(seconds: 3));
    }
  });
}

void main() {
  late InterceptorsWrapper fake;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];
  void ok(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
  void fail(RequestOptions r, RequestInterceptorHandler h) =>
      h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': 403, 'message': '操作未获允许'}));
  Map<String, dynamic> groupInfo({bool owner = false}) => {
        'name': '测试群',
        'isMember': true,
        'isOwner': owner,
        'canManage': owner,
        'memberCount': 1,
        'mute': false,
        'pinned': false,
        'isPublic': false,
      };
  void groupReply(RequestOptions r, RequestInterceptorHandler h,
      {bool owner = false}) {
    if (r.path.endsWith('/info')) {
      ok(r, h, groupInfo(owner: owner));
    } else if (r.path.endsWith('/members')) {
      ok(r, h, {'list': [], 'pendingInvites': []});
    } else {
      ok(r, h, null);
    }
  }

  Future<void> openAction(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> fillCreation(WidgetTester tester, bool tribe) async {
    final values = tribe
        ? {
            '部落名称': '测试部落',
            '部落介绍': '线上协作',
            '技能标签（1—5个）': '资料检索',
            '能帮助什么': '核对信息',
            '不提供什么': '不保证结果',
            '部落公约': '尊重他人',
          }
        : {'群名称': '测试群'};
    for (final entry in values.entries) {
      final field = find
          .byWidgetPredicate((w) => w is AppTextField && w.label == entry.key);
      if (tribe) {
        await tester.scrollUntilVisible(field, 200,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.enterText(
          find.descendant(of: field, matching: find.byType(TextFormField)),
          entry.value);
    }
    tester.testTextInput.hide();
    await tester.pump();
  }

  Future<void> openPage(
      WidgetTester tester, Widget page, void Function(Object?) result) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result(await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => page)));
                      },
                      child: const Text('测试入口')),
                ))));
    await tester.tap(find.text('测试入口'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    apiClient.options.headers['Authorization'] = 'local-lifecycle-a';
    calls.clear();
    respond = (r, h) => ok(r, h, {'list': []});
    fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
    apiClient.options.headers.remove('Authorization');
  });

  lifecycleTest('创建群聊候选人网络失败可重试，不冒充无人关注', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(const MaterialApp(home: CreateGroupPage()));
    await tester.pumpAndSettle();
    expect(find.text('重试加载'), findsOneWidget);
    expect(find.text('暂无关注的人，先去社区关注用户再来建群吧'), findsNothing);
  });

  lifecycleTest('群详情失败不能显示可退出的假详情', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    expect(find.text('重试加载'), findsOneWidget);
    expect(find.text('退出群聊'), findsNothing);
  });

  lifecycleTest('退出群聊业务失败不能提示已退出', (tester) async {
    respond = (r, h) => r.method == 'POST' ? fail(r, h) : groupReply(r, h);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '退出群聊');
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(find.text('已退出群聊'), findsNothing);
    expect(find.text('操作未获允许'), findsOneWidget);
  });

  lifecycleTest('退出确认期间切号不能替新账号退出旧群', (tester) async {
    respond = (r, h) => groupReply(r, h);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '退出群聊');
    apiClient.options.headers['Authorization'] = 'local-lifecycle-b';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });

  lifecycleTest('群二维码弹窗切号后立即隐藏旧群二维码', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/info')) {
        ok(r, h, {...groupInfo(), 'isPublic': true});
      } else if (r.path.endsWith('/members')) {
        ok(r, h, {'list': [], 'pendingInvites': []});
      } else {
        ok(r, h, null);
      }
    };
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '群二维码');
    expect(find.text('群聊二维码'), findsOneWidget);
    apiClient.options.headers['Authorization'] = 'new-qr-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('账号已切换'), findsOneWidget);
    expect(find.text('群聊二维码'), findsNothing);
  });

  lifecycleTest('私聊置顶业务失败不改变开关', (tester) async {
    respond = (r, h) => r.method == 'PATCH'
        ? fail(r, h)
        : ok(r, h, {
            'type': 'single',
            'displayName': '对方',
            'pinned': false,
            'mute': false,
          });
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, '置顶聊天');
    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('操作未获允许'), findsOneWidget);
  });

  lifecycleTest('关注列表错误可重试而不是暂无用户', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(const MaterialApp(
        home: UserListPage(
            title: '关注', apiPath: '/api/community/user/me/following-list')));
    await tester.pumpAndSettle();
    expect(find.text('重试加载'), findsOneWidget);
    expect(find.text('暂无用户'), findsNothing);
  });

  lifecycleTest('创建部落加载失败也保留标题和返回导航', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(const MaterialApp(home: CreateTeamPage()));
    await tester.pumpAndSettle();
    expect(find.text('创建部落'), findsOneWidget);
    expect(find.text('重试加载'), findsOneWidget);
  });

  for (final tribe in [false, true]) {
    final label = tribe ? '部落' : '群聊';
    lifecycleTest('$label创建连续点击仅发一次，业务失败保留表单可重试', (tester) async {
      RequestOptions? held;
      RequestInterceptorHandler? handler;
      respond = (r, h) {
        if (r.method == 'POST') {
          held = r;
          handler = h;
        } else {
          ok(r, h, {'list': []});
        }
      };
      await tester.pumpWidget(MaterialApp(
          home: tribe ? const CreateTeamPage() : const CreateGroupPage()));
      await tester.pumpAndSettle();
      await fillCreation(tester, tribe);
      final callback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '创建'))
          .onPressed!;
      callback();
      callback();
      callback();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.where((r) => r.method == 'POST').length, 1);
      fail(held!, handler!);
      await tester.pumpAndSettle();
      expect(find.text('操作未获允许'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '创建'))
              .onPressed,
          isNotNull);
      expect(calls.where((r) => r.method == 'POST').single.data['name'],
          tribe ? '测试部落' : '测试群');
    });

    lifecycleTest('$label创建迟到成功不能关闭切号后的页面', (tester) async {
      RequestOptions? held;
      RequestInterceptorHandler? handler;
      respond = (r, h) {
        if (r.method == 'POST') {
          held = r;
          handler = h;
        } else {
          ok(r, h, {'list': []});
        }
      };
      await tester.pumpWidget(MaterialApp(
          home: tribe ? const CreateTeamPage() : const CreateGroupPage()));
      await tester.pumpAndSettle();
      await fillCreation(tester, tribe);
      await tester.tap(find.widgetWithText(TextButton, '创建'));
      await tester.pump(const Duration(milliseconds: 300));
      apiClient.options.headers['Authorization'] = 'local-lifecycle-b';
      apiSessionChanges.value++;
      await tester.pumpAndSettle();
      ok(held!, handler!,
          {'conversationId': 25, 'title': '旧账号群', 'invited': 0});
      await tester.pumpAndSettle();
      expect(find.text(imSessionChangedMessage), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '创建'))
              .onPressed,
          isNull);
    });

    lifecycleTest('$label创建结果不明时禁止重复创建', (tester) async {
      respond = (r, h) {
        if (r.method == 'POST') {
          h.reject(DioException(
              requestOptions: r, type: DioExceptionType.receiveTimeout));
        } else {
          ok(r, h, {'list': []});
        }
      };
      await tester.pumpWidget(MaterialApp(
          home: tribe ? const CreateTeamPage() : const CreateGroupPage()));
      await tester.pumpAndSettle();
      await fillCreation(tester, tribe);
      await tester.tap(find.widgetWithText(TextButton, '创建'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '创建'))
              .onPressed,
          isNull);
      expect(find.text('创建结果待确认，请返回群聊与部落查看，避免重复创建'), findsWidgets);
    });

    lifecycleTest('$label创建成功准确提示成员结果并返回新群', (tester) async {
      Object? result;
      respond = (r, h) => ok(
          r,
          h,
          r.method == 'POST'
              ? {
                  'conversationId': 25,
                  'title': '新群',
                  'invited': 0,
                  if (tribe) 'invitationUnavailable': true,
                  if (!tribe) 'added': 1
                }
              : {'list': []});
      await openPage(
          tester,
          tribe ? const CreateTeamPage() : const CreateGroupPage(),
          (r) => result = r);
      await fillCreation(tester, tribe);
      await tester.tap(find.widgetWithText(TextButton, '创建'));
      await tester.pumpAndSettle();
      expect(result, {'conversationId': 25, 'title': '新群'});
      expect(find.text(tribe ? '部落已创建，邀请暂未发出，请稍后在部落管理中重试' : '群聊已创建，1位好友已加入'),
          tribe ? findsNothing : findsOneWidget);
      expect(find.text('测试入口'), findsOneWidget);
    });
  }

  for (final owner in [false, true]) {
    final action = owner ? '解散群聊' : '退出群聊';
    lifecycleTest('$action成功才返回true，确认前连点只出现一个弹窗', (tester) async {
      Object? result;
      respond = (r, h) => r.method == 'POST'
          ? ok(r, h, {'message': '已完成'})
          : groupReply(r, h, owner: owner);
      await openPage(tester, const ChatInfoPage(conversationId: 12, title: '群'),
          (r) => result = r);
      await tester.scrollUntilVisible(find.text(action), 300,
          scrollable: find.byType(Scrollable).first);
      final callback = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, action))
          .onPressed!;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, owner ? '解散群聊' : '退出'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST').length, 1);
      expect(calls.where((r) => r.method == 'POST').single.path,
          '/api/im/conversation/12/${owner ? 'dissolve' : 'leave'}');
      expect(result, isTrue);
    });
  }

  lifecycleTest('解散确认切号不能请求旧群，旧权限清空', (tester) async {
    respond = (r, h) => groupReply(r, h, owner: true);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '解散群聊');
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '解散群聊'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });

  lifecycleTest('服务端未保存公开开关时，不假装设置成功', (tester) async {
    respond = (r, h) => r.method == 'PATCH'
        ? ok(r, h, {'message': '已更新'})
        : groupReply(r, h, owner: true);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('允许他人申请加入'), 250,
        scrollable: find.byType(Scrollable).first);
    final tile = find.ancestor(
        of: find.text('允许他人申请加入'), matching: find.byType(ListTile));
    tester
        .widget<Switch>(
            find.descendant(of: tile, matching: find.byType(Switch)))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('设置未生效，请刷新确认当前权限'), findsOneWidget);
    expect(
        tester
            .widget<Switch>(
                find.descendant(of: tile, matching: find.byType(Switch)))
            .value,
        isFalse);
  });

  lifecycleTest('群名保存业务失败保留旧值，错误可重试', (tester) async {
    respond = (r, h) =>
        r.method == 'PATCH' ? fail(r, h) : groupReply(r, h, owner: true);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '群聊名称');
    await tester.enterText(find.byType(TextFormField), '新名称');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('新名称'), findsNothing);
    expect(find.text('操作未获允许'), findsOneWidget);
    expect(find.text('重试加载'), findsOneWidget);
  });

  lifecycleTest('群备注保存前切号，不写入新账号', (tester) async {
    respond = (r, h) => groupReply(r, h);
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    await openAction(tester, '备注');
    await tester.enterText(find.byType(TextFormField), '账号甲的备注');
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('chat_remark_')), isEmpty);
  });

  lifecycleTest('取消关注确认期间切号不提交，取消后也可正常重试', (tester) async {
    respond = (r, h) =>
        ok(r, h, {'type': 'single', 'following': true, 'mutualFollow': true});
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    await openAction(tester, '取消关注');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    await openAction(tester, '取消关注');
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消关注'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });

  lifecycleTest('关注连续点击只请求一次，成功同步互关状态', (tester) async {
    RequestOptions? held;
    RequestInterceptorHandler? handler;
    respond = (r, h) {
      if (r.method == 'POST') {
        held = r;
        handler = h;
      } else {
        ok(r, h, {'type': 'single', 'following': false, 'mutualFollow': false});
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('关注'), 250,
        scrollable: find.byType(Scrollable).first);
    final callback =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '关注')).onTap!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST').length, 1);
    ok(held!, handler!, {'following': true, 'mutual': true});
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
  });

  lifecycleTest('拉黑失败不解除互关，也不显示解除拉黑', (tester) async {
    respond = (r, h) => r.method == 'POST'
        ? fail(r, h)
        : ok(r, h, {
            'type': 'single',
            'following': true,
            'mutualFollow': true,
            'blocked': false
          });
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    await openAction(tester, '拉黑用户');
    await tester.tap(find.text('拉黑'));
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
    expect(find.text('解除拉黑'), findsNothing);
    expect(find.text('操作未获允许'), findsOneWidget);
  });

  for (final success in [false, true]) {
    lifecycleTest('删除私聊会话只在业务成功返回：$success', (tester) async {
      Object? result;
      respond = (r, h) {
        if (r.method == 'POST') {
          success ? ok(r, h, {'message': '已删除'}) : fail(r, h);
        } else {
          ok(r, h, {'type': 'single', 'displayName': '对方'});
        }
      };
      await openPage(
          tester,
          const SingleChatSettingsPage(
              conversationId: 12, peerUserId: 8, initialTitle: '对方'),
          (r) => result = r);
      await openAction(tester, '删除会话');
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(result, success ? 'deleted' : isNull);
      expect(find.byType(SingleChatSettingsPage),
          success ? findsNothing : findsOneWidget);
    });
  }

  lifecycleTest('群置顶成功回读真实状态，并通知父页刷新', (tester) async {
    var pinned = false;
    var updates = 0;
    respond = (r, h) {
      if (r.method == 'PATCH') {
        pinned = r.data['pinned'] == true;
        ok(r, h, {'message': '已更新'});
      } else if (r.path.endsWith('/info')) {
        ok(r, h, {...groupInfo(), 'pinned': pinned});
      } else {
        groupReply(r, h);
      }
    };
    await tester.pumpWidget(MaterialApp(
        home: ChatInfoPage(
            conversationId: 12, title: '群', onUpdated: () => updates++)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('置顶聊天'), 250,
        scrollable: find.byType(Scrollable).first);
    final tile =
        find.ancestor(of: find.text('置顶聊天'), matching: find.byType(ListTile));
    tester
        .widget<Switch>(
            find.descendant(of: tile, matching: find.byType(Switch)))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Switch>(
                find.descendant(of: tile, matching: find.byType(Switch)))
            .value,
        isTrue);
    expect(updates, 1);
  });

  lifecycleTest('群备注按账号保存，旧全局备注保留但不自动认领', (tester) async {
    respond = (r, h) => groupReply(r, h);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_remark_12', '无归属旧备注');
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    expect(find.text('无归属旧备注'), findsNothing);
    await openAction(tester, '备注');
    await tester.enterText(find.byType(TextFormField), '甲的备注');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('甲的备注'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await prefs.setInt(AppConstants.keyUserId, 8);
    apiSessionChanges.value++;
    await tester.pumpWidget(
        const MaterialApp(home: ChatInfoPage(conversationId: 12, title: '群')));
    await tester.pumpAndSettle();
    expect(find.text('甲的备注'), findsNothing);
    expect(prefs.getString('chat_remark_account_7_12'), '甲的备注');
    expect(prefs.getString('chat_remark_12'), '无归属旧备注');
  });

  lifecycleTest('关注列表切号后旧结果不会覆盖新账号列表', (tester) async {
    RequestOptions? held;
    RequestInterceptorHandler? handler;
    respond = (r, h) {
      if (held == null) {
        held = r;
        handler = h;
      } else {
        ok(r, h, {
          'list': [
            {'userId': 10, 'nickname': '新账号关注'}
          ]
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: UserListPage(
            title: '关注', apiPath: '/api/community/user/me/following-list')));
    await tester.pump(const Duration(milliseconds: 300));
    apiClient.options.headers['Authorization'] = 'local-lifecycle-b';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    ok(held!, handler!, {
      'list': [
        {'userId': 8, 'nickname': '旧账号关注'}
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('旧账号关注'), findsNothing);
    expect(find.text('新账号关注'), findsOneWidget);
  });

  lifecycleTest('聊天设置加载失败可重试恢复', (tester) async {
    var failed = true;
    respond = (r, h) => failed
        ? h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError))
        : ok(r, h, {'type': 'single', 'displayName': '恢复的用户'});
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    failed = false;
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(find.text('恢复的用户'), findsOneWidget);
  });

  lifecycleTest('正常取消关注同步解除互关，不自动再次关注', (tester) async {
    respond = (r, h) => ok(
        r,
        h,
        r.method == 'POST'
            ? {'following': false, 'mutual': false}
            : {'type': 'single', 'following': true, 'mutualFollow': true});
    await tester.pumpWidget(const MaterialApp(
        home: SingleChatSettingsPage(
            conversationId: 12, peerUserId: 8, initialTitle: '对方')));
    await tester.pumpAndSettle();
    await openAction(tester, '取消关注');
    await tester.tap(find.widgetWithText(TextButton, '取消关注'));
    await tester.pumpAndSettle();
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('取消关注'), findsNothing);
    expect(calls.where((r) => r.method == 'POST').length, 1);
  });

  lifecycleTest('关注列表刷新失败保留旧列表，重试更新并去重', (tester) async {
    var attempt = 0;
    respond = (r, h) {
      attempt++;
      if (attempt == 2) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        ok(r, h, {
          'list': attempt == 1
              ? [
                  {'userId': 8, 'nickname': '旧关注'}
                ]
              : [
                  {'userId': 9, 'nickname': '新关注'},
                  {'userId': 9, 'nickname': '新关注'}
                ]
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: UserListPage(
            title: '关注', apiPath: '/api/community/user/me/following-list')));
    await tester.pumpAndSettle();
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('旧关注'), findsOneWidget);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(find.text('旧关注'), findsNothing);
    expect(find.text('新关注'), findsOneWidget);
  });
}
