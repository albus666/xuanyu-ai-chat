import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_apply_page.dart';
import 'package:xuanyu/features/message/add_group_members_page.dart';
import 'package:xuanyu/features/message/group_members_page.dart';
import 'package:xuanyu/features/message/joinable_groups_page.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';

void reply(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
    h.resolve(Response(
        requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));

void workflowTest(String name, Future<void> Function(WidgetTester) body) {
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
  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    apiClient.options.headers['Authorization'] = 'test-group-session';
    calls.clear();
    respond = (r, h) => reply(r, h, {'list': []});
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

  workflowTest('申请加载失败不伪装成暂无记录，可重试', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    expect(find.text('暂无记录'), findsNothing);
    expect(find.text('重试加载'), findsWidgets);
  });

  workflowTest('批量隐藏只移除成功项，后端跳过的记录仍保留', (tester) async {
    respond = (r, h) {
      if (r.path == '/api/im/chat/applies' &&
          r.queryParameters['status'] == 'processed') {
        reply(r, h, {
          'list': [
            {'id': 1, 'fromNickname': '记录甲', 'status': 'approved'},
            {'id': 2, 'fromNickname': '记录乙', 'status': 'approved'},
          ]
        });
      } else if (r.path.endsWith('/hide')) {
        reply(r, h, {
          'hiddenCount': 1,
          'skipped': [
            {'type': 'chatApply', 'id': 2}
          ]
        });
      } else {
        reply(r, h, {'list': []});
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('处理记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空已处理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('记录甲 · 私聊申请'), findsNothing);
    expect(find.text('记录乙 · 私聊申请'), findsOneWidget);
  });

  workflowTest('邀请候选人加载失败不能显示暂无可邀请的人', (tester) async {
    respond = (r, h) => h.reject(DioException(
        requestOptions: r, type: DioExceptionType.connectionError));
    await tester.pumpWidget(const MaterialApp(
        home: AddGroupMembersPage(conversationId: 12, existingUserIds: {})));
    await tester.pumpAndSettle();
    expect(find.text('暂无可邀请的人'), findsNothing);
    expect(find.text('重试加载'), findsOneWidget);
  });

  workflowTest('邀请业务失败不提示发送成功', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/following-list')) {
        reply(r, h, {
          'list': [
            {'userId': 8, 'nickname': '待邀请用户'}
          ]
        });
      } else if (r.path.endsWith('/add-members')) {
        h.resolve(Response(
            requestOptions: r,
            statusCode: 200,
            data: {'code': 403, 'message': '邀请失败'}));
      } else {
        reply(r, h, {'list': []});
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: AddGroupMembersPage(conversationId: 12, existingUserIds: {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待邀请用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成(1)'));
    await tester.pumpAndSettle();
    final falseSuccess = find.text('邀请已发送').evaluate().isNotEmpty;
    await tester.pump(const Duration(seconds: 3));
    expect(falseSuccess, isFalse);
  });

  workflowTest('群成员长昵称和多个身份标签在360宽度不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    respond = (r, h) => reply(r, h, {
          'list': [
            {
              'userId': 8,
              'nickname': '这是一个特别特别长的部落成员昵称用于验证布局',
              'role': 'admin',
              'muted': true,
              'membershipStatus': 'probation'
            }
          ],
          'isOwner': true,
          'canManage': true,
          'teamId': 4,
          'pendingInvites': []
        });
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(
            conversationId: 12, title: '测试部落', isTribe: true)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  Future<void> openHistoryDelete(WidgetTester tester) async {
    await tester.tap(find.text('处理记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空已处理'));
    await tester.pumpAndSettle();
  }

  workflowTest('一路申请接口失败不遮蔽其他成功记录', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/invites') && r.queryParameters.isEmpty) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else if (r.path.endsWith('/applies') && r.queryParameters.isEmpty) {
        reply(r, h, {
          'list': [
            {'id': 1, 'fromNickname': '正常私聊申请', 'status': 'pending'}
          ]
        });
      } else {
        reply(r, h, {'list': []});
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    expect(find.text('正常私聊申请'), findsOneWidget);
    expect(find.text('部分记录加载失败，请重试'), findsOneWidget);
  });

  workflowTest('空记录也能下拉刷新', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsWidgets);
    final before = calls.length;
    tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
        .onRefresh();
    await tester.pumpAndSettle();
    expect(calls.length, before + 7);
  });

  workflowTest('连续点同意和拒绝只执行第一项', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    respond = (r, h) {
      if (r.method == 'POST') {
        heldRequest = r;
        heldHandler = h;
      } else if (r.path.endsWith('/applies') && r.queryParameters.isEmpty) {
        reply(r, h, {
          'list': [
            {'id': 1, 'fromNickname': '申请人', 'status': 'pending'}
          ]
        });
      } else {
        reply(r, h, {'list': []});
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    final approve = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '同意'))
        .onPressed!;
    final reject = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '拒绝'))
        .onPressed!;
    approve();
    reject();
    approve();
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST').length, 1);
    expect(heldRequest!.path, '/api/im/chat/apply/1/approve');
    heldHandler!.resolve(Response(
        requestOptions: heldRequest!, data: {'code': 500, 'message': '处理失败'}));
    await tester.pumpAndSettle();
    expect(find.text('申请人'), findsOneWidget);
    expect(find.text('处理失败'), findsOneWidget);
  });

  for (final type in ['groupApply', 'groupInvite']) {
    workflowTest('群申请和邀请按类型分流到真实接口：$type', (tester) async {
      var rejected = false;
      final listPath = type == 'groupApply'
          ? '/api/im/group/join-applies'
          : '/api/im/group/invites';
      final actionPath = type == 'groupApply'
          ? '/api/im/group/join-apply/1/reject'
          : '/api/im/group/invite/1/reject';
      respond = (r, h) {
        if (r.path == actionPath) {
          rejected = true;
          reply(r, h, {'message': '已拒绝'});
        } else if (r.path == listPath &&
            r.queryParameters.isEmpty &&
            !rejected) {
          reply(r, h, {
            'list': [
              {
                'id': 1,
                'fromNickname': '群相关申请人',
                'status': 'pending',
                'groupName': '测试群'
              }
            ]
          });
        } else {
          reply(r, h, {'list': []});
        }
      };
      await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST').single.path, actionPath);
      expect(find.text('群相关申请人'), findsNothing);
    });
  }

  workflowTest('邀请列表失败后可重试恢复，不丢正常邀请能力', (tester) async {
    var failing = true;
    respond = (r, h) {
      if (failing) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        reply(r, h, {
          'list': [
            {'userId': 8, 'nickname': '恢复的邀请对象'}
          ]
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: AddGroupMembersPage(conversationId: 12, existingUserIds: {})));
    await tester.pumpAndSettle();
    failing = false;
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(find.text('恢复的邀请对象'), findsOneWidget);
    await tester.tap(find.text('恢复的邀请对象'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '完成(1)'))
            .onPressed,
        isNotNull);
  });

  workflowTest('记录左滑删除成功立即移除，不触发Dismissible异常', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/hide')) {
        reply(r, h, {'hiddenCount': 1, 'skipped': []});
      } else {
        reply(r, h, {
          'list': r.path.endsWith('/applies') &&
                  r.queryParameters['status'] == 'processed'
              ? [
                  {'id': 1, 'fromNickname': '左滑记录', 'status': 'approved'}
                ]
              : []
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('处理记录'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('左滑记录 · 私聊申请'), const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('左滑记录 · 私聊申请'), findsNothing);
    expect(tester.takeException(), isNull);
    tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).last)
        .onRefresh();
    await tester.pumpAndSettle();
    // 即使并发刷新携带旧副本，也不复活已经确认隐藏的记录。
    expect(find.text('左滑记录 · 私聊申请'), findsNothing);
  });

  for (final businessFailure in [false, true]) {
    workflowTest('入群正常提交与业务失败，理由去空格：$businessFailure', (tester) async {
      var applied = false;
      var callbacks = 0;
      respond = (r, h) {
        if (r.method == 'POST') {
          if (businessFailure) {
            h.resolve(Response(
                requestOptions: r, data: {'code': 400, 'message': '该群不再公开'}));
          } else {
            applied = true;
            reply(r, h, {'status': 'pending', 'applyId': 1});
          }
        } else {
          reply(r, h, {
            'list': r.path.endsWith('/groups/joinable')
                ? [
                    {
                      'conversationId': 12,
                      'name': '可申请的群',
                      'memberCount': 2,
                      'applyStatus': applied ? 'pending' : null,
                    }
                  ]
                : []
          });
        }
      };
      await tester.pumpWidget(
          MaterialApp(home: JoinableGroupsPage(onJoined: () => callbacks++)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('申请加入'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('申请加入'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextFormField), '  交流学习  ');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(
          calls.where((r) => r.method == 'POST').single.data, {'note': '交流学习'});
      expect(callbacks, businessFailure ? 0 : 1);
      expect(find.text(businessFailure ? '该群不再公开' : '已提交申请'), findsOneWidget);
      if (businessFailure) expect(find.text('已提交申请'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  workflowTest('邀请成功返回上页并通知刷新，而不是直接将对方算作成员', (tester) async {
    Object? result;
    respond = (r, h) {
      reply(
          r,
          h,
          r.method == 'POST'
              ? {
                  'invited': 1,
                  'blockedUserIds': [],
                  'busyUserIds': [],
                  'invalidUserIds': []
                }
              : {
                  'list': [
                    {'userId': 8, 'nickname': '邀请成功对象'}
                  ]
                });
    };
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AddGroupMembersPage(
                                    conversationId: 12, existingUserIds: {})));
                      },
                      child: const Text('邀请入口')),
                ))));
    await tester.tap(find.text('邀请入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请成功对象'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成(1)'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('邀请入口'), findsOneWidget);
    expect(find.byType(AddGroupMembersPage), findsNothing);
    expect(calls.where((r) => r.method == 'POST').single.data, {
      'memberIds': [8]
    });
  });

  workflowTest('切号后迟到的旧申请不能回到列表', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    respond = (r, h) {
      if (r.path.endsWith('/applies') &&
          r.queryParameters.isEmpty &&
          heldRequest == null) {
        heldRequest = r;
        heldHandler = h;
      } else {
        reply(r, h, {'list': []});
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    apiClient.options.headers['Authorization'] = 'new-group-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    reply(heldRequest!, heldHandler!, {
      'list': [
        {'id': 1, 'fromNickname': '旧账号申请', 'status': 'pending'}
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('旧账号申请'), findsNothing);
  });

  workflowTest('删除确认期间切号，不提交旧账号的记录', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': r.path.endsWith('/applies') &&
                  r.queryParameters['status'] == 'processed'
              ? [
                  {'id': 1, 'fromNickname': '旧记录', 'status': 'approved'}
                ]
              : []
        });
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    await openHistoryDelete(tester);
    apiClient.options.headers['Authorization'] = 'new-delete-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });

  for (final failSecond in [false, true]) {
    workflowTest('101条记录按100条分批，部分失败保留余项：$failSecond', (tester) async {
      var chunks = 0;
      respond = (r, h) {
        if (r.path.endsWith('/applies') &&
            r.queryParameters['status'] == 'processed') {
          reply(r, h, {
            'list': List.generate(
                101,
                (i) => {
                      'id': i + 1,
                      'fromNickname': '记录${i + 1}',
                      'status': 'approved'
                    })
          });
        } else if (r.path.endsWith('/hide')) {
          chunks++;
          if (failSecond && chunks == 2) {
            h.reject(DioException(
                requestOptions: r, type: DioExceptionType.connectionError));
          } else {
            reply(r, h, {
              'hiddenCount': (r.data['records'] as List).length,
              'skipped': []
            });
          }
        } else {
          reply(r, h, {'list': []});
        }
      };
      await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
      await tester.pumpAndSettle();
      await openHistoryDelete(tester);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(
          calls
              .where((r) => r.path.endsWith('/hide'))
              .map((r) => (r.data['records'] as List).length),
          [100, 1]);
      final chunksSent = calls.where((r) => r.path.endsWith('/hide')).toList();
      final firstId = chunksSent.first.data['records'].first['id'];
      final lastId = chunksSent.last.data['records'].single['id'];
      expect(find.text('记录$firstId · 私聊申请'), findsNothing);
      expect(find.text('记录$lastId · 私聊申请'),
          failSecond ? findsOneWidget : findsNothing);
      if (failSecond) expect(find.text('已删除100条，其余删除失败，请重试'), findsOneWidget);
    });
  }

  workflowTest('删除业务失败保留记录而非假删除', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/hide')) {
        h.resolve(Response(
            requestOptions: r, data: {'code': 500, 'message': '删除失败'}));
      } else {
        reply(r, h, {
          'list': r.path.endsWith('/applies') &&
                  r.queryParameters['status'] == 'processed'
              ? [
                  {'id': 1, 'fromNickname': '不能丢的记录', 'status': 'approved'}
                ]
              : []
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    await openHistoryDelete(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('不能丢的记录 · 私聊申请'), findsOneWidget);
    expect(find.text('删除失败'), findsOneWidget);
  });

  workflowTest('入群重新申请确认期间切号不发送旧申请', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': r.queryParameters['scope'] == 'sent'
              ? [
                  {
                    'id': 1,
                    'conversationId': 12,
                    'groupName': '旧群',
                    'status': 'withdrawn',
                    'isPublic': true,
                    'isMember': false
                  }
                ]
              : []
        });
    await tester.pumpWidget(const MaterialApp(home: ChatApplyPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的申请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再次申请'));
    await tester.pumpAndSettle();
    apiClient.options.headers['Authorization'] = 'reapply-new-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  Map<String, dynamic> memberData({bool owner = true, bool manage = true}) => {
        'list': [
          {'userId': 7, 'nickname': '当前用户', 'role': owner ? 'owner' : 'member'},
          {'userId': 8, 'nickname': '目标成员', 'role': 'member'},
        ],
        'isOwner': owner,
        'canManage': manage,
        'teamId': 4,
        'pendingInvites': [],
      };

  Future<void> openTargetMenu(WidgetTester tester) async {
    final target = find
        .ancestor(of: find.text('目标成员'), matching: find.byType(ListTile))
        .first;
    await tester
        .tap(find.descendant(of: target, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
  }

  workflowTest('移出成员确认期间切号不可执行旧权限操作', (tester) async {
    respond = (r, h) => reply(r, h, memberData());
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(conversationId: 12, title: '测试群')));
    await tester.pumpAndSettle();
    await openTargetMenu(tester);
    await tester.tap(find.text('移出群聊'));
    await tester.pumpAndSettle();
    apiClient.options.headers['Authorization'] = 'new-member-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });

  workflowTest('转让成功后刷新失败不能保留群主操作', (tester) async {
    var loads = 0;
    respond = (r, h) {
      if (r.path.endsWith('/members')) {
        if (loads++ == 0) {
          reply(r, h, memberData());
        } else {
          h.reject(DioException(
              requestOptions: r, type: DioExceptionType.connectionError));
        }
      } else {
        reply(r, h, {'message': '已转让'});
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(conversationId: 12, title: '测试群')));
    await tester.pumpAndSettle();
    await openTargetMenu(tester);
    await tester.tap(find.text('转让群主'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认转让'));
    await tester.pumpAndSettle();
    expect(find.text('重试加载'), findsOneWidget);
    await openTargetMenu(tester);
    expect(find.text('转让群主'), findsNothing);
    expect(find.text('移出群聊'), findsNothing);
    expect(find.text('设为管理员'), findsNothing);
  });

  workflowTest('普通成员没有管理操作，管理员不能转让或移出', (tester) async {
    var manager = false;
    respond = (r, h) => reply(r, h, memberData(owner: false, manage: manager));
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(conversationId: 12, title: '测试群')));
    await tester.pumpAndSettle();
    await openTargetMenu(tester);
    expect(find.text('禁言成员'), findsNothing);
    expect(find.text('移出群聊'), findsNothing);
    Navigator.of(tester.element(find.text('查看主页'))).pop();
    await tester.pumpAndSettle();
    manager = true;
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    await openTargetMenu(tester);
    expect(find.text('禁言成员'), findsOneWidget);
    expect(find.text('转让群主'), findsNothing);
    expect(find.text('设为管理员'), findsNothing);
  });

  workflowTest('设置管理员业务失败不提示成功、不改变成员身份', (tester) async {
    respond = (r, h) {
      if (r.method == 'POST') {
        h.resolve(Response(
            requestOptions: r, data: {'code': 403, 'message': '权限不足'}));
      } else {
        reply(r, h, memberData());
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(conversationId: 12, title: '测试群')));
    await tester.pumpAndSettle();
    await openTargetMenu(tester);
    await tester.tap(find.text('设为管理员'));
    await tester.pumpAndSettle();
    expect(find.text('已设为管理员'), findsNothing);
    expect(find.text('权限不足'), findsOneWidget);
    expect(find.text('重试加载'), findsOneWidget);
  });

  workflowTest('邀请连续点击只发一次，等待结果期间切号不会弹出新页面', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    respond = (r, h) {
      if (r.path.endsWith('/add-members')) {
        heldRequest = r;
        heldHandler = h;
      } else {
        reply(r, h, {
          'list': [
            {'userId': 8, 'nickname': '邀请对象'}
          ]
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: AddGroupMembersPage(conversationId: 12, existingUserIds: {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请对象'));
    await tester.pumpAndSettle();
    final invite = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '完成(1)'))
        .onPressed!;
    invite();
    invite();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((r) => r.path.endsWith('/add-members')).length, 1);
    apiClient.options.headers['Authorization'] = 'new-invite-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    reply(heldRequest!, heldHandler!, {
      'invited': 1,
      'blockedUserIds': [],
      'busyUserIds': [],
      'invalidUserIds': []
    });
    await tester.pumpAndSettle();
    expect(find.text(imSessionChangedMessage), findsOneWidget);
    expect(find.text('邀请对象'), findsNothing);
  });

  workflowTest('全部邀请被跳过时不弹出页面，统计包含无效账号', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/add-members')) {
        reply(r, h, {
          'invited': 0,
          'blockedUserIds': [],
          'busyUserIds': [],
          'invalidUserIds': [8]
        });
      } else {
        reply(r, h, {
          'list': [
            {'userId': 8, 'nickname': '无效邀请对象'}
          ]
        });
      }
    };
    await tester.pumpWidget(const MaterialApp(
        home: AddGroupMembersPage(conversationId: 12, existingUserIds: {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无效邀请对象'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成(1)'));
    await tester.pumpAndSettle();
    expect(find.text('已发送0个邀请，1人暂不可邀请'), findsOneWidget);
    expect(find.text('完成(0)'), findsOneWidget);
  });

  workflowTest('群部落中心某路失败保留我的群聊，显示重试而非空列表', (tester) async {
    respond = (r, h) {
      if (r.path.endsWith('/mine')) {
        reply(r, h, {
          'list': [
            {'conversationId': 12, 'name': '已加入的群', 'kind': 'group'}
          ]
        });
      } else {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      }
    };
    await tester.pumpWidget(const MaterialApp(home: JoinableGroupsPage()));
    await tester.pumpAndSettle();
    expect(find.text('已加入的群'), findsOneWidget);
    expect(find.text('重试加载'), findsOneWidget);
  });

  workflowTest('扫码进入未加入群聊后自动展示真实申请入口', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': r.path.endsWith('/groups/joinable')
              ? [
                  {
                    'conversationId': 42,
                    'name': '二维码测试群',
                    'memberCount': 8,
                    'maxMembers': 200,
                  }
                ]
              : []
        });
    await tester.pumpWidget(const MaterialApp(
        home: JoinableGroupsPage(initialConversationId: 42)));
    await tester.pumpAndSettle();
    expect(find.text('二维码测试群'), findsWidgets);
    expect(find.text('8 / 200 人'), findsWidgets);
    expect(find.text('填写申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  workflowTest('群申请浮层切号后隐藏旧群操作，不借新账号继续', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': r.path.endsWith('/groups/joinable')
              ? [
                  {
                    'conversationId': 42,
                    'name': '切号测试群',
                    'memberCount': 8,
                    'maxMembers': 200,
                  }
                ]
              : []
        });
    await tester.pumpWidget(const MaterialApp(home: JoinableGroupsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('切号测试群'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('切号测试群'));
    await tester.pumpAndSettle();
    expect(find.text('填写申请'), findsOneWidget);
    apiClient.options.headers['Authorization'] = 'new-group-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text(imSessionChangedMessage), findsOneWidget);
    expect(find.text('填写申请'), findsNothing);
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });

  workflowTest('成员长按菜单切号后隐藏旧账号举报和管理入口', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': [
            {'userId': 7, 'nickname': '群主', 'role': 'owner'},
            {'userId': 8, 'nickname': '待管理成员', 'role': 'member'},
          ],
          'isOwner': true,
          'canManage': true,
          'pendingInvites': [],
        });
    await tester.pumpWidget(const MaterialApp(
        home: GroupMembersPage(conversationId: 12, title: '测试群')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('待管理成员'));
    await tester.pumpAndSettle();
    expect(find.text('举报用户'), findsOneWidget);
    apiClient.options.headers['Authorization'] = 'new-member-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text(imSessionChangedMessage), findsWidgets);
    expect(find.text('举报用户'), findsNothing);
    expect(find.text('转让群主'), findsNothing);
  });

  workflowTest('群部落申请对话框切号后提交无效，不发生控制器销毁异常', (tester) async {
    respond = (r, h) => reply(r, h, {
          'list': r.path.endsWith('/groups/joinable')
              ? [
                  {'conversationId': 12, 'name': '公开测试群', 'memberCount': 2}
                ]
              : []
        });
    await tester.pumpWidget(const MaterialApp(home: JoinableGroupsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('申请加入'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('申请加入'));
    await tester.pump(const Duration(milliseconds: 500));
    apiClient.options.headers['Authorization'] = 'new-join-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
