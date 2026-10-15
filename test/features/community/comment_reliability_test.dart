import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/post_detail_page.dart';

final _post = <String, dynamic>{
  'id': 7,
  'userId': 2,
  'nickname': '发布者',
  'content': '测试作品',
  'mediaUrls': [],
  'topics': [],
  'mentions': [],
  'commentCount': 0
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('慢网评论成功不清空继续输入的下一条草稿', (tester) async {
    RequestOptions? sentRequest;
    RequestInterceptorHandler? sentHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        sentRequest = request;
        sentHandler = handler;
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/comments')
            ? {'list': [], 'hasMore': false}
            : _post
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: _post)));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('comment-text-field'));
    await tester.enterText(input, '第一条');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-comment')));
    await tester.pump();
    await tester.enterText(input, '不能丢的下一条');
    sentHandler!.resolve(Response(
        requestOptions: sentRequest!,
        statusCode: 200,
        data: {'code': 0, 'data': {}}));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '不能丢的下一条');
    expect(sentRequest!.data['content'], '第一条');
  });

  testWidgets('评论初次加载失败可重试，而不是伪装成没有评论', (tester) async {
    var reads = 0;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/comments') && reads++ == 0) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/comments')
            ? {'list': [], 'hasMore': false}
            : _post
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: _post)));
    await tester.pumpAndSettle();
    expect(find.text('评论加载失败'), findsOneWidget);
    await tester.tap(find.text('重试加载评论'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('评论加载失败'), findsNothing);
  });

  testWidgets('初次加载未返回时发评论，刷新不能被旧请求覆盖', (tester) async {
    var reads = 0;
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/comments')) {
        if (reads++ == 0) {
          oldRequest = request;
          oldHandler = handler;
          return;
        }
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {
            'list': [
              {'id': 42, 'userId': 9, 'nickname': '测试用户', 'content': '刚发布的评论'}
            ],
            'hasMore': false
          }
        }));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'code': 0, 'data': _post}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: _post)));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('comment-text-field')), '刚发布的评论');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-comment')));
    await tester.pump(const Duration(milliseconds: 100));
    oldHandler!
        .resolve(Response(requestOptions: oldRequest!, statusCode: 200, data: {
      'code': 0,
      'data': {'list': [], 'hasMore': false}
    }));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byKey(const ValueKey('comment-42')), findsOneWidget);
  });

  testWidgets('已有评论刷新失败后保留列表，重试重新请求第一页', (tester) async {
    final pages = <int>[];
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/comments')) {
        pages.add(request.queryParameters['page'] as int);
        if (pages.length == 2) {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
          return;
        }
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {
            'list': [
              {'id': 42, 'userId': 9, 'nickname': '测试用户', 'content': '原有评论'}
            ],
            'hasMore': false
          }
        }));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'code': 0, 'data': _post}));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: _post)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('comment-text-field')), '新增评论');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-comment')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comment-42')), findsOneWidget);
    await tester.ensureVisible(find.text('重试加载评论'));
    await tester.tap(find.text('重试加载评论'));
    await tester.pumpAndSettle();
    expect(pages, [1, 1, 1]);
    expect(find.text('评论加载失败'), findsNothing);
  });

  testWidgets('评论发送失败保留原文并允许重试', (tester) async {
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': request.path.endsWith('/comments')
            ? {'list': [], 'hasMore': false}
            : _post
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(
        MaterialApp(home: PostDetailPage(postId: 7, initialItem: _post)));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('comment-text-field'));
    await tester.enterText(input, '需要保留');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-comment')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '需要保留');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('send-comment')))
            .onPressed,
        isNotNull);
    expect(find.text('评论发送失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
