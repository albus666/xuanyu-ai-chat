import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_cloud_sync_service.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';
import 'package:xuanyu/features/merit/services/muyu_knock_sound.dart';
import 'package:xuanyu/features/merit/widgets/muyu_floating_overlay.dart';
import 'package:xuanyu/features/role_diagnosis/models/life_atlas_models.dart';
import 'package:xuanyu/features/role_diagnosis/services/life_atlas_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InterceptorsWrapper interceptor;
  final requests = <RequestOptions>[];
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final birth = DateTime(2000, 1, 1);
  const achievement = LifeAtlasAchievement(
    id: 'a-title',
    title: '账号A称号',
    quote: '仅属于A',
    domain: LifeAtlasDomain.growth,
    rarityLabel: '常见',
  );

  setUpAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['playerId'];
        messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null);
      }
      return null;
    });
    await MuyuKnockSound.ensureReady();
  });

  Future<void> account(int? uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove(AppConstants.keyUserId);
    } else {
      await prefs.setInt(AppConstants.keyUserId, uid);
    }
    setupApiClientToken(uid == null ? null : 'synthetic-$uid');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
    respond = (r, h) => h.resolve(Response(
        requestOptions: r, statusCode: 200, data: {'code': 0, 'data': {}}));
    interceptor = InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, interceptor);
    await account(71);
  });
  tearDown(() {
    setupApiClientToken(null);
    apiClient.interceptors.remove(interceptor);
  });

  test('木鱼旧页面保存既不覆盖新账号也不改写旧存档', () async {
    await MeritStorageService.save(MeritSaveData(totalTaps: 100),
        syncCloud: false);
    final old = await MeritStorageService.load();
    await account(72);
    await MeritStorageService.save(MeritSaveData(totalTaps: 200),
        syncCloud: false);
    old.totalTaps = 999;
    await MeritStorageService.save(old, immediateCloud: true);
    expect((await MeritStorageService.load()).totalTaps, 200);
    expect(requests, isEmpty);
    await account(71);
    expect((await MeritStorageService.load()).totalTaps, 100);
  });

  test('未知归属的旧木鱼和图鉴键保留且不被任意账号认领', () async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = jsonEncode(MeritSaveData(totalTaps: 333).toJson());
    await prefs.setString('merit_save_v1', legacy);
    final titleKey =
        'life_atlas_main_title_v1:${LifeAtlasStore.profileKey(birth: birth, hour: 12, isMale: true)}';
    await prefs.setString(titleKey, 'legacy-title');
    expect((await MeritStorageService.load()).totalTaps, 0);
    expect(
        await LifeAtlasStore.loadMainTitleId(
            birth: birth, hour: 12, isMale: true),
        isNull);
    expect(prefs.getString('merit_save_v1'), legacy);
    expect(prefs.getString(titleKey), 'legacy-title');
  });

  test('木鱼首次隔离存档可从当前账号云端恢复', () async {
    respond =
        (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200, data: {
              'code': 0,
              'data': {'saveData': MeritSaveData(totalTaps: 321).toJson()}
            }));
    expect((await MeritStorageService.load()).totalTaps, 321);
    expect(requests.single.headers['Authorization'], 'Bearer synthetic-71');
    expect((await MeritStorageService.load()).totalTaps, 321);
    expect(requests, hasLength(1));
  });

  test('木鱼旧409响应不能落入新账号缓存', () async {
    final data = MeritSaveData(totalTaps: 100);
    await MeritStorageService.save(data, syncCloud: false);
    final entered = Completer<void>();
    late RequestInterceptorHandler pending;
    late RequestOptions oldRequest;
    respond = (r, h) {
      oldRequest = r;
      pending = h;
      entered.complete();
    };
    final upload = MeritCloudSyncService.flushUpload(data);
    await entered.future;
    await account(72);
    await MeritStorageService.save(MeritSaveData(totalTaps: 200),
        syncCloud: false);
    pending
        .resolve(Response(requestOptions: oldRequest, statusCode: 200, data: {
      'code': 409,
      'data': {'saveData': MeritSaveData(totalTaps: 999).toJson()}
    }));
    await upload;
    expect((await MeritStorageService.load()).totalTaps, 200);
    await account(71);
    expect((await MeritStorageService.load()).totalTaps, 100);
  });

  testWidgets('悬浮木鱼切号立即清空缓存且旧数据不能回灌', (tester) async {
    final controller = MuyuFloatingController.instance;
    await tester.runAsync(() async {
      await MeritStorageService.save(MeritSaveData(totalTaps: 100),
          syncCloud: false);
      await controller.initialize();
      final old = controller.data!;
      await controller.enable(data: old);
      expect(controller.enabled, isTrue);
      await account(72);
      expect(controller.data, isNull);
      expect(controller.enabled, isFalse);
      controller.syncData(old);
      expect(controller.data, isNull);
      await MeritStorageService.save(MeritSaveData(totalTaps: 200),
          syncCloud: false);
      await controller.initialize();
      expect(controller.data!.totalTaps, 200);
    });
    await tester.pump(const Duration(seconds: 3));
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  test('悬浮木鱼初始化中切号不抛出未处理异常', () async {
    final controller = MuyuFloatingController.instance;
    final entered = Completer<void>();
    late RequestOptions oldRequest;
    late RequestInterceptorHandler pending;
    respond = (r, h) {
      oldRequest = r;
      pending = h;
      entered.complete();
    };
    final load = controller.initialize();
    await entered.future;
    await account(72);
    pending
        .resolve(Response(requestOptions: oldRequest, statusCode: 200, data: {
      'code': 0,
      'data': {'saveData': MeritSaveData(totalTaps: 999).toJson()}
    }));
    await load;
    expect(controller.data, isNull);
    await MeritStorageService.save(MeritSaveData(totalTaps: 200),
        syncCloud: false);
    await controller.initialize();
    expect(controller.data!.totalTaps, 200);
  });

  test('图鉴答案成就称号均按账号隔离且切回可恢复', () async {
    await LifeAtlasStore.saveAnswers(
        birth: birth,
        hour: 12,
        isMale: true,
        answers: {'private': LifeAtlasAnswer.yes});
    await LifeAtlasStore.saveAchievement(
        birth: birth, hour: 12, isMale: true, achievement: achievement);
    await LifeAtlasStore.saveMainTitleId(
        birth: birth, hour: 12, isMale: true, achievementId: achievement.id);
    await account(72);
    expect(
        await LifeAtlasStore.loadAnswers(birth: birth, hour: 12, isMale: true),
        isEmpty);
    expect(
        await LifeAtlasStore.loadAchievements(
            birth: birth, hour: 12, isMale: true),
        isEmpty);
    expect(
        await LifeAtlasStore.loadMainTitleId(
            birth: birth, hour: 12, isMale: true),
        isNull);
    await account(71);
    expect(
        (await LifeAtlasStore.loadAchievements(
                birth: birth, hour: 12, isMale: true))
            .single
            .id,
        achievement.id);
    expect(
        await LifeAtlasStore.loadMainTitleId(
            birth: birth, hour: 12, isMale: true),
        achievement.id);
    expect(
        (await LifeAtlasStore.loadAnswers(
            birth: birth, hour: 12, isMale: true))['private'],
        LifeAtlasAnswer.yes);
  });

  test('旧图鉴页面scope不能给新账号写称号或成就', () async {
    final oldPage = ApiSessionScope();
    await account(72);
    await LifeAtlasStore.saveAchievement(
        session: oldPage,
        birth: birth,
        hour: 12,
        isMale: true,
        achievement: achievement);
    await LifeAtlasStore.saveMainTitleId(
        session: oldPage,
        birth: birth,
        hour: 12,
        isMale: true,
        achievementId: achievement.id);
    expect(
        await LifeAtlasStore.loadAchievements(
            birth: birth, hour: 12, isMale: true),
        isEmpty);
    expect(
        await LifeAtlasStore.loadMainTitleId(
            birth: birth, hour: 12, isMale: true),
        isNull);
  });
}
