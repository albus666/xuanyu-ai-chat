import 'package:bazi_core/bazi_core.dart' show PillarType;
import 'package:lunar/lunar.dart';

import 'jiaoyun.dart';
import 'shen_sha_bazi_core.dart';

export 'gan_zhi_liu_yi.dart' show buildGanZhiLiuYi;

// LunarUtil：天干五合、四冲、地支冲合、五行表（与 6tail lunar 一致）

/// 排盘结果数据，与 myresource/bazi.py 输出对应
class BaziResult {
  final String yearGan;
  final String yearZhi;
  final String monthGan;
  final String monthZhi;
  final String dayGan;
  final String dayZhi;
  final String timeGan;
  final String timeZhi;
  final List<String> ganShens;   // 天干十神 4 个
  final List<String> zhiShens;   // 地支十神（主气）4 个
  final List<String> zhiCangGan; // 地支藏干（如 "癸" "己癸辛"）
  final List<String> daYun;      // 大运 12 步
  final String taiYuan;          // 胎元（月干+1 月支+3）
  final String taiXi;           // 胎息（日柱干支五合六合）
  final String mingGong;         // 命宫
  final String shenGong;        // 身宫
  final DateTime solarDate;      // 公历
  final String lunarYearMonthDay; // 农历年月日描述
  // 命主信息（能算的填，不能算的为空串）
  final String shengXiao;       // 生肖
  final String xingZuo;         // 星座
  final String riKong;          // 日空
  final String taiYuanNayin;    // 胎元纳音
  final String mingGongNayin;  // 命宫纳音
  final String taiXiNayin;     // 胎息纳音
  final String shenGongNayin;   // 身宫纳音
  final String daYunStart;     // 大运：出生后X年X月X日X时
  final String mangZhong;      // 芒种节气时刻
  final String xiaoShu;        // 小暑节气时刻
  final String jiaoYun;        // 交运描述
  /// 大运起始虚岁（由起运时间计算），小运为 1 至 daYunStartXuSui-1 岁
  final int daYunStartXuSui;

  const BaziResult({
    required this.yearGan,
    required this.yearZhi,
    required this.monthGan,
    required this.monthZhi,
    required this.dayGan,
    required this.dayZhi,
    required this.timeGan,
    required this.timeZhi,
    required this.ganShens,
    required this.zhiShens,
    required this.zhiCangGan,
    required this.daYun,
    required this.taiYuan,
    required this.taiXi,
    required this.mingGong,
    required this.shenGong,
    required this.solarDate,
    required this.lunarYearMonthDay,
    this.shengXiao = '',
    this.xingZuo = '',
    this.riKong = '',
    this.taiYuanNayin = '',
    this.mingGongNayin = '',
    this.taiXiNayin = '',
    this.shenGongNayin = '',
    this.daYunStart = '',
    this.mangZhong = '',
    this.xiaoShu = '',
    this.jiaoYun = '',
    this.daYunStartXuSui = 7,
    required this.mainStars,
    required this.xingYun,
    required this.ziZuo,
    required this.pillarEmpties,
    required this.pillarNayins,
    required this.zhiCangGanWithShen,
    required this.shenSha,
    required this.daYunWithShen,
    required this.siLing,
    required this.daYunAgeRanges,
    this.xiaoYun = '',
    this.liuNian = '',
    this.liuYue = '',
    required this.detailMainStars,
    required this.detailGans,
    required this.detailZhis,
    required this.detailXingYun,
    required this.detailZiZuo,
    required this.detailPillarEmpties,
    required this.detailPillarNayins,
    required this.detailZhiCangGanWithShen,
    required this.taiMingShenXingYun,
    required this.taiMingShenZiZuo,
    required this.taiMingShenEmpties,
    required this.taiMingShenZhiCangGanWithShen,
  });

  List<String> get gans => [yearGan, monthGan, dayGan, timeGan];
  List<String> get zhis => [yearZhi, monthZhi, dayZhi, timeZhi];

  /// 四柱字符串 如 "丙午 庚寅 丙辰 丙申"
  String get fourPillarsStr =>
      '$yearGan$yearZhi $monthGan$monthZhi $dayGan$dayZhi $timeGan$timeZhi';

  /// 基本命盘表格用：主星（十神全称，日柱为元男/元女）
  final List<String> mainStars;
  /// 星运：地支对日主的十二长生全称
  final List<String> xingYun;
  /// 自坐：天干对坐支的十二长生全称
  final List<String> ziZuo;
  /// 四柱空亡
  final List<String> pillarEmpties;
  /// 四柱纳音
  final List<String> pillarNayins;
  /// 藏干+十神全称，每柱多条如 ["丁·正官","己·正印"]
  final List<List<String>> zhiCangGanWithShen;
  /// 神煞（暂空，每柱可多条）
  final List<List<String>> shenSha;
  /// 大运干支+十神，如 "辛劫财 卯财"
  final List<String> daYunWithShen;
  /// 司令（月令当令之干，月支藏干主气）
  final String siLing;
  /// 大运年龄区间，如 ["1-6岁", "7-16岁", ...]
  final List<String> daYunAgeRanges;

  /// 小运干支（1岁小运从时柱起，此处取时柱）
  final String xiaoYun;
  /// 流年干支（当前公历年的干支）
  final String liuNian;
  /// 流月干支（当前节气月的干支）
  final String liuYue;
  /// 专业细盘表 7 列：年柱/月柱/日柱/时柱/大运/流年/流月
  final List<String> detailMainStars;
  final List<String> detailGans;
  final List<String> detailZhis;
  final List<String> detailXingYun;
  final List<String> detailZiZuo;
  final List<String> detailPillarEmpties;
  final List<String> detailPillarNayins;
  final List<List<String>> detailZhiCangGanWithShen;
  /// 胎元、命宫、身宫 的 星运/自坐/空亡/藏干（专业细盘胎命身开关打开时用）
  final List<String> taiMingShenXingYun;
  final List<String> taiMingShenZiZuo;
  final List<String> taiMingShenEmpties;
  final List<List<String>> taiMingShenZhiCangGanWithShen;
  Map<String, dynamic> toSharedJson() => {
        'timelineBasisYear': solarDate.year,
        'yearGan': yearGan,
        'yearZhi': yearZhi,
        'monthGan': monthGan,
        'monthZhi': monthZhi,
        'dayGan': dayGan,
        'dayZhi': dayZhi,
        'timeGan': timeGan,
        'timeZhi': timeZhi,
        'ganShens': ganShens,
        'zhiShens': zhiShens,
        'zhiCangGan': zhiCangGan,
        'daYun': daYun,
        'taiYuan': taiYuan,
        'taiXi': taiXi,
        'mingGong': mingGong,
        'shenGong': shenGong,
        'shengXiao': shengXiao,
        'xingZuo': xingZuo,
        'riKong': riKong,
        'taiYuanNayin': taiYuanNayin,
        'mingGongNayin': mingGongNayin,
        'taiXiNayin': taiXiNayin,
        'shenGongNayin': shenGongNayin,
        'daYunStart': daYunStart,
        'mangZhong': mangZhong,
        'xiaoShu': xiaoShu,
        'jiaoYun': jiaoYun,
        'daYunStartXuSui': daYunStartXuSui,
        'mainStars': mainStars,
        'xingYun': xingYun,
        'ziZuo': ziZuo,
        'pillarEmpties': pillarEmpties,
        'pillarNayins': pillarNayins,
        'zhiCangGanWithShen': zhiCangGanWithShen,
        'shenSha': shenSha,
        'daYunWithShen': daYunWithShen,
        'siLing': siLing,
        'daYunAgeRanges': daYunAgeRanges,
        'xiaoYun': xiaoYun,
        'liuNian': liuNian,
        'liuYue': liuYue,
        'detailMainStars': detailMainStars,
        'detailGans': detailGans,
        'detailZhis': detailZhis,
        'detailXingYun': detailXingYun,
        'detailZiZuo': detailZiZuo,
        'detailPillarEmpties': detailPillarEmpties,
        'detailPillarNayins': detailPillarNayins,
        'detailZhiCangGanWithShen': detailZhiCangGanWithShen,
        'taiMingShenXingYun': taiMingShenXingYun,
        'taiMingShenZiZuo': taiMingShenZiZuo,
        'taiMingShenEmpties': taiMingShenEmpties,
        'taiMingShenZhiCangGanWithShen': taiMingShenZhiCangGanWithShen,
      };

