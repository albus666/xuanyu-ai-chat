import 'package:intl/intl.dart';

import '../../archive_relationship.dart';
import '../utils/bazi_result.dart';
import '../utils/wu_xing_liang_hua.dart';
import 'region.dart';

/// 八字排盘记录：用于命理档案本地存储与展示
class PaipanRecord {
  final String id;
  final DateTime createdAt;

  /// 命主姓名（用于命理档案主标题展示）
  final String displayName;
  final bool isSelf;
  final String relationship;
  final DateTime birthDateTime;
  final bool isFemale;
  final int calendarTypeIndex;
  final Region? birthPlace;

  /// 四柱摘要，如 "甲子 丙寅 庚午 辛巳"
  final String summary;

  /// 档案笔记沿用旧字段保存，兼容已经存在的记录。
  final String caseTitle;
  final String reasoningNotes;
  final String commentary;
  final DateTime? caseUpdatedAt;

  const PaipanRecord({
    required this.id,
    required this.createdAt,
    this.displayName = '',
    this.isSelf = false,
    this.relationship = ArchiveRelationship.other,
    required this.birthDateTime,
    required this.isFemale,
    required this.calendarTypeIndex,
    this.birthPlace,
    required this.summary,
    this.caseTitle = '',
    this.reasoningNotes = '',
    this.commentary = '',
    this.caseUpdatedAt,
  });

