import 'package:xuanyu/core/config/app_content_config.dart';
import 'package:xuanyu/features/fortune/paipan/utils/bazi_result.dart';
import 'package:xuanyu/features/role_diagnosis/models/role_diagnosis_models.dart';

/// 标签前缀：按最旺十神（伤官 → 人间清醒型）
const Map<String, String> kTagPrefixByGod = {
  '正官': '持证上岗型',
  '七杀': '绝地求生型',
  '正印': '自带靠山型',
  '偏印': '独门绝技型',
  '正财': '稳定输出型',
  '偏财': '风投博弈型',
  '食神': '天赋摸鱼型',
  '伤官': '人间清醒型',
  '比肩': '兄弟连坐型',
  '劫财': '散财童子型',
};

const Map<String, String> kDaySitByGod = {
  '正官': '规则内化者，靠谱但累',
  '七杀': '内心将军，随时准备战斗',
  '正印': '后台依赖者，需要被认可',
  '偏印': '独行侠，擅长独自钻研',
  '正财': '对钱和感情都很认真',
  '偏财': '机会嗅觉灵敏，握住的比闻到的少',
  '食神': '快乐创造者，容易把快乐外包',
  '伤官': '心中有火，才华与脾气成正比',
  '比肩': '内心住着团队，很难真正独处',
  '劫财': '把兄弟当自己人，忘了问他们愿不愿意',
};

const List<String> kKuiGangDays = ['戊戌', '庚戌', '庚辰', '壬辰', '辛巳'];

const Map<String, List<String>> kLuRen = {
  '甲': ['寅', '卯'],
  '乙': ['卯', '寅'],
  '丙': ['巳', '午'],
  '丁': ['午', '巳'],
  '戊': ['巳', '午'],
  '己': ['午', '巳'],
  '庚': ['申', '酉'],
  '辛': ['酉', '申'],
  '壬': ['亥', '子'],
  '癸': ['子', '亥'],
};

/// 将排盘简写十神转为全称
String shenFull(String abbr) {
  const m = {
    '比': '比肩',
    '劫': '劫财',
    '食': '食神',
    '伤': '伤官',
    '才': '偏财',
    '财': '正财',
    '杀': '七杀',
    '官': '正官',
    '枭': '偏印',
    '印': '正印',
  };
  return m[abbr] ?? abbr;
}

/// L2/L3 本地规则引擎（文档核心链路的前端可运行版）
class RoleDiagnosisEngine {
  RoleDiagnosisEngine._();

  static RoleDiagnosisReport diagnose({
    required DateTime birth,
    required int hour,
    required bool isMale,
  }) {
    final dt = DateTime(birth.year, birth.month, birth.day, hour);
    final bazi = computeBaziResult(dt, isFemale: !isMale);

    final dayGan = bazi.gans.isNotEmpty ? bazi.gans[2] : '甲';
    final dayZhi = bazi.zhis.length > 2 ? bazi.zhis[2] : '子';
    final dayPillar = '$dayGan$dayZhi';
    final pillars = List.generate(
      4,
      (i) => '${bazi.gans[i]}${bazi.zhis[i]}',
    ).join(' ');

    final scores = _godScores(bazi);
    final dominant = _dominantGod(scores, dayPillar);
    final tag = _buildTag(dominant, bazi, dayPillar, dayGan);
    final radar = _buildRadar(scores, dayGan, bazi);
    final matchScore = _matchScore(radar, scores);
    final daySitMap = _roleStringMap('daySitByGod');
    final daySit =
        daySitMap[shenFull(bazi.zhiShens.length > 2 ? bazi.zhiShens[2] : '')] ??
            daySitMap[dominant] ??
            kDaySitByGod[
                shenFull(bazi.zhiShens.length > 2 ? bazi.zhiShens[2] : '')] ??
            kDaySitByGod[dominant] ??
            '角色剧本正在展开';

    final verdict = _verdict(tag, dominant, dayPillar, daySit);
    final story = _story(
      tag: tag,
      dayMaster: dayGan,
      dayPillar: dayPillar,
      pillars: pillars,
      dominant: dominant,
      daySit: daySit,
      nayin: bazi.pillarNayins.length > 2 ? bazi.pillarNayins[2] : '',
      isMale: isMale,
      bazi: bazi,
    );
    final dims = _dimensions(
      dominant: dominant,
      dayGan: dayGan,
      dayPillar: dayPillar,
      tag: tag,
      radar: radar,
      bazi: bazi,
      isMale: isMale,
    );
    final insights = _buildInsights(bazi, dayGan);

    return RoleDiagnosisReport(
      tag: tag,
      verdict: verdict,
      matchScore: matchScore,
      radar: radar,
      story: story,
      dimensions: dims,
      dayMaster: dayGan,
      pillars: pillars,
      dominantGod: dominant,
      genderMale: isMale,
      birthDate: birth,
      birthHour: hour,
      insights: insights,
    );
  }

