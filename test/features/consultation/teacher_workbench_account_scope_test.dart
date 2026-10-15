import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/consultation/teacher_workbench_page.dart';
import 'package:xuanyu/features/consultation/consultation_call_overlay.dart';
import 'package:xuanyu/features/consultation/teacher_profile_editor_page.dart';
import 'package:xuanyu/features/profile/teacher_apply_page.dart';

void main() {
  late InterceptorsWrapper interceptor;
  final pending = <(RequestOptions, RequestInterceptorHandler)>[];
  bool fail = false;
  setUp(() {
    pending.clear();
    fail = false;
    setupApiClientToken('teacher-a-test-only');
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      if (fail) {
        handler.reject(DioException(requestOptions: request));
      } else {
        pending.add((request, handler));
      }
    });
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
  });

  testWidgets('双方签到后老师从预约待办发起原预约专线', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TeacherWorkbenchPage()));
    await tester.pump(const Duration(milliseconds: 100));
    final get = pending.removeAt(0);
    final data = {
      'profile': {'nickname': '老师'},
      'appointments': [
        {
          'id': 51,
          'status': 'accepted',
          'checkedIn': true,
          'peerCheckedIn': true,
          'canStart': true,
          'peer': {'nickname': '测试用户'}
        }
      ]
    };
    get.$2.resolve(Response(
        requestOptions: get.$1,
        statusCode: 200,
        data: {'code': 0, 'data': data}));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('发起专线'));
    await tester.tap(find.text('发起专线'));
    await tester.pump(const Duration(milliseconds: 100));
    final start = pending.removeAt(0);
    expect(start.$1.path, '/api/consultation/appointments/51/start');
    expect(start.$1.data, {'paymentMethod': 'coin', 'agreementAccepted': true});
    start.$2.resolve(Response(requestOptions: start.$1, statusCode: 200, data: {
      'code': 0,
      'data': {
        'session': {'id': 99}
      }
    }));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ConsultationCallOverlay.instance.sessionId, 99);
    ConsultationCallOverlay.instance.close();
    await tester.pump(const Duration(milliseconds: 100));
    for (final r in pending.toList()) {
      r.$2.resolve(Response(
          requestOptions: r.$1,
          statusCode: 200,
          data: {'code': 0, 'data': data}));
    }
    pending.clear();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final page in <String, Widget>{
    '入驻': const TeacherApplyPage(),
    '工作台': const TeacherWorkbenchPage(),
  }.entries) {
    testWidgets('${page.key}切号后丢弃迟到响应并停止旧页面请求', (tester) async {
      await tester.pumpWidget(MaterialApp(home: page.value));
      await tester.pump(const Duration(milliseconds: 100));
      expect(pending, hasLength(1));
      setupApiClientToken('teacher-b-test-only');
      final request = pending.single;
      request.$2.resolve(Response(
        requestOptions: request.$1,
        statusCode: 200,
        data: {
          'code': 0,
          'data': {
            'status': 'approved',
            'profile': {'displayTitle': '旧账号老师'}
          }
        },
      ));
      await tester.pumpAndSettle();
      expect(find.text(apiSessionChangedMessage), findsOneWidget);
      expect(find.text('您已通过老师认证'), findsNothing);
      expect(find.text('旧账号老师'), findsNothing);
      expect(pending, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('名师资料置顶，保存结果立即更新工作台而无需刷新', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TeacherWorkbenchPage()));
    await tester.pump(const Duration(milliseconds: 100));
    final get = pending.removeAt(0);
    get.$2.resolve(Response(requestOptions: get.$1, statusCode: 200, data: {
      'code': 0,
      'data': {
        'profile': {
          'userId': 7,
          'nickname': '原名称',
          'serviceIntro': '原有服务介绍',
          'privatePricePerMin': 10,
          'publicPricePerMin': 6
        }
      }
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务'));
    await tester.pumpAndSettle();
    expect(find.text('名师个人介绍'), findsNothing);
    expect(tester.getTopLeft(find.text('名师资料')).dy,
        lessThan(tester.getTopLeft(find.text('服务与价格')).dy));
    await tester.tap(find.text('名师资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '立即更新的名称');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.dragUntilVisible(find.text('保存名师资料'),
        find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存名师资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存名师资料'));
    await tester.pump(const Duration(milliseconds: 100));
    final put = pending.removeAt(0);
    expect(put.$1.data['teacherName'], '立即更新的名称');
    expect(put.$1.data.containsKey('intro'), isFalse);
    put.$2.resolve(Response(requestOptions: put.$1, statusCode: 200, data: {
      'code': 0,
      'data': {
        'userId': 7,
        'nickname': '立即更新的名称',
        'serviceIntro': '原有服务介绍',
        'privatePricePerMin': 10,
        'publicPricePerMin': 6
      }
    }));
    await tester.pumpAndSettle();
    expect(pending, isEmpty);
    await tester.tap(find.text('名师资料'));
    await tester.pumpAndSettle();
    expect(find.text('立即更新的名称'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('申请类别其它显示输入框并去除说明卡片', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TeacherApplyPage()));
    await tester.pump(const Duration(milliseconds: 100));
    final request = pending.removeAt(0);
    request.$2
        .resolve(Response(requestOptions: request.$1, statusCode: 200, data: {
      'code': 0,
      'data': {'status': 'none'}
    }));
    await tester.pump(const Duration(milliseconds: 100));
    final identity = pending.removeAt(0);
    identity.$2
        .resolve(Response(requestOptions: identity.$1, statusCode: 200, data: {
      'code': 0,
      'data': {'status': 'pending'}
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('不同服务类别分别审核'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其它').last);
    await tester.pumpAndSettle();
    expect(find.text('服务类别'), findsOneWidget);
    expect(find.text('请输入服务类别'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('名师资料编辑器提交独立字段，切号后停止保存', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: TeacherProfileEditorPage(profile: {
      'nickname': '名师名称',
      'serviceIntro': '名师介绍',
      'education': '本科',
      'experienceYears': 10,
      'specialties': ['八字'],
      'privatePricePerMin': 10,
      'publicPricePerMin': 6,
    })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '独立名师名称');
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('保存名师资料'),
        find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存名师资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存名师资料'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final put = pending.removeAt(0);
    expect(put.$1.path, '/api/consultation/teacher/service');
    expect(put.$1.data['teacherName'], '独立名师名称');
    expect(put.$1.data['serviceIntro'], '名师介绍');
    expect(put.$1.data['education'], '本科');
    expect(put.$1.data['experienceYears'], 10);
    expect(put.$1.data.containsKey('nickname'), isFalse);
    expect(put.$1.data.containsKey('intro'), isFalse);
    expect(put.$1.data.containsKey('teacherAvatarUrl'), isFalse);
    setupApiClientToken('teacher-b-test-only');
    put.$2.resolve(
        Response(requestOptions: put.$1, statusCode: 200, data: {'code': 0}));
    await tester.pumpAndSettle();
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(find.text('保存名师资料'), findsNothing);
    expect(pending, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('入驻状态加载失败禁止提交未知状态申请', (tester) async {
    fail = true;
    await tester.pumpWidget(const MaterialApp(home: TeacherApplyPage()));
    await tester.pumpAndSettle();
    expect(find.text('提交审核'), findsNothing);
    expect(find.text('重新加载'), findsOneWidget);
  });
}
