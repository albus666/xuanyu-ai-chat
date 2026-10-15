import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/profile/orders_page.dart';

void main() {
  testWidgets('分页失败提示重试，重试仍请求同一页且去重', (tester) async {
    final pages = <int>[];
    final fake = InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      if (pages.length == 2) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'list': [
            for (var id = 1; id <= page; id++)
              {
                'id': id,
                'type': 'shop_order',
                'subject': '测试订单$id',
                'amount': 1,
                'status': 'completed',
                'canDelete': false,
              }
          ],
          'hasMore': page == 1,
        }
      }));
    });
    apiClient.interceptors.insert(0, fake);
    addTearDown(() => apiClient.interceptors.remove(fake));
    await tester.pumpWidget(const MaterialApp(home: OrdersPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('订单加载失败'), findsOneWidget);
    expect(find.text('测试订单1'), findsOneWidget);
    await tester.tap(find.text('重试加载更多'));
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 2]);
    expect(find.text('测试订单1'), findsOneWidget);
    expect(find.text('测试订单2'), findsOneWidget);
    expect(find.text('订单加载失败'), findsNothing);
  });
  for (final duringPagination in [false, true]) {
    testWidgets(
        duringPagination ? '分页未结束也能切换筛选，旧分页不能污染新列表' : '快速切换订单筛选，迟到响应不能覆盖当前结果',
        (tester) async {
      RequestOptions? delayedRequest;
      RequestInterceptorHandler? delayedHandler;
      Response<dynamic> response(RequestOptions request, String subject,
              {bool more = false}) =>
          Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'list': [
                  {
                    'id': subject.hashCode,
                    'type': 'shop_order',
                    'subject': subject,
                    'status': 'completed',
                    'amount': 1,
                    'canDelete': false,
                  }
                ],
                'hasMore': more
              },
            },
          );
      final fake = InterceptorsWrapper(onRequest: (request, handler) {
        final group = request.queryParameters['status_group'];
        final page = request.queryParameters['page'];
        if (duringPagination && group == null && page == 1) {
          handler.resolve(response(request, '原来的第一页', more: true));
        } else if (group == 'pending') {
          handler.resolve(response(request, '新筛选的订单'));
        } else {
          delayedRequest = request;
          delayedHandler = handler;
        }
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));
      await tester.pumpWidget(const MaterialApp(home: OrdersPage()));
      await tester.pump();
      if (duringPagination) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('加载更多'));
        await tester.pump();
      }
      await tester.tap(find.text('待处理'));
      await tester.pump(const Duration(milliseconds: 100));
      // 先收新筛选，再收旧请求；旧请求不应再决定界面。
      delayedHandler!.resolve(response(delayedRequest!, '旧请求返回的订单'));
      await tester.pumpAndSettle();
      expect(find.text('新筛选的订单'), findsOneWidget);
      expect(find.text('旧请求返回的订单'), findsNothing);
    });
  }
}