  bool get isCase =>
      caseTitle.trim().isNotEmpty ||
      reasoningNotes.trim().isNotEmpty ||
      commentary.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'displayName': displayName,
      'isSelf': isSelf,
      'relationship': relationship,
      'birthDateTime': birthDateTime.toIso8601String(),
      'isFemale': isFemale,
      'calendarTypeIndex': calendarTypeIndex,
      'birthPlace': birthPlace == null
          ? null
          : {
              'name': birthPlace!.name,
              'extPath': birthPlace!.extPath,
              'lng': birthPlace!.lng,
              'lat': birthPlace!.lat,
            },
      'summary': summary,
      'caseTitle': caseTitle,
      'reasoningNotes': reasoningNotes,
      'commentary': commentary,
      'caseUpdatedAt': caseUpdatedAt?.toIso8601String(),
    };
  }

  factory PaipanRecord.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? bp = json['birthPlace'] as Map<String, dynamic>?;
    Region? birthPlace;
    if (bp != null) {
      final extPath = bp['extPath'] as String?;
      final name = (bp['name'] as String?) ?? extPath ?? '';
      birthPlace = Region.placeholder(
        name: name.isNotEmpty ? name : (extPath ?? ''),
        extPath: extPath,
        lng: (bp['lng'] as num?)?.toDouble(),
        lat: (bp['lat'] as num?)?.toDouble(),
      );
    }
    final displayName = (json['displayName'] as String?)?.trim() ?? '';
    final isSelf = json['isSelf'] == true;
    final relationship = (json['relationship'] as String?)?.trim();
    return PaipanRecord(
      id: (json['id'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      displayName: displayName,
      isSelf: isSelf,
      relationship: relationship?.isNotEmpty == true
          ? relationship!
          : isSelf
              ? ArchiveRelationship.self
              : ArchiveRelationship.isReservedSelfName(displayName)
                  ? ArchiveRelationship.legacy
                  : ArchiveRelationship.other,
      birthDateTime:
          DateTime.tryParse((json['birthDateTime'] as String?) ?? '') ??
              DateTime.now(),
      isFemale: json['isFemale'] as bool? ?? false,
      calendarTypeIndex: (json['calendarTypeIndex'] as num?)?.toInt() ?? 0,
      birthPlace: birthPlace,
      summary: (json['summary'] as String?) ?? '',
      caseTitle: (json['caseTitle'] as String?) ?? '',
      reasoningNotes: (json['reasoningNotes'] as String?) ?? '',
      commentary: (json['commentary'] as String?) ?? '',
      caseUpdatedAt: DateTime.tryParse(
        (json['caseUpdatedAt'] as String?) ?? '',
      ),
    );
  }

  PaipanRecord copyWith({
    String? displayName,
    bool? isSelf,
    String? relationship,
    String? caseTitle,
    String? reasoningNotes,
    String? commentary,
    DateTime? caseUpdatedAt,
  }) {
    return PaipanRecord(
      id: id,
      createdAt: createdAt,
      displayName: displayName ?? this.displayName,
      isSelf: isSelf ?? this.isSelf,
      relationship: relationship ?? this.relationship,
      birthDateTime: birthDateTime,
      isFemale: isFemale,
      calendarTypeIndex: calendarTypeIndex,
      birthPlace: birthPlace,
      summary: summary,
      caseTitle: caseTitle ?? this.caseTitle,
      reasoningNotes: reasoningNotes ?? this.reasoningNotes,
      commentary: commentary ?? this.commentary,
      caseUpdatedAt: caseUpdatedAt ?? this.caseUpdatedAt,
    );
  }

  bool get isLegacySelf =>
      !isSelf && relationship == ArchiveRelationship.legacy;

  String get relationshipLabel => ArchiveRelationship.label(
        isSelf ? ArchiveRelationship.self : relationship,
      );

  static const _calendarNames = ['公历', '农历', '四柱'];

  String get calendarTypeName {
    if (calendarTypeIndex >= 0 && calendarTypeIndex < _calendarNames.length) {
      return _calendarNames[calendarTypeIndex];
    }
    return '公历';
  }

  String get birthPlaceDisplay {
    if (birthPlace == null) return '未填写';
    if (birthPlace!.extPath.isNotEmpty) {
      return birthPlace!.extPath.replaceAll(' ', ' / ');
    }
    if (birthPlace!.name.isNotEmpty) {
      return birthPlace!.name.replaceAll(' ', ' / ');
    }
    return '未填写';
  }

  /// 供 AI 名师等接口附带：命主信息、五行量化、基本命盘、干支留意，以及大运全表与近年流年干支（含流年天干十神）。
  String toAiContextBlock() {
    final result = computeBaziResult(birthDateTime, isFemale: isFemale);
    final gender = isFemale ? '女（坤造）' : '男（乾造）';
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(birthDateTime);
    String v(String s) => s.isEmpty ? '—' : s;

    final buf = StringBuffer()
      ..writeln('【命理档案】')
      ..writeln('命主：${displayName.trim().isEmpty ? '未命名' : displayName.trim()}')
      ..writeln('四柱：${result.fourPillarsStr}')
      ..writeln('性别：$gender')
      ..writeln('历法：$calendarTypeName')
      ..writeln('公历出生：$dateStr')
      ..writeln('农历：${result.lunarYearMonthDay} ${result.timeZhi}时')
      ..writeln('出生地：$birthPlaceDisplay')
      ..writeln()
      ..writeln('【命主信息】')
      ..writeln(
          '生肖：${v(result.shengXiao)}　星座：${v(result.xingZuo)}　日空：${v(result.riKong)}');

    final taiYuanStr = result.taiYuanNayin.isEmpty
        ? result.taiYuan
        : '${result.taiYuan}（${result.taiYuanNayin}）';
    final taiXiStr = result.taiXiNayin.isEmpty
        ? result.taiXi
        : '${result.taiXi}（${result.taiXiNayin}）';
    final mingGongStr = result.mingGongNayin.isEmpty
        ? result.mingGong
        : '${result.mingGong}（${result.mingGongNayin}）';
    final shenGongStr = result.shenGongNayin.isEmpty
        ? result.shenGong
        : '${result.shenGong}（${result.shenGongNayin}）';
    buf
      ..writeln('胎元：$taiYuanStr')
      ..writeln('胎息：$taiXiStr')
      ..writeln('命宫：$mingGongStr')
      ..writeln('身宫：$shenGongStr')
      ..writeln('芒种：${v(result.mangZhong)}　小暑：${v(result.xiaoShu)}')
      ..writeln('大运：${v(result.daYunStart)}')
      ..writeln('交运：${v(result.jiaoYun)}')
      ..writeln();

    final wx = computeWuXingLiangHua(result);
    final sq = analyzeWuXingShenQiangYongShen(wx, result.dayGan, result);
    const jinOrderLabels = ['金', '木', '水', '火', '土'];
    final jm = wx.byJinMuShuiHuoTu;
    buf
      ..writeln('【五行量化】')
      ..writeln(jinOrderLabels
          .asMap()
          .entries
          .map((e) => '${e.value}${jm[e.key].toStringAsFixed(3)}')
          .join('　'))
      ..writeln(
        '同类（印比）${wx.tongLeiForDayGan(result.dayGan).toStringAsFixed(3)}　异类${wx.yiLeiForDayGan(result.dayGan).toStringAsFixed(3)}',
      )
      ..writeln(
          '旺衰得分：${sq.wangShuaiDeFen.toStringAsFixed(3)}（同类−异类）【${sq.shenQiangRuo}】')
      ..writeln('喜用神：${sq.xiYongShen.isEmpty ? '—' : sq.xiYongShen}');
    if (sq.queWuXing.isNotEmpty) {
      buf.writeln('五行缺：${sq.queWuXing.join('、')}');
    }
    if (sq.yongShenHint.isNotEmpty) {
      buf.writeln('说明：${sq.yongShenHint}');
    }
    buf.writeln();

    void row4(String label, List<String> vals) {
      final vs =
          List<String>.generate(4, (i) => i < vals.length ? vals[i] : '');
      buf.writeln('$label：年${vs[0]}　月${vs[1]}　日${vs[2]}　时${vs[3]}');
    }

    const pillarLabels = ['年柱', '月柱', '日柱', '时柱'];
    buf.writeln('【基本命盘】');
    row4('主星', result.mainStars);
    row4('天干', result.gans);
    row4('地支', result.zhis);
    for (var i = 0; i < 4; i++) {
      final cg = result.zhiCangGanWithShen[i];
      buf.writeln('藏干（${pillarLabels[i]}）：${cg.isEmpty ? '—' : cg.join('、')}');
    }
    row4('星运', result.xingYun);
    row4('自坐', result.ziZuo);
    row4('空亡', result.pillarEmpties);
    row4('纳音', result.pillarNayins);
    for (var i = 0; i < 4; i++) {
      final sh = result.shenSha[i];
      buf.writeln('神煞（${pillarLabels[i]}）：${sh.isEmpty ? '—' : sh.join('、')}');
    }

    final (ganLine, zhiLine) = buildGanZhiLiuYi(
        List<String>.from(result.gans), List<String>.from(result.zhis));
    buf
      ..writeln()
      ..writeln('【干支留意】（四柱）');
    if (ganLine.isEmpty && zhiLine.isEmpty) {
      buf.writeln('—');
    } else {
      if (ganLine.isNotEmpty) buf.writeln(ganLine);
      if (zhiLine.isNotEmpty) buf.writeln(zhiLine);
    }

    final birthYear = result.solarDate.year;
    buf
      ..writeln()
      ..writeln('【大运排表】')
      ..writeln(
        '起运虚岁：${result.daYunStartXuSui}；大运共 ${result.daYun.length} 步（每步约10年）。下一步小运干支参考：${result.xiaoYun.isEmpty ? '—' : result.xiaoYun}',
      );
    final nDaYun = result.daYun.length;
    for (var i = 0; i < nDaYun; i++) {
      final ageLabel =
          i < result.daYunAgeRanges.length ? result.daYunAgeRanges[i] : '—';
      final gz = result.daYun[i];
      final ss =
          i < result.daYunWithShen.length ? result.daYunWithShen[i] : '—';
      final yStart = birthYear + (result.daYunStartXuSui - 1) + i * 10;
      final yEnd = yStart + 9;
      buf.writeln('第${i + 1}步：起始$ageLabel · 干支 $gz · $ss · 公历年约 $yStart–$yEnd');
    }

    final now = DateTime.now();
    final xuSuiNow = now.year - birthYear + 1;
    var currentDaYun = '';
    var currentDaYunShen = '';
    var currentDaYunIndex = -1;
    if (xuSuiNow < result.daYunStartXuSui) {
      buf.writeln('当前（${now.year}年）虚岁约$xuSuiNow：尚未入大运（童限/小运，以排盘小运参考为准）。');
    } else {
      final idx = ((xuSuiNow - result.daYunStartXuSui) ~/ 10)
          .clamp(0, result.daYun.length - 1);
      final curSs =
          idx < result.daYunWithShen.length ? result.daYunWithShen[idx] : '';
      currentDaYun = result.daYun[idx];
      currentDaYunShen = curSs;
      currentDaYunIndex = idx;
      buf.writeln(
        '当前（${now.year}年）虚岁约$xuSuiNow：处第${idx + 1}步大运「${result.daYun[idx]}」${curSs.isNotEmpty ? '（$curSs）' : ''}',
      );
    }

    buf
      ..writeln()
      ..writeln('【流年干支】（公历六十甲子，与排盘一致；流年天干十神相对日主${result.dayGan}）');
    const pastYears = 8;
    const futureYears = 15;
    for (var y = now.year - pastYears; y <= now.year + futureYears; y++) {
      final gz = ganZhiForLiuNian(y);
      final stem = gz.isNotEmpty ? String.fromCharCode(gz.runes.first) : '';
      final ss = shiShenJianForDayGanVsStem(result.dayGan, stem);
      final mark = y == now.year ? '（今年）' : '';
      buf.writeln('$y年：$gz　流年天干十神：${ss.isEmpty ? '—' : ss}$mark');
    }

    final liuNianNow = ganZhiForLiuNian(now.year);
    final liuYueNow = result.liuYue.isNotEmpty
        ? result.liuYue
        : ganZhiForLiuYue(now.year, (now.month - 1) % 12);
    final liuRiNow = dayGanZhiFromDate(now);
    final liuShiNow = ganZhiForLiuShi(
        liuRiNow.isNotEmpty ? liuRiNow[0] : result.dayGan,
        hourToLiuShiZhiIndex(now.hour));
    final currentDaYunGz = currentDaYun.isNotEmpty
        ? currentDaYun
        : (result.daYun.isNotEmpty ? result.daYun.first : '');
    final detail = buildDetailTableForSelection(
      result,
      isFemale,
      currentDaYunGz,
      liuNianNow,
      liuYueNow,
      liuRiNow,
      liuShiNow,
    );
    buf
      ..writeln()
      ..writeln('【详细排盘原文（当前时空点）】')
      ..writeln('数据来源：本地八字排盘引擎实时计算（非 AI 生成）')
      ..writeln(
        '当前定位：${now.year}年${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      )
      ..writeln(
        '当前大运：${currentDaYunIndex >= 0 ? "第${currentDaYunIndex + 1}步 " : ""}${currentDaYunGz.isEmpty ? "—" : currentDaYunGz}'
        '${currentDaYunShen.isNotEmpty ? "（$currentDaYunShen）" : ""}',
      )
      ..writeln('当前流年：${liuNianNow.isEmpty ? '—' : liuNianNow}')
      ..writeln('当前流月：${liuYueNow.isEmpty ? '—' : liuYueNow}')
      ..writeln('当前流日：${liuRiNow.isEmpty ? '—' : liuRiNow}')
      ..writeln('当前流时：${liuShiNow.isEmpty ? '—' : liuShiNow}');

    void row9(String label, List<String> vals) {
      final vs =
          List<String>.generate(9, (i) => i < vals.length ? vals[i] : '');
      buf.writeln(
        '$label：年${vs[0]}　月${vs[1]}　日${vs[2]}　时${vs[3]}　大运${vs[4]}　流年${vs[5]}　流月${vs[6]}　流日${vs[7]}　流时${vs[8]}',
      );
    }

    row9('主星', detail.mainStars);
    row9('天干', detail.gans);
    row9('地支', detail.zhis);
    row9('星运', detail.xingYun);
    row9('自坐', detail.ziZuo);
    row9('空亡', detail.empties);
    row9('纳音', detail.nayins);
    const detailLabels = ['年柱', '月柱', '日柱', '时柱', '大运', '流年', '流月', '流日', '流时'];
    for (var i = 0; i < detailLabels.length; i++) {
      final cg = i < detail.zhiCangGanWithShen.length
          ? detail.zhiCangGanWithShen[i]
          : const <String>[];
      buf.writeln('藏干（${detailLabels[i]}）：${cg.isEmpty ? '—' : cg.join('、')}');
    }

    final (ganLineExt, zhiLineExt) = buildGanZhiLiuYi(
      List<String>.from(detail.gans),
      List<String>.from(detail.zhis),
    );
    buf
      ..writeln()
      ..writeln('【干支留意】（原局+大运+流年+流月+流日+流时）');
    if (ganLineExt.isEmpty && zhiLineExt.isEmpty) {
      buf.writeln('—');
    } else {
      if (ganLineExt.isNotEmpty) buf.writeln(ganLineExt);
      if (zhiLineExt.isNotEmpty) buf.writeln(zhiLineExt);
    }

    if (isCase) {
      buf
        ..writeln()
        ..writeln('【档案笔记】')
        ..writeln(
            '笔记标题：${caseTitle.trim().isEmpty ? '未命名笔记' : caseTitle.trim()}');
      if (reasoningNotes.trim().isNotEmpty) {
        buf
          ..writeln('看盘判断：')
          ..writeln(reasoningNotes.trim());
      }
      if (commentary.trim().isNotEmpty) {
        buf
          ..writeln('现实反馈：')
          ..writeln(commentary.trim());
      }
    }

    return buf.toString().trimRight();
  }
}
