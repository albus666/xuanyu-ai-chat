import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';

class DateUtil {
  /// 公历：2026年02月11日 15:09:10
  static String formatGregorian(DateTime dt) {
    final formatter = DateFormat('yyyy年MM月dd日 HH:mm:ss', 'zh_CN');
    return formatter.format(dt);
  }

  /// 将小时转换为地支时辰
  static String _hourToShiChen(int hour) {
    const shichen = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
    if (hour == 23 || hour == 0) return '${shichen[0]}时';
    final index = ((hour + 1) ~/ 2);
    return '${shichen[index]}时';
  }

  /// 农历：2025年腊月廿四
  static String formatLunar(DateTime dt) {
    try {
      final lunar = Lunar.fromDate(dt);
      final year = lunar.getYear();
      final month = lunar.getMonth();
      final day = lunar.getDay();
      final monthCn = _numberToChineseMonth(month);
      final dayCn = _numberToChineseDay(day);
      final shichen = _hourToShiChen(dt.hour);
      return '$year年$monthCn月$dayCn $shichen';
    } catch (e) {
      return '农历：${dt.year}年${dt.month}月${dt.day}日';
    }
  }

  static String _numberToChineseMonth(int month) {
    const months = [
      '', '正', '二', '三', '四', '五', '六',
      '七', '八', '九', '十', '冬', '腊'
    ];
    if (month >= 1 && month <= 12) return months[month];
    return month.toString();
  }

  static String _numberToChineseDay(int day) {
    const days = [
      '', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
      '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
      '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
    ];
    if (day >= 1 && day <= 30) return days[day];
    return day.toString();
  }

  /// 农历月份标签（滚轮用）：正月、二月、…、腊月；闰月用负月，如 -4 → 闰四月
  static String lunarMonthLabel(int month) {
    const names = ['', '正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
    if (month >= 1 && month <= 12) return names[month];
    if (month <= -1 && month >= -12) return '闰${names[-month].replaceFirst('月', '')}月';
    return '$month月';
  }

  /// 某农历年是否有闰月及闰几月
  static int? getLeapMonthForYear(int lunarYear) {
    for (int m = 1; m <= 12; m++) {
      try {
        final lunar = Lunar.fromYmdHms(lunarYear, -m, 1, 12, 0, 0);
        final solar = lunar.getSolar();
        final sy = solar.getYear();
        if (sy == lunarYear || (sy - lunarYear).abs() <= 1) return m;
      } catch (_) {}
    }
    return null;
  }

  /// 农历日期标签（滚轮用）：初一、初二、…、三十
  static String lunarDayLabel(int day) {
    const names = [
      '', '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
      '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
      '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
    ];
    return day >= 1 && day <= 30 ? names[day] : '$day';
  }

  /// 获取八字四柱（天干地支），返回格式：年干  月干  日干  时干\n年支  月支  日支  时支
  static String getEightChar(DateTime dt) {
    try {
      final lunar = Lunar.fromDate(dt);
      final eightChar = lunar.getEightChar();
      final yearGan = eightChar.getYearGan();
      final monthGan = eightChar.getMonthGan();
      final dayGan = eightChar.getDayGan();
      final timeGan = eightChar.getTimeGan();
      final yearZhi = eightChar.getYearZhi();
      final monthZhi = eightChar.getMonthZhi();
      final dayZhi = eightChar.getDayZhi();
      final timeZhi = eightChar.getTimeZhi();
      return '$yearGan  $monthGan  $dayGan  $timeGan\n$yearZhi  $monthZhi  $dayZhi  $timeZhi';
    } catch (e) {
      return '甲  乙  丙  丁\n子  丑  寅  卯';
    }
  }

  /// 获取四柱为 4 列，每列格式为 "天干\n地支"
  static List<String> getEightCharColumns(DateTime dt) {
    try {
      final lunar = Lunar.fromDate(dt);
      final eightChar = lunar.getEightChar();
      return [
        '${eightChar.getYearGan()}\n${eightChar.getYearZhi()}',
        '${eightChar.getMonthGan()}\n${eightChar.getMonthZhi()}',
        '${eightChar.getDayGan()}\n${eightChar.getDayZhi()}',
        '${eightChar.getTimeGan()}\n${eightChar.getTimeZhi()}',
      ];
    } catch (e) {
      return ['甲\n子', '乙\n丑', '丙\n寅', '丁\n卯'];
    }
  }

  /// 60 甲子校验：天干+地支是否为合法组合
  static bool isValidGanZhi(String gan, String zhi) {
    const tiangan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    const dizhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
    final gi = tiangan.indexOf(gan);
    final zi = dizhi.indexOf(zhi);
    if (gi < 0 || zi < 0) return false;
    return (gi % 2) == (zi % 2);
  }

  /// 从四柱反推全部公历候选，覆盖 1800 年至设备当前年份。
  static List<DateTime> datesFromBaZi(String yearGanZhi, String monthGanZhi, String dayGanZhi, String timeGanZhi) {
    try {
      final candidates = <DateTime>{};
      for (final sect in const [2, 1]) {
        for (final solar in Solar.fromBaZi(yearGanZhi, monthGanZhi, dayGanZhi, timeGanZhi, sect: sect, baseYear: 1800)) {
          candidates.add(DateTime(solar.getYear(), solar.getMonth(), solar.getDay(), solar.getHour(), solar.getMinute(), solar.getSecond()));
        }
      }
      return candidates.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// 从四柱反推公历日期
  static DateTime? dateFromBaZi(String yearGanZhi, String monthGanZhi, String dayGanZhi, String timeGanZhi, {DateTime? near}) {
    try {
      final list = datesFromBaZi(yearGanZhi, monthGanZhi, dayGanZhi, timeGanZhi);
      if (list.isEmpty) return null;
      DateTime solar;
      if (near != null && list.isNotEmpty) {
        int bestIdx = 0;
        int bestDiff = -1;
        for (int i = 0; i < list.length; i++) {
          final dt = list[i];
          final diff = (dt.difference(near).inSeconds).abs();
          if (bestDiff < 0 || diff < bestDiff) {
            bestDiff = diff;
            bestIdx = i;
          }
        }
        solar = list[bestIdx];
      } else {
        solar = list.first;
      }
      return DateTime(
        solar.year,
        solar.month,
        solar.day,
        solar.hour,
        solar.minute,
        solar.second,
      );
    } catch (e) {
      return null;
    }
  }
}
