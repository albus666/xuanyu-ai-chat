import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/features/consultation/room_chart_case_details.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_archive_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_models.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_archive_store.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_models.dart';
import 'package:xuanyu/features/fortune/shared_chart_archive.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_archive_store.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform previous;

  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    directory = await Directory.systemTemp.createTemp('shared-chart-archive-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  test('旧八字与星盘资料一致时合并为一人且四种专业盘均可生成', () async {
    final birth = DateTime(2000, 1, 1, 12);
    final place = Region.placeholder(
      name: '北京市',
      extPath: '北京市',
      lng: 116.4,
      lat: 39.9,
    );
    await PaipanRecordStore.save(
      PaipanRecord(
        id: 'bazi-1',
        createdAt: DateTime(2026, 9, 1),
        displayName: '共同案例',
        relationship: ArchiveRelationship.friend,
        birthDateTime: birth,
        isFemale: true,
        calendarTypeIndex: 0,
        birthPlace: place,
        summary: '庚辰 戊子 戊午 戊午',
      ),
    );
    await AstrologyArchiveStore.save(
      AstrologyProfile(
        name: '共同案例',
        birthDateTime: birth,
        birthPlace: '北京市',
        longitude: 116.4,
        latitude: 39.9,
      ),
      isSelf: false,
    );

    final cases = await loadRoomChartCases();
    expect(cases, hasLength(1));
    expect(cases.single.snapshots, hasLength(2));
    for (final kind in RoomChartKind.values) {
      expect(cases.single.archiveFor(kind).unavailableReason, isNull);
      expect(cases.single.archiveFor(kind).snapshot, isNotEmpty);
    }
  });

  test('旧星盘案例资料不全时仍保留，补全后立即可在八字与斗数打开', () async {
    await AstrologyArchiveStore.save(
      AstrologyProfile(
        name: '待补全案例',
        birthDateTime: DateTime(2000, 1, 1, 12),
        birthPlace: '北京市',
        longitude: 116.4,
        latitude: 39.9,
      ),
      isSelf: false,
    );
    final original = (await loadRoomChartCases()).single;
    expect(
      original.archiveFor(RoomChartKind.bazi).unavailableReason,
      isNotNull,
    );

    await RoomChartCaseDetailsStore.save(original.sourceKeys, <String, dynamic>{
      'isFemale': false,
    }, expectedUserId: 77);

    final completed = (await loadRoomChartCases()).single;
    expect(completed.isFemale, isFalse);
    expect(completed.archiveFor(RoomChartKind.bazi).unavailableReason, isNull);
    expect(completed.archiveFor(RoomChartKind.ziwei).unavailableReason, isNull);
  });

  test('共同修改称呼会同步到各盘投影且不覆盖旧源数据', () async {
    await AstrologyArchiveStore.save(
      AstrologyProfile(
        name: '旧称呼',
        birthDateTime: DateTime(2000, 1, 1, 12),
        birthPlace: '北京市',
        longitude: 116.4,
        latitude: 39.9,
      ),
      isSelf: false,
    );
    final original = (await loadRoomChartCases()).single;
    await updateRoomChartCaseIdentity(
      original,
      displayName: '新称呼',
      relationship: ArchiveRelationship.friend,
    );

    final updated = (await loadRoomChartCases()).single;
    expect(updated.name, '新称呼');
    expect(updated.relationship, ArchiveRelationship.friend);
    final astrology = AstrologyArchiveRecord.fromJson(
      updated.archiveFor(RoomChartKind.astrology).snapshot,
    );
    expect(astrology.profile.name, '新称呼');
    expect((await AstrologyArchiveStore.loadAll()).single.profile.name, '旧称呼');
  });

  test('共同删除会清理各盘源记录与补充资料且不会影响其他账号', () async {
    final birth = DateTime(2000, 1, 1, 12);
    await AstrologyArchiveStore.save(
      AstrologyProfile(
        name: '删除案例',
        birthDateTime: birth,
        birthPlace: '北京市',
        longitude: 116.4,
        latitude: 39.9,
      ),
      isSelf: false,
    );
    final record = (await loadRoomChartCases()).single;
    await RoomChartCaseDetailsStore.save(record.sourceKeys, <String, dynamic>{
      'isFemale': true,
    }, expectedUserId: 77);

    await deleteRoomChartCase(record);

    expect(await AstrologyArchiveStore.loadAll(), isEmpty);
    expect(await RoomChartCaseDetailsStore.load(), isEmpty);
    expect(await loadRoomChartCases(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);
    expect(await loadRoomChartCases(), isEmpty);
  });

  test('星盘与七政的同名同生日不同性别不会互相覆盖', () async {
    final birth = DateTime(2000, 1, 1, 12);
    for (final isFemale in <bool>[false, true]) {
      await AstrologyArchiveStore.save(
        AstrologyProfile(
          name: '同名案例',
          birthDateTime: birth,
          birthPlace: '北京市',
          longitude: 116.4,
          latitude: 39.9,
          isFemale: isFemale,
        ),
        isSelf: false,
      );
      await QizhengArchiveStore.save(
        QizhengProfile(
          name: '同名案例',
          birthDateTime: birth,
          birthPlace: '北京市',
          longitude: 116.4,
          latitude: 39.9,
          isFemale: isFemale,
        ),
        isSelf: false,
      );
    }

    expect(await AstrologyArchiveStore.loadAll(), hasLength(2));
    expect(await QizhengArchiveStore.loadAll(), hasLength(2));
    final cases = await loadRoomChartCases();
    expect(cases, hasLength(2));
    expect(cases.map((item) => item.isFemale).toSet(), <bool>{false, true});
  });

  test('账号切换后旧页面的删除请求会被拒绝且原档案保留', () async {
    final saved = await AstrologyArchiveStore.save(
      AstrologyProfile(
        name: '账号一案例',
        birthDateTime: DateTime(2000, 1, 1, 12),
        birthPlace: '北京市',
        longitude: 116.4,
        latitude: 39.9,
        isFemale: false,
      ),
      isSelf: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);

    await expectLater(
      AstrologyArchiveStore.delete(saved.id, expectedUserId: 77),
      throwsStateError,
    );

    await prefs.setInt(AppConstants.keyUserId, 77);
    expect(await AstrologyArchiveStore.loadAll(), hasLength(1));
  });

  test('排盘期间切号后星盘七政斗数的迟到结果都不会写入新账号', () async {
    final birth = DateTime(2000, 1, 1, 12);
    final astrology = AstrologyProfile(
      name: '迟到星盘',
      birthDateTime: birth,
      birthPlace: '北京市',
      longitude: 116.4,
      latitude: 39.9,
      isFemale: false,
    );
    final qizheng = QizhengProfile(
      name: '迟到七政',
      birthDateTime: birth,
      birthPlace: '北京市',
      longitude: 116.4,
      latitude: 39.9,
      isFemale: false,
    );
    final ziwei = ZiweiProfile(
      name: '迟到斗数',
      gender: '男',
      clockBirthDate: birth,
      effectiveBirthDate: birth,
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);

    await expectLater(
      AstrologyArchiveStore.save(astrology, isSelf: false, expectedUserId: 77),
      throwsStateError,
    );
    await expectLater(
      QizhengArchiveStore.save(qizheng, isSelf: false, expectedUserId: 77),
      throwsStateError,
    );
    await expectLater(
      ZiweiArchiveStore.save(ziwei, expectedUserId: 77),
      throwsStateError,
    );

    expect(await AstrologyArchiveStore.loadAll(), isEmpty);
    expect(await QizhengArchiveStore.loadAll(), isEmpty);
    expect(await ZiweiArchiveStore.loadAll(), isEmpty);
  });

  test('三个远程排盘加载页固定首次进入账号，重试不重新认领新账号', () {
    for (final path in <String>[
      'lib/features/fortune/astrology/astrology_page.dart',
      'lib/features/fortune/qizheng/qizheng_page.dart',
      'lib/features/fortune/ziwei/ziwei_input_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('late final Future<int?> _archiveUserId;'));
      expect(
        source,
        contains('_archiveUserId = ArchiveAccountScope.currentUserId();'),
      );
      expect(source, contains('expectedUserId: expectedUserId'));
    }
  });
}
