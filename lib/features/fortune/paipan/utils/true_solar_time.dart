import 'dart:math' as math;

/// 真太阳时计算，与 myresource/bazi_gui 的 calculate_true_solar_time 一致
/// （经度修正 + 均时差，不含纬度）
class TrueSolarTime {
  /// 计算儒略日（高精度）
  static double _julianDay(DateTime dt) {
    int y = dt.year, m = dt.month, d = dt.day;
    final h = dt.hour + dt.minute / 60.0 + dt.second / 3600.0;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = y ~/ 100;
    final b = 2 - a + (a ~/ 4);
    return (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + h / 24.0 + b - 1524.5;
  }

  /// 均时差（分钟）
  static double _equationOfTimeMinutes(DateTime dt) {
    final jd = _julianDay(dt);
    final n = jd - 2451545.0;
    final L0 = (280.46646 + 0.98564736 * n) % 360.0;
    final M = (357.52911 + 0.98560028 * n) % 360.0;
    final Mrad = M * math.pi / 180;
    final C = (1.914602 - 0.004817 * n / 36525.0 - 0.000014 * math.pow(n / 36525.0, 2)) * math.sin(Mrad) +
        (0.019993 - 0.000101 * n / 36525.0) * math.sin(2 * Mrad) +
        0.000289 * math.sin(3 * Mrad);
    final L = L0 + C;
    final epsilon = 23.4392911 - 0.000130042 * n / 36525.0;
    final epsRad = epsilon * math.pi / 180;
    final Lrad = L * math.pi / 180;
    double alpha = math.atan2(math.cos(epsRad) * math.sin(Lrad), math.cos(Lrad)) * 180 / math.pi;
    if (alpha < 0) alpha += 360.0;
    double eot = 4 * (L0 - alpha);
    if (eot > 720) eot -= 1440;
    if (eot < -720) eot += 1440;
    return eot;
  }

  /// 将北京时间转为当地真太阳时
  /// [beijingDt] 北京时间（东八区）
  /// [longitude] 当地经度（度）
  /// 返回真太阳时对应的 DateTime（仅日期时间用于排盘，不包含时区）
  static DateTime toTrueSolar(DateTime beijingDt, double longitude) {
    final lonCorrectionMin = 4.0 * (longitude - 120.0);
    final eotMin = _equationOfTimeMinutes(beijingDt);
    final totalSec = (lonCorrectionMin + eotMin) * 60.0;
    return beijingDt.add(Duration(milliseconds: (totalSec * 1000).round()));
  }
}
