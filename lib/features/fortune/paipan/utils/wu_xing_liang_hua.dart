import 'bazi_result.dart';

/// 五行量化得分（木、火、土、金、水）。
///
/// 仅一种算法：**四柱天干柱权 + 四柱地支柱权按藏干比例拆分**（子癸、酉辛、午丁己等一律走藏干表，与命盘藏干一致）。
class WuXingLiangHuaScores {
  /// 木、火、土、金、水
  final List<double> byMuHuoTuJinShui;

  const WuXingLiangHuaScores._(this.byMuHuoTuJinShui);

  double get mu => byMuHuoTuJinShui[0];
  double get huo => byMuHuoTuJinShui[1];
  double get tu => byMuHuoTuJinShui[2];
  double get jin => byMuHuoTuJinShui[3];
  double get shui => byMuHuoTuJinShui[4];

  /// 展示顺序：金木水火土（与部分网站表格一致）
  List<double> get byJinMuShuiHuoTu => [jin, mu, shui, huo, tu];

  /// 日主同类（比劫 + 印星）得分；[木火土金水] 下标分组求和。
  double tongLeiForDayGan(String dayGan) {
    final dw = _ganWuXingIndex(dayGan);
    if (dw == null) return 0;
    // 生我者为印：wx 母 = (dw - 1 + 5) % 5
    final yin = (dw - 1 + 5) % 5;
    return byMuHuoTuJinShui[dw] + byMuHuoTuJinShui[yin];
  }

  /// 异类：总分减同类
  double yiLeiForDayGan(String dayGan) {
    final t = total;
    if (t <= 0) return 0;
    return t - tongLeiForDayGan(dayGan);
  }

  double get total => byMuHuoTuJinShui.fold(0.0, (a, b) => a + b);
}

/// 由五行量化同类/异类推出的身强身弱、喜用神与五行缺（对齐常见网页：旺衰得分、【平衡】、喜用、缺项）。
class WuXingShenQiangYongShen {
  /// 身强 / 身弱 / 八字比较平衡（与部分站「【八字比较平衡】」一致）
  final String shenQiangRuo;
  /// 同类 − 异类，与部分网站「旺衰得分」同号
  final double wangShuaiDeFen;
  /// 喜用五行（单字或多字顿号），在印比中取弱、在异类中取强等规则见 [analyzeWuXingShenQiangYongShen]
  final String xiYongShen;
  /// 天干与本气未出现的五行（「五行缺」，与网页个数一致）
  final List<String> queWuXing;
  /// 一句补充说明
  final String yongShenHint;

  const WuXingShenQiangYongShen({
    required this.shenQiangRuo,
    required this.wangShuaiDeFen,
    required this.xiYongShen,
    required this.queWuXing,
    required this.yongShenHint,
  });
}

const List<String> _wxNamesMuHuoTuJinShui = ['木', '火', '土', '金', '水'];

/// 与「本气个数」一致：八字里天干 + 四支 **本气** 从未出现的五行，判为「缺」。
List<String> _queWuXingBenQiOnly(BaziResult r) {
  final has = List<bool>.filled(5, false);
  for (final g in r.gans) {
    final wx = _ganWuXingIndex(g);
    if (wx != null) has[wx] = true;
  }
  for (final z in r.zhis) {
    final zx = _zhiBenQiWuXingIndex(z);
    if (zx != null) has[zx] = true;
  }
  final out = <String>[];
  for (int i = 0; i < 5; i++) {
    if (!has[i]) out.add(_wxNamesMuHuoTuJinShui[i]);
  }
  return out;
}

/// 印、比劫中取量化分 **较低** 者，作扶抑喜用（与华易类「金多水少喜水」一致）。
String _xiYongYinBiJie(WuXingLiangHuaScores s, int yinWx, int dw) {
  final sy = s.byMuHuoTuJinShui[yinWx];
  final sb = s.byMuHuoTuJinShui[dw];
  final yn = _wxNamesMuHuoTuJinShui[yinWx];
  final bn = _wxNamesMuHuoTuJinShui[dw];
  if ((sy - sb).abs() < 1e-9) return '$yn、$bn';
  return sy < sb ? yn : bn;
}

/// 身强：官杀、食伤、财三类中取量化分 **最高** 者作主要喜用方向。
String _xiYongYiLeiMax(WuXingLiangHuaScores s, int guanSha, int shiShang, int cai) {
  var best = guanSha;
  var bestV = s.byMuHuoTuJinShui[guanSha];
  final b2 = s.byMuHuoTuJinShui[shiShang];
  if (b2 > bestV + 1e-9) {
    bestV = b2;
    best = shiShang;
  }
  final b3 = s.byMuHuoTuJinShui[cai];
  if (b3 > bestV + 1e-9) best = cai;
  return _wxNamesMuHuoTuJinShui[best];
}