  factory BaziResult.fromSharedJson(Map<String, dynamic> data) {
    List<String> strings(String key) =>
        (data[key] as List? ?? []).map((e) => e.toString()).toList();
    List<List<String>> groups(String key) => (data[key] as List? ?? [])
        .map((e) => (e as List).map((v) => v.toString()).toList())
        .toList();
    if ((data['dayGan']?.toString() ?? '').isEmpty ||
        data['timelineBasisYear'] is! num) {
      throw const FormatException('专业八字数据缺失，请重新分享');
    }
    return BaziResult(
      yearGan: data['yearGan']?.toString() ?? '',
      yearZhi: data['yearZhi']?.toString() ?? '',
      monthGan: data['monthGan']?.toString() ?? '',
      monthZhi: data['monthZhi']?.toString() ?? '',
      dayGan: data['dayGan']?.toString() ?? '',
      dayZhi: data['dayZhi']?.toString() ?? '',
      timeGan: data['timeGan']?.toString() ?? '',
      timeZhi: data['timeZhi']?.toString() ?? '',
      ganShens: strings('ganShens'),
      zhiShens: strings('zhiShens'),
      zhiCangGan: strings('zhiCangGan'),
      daYun: strings('daYun'),
      taiYuan: data['taiYuan']?.toString() ?? '',
      taiXi: data['taiXi']?.toString() ?? '',
      mingGong: data['mingGong']?.toString() ?? '',
      shenGong: data['shenGong']?.toString() ?? '',
      solarDate: DateTime((data['timelineBasisYear'] as num).toInt(), 7, 1),
      lunarYearMonthDay: '',
      shengXiao: data['shengXiao']?.toString() ?? '',
      xingZuo: data['xingZuo']?.toString() ?? '',
      riKong: data['riKong']?.toString() ?? '',
      taiYuanNayin: data['taiYuanNayin']?.toString() ?? '',
      mingGongNayin: data['mingGongNayin']?.toString() ?? '',
      taiXiNayin: data['taiXiNayin']?.toString() ?? '',
      shenGongNayin: data['shenGongNayin']?.toString() ?? '',
      daYunStart: data['daYunStart']?.toString() ?? '',
      mangZhong: data['mangZhong']?.toString() ?? '',
      xiaoShu: data['xiaoShu']?.toString() ?? '',
      jiaoYun: data['jiaoYun']?.toString() ?? '',
      daYunStartXuSui: (data['daYunStartXuSui'] as num?)?.toInt() ?? 7,
      mainStars: strings('mainStars'),
      xingYun: strings('xingYun'),
      ziZuo: strings('ziZuo'),
      pillarEmpties: strings('pillarEmpties'),
      pillarNayins: strings('pillarNayins'),
      zhiCangGanWithShen: groups('zhiCangGanWithShen'),
      shenSha: groups('shenSha'),
      daYunWithShen: strings('daYunWithShen'),
      siLing: data['siLing']?.toString() ?? '',
      daYunAgeRanges: strings('daYunAgeRanges'),
      xiaoYun: data['xiaoYun']?.toString() ?? '',
      liuNian: data['liuNian']?.toString() ?? '',
      liuYue: data['liuYue']?.toString() ?? '',
      detailMainStars: strings('detailMainStars'),
      detailGans: strings('detailGans'),
      detailZhis: strings('detailZhis'),
      detailXingYun: strings('detailXingYun'),
      detailZiZuo: strings('detailZiZuo'),
      detailPillarEmpties: strings('detailPillarEmpties'),
      detailPillarNayins: strings('detailPillarNayins'),
      detailZhiCangGanWithShen: groups('detailZhiCangGanWithShen'),
      taiMingShenXingYun: strings('taiMingShenXingYun'),
      taiMingShenZiZuo: strings('taiMingShenZiZuo'),
      taiMingShenEmpties: strings('taiMingShenEmpties'),
      taiMingShenZhiCangGanWithShen: groups('taiMingShenZhiCangGanWithShen'),
    );
  }
}

/// 十神表：以日干为日主，其他天干/地支主气对应的十神（与 myresource/ganzhi.py ten_deities 一致）
const Map<String, Map<String, String>> _kTenDeities = {
  '甲': {'甲': '比', '乙': '劫', '丙': '食', '丁': '伤', '戊': '才', '己': '财', '庚': '杀', '辛': '官', '壬': '枭', '癸': '印', '子': '沐', '丑': '冠', '寅': '建', '卯': '帝', '辰': '衰', '巳': '病', '午': '死', '未': '墓', '申': '绝', '酉': '胎', '戌': '养', '亥': '长'},
  '乙': {'甲': '劫', '乙': '比', '丙': '伤', '丁': '食', '戊': '财', '己': '才', '庚': '官', '辛': '杀', '壬': '印', '癸': '枭', '子': '病', '丑': '衰', '寅': '帝', '卯': '建', '辰': '冠', '巳': '沐', '午': '长', '未': '养', '申': '胎', '酉': '绝', '戌': '墓', '亥': '死'},
  '丙': {'甲': '枭', '乙': '印', '丙': '比', '丁': '劫', '戊': '食', '己': '伤', '庚': '才', '辛': '财', '壬': '杀', '癸': '官', '子': '胎', '丑': '养', '寅': '长', '卯': '沐', '辰': '冠', '巳': '建', '午': '帝', '未': '衰', '申': '病', '酉': '死', '戌': '墓', '亥': '绝'},
  '丁': {'甲': '印', '乙': '枭', '丙': '劫', '丁': '比', '戊': '伤', '己': '食', '庚': '财', '辛': '才', '壬': '官', '癸': '杀', '子': '绝', '丑': '墓', '寅': '死', '卯': '病', '辰': '衰', '巳': '帝', '午': '建', '未': '冠', '申': '沐', '酉': '长', '戌': '养', '亥': '胎'},
  '戊': {'甲': '杀', '乙': '官', '丙': '枭', '丁': '印', '戊': '比', '己': '劫', '庚': '食', '辛': '伤', '壬': '才', '癸': '财', '子': '胎', '丑': '养', '寅': '长', '卯': '沐', '辰': '冠', '巳': '建', '午': '帝', '未': '衰', '申': '病', '酉': '死', '戌': '墓', '亥': '绝'},
  '己': {'甲': '官', '乙': '杀', '丙': '印', '丁': '枭', '戊': '劫', '己': '比', '庚': '伤', '辛': '食', '壬': '财', '癸': '才', '子': '绝', '丑': '墓', '寅': '死', '卯': '病', '辰': '衰', '巳': '帝', '午': '建', '未': '冠', '申': '沐', '酉': '长', '戌': '养', '亥': '胎'},
  '庚': {'甲': '才', '乙': '财', '丙': '杀', '丁': '官', '戊': '枭', '己': '印', '庚': '比', '辛': '劫', '壬': '食', '癸': '伤', '子': '死', '丑': '墓', '寅': '绝', '卯': '胎', '辰': '养', '巳': '长', '午': '沐', '未': '冠', '申': '建', '酉': '帝', '戌': '衰', '亥': '病'},
  '辛': {'甲': '财', '乙': '才', '丙': '官', '丁': '杀', '戊': '印', '己': '枭', '庚': '劫', '辛': '比', '壬': '伤', '癸': '食', '子': '长', '丑': '养', '寅': '胎', '卯': '绝', '辰': '墓', '巳': '死', '午': '病', '未': '衰', '申': '帝', '酉': '建', '戌': '冠', '亥': '沐'},
  '壬': {'甲': '食', '乙': '伤', '丙': '才', '丁': '财', '戊': '杀', '己': '官', '庚': '枭', '辛': '印', '壬': '比', '癸': '劫', '子': '帝', '丑': '衰', '寅': '病', '卯': '死', '辰': '墓', '巳': '绝', '午': '胎', '未': '养', '申': '长', '酉': '沐', '戌': '冠', '亥': '建'},
  '癸': {'甲': '伤', '乙': '食', '丙': '财', '丁': '才', '戊': '官', '己': '杀', '庚': '印', '辛': '枭', '壬': '劫', '癸': '比', '子': '建', '丑': '冠', '寅': '沐', '卯': '长', '辰': '养', '巳': '胎', '午': '绝', '未': '墓', '申': '死', '酉': '病', '戌': '衰', '亥': '帝'},
};

