// Regression coverage for account-bound purchase and decoration workflows.
// Every request is intercepted; no real users, payments or server writes occur.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/partner_portrait/partner_portrait_page.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_archive_store.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/virtual_goods/decoration_center_page.dart';

void main() {
  late InterceptorsWrapper fake;
  final calls = <RequestOptions>[];
  final held = <(RequestOptions, RequestInterceptorHandler)>[];
  String? holdPath;
  final birth = DateTime(2000, 1, 1, 12);
  final record = ZiweiArchiveRecord(
    id: 'synthetic-a-record',
    createdAt: DateTime(2026, 1, 1),
    profile: ZiweiProfile(
      name: '仅甲账号测试命盘',
      gender: '女',
      clockBirthDate: birth,
      effectiveBirthDate: birth,
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserId: 77,
      'ziwei_archive_records_v1_user_77': jsonEncode([record.toJson()]),
    });
    setupApiClientToken('synthetic-paid-a');
    calls.clear();
    held.clear();
    holdPath = null;
    fake = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      if (request.path == holdPath) {
        held.add((request, handler));
        return;
      }
      final portrait = request.path.contains('partner-portrait');
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'code': 0,
          'data': portrait
              ? {
                  'profileKey': 'synthetic-profile',
                  'reportOwned': request.path.endsWith('/purchase'),
                  'reportPrice': '10',
                  'walletBalance': '100',
                  'chapters': [],
                  'tests': [],
                  'keywords': ['测试关键词'],
                }
              : {
                  'backgrounds': [],
                  'homeBackgroundId': '',
                  'avatars': [],
                  'ownedAvatars': [],
                  'entryEffects': [],
                },
        },
      ));
    });
    apiClient.interceptors.insert(0, fake);
  });

  tearDown(() {
    apiClient.interceptors.remove(fake);
    setupApiClientToken(null);
  });

  Future<void> switchAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);
    setupApiClientToken('synthetic-paid-b');
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void portraitResponse(int index, String keyword, {bool owned = false}) {
    final (request, handler) = held[index];
    handler.resolve(Response(
      requestOptions: request,
      statusCode: 200,
      data: {
        'code': 0,
        'data': {
          'profileKey': keyword,
          'reportOwned': owned,
          'reportPrice': '10',
          'walletBalance': '100',
          'chapters': [],
          'tests': [],
          'keywords': [keyword],
        },
      },
    ));
  }

  Future<void> openPortrait(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PartnerPortraitPage()));
    await frames(tester);
  }

  testWidgets('旧装扮页面切号后清空内容且不向新账号提交背景', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DecorationCenterPage(user: {'nickname': '甲账号'}),
    ));
    await tester.pumpAndSettle();
    await switchAccount();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '使用默认背景'), findsNothing);
    expect(find.text('账号已切换，请重新进入当前页面'), findsOneWidget);
    final writes = calls.where((r) => r.method == 'PATCH').toList();
    expect(writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('旧命盘购买弹窗切号后关闭且不能用新账号购买', (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PartnerPortraitPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10币  解锁完整报告'));
    await tester.pumpAndSettle();
    expect(find.text('确认解锁'), findsOneWidget);
    await switchAccount();
    await tester.pumpAndSettle();
    expect(find.text('确认解锁'), findsNothing);
    final purchases = calls.where((r) => r.path.endsWith('/purchase')).toList();
    expect(purchases, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('同账号确认购买正常提交并解锁', (tester) async {
    await openPortrait(tester);
    await tester.tap(find.text('10币  解锁完整报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认解锁'));
    await tester.pumpAndSettle();
    final purchases = calls.where((r) => r.path.endsWith('/purchase')).toList();
    expect(purchases, hasLength(1));
    expect(
        purchases.single.headers['Authorization'], 'Bearer synthetic-paid-a');
    expect(find.text('已永久解锁'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('购买提交后切号，迟到的已解锁结果不进入新账号', (tester) async {
    await openPortrait(tester);
    holdPath = '/api/fortune/partner-portrait/purchase';
    await tester.tap(find.text('10币  解锁完整报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认解锁'));
    await frames(tester);
    expect(held, hasLength(1));
    await switchAccount();
    portraitResponse(0, '甲账号私密付费结果', owned: true);
    await frames(tester);
    expect(find.text('甲账号私密付费结果'), findsNothing);
    expect(find.text('已永久解锁'), findsNothing);
    expect(held.single.$1.headers['Authorization'], 'Bearer synthetic-paid-a');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('快速切号甲乙甲时旧预览不能覆盖新会话同ID命盘', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'ziwei_archive_records_v1_user_88', jsonEncode([record.toJson()]));
    holdPath = '/api/fortune/partner-portrait/preview';
    await openPortrait(tester);
    expect(held, hasLength(1));
    await switchAccount();
    await frames(tester);
    expect(held, hasLength(2));
    await prefs.setInt(AppConstants.keyUserId, 77);
    setupApiClientToken('synthetic-paid-a-new-session');
    await frames(tester);
    expect(held, hasLength(3));
    portraitResponse(2, '最新会话预览');
    await frames(tester);
    portraitResponse(0, '迟到旧甲预览', owned: true);
    portraitResponse(1, '迟到乙预览', owned: true);
    await tester.pumpAndSettle();
    expect(find.text('最新会话预览'), findsOneWidget);
    expect(find.text('迟到旧甲预览'), findsNothing);
    expect(find.text('迟到乙预览'), findsNothing);
    expect(find.text('已永久解锁'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('同账号切换命盘甲乙甲后旧甲预览也不能覆盖最新结果', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final second = <String, dynamic>{
      ...record.toJson(),
      'id': 'synthetic-second-record',
      'createdAt': DateTime(2025, 1, 1).toIso8601String(),
      'profile': {...record.profile.toJson(), 'name': '第二测试命盘'},
    };
    await prefs.setString('ziwei_archive_records_v1_user_77',
        jsonEncode([record.toJson(), second]));
    await openPortrait(tester);
    holdPath = '/api/fortune/partner-portrait/preview';
    final staleRefresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await frames(tester);
    expect(held, hasLength(1));
    holdPath = null;
    await tester.tap(find.text('当前命盘  仅甲账号测试命盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二测试命盘'));
    await tester.pumpAndSettle();
    expect(find.text('当前命盘  第二测试命盘'), findsOneWidget);
    holdPath = '/api/fortune/partner-portrait/preview';
    await tester.tap(find.text('当前命盘  第二测试命盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅甲账号测试命盘'));
    await frames(tester);
    expect(held, hasLength(2));
    portraitResponse(1, '最新甲命盘结果');
    await frames(tester);
    portraitResponse(0, '迟到旧甲命盘结果', owned: true);
    await staleRefresh;
    await tester.pumpAndSettle();
    expect(find.text('最新甲命盘结果'), findsOneWidget);
    expect(find.text('迟到旧甲命盘结果'), findsNothing);
    expect(find.text('已永久解锁'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