/// 旺衰得分 + 身强/身弱/平衡 + 喜用神 + 五行缺（缺字按本气，与华易「个数」一致）。
WuXingShenQiangYongShen analyzeWuXingShenQiangYongShen(
  WuXingLiangHuaScores s,
  String dayGan,
  BaziResult bazi,
) {
  final que = _queWuXingBenQiOnly(bazi);
  final dw = _ganWuXingIndex(dayGan);
  if (dw == null) {
    return WuXingShenQiangYongShen(
      shenQiangRuo: '—',
      wangShuaiDeFen: 0,
      xiYongShen: '',
      queWuXing: que,
      yongShenHint: '日主天干无效。',
    );
  }
  final tong = s.tongLeiForDayGan(dayGan);
  final yi = s.yiLeiForDayGan(dayGan);
  final total = s.total;
  final balance = tong - yi;
  if (total < 1e-9) {
    return WuXingShenQiangYongShen(
      shenQiangRuo: '—',
      wangShuaiDeFen: 0,
      xiYongShen: '',
      queWuXing: que,
      yongShenHint: '五行量化总分为零，无法推断。',
    );
  }

  final rel = balance.abs() / total;
  const zhongHeRatio = 0.06;
  const zhongHeAbsScore = 3.5;

  final yinWx = (dw - 1 + 5) % 5;
  final guanSha = (dw + 3) % 5;
  final shiShang = (dw + 1) % 5;
  final cai = (dw + 2) % 5;
  final yinName = _wxNamesMuHuoTuJinShui[yinWx];
  final bijieName = _wxNamesMuHuoTuJinShui[dw];

  if (balance.abs() <= zhongHeAbsScore || rel < zhongHeRatio) {
    final xi = _xiYongYinBiJie(s, yinWx, dw);
    return WuXingShenQiangYongShen(
      shenQiangRuo: '八字比较平衡',
      wangShuaiDeFen: balance,
      xiYongShen: xi,
      queWuXing: que,
      yongShenHint: '印（$yinName）与比劫（$bijieName）中取分较低者为喜用参考；调候、从格等须另参。',
    );
  }
  if (balance > 0) {
    final xi = _xiYongYiLeiMax(s, guanSha, shiShang, cai);
    const guoYingThreshold = 7.0;
    final label = balance > guoYingThreshold ? '八字过硬' : '身强';
    return WuXingShenQiangYongShen(
      shenQiangRuo: label,
      wangShuaiDeFen: balance,
      xiYongShen: xi,
      queWuXing: que,
      yongShenHint: balance > guoYingThreshold
          ? '印比明显占优，喜克泄耗；官杀、食伤、财中取分较高者为参考。'
          : '官杀、食伤、财中取分较高者为克泄耗参考；具体用神须看格局。',
    );
  }
  final xi = _xiYongYinBiJie(s, yinWx, dw);
  return WuXingShenQiangYongShen(
    shenQiangRuo: '身弱',
    wangShuaiDeFen: balance,
    xiYongShen: xi,
    queWuXing: que,
    yongShenHint: '印（$yinName）与比劫（$bijieName）中取分较低者为扶身参考。',
  );
}

class WuXingLiangHuaConfig {
  /// 年、月、日、时 天干权重
  final List<double> stemPillarWeights;
  /// 年、月、日、时 地支权重（按藏干比例分配到各五行）
  final List<double> branchPillarWeights;

  const WuXingLiangHuaConfig({
    this.stemPillarWeights = const [0.8, 0.8, 1.2, 1.0],
    this.branchPillarWeights = const [1.0, 1.2, 1.8, 1.0],
  });
}

/// 地支藏干及比例（与命盘藏干、个人信息环图一致）。
const Map<String, List<String>> _zhiCangGanList = {
  '子': ['癸'],
  '丑': ['己', '癸', '辛'],
  '寅': ['甲', '丙', '戊'],
  '卯': ['乙'],
  '辰': ['戊', '乙', '癸'],
  '巳': ['丙', '戊', '庚'],
  '午': ['丁', '己'],
  '未': ['己', '丁', '乙'],
  '申': ['庚', '壬', '戊'],
  '酉': ['辛'],
  '戌': ['戊', '辛', '丁'],
  '亥': ['壬', '甲'],
};

const Map<String, List<int>> _zhiCangScoreList = {
  '子': [100],
  '丑': [60, 30, 10],
  '寅': [60, 30, 10],
  '卯': [100],
  '辰': [60, 30, 10],
  '巳': [60, 30, 10],
  '午': [70, 30],
  '未': [60, 30, 10],
  '申': [60, 30, 10],
  '酉': [100],
  '戌': [60, 30, 10],
  '亥': [70, 30],
};

int? _ganWuXingIndex(String g) {
  const map = {'甲': 0, '乙': 0, '丙': 1, '丁': 1, '戊': 2, '己': 2, '庚': 3, '辛': 3, '壬': 4, '癸': 4};
  return map[g];
}

int? _zhiBenQiWuXingIndex(String z) {
  const map = {'寅': 0, '卯': 0, '巳': 1, '午': 1, '辰': 2, '戌': 2, '丑': 2, '未': 2, '申': 3, '酉': 3, '亥': 4, '子': 4};
  return map[z];
}

WuXingLiangHuaScores computeWuXingLiangHua(
  BaziResult r, {
  WuXingLiangHuaConfig config = const WuXingLiangHuaConfig(),
}) {
  final raw = [0.0, 0.0, 0.0, 0.0, 0.0];
  final gans = r.gans;
  final zhis = r.zhis;
  final sw = config.stemPillarWeights;
  final bw = config.branchPillarWeights;

  for (int i = 0; i < 4; i++) {
    final wG = i < sw.length ? sw[i] : 1.0;
    final wx = _ganWuXingIndex(gans[i]);
    if (wx != null) raw[wx] += wG;
  }

  for (int i = 0; i < 4; i++) {
    final wB = i < bw.length ? bw[i] : 1.0;
    final z = zhis[i];
    final gList = _zhiCangGanList[z];
    final sList = _zhiCangScoreList[z];
    if (gList == null || sList == null || gList.length != sList.length) continue;
    final sum = sList.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) continue;
    for (int k = 0; k < gList.length; k++) {
      final wx = _ganWuXingIndex(gList[k]);
      if (wx == null) continue;
      raw[wx] += wB * (sList[k] / sum);
    }
  }

  return WuXingLiangHuaScores._(raw);
}
