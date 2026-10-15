import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/features/consultation/room_chart_sheet.dart';
import 'package:xuanyu/features/consultation/room_chart_case_details.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_archive_store.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_models.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_archive_store.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_models.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_archive_store.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';

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
    directory = await Directory.systemTemp.createTemp('archive-retention-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  test('三种档案第51条后仍保留旧档案及笔记', () async {
    String? ziweiId;
    String? astrologyId;
    String? qizhengId;
    for (var i = 0; i < 55; i++) {
      final birth = DateTime(2000, 1, i + 1, 12);
      final z = await ZiweiArchiveStore.save(ZiweiProfile(
          name: '案例$i',
          gender: '女',
          clockBirthDate: birth,
          effectiveBirthDate: birth,
          calendarTypeIndex: 0,
          settings: const ZiweiSettings()));
      final a = await AstrologyArchiveStore.save(
          AstrologyProfile(
              name: '案例$i',
              birthDateTime: birth,
              birthPlace: '北京市',
              longitude: 116.4,
              latitude: 39.9),
          isSelf: false);
      final q = await QizhengArchiveStore.save(
          QizhengProfile(
              name: '案例$i',
              birthDateTime: birth,
              birthPlace: '北京市',
              longitude: 116.4,
              latitude: 39.9),
          isSelf: false);
      if (i == 0) {
        ziweiId = z.id;
        astrologyId = a.id;
        qizhengId = q.id;
        await ZiweiArchiveStore.saveCase(
            fallback: z,
            caseTitle: '保留',
            reasoningNotes: '旧笔记',
            commentary: '');
        await AstrologyArchiveStore.updateNote(a.id, '旧笔记');
        await QizhengArchiveStore.updateNote(q.id, '旧笔记');
      }
    }
    final z = await ZiweiArchiveStore.loadAll();
    final a = await AstrologyArchiveStore.loadAll();
    final q = await QizhengArchiveStore.loadAll();
    expect([z.length, a.length, q.length], [55, 55, 55]);
    expect(z.firstWhere((r) => r.id == ziweiId).reasoningNotes, '旧笔记');
    expect(a.firstWhere((r) => r.id == astrologyId).note, '旧笔记');
    expect(q.firstWhere((r) => r.id == qizhengId).note, '旧笔记');
  });

  test('星盘案例补全性别后四种盘面均可打开，重新加载仍保留且账号隔离', () async {
    await AstrologyArchiveStore.save(
        AstrologyProfile(
            name: '完整案例',
            birthDateTime: DateTime(2000, 1, 1, 12),
            birthPlace: '北京市',
            longitude: 116.4,
            latitude: 39.9),
        isSelf: false);
    final original = (await loadRoomChartCases()).single;
    expect(
        original.archiveFor(RoomChartKind.bazi).unavailableReason, isNotNull);
    await RoomChartCaseDetailsStore.save(
        original.sourceKeys, {'isFemale': true},
        expectedUserId: 77);
    final completed = (await loadRoomChartCases()).single;
    for (final kind in RoomChartKind.values) {
      expect(completed.archiveFor(kind).unavailableReason, isNull);
    }
    expect(completed.id, original.id);
    expect(completed.isFemale, isTrue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);
    expect(await RoomChartCaseDetailsStore.load(), isEmpty);
    await expectLater(
        RoomChartCaseDetailsStore.save(original.sourceKeys, {'isFemale': false},
            expectedUserId: 77),
        throwsStateError);
  });

  test('同名同生日但性别不同的案例不会被合并覆盖', () async {
    final birth = DateTime(2000, 1, 1, 12);
    for (final gender in ['男', '女']) {
      await ZiweiArchiveStore.save(ZiweiProfile(
        name: '同名案例',
        gender: gender,
        clockBirthDate: birth,
        effectiveBirthDate: birth,
        calendarTypeIndex: 0,
        settings: const ZiweiSettings(),
      ));
    }
    expect(await ZiweiArchiveStore.loadAll(), hasLength(2));
    final cases = await loadRoomChartCases();
    expect(cases, hasLength(2));
    expect(cases.map((item) => item.isFemale).toSet(), {true, false});
  });

  test('跨盘种同名同生日但出生地不同不会混盘', () async {
    final birth = DateTime(2000, 1, 1, 12);
    await AstrologyArchiveStore.save(
        AstrologyProfile(
          name: '同名案例',
          birthDateTime: birth,
          birthPlace: '北京',
          longitude: 116.4,
          latitude: 39.9,
        ),
        isSelf: false);
    await QizhengArchiveStore.save(
        QizhengProfile(
          name: '同名案例',
          birthDateTime: birth,
          birthPlace: '上海',
          longitude: 121.4,
          latitude: 31.2,
        ),
        isSelf: false);
    expect(await loadRoomChartCases(), hasLength(2));
  });

  test('跨盘种资料一致继续共用一个案例', () async {
    final birth = DateTime(2000, 1, 1, 12);
    await AstrologyArchiveStore.save(
        AstrologyProfile(
          name: '互通案例',
          birthDateTime: birth,
          birthPlace: '北京',
          longitude: 116.4,
          latitude: 39.9,
        ),
        isSelf: false);
    await QizhengArchiveStore.save(
        QizhengProfile(
          name: '互通案例',
          birthDateTime: birth,
          birthPlace: '北京',
          longitude: 116.4,
          latitude: 39.9,
        ),
        isSelf: false);
    final cases = await loadRoomChartCases();
    expect(cases, hasLength(1));
    expect(cases.single.snapshots, hasLength(2));
  });

  testWidgets('补全弹窗选择性别并保存，不要求重复填写已有出生地', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => RoomChartCaseDetailsDialog(
                              place: Region.placeholder(
                            name: '北京',
                            extPath: '北京市',
                            lng: 116.4,
                            lat: 39.9,
                          )),
                        );
                      },
                      child: const Text('补全')),
                ))));
    await tester.tap(find.text('补全'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('女'));
    await tester.pump();
    await tester.tap(find.text('保存并查看'));
    await tester.pumpAndSettle();
    expect(result?['isFemale'], true);
    expect(result?['longitude'], 116.4);
    expect(tester.takeException(), isNull);
  });
}
