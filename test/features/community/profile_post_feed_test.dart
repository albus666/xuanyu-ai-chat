import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/profile_post_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfilePostFeed feed;
  late InterceptorsWrapper fake;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];
  final held = <(RequestOptions, RequestInterceptorHandler)>[];

  void reply(RequestOptions r, RequestInterceptorHandler h, List<int> ids,
          {bool more = false}) =>
      h.resolve(Response(requestOptions: r, data: {
        'code': 0,
        'data': {
          'list': ids.map((id) => {'id': id}).toList(),
          'hasMore': more
        }
      }));
  void fail(RequestOptions r, RequestInterceptorHandler h) => h.reject(
      DioException(requestOptions: r, type: DioExceptionType.connectionError));

  setUp(() {
    calls.clear();
    held.clear();
    apiClient.options.headers['Authorization'] = 'profile-feed-test';
    respond = (r, h) => reply(r, h, []);
    fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, fake);
    feed = ProfilePostFeed(() => '/api/community/favorites', pageSize: 2);
  });
  tearDown(() {
    feed.dispose();
    apiClient.interceptors.remove(fake);
    apiClient.options.headers.remove('Authorization');
  });

  test('数量取已过滤列表的总数且切号后清空', () async {
    respond = (r, h) => h.resolve(Response(requestOptions: r, data: {
          'code': 0,
          'data': {
            'list': [
              {'id': 1}
            ],
            'total': 31,
            'hasMore': true
          }
        }));
    await feed.load();
    expect(feed.total, 31);
    expect(feed.items.length, 1);
    feed.reset();
    expect(feed.total, isNull);
  });

  test('分页按 ID 去重并保留顺序', () async {
    respond = (r, h) => reply(
        r, h, r.queryParameters['page'] == 1 ? [1, 2] : [2, 3],
        more: true);
    await feed.load();
    await feed.load();
    expect(feed.items.map((e) => e['id']), [1, 2, 3]);
    expect(calls.map((e) => e.queryParameters['page']), [1, 2]);
  });

  test('下一页失败保留数据，不跳页，不反复自动重试', () async {
    respond = (r, h) => r.queryParameters['page'] == 1
        ? reply(r, h, [1, 2], more: true)
        : fail(r, h);
    await feed.load();
    await feed.load();
    expect(feed.items.length, 2);
    expect(feed.error, isNotNull);
    await feed.load();
    expect(calls.length, 2);
    respond = (r, h) => reply(r, h, [3]);
    await feed.retry();
    expect(calls.last.queryParameters['page'], 2);
    expect(feed.items.map((e) => e['id']), [1, 2, 3]);
    expect(feed.error, isNull);
  });

  test('末页刷新失败也能重试第一页，失败期间保留旧内容', () async {
    respond = (r, h) => reply(r, h, [1]);
    await feed.load();
    expect(feed.hasMore, isFalse);
    respond = fail;
    await feed.refresh();
    expect(feed.items.single['id'], 1);
    respond = (r, h) => reply(r, h, [2]);
    await feed.retry();
    expect(calls.last.queryParameters['page'], 1);
    expect(feed.items.single['id'], 2);
  });

  test('刷新取代未完成旧请求，旧响应和旧结束状态都不能覆盖新请求', () async {
    final arrivals = [Completer<void>(), Completer<void>()];
    respond = (r, h) {
      held.add((r, h));
      arrivals[held.length - 1].complete();
    };
    final old = feed.load();
    await arrivals[0].future;
    final fresh = feed.refresh();
    await arrivals[1].future;
    reply(held[0].$1, held[0].$2, [1]);
    await old;
    expect(feed.loading, isTrue);
    expect(feed.items, isEmpty);
    reply(held[1].$1, held[1].$2, [2]);
    await fresh;
    expect(feed.loading, isFalse);
    expect(feed.items.single['id'], 2);
  });

  test('切号立即清除私有收藏，迟到的旧账号响应不能恢复', () async {
    respond = (r, h) => reply(r, h, [1], more: true);
    await feed.load();
    final arrival = Completer<void>();
    respond = (r, h) {
      held.add((r, h));
      arrival.complete();
    };
    final pending = feed.load();
    await arrival.future;
    apiClient.options.headers['Authorization'] = 'another-profile-feed-test';
    apiSessionChanges.value++;
    expect(feed.items, isEmpty);
    reply(held.single.$1, held.single.$2, [2]);
    await pending;
    expect(feed.items, isEmpty);
    expect(feed.loading, isFalse);
    expect(held.single.$1.headers['Authorization'], 'profile-feed-test');
  });

  for (final body in [
    {
      'code': 500,
      'data': {'list': [], 'hasMore': false}
    },
    {'code': 0, 'data': {}},
    {
      'code': 0,
      'data': {
        'list': [{}]
      }
    },
  ]) {
    test('异常响应不能伪装成空列表：$body', () async {
      respond = (r, h) => h.resolve(Response(requestOptions: r, data: body));
      await feed.load();
      expect(feed.error, isNotNull);
      expect(feed.loaded, isFalse);
      expect(feed.hasMore, isTrue);
    });
  }

  test('空页误报有下一页时不继续循环请求', () async {
    respond = (r, h) => reply(r, h, [], more: true);
    await feed.load();
    await feed.load();
    expect(feed.hasMore, isFalse);
    expect(calls.length, 1);
  });

  test('同一页加载中的重复点击只发一次请求', () async {
    final arrival = Completer<void>();
    respond = (r, h) {
      held.add((r, h));
      arrival.complete();
    };
    final pending = feed.load();
    await arrival.future;
    await feed.load();
    expect(calls.length, 1);
    reply(held.single.$1, held.single.$2, [1]);
    await pending;
  });

  test('页面关闭后迟到响应不再通知或写数据', () async {
    final temporary = ProfilePostFeed(() => '/test/profile');
    final arrival = Completer<void>();
    var notices = 0;
    temporary.addListener(() => notices++);
    respond = (r, h) {
      held.add((r, h));
      arrival.complete();
    };
    final pending = temporary.load();
    await arrival.future;
    temporary.dispose();
    reply(held.single.$1, held.single.$2, [1]);
    await pending;
    expect(notices, 1);
    expect(temporary.items, isEmpty);
  });
}
