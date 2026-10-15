// Correct-behavior regressions converted from the eight-scope audit probes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/core/utils/user_cache_utils.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_cloud_sync_service.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';
import 'package:xuanyu/features/role_diagnosis/services/life_atlas_store.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  Future<void> Function()? beforeResolve;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    await beforeResolve?.call();
    return path;
  }
}

PaipanRecord record(String id) => PaipanRecord(
      id: id,
      displayName: '合成案例$id',
      createdAt: DateTime(2026, 9, 28),
      birthDateTime: DateTime(2000, 1, 1, 12),
      isFemale: false,
      calendarTypeIndex: 0,
      summary: '庚辰 戊子 戊午 戊午',
      reasoningNotes: '合成笔记$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previous;
  late _Paths paths;
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final requests = <RequestOptions>[];
  File file(int uid) => File('${directory.path}/paipan_records_user_$uid.json');
  Future<void> account(int uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, uid);
    await prefs.setString(AppConstants.keyToken, 'synthetic-$uid');
    setupApiClientToken('synthetic-$uid');
    await clearUserDependentCache();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    directory = await Directory.systemTemp.createTemp('eight-scope-audit-');
    previous = PathProviderPlatform.instance;
    paths = _Paths(directory.path);
    PathProviderPlatform.instance = paths;
    requests.clear();
    respond = (r, h) => h.resolve(Response(
        requestOptions: r, statusCode: 200, data: {'code': 0, 'data': {}}));
    interceptor = InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, interceptor);
    await account(77);
  });
  tearDown(() async {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    DailyEnergyLoader.clearSession();
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  test('损坏档案保存笔记时拒绝覆盖', () async {
    const damaged = '[{"id":"旧笔记未读完"';
    await file(77).writeAsString(damaged);
    await expectLater(
        PaipanRecordStore.saveCase(
            recordId: 'new',
            fallback: record('new'),
            caseTitle: '新增',
            reasoningNotes: '合成',
            commentary: ''),
        throwsFormatException);
    expect(await file(77).readAsString(), damaged);
  });

  test('保存笔记切号时保留两个账号原档案', () async {
    await file(77).writeAsString(jsonEncode([record('old').toJson()]));
    await file(88).writeAsString(jsonEncode([record('other').toJson()]));
    final entered = Completer<void>();
    final resume = Completer<void>();
    var calls = 0;
    paths.beforeResolve = () async {
      if (++calls == 1) {
        entered.complete();
        await resume.future;
      }
    };
    final save = expectLater(
        PaipanRecordStore.saveCase(
            recordId: 'old',
            fallback: record('old'),
            caseTitle: '新笔记',
            reasoningNotes: '甲账号内容',
            commentary: ''),
        throwsStateError);
    await entered.future;
    await account(88);
    resume.complete();
    await save;
    final result = jsonDecode(await file(88).readAsString()) as List;
    expect(result.single['id'], 'other');
    expect(result.single['reasoningNotes'], '合成笔记other');
    final unchanged = jsonDecode(await file(77).readAsString()) as List;
    expect(unchanged.single['reasoningNotes'], '合成笔记old');
  });

  test('OBSERVE: 旧公共笔记归首次访问者且其他账号显示为空', () async {
    await File('${directory.path}/paipan_records.json')
        .writeAsString(jsonEncode([record('legacy').toJson()]));
    await account(88);
    expect((await PaipanRecordStore.loadAll()).single.id, 'legacy');
    await account(77);
    expect(await PaipanRecordStore.loadAll(), isEmpty);
    expect(await file(88).exists(), isTrue);
  });

  test('木鱼本地进度按账号隔离', () async {
    await MeritStorageService.save(MeritSaveData(totalTaps: 777),
        syncCloud: false);
    await account(88);
    expect((await MeritStorageService.load()).totalTaps, 0);
  });

  testWidgets('切号使木鱼旧延迟云同步失效', (tester) async {
    MeritCloudSyncService.scheduleUpload(MeritSaveData(totalTaps: 777));
    await account(88);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, isEmpty);
  });

  test('人生图鉴相同生辰也不跨账号沿用称号', () async {
    await LifeAtlasStore.saveMainTitleId(
        birth: DateTime(2000, 1, 1),
        hour: 12,
        isMale: true,
        achievementId: 'account-77-title');
    await account(88);
    expect(
        await LifeAtlasStore.loadMainTitleId(
            birth: DateTime(2000, 1, 1), hour: 12, isMale: true),
        isNull);
  });

  test('今日能量旧账号迟到结果不得重新写入缓存', () async {
    final entered = Completer<void>();
    late RequestOptions pendingRequest;
    late RequestInterceptorHandler pending;
    respond = (r, h) {
      pendingRequest = r;
      pending = h;
      entered.complete();
    };
    final load = DailyEnergyLoader.load(forceRefresh: true);
    await entered.future;
    await account(88);
    pending.resolve(
        Response(requestOptions: pendingRequest, statusCode: 200, data: {
      'code': 0,
      'data': {'content': '旧账号合成能量内容', 'date': DailyEnergyLoader.todayString()}
    }));
    expect((await load).hasError, isTrue);
    expect(DailyEnergyLoader.sessionCacheForToday(), isNull);
    respond =
        (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200, data: {
              'code': 0,
              'data': {'content': '新账号合成内容'}
            }));
    expect((await DailyEnergyLoader.load()).content, '新账号合成内容');
    expect(requests, hasLength(2));
  });
}