  static RoleDiagnosisInsights _buildInsights(BaziResult bazi, String dayGan) {
    const elementByGan = {
      '甲': '木',
      '乙': '木',
      '丙': '火',
      '丁': '火',
      '戊': '土',
      '己': '土',
      '庚': '金',
      '辛': '金',
      '壬': '水',
      '癸': '水',
    };
    const elementByZhi = {
      '子': '水',
      '丑': '土',
      '寅': '木',
      '卯': '木',
      '辰': '土',
      '巳': '火',
      '午': '火',
      '未': '土',
      '申': '金',
      '酉': '金',
      '戌': '土',
      '亥': '水',
    };
    const clashPairs = ['子午', '丑未', '寅申', '卯酉', '辰戌', '巳亥'];
    const combinePairs = ['子丑', '寅亥', '卯戌', '辰酉', '巳申', '午未'];
    final counts = <String, int>{for (final e in '木火土金水'.split('')) e: 0};
    for (final gan in bazi.gans) {
      counts[elementByGan[gan]!] = counts[elementByGan[gan]]! + 1;
    }
    for (final zhi in bazi.zhis) {
      counts[elementByZhi[zhi]!] = counts[elementByZhi[zhi]]! + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final weakest = sorted.take(2).map((e) => e.key).toList();
    final strongest = sorted.reversed.take(2).map((e) => e.key).toList();
    final zhis = bazi.zhis.toSet();
    final interactions = <String>[
      for (final pair in clashPairs)
        if (pair.split('').every(zhis.contains)) '$pair冲',
      for (final pair in combinePairs)
        if (pair.split('').every(zhis.contains)) '$pair合',
    ];
    final shenSha =
        bazi.shenSha.expand((items) => items).toSet().take(4).toList();
    final month = bazi.zhis[1];
    final tuning = month == '亥' || month == '子' || month == '丑'
        ? '偏寒，优先补火土并维持规律节奏'
        : month == '巳' || month == '午' || month == '未'
            ? '偏燥，优先补水并减少高压消耗'
            : '五行温度适中，保持稳定节奏即可';
    final circulation = interactions.any((item) => item.endsWith('冲'))
        ? '有冲，适合用明确边界疏通变化'
        : strongest.first == elementByGan[dayGan]
            ? '日主有根，适合持续积累'
            : '流通平稳，适合借助外部资源';
    return RoleDiagnosisInsights(
      tuning: tuning,
      circulation: circulation,
      favorableElements: weakest,
      unfavorableElements: strongest,
      interactions: interactions,
      shenSha: shenSha,
    );
  }

  /// 统计十神权重：透干权重高，藏干主气次之，月令加权
  static Map<String, double> _godScores(BaziResult bazi) {
    final scores = <String, double>{
      for (final g in kTagPrefixByGod.keys) g: 0,
    };

    void add(String abbr, double w) {
      final full = shenFull(abbr);
      if (scores.containsKey(full)) scores[full] = scores[full]! + w;
    }

    // 天干十神（日干为空）
    for (var i = 0; i < bazi.ganShens.length; i++) {
      if (i == 2) continue;
      final s = bazi.ganShens[i];
      if (s.isEmpty || s == '--') continue;
      add(s, i == 1 ? 2.2 : 1.6); // 月干更重
    }
    // 地支主气十神
    for (var i = 0; i < bazi.zhiShens.length; i++) {
      final s = bazi.zhiShens[i];
      if (s.isEmpty) continue;
      add(s, i == 1 ? 2.0 : (i == 2 ? 1.8 : 1.2));
    }
    return scores;
  }

  static String _dominantGod(Map<String, double> scores, String dayPillar) {
    var best = '伤官';
    var max = -1.0;
    scores.forEach((k, v) {
      if (v > max) {
        max = v;
        best = k;
      }
    });
    if (kKuiGangDays.contains(dayPillar) && (scores['伤官'] ?? 0) >= max * 0.7) {
      return '伤官';
    }
    return best;
  }

  static String _buildTag(
      String dominant, BaziResult bazi, String dayPillar, String dayGan) {
    final prefix = _tagPrefix(dominant);
    final yearZhi = bazi.zhis[0];
    final monthZhi = bazi.zhis[1];
    final dayZhi = bazi.zhis[2];
    final timeZhi = bazi.zhis[3];
    final home = {dayZhi, timeZhi};
    final outer = {yearZhi, monthZhi};
    final luRen = kLuRen[dayGan];
    final hasLu =
        luRen != null && (home.contains(luRen[0]) || outer.contains(luRen[0]));
    final hasRen =
        luRen != null && (home.contains(luRen[1]) || outer.contains(luRen[1]));
    final hasKu = ['辰', '戌', '丑', '未'].any(home.contains);
    final shiShangCai = (dominant == '食神' || dominant == '伤官') &&
        ((bazi.ganShens.any((s) => s == '财' || s == '才')) ||
            bazi.zhiShens.any((s) => s == '财' || s == '才'));

    String suffix = '·野生发育版';
    if (hasLu && outer.contains(luRen[0])) {
      suffix = '·远征版';
    } else if (hasKu) {
      suffix = '·总库持有者';
    } else if (hasRen && home.contains(luRen[1])) {
      suffix = '·团队收编体质';
    } else if (shiShangCai) {
      suffix = '·产品驱动型';
    } else if (!hasLu && !hasRen) {
      suffix = '·野生发育版';
    }
    if (kKuiGangDays.contains(dayPillar)) {
      suffix = '·人间清醒体验服';
    }
    return '$prefix$suffix';
  }

  static RadarScores _buildRadar(
      Map<String, double> scores, String dayGan, BaziResult bazi) {
    double g(String name) => scores[name] ?? 0;
    final cai = g('正财') + g('偏财');
    final shiShang = g('食神') + g('伤官');
    final yin = g('正印') + g('偏印');
    final guanSha = g('正官') + g('七杀');
    final biJie = g('比肩') + g('劫财');
    final dayPower = biJie + yin * 0.6 + 2;

    int map(double v, {double boost = 0}) {
      final x = ((v + boost) / 12 * 100).clamp(18, 96).round();
      return x;
    }

    return RadarScores(
      money: map(cai + shiShang * 0.7, boost: 1),
      pressure: map(dayPower + yin, boost: 0.5),
      peach: map(guanSha * 0.5 +
          cai * 0.4 +
          (bazi.zhis.contains('午') || bazi.zhis.contains('酉') ? 2 : 0)),
      roast: map(shiShang + g('伤官') * 0.8, boost: 1),
      blame: map((guanSha - yin).clamp(0, 10) + 1),
      slack: map(shiShang + biJie - guanSha * 0.5 + 2),
    );
  }

  static int _matchScore(RadarScores r, Map<String, double> scores) {
    final avg =
        (r.money + r.pressure + r.peach + r.roast + (100 - r.blame) + r.slack) /
            6;
    return avg.round().clamp(90, 98);
  }

  static String _verdict(
      String tag, String dominant, String dayPillar, String daySit) {
    if (kKuiGangDays.contains(dayPillar)) {
      return _roleStringMap('storyFragments')['kuigangVerdict'] ??
          '专利自家产，团队自家带，财带资源来加盟。';
    }
    final remote = _roleStringMap('verdictByGod')[dominant];
    if (remote != null && remote.isNotEmpty) return remote;
    const map = {
      '伤官': '才华是你的矛，清醒是你的盾。别把所有真话都一次说完。',
      '正官': '权威主动找你合作，才华在挑战权威。你是被看上的，但别自己搞砸。',
      '七杀': '战场是日常，喘息是奢侈。学会放下刀，比学会挥刀难。',
      '正印': '后台很厚，动力很软。被照顾惯了，也要学会自己站台。',
      '偏印': '独门绝技让你发光，也让你孤独。别一个人把门焊死。',
      '正财': '认真是美德，也是枷锁。别把每段关系都当成年报来审。',
      '偏财': '机会很多，留下的很少。嗅觉再好，也要学会存折。',
      '食神': '快乐可以外包，路径不能外包。摸鱼是天赋，躺平是风险。',
      '比肩': '你身边永远有“我们”。分责可以，分账也要清醒。',
      '劫财': '讲义气没问题，把家底交出去就有问题。',
    };
    return map[dominant] ?? daySit;
  }

  static String _story({
    required String tag,
    required String dayMaster,
    required String dayPillar,
    required String pillars,
    required String dominant,
    required String daySit,
    required String nayin,
    required bool isMale,
    required BaziResult bazi,
  }) {
    final gender = isMale ? '乾造' : '坤造';
    final lu = kLuRen[dayMaster];
    final hasKuigang = kKuiGangDays.contains(dayPillar);
    final buf = StringBuffer();
    final fragments = _roleStringMap('storyFragments');
    String fill(String template) => _fillTemplate(
          template,
          {
            'gender': gender,
            'pillars': pillars,
            'nayin': nayin,
            'tag': tag,
            'dayMaster': dayMaster,
            'daySit': daySit,
            'dominant': dominant,
          },
        );

    buf.write(fill(fragments['start'] ?? '你是{gender} {pillars}。'));
    if (nayin.isNotEmpty) {
      buf.write(fill(fragments['nayin'] ?? '日柱纳音{nayin}。'));
    }
    buf.write(fill(fragments['tag'] ?? '日主{dayMaster}，人格底层代码更接近「{tag}」。'));
    buf.write(fill(fragments['daySit'] ?? '日坐解读：{daySit}。'));
    if (hasKuigang) {
      buf.write(
          fill(fragments['kuigangStory'] ?? '魁罡自带杀伐决断，不按规矩出牌，江湖规矩对你经常失灵。'));
    }
    buf.write(
        fill(fragments['dominantLead'] ?? '你最旺的十神是{dominant}，社会出场方式也绕不开它：'));
    buf.write(_dominantStoryLine(dominant));
    if (lu != null) {
      final home = {bazi.zhis[2], bazi.zhis[3]};
      final outer = {bazi.zhis[0], bazi.zhis[1]};
      if (outer.contains(lu[0])) {
        buf.write(
            fill(fragments['luOuter'] ?? '禄落家外，你的「行动力」更爱在外部舞台兑现，适合远征版生存。'));
      } else if (home.contains(lu[0])) {
        buf.write(fill(fragments['luHome'] ?? '禄在自家，走健康日常节奏时反而更稳。'));
      } else {
        buf.write(
            fill(fragments['luMissing'] ?? '禄刃不明显，属于野生发育：自己找生态位，自己扛冷启动。'));
      }
    }
    buf.write(fill(fragments['mainConflict'] ??
        '主要矛盾不在能力，在角色错位——你用{dominant}的方式解决世界，世界却用别的规则回你。'));
    buf.write(
        fill(fragments['tuning'] ?? '调候建议：找到能「补你缺、泄你旺」的人事物，而不是继续把自己拧成一根筋。'));
    buf.write(fill(fragments['footer'] ?? '这份诊断书是社会剧本，不是判决书：好玩，但建议认真看一眼。'));
    return buf.toString();
  }

  static String _dominantStoryLine(String god) {
    final remote = _roleStringMap('dominantStoryLineByGod')[god];
    if (remote != null && remote.isNotEmpty) return remote;
    return switch (god) {
      '伤官' => '你靠洞察与表达破局，一句真话能救人也能得罪一整桌。',
      '正官' => '规则感极强，像自带考勤机；权威既是靠山也可能变成枷。',
      '七杀' => '挑战欲旺盛，竞争场合精神头最好，安稳日常反而坐立不安。',
      '正印' => '学习与庇护是你的舒适区，缺少认可时整个人会掉血。',
      '偏印' => '钻牛角尖天赋拉满，一个人能走得很远，也能把自己关很久。',
      '正财' => '稳定现金流好感拉满，但对变数容忍度低。',
      '偏财' => '嗅觉像行情软件，更新快，落袋却慢半拍。',
      '食神' => '创造力常常藏在「看起来很闲」里面。',
      '比肩' => '平级协作是你的主舞台，单打独斗会觉得像断网。',
      '劫财' => '仗义换共鸣快，账目一细就容易伤感情。',
      _ => '你的角色标签还在迭代。',
    };
  }

  static Map<String, String> _roleStringMap(String key) =>
      AppContentConfig.stringMap('roleDiagnosis', key);

  static String _tagPrefix(String dominant) =>
      _roleStringMap('tagPrefixByGod')[dominant] ??
      kTagPrefixByGod[dominant] ??
      '人间清醒型';

  static String _fillTemplate(String template, Map<String, Object> values) {
    var out = template;
    values.forEach((key, value) {
      out = out.replaceAll('{$key}', value.toString());
    });
    return out;
  }

  static Map<String, dynamic> _roleMap(String key) {
    final value = AppContentConfig.section('roleDiagnosis')[key];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  static Map<DiagnosisDimension, DimDiagnosis> _dimensions({
    required String dominant,
    required String dayGan,
    required String dayPillar,
    required String tag,
    required RadarScores radar,
    required BaziResult bazi,
    required bool isMale,
  }) {
    String clip(String s, int max) =>
        s.length <= max ? s : '${s.substring(0, max - 1)}…';

    DimDiagnosis make({
      required String d,
      required String p,
      required String a,
    }) =>
        DimDiagnosis(
          diagnosis: clip(d, 50),
          prescription: clip(p, 80),
          action: clip(a, 40),
        );
    DimDiagnosis fromTemplate(String key, {String? fallbackKey}) {
      final map = _roleMap('dimensionTemplates');
      final item =
          map[key] is Map ? Map<String, dynamic>.from(map[key] as Map) : {};
      final fallback = fallbackKey != null && map[fallbackKey] is Map
          ? Map<String, dynamic>.from(map[fallbackKey] as Map)
          : const <String, dynamic>{};
      String value(String field, String defaultValue) =>
          (item[field] ?? fallback[field] ?? defaultValue).toString();
      final values = {
        'tag': tag,
        'dominant': dominant,
        'money': radar.money,
        'pressure': radar.pressure,
        'roast': radar.roast,
        'blame': radar.blame,
        'slack': radar.slack,
        'dayGan': dayGan,
        'dayPillar': dayPillar,
      };
      return make(
        d: _fillTemplate(value('diagnosis', ''), values),
        p: _fillTemplate(value('prescription', ''), values),
        a: _fillTemplate(value('action', ''), values),
      );
    }

    return {
      DiagnosisDimension.career: fromTemplate('career'),
      DiagnosisDimension.love: fromTemplate(isMale ? 'loveMale' : 'loveFemale'),
      DiagnosisDimension.wealth: fromTemplate('wealth'),
      DiagnosisDimension.emotion: fromTemplate('emotion'),
      DiagnosisDimension.health: fromTemplate('health'),
      DiagnosisDimension.social: fromTemplate('social'),
    };
  }
}
