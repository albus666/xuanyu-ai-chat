import 'package:bazi_core/bazi_core.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart' show RatHourMode;

/// 试用开关：为 `true` 时四柱神煞与 `computeShenShaForExtraPillar` 走 [ShenShaHelper]。
/// bazi_core 文档标明神煞为实验性、AI 录入，与原先自写表可能不一致，对比满意后再长期开启。
const bool kShenShaUseBaziCore = true;

/// 与排盘一致：不用真太阳时；子时按「晚子时日柱算当天」近似为 [RatHourMode.todayGan]。
BaziChart buildBaziChartForShenSha(
  DateTime effectiveSolar, {
  required bool isFemale,
}) {
  return BaziChart.createBySolarDate(
    clockTime: AstroDateTime(
      effectiveSolar.year,
      effectiveSolar.month,
      effectiveSolar.day,
      effectiveSolar.hour,
      effectiveSolar.minute,
      effectiveSolar.second,
    ),
    useTrueSolarTime: false,
    timeZone: 8,
    ratHourMode: RatHourMode.todayGan,
    gender: isFemale ? Gender.female : Gender.male,
  );
}

/// 四柱神煞 → 与 [BaziResult.shenSha] 相同结构 [年, 月, 日, 时]。
List<List<String>> computeShenShaFourPillarsBaziCore(
  DateTime effectiveSolar, {
  required bool isFemale,
}) {
  final chart = buildBaziChartForShenSha(effectiveSolar, isFemale: isFemale);
  final info = ShenShaHelper.analyze(chart);
  return [
    List<String>.from(info.yearShenSha),
    List<String>.from(info.monthShenSha),
    List<String>.from(info.dayShenSha),
    List<String>.from(info.hourShenSha),
  ];
}

/// 大运 / 流年 / 流月 等单柱，在命盘 context 下的神煞（与库中柱位类型一致）。
List<String> computeShenShaExtraPillarBaziCore(
  DateTime effectiveSolar, {
  required bool isFemale,
  required String extraGan,
  required String extraZhi,
  required PillarType pillarType,
}) {
  if (extraGan.length != 1 || extraZhi.length != 1) return [];
  try {
    final chart = buildBaziChartForShenSha(effectiveSolar, isFemale: isFemale);
    final gz = GanZhi(TianGan.fromName(extraGan), DiZhi.fromName(extraZhi));
    return List<String>.from(ShenShaHelper.getShenSha(chart, gz, pillarType));
  } catch (_) {
    return [];
  }
}
