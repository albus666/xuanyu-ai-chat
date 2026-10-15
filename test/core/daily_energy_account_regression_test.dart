import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/config/app_content_config.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/features/home/home_page.dart';
import 'package:xuanyu/app/pages/home/home_index/controller.dart';
import 'package:xuanyu/app/pages/home/today_fortune/controller.dart';
import 'package:xuanyu/app/pages/home/today_health/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InterceptorsWrapper interceptor;
  final requests = <RequestOptions>[];
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final held = <(RequestOptions, RequestInterceptorHandler)>[];
  Map<String, Object> payload(String content) => {
    'content': content,
    'date': DailyEnergyLoader.todayString(),
    'overall': 75,
    'energyVersion': 'v15-light-professional-copy',
  };
  void answer(RequestOptions r, RequestInterceptorHandler h, Object data) =>
      h.resolve(
        Response(
          requestOptions: r,
          statusCode: 200,
          data: {'code': 0, 'data': data},
        ),
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    setupApiClientToken('synthetic-a');
    DailyEnergyLoader.clearSession();
    held.clear();
    requests.clear();
    respond = (r, h) => answer(r, h, payload('当前账号'));
    interceptor = InterceptorsWrapper(
      onRequest: (r, h) {
        if (r.path == '/api/config/app-content') {
          answer(r, h, {
            'home': {'galaxyRevolutionSeconds': 420},
          });
          return;
        }
        requests.add(r);
        respond(r, h);
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    await AppContentConfig.load(force: true);
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    DailyEnergyLoader.clearSession();
  });
  Future<void> switchTo(int id) async {
    await (await SharedPreferences.getInstance()).setInt(
      AppConstants.keyUserId,
      id,
    );
    setupApiClientToken('synthetic-$id');
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test('切号不依赖额外清缓存也不能读到旧会话结果', () async {
    expect((await DailyEnergyLoader.load()).content, '当前账号');
    await switchTo(88);
    expect(DailyEnergyLoader.sessionCacheForToday(), isNull);
    respond = (r, h) => answer(r, h, payload('乙账号'));
    expect((await DailyEnergyLoader.load()).content, '乙账号');
    expect(requests, hasLength(2));
  });

  test('各账号缓存独立且重新进入当前账号可复用', () async {
    await DailyEnergyLoader.load();
    DailyEnergyLoader.clearSession();
    expect((await DailyEnergyLoader.load()).fromCache, isTrue);
    expect(requests, hasLength(1));
    await switchTo(88);
    respond = (r, h) => answer(r, h, payload('乙账号'));
    await DailyEnergyLoader.load();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${AppConstants.keyDailyFortuneCache}_user_77'),
      contains('当前账号'),
    );
    expect(
      prefs.getString('${AppConstants.keyDailyFortuneCache}_user_88'),
      contains('乙账号'),
    );
  });

  test('无归属旧缓存不作为新账号的今日能量', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.keyDailyFortuneDate,
      DailyEnergyLoader.todayString(),
    );
    await prefs.setString(
      AppConstants.keyDailyFortuneCache,
      jsonEncode(payload('旧未知账号')),
    );
    expect((await DailyEnergyLoader.load()).content, '当前账号');
    expect(requests, hasLength(1));
  });

  testWidgets('首页资料与能量并行且切号后旧响应不回填', (tester) async {
    respond = (r, h) => held.add((r, h));
    final controller = HomeIndexController()..onInit();
    final loading = controller.loadDailyEnergy();
    await frames(tester);
    expect(
      held.map((item) => item.$1.path),
      containsAll(['/api/auth/me', '/api/fortune/today-fortune']),
    );
    await switchTo(88);
    for (final item in held) {
      answer(
        item.$1,
        item.$2,
        item.$1.path == '/api/auth/me'
            ? {'birthDate': '1999-01-01', 'homeBackgroundUrl': 'synthetic'}
            : payload('旧账号能量'),
      );
    }
    await loading;
    expect(controller.birthDate, isNull);
    expect(controller.homeBackgroundUrl, isNull);
    expect(controller.energyPreview, isNull);
    expect(requests, hasLength(2));
    controller.onDelete();
    await frames(tester);
  });

  testWidgets('首页本地能量不等待资料接口，首页与详情并发只请求一次能量', (tester) async {
    respond = (r, h) => held.add((r, h));
    final controller = HomeIndexController()..onInit();
    final loading = controller.loadDailyEnergy();
    final detail = DailyEnergyLoader.load();
    await frames(tester);
    expect(
      requests.where((r) => r.path == '/api/fortune/today-fortune'),
      hasLength(1),
    );
    final energy = held.firstWhere(
      (item) => item.$1.path == '/api/fortune/today-fortune',
    );
    answer(energy.$1, energy.$2, payload('先显示能量'));
    await frames(tester);
    await loading;
    await detail;
    expect(controller.energyPreview, '先显示能量');
    final profile = held.firstWhere((item) => item.$1.path == '/api/auth/me');
    answer(profile.$1, profile.$2, {'birthDate': '1999-01-01'});
    await frames(tester);
    controller.onDelete();
    await frames(tester);
  });

  testWidgets('养生控制器旧响应不写新缓存也不恢复旧建议', (tester) async {
    respond = (r, h) => held.add((r, h));
    final controller = TodayHealthController()..onInit();
    final loading = controller.refreshHealth();
    await frames(tester);
    await switchTo(88);
    answer(held.single.$1, held.single.$2, {
      'constitution': '旧体质',
      'content': '旧建议',
    });
    await loading;
    expect(controller.tizhi, isNot(contains('旧体质')));
    expect(
      controller.sections.map((s) => s.content).join(),
      isNot(contains('旧建议')),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${AppConstants.keyDailyHealthCache}_user_88'),
      isNull,
    );
    controller.onDelete();
    await frames(tester);
  });

  test('能量详情切号立即清除已有分析而非只挡后续请求', () async {
    await DailyEnergyLoader.load();
    final controller = TodayFortuneController()..onInit();
    expect(controller.sections.single.content, '当前账号');
    await switchTo(88);
    expect(controller.sections.single.content, isNot('当前账号'));
    expect(controller.birthDate, isNull);
    controller.onDelete();
  });

  test('养生切号清除已加载的专业关注与推荐方向', () async {
    respond = (r, h) => answer(r, h, {
      'content': '甲账号建议',
      'recommendationDirection': {
        'title': '甲的方向',
        'principles': ['甲的原则'],
      },
      'ziweiHealth': {
        'available': true,
        'natal': {'bodyArea': '甲的本命关注', 'summary': '甲的本命建议'},
        'decadal': {'bodyArea': '甲的大限关注', 'summary': '甲的大限建议'},
      },
    });
    final controller = TodayHealthController()..onInit();
    await controller.refreshHealth();
    expect(controller.recommendationDirection, '甲的方向');
    expect(controller.natalFocus.bodyArea, '甲的本命关注');
    await switchTo(88);
    expect(controller.recommendationDirection, isNot(contains('甲')));
    expect(controller.recommendationPrinciples.join(), isNot(contains('甲')));
    expect(controller.natalFocus.bodyArea, isNot(contains('甲')));
    expect(controller.decadalFocus.bodyArea, isNot(contains('甲')));
    expect(controller.healthFocusAvailable, isFalse);
    controller.onDelete();
  });

  testWidgets('强制刷新后迟到旧响应不覆盖新结果', (tester) async {
    respond = (r, h) => held.add((r, h));
    final old = DailyEnergyLoader.load(forceRefresh: true);
    await frames(tester);
    final fresh = DailyEnergyLoader.load(forceRefresh: true);
    await frames(tester);
    answer(held[1].$1, held[1].$2, payload('最新'));
    expect((await fresh).content, '最新');
    answer(held[0].$1, held[0].$2, payload('旧值'));
    expect((await old).hasError, isTrue);
    expect(DailyEnergyLoader.sessionCacheForToday()!.content, '最新');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyFortuneCache),
      ),
      contains('最新'),
    );
  });

  testWidgets('首页养生迟到响应不能在切号后写回缓存或页面', (tester) async {
    tester.view.physicalSize = const Size(600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    respond = (r, h) {
      if (r.path == '/api/fortune/daily-health') {
        held.add((r, h));
      } else if (r.path == '/api/fortune/today-fortune') {
        answer(r, h, payload('能量'));
      } else {
        answer(r, h, {'list': [], 'hasMore': false});
      }
    };
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await frames(tester);
    expect(held, hasLength(1));
    await switchTo(88);
    answer(held.single.$1, held.single.$2, {'content': '甲的合成体质建议'});
    await frames(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${AppConstants.keyDailyHealthCache}_user_88'),
      isNull,
    );
    expect(
      prefs.getString('${AppConstants.keyDailyHealthCache}_user_77'),
      isNull,
    );
    expect(find.textContaining('甲的合成体质建议'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
}
