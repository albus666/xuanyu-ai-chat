import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/team_home_page.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';

void teamTest(String name, Future<void> Function(WidgetTester) body) {
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
  var member = true;
  var pending = false;
  void ok(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
  void deny(RequestOptions r, RequestInterceptorHandler h) =>
      h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': 403, 'message': '操作未获允许'}));
  Map<String, dynamic> resource(int id) => {
        'id': id,
        'title': '回归资料$id',
        'type': 'text',
        'content': '不可串号正文',
        'visibility': 'members'
      };
  void normal(RequestOptions r, RequestInterceptorHandler h) {
    ok(
        r,
        h,
        r.path == '/api/im/team/conversation/88'
            ? {
                'teamId': 3,
                'name': '测试部落',
                'isMember': member,
                'canManage': member,
                'isPublic': true,
                'following': true,
                'applyStatus': pending ? 'pending' : null
              }
            : r.path.endsWith('/info')
                ? {'isMember': member, 'canManage': member}
                : r.path.endsWith('/resources')
                    ? {
                        'list': [resource(31)],
                        'hasMore': false
                      }
                    : {'list': [], 'hasMore': false});
  }

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(
        home: TeamHomePage(conversationId: 88, initialName: '测试部落')));
    await t.pumpAndSettle();
  }

  Finder followButton(String label) =>
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label);
  Future<void> action(WidgetTester t, String label) async {
    await t.scrollUntilVisible(find.text(label), 300,
        scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  Future<void> resourceMenu(WidgetTester t, String action) async {
    await t.scrollUntilVisible(find.text('回归资料31'), 350,
        scrollable: find.byType(Scrollable).first);
    final tile = find.ancestor(
        of: find.text('回归资料31'), matching: find.byType(ExpansionTile));
    final menu = find.descendant(
        of: tile, matching: find.byType(PopupMenuButton<String>));
    await t.ensureVisible(menu);
    await t.pumpAndSettle();
    await t.tap(menu);
    await t.pumpAndSettle();
    await t.tap(find.text(action));
    await t.pumpAndSettle();
  }

  setUp(() {
    member = true;
    pending = false;
    calls.clear();
    apiClient.options.headers['Authorization'] = 'local-team-a';
    respond = normal;
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

  teamTest('主页加载业务失败显示重试而非假空主页', (t) async {
    respond = deny;
    await open(t);
    expect(find.text('重试加载'), findsOneWidget);
    expect(find.text('申请加入'), findsNothing);
    respond = normal;
    await t.tap(find.text('重试加载'));
    await t.pumpAndSettle();
    expect(find.text('进入部落群聊'), findsOneWidget);
  });
  teamTest('关注业务失败停止操作且不提示成功', (t) async {
    respond = (r, h) => r.method == 'POST' ? deny(r, h) : normal(r, h);
    await open(t);
    await t.tap(find.byTooltip('取消关注'));
    await t.pumpAndSettle();
    expect(t.widget<IconButton>(followButton('关注部落')).onPressed, isNull);
    expect(find.text('操作未获允许'), findsWidgets);
  });
  teamTest('关注连续点击只请求一次且正常更新', (t) async {
    RequestOptions? held;
    RequestInterceptorHandler? handler;
    respond = (r, h) {
      if (r.method == 'POST') {
        held = r;
        handler = h;
      } else {
        normal(r, h);
      }
    };
    await open(t);
    final callback = t.widget<IconButton>(followButton('取消关注')).onPressed!;
    callback();
    callback();
    for (var i = 0; i < 10 && held == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    ok(held!, handler!, {'following': false});
    await t.pumpAndSettle();
    expect(find.byTooltip('关注部落'), findsOneWidget);
  });
  teamTest('申请确认期间切号清空表单且不替新账号提交', (t) async {
    member = false;
    await open(t);
    await action(t, '申请加入');
    await t.enterText(find.byType(TextFormField), '原账号的申请理由');
    apiClient.options.headers['Authorization'] = 'local-team-b';
    apiSessionChanges.value++;
    await t.pump();
    expect(find.text('提交申请'), findsNothing);
    expect(find.text('原账号的申请理由'), findsNothing);
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text(imSessionChangedMessage), findsWidgets);
  });
  teamTest('删除资料业务失败不能提示已删除', (t) async {
    respond = (r, h) => r.method == 'DELETE' ? deny(r, h) : normal(r, h);
    await open(t);
    await resourceMenu(t, '删除');
    await t.tap(find.widgetWithText(FilledButton, '删除'));
    await t.pumpAndSettle();
    expect(find.text('资料已删除'), findsNothing);
    expect(find.text('操作未获允许'), findsWidgets);
  });
  teamTest('切号立即清除部落资料及管理入口', (t) async {
    await open(t);
    await t.scrollUntilVisible(find.text('回归资料31'), 350,
        scrollable: find.byType(Scrollable).first);
    apiClient.options.headers['Authorization'] = 'local-team-b';
    apiSessionChanges.value++;
    await t.pumpAndSettle();
    expect(find.text('回归资料31'), findsNothing);
    expect(find.text('发布资料'), findsNothing);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });
  teamTest('非成员能查看公开主页且不请求成员详情', (t) async {
    member = false;
    await open(t);
    expect(find.text('申请加入'), findsOneWidget);
    expect(
        calls.where(
            (r) => r.path.endsWith('/info') || r.path.endsWith('/members')),
        isEmpty);
    await t.scrollUntilVisible(find.text('资料库'), 350,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('发布资料'), findsNothing);
  });
  teamTest('不存在的部落显示重试且无关注操作', (t) async {
    respond = (r, h) => ok(r, h, null);
    await open(t);
    expect(find.text('重试加载'), findsOneWidget);
    expect(t.widget<IconButton>(followButton('关注部落')).onPressed, isNull);
    expect(calls, hasLength(1));
  });
  for (final endpoint in ['cases', 'posts', 'resources']) {
    teamTest('$endpoint业务失败显示错误，重试可以恢复', (t) async {
      respond = (r, h) {
        if (r.path.endsWith('/$endpoint')) {
          ok(r, h, {'list': 'invalid'});
        } else {
          normal(r, h);
        }
      };
      await open(t);
      await t.scrollUntilVisible(find.text('列表数据异常，请重试'), 350,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('列表数据异常，请重试'), findsOneWidget);
      respond = normal;
      final retry = find.text(endpoint == 'resources' ? '重试' : '重试加载');
      await t.ensureVisible(retry);
      await t.pumpAndSettle();
      await t.tap(retry);
      await t.pumpAndSettle();
      expect(find.text('列表数据异常，请重试'), findsNothing);
    });
  }
  teamTest('正常申请和撤回实时更新，重复申请只弹一个窗口', (t) async {
    member = false;
    respond = (r, h) => r.method == 'POST' ? ok(r, h, {}) : normal(r, h);
    await open(t);
    final apply = t
        .widget<FilledButton>(find.widgetWithText(FilledButton, '申请加入'))
        .onPressed!;
    apply();
    apply();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.enterText(find.byType(TextFormField), '  线上答疑  ');
    await t.tap(find.text('提交申请'));
    await t.pumpAndSettle();
    expect(find.text('撤回申请'), findsOneWidget);
    expect(
        calls.where((r) => r.method == 'POST').single.data, {'note': '线上答疑'});
    await action(t, '撤回申请');
    expect(find.text('申请加入'), findsOneWidget);
    expect(calls.where((r) => r.path.endsWith('/withdraw')), hasLength(1));
  });
  teamTest('撤回申请业务失败不能提示撤回成功', (t) async {
    member = false;
    pending = true;
    respond = (r, h) => r.method == 'POST' ? deny(r, h) : normal(r, h);
    await open(t);
    await action(t, '撤回申请');
    expect(find.text('申请已撤回'), findsNothing);
    expect(find.text('操作未获允许'), findsWidgets);
  });
  teamTest('关注结果不确定必须重新加载，不能盲目再次切换', (t) async {
    respond = (r, h) => r.method == 'POST' ? ok(r, h, {}) : normal(r, h);
    await open(t);
    await t.tap(find.byTooltip('取消关注'));
    await t.pumpAndSettle();
    expect(find.text('重试加载'), findsOneWidget);
    expect(t.widget<IconButton>(followButton('关注部落')).onPressed, isNull);
  });
  teamTest('旧主页请求切号后返回不能再次显示旧资料', (t) async {
    RequestOptions? held;
    RequestInterceptorHandler? handler;
    respond = (r, h) {
      held = r;
      handler = h;
    };
    await t.pumpWidget(const MaterialApp(
        home: TeamHomePage(conversationId: 88, initialName: '测试部落')));
    for (var i = 0; i < 10 && held == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    apiClient.options.headers['Authorization'] = 'local-team-b';
    apiSessionChanges.value++;
    normal(held!, handler!);
    await t.pumpAndSettle();
    expect(find.text(imSessionChangedMessage), findsOneWidget);
    expect(find.text('进入部落群聊'), findsNothing);
    expect(calls, hasLength(1));
  });
  teamTest('编辑资料切号后清除原正文且不发保存请求', (t) async {
    await open(t);
    await resourceMenu(t, '编辑');
    expect(find.text('不可串号正文'), findsOneWidget);
    apiClient.options.headers['Authorization'] = 'local-team-b';
    apiSessionChanges.value++;
    await t.pumpAndSettle();
    expect(find.text('不可串号正文'), findsNothing);
    expect(find.text('保存'), findsNothing);
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    expect(calls.where((r) => r.method != 'GET'), isEmpty);
  });
  teamTest('发布资料成功后立即加载新列表', (t) async {
    var created = false;
    respond = (r, h) {
      if (r.method == 'POST') {
        created = true;
        ok(r, h, {'id': 32});
      } else if (r.path.endsWith('/resources') && created) {
        ok(r, h, {
          'list': [resource(32)],
          'hasMore': false
        });
      } else {
        normal(r, h);
      }
    };
    await open(t);
    await action(t, '发布资料');
    await t.enterText(find.byType(TextField).at(0), '新资料');
    await t.enterText(find.byType(TextField).at(1), '新正文');
    await t.tap(find.widgetWithText(FilledButton, '发布'));
    await t.pumpAndSettle();
    expect(find.text('回归资料32'), findsOneWidget);
    expect(find.text('资料已发布'), findsOneWidget);
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
  });
  teamTest('保存资料业务失败不会提示更新成功', (t) async {
    respond = (r, h) => r.method == 'PATCH' ? deny(r, h) : normal(r, h);
    await open(t);
    await resourceMenu(t, '编辑');
    await t.tap(find.widgetWithText(FilledButton, '保存'));
    await t.pumpAndSettle();
    expect(find.text('资料已更新'), findsNothing);
    expect(find.text('操作未获允许'), findsWidgets);
  });
  teamTest('删除确认时切号不能删除旧账号资料', (t) async {
    await open(t);
    await resourceMenu(t, '删除');
    apiClient.options.headers['Authorization'] = 'local-team-b';
    apiSessionChanges.value++;
    await t.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    expect(calls.where((r) => r.method == 'DELETE'), isEmpty);
  });
  teamTest('资料分页重复且还有下一页时停止并提示重试', (t) async {
    respond = (r, h) => r.path.endsWith('/resources')
        ? ok(r, h, {
            'list': [resource(31)],
            'hasMore': true
          })
        : normal(r, h);
    await open(t);
    await t.scrollUntilVisible(find.text('资料分页异常，请重试'), 350,
        scrollable: find.byType(Scrollable).first);
    expect(calls.where((r) => r.path.endsWith('/resources')), hasLength(2));
    expect(find.text('回归资料31'), findsNothing);
  });
}
