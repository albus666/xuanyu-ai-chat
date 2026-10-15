import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// Fake the platform of the app's path_provider dependency; no real user files.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/month_calendar_sheet.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

PaipanRecord _record(String id, {bool self = false, int day = 1}) =>
    PaipanRecord(
      id: id,
      createdAt: DateTime(2026, 9, self ? 28 : 27),
      displayName: id,
      isSelf: self,
      birthDateTime: DateTime(2000, 1, day, 12),
      isFemale: false,
      calendarTypeIndex: 0,
      summary: '己卯 丙子 戊午 戊午',
      reasoningNotes: '档案笔记',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late File recordsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('calendar-archive-test-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory);
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 101});
    Get.testMode = true;
    recordsFile = File('${directory.path}/paipan_records_user_101.json');
  });

  tearDown(() async {
    Get.reset();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  Future<void> seed(List<PaipanRecord> records) async {
    await recordsFile
        .writeAsString(jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  Future<void> settleIO(WidgetTester tester) async {
    // Platform/file futures run outside the widget test's fake async clock.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 15 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> openCalendar(
      WidgetTester tester, List<PaipanRecord> records) async {
    await tester.runAsync(() => seed(records));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          home: Scaffold(
        body: MonthCalendarSheet(initial: DateTime(2026, 9, 28)),
      )),
    ));
    await settleIO(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settleIO(tester);
  }

  Future<void> openPersonal(WidgetTester tester) =>
      tapVisible(tester, find.text('切换').first);

  Future<void> deleteRow(WidgetTester tester, String id,
      {bool confirm = true}) async {
    await tapVisible(tester, find.byKey(ValueKey('calendar-delete-$id')));
    expect(find.text('删除八字档案？'), findsOneWidget);
    await tapVisible(
        tester,
        confirm
            ? find.byKey(const ValueKey('calendar-confirm-delete'))
            : find.text('取消'));
  }

  Future<List<PaipanRecord>> stored(WidgetTester tester) async =>
      (await tester.runAsync(PaipanRecordStore.loadAll))!;

  testWidgets('取消删除保留档案、笔记和当前选择', (tester) async {
    await openCalendar(tester, [_record('本人', self: true), _record('对方')]);
    await openPersonal(tester);
    await deleteRow(tester, '本人', confirm: false);
    expect(find.byKey(const ValueKey('calendar-archive-本人')), findsOneWidget);
    final records = await stored(tester);
    expect(records.length, 2);
    expect(records.first.reasoningNotes, '档案笔记');
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('本人可删除，自动切换剩余档案，删完立即显示空态', (tester) async {
    // Identical birth data must not hide one person's independently stored record.
    await openCalendar(tester, [_record('本人', self: true), _record('对方')]);
    await openPersonal(tester);
    expect(find.byType(ListTile), findsNWidgets(2));
    await deleteRow(tester, '本人');
    expect(find.byKey(const ValueKey('calendar-archive-本人')), findsNothing);
    expect((await stored(tester)).single.id, '对方');
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('calendar-archive-对方')),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget);
    await deleteRow(tester, '对方');
    expect(find.text('暂无八字档案'), findsOneWidget);
    expect(await stored(tester), isEmpty);
    Navigator.of(tester.element(find.text('暂无八字档案'))).pop();
    await settleIO(tester);
    expect(find.text('建立八字档案后即可启用'), findsOneWidget);
    expect(find.text('帮我找未来30天'), findsNothing);
  });

  testWidgets('删除已选对方后清空双方结果，两个选择列表同步且重开不恢复', (tester) async {
    await openCalendar(
        tester, [_record('本人', self: true), _record('对方', day: 2)]);
    await tester.ensureVisible(find.byType(ChoiceChip).first);
    await tester.drag(find.byType(ChoiceChip).first, const Offset(-600, 0));
    await settleIO(tester);
    await tapVisible(tester, find.text('登记婚礼'));
    await tapVisible(tester, find.text('选择对方八字档案'));
    await tapVisible(tester, find.byKey(const ValueKey('calendar-archive-对方')));
    await tapVisible(tester, find.text('对方'));
    await deleteRow(tester, '对方');
    expect(find.text('暂无可选的其他档案'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-create-partner-archive')),
        findsOneWidget);
    Navigator.of(tester.element(find.text('暂无可选的其他档案'))).pop();
    await settleIO(tester);
    expect(find.text('选择对方八字档案'), findsOneWidget);
    expect(find.text('请再选择一份对方八字档案，查看双方共同适合的日期。'), findsOneWidget);
    final recommendation = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('帮我找未来30天'),
      matching: find.byType(OutlinedButton),
    ));
    expect(recommendation.onPressed, isNull);
    await openPersonal(tester);
    expect(find.byKey(const ValueKey('calendar-archive-对方')), findsNothing);
    Navigator.of(tester.element(find.text('选择八字档案'))).pop();
    await settleIO(tester);
    await tapVisible(tester, find.text('选择对方八字档案'));
    expect(find.text('暂无可选的其他档案'), findsOneWidget);
    expect((await stored(tester)).single.id, '本人');
  });

  testWidgets('存储错误提示失败，列表和原文件都保留', (tester) async {
    await openCalendar(tester, [_record('本人', self: true)]);
    await openPersonal(tester);
    await tester.runAsync(() => recordsFile.writeAsString('invalid-json'));
    await deleteRow(tester, '本人');
    expect(find.text('删除失败，档案已保留，请稍后重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-archive-本人')), findsOneWidget);
    expect(await tester.runAsync(recordsFile.readAsString), 'invalid-json');
  });

  test('删除仅影响指定档案及上下文，不影响同生日档案或另一账号', () async {
    await seed([_record('self', self: true), _record('partner')]);
    final otherAccount = File('${directory.path}/paipan_records_user_202.json');
    await otherAccount.writeAsString(await recordsFile.readAsString());
    final originalOther = await otherAccount.readAsString();
    final contexts =
        await Directory('${directory.path}/paipan_contexts_user_101').create();
    final removedContext =
        await File('${contexts.path}/partner.txt').writeAsString('notes');
    final keptContext =
        await File('${contexts.path}/self.txt').writeAsString('keep');
    await PaipanRecordStore.delete('partner', expectedUserId: 101);
    expect((await PaipanRecordStore.loadAll()).single.id, 'self');
    expect(await removedContext.exists(), isFalse);
    expect(await keptContext.readAsString(), 'keep');
    expect(await otherAccount.readAsString(), originalOther);
  });

  test('切换账号后的旧删除请求不能操作新账号同 ID 档案', () async {
    await seed([_record('shared-id')]);
    final otherAccount = File('${directory.path}/paipan_records_user_202.json');
    await otherAccount.writeAsString(await recordsFile.readAsString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 202);
    await expectLater(
        PaipanRecordStore.delete('shared-id', expectedUserId: 101),
        throwsStateError);
    expect((await PaipanRecordStore.loadAll()).single.id, 'shared-id');
    await prefs.remove(AppConstants.keyUserId);
    await expectLater(PaipanRecordStore.delete('shared-id'), throwsStateError);
  });
}
