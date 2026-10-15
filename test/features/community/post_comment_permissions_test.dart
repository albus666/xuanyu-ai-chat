import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/post_detail_page.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

void commentTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    try {
      await body(t);
    } finally {
      await t.pump(const Duration(seconds: 3));
    }
  });
}

void main() {
  late InterceptorsWrapper fake;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];
  Map<String, dynamic> post() => {
        'id': 7,
        'userId': 7,
        'nickname': '发布者',
        'content': '私密原正文',
        'mediaUrls': [],
        'topics': [],
        'mentions': [],
        'commentCount': 1,
        'helpRequest': {
          'requested': true,
          'teamId': 3,
          'teamName': '测试部落',
          'status': 'open'
        },
      };
  Map<String, dynamic> comment() => {
        'id': 42,
        'userId': 8,
        'nickname': '答疑人',
        'content': '原评论正文',
        'likeCount': 2,
        'dislikeCount': 1,
        'liked': false,
        'disliked': false,
        'teamIdentity': {'teamId': 3},
      };
  void ok(RequestOptions r, RequestInterceptorHandler h, Object? data) =>
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
  void fail(RequestOptions r, RequestInterceptorHandler h, {int code = 400}) =>
      h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': code, 'message': '本次操作未成功'}));
  void normal(RequestOptions r, RequestInterceptorHandler h) => ok(
      r,
      h,
      r.path.endsWith('/comments')
          ? {
              'list': [comment()],
              'hasMore': false
            }
          : post());
  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: post())));
    await t.pumpAndSettle();
  }

  Future<void> send(WidgetTester t, [String draft = '不能丢的草稿']) async {
    await t.enterText(find.byKey(const ValueKey('comment-text-field')), draft);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('send-comment')));
    await t.pumpAndSettle();
  }

  Finder getComment() => find.byKey(const ValueKey('comment-42'));
  Future<void> openDelete(WidgetTester t) async {
    await t.ensureVisible(getComment());
    await t.longPress(getComment());
    await t.pumpAndSettle();
    await t.tap(find.text('删除'));
    await t.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    apiClient.options.headers['Authorization'] = 'local-post-a';
    calls.clear();
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
  commentTest('评论发送业务失败保留草稿和数量', (t) async {
    respond = (r, h) => r.method == 'POST' ? fail(r, h) : normal(r, h);
    await open(t);
    await send(t);
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('comment-text-field')))
            .controller!
            .text,
        '不能丢的草稿');
    expect(find.text('共 1 条评论'), findsOneWidget);
    expect(find.text('本次操作未成功'), findsOneWidget);
  });
  commentTest('删除评论业务失败保留评论和数量', (t) async {
    respond = (r, h) => r.method == 'POST' ? fail(r, h) : normal(r, h);
    await open(t);
    await openDelete(t);
    await t.tap(find.widgetWithText(TextButton, '删除'));
    await t.pumpAndSettle();
    expect(getComment(), findsOneWidget);
    expect(find.text('共 1 条评论'), findsOneWidget);
    expect(find.text('已删除'), findsNothing);
  });
  for (final dislike in [false, true]) {
    commentTest('${dislike ? '踩' : '赞'}评论业务失败恢复原状态', (t) async {
      respond = (r, h) => r.method == 'POST' ? fail(r, h) : normal(r, h);
      await open(t);
      final icon = dislike
          ? find.descendant(
              of: getComment(),
              matching: find.byWidgetPredicate((w) =>
                  w is ReferenceActionGlyph &&
                  w.type == ReferenceActionIconType.dislike))
          : find.descendant(
              of: getComment(),
              matching: find.byIcon(Icons.favorite_border_rounded));
      await t.tap(icon);
      await t.pumpAndSettle();
      expect(
          find.descendant(
              of: getComment(), matching: find.text(dislike ? '1' : '2')),
          findsOneWidget);
      expect(find.text('本次操作未成功'), findsOneWidget);
    });
  }
  commentTest('采纳评论业务失败不能标记已解决', (t) async {
    respond = (r, h) => r.method == 'POST' ? fail(r, h) : normal(r, h);
    await open(t);
    await t.tap(find.text('采纳'));
    await t.pumpAndSettle();
    expect(find.text('已采纳'), findsNothing);
    expect(find.text('已采纳，问题标记为已解决'), findsNothing);
    expect(find.text('本次操作未成功'), findsOneWidget);
  });
  for (final comments in [false, true]) {
    commentTest('${comments ? '评论' : '详情'}无权访问时清除缓存正文和评论', (t) async {
      respond = (r, h) => r.path.endsWith('/comments') == comments
          ? fail(r, h, code: 403)
          : normal(r, h);
      await open(t);
      expect(find.text('私密原正文'), findsNothing);
      expect(find.text('原评论正文'), findsNothing);
      expect(find.byKey(const ValueKey('comment-text-field')), findsNothing);
    });
  }
  commentTest('切号清除详情评论与草稿并禁用旧操作', (t) async {
    await open(t);
    final input =
        t.widget<TextField>(find.byKey(const ValueKey('comment-text-field')));
    await t.enterText(
        find.byKey(const ValueKey('comment-text-field')), '旧账号的草稿');
    apiClient.options.headers['Authorization'] = 'local-post-b';
    apiSessionChanges.value++;
    await t.pumpAndSettle();
    expect(find.text('私密原正文'), findsNothing);
    expect(find.text('原评论正文'), findsNothing);
    expect(input.controller!.text, isEmpty);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });

  for (final code in [403, 404]) {
    commentTest('${code == 403 ? '关闭评论' : '回复对象已删除'}不误清仍可见的帖子和草稿', (t) async {
      respond =
          (r, h) => r.method == 'POST' ? fail(r, h, code: code) : normal(r, h);
      await open(t);
      if (code == 404) {
        await t
            .tap(find.descendant(of: getComment(), matching: find.text('回复')));
        await t.pump();
      }
      await send(t);
      expect(find.text('私密原正文'), findsOneWidget);
      expect(find.text('共 1 条评论'), findsOneWidget);
      expect(
          t
              .widget<TextField>(
                  find.byKey(const ValueKey('comment-text-field')))
              .controller!
              .text,
          '不能丢的草稿');
      expect(
          calls.where(
              (r) => r.path == '/api/community/post/7' && r.method == 'GET'),
          hasLength(2));
      if (code == 404) {
        expect(
            calls.where((r) => r.method == 'POST').single.data['parentId'], 42);
      }
    });
  }
  commentTest('动作被拒后详情也确认不可见才清缓存', (t) async {
    var rejected = false;
    respond = (r, h) {
      if (r.method == 'POST') {
        rejected = true;
        fail(r, h, code: 403);
      } else if (rejected && r.path == '/api/community/post/7') {
        fail(r, h, code: 404);
      } else {
        normal(r, h);
      }
    };
    await open(t);
    await send(t);
    expect(find.text('私密原正文'), findsNothing);
    expect(find.text('原评论正文'), findsNothing);
    expect(find.byKey(const ValueKey('comment-text-field')), findsNothing);
  });
  commentTest('正常发送清空本次草稿并刷新评论', (t) async {
    var sent = false;
    respond = (r, h) {
      if (r.method == 'POST') {
        sent = true;
        ok(r, h, {'id': 43});
      } else if (sent && r.path.endsWith('/comments')) {
        ok(r, h, {
          'list': [
            comment(),
            {...comment(), 'id': 43, 'content': '新评论'}
          ],
          'hasMore': false
        });
      } else {
        normal(r, h);
      }
    };
    await open(t);
    await send(t, '新评论');
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('comment-text-field')))
            .controller!
            .text,
        isEmpty);
    expect(find.byKey(const ValueKey('comment-43')), findsOneWidget);
    expect(find.text('共 2 条评论'), findsOneWidget);
  });
  commentTest('正常采纳即时展示已采纳且连点仅请求一次', (t) async {
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
    final callback = t
        .element(find.text('采纳'))
        .findAncestorWidgetOfExactType<GestureDetector>()!
        .onTap!;
    callback();
    callback();
    for (var i = 0; i < 10 && held == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    ok(held!, handler!, {'acceptedCommentId': 42, 'helpStatus': 'resolved'});
    await t.pumpAndSettle();
    expect(find.text('已采纳'), findsOneWidget);
    expect(find.text('采纳'), findsNothing);
  });
  commentTest('同一评论赞踩并发只提交一次且采用服务端结果', (t) async {
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
    final like = find.descendant(
        of: getComment(), matching: find.byIcon(Icons.favorite_border_rounded));
    final dislike = find.descendant(
        of: getComment(),
        matching: find.byWidgetPredicate((w) =>
            w is ReferenceActionGlyph &&
            w.type == ReferenceActionIconType.dislike));
    final likeAction = t
        .element(like)
        .findAncestorWidgetOfExactType<GestureDetector>()!
        .onTap!;
    final dislikeAction = t
        .element(dislike)
        .findAncestorWidgetOfExactType<GestureDetector>()!
        .onTap!;
    likeAction();
    dislikeAction();
    likeAction();
    for (var i = 0; i < 10 && held == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    ok(held!, handler!,
        {'liked': true, 'disliked': false, 'likeCount': 9, 'dislikeCount': 1});
    await t.pumpAndSettle();
    expect(
        find.descendant(
            of: getComment(), matching: find.byIcon(Icons.favorite_rounded)),
        findsOneWidget);
    expect(find.descendant(of: getComment(), matching: find.text('9')),
        findsOneWidget);
  });
  commentTest('评论权限拒绝后迟到详情不能恢复缓存', (t) async {
    RequestOptions? held;
    RequestInterceptorHandler? handler;
    respond = (r, h) {
      if (r.path.endsWith('/comments')) {
        fail(r, h, code: 404);
      } else {
        held = r;
        handler = h;
      }
    };
    await t.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: post())));
    for (var i = 0; i < 10 && held == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    await t.pump(const Duration(milliseconds: 100));
    normal(held!, handler!);
    await t.pumpAndSettle();
    expect(find.text('私密原正文'), findsNothing);
    expect(find.byKey(const ValueKey('comment-text-field')), findsNothing);
  });
  commentTest('删除确认期间切号不替新账号发请求', (t) async {
    await open(t);
    await openDelete(t);
    apiClient.options.headers['Authorization'] = 'local-post-b';
    apiSessionChanges.value++;
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, '删除'));
    await t.pumpAndSettle();
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text(imSessionChangedMessage), findsOneWidget);
  });
  commentTest('删除成功但刷新失败仍立即移除条目且只扣一次数量', (t) async {
    var deleted = false;
    respond = (r, h) {
      if (r.method == 'POST') {
        deleted = true;
        ok(r, h, {'message': '已删除'});
      } else if (deleted && r.path.endsWith('/comments')) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        normal(r, h);
      }
    };
    await open(t);
    await openDelete(t);
    await t.tap(find.widgetWithText(TextButton, '删除'));
    await t.pumpAndSettle();
    expect(getComment(), findsNothing);
    expect(find.text('共 0 条评论'), findsOneWidget);
    expect(find.text('评论加载失败'), findsOneWidget);
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    await t.tap(find.text('重试加载评论'));
    await t.pumpAndSettle();
    expect(getComment(), findsNothing);
    expect(find.text('共 0 条评论'), findsOneWidget);
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
  });
}
