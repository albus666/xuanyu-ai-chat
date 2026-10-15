import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/archive_account_scope.dart';
import 'package:xuanyu/core/local/archive_cloud_sync.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_archive_store.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_archive_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_models.dart';
import 'package:xuanyu/features/consultation/room_chart_case_details.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform previous;
  late InterceptorsWrapper interceptor;
  late Map<String, Map<String, Map<String, dynamic>>> server;
  bool offline = false;
  Completer<void>? hold;
  Completer<void>? started;
  Future<void> login(int uid) async {
    await (await SharedPreferences.getInstance())
        .setInt(AppConstants.keyUserId, uid);
    setupApiClientToken('synthetic-$uid');
    ArchiveCloudSync.status.value = {};
  }

  Map<String, Map<String, dynamic>> rows(String kind, [int uid = 7]) =>
      server.putIfAbsent('$uid:$kind', () => {});
  String data(String note) => jsonEncode([
        {'id': 'r1', 'note': note}
      ]);
  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    dir = await Directory.systemTemp.createTemp('archive-cloud-test-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir);
    server = {};
    offline = false;
    hold = null;
    started = null;
    interceptor = InterceptorsWrapper(onRequest: (request, handler) async {
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      final uid =
          request.headers['Authorization'].toString().endsWith('-8') ? 8 : 7;
      final body = request.data as Map;
      final items = rows(body['collection'] as String, uid);
      final conflicts = <String>[];
      for (final change in body['changes'] as List) {
        final id = change['id'] as String;
        final old = items[id];
        if (old != null &&
            old['deleted'] == change['deleted'] &&
            jsonEncode(old['payload']) == jsonEncode(change['payload']))
          continue;
        if ((old?['revision'] ?? 0) != change['revision']) {
          conflicts.add(id);
          continue;
        }
        items[id] = {
          'id': id,
          'revision': (old?['revision'] as int? ?? 0) + 1,
          'deleted': change['deleted'],
          'payload': change['payload']
        };
      }
      final response = {
        'code': 0,
        'data': {'items': items.values.toList(), 'conflicts': conflicts}
      };
      if (hold != null) {
        started?.complete();
        await hold!.future;
      }
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: response));
    });
    apiClient.interceptors.insert(0, interceptor);
    await login(7);
  });
  tearDown(() async {
    setupApiClientToken(null);
    apiClient.interceptors.remove(interceptor);
    PathProviderPlatform.instance = previous;
    await dir.delete(recursive: true);
  });

  test('四种案例及补充资料清除本地后自动恢复，换号不串数据', () async {
    for (final kind in ArchiveCloudSync.collections) {
      final raw = kind == 'room_chart_case_details_v1'
          ? jsonEncode({
              'bazi:r1': {'place': '北京', 'gender': '女'}
            })
          : data('原始笔记');
      await ArchiveCloudSync.write(kind, raw);
    }
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    await File('${dir.path}/paipan_records_user_7.json').delete();
    await login(7);
    for (final kind in ArchiveCloudSync.collections) {
      final restored = await ArchiveCloudSync.read(kind, force: true);
      expect(restored,
          contains(kind == 'room_chart_case_details_v1' ? '北京' : '原始笔记'));
    }
    await login(8);
    for (final kind in ArchiveCloudSync.collections) {
      final restored =
          jsonDecode((await ArchiveCloudSync.read(kind, force: true))!);
      expect(restored, isEmpty);
      expect(rows(kind, 7), isNotEmpty);
    }
  });

  test('断网修改保留本地，联网重试；删除后换设备不会复活', () async {
    const kind = 'ziwei_archive_records_v1';
    await ArchiveCloudSync.write(kind, data('原笔记'));
    offline = true;
    await ArchiveCloudSync.write(kind, data('离线修改'));
    expect(rows(kind)['r1']!['payload']['note'], '原笔记');
    expect(ArchiveCloudSync.status.value[kind], 'pending');
    offline = false;
    expect(await ArchiveCloudSync.read(kind, force: true), contains('离线修改'));
    expect(rows(kind)['r1']!['payload']['note'], '离线修改');
    await ArchiveCloudSync.write(kind, '[]');
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    await login(7);
    expect(
        jsonDecode((await ArchiveCloudSync.read(kind, force: true))!), isEmpty);
    expect(rows(kind)['r1']!['deleted'], true);
  });

  test('多设备修改冲突不会覆盖云端或丢本地，用户可选择版本', () async {
    const kind = 'astrology_archive_records_v1';
    await ArchiveCloudSync.write(kind, data('原笔记'));
    rows(kind)['r1'] = {
      'id': 'r1',
      'revision': 2,
      'deleted': false,
      'payload': {'id': 'r1', 'note': '另一设备新笔记'}
    };
    await ArchiveCloudSync.write(kind, data('本机离线笔记'));
    expect(rows(kind)['r1']!['payload']['note'], '另一设备新笔记');
    expect(await ArchiveAccountScope.readLocalJson(kind), contains('本机离线笔记'));
    expect(ArchiveCloudSync.status.value[kind], 'conflict');
    await ArchiveCloudSync.resolveConflicts(useLocal: false);
    expect(await ArchiveAccountScope.readLocalJson(kind), contains('另一设备新笔记'));
    rows(kind)['r1']!['revision'] = 3;
    rows(kind)['r1']!['payload'] = {'id': 'r1', 'note': '再次更新'};
    await ArchiveCloudSync.write(kind, data('确认保留的本机修改'));
    await ArchiveCloudSync.resolveConflicts(useLocal: true);
    expect(rows(kind)['r1']!['payload']['note'], '确认保留的本机修改');
  });

  test('迟到的恢复响应不会写入切换后的账号', () async {
    const kind = 'qizheng_archive_records_v1';
    rows(kind)['r1'] = {
      'id': 'r1',
      'revision': 1,
      'deleted': false,
      'payload': {'id': 'r1', 'note': '账号A私有资料'}
    };
    hold = Completer<void>();
    started = Completer<void>();
    final pending = ArchiveCloudSync.read(kind, force: true);
    final assertion = expectLater(pending, throwsA(isA<Exception>()));
    await started!.future;
    await login(8);
    hold!.complete();
    await assertion;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ArchiveAccountScope.scopedKey(kind, 8)), isNull);
    expect(prefs.getString(ArchiveAccountScope.scopedKey(kind, 7)), isNull);
  });

  test('真实档案保存、编辑笔记、资料补全和删除入口均自动同步', () async {
    final bazi = PaipanRecord(
        id: 'b1',
        createdAt: DateTime(2026, 10, 10),
        displayName: '案例',
        birthDateTime: DateTime(2000, 1, 1, 12),
        isFemale: true,
        calendarTypeIndex: 0,
        summary: '己卯 丙子 戊午 戊午');
    await PaipanRecordStore.save(bazi, expectedUserId: 7);
    await PaipanRecordStore.saveCase(
        recordId: bazi.id,
        fallback: bazi,
        caseTitle: '云端案例',
        reasoningNotes: '修改后的笔记',
        commentary: '',
        expectedUserId: 7);
    await ArchiveCloudSync.read(ArchiveCloudSync.bazi, force: true);
    expect(rows(ArchiveCloudSync.bazi)['b1']!['payload']['reasoningNotes'],
        '修改后的笔记');
    final ziwei = await ZiweiArchiveStore.save(
        ZiweiProfile(
            name: '斗数案例',
            gender: '女',
            clockBirthDate: DateTime(2000, 1, 1, 12),
            effectiveBirthDate: DateTime(2000, 1, 1, 12),
            calendarTypeIndex: 0,
            settings: const ZiweiSettings()),
        expectedUserId: 7);
    await ZiweiArchiveStore.saveCase(
        fallback: ziwei,
        caseTitle: '标题',
        reasoningNotes: '斗数笔记',
        commentary: '');
    await ArchiveCloudSync.read('ziwei_archive_records_v1', force: true);
    expect(
        rows('ziwei_archive_records_v1')[ziwei.id]!['payload']
            ['reasoningNotes'],
        '斗数笔记');
    final astrology = await AstrologyArchiveStore.save(
        AstrologyProfile(
            name: '星盘案例',
            birthDateTime: DateTime(2000, 1, 1, 12),
            birthPlace: '北京',
            longitude: 116.4,
            latitude: 39.9),
        isSelf: false,
        expectedUserId: 7);
    await AstrologyArchiveStore.updateCase(astrology.id,
        caseTitle: '标题',
        reasoningNotes: '星盘笔记',
        commentary: '',
        expectedUserId: 7);
    await ArchiveCloudSync.read('astrology_archive_records_v1', force: true);
    expect(
        rows('astrology_archive_records_v1')[astrology.id]!['payload']
            ['reasoningNotes'],
        '星盘笔记');
    await RoomChartCaseDetailsStore.save(
        ['bazi:b1'], {'gender': '女', 'place': '北京'},
        expectedUserId: 7);
    await ArchiveCloudSync.read('room_chart_case_details_v1', force: true);
    expect(rows('room_chart_case_details_v1')['bazi:b1']!['payload']['place'],
        '北京');
    await ZiweiArchiveStore.delete(ziwei.id, expectedUserId: 7);
    await ArchiveCloudSync.read('ziwei_archive_records_v1', force: true);
    expect(rows('ziwei_archive_records_v1')[ziwei.id]!['deleted'], true);
  });

  test('损坏本地文件不会上传空值或覆盖旧文件', () async {
    final file = File('${dir.path}/paipan_records_user_7.json');
    await file.writeAsString('[broken');
    await ArchiveCloudSync.read(ArchiveCloudSync.bazi, force: true);
    expect(await file.readAsString(), '[broken');
    expect(rows(ArchiveCloudSync.bazi), isEmpty);
    await expectLater(
        ArchiveCloudSync.write(ArchiveCloudSync.bazi, data('新笔记')),
        throwsFormatException);
    expect(await file.readAsString(), '[broken');
  });
}
