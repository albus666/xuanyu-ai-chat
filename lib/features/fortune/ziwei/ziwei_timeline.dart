import 'package:lunar/lunar.dart';

import 'ziwei_models.dart';

class ZiweiTimelineItem {
  const ZiweiTimelineItem({
    required this.key,
    required this.date,
    required this.timeIndex,
    required this.title,
    required this.subtitle,
    required this.tertiary,
    this.palaceIndex,
    this.age,
    this.lunarYear,
    this.lunarMonth,
  });

  final String key;
  final DateTime date;
  final int timeIndex;
  final String title;
  final String subtitle;
  final String tertiary;
  final int? palaceIndex;
  final int? age;
  final int? lunarYear;
  final int? lunarMonth;
}

class ZiweiTimelineBuilder {
  ZiweiTimelineBuilder._();

  static List<ZiweiTimelineItem> decadals(
    ZiweiChartData data,
    ZiweiProfile profile,
  ) {
    final result = data.decadals.map((palace) {
      final decadal = palace.decadal;
      final startLunarYear = lunarYearForNominalAge(
        profile,
        decadal.startAge,
      );
      return ZiweiTimelineItem(
        key: 'decadal-${palace.index}',
        date: dateForNominalAge(profile, decadal.startAge),
        timeIndex: 6,
        title: '${decadal.startAge}～${decadal.endAge}岁',
        subtitle: '$startLunarYear',
        tertiary: decadal.ganZhi,
        palaceIndex: palace.index,
        age: decadal.startAge,
        lunarYear: startLunarYear,
      );
    }).toList();
    final firstAge = data.decadals.first.decadal.startAge;
    if (firstAge > 1) {
      final soulPalace = data.astrolabe.palaces.firstWhere(
        (palace) => palace.earthlyBranch == data.astrolabe.soulPalaceBranch,
      );
      result.insert(
        0,
        ZiweiTimelineItem(
          key: 'decadal-child',
          date: profile.effectiveBirthDate,
          timeIndex: profile.birthTimeIndex,
          title: '起限前',
          subtitle: '童限',
          tertiary: '1～${firstAge - 1}岁',
          palaceIndex: soulPalace.index,
          age: 1,
        ),
      );
    }
    return result;
  }

  static List<ZiweiTimelineItem> years(
    ZiweiPalace decadalPalace,
    ZiweiProfile profile,
  ) {
    final startAge = decadalPalace.decadal.startAge;
    final endAge = decadalPalace.decadal.endAge;
    return [
      for (var age = startAge; age <= endAge; age++) _yearItem(profile, age),
    ];
  }

  static List<ZiweiTimelineItem> childYears(
    ZiweiChartData data,
    ZiweiProfile profile,
  ) {
    final endAge = data.decadals.first.decadal.startAge - 1;
    return [
      for (var age = 1; age <= endAge; age++) _yearItem(profile, age),
    ];
  }

  static ZiweiTimelineItem _yearItem(ZiweiProfile profile, int age) {
    final year = lunarYearForNominalAge(profile, age);
    final date = dateForNominalAge(profile, age);
    final lunar = Lunar.fromDate(date);
    final ganZhi = profile.settings.yearDivide == 'exact'
        ? lunar.getYearInGanZhiExact()
        : lunar.getYearInGanZhi();
    return ZiweiTimelineItem(
      key: 'year-$year',
      date: date,
      timeIndex: 6,
      title: '$year',
      subtitle: '$age岁',
      tertiary: ganZhi,
      age: age,
      lunarYear: year,
    );
  }

  /// 紫微运限使用虚岁；虚岁在农历新年递增，不能直接套用公历出生年。
  static int lunarYearForNominalAge(ZiweiProfile profile, int age) {
    final birthLunarYear = Lunar.fromDate(profile.effectiveBirthDate).getYear();
    return birthLunarYear + age - 1;
  }

  /// 流年命宫每年顺行一宫；以引擎当前流年落宫为锚点还原各宫虚岁序列。
  static List<int> yearlyAgesForPalace({
    required int? currentAge,
    required int currentPalaceIndex,
    required int palaceIndex,
    int maxAge = 120,
  }) {
    if (currentAge == null || currentAge < 1 || maxAge < 1) return const [];
    final offset = (palaceIndex - currentPalaceIndex) % 12;
    final firstAge = (currentAge + offset - 1) % 12 + 1;
    return [for (var age = firstAge; age <= maxAge; age += 12) age];
  }

