import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_history_page.dart';
import 'package:xuanyu/features/consultation/teacher_workbench_page.dart';

void main() {
  late InterceptorsWrapper fake;
  final writes = <String>[];
  var bothCheckedIn = false;
  var mineCheckedIn = false;
  var failDelete = false;
  Map<String, dynamic> appointment() => {
        'id': 55,
        'status': 'accepted',
        'canCheckIn': false,
        'checkedIn': mineCheckedIn,
        'canCancelCheckIn': mineCheckedIn && !bothCheckedIn,
        'peerCheckedIn': bothCheckedIn,
        'canStart': bothCheckedIn,
        'scheduledAt':
            DateTime.now().add(const Duration(minutes: 25)).toIso8601String(),
        'peer': {'nickname': '预约测试对象'},
      };
  setUp(() {
    writes.clear();
    bothCheckedIn = false;
    mineCheckedIn = false;
    failDelete = false;
    setupApiClientToken('isolated-checkin-order-test');
    fake = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        writes.add(request.path);
        if (failDelete) {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
          return;
        }
      }
      final data = request.path.endsWith('/workbench')
          ? {
              'profile': {'userId': 2},
              'appointments': [appointment()],
              'recentOrders': [
                {
                  'id': 77,
                  'status': 'cancelled',
                  'peer': {'nickname': '已结束测试订单'}
                },
              ],
            }
          : {
              'list':
                  request.path.endsWith('/appointments') ? [appointment()] : []
            };
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'code': 0, 'data': data}));
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
    setupApiClientToken(null);
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final teacher in [false, true]) {
    testWidgets(teacher ? '老师未到签到窗口可点击查看提示，不发签到请求' : '用户未到签到窗口可点击查看提示，不发签到请求',
        (tester) async {
      await open(
          tester,
          teacher
              ? const TeacherWorkbenchPage()
              : const ConsultationHistoryPage());
      await tester.ensureVisible(find.text('到场签到'));
      await tester.tap(find.text('到场签到'));
      await tester.pumpAndSettle();
      expect(find.text('预约前30分钟内签到'), findsOneWidget);
      expect(writes, isEmpty);
      await finish(tester);
    });
  }
  testWidgets('对方签到后无需退出刷新即可启用提前发起专线', (tester) async {
    await open(tester, const ConsultationHistoryPage());
    FilledButton startButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '发起专线'));
    expect(startButton().onPressed, isNull);
    bothCheckedIn = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(startButton().onPressed, isNotNull);
    await finish(tester);
  });
  for (final failure in [false, true]) {
    testWidgets(failure ? '订单删除失败保留记录' : '订单删除需要确认，成功后移除本人列表记录',
        (tester) async {
      failDelete = failure;
      await open(tester, const TeacherWorkbenchPage());
      await tester.tap(find.text('订单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除订单记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.byTooltip('删除订单记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(writes, ['/api/consultation/sessions/77/delete-record']);
      expect(find.text('已结束测试订单'), failure ? findsOneWidget : findsNothing);
      await finish(tester);
    });
  }
  for (final teacher in [false, true]) {
    testWidgets('${teacher ? "老师" : "用户"}仅单方签到时可撤回自己的签到', (tester) async {
      mineCheckedIn = true;
      await open(
          tester,
          teacher
              ? const TeacherWorkbenchPage()
              : const ConsultationHistoryPage());
      final cancel = find.text('取消签到');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(writes,
          contains('/api/consultation/appointments/55/cancel-check-in'));
      await finish(tester);
    });
  }
}
