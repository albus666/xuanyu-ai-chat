import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_history_page.dart';

void main() {
  for (final failDelete in [false, true]) {
    testWidgets(failDelete ? '预约记录删除失败仍保留' : '取消删除不发请求，确认成功后预约记录消失',
        (tester) async {
      setupApiClientToken('consultation-record-test');
      addTearDown(() => setupApiClientToken(null));
      var deletes = 0;
      final fake = InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method == 'POST') {
          expect(
              request.path, '/api/consultation/appointments/3/delete-record');
          deletes++;
          if (failDelete) {
            handler.reject(DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError));
            return;
          }
        }
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {
            'list': request.path.endsWith('/appointments')
                ? [
                    {
                      'id': 3,
                      'status': 'cancelled',
                      'canDelete': true,
                      'peer': {'nickname': '测试预约'}
                    },
                    {
                      'id': 4,
                      'status': 'pending',
                      'canDelete': false,
                      'peer': {'nickname': '仍待处理'}
                    },
                  ]
                : [],
          }
        }));
      });
      apiClient.interceptors.insert(0, fake);
      addTearDown(() => apiClient.interceptors.remove(fake));
      await tester
          .pumpWidget(const MaterialApp(home: ConsultationHistoryPage()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除预约记录'), findsOneWidget);
      await tester.tap(find.byTooltip('删除预约记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      await tester.tap(find.byTooltip('删除预约记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('测试预约'), failDelete ? findsOneWidget : findsNothing);
      expect(find.text('仍待处理'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