/// 地支藏干主气（与 myresource/ganzhi zhi5_list 一致，取第一个为主气）
const Map<String, List<String>> _zhi5List = {
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

const List<String> _gan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const List<String> _zhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

/// 纳音（与 myresource/datas.py nayins 一致），key 为 "干支" 如 "甲子"
const Map<String, String> _kNayins = {
  '甲子': '海中金', '乙丑': '海中金', '壬寅': '金泊金', '癸卯': '金泊金', '庚辰': '白蜡金', '辛巳': '白蜡金',
  '甲午': '沙中金', '乙未': '沙中金', '壬申': '剑锋金', '癸酉': '剑锋金', '庚戌': '钗钏金', '辛亥': '钗钏金',
  '戊子': '霹雳火', '己丑': '霹雳火', '丙寅': '炉中火', '丁卯': '炉中火', '甲辰': '覆灯火', '乙巳': '覆灯火',
  '戊午': '天上火', '己未': '天上火', '丙申': '山下火', '丁酉': '山下火', '甲戌': '山头火', '乙亥': '山头火',
  '壬子': '桑柘木', '癸丑': '桑柘木', '庚寅': '松柏木', '辛卯': '松柏木', '戊辰': '大林木', '己巳': '大林木',
  '壬午': '杨柳木', '癸未': '杨柳木', '庚申': '石榴木', '辛酉': '石榴木', '戊戌': '平地木', '己亥': '平地木',
  '庚子': '壁上土', '辛丑': '壁上土', '戊寅': '城头土', '己卯': '城头土', '丙辰': '砂中土', '丁巳': '砂中土',
  '庚午': '路旁土', '辛未': '路旁土', '戊申': '大驿土', '己酉': '大驿土', '丙戌': '屋上土', '丁亥': '屋上土',
  '丙子': '涧下水', '丁丑': '涧下水', '甲寅': '大溪水', '乙卯': '大溪水', '壬辰': '长流水', '癸巳': '长流水',
  '丙午': '天河水', '丁未': '天河水', '甲申': '井泉水', '乙酉': '井泉水', '壬戌': '大海水', '癸亥': '大海水',
};

/// 空亡（与 myresource/datas.py empties 一致），日柱干支 -> 空亡地支 "支1支2"
const Map<String, String> _kEmpties = {
  '甲子': '戌亥', '乙丑': '戌亥', '丙寅': '戌亥', '丁卯': '戌亥', '戊辰': '戌亥', '己巳': '戌亥',
  '庚午': '戌亥', '辛未': '戌亥', '壬申': '戌亥', '癸酉': '戌亥', '甲戌': '申酉', '乙亥': '申酉',
  '丙子': '申酉', '丁丑': '申酉', '戊寅': '申酉', '己卯': '申酉', '庚辰': '申酉', '辛巳': '申酉',
  '壬午': '申酉', '癸未': '申酉', '甲申': '午未', '乙酉': '午未', '丙戌': '午未', '丁亥': '午未',
  '戊子': '午未', '己丑': '午未', '庚寅': '午未', '辛卯': '午未', '壬辰': '午未', '癸巳': '午未',
  '甲午': '辰巳', '乙未': '辰巳', '丙申': '辰巳', '丁酉': '辰巳', '戊戌': '辰巳', '己亥': '辰巳',
  '庚子': '辰巳', '辛丑': '辰巳', '壬寅': '辰巳', '癸卯': '辰巳', '甲辰': '寅卯', '乙巳': '寅卯',
  '丙午': '寅卯', '丁未': '寅卯', '戊申': '寅卯', '己酉': '寅卯', '庚戌': '寅卯', '辛亥': '寅卯',
  '壬子': '寅卯', '癸丑': '寅卯', '甲寅': '子丑', '乙卯': '子丑', '丙辰': '子丑', '丁巳': '子丑',
  '戊午': '子丑', '己未': '子丑', '庚申': '子丑', '辛酉': '子丑', '壬戌': '子丑', '癸亥': '子丑',
};

/// 十二长生简写 -> 全称
const Map<String, String> _kChangShengFull = {
  '长': '长生', '沐': '沐浴', '冠': '冠带', '建': '临官', '帝': '帝旺',
  '衰': '衰', '病': '病', '死': '死', '墓': '墓', '绝': '绝', '胎': '胎', '养': '养',
};

/// 十神简写 -> 全称
const Map<String, String> _kShenFull = {
  '比': '比肩', '劫': '劫财', '食': '食神', '伤': '伤官', '才': '偏财', '财': '正财',
  '杀': '七杀', '官': '正官', '枭': '偏印', '印': '正印',
};

// ========== 神煞表（与 assets/bz/data/shen_sha.json 查法一致）==========

/// 年支查：孤辰、寡宿、大耗、丧门、吊客、披麻、灾煞、红鸾、天喜（填在月日时柱 i=1,2,3）
const Map<String, Map<String, String>> _yearShens = {
  '孤辰': {'子': '寅', '丑': '寅', '寅': '巳', '卯': '巳', '辰': '巳', '巳': '申',
          '午': '申', '未': '申', '申': '亥', '酉': '亥', '戌': '亥', '亥': '寅'},
  '寡宿': {'子': '戌', '丑': '戌', '寅': '丑', '卯': '丑', '辰': '丑', '巳': '辰',
          '午': '辰', '未': '辰', '申': '未', '酉': '未', '戌': '未', '亥': '戌'},
  '大耗': {'子': '巳未', '丑': '午申', '寅': '未酉', '卯': '申戌', '辰': '酉亥', '巳': '戌子',
          '午': '亥丑', '未': '子寅', '申': '丑卯', '酉': '寅辰', '戌': '卯巳', '亥': '辰午'},
  '丧门': {'子': '寅', '丑': '卯', '寅': '辰', '卯': '巳', '辰': '午', '巳': '未',
          '午': '申', '未': '酉', '申': '戌', '酉': '亥', '戌': '子', '亥': '丑'},
  '吊客': {'子': '戌', '丑': '亥', '寅': '子', '卯': '丑', '辰': '寅', '巳': '卯',
          '午': '辰', '未': '巳', '申': '午', '酉': '未', '戌': '申', '亥': '酉'},
  '披麻': {'子': '酉', '丑': '戌', '寅': '亥', '卯': '子', '辰': '丑', '巳': '寅',
          '午': '卯', '未': '辰', '申': '巳', '酉': '午', '戌': '未', '亥': '申'},
  '灾煞': {'子': '午', '丑': '', '寅': '子', '卯': '酉', '辰': '午', '巳': '卯',
          '午': '子', '未': '酉', '申': '午', '酉': '卯', '戌': '子', '亥': '酉'},
  '红鸾': {'子': '卯', '丑': '寅', '寅': '丑', '卯': '子', '辰': '亥', '巳': '戌',
          '午': '酉', '未': '申', '申': '未', '酉': '午', '戌': '巳', '亥': '辰'},
  '天喜': {'子': '酉', '丑': '申', '寅': '未', '卯': '午', '辰': '巳', '巳': '辰',
          '午': '卯', '未': '寅', '申': '丑', '酉': '子', '戌': '亥', '亥': '戌'},
  '勾绞煞': {'子': '卯', '丑': '辰', '寅': '巳', '卯': '午', '辰': '未', '巳': '申',
             '午': '酉', '未': '戌', '申': '亥', '酉': '子', '戌': '丑', '亥': '寅'},
};

/// 月支查：天德贵人、月德贵人、天医、血刃、月德合（填在四柱；天德值为干或支，月德/月德合为干，天医/血刃为支）
const Map<String, Map<String, String>> _monthShens = {
  '天德贵人': {'子': '巳', '丑': '庚', '寅': '丁', '卯': '申', '辰': '壬', '巳': '辛',
               '午': '亥', '未': '甲', '申': '癸', '酉': '寅', '戌': '丙', '亥': '乙'},
  '月德贵人': {'子': '壬', '丑': '庚', '寅': '丙', '卯': '甲', '辰': '壬', '巳': '庚',
               '午': '丙', '未': '甲', '申': '壬', '酉': '庚', '戌': '丙', '亥': '甲'},
  '天医': {'子': '亥', '丑': '子', '寅': '丑', '卯': '寅', '辰': '卯', '巳': '辰',
           '午': '巳', '未': '午', '申': '未', '酉': '申', '戌': '酉', '亥': '戌'},
  '血刃': {'子': '午', '丑': '子', '寅': '丑', '卯': '未', '辰': '寅', '巳': '申',
           '午': '卯', '未': '酉', '申': '辰', '酉': '戌', '戌': '巳', '亥': '亥'},
  '月德合': {'子': '丁', '丑': '乙', '寅': '辛', '卯': '己', '辰': '丁', '巳': '乙',
             '午': '辛', '未': '己', '申': '丁', '酉': '乙', '戌': '辛', '亥': '己'},
};

/// 天德（通行版，月支→天干）：用于推导天德合。天德合 = 该干的五合之干，仅查四柱天干
const Map<String, String> _tianDeGanByMonth = {
  '寅': '丙', '卯': '丁', '辰': '戊', '巳': '己', '午': '庚', '未': '辛',
  '申': '壬', '酉': '癸', '戌': '甲', '亥': '乙', '子': '丙', '丑': '丁',
};

/// 天干五合：甲己、乙庚、丙辛、丁壬、戊癸 → 取合干（如癸→戊）
const Map<String, String> _wuHeGan = {
  '甲': '己', '乙': '庚', '丙': '辛', '丁': '壬', '戊': '癸',
  '己': '甲', '庚': '乙', '辛': '丙', '壬': '丁', '癸': '戊',
};

/// 词馆：日干查四柱干支（某柱干支=该组合则填该柱）
const Map<String, String> _ciGuanByDayGan = {
  '甲': '庚寅', '乙': '辛卯', '丙': '乙巳', '丁': '戊午', '戊': '丁巳',
  '己': '庚午', '庚': '壬申', '辛': '癸酉', '壬': '癸亥', '癸': '壬戌',
};

/// 天转：月支+日柱（寅卯辰→乙卯，巳午未→丙午，申酉戌→辛酉，亥子丑→壬子）
const Map<String, String> _tianZhuanDayByMonth = {
  '寅': '乙卯', '卯': '乙卯', '辰': '乙卯',
  '巳': '丙午', '午': '丙午', '未': '丙午',
  '申': '辛酉', '酉': '辛酉', '戌': '辛酉',
  '亥': '壬子', '子': '壬子', '丑': '壬子',
};

/// 地转：月支+日柱（寅卯辰→辛卯，巳午未→戊午，申酉戌→癸酉，亥子丑→丙子）
const Map<String, String> _diZhuanDayByMonth = {
  '寅': '辛卯', '卯': '辛卯', '辰': '辛卯',
  '巳': '戊午', '午': '戊午', '未': '戊午',
  '申': '癸酉', '酉': '癸酉', '戌': '癸酉',
  '亥': '丙子', '子': '丙子', '丑': '丙子',
};

/// 拱禄：日柱+时柱组合（标在时柱）
const List<(String, String)> _gongLuPairs = [
  ('癸亥', '癸丑'), ('癸丑', '癸亥'),
  ('丁巳', '丁未'), ('己未', '己巳'), ('戊辰', '戊午'),
];

/// 三奇贵人：四柱天干中按顺序出现 甲戊庚 / 乙丙丁 / 壬癸辛（顺连）
bool _hasSanQiGuiRen(List<String> gans) {
  bool find(List<String> seq) {
    int k = 0;
    for (int i = 0; i < gans.length && k < seq.length; i++) {
      if (gans[i] == seq[k]) k++;
    }
    return k == seq.length;
  }
  return find(['甲', '戊', '庚']) || find(['乙', '丙', '丁']) || find(['壬', '癸', '辛']);
}

/// 日支查：将星、华盖、驿马、劫煞、亡神、桃花（填在年月时柱 i=0,1,3）
const Map<String, Map<String, String>> _dayShens = {
  '将星': {'子': '子', '丑': '酉', '寅': '午', '卯': '卯', '辰': '子', '巳': '酉',
          '午': '午', '未': '卯', '申': '子', '酉': '酉', '戌': '午', '亥': '卯'},
  '华盖': {'子': '辰', '丑': '丑', '寅': '戌', '卯': '未', '辰': '辰', '巳': '丑',
          '午': '戌', '未': '未', '申': '辰', '酉': '丑', '戌': '戌', '亥': '未'},
  '驿马': {'子': '寅', '丑': '亥', '寅': '申', '卯': '巳', '辰': '寅', '巳': '亥',
          '午': '申', '未': '巳', '申': '寅', '酉': '亥', '戌': '申', '亥': '巳'},
  '劫煞': {'子': '巳', '丑': '寅', '寅': '亥', '卯': '申', '辰': '巳', '巳': '寅',
          '午': '亥', '未': '申', '申': '巳', '酉': '寅', '戌': '亥', '亥': '申'},
  '亡神': {'子': '亥', '丑': '申', '寅': '巳', '卯': '寅', '辰': '亥', '巳': '申',
          '午': '巳', '未': '寅', '申': '亥', '酉': '申', '戌': '巳', '亥': '寅'},
  '桃花': {'子': '酉', '丑': '午', '寅': '卯', '卯': '子', '辰': '酉', '巳': '午',
          '午': '卯', '未': '子', '申': '酉', '酉': '午', '戌': '卯', '亥': '子'},
};

/// 日干查：天乙贵人、文昌贵人、羊刃、红艳煞、国印贵人、金舆、禄神、太极贵人、福星贵人、飞刃、流霞、天厨贵人（填在四柱）
const Map<String, Map<String, String>> _gShens = {
  '天乙贵人': {'甲': '未丑', '乙': '申子', '丙': '酉亥', '丁': '酉亥', '戊': '未丑', '己': '申子',
               '庚': '未丑', '辛': '寅午', '壬': '卯巳', '癸': '卯巳'},
  '文昌贵人': {'甲': '巳', '乙': '午', '丙': '申', '丁': '酉', '戊': '申', '己': '酉',
               '庚': '亥', '辛': '子', '壬': '寅', '癸': '卯'},
  '羊刃': {'甲': '卯', '乙': '寅', '丙': '午', '丁': '巳', '戊': '午', '己': '巳',
           '庚': '酉', '辛': '申', '壬': '子', '癸': '亥'},
  '红艳煞': {'甲': '午', '乙': '午', '丙': '寅', '丁': '未', '戊': '辰', '己': '辰',
             '庚': '戌', '辛': '酉', '壬': '子', '癸': '申'},
  '国印贵人': {'甲': '戌', '乙': '亥', '丙': '丑', '丁': '寅', '戊': '丑', '己': '寅',
               '庚': '辰', '辛': '巳', '壬': '未', '癸': '申'},
  '金舆': {'甲': '辰', '乙': '巳', '丙': '未', '丁': '申', '戊': '未', '己': '申',
           '庚': '戌', '辛': '亥', '壬': '丑', '癸': '寅'},
  '禄神': {'甲': '寅', '乙': '卯', '丙': '巳', '丁': '午', '戊': '巳', '己': '午',
           '庚': '申', '辛': '酉', '壬': '亥', '癸': '子'},
  '太极贵人': {'甲': '子午', '乙': '子午', '丙': '卯酉', '丁': '卯酉', '戊': '辰戌丑未', '己': '辰戌丑未',
               '庚': '寅亥', '辛': '寅亥', '壬': '巳申', '癸': '巳申'},
  '福星贵人': {'甲': '寅子', '乙': '卯丑', '丙': '寅子', '丁': '亥', '戊': '申', '己': '未',
               '庚': '午', '辛': '巳', '壬': '辰', '癸': '卯丑'},
  '飞刃': {'甲': '酉', '乙': '申', '丙': '子', '丁': '亥', '戊': '子', '己': '亥',
           '庚': '卯', '辛': '寅', '壬': '午', '癸': '巳'},
  '流霞': {'甲': '酉', '乙': '戌', '丙': '未', '丁': '申', '戊': '巳', '己': '午',
           '庚': '辰', '辛': '卯', '壬': '亥', '癸': '寅'},
  '天厨贵人': {'甲': '', '乙': '', '丙': '巳', '丁': '午', '戊': '申', '己': '酉',
               '庚': '亥', '辛': '子', '壬': '寅', '癸': '卯'},
};

/// 天罗地网：戌亥为天罗、辰巳为地网，四柱见则填
const List<String> _tianLuoZhi = ['戌', '亥'];
const List<String> _diWangZhi = ['辰', '巳'];

/// 日柱专属神煞（仅填在日柱 i=2）：魁罡、阴差阳错、十灵日、八专、九丑日、四废、天赦日、金神、十恶大败、孤鸾煞、六秀日
const List<String> _kuiGangDays = ['庚辰', '庚戌', '壬辰', '戊戌'];
const List<String> _yinChaYangCuoDays = [
  '丙子', '丁丑', '戊寅', '辛卯', '壬辰', '癸巳', '丙午', '丁未', '戊申', '辛酉', '壬戌', '癸亥'
];
const List<String> _shiLingDays = ['甲辰', '乙亥', '丙辰', '丁酉', '戊午', '庚戌', '庚寅', '辛亥', '壬寅', '癸未'];
const List<String> _baZhuanDays = ['甲寅', '乙卯', '丁未', '戊戌', '己未', '庚申', '辛酉', '癸丑'];
const List<String> _jiuChouDays = ['丁酉', '戊子', '戊午', '己卯', '己酉', '辛卯', '辛酉', '壬子', '壬午'];
const List<String> _siFeiDays = ['庚申', '辛酉', '壬子', '癸亥', '甲寅', '乙卯', '丙午', '丁巳'];
const List<String> _jinShenDays = ['乙丑', '己巳', '癸酉'];
const List<String> _shiEDaBaiDays = ['甲辰', '乙巳', '壬申', '丙申', '丁亥', '庚辰', '戊戌', '癸亥', '辛巳', '己丑'];
const List<String> _guLuanDays = ['甲寅', '乙巳', '丙午', '丁巳', '戊午', '戊申', '辛亥', '壬子'];
const List<String> _liuXiuDays = ['丙午', '丁未', '戊子', '戊午', '己丑', '己未'];

/// 天赦日：寅卯辰月戊寅、巳午未月甲午、申酉戌月戊申、亥子丑月甲子（需结合月支判断）
bool _isTianSheDay(String dayPillar, String monthZhi) {
  if (dayPillar != '戊寅' && dayPillar != '甲午' && dayPillar != '戊申' && dayPillar != '甲子') return false;
  const spring = ['寅', '卯', '辰'], summer = ['巳', '午', '未'];
  const autumn = ['申', '酉', '戌'], winter = ['亥', '子', '丑'];
  if (spring.contains(monthZhi) && dayPillar == '戊寅') return true;
  if (summer.contains(monthZhi) && dayPillar == '甲午') return true;
  if (autumn.contains(monthZhi) && dayPillar == '戊申') return true;
  if (winter.contains(monthZhi) && dayPillar == '甲子') return true;
  return false;
}

/// 德秀贵人：月支查四柱天干（寅午戌丙丁戊癸，申子辰壬癸戊己丙辛甲己，巳酉丑庚辛乙，亥卯未甲乙丁壬）
const Map<String, String> _deXiuGanByMonth = {
  '寅': '丙丁戊癸', '午': '丙丁戊癸', '戌': '丙丁戊癸',
  '申': '壬癸戊己丙辛甲己', '子': '壬癸戊己丙辛甲己', '辰': '壬癸戊己丙辛甲己',
  '巳': '庚辛乙', '酉': '庚辛乙', '丑': '庚辛乙',
  '亥': '甲乙丁壬', '卯': '甲乙丁壬', '未': '甲乙丁壬',
};

/// 学堂：年纳音查月日时支（金巳、木亥、水申、土申、火寅）
String? _xueTangZhiFromNayin(String nayin) {
  if (nayin.isEmpty) return null;
  if (nayin.contains('金')) return '巳';
  if (nayin.contains('木')) return '亥';
  if (nayin.contains('水')) return '申';
  if (nayin.contains('土')) return '申';
  if (nayin.contains('火')) return '寅';
  return null;
}

/// 童子煞：日支或时支满足则标在该柱。返回 (日柱标, 时柱标)。
(bool, bool) _tongZiShaInDayOrTime(String monthZhi, String dayZhi, String timeZhi, String yearNayin) {
  const spring = ['寅', '卯', '辰'], autumn = ['申', '酉', '戌'];
  const summer = ['巳', '午', '未'], winter = ['亥', '子', '丑'];
  bool dayOk = false, timeOk = false;
  if (spring.contains(monthZhi) || autumn.contains(monthZhi)) {
    if (dayZhi == '寅' || dayZhi == '子') dayOk = true;
    if (timeZhi == '寅' || timeZhi == '子') timeOk = true;
  }
  if (summer.contains(monthZhi) || winter.contains(monthZhi)) {
    if (dayZhi == '卯' || dayZhi == '未' || dayZhi == '辰') dayOk = true;
    if (timeZhi == '卯' || timeZhi == '未' || timeZhi == '辰') timeOk = true;
  }
  if (yearNayin.contains('金') || yearNayin.contains('木')) {
    if (dayZhi == '午' || dayZhi == '卯') dayOk = true;
    if (timeZhi == '午' || timeZhi == '卯') timeOk = true;
  }
  if (yearNayin.contains('水') || yearNayin.contains('火')) {
    if (dayZhi == '酉' || dayZhi == '戌') dayOk = true;
    if (timeZhi == '酉' || timeZhi == '戌') timeOk = true;
  }
  if (yearNayin.contains('土')) {
    if (dayZhi == '辰' || dayZhi == '巳') dayOk = true;
    if (timeZhi == '辰' || timeZhi == '巳') timeOk = true;
  }
  return (dayOk, timeOk);
}

/// 四废：春庚申辛酉、夏壬子癸亥、秋甲寅乙卯、冬丙午丁巳（日柱+月支）
bool _isSiFeiDay(String dayPillar, String monthZhi) {
  if (!_siFeiDays.contains(dayPillar)) return false;
  const spring = ['寅', '卯', '辰'], summer = ['巳', '午', '未'];
  const autumn = ['申', '酉', '戌'], winter = ['亥', '子', '丑'];
  if (spring.contains(monthZhi) && ['庚申', '辛酉'].contains(dayPillar)) return true;
  if (summer.contains(monthZhi) && ['壬子', '癸亥'].contains(dayPillar)) return true;
  if (autumn.contains(monthZhi) && ['甲寅', '乙卯'].contains(dayPillar)) return true;
  if (winter.contains(monthZhi) && ['丙午', '丁巳'].contains(dayPillar)) return true;
  return false;
}

List<List<String>> _computeShenSha({
  required List<String> gans,
  required List<String> zhis,
  required String yearZhi,
  required String monthZhi,
  required String dayZhi,
  required String dayGan,
  required String yearNayin,
}) {
  final out = List.generate(4, (_) => <String>{});
  // 年支神煞：孤辰寡宿丧门等填在月日时柱 i=1,2,3
  for (final entry in _yearShens.entries) {
    final val = entry.value[yearZhi];
    if (val == null || val.isEmpty) continue;
    for (int i = 1; i <= 3; i++) {
      final z = zhis[i];
      if (val.length == 1 && z == val) out[i].add(entry.key);
      if (val.length >= 2 && val.contains(z)) out[i].add(entry.key);
    }
  }
  // 年支查将星、华盖、驿马、劫煞、亡神、桃花：查「余支」填在月日时（i=1,2,3），不填年柱
  for (final entry in _dayShens.entries) {
    final val = entry.value[yearZhi];
    if (val == null) continue;
    for (int i = 1; i <= 3; i++) {
      final z = zhis[i];
      if (val.length == 1 && z == val) out[i].add(entry.key);
      if (val.length >= 2 && val.contains(z)) out[i].add(entry.key);
    }
  }
  // 月支神煞：天德贵人看干或支，月德贵人/月德合看干，天医/血刃看支
  for (final entry in _monthShens.entries) {
    final val = entry.value[monthZhi];
    if (val == null) continue;
    final key = entry.key;
    final byGan = key == '天德贵人' || key == '月德贵人' || key == '月德合';
    final byZhi = key == '天医' || key == '血刃';
    for (int i = 0; i < 4; i++) {
      if (byZhi) {
        if (zhis[i] == val) out[i].add(key);
      } else if (key == '天德贵人') {
        if (gans[i] == val || zhis[i] == val) out[i].add(key);
      } else if (byGan) {
        if (gans[i] == val) out[i].add(key);
      }
    }
  }
  // 天德合：天德之干的五合之干，仅查四柱天干（酉月天德癸→癸合戊→见戊才标）
  final tianDeGan = _tianDeGanByMonth[monthZhi];
  if (tianDeGan != null) {
    final tianDeHeGan = _wuHeGan[tianDeGan];
    if (tianDeHeGan != null && tianDeHeGan.isNotEmpty) {
      for (int i = 0; i < 4; i++) {
        if (gans[i] == tianDeHeGan) out[i].add('天德合');
      }
    }
  }
  // 词馆：日干→干支，四柱任一支柱=该干支则填该柱
  final ciGuanPillar = _ciGuanByDayGan[dayGan];
  if (ciGuanPillar != null) {
    for (int i = 0; i < 4; i++) {
      if (gans[i] + zhis[i] == ciGuanPillar) out[i].add('词馆');
    }
  }
  // 三奇贵人：四柱天干顺连 甲戊庚 / 乙丙丁 / 壬癸辛 → 标日柱
  if (_hasSanQiGuiRen(gans)) out[2].add('三奇贵人');
  // 天转 / 地转：月支+日柱匹配 → 标日柱
  final dayPillarForTianDi = dayGan + dayZhi;
  if (_tianZhuanDayByMonth[monthZhi] == dayPillarForTianDi) out[2].add('天转');
  if (_diZhuanDayByMonth[monthZhi] == dayPillarForTianDi) out[2].add('地转');
  // 拱禄：日柱+时柱特定组合 → 标时柱
  final timePillar = gans[3] + zhis[3];
  for (final p in _gongLuPairs) {
    if (p.$1 == dayPillarForTianDi && p.$2 == timePillar) {
      out[3].add('拱禄');
      break;
    }
  }
  // 日支神煞：填在年月时柱 i=0,1,3
  for (final entry in _dayShens.entries) {
    final val = entry.value[dayZhi];
    if (val == null) continue;
    for (final i in [0, 1, 3]) {
      if (val.length == 1) {
        if (zhis[i] == val) out[i].add(entry.key);
      } else {
        if (val.contains(zhis[i])) out[i].add(entry.key);
      }
    }
  }
  // 日干神煞：以日干查四地支，地支符合的柱标该神煞；文昌/天厨/金舆再在日柱标一份（表示命带，仅展示）
  const dayGanShensShowOnDayPillar = {'文昌贵人', '天厨贵人', '金舆'};
  for (final entry in _gShens.entries) {
    if (entry.key == '福星贵人') continue;
    final val = entry.value[dayGan];
    if (val == null || val.isEmpty) continue;
    for (int i = 0; i < 4; i++) {
      if (val.length == 1) {
        if (zhis[i] == val) out[i].add(entry.key);
      } else {
        if (val.contains(zhis[i])) out[i].add(entry.key);
      }
    }
    if (dayGanShensShowOnDayPillar.contains(entry.key)) {
      final anyHas = val.length == 1
          ? zhis.any((z) => z == val)
          : zhis.any((z) => val.contains(z));
      if (anyHas) out[2].add(entry.key);
    }
  }
  // 福星贵人：以年/月干查四柱地支（与 JSON 查法一致）
  final fuXingMap = _gShens['福星贵人']!;
  for (final gan in [gans[0], gans[1]]) {
    final val = fuXingMap[gan];
    if (val == null || val.isEmpty) continue;
    for (int i = 0; i < 4; i++) {
      if (val.length == 1) { if (zhis[i] == val) out[i].add('福星贵人'); }
      else { if (val.contains(zhis[i])) out[i].add('福星贵人'); }
    }
  }
  // 天罗地网：以年、日支查余三支。戌见亥/亥见戌为天罗；辰见巳/巳见辰为地网（男忌天罗，女忌地网）
  for (int i = 0; i < 4; i++) {
    final z = zhis[i];
    // 天罗：年支戌则余三支见亥标天罗；年支亥则余三支见戌标天罗；日支同理
    if (yearZhi == '戌' && z == '亥' && i != 0) out[i].add('天罗');
    if (yearZhi == '亥' && z == '戌' && i != 0) out[i].add('天罗');
    if (dayZhi == '戌' && z == '亥' && i != 2) out[i].add('天罗');
    if (dayZhi == '亥' && z == '戌' && i != 2) out[i].add('天罗');
    // 地网：年支辰则余三支见巳标地网；年支巳则余三支见辰标地网；日支同理
    if (yearZhi == '辰' && z == '巳' && i != 0) out[i].add('地网');
    if (yearZhi == '巳' && z == '辰' && i != 0) out[i].add('地网');
    if (dayZhi == '辰' && z == '巳' && i != 2) out[i].add('地网');
    if (dayZhi == '巳' && z == '辰' && i != 2) out[i].add('地网');
  }
  // 空亡：以日柱定旬，四柱地支落在空亡支则神煞行加「空亡」
  final kongWangZhi = _kEmpties[dayGan + dayZhi] ?? '';
  if (kongWangZhi.length >= 2) {
    for (int i = 0; i < 4; i++) {
      if (zhis[i] == kongWangZhi[0] || zhis[i] == kongWangZhi[1]) out[i].add('空亡');
    }
  }
  // 德秀贵人：月支查四柱天干
  final deXiuGans = _deXiuGanByMonth[monthZhi];
  if (deXiuGans != null && deXiuGans.isNotEmpty) {
    for (int i = 0; i < 4; i++) {
      if (deXiuGans.contains(gans[i])) out[i].add('德秀贵人');
    }
  }
  // 学堂：年纳音查月日时支（禄命法）
  final xueTangZhi = _xueTangZhiFromNayin(yearNayin);
  if (xueTangZhi != null) {
    for (int i = 1; i <= 3; i++) {
      if (zhis[i] == xueTangZhi) out[i].add('学堂');
    }
  }
  // 日柱专属神煞（仅填在日柱 i=2）
  final dayPillar = dayGan + dayZhi;
  if (_kuiGangDays.contains(dayPillar)) out[2].add('魁罡');
  if (_yinChaYangCuoDays.contains(dayPillar)) out[2].add('阴差阳错');
  if (_shiLingDays.contains(dayPillar)) out[2].add('十灵日');
  if (_baZhuanDays.contains(dayPillar)) out[2].add('八专');
  if (_jiuChouDays.contains(dayPillar)) out[2].add('九丑日');
  if (_jinShenDays.contains(dayPillar)) out[2].add('金神');
  if (_shiEDaBaiDays.contains(dayPillar)) out[2].add('十恶大败');
  if (_guLuanDays.contains(dayPillar)) out[2].add('孤鸾煞');
  if (_liuXiuDays.contains(dayPillar)) out[2].add('六秀日');
  if (_isTianSheDay(dayPillar, monthZhi)) out[2].add('天赦日');
  if (_isSiFeiDay(dayPillar, monthZhi)) out[2].add('四废');
  // 童子煞：日支或时支满足则标在该柱（春秋寅子、冬夏卯未辰、金木午卯、水火酉戌、土辰巳）
  final (inDay, inTime) = _tongZiShaInDayOrTime(monthZhi, dayZhi, zhis[3], yearNayin);
  if (inDay) out[2].add('童子煞');
  if (inTime) out[3].add('童子煞');
  return out.map((s) => s.toList()..sort()).toList();
}

// ---------- 排盘公共辅助（复用空亡/纳音/藏干+十神/星运/自坐，不改变结果）----------

List<String> _emptiesForPillars(List<String> gans, List<String> zhis) {
  return List.generate(gans.length, (i) => _kEmpties[gans[i] + zhis[i]] ?? '');
}

List<String> _nayinsForPillars(
  List<String> gans,
  List<String> zhis, {
  /// 若提供，则前 4 柱直接使用 lunar.getBaZiNaYin() 的结果，其余柱仍按 _kNayins 计算
  List<String>? baseBaZiNaYin,
}) {
  return List.generate(gans.length, (i) {
    if (baseBaZiNaYin != null && i < baseBaZiNaYin.length) {
      return baseBaZiNaYin[i];
    }
    return _kNayins[gans[i] + zhis[i]] ?? '';
  });
}

List<List<String>> _zhiCangWithShenForZhis(List<String> zhis, Map<String, String> td) {
  return zhis.map((z) => (_zhi5List[z] ?? []).map((g) => '$g·${_shenFull(td[g])}').toList()).toList();
}

List<String> _xingYunForZhis(List<String> zhis, Map<String, String> td) {
  return zhis.map((z) => _changShengFull(td[z])).toList();
}

List<String> _ziZuoForPillars(List<String> gans, List<String> zhis) {
  return List.generate(gans.length, (i) {
    final t = _kTenDeities[gans[i]];
    return _changShengFull(t != null ? t[zhis[i]] : null);
  });
}

List<String> _mainStarsForFourPillars(String yearGan, String monthGan, String timeGan, bool isFemale, Map<String, String> td) {
  return [_shenFull(td[yearGan]), _shenFull(td[monthGan]), isFemale ? '元女' : '元男', _shenFull(td[timeGan])];
}

List<String> _mainStarsForExtPillars(List<String> extGans, List<String> extZhis, int dayIndex, bool isFemale, Map<String, String> td) {
  return List.generate(extGans.length, (i) => i == dayIndex ? (isFemale ? '元女' : '元男') : _shenFull(td[extGans[i]]));
}

(String, String) _buildMangZhongXiaoShu(dynamic lunar) {
  try {
    final jieQiTable = lunar.getJieQiTable();
    final mangSolar = jieQiTable['芒种'];
    final xiaoSolar = jieQiTable['小暑'];
    return (
      mangSolar != null ? _solarToDateTimeStr(mangSolar) : '',
      xiaoSolar != null ? _solarToDateTimeStr(xiaoSolar) : '',
    );
  } catch (_) {
    return ('', '');
  }
}

List<String> _daYunWithShenList(List<String> daYun, Map<String, String> td) {
  return daYun.map((s) {
    if (s.length < 2) return s;
    final gan = s[0];
    final zhi = s.substring(1);
    final zhiMain = _zhi5List[zhi];
    final zhiShen = (zhiMain != null && zhiMain.isNotEmpty) ? _shenFull(td[zhiMain.first]) : '';
    return '$gan${_shenFull(td[gan])} $zhi$zhiShen';
  }).toList();
}

/// 大运年龄：直接使用 lunar DaYun.getStartAge()，如 4岁、14岁、24岁…
List<String> _daYunAgeRangesFromDaYun(List<DaYun> daYunList) {
  return daYunList.map((d) => '${d.getStartAge()}岁').toList();
}

/// 夜子时归一化：
/// - sect=2：晚子时日柱算当天（不改时间）
/// - sect=1：晚子时日柱算明天（23:xx 归到次日 0:xx）
DateTime _normalizeYeZiShi(DateTime dt, {int sect = 2}) {
  if (sect == 2) {
    // 流派2：晚子时日柱算当天
    return dt;
  }
  if (dt.hour >= 23) {
    final next = dt.add(const Duration(days: 1));
    return DateTime(next.year, next.month, next.day, dt.hour - 23, dt.minute, dt.second);
  }
  return dt;
}

/// 供 compute() 在后台 isolate 中调用，避免排盘计算阻塞 UI
BaziResult computeBaziResultInIsolate((int, bool) args) {
  final birth = DateTime.fromMillisecondsSinceEpoch(args.$1);
  return computeBaziResult(birth, isFemale: args.$2);
}

/// 从公历时间计算排盘结果（当前固定：子时流派1、起运流派1）
BaziResult computeBaziResult(DateTime dt, {required bool isFemale}) {
  const ziShiSect = 1; // 晚子时日柱算次日（23:00 起按第二天）
  const yunSect = 1; // 3天=1年，1天=4月，1时辰=10天
  final effectiveDt = _normalizeYeZiShi(dt, sect: ziShiSect);
  final lunar = Lunar.fromDate(effectiveDt);
  final eightChar = lunar.getEightChar();
  eightChar.setSect(ziShiSect);
  final yun = eightChar.getYun(isFemale ? 0 : 1, yunSect);

  final yearGan = eightChar.getYearGan();
  final yearZhi = eightChar.getYearZhi();
  final monthGan = eightChar.getMonthGan();
  final monthZhi = eightChar.getMonthZhi();
  final dayGan = eightChar.getDayGan();
  final dayZhi = eightChar.getDayZhi();
  final timeGan = eightChar.getTimeGan();
  final timeZhi = eightChar.getTimeZhi();

  final me = dayGan;
  final td = _kTenDeities[me] ?? {};

  final ganShens = <String>[td[yearGan] ?? '--', td[monthGan] ?? '--', '--', td[timeGan] ?? '--'];
  final zhiShens = <String>[];
  final zhiCangGan = <String>[];
  for (final z in [yearZhi, monthZhi, dayZhi, timeZhi]) {
    final list = _zhi5List[z] ?? [];
    zhiCangGan.add(list.join());
    zhiShens.add(list.isNotEmpty ? (td[list.first] ?? '') : '');
  }

  // 大运列表改为直接使用 lunar Yun.getDaYunBy() 计算，
  // 同时过滤掉 index=0 的「小运占位」，仅保留真正大运（index>=1）。
  // 为了得到 12 步大运，需要请求 13 轮（含 index=0 小运占位）。
  final allDaYun = yun.getDaYunBy(13);
  final daYunList = allDaYun.where((d) => d.getIndex() >= 1).take(12).toList();
  final daYun = daYunList.map((d) => d.getGanZhi()).toList();

  final lunarY = lunar.getYear();
  final lunarM = lunar.getMonth();
  final lunarD = lunar.getDay();
  final lunarStr = '$lunarY年${_lunarMonthCn(lunarM)}月${_lunarDayCn(lunarD)}';
  // 排盘用公历日期取夜子时规范化后的日期，与日柱一致
  final solarDateForResult = effectiveDt;

  // 胎元 / 胎息 / 命宫 / 身宫 统一改用 lunar EightChar 内置逻辑
  final taiYuan = eightChar.getTaiYuan();
  final taiXi = eightChar.getTaiXi();
  final mingGong = eightChar.getMingGong();
  final shenGong = eightChar.getShenGong();

  // 生肖直接使用 lunar 内置
  final shengXiao = lunar.getYearShengXiao();
  final xingZuo = _westernZodiac(solarDateForResult);
  // 日空使用 EightChar.getDayXunKong()，与库保持一致
  final riKong = eightChar.getDayXunKong();
  final taiYuanNayin = eightChar.getTaiYuanNaYin();
  final mingGongNayin = eightChar.getMingGongNaYin();
  final taiXiNayin = eightChar.getTaiXiNaYin();
  final shenGongNayin = eightChar.getShenGongNaYin();

  final (daYunStart, jiaoYun, daYunStartXuSui) = buildDaYunStartAndJiaoYun(
    eightChar,
    isFemale,
    solarDateForResult,
    yunSect: yunSect,
  );
  final (mangZhong, xiaoShu) = _buildMangZhongXiaoShu(lunar);

  final gansList = [yearGan, monthGan, dayGan, timeGan];
  final zhisList = [yearZhi, monthZhi, dayZhi, timeZhi];

  final mainStars = _mainStarsForFourPillars(yearGan, monthGan, timeGan, isFemale, td);
  final xingYun = _xingYunForZhis(zhisList, td);
  final ziZuo = _ziZuoForPillars(gansList, zhisList);
  final pillarEmpties = _emptiesForPillars(gansList, zhisList);
  final pillarNayins = _nayinsForPillars(
    gansList,
    zhisList,
    baseBaZiNaYin: lunar.getBaZiNaYin(),
  );
  final zhiCangGanWithShen = _zhiCangWithShenForZhis(zhisList, td);
  final shenSha = kShenShaUseBaziCore
      ? computeShenShaFourPillarsBaziCore(effectiveDt, isFemale: isFemale)
      : _computeShenSha(
          gans: gansList,
          zhis: zhisList,
          yearZhi: yearZhi,
          monthZhi: monthZhi,
          dayZhi: dayZhi,
          dayGan: me,
          yearNayin: lunar.getYearNaYin(),
        );

  final siLing = (_zhi5List[monthZhi]?.isNotEmpty ?? false) ? _zhi5List[monthZhi]!.first : '';
  final daYunWithShen = _daYunWithShenList(daYun, td);
  final daYunAgeRanges = _daYunAgeRangesFromDaYun(daYunList);

  final now = DateTime.now();
  final xuSui = now.year - solarDateForResult.year + 1;
  final currentDaYunIdx = xuSui >= daYunStartXuSui ? ((xuSui - daYunStartXuSui) ~/ 10).clamp(0, daYun.length - 1) : 0;
  final currentDaYun = daYun[currentDaYunIdx];

  // 小运（醉醒子法）：方向直接采用 Yun.isForward()，
  // 即与大运顺逆一致（阳男阴女顺推、阴男阳女逆推）
  final xiaoYunShun = yun.isForward();
  int xg = _gan.indexOf(timeGan);
  int xz = _zhi.indexOf(timeZhi);
  if (xiaoYunShun) { xg = (xg + 1) % 10; xz = (xz + 1) % 12; } else { xg = (xg - 1 + 10) % 10; xz = (xz - 1 + 12) % 12; }
  final xiaoYun = '${_gan[xg]}${_zhi[xz]}';

  final liuNianIdx = ((now.year - 4) % 60 + 60) % 60;
  final liuNian = '${_gan[liuNianIdx % 10]}${_zhi[liuNianIdx % 12]}';
  final liuYueZhiIdx = now.month % 12;
  final liuYueYinGan = (_gan.indexOf(liuNian[0]) * 2 + 2) % 10;
  final liuYue = '${_gan[(liuYueYinGan + liuYueZhiIdx - 2 + 10) % 10]}${_zhi[liuYueZhiIdx]}';

  final extGans = List<String>.from(gansList)..addAll([currentDaYun[0], liuNian[0], liuYue[0]]);
  final extZhis = List<String>.from(zhisList)..addAll([currentDaYun.substring(1), liuNian.substring(1), liuYue.substring(1)]);

  final detailMainStars = _mainStarsForExtPillars(extGans, extZhis, 2, isFemale, td);
  final detailGans = extGans;
  final detailZhis = extZhis;
  final detailXingYun = _xingYunForZhis(extZhis, td);
  final detailZiZuo = _ziZuoForPillars(extGans, extZhis);
  final detailPillarEmpties = _emptiesForPillars(extGans, extZhis);
  final detailPillarNayins = _nayinsForPillars(
    extGans,
    extZhis,
    baseBaZiNaYin: lunar.getBaZiNaYin(),
  );
  final detailZhiCangGanWithShen = _zhiCangWithShenForZhis(extZhis, td);

  final taiMingShenZhis = [taiYuan.substring(1), mingGong.substring(1), shenGong.substring(1)];
  final taiMingShenGans = [taiYuan[0], mingGong[0], shenGong[0]];
  final taiMingShenXingYun = _xingYunForZhis(taiMingShenZhis, td);
  final taiMingShenZiZuo = List.generate(3, (i) {
    final t = _kTenDeities[taiMingShenGans[i]];
    return _changShengFull(t != null ? t[taiMingShenZhis[i]] : null);
  });
  final taiMingShenEmpties = _emptiesForPillars(taiMingShenGans, taiMingShenZhis);
  final taiMingShenZhiCangGanWithShen = _zhiCangWithShenForZhis(taiMingShenZhis, td);

  return BaziResult(
    yearGan: yearGan,
    yearZhi: yearZhi,
    monthGan: monthGan,
    monthZhi: monthZhi,
    dayGan: dayGan,
    dayZhi: dayZhi,
    timeGan: timeGan,
    timeZhi: timeZhi,
    ganShens: ganShens,
    zhiShens: zhiShens,
    zhiCangGan: zhiCangGan,
    daYun: daYun,
    taiYuan: taiYuan,
    taiXi: taiXi,
    mingGong: mingGong,
    shenGong: shenGong,
    solarDate: solarDateForResult,
    lunarYearMonthDay: lunarStr,
    shengXiao: shengXiao,
    xingZuo: xingZuo,
    riKong: riKong,
    taiYuanNayin: taiYuanNayin,
    mingGongNayin: mingGongNayin,
    taiXiNayin: taiXiNayin,
    shenGongNayin: shenGongNayin,
    daYunStart: daYunStart,
    mangZhong: mangZhong,
    xiaoShu: xiaoShu,
    jiaoYun: jiaoYun,
    daYunStartXuSui: daYunStartXuSui,
    mainStars: mainStars,
    xingYun: xingYun,
    ziZuo: ziZuo,
    pillarEmpties: pillarEmpties,
    pillarNayins: pillarNayins,
    zhiCangGanWithShen: zhiCangGanWithShen,
    shenSha: shenSha,
    daYunWithShen: daYunWithShen,
    siLing: siLing,
    daYunAgeRanges: daYunAgeRanges,
    xiaoYun: xiaoYun,
    liuNian: liuNian,
    liuYue: liuYue,
    detailMainStars: detailMainStars,
    detailGans: detailGans,
    detailZhis: detailZhis,
    detailXingYun: detailXingYun,
    detailZiZuo: detailZiZuo,
    detailPillarEmpties: detailPillarEmpties,
    detailPillarNayins: detailPillarNayins,
    detailZhiCangGanWithShen: detailZhiCangGanWithShen,
    taiMingShenXingYun: taiMingShenXingYun,
    taiMingShenZiZuo: taiMingShenZiZuo,
    taiMingShenEmpties: taiMingShenEmpties,
    taiMingShenZhiCangGanWithShen: taiMingShenZhiCangGanWithShen,
  );
}

String _changShengFull(String? s) => s != null && s.isNotEmpty ? (_kChangShengFull[s] ?? s) : '';
String _shenFull(String? s) => s != null && s.isNotEmpty ? (_kShenFull[s] ?? s) : '';

/// 星座（按公历月日）：摩羯12/22起，水瓶1/20起，双鱼2/19起，白羊3/21起，金牛4/20起，双子5/21起，
/// 巨蟹6/22起，狮子7/23起，处女8/23起，天秤9/23起，天蝎10/24起，射手11/23起
String _westernZodiac(DateTime dt) {
  final m = dt.month;
  final d = dt.day;
  if (m == 1 && d >= 20 || m == 2 && d < 19) return '水瓶';
  if (m == 2 && d >= 19 || m == 3 && d < 21) return '双鱼';
  if (m == 3 && d >= 21 || m == 4 && d < 20) return '白羊';
  if (m == 4 && d >= 20 || m == 5 && d < 21) return '金牛';
  if (m == 5 && d >= 21 || m == 6 && d < 22) return '双子';
  if (m == 6 && d >= 22 || m == 7 && d < 23) return '巨蟹';
  if (m == 7 && d >= 23 || m == 8 && d < 23) return '狮子';
  if (m == 8 && d >= 23 || m == 9 && d < 23) return '处女';
  if (m == 9 && d >= 23 || m == 10 && d < 24) return '天秤';
  if (m == 10 && d >= 24 || m == 11 && d < 23) return '天蝎';
  if (m == 11 && d >= 23 || m == 12 && d < 22) return '射手';
  return '摩羯';
}

/// 农历月份中文（与 myresource 一致：负月表示闰月，如 -4 → 闰四）
String _lunarMonthCn(int m) {
  const names = ['', '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
  if (m >= 1 && m <= 12) return names[m];
  if (m <= -1 && m >= -12) return '闰${names[-m]}';
  return '$m';
}

String _lunarDayCn(int d) {
  const names = ['', '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
    '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
    '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'];
  return (d >= 1 && d <= 30) ? names[d] : '$d';
}

/// 将 lunar 的 Solar 格式化为 "yyyy-MM-dd HH:mm:ss"（芒种/小暑等节气时刻）
String _solarToDateTimeStr(Solar s) {
  final y = s.getYear();
  final m = s.getMonth();
  final d = s.getDay();
  final h = s.getHour();
  final min = s.getMinute();
  final sec = s.getSecond();
  return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')} '
      '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// 专业细盘「选中大运/流年/流月/流日/流时」时的 9 列详情（年柱/月柱/日柱/时柱/大运/流年/流月/流日/流时）
class DetailTableSelection {
  final List<String> mainStars;
  final List<String> gans;
  final List<String> zhis;
  final List<List<String>> zhiCangGanWithShen;
  final List<String> xingYun;
  final List<String> ziZuo;
  final List<String> empties;
  final List<String> nayins;

  const DetailTableSelection({
    required this.mainStars,
    required this.gans,
    required this.zhis,
    required this.zhiCangGanWithShen,
    required this.xingYun,
    required this.ziZuo,
    required this.empties,
    required this.nayins,
  });
}

/// 根据四柱 + 选中的大运/流年/流月/流日/流时干支，返回 9 列详情
DetailTableSelection buildDetailTableForSelection(
  BaziResult result,
  bool isFemale,
  String daYunGanZhi,
  String liuNianGanZhi,
  String liuYueGanZhi,
  String liuRiGanZhi,
  String liuShiGanZhi,
) {
  final dayGan = result.dayGan;
  final td = _kTenDeities[dayGan] ?? {};
  final extGans = [
    result.yearGan,
    result.monthGan,
    result.dayGan,
    result.timeGan,
    daYunGanZhi.isNotEmpty ? daYunGanZhi[0] : '',
    liuNianGanZhi.isNotEmpty ? liuNianGanZhi[0] : '',
    liuYueGanZhi.isNotEmpty ? liuYueGanZhi[0] : '',
    liuRiGanZhi.isNotEmpty ? liuRiGanZhi[0] : '',
    liuShiGanZhi.isNotEmpty ? liuShiGanZhi[0] : '',
  ];
  final extZhis = [
    result.yearZhi,
    result.monthZhi,
    result.dayZhi,
    result.timeZhi,
    daYunGanZhi.length > 1 ? daYunGanZhi.substring(1) : '',
    liuNianGanZhi.length > 1 ? liuNianGanZhi.substring(1) : '',
    liuYueGanZhi.length > 1 ? liuYueGanZhi.substring(1) : '',
    liuRiGanZhi.length > 1 ? liuRiGanZhi.substring(1) : '',
    liuShiGanZhi.length > 1 ? liuShiGanZhi.substring(1) : '',
  ];
  final mainStars = _mainStarsForExtPillars(extGans, extZhis, 2, isFemale, td);
  final xingYun = _xingYunForZhis(extZhis, td);
  final ziZuo = _ziZuoForPillars(extGans, extZhis);
  final empties = _emptiesForPillars(extGans, extZhis);
  final nayins = _nayinsForPillars(extGans, extZhis);
  final zhiCang = _zhiCangWithShenForZhis(extZhis, td);
  return DetailTableSelection(
    mainStars: mainStars,
    gans: extGans,
    zhis: extZhis,
    zhiCangGanWithShen: zhiCang,
    xingYun: xingYun,
    ziZuo: ziZuo,
    empties: empties,
    nayins: nayins,
  );
}

/// 从公历年份得到该年正月初一对应的干支序号（0–59），用于流年干支。以立春为岁首时需另算，此处按年柱规则。
int _yearToGanZhiIndex(int solarYear) {
  return ((solarYear - 4) % 60 + 60) % 60;
}

/// 流年干支（公历年份，六十甲子纪年）
String ganZhiForLiuNian(int solarYear) {
  final idx = _yearToGanZhiIndex(solarYear);
  return '${_gan[idx % 10]}${_zhi[idx % 12]}';
}

/// 流年等「他干」相对日干（日主）之十神简称，与四柱天干十神查表一致。
String shiShenJianForDayGanVsStem(String dayGan, String otherStem) {
  if (dayGan.isEmpty || otherStem.isEmpty) return '';
  final g = String.fromCharCode(otherStem.runes.first);
  final row = _kTenDeities[dayGan];
  return row?[g] ?? '';
}

/// 年柱干支转六十甲子序号（0–59）
int _ganZhiToIndex(String gan, String zhi) {
  final gi = _gan.indexOf(gan);
  final zi = _zhi.indexOf(zhi);
  if (gi < 0 || zi < 0) return 0;
  for (int i = 0; i < 60; i++) {
    if (i % 10 == gi && i % 12 == zi) return i;
  }
  return 0;
}

/// 命盘流年干支：按公历年份对应的六十甲子顺序计算（与顺逆无关），
/// 再按大运起止年份把各年划分到对应大运区间。
/// 保留旧参数签名，便于调用方兼容。
String liuNianGanZhiFromMingPan(int birthYear, int solarYear, String yearGan, String yearZhi, bool shun) {
  return ganZhiForLiuNian(solarYear);
}

/// 流年最下一行干支：小运 1-6 岁时以时柱为基准、每年逆推一柱（1岁=时柱逆推1，2岁=逆推2，…，6岁=逆推6）。
String liuNianBottomGanZhi(int age, String timeGan, String timeZhi) {
  if (age < 1) return timeGan + timeZhi;
  int idx = _ganZhiToIndex(timeGan, timeZhi);
  idx = (idx - age % 60 + 60) % 60;
  return '${_gan[idx % 10]}${_zhi[idx % 12]}';
}

/// 流月干支（公历年份 + 节气月 0–11，寅=0 卯=1 … 丑=11）
String ganZhiForLiuYue(int solarYear, int monthIndex) {
  final yearGanIdx = _yearToGanZhiIndex(solarYear) % 10;
  final yinGan = (yearGanIdx * 2 + 2) % 10;
  const zhiList = ['寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥', '子', '丑'];
  final gan = _gan[(yinGan + monthIndex) % 10];
  final zhi = zhiList[monthIndex % 12];
  return '$gan$zhi';
}

/// 五鼠遁：日干 → 子时天干
String _ziShiGanForDayGan(String dayGan) {
  const map = {'甲': '甲', '己': '甲', '乙': '丙', '庚': '丙', '丙': '戊', '辛': '戊', '丁': '庚', '壬': '庚', '戊': '壬', '癸': '壬'};
  return map[dayGan] ?? '甲';
}

/// 流时干支（日干 + 时支索引 0–11，子=0 … 亥=11）
String ganZhiForLiuShi(String dayGan, int shiIndex) {
  final ziGan = _ziShiGanForDayGan(dayGan);
  final ganIdx = (_gan.indexOf(ziGan) + shiIndex) % 10;
  const zhiList = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  return '${_gan[ganIdx]}${zhiList[shiIndex % 12]}';
}

/// 公历小时 → 流时地支索引（子=0），与 `DateUtil` 时辰划分一致：23 点与 0 点为子时，其余每 2 小时一时辰。
int hourToLiuShiZhiIndex(int hour) {
  if (hour == 23 || hour == 0) return 0;
  return ((hour + 1) ~/ 2).clamp(0, 11);
}

/// 流时地支索引对应的整点起点（0–23）：子=23、丑=1、寅=3 … 亥=21，与十二时辰每 2 小时一节一致。
int liuShiZhiStartHour(int shiIndex) => (shiIndex * 2 + 23) % 24;

/// 公历日期的日柱干支（用于流日）
String dayGanZhiFromDate(DateTime date) {
  final lunar = Lunar.fromDate(date);
  final ec = lunar.getEightChar();
  return '${ec.getDayGan()}${ec.getDayZhi()}';
}

// 干支留意算法：gan_zhi_liu_yi.dart

/// 大运/流年/流月单柱神煞（在命盘四柱 context 下计算该干支的神煞）
List<String> computeShenShaForExtraPillar(
  BaziResult result,
  String extraGan,
  String extraZhi, {
  String? yearNayin,
  bool isFemale = false,
  /// 使用 bazi_core 时：大运 / 流年 / 流月 对应柱位；为 null 时按大运
  PillarType? baziCoreExtraPillar,
}) {
  if (kShenShaUseBaziCore) {
    return computeShenShaExtraPillarBaziCore(
      result.solarDate,
      isFemale: isFemale,
      extraGan: extraGan,
      extraZhi: extraZhi,
      pillarType: baziCoreExtraPillar ?? PillarType.decade,
    );
  }

  final out = <String>{};
  final yearZhi = result.yearZhi;
  final monthZhi = result.monthZhi;
  final dayZhi = result.dayZhi;
  final dayGan = result.dayGan;
  final g = extraGan;
  final z = extraZhi;
  if (g.isEmpty || z.isEmpty) return [];

  for (final e in _monthShens.entries) {
    final val = e.value[monthZhi];
    if (val == null) continue;
    final key = e.key;
    if (key == '天医' || key == '血刃') { if (z == val) out.add(key); }
    else if (key == '天德贵人') { if (g == val || z == val) out.add(key); }
    else if (g == val) out.add(key);
  }
  for (final e in _dayShens.entries) {
    final val = e.value[dayZhi];
    if (val == null) continue;
    if (val.length == 1 && z == val) out.add(e.key);
    if (val.length >= 2 && val.contains(z)) out.add(e.key);
  }
  for (final e in _gShens.entries) {
    if (e.key == '福星贵人') continue;
    final val = e.value[dayGan];
    if (val == null || val.isEmpty) continue;
    if (val.length == 1 && z == val) out.add(e.key);
    if (val.length >= 2 && val.contains(z)) out.add(e.key);
  }
  final fuXingMap = _gShens['福星贵人']!;
  for (final gan in [result.yearGan, result.monthGan]) {
    final val = fuXingMap[gan];
    if (val != null && val.isNotEmpty && (val.length == 1 ? z == val : val.contains(z))) out.add('福星贵人');
  }
  final kongWangZhi = _kEmpties[dayGan + dayZhi] ?? '';
  if (kongWangZhi.length >= 2 && (z == kongWangZhi[0] || z == kongWangZhi[1])) out.add('空亡');
  final deXiuGans = _deXiuGanByMonth[monthZhi];
  if (deXiuGans != null && deXiuGans.contains(g)) out.add('德秀贵人');
  if (yearZhi == '戌' && z == '亥') out.add('天罗');
  if (yearZhi == '亥' && z == '戌') out.add('天罗');
  if (dayZhi == '戌' && z == '亥') out.add('天罗');
  if (dayZhi == '亥' && z == '戌') out.add('天罗');
  if (yearZhi == '辰' && z == '巳') out.add('地网');
  if (yearZhi == '巳' && z == '辰') out.add('地网');
  if (dayZhi == '辰' && z == '巳') out.add('地网');
  if (dayZhi == '巳' && z == '辰') out.add('地网');
  for (final e in _yearShens.entries) {
    final val = e.value[yearZhi];
    if (val == null || val.isEmpty) continue;
    if (val.length == 1 && z == val) out.add(e.key);
    if (val.length >= 2 && val.contains(z)) out.add(e.key);
  }
  for (final e in _dayShens.entries) {
    final val = e.value[yearZhi];
    if (val == null) continue;
    if (val.length == 1 && z == val) out.add(e.key);
    if (val.length >= 2 && val.contains(z)) out.add(e.key);
  }
  const ciGuanMap = {'甲': '庚寅', '乙': '辛卯', '丙': '乙巳', '丁': '戊午', '戊': '丁巳', '己': '庚午', '庚': '壬申', '辛': '癸酉', '壬': '癸亥', '癸': '壬戌'};
  if (ciGuanMap[dayGan] == g + z) out.add('词馆');
  const yuanChenYang = {'子': '未', '丑': '申', '寅': '酉', '卯': '戌', '辰': '亥', '巳': '子', '午': '丑', '未': '寅', '申': '卯', '酉': '辰', '戌': '巳', '亥': '午'};
  final yuanChenZhi = (yuanChenYang[yearZhi] ?? '');
  if (z == yuanChenZhi) out.add('元辰');
  final list = out.toList()..sort();
  return list;
}
