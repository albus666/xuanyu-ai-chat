import 'package:lunar/lunar.dart';

import 'ziwei_models.dart';

class ZiweiFourPillars {
  ZiweiFourPillars._();

  /// 八字使用立春换年、节令换月，并跟随命盘的晚子时换日规则。
  static String solarTerm(ZiweiProfile profile) {
    final eightChar = Lunar.fromDate(profile.effectiveBirthDate).getEightChar();
    eightChar.setSect(profile.settings.dayDivide == 'forward' ? 1 : 2);
    return '${eightChar.getYear()} ${eightChar.getMonth()} '
        '${eightChar.getDay()} ${eightChar.getTime()}';
  }

  static String chartBoundaryLabel(ZiweiProfile profile) =>
      profile.settings.yearDivide == 'exact' ? '立春界' : '正月界';
}
