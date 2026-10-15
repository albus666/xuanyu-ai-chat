import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/consultation/consultation_after_sales_page.dart';
import 'package:xuanyu/features/consultation/teacher_income_page.dart';
import 'package:xuanyu/features/consultation/teacher_schedule_page.dart';
import 'package:xuanyu/features/consultation/teacher_settlement_amount.dart';

void main() {
  late InterceptorsWrapper fake;
  final requests = <RequestOptions>[];
  Map<String, dynamic> data = {};
  RequestOptions? heldRequest;
  RequestInterceptorHandler? heldHandler;
  bool hold = false;
  bool fail = false;

  Response<dynamic> response(RequestOptions request) => Response(
        requestOptions: request,
        statusCode: 200,
        data: {'code': 0, 'data': data},
      );

  setUp(() {
    requests.clear();
    data = {};
    hold = false;
    fail = false;
    heldRequest = null;
    heldHandler = null;
    setupApiClientToken('teacher-a-test-only');
    fake = InterceptorsWrapper(
      onRequest: (request, handler) {
        requests.add(request);
        if (hold) {
          heldRequest = request;
          heldHandler = handler;
        } else if (fail) {
          handler.reject(DioException(requestOptions: request));
        } else {
          handler.resolve(response(request));
        }
      },
    );
    apiClient.interceptors.insert(0, fake);
  });

  tearDown(() {
    apiClient.interceptors.remove(fake);
    setupApiClientToken(null);
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump(const Duration(milliseconds: 100));
  }

  final pages = <String, Widget>{
    '排班': const TeacherSchedulePage(),
    '售后': const ConsultationAfterSalesPage(),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key}切号后忽略迟到响应且不请求新账号', (tester) async {
      hold = true;
      await open(tester, entry.value);
      expect(heldHandler, isNotNull);
      final count = requests.length;
      setupApiClientToken('teacher-b-test-only');
      data = {'status': 'approved', 'notice': '旧老师私密说明', 'list': []};
      heldHandler!.resolve(response(heldRequest!));
      await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
      expect(find.text(apiSessionChangedMessage), findsOneWidget);
      expect(find.text('旧老师私密说明'), findsNothing);
      expect(find.text('您已通过老师认证'), findsNothing);
      expect(requests.length, count);
    });
  }

  testWidgets('排班加载失败不能提交默认排班', (tester) async {
    fail = true;
    await open(tester, const TeacherSchedulePage());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('保存设置'), findsNothing);
    expect(find.text('重新加载'), findsOneWidget);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });

  testWidgets('后端返回非预设提前小时数不会导致排班崩溃', (tester) async {
    data = {'enabled': true, 'minNoticeHours': 3, 'weekly': []};
    await open(tester, const TeacherSchedulePage());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('3小时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排班保存连续点击只提交一次', (tester) async {
    data = {'enabled': false, 'weekly': []};
    await open(tester, const TeacherSchedulePage());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    hold = true;
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存设置'),
    );
    button.onPressed!();
    button.onPressed!();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requests.where((request) => request.method == 'PUT'), hasLength(1));
    heldHandler!.resolve(response(heldRequest!));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('售后连续提交只发起一次', (tester) async {
    data = {'list': []};
    await open(
      tester,
      const ConsultationAfterSalesPage(
        initialSession: {'id': 9, 'chargedAmount': 10},
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.enterText(find.byType(TextField), '测试咨询过程中无法听到对方的声音');
    hold = true;
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交平台核查'),
    );
    button.onPressed!();
    button.onPressed!();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    hold = false;
    heldHandler!.resolve(response(heldRequest!));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('提现金额向下取分且仅支付宝', (tester) async {
    data = {
      'settlement': {'availableAmount': '100.0099', 'minimumWithdrawal': 50},
      'list': [],
    };
    await open(tester, const TeacherIncomePage());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('¥100.00'), findsOneWidget);
    await tester.tap(find.text('申请提现'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '100.00',
    );
    expect(find.text('微信'), findsNothing);
    expect(find.text('银行卡'), findsNothing);
    expect(find.text('支付宝'), findsOneWidget);
  });

  for (final available in ['-80.00', '0.00']) {
    testWidgets('退款欠款可见且不能提现（余额 $available）', (tester) async {
      data = {
        'settlement': {
          'availableAmount': available,
          'debtAmount': available == '0.00' ? 80 : 0,
          'minimumWithdrawal': 1,
        },
        'list': [],
      };
      await open(tester, const TeacherIncomePage());
      await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
      expect(find.text('¥0.00'), findsWidgets);
      expect(find.text('待抵扣金额 ¥80.00'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '申请提现'))
            .onPressed,
        isNull,
      );
    });
  }

  test('可提现金额精确截断到分，保留边界整数分', () {
    for (final sample in {
      '100.0099': '100.00',
      '0.29': '0.29',
      '1.9999': '1.99',
      '-1': '0.00',
      '0.0099': '0.00',
      'NaN': '0.00',
      'Infinity': '0.00',
    }.entries) {
      expect(withdrawableAmountText(sample.key), sample.value);
    }
  });
}
