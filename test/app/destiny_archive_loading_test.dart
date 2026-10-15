import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/pages/home/destiny_match/controller.dart';
import 'package:xuanyu/app/pages/home/destiny_match/view.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/profile/account_birth_profile.dart';
import 'package:xuanyu/core/profile/destiny_archive_repository.dart';
import 'package:xuanyu/features/fortune/fortune_preload_coordinator.dart';

const _profile = AccountBirthProfile(
  nickname: '缓存测试',
  birthDate: '2000-01-01',
  birthTime: '12:00',
  gender: 2,
  birthPlace: '',
  birthLongitude: null,
  birthLatitude: null,
  birthTimezone: 'Asia/Shanghai',
);

class _Controller extends DestinyMatchController {
  _Controller(SharedPreferences prefs) : super(preferences: prefs);
  @override
  void onReady() {}
}

class _Adapter implements HttpClientAdapter {
  final paths = <String>[];
  final xiStarted = Completer<void>();
  Completer<ResponseBody>? heldXi;
  Completer<ResponseBody>? heldLocation;
  final locationStarted = Completer<void>();
  Map<String, dynamic> profile = _profile.toJson();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    if (options.path == '/api/auth/location') {
      if (!locationStarted.isCompleted) locationStarted.complete();
      if (heldLocation != null) return heldLocation!.future;
    }
    if (options.path == '/api/fortune/xiyongshen') {
      if (!xiStarted.isCompleted) xiStarted.complete();
      if (heldXi != null) return heldXi!.future;
    }
    if (options.path.contains('/ziwei/')) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(
        jsonEncode({
          'code': 0,
          'data': switch (options.path) {
            '/api/auth/privacy' => {'allowFateMatch': 1},
            '/api/auth/location' => {'locationCode': ''},
            '/api/fortune/fate-match' => {'list': [], 'total': 0},
            '/api/fortune/xiyongshen' => {'喜神': '土', '用神': '火'},
            _ => profile,
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;
  late _Adapter adapter;
  late SharedPreferences prefs;

  Future<void> seed({bool cached = true, bool stale = false}) async {
    final snapshot = DestinyArchiveSnapshot(
      profileKey: DestinyArchiveRepository.profileKey(_profile),
      cachedAt:
          DateTime.now().toUtc().subtract(Duration(minutes: stale ? 30 : 0)),
      birthDate: _profile.birthDate,
      title: '你好，我是戊午',
      temperament: '稳重担当 · 重视承诺',
      assetPath: null,
      xishen: '喜神 土',
      yongshen: '用神 火',
      zodiac: '兔',
      constellation: '摩羯',
      ziweiPattern: '府相朝垣',
      complete: true,
    );
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserId: 77,
      'account_birth_profile_v2_77': jsonEncode({
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'profile': _profile.toJson(),
      }),
      '${DestinyArchiveRepository.hideBirthDatePrefix}77': true,
      if (cached)
        '${DestinyArchiveRepository.cachePrefix}77':
            jsonEncode(snapshot.toJson()),
    });
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    Get.testMode = true;
    FortunePreloadCoordinator.clearMemory();
    setupApiClientToken('synthetic-archive-session');
    original = apiClient.httpClientAdapter;
    adapter = _Adapter();
    apiClient.httpClientAdapter = adapter;
    await seed();
  });
  tearDown(() {
    apiClient.httpClientAdapter = original;
    Get.reset();
    FortunePreloadCoordinator.clearMemory();
    setupApiClientToken(null);
  });

  testWidgets('缓存首帧直接展示完整卡片和已保存的开关，不闪出生日', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _Controller(prefs)..privacyReady = true;
    Get.put<DestinyMatchController>(controller);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const GetMaterialApp(home: DestinyMatchPage()),
    ));
    expect(find.text('你好，我是戊午'), findsOneWidget);
    expect(find.text('紫微格局 府相朝垣'), findsOneWidget);
    expect(find.text('八字命灵'), findsNothing);
    expect(find.text('2000-01-01'), findsNothing);
    expect(find.byKey(const ValueKey('destiny-archive-placeholder')),
        findsNothing);
    expect(find.bySemanticsLabel('显示出生日期'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('显示出生日期'));
    await tester.pumpAndSettle();
    expect(find.text('2000-01-01'), findsOneWidget);
    expect(prefs.getBool('${DestinyArchiveRepository.hideBirthDatePrefix}77'),
        false);
    await tester.runAsync(controller.initialize);
    await tester.pumpAndSettle();
    expect(find.text('2000-01-01'), findsOneWidget);
    expect(controller.hideMyBirthDate, false);
    expect(
        adapter.paths.where((p) => p.contains('/fortune/xiyongshen')), isEmpty);
  });

  test('冷启动从磁盘恢复，换账号或修改出生资料后不复用旧卡片', () async {
    expect(DestinyArchiveRepository.peek(prefs)?.title, '你好，我是戊午');
    AccountBirthProfileRepository.clearMemory();
    expect(DestinyArchiveRepository.peek(prefs)?.title, '你好，我是戊午');
    await prefs.setInt(AppConstants.keyUserId, 88);
    expect(DestinyArchiveRepository.peek(prefs), isNull);
    await prefs.setInt(AppConstants.keyUserId, 77);
    await AccountBirthProfileRepository.invalidateCurrent();
    expect(DestinyArchiveRepository.peek(prefs), isNull);
    await prefs.setString(
        'account_birth_profile_v2_77',
        jsonEncode({
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
          'profile': {..._profile.toJson(), 'birthDate': '2001-02-03'},
        }));
    expect(DestinyArchiveRepository.peek(prefs), isNull);
  });

  test('慢网首开在标签准备期间不发布半张卡片，完成后整体更新', () async {
    await seed(cached: false);
    adapter.heldXi = Completer<ResponseBody>();
    final controller = _Controller(prefs);
    controller.onInit();
    final pending = controller.loadArchive();
    await adapter.xiStarted.future;
    expect(controller.archiveReady, false);
    expect(controller.xishen, isEmpty);
    expect(controller.minglingAssetPath, isNull);
    adapter.heldXi!.complete(ResponseBody.fromString(
      '{"code":0,"data":{"喜神":"土","用神":"火"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    ));
    await pending;
    expect(controller.archiveReady, true);
    expect(controller.xishen, '喜神 土');
    expect(controller.minglingAssetPath, isNotNull);
    expect(controller.hideMyBirthDate, true);
    controller.onClose();
  });

  test('后台刷新期间保留整张缓存，失败不清空已有标签', () async {
    await seed(stale: true);
    adapter.heldXi = Completer<ResponseBody>();
    final controller = _Controller(prefs);
    controller.onInit();
    final pending = controller.loadArchive();
    await adapter.xiStarted.future;
    expect(controller.archiveReady, true);
    expect(controller.ziweiPattern, '府相朝垣');
    adapter.heldXi!.completeError(DioException(
      requestOptions: RequestOptions(path: '/api/fortune/xiyongshen'),
      type: DioExceptionType.connectionError,
    ));
    await pending;
    expect(controller.archiveReady, true);
    expect(controller.xishen, '喜神 土');
    expect(controller.ziweiPattern, '府相朝垣');
    expect(controller.archiveError, isNull);
    controller.onClose();
  });

  test('请求中途换账号，迟到结果不得展示或写入缓存', () async {
    await seed(cached: false);
    adapter.heldXi = Completer<ResponseBody>();
    final pending = DestinyArchiveRepository.load();
    final expectation =
        expectLater(pending, throwsA(isA<ApiSessionChangedException>()));
    await adapter.xiStarted.future;
    await prefs.setInt(AppConstants.keyUserId, 88);
    setupApiClientToken('synthetic-next-archive-session');
    adapter.heldXi!.complete(ResponseBody.fromString(
      '{"code":0,"data":{"喜神":"土","用神":"火"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    ));
    await expectation;
    expect(
        prefs.getString('${DestinyArchiveRepository.cachePrefix}77'), isNull);
    expect(
        prefs.getString('${DestinyArchiveRepository.cachePrefix}88'), isNull);
  });

  test('过期出生资料先校准，再计算并缓存新生日卡片', () async {
    await seed(cached: false);
    await prefs.setString(
        'account_birth_profile_v2_77',
        jsonEncode({
          'cachedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 30))
              .toIso8601String(),
          'profile': _profile.toJson(),
        }));
    adapter.profile = {..._profile.toJson(), 'birthDate': '2001-02-03'};
    adapter.heldXi = Completer<ResponseBody>();
    final pending = DestinyArchiveRepository.load();
    await adapter.xiStarted.future;
    expect(AccountBirthProfileRepository.peek(prefs)?.birthDate, '2001-02-03');
    adapter.heldXi!.complete(ResponseBody.fromString(
      '{"code":0,"data":{"喜神":"土","用神":"火"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    ));
    final result = await pending;
    expect(result.birthDate, '2001-02-03');
    expect(DestinyArchiveRepository.peek(prefs)?.birthDate, '2001-02-03');
  });

  test('初始化定位请求迟到且换账号时安全结束，无异步异常', () async {
    adapter.heldLocation = Completer<ResponseBody>();
    final controller = _Controller(prefs);
    controller.onInit();
    final pending = controller.initialize();
    await adapter.locationStarted.future;
    await prefs.setInt(AppConstants.keyUserId, 88);
    setupApiClientToken('synthetic-next-archive-session');
    adapter.heldLocation!.complete(ResponseBody.fromString(
      '{"code":0,"data":{"locationCode":"old-user-location"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    ));
    await pending;
    expect(controller.currentLocation, isNot('old-user-location'));
    expect(adapter.paths.where((path) => path == '/api/fortune/fate-match'),
        isEmpty);
    controller.onClose();
  });
}