  /// 取该虚岁农历年中的稳定日期，避开春节、立春等年界。
  /// 第一虚岁若出生在年中之后，则不能生成早于出生时刻的日期。
  static DateTime dateForNominalAge(ZiweiProfile profile, int age) {
    final lunarYear = lunarYearForNominalAge(profile, age);
    final lunar = Lunar.fromYmdHms(lunarYear, 6, 15, 12, 0, 0);
    final solar = lunar.getSolar();
    final date = DateTime(
      solar.getYear(),
      solar.getMonth(),
      solar.getDay(),
      12,
    );
    if (age == 1 && date.isBefore(profile.effectiveBirthDate)) {
      return profile.effectiveBirthDate;
    }
    return date;
  }

  static List<ZiweiTimelineItem> months(
    int lunarYear,
    ZiweiProfile profile,
  ) {
    final result = <ZiweiTimelineItem>[];
    for (var month = 1; month <= 12; month++) {
      _addMonth(result, lunarYear, month, profile);
      if (LunarMonth.fromYm(lunarYear, -month) != null) {
        _addMonth(result, lunarYear, -month, profile);
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  static void _addMonth(
    List<ZiweiTimelineItem> target,
    int lunarYear,
    int lunarMonth,
    ZiweiProfile profile,
  ) {
    final lunar = Lunar.fromYmdHms(lunarYear, lunarMonth, 1, 12, 0, 0);
    final solar = lunar.getSolar();
    final date = DateTime(
      solar.getYear(),
      solar.getMonth(),
      solar.getDay(),
      12,
    );
    final ganZhi = profile.settings.horoscopeDivide == 'exact'
        ? lunar.getMonthInGanZhiExact()
        : lunar.getMonthInGanZhi();
    target.add(
      ZiweiTimelineItem(
        key: 'month-$lunarYear-$lunarMonth',
        date: date,
        timeIndex: 6,
        title: '${date.month}.${date.day}',
        subtitle: '${lunar.getMonthInChinese()}月',
        tertiary: ganZhi,
        lunarYear: lunarYear,
        lunarMonth: lunarMonth,
      ),
    );
  }

  static List<ZiweiTimelineItem> days(
    int lunarYear,
    int lunarMonth,
  ) {
    final month = LunarMonth.fromYm(lunarYear, lunarMonth);
    if (month == null) return const [];
    return [
      for (var day = 1; day <= month.getDayCount(); day++)
        _dayItem(lunarYear, lunarMonth, day),
    ];
  }

  static ZiweiTimelineItem _dayItem(
    int lunarYear,
    int lunarMonth,
    int day,
  ) {
    final lunar = Lunar.fromYmdHms(lunarYear, lunarMonth, day, 12, 0, 0);
    final solar = lunar.getSolar();
    final date = DateTime(
      solar.getYear(),
      solar.getMonth(),
      solar.getDay(),
      12,
    );
    return ZiweiTimelineItem(
      key: 'day-${date.year}-${date.month}-${date.day}',
      date: date,
      timeIndex: 6,
      title: '${date.month}.${date.day}',
      subtitle: lunar.getDayInChinese(),
      tertiary: lunar.getDayInGanZhi(),
      lunarYear: lunarYear,
      lunarMonth: lunarMonth,
    );
  }

  static List<ZiweiTimelineItem> hours(DateTime date) {
    const hours = [0, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23];
    const names = [
      '早子',
      '丑',
      '寅',
      '卯',
      '辰',
      '巳',
      '午',
      '未',
      '申',
      '酉',
      '戌',
      '亥',
      '晚子',
    ];
    return [
      for (var index = 0; index < hours.length; index++)
        _hourItem(date, index, hours[index], names[index]),
    ];
  }

  static ZiweiTimelineItem _hourItem(
    DateTime date,
    int timeIndex,
    int hour,
    String name,
  ) {
    final target = DateTime(date.year, date.month, date.day, hour);
    final lunar = Lunar.fromDate(target);
    return ZiweiTimelineItem(
      key: 'hour-${date.year}-${date.month}-${date.day}-$timeIndex',
      date: target,
      timeIndex: timeIndex,
      title: '${hour.toString().padLeft(2, '0')}:00',
      subtitle: '$name时',
      tertiary: lunar.getTimeInGanZhi(),
    );
  }

  static Set<int> surroundedIndices(int target) => {
        target,
        (target + 6) % 12,
        (target + 4) % 12,
        (target + 8) % 12,
      };
}
