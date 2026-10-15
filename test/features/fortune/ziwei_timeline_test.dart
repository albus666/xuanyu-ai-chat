import 'package:flutter_test/flutter_test.dart';
import 'package:lunar/lunar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/features/fortune/archive_relationship.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_archive_store.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_four_pillars.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_timeline.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.keyUserId: 1,
    }),
  );

  group('紫微时辰索引', () {
    test('早晚子时和其他时辰映射正确', () {
      expect(ZiweiProfile.timeIndexFor(0), 0);
      expect(ZiweiProfile.timeIndexFor(1), 1);
      expect(ZiweiProfile.timeIndexFor(12), 6);
      expect(ZiweiProfile.timeIndexFor(22), 11);
      expect(ZiweiProfile.timeIndexFor(23), 12);
    });
  });

  test('三方四正随选中宫位联动', () {
    expect(ZiweiTimelineBuilder.surroundedIndices(0), <int>{0, 4, 6, 8});
    expect(ZiweiTimelineBuilder.surroundedIndices(11), <int>{11, 3, 5, 7});
  });

  test('中宫节气四柱采用立春换年和节令换月并明确斗数分界', () {
    final profile = ZiweiProfile(
      name: '节气四柱',
      gender: '女',
      clockBirthDate: DateTime(2000, 8, 16, 3),
      effectiveBirthDate: DateTime(2000, 8, 16, 3),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(yearDivide: 'exact'),
    );

    expect(ZiweiFourPillars.solarTerm(profile), '庚辰 甲申 丙午 庚寅');
    expect(ZiweiFourPillars.chartBoundaryLabel(profile), '立春界');
    expect(
      ZiweiFourPillars.chartBoundaryLabel(
        ZiweiProfile(
          name: profile.name,
          gender: profile.gender,
          clockBirthDate: profile.clockBirthDate,
          effectiveBirthDate: profile.effectiveBirthDate,
          calendarTypeIndex: profile.calendarTypeIndex,
          settings: const ZiweiSettings(),
        ),
      ),
      '正月界',
    );
  });

  test('各宫流年虚岁以当前流年落宫为锚点顺行还原', () {
    expect(
      ZiweiTimelineBuilder.yearlyAgesForPalace(
        currentAge: 24,
        currentPalaceIndex: 1,
        palaceIndex: 1,
        maxAge: 60,
      ),
      [12, 24, 36, 48, 60],
    );
    expect(
      ZiweiTimelineBuilder.yearlyAgesForPalace(
        currentAge: 24,
        currentPalaceIndex: 1,
        palaceIndex: 2,
        maxAge: 60,
      ),
      [1, 13, 25, 37, 49],
    );
  });

  test('一天生成13个时辰节点并区分早晚子时', () {
    final items = ZiweiTimelineBuilder.hours(DateTime(2026, 8, 10));

    expect(items, hasLength(13));
    expect(items.first.subtitle, '早子时');
    expect(items.last.subtitle, '晚子时');
    expect(items.last.timeIndex, 12);
  });

  test('春节前出生者的虚岁年份按农历出生年计算', () {
    final profile = ZiweiProfile(
      name: '春节前出生',
      gender: '男',
      clockBirthDate: DateTime(2000, 1, 20, 12),
      effectiveBirthDate: DateTime(2000, 1, 20, 12),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );

    expect(Lunar.fromDate(profile.effectiveBirthDate).getYear(), 1999);
    expect(ZiweiTimelineBuilder.lunarYearForNominalAge(profile, 1), 1999);
    expect(ZiweiTimelineBuilder.lunarYearForNominalAge(profile, 2), 2000);
    expect(
      Lunar.fromDate(ZiweiTimelineBuilder.dateForNominalAge(profile, 2))
          .getYear(),
      2000,
    );
  });

  test('第一虚岁的运限日期不会早于实际出生日期', () {
    final profile = ZiweiProfile(
      name: '年末出生',
      gender: '女',
      clockBirthDate: DateTime(2000, 12, 20, 18),
      effectiveBirthDate: DateTime(2000, 12, 20, 18),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );

    expect(
      ZiweiTimelineBuilder.dateForNominalAge(profile, 1),
      profile.effectiveBirthDate,
    );
  });

  test('默认规则和中州规则标识清晰', () {
    const defaults = ZiweiSettings();
    final zhongzhou = defaults.copyWith(
      algorithm: 'zhongzhou',
      astroType: 'earth',
    );

    expect(defaults.presetName, '通行默认');
    expect(zhongzhou.presetName, '中州地盘');
    expect(zhongzhou.toRequestConfig()['algorithm'], 'zhongzhou');
  });

  test('紫微档案仅在本地完整保存规则并可删除', () async {
    final profile = ZiweiProfile(
      name: '测试档案',
      gender: '女',
      clockBirthDate: DateTime(1990, 5, 8, 13, 30),
      effectiveBirthDate: DateTime(1990, 5, 8, 13, 12),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(
        algorithm: 'zhongzhou',
        astroType: 'earth',
        useTrueSolarTime: true,
      ),
      birthPlace: '北京市',
      longitude: 116.4,
      latitude: 39.9,
    );

    await ZiweiArchiveStore.save(
      profile,
      engineName: 'iztro',
      engineVersion: '2.5.8',
      ruleCode: 'test-rule',
    );
    final saved = await ZiweiArchiveStore.loadAll();

    expect(saved, hasLength(1));
    expect(saved.single.profile.name, '测试档案');
    expect(saved.single.profile.settings.presetName, '中州地盘');
    expect(saved.single.profile.effectiveBirthDate.minute, 12);
    expect(saved.single.engineVersion, '2.5.8');
    expect(saved.single.ruleCode, 'test-rule');
    await ZiweiArchiveStore.delete(saved.single.id);
    expect(await ZiweiArchiveStore.loadAll(), isEmpty);
  });

  test('紫微本人档案重复排盘时更新而不新增', () async {
    final profile = ZiweiProfile(
      name: '玄遇用户',
      gender: '男',
      clockBirthDate: DateTime(1991, 2, 3, 8),
      effectiveBirthDate: DateTime(1991, 2, 3, 8),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );
    await ZiweiArchiveStore.save(
      profile,
      isSelf: true,
      relationship: ArchiveRelationship.self,
    );
    await ZiweiArchiveStore.save(
      profile.copyWith(name: '新昵称'),
      isSelf: true,
      relationship: ArchiveRelationship.self,
    );
    final saved = await ZiweiArchiveStore.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.isSelf, isTrue);
    expect(saved.single.profile.name, '新昵称');
  });

  test('紫微档案不会在同一设备的不同账号之间串档', () async {
    final profile = ZiweiProfile(
      name: '账号一档案',
      gender: '男',
      clockBirthDate: DateTime(1992, 6, 7, 9),
      effectiveBirthDate: DateTime(1992, 6, 7, 9),
      calendarTypeIndex: 0,
      settings: const ZiweiSettings(),
    );
    await ZiweiArchiveStore.save(profile);
    expect(await ZiweiArchiveStore.loadAll(), hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 2);
    expect(await ZiweiArchiveStore.loadAll(), isEmpty);

    await prefs.setInt(AppConstants.keyUserId, 1);
    expect(await ZiweiArchiveStore.loadAll(), hasLength(1));
  });
}
