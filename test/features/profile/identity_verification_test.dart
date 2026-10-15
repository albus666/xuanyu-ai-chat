import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/profile/identity_verification_page.dart';
import 'package:xuanyu/features/profile/teacher_apply_page.dart';

void main() {
  late InterceptorsWrapper fake;
  final calls = <RequestOptions>[];
  Map<String, dynamic> current = {'status': 'none'};
  bool uploadFails = false;
  late Directory temp;
  late File photo;
  setUp(() async {
    calls.clear();
    current = {'status': 'none'};
    uploadFails = false;
    setupApiClientToken('identity-test-only');
    temp = await Directory.systemTemp.createTemp('identity-ui-');
    photo =
        await File('assets/zodiac/tiger.webp').copy('${temp.path}/photo.webp');
    // Provider responses are mocked; this fixture is ordinary artwork.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (_) async => photo.path);
    fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      Map<String, dynamic> data;
      if (r.path.endsWith('/upload')) {
        if (uploadFails) {
          h.resolve(Response(
              requestOptions: r,
              statusCode: 200,
              data: {'code': 400, 'message': '没有识别到身份证正面'}));
          return;
        }
        final side = (r.data as FormData)
            .fields
            .firstWhere((e) => e.key == 'side')
            .value;
        data = {'documentId': (side == 'front' ? 'a' : 'b') * 32, 'side': side};
      } else if (r.method == 'POST' && r.path.endsWith('/identity')) {
        current = {
          'id': 1,
          'status': 'pending',
          'realName': '测试姓名',
          'idCardMask': '110***********0015'
        };
        data = current;
      } else {
        data = current;
      }
      h.resolve(Response(
          requestOptions: r, statusCode: 200, data: {'code': 0, 'data': data}));
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() async {
    apiClient.interceptors.remove(fake);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'), null);
    setupApiClientToken(null);
    await temp.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester,
      {Widget page = const IdentityVerificationPage()}) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String side) async {
    final target = find.byKey(ValueKey('identity-photo-$side'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('必须同意后上传，非身份证照片不能提交', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('identity-photo-front')));
    await tester.pump();
    expect(calls.where((r) => r.path.endsWith('/upload')), isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    uploadFails = true;
    await pick(tester, 'front');
    expect(find.text('识别通过 · 点击更换'), findsNothing);
    expect(
        calls.where((r) => r.method == 'POST' && r.path.endsWith('/identity')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('相册选项避开手机底部导航栏且删除长段说明', (tester) async {
    await open(tester);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPadding);
    expect(find.textContaining('照片由阿里云身份证识别服务处理'), findsNothing);
    expect(find.text('同意身份资料用于证件识别与实名认证审核'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('identity-photo-front')));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, '从相册选择');
    expect(tester.getRect(tile).bottom, lessThanOrEqualTo(1000 - 48));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });
  testWidgets('正反面识别通过后提交，展示脱敏审核状态', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).at(0), '测试姓名');
    await tester.enterText(find.byType(TextField).at(1), '110101199001010015');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await pick(tester, 'front');
    await pick(tester, 'back');
    final submit = find.byKey(const ValueKey('identity-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final request = calls
        .singleWhere((r) => r.method == 'POST' && r.path.endsWith('/identity'));
    expect(request.data['frontId'], 'a' * 32);
    expect(request.data['backId'], 'b' * 32);
    expect(find.text('实名认证审核中'), findsOneWidget);
    expect(find.text('110101199001010015'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('切号清除旧身份资料且禁止后续请求', (tester) async {
    current = {
      'status': 'approved',
      'realName': '旧账号身份',
      'idCardMask': '110***********0015'
    };
    await open(tester);
    expect(find.text('旧账号身份'), findsOneWidget);
    final count = calls.length;
    setupApiClientToken('identity-other-test-only');
    await tester.pumpAndSettle();
    expect(find.text('旧账号身份'), findsNothing);
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(calls.length, count);
  });
  testWidgets('名师申请提供身份材料入口', (tester) async {
    await open(tester, page: const TeacherApplyPage());
    expect(find.text('实名认证与身份证正反面'), findsOneWidget);
    expect(calls.where((r) => r.path.endsWith('/identity')), hasLength(1));
  });
}
