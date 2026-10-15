import 'package:xuanyu/app/common/style/colors.dart' as shell;
import 'package:xuanyu/app/pages/home/home_index/widgets/fortune_bars.dart';

/// 五维能量分：由服务端规则引擎根据排盘与当天干支计算。
class DailyEnergyScore {
  const DailyEnergyScore({
    required this.overall,
    required this.love,
    required this.wealth,
    required this.career,
    required this.study,
    required this.social,
  });

  final int overall;
  final int love;
  final int wealth;
  final int career;
  final int study;
  final int social;

  static const _labels = ['爱情', '财富', '事业', '学习', '人际'];

  List<FortuneBarItem> toBarItems() {
    final values = [love, wealth, career, study, social];
    return List.generate(_labels.length, (i) {
      return FortuneBarItem(
        _labels[i],
        values[i],
        shell.AppColors.fortuneBars[i],
      );
    });
  }

  static int _clampScore(dynamic v, [int fallback = 70]) {
    if (v is int) return v.clamp(0, 100);
    if (v is num) return v.round().clamp(0, 100);
    return fallback;
  }

  /// 从 `/api/fortune/today-fortune` 或本地缓存 map 解析。
  static DailyEnergyScore? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    if (map['overall'] == null && map['love'] == null) return null;
    final love = _clampScore(map['love']);
    final wealth = _clampScore(map['wealth']);
    final career = _clampScore(map['career']);
    final study = _clampScore(map['study']);
    final social = _clampScore(map['social']);
    final overallRaw = map['overall'];
    final overall = overallRaw != null
        ? _clampScore(overallRaw)
        : ((love + wealth + career + study + social) / 5).round();
    return DailyEnergyScore(
      overall: overall,
      love: love,
      wealth: wealth,
      career: career,
      study: study,
      social: social,
    );
  }

  /// 服务端不可用时只显示校准后的中性占位分，不再用日期哈希伪造每日波动。
  static DailyEnergyScore compute({
    String? birthDate,
    String? birthTime,
    DateTime? forDate,
  }) {
    return const DailyEnergyScore(
      overall: 74,
      love: 74,
      wealth: 74,
      career: 74,
      study: 74,
      social: 74,
    );
  }
}
