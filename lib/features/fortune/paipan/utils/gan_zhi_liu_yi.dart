import 'package:bazi_core/bazi_core.dart';

/// 干支留意：由平行 [gans]/[zhis]（如四柱+大运+流年+流月）生成说明文案。
///
/// 底层使用 [bazi_core] 的 [BaziInteractionCalculator]（天干五合/四冲/同性克，
/// 地支六合、三合/半合/拱合、三会、六冲、害、破、刑、暗合、相等），再格式化为简短中文。

const _kGanOrder = '甲乙丙丁戊己庚辛壬癸';
const _kZhiOrder = '子丑寅卯辰巳午未申酉戌亥';

int _ganIdx(String c) {
  final i = _kGanOrder.indexOf(c);
  return i < 0 ? 99 : i;
}

int _zhiIdx(String c) {
  final i = _kZhiOrder.indexOf(c);
  return i < 0 ? 99 : i;
}

String _tianGanChar(TianGan g) => _kGanOrder[g.index % 10];

String _diZhiChar(DiZhi z) => _kZhiOrder[z.index % 12];

String _wxCn(WuXing? w) {
  if (w == null) return '';
  return switch (w) {
    WuXing.wood => '木',
    WuXing.fire => '火',
    WuXing.earth => '土',
    WuXing.metal => '金',
    WuXing.water => '水',
  };
}

/// 与 [paipanBuildGanZhiLiuYiContent] 中拼接顺序一致：年、月、日、时、大运、流年、流月…
const List<PillarType> _pillarByColIndex = [
  PillarType.year,
  PillarType.month,
  PillarType.day,
  PillarType.hour,
  PillarType.decade,
  PillarType.flowYear,
  PillarType.flowMonth,
  PillarType.flowDay,
  PillarType.flowHour,
];

PillarType _pillarForIndex(int i) =>
    i < _pillarByColIndex.length ? _pillarByColIndex[i] : PillarType.flowHour;

List<InteractionNode<TianGan>> _buildStemPool(List<String> gans) {
  final out = <InteractionNode<TianGan>>[];
  for (var i = 0; i < gans.length; i++) {
    final g = gans[i].trim();
    if (g.length != 1) continue;
    try {
      out.add(InteractionNode(_pillarForIndex(i), TianGan.fromName(g)));
    } catch (_) {}
  }
  return out;
}

List<InteractionNode<DiZhi>> _buildBranchPool(List<String> zhis) {
  final out = <InteractionNode<DiZhi>>[];
  for (var i = 0; i < zhis.length; i++) {
    final z = zhis[i].trim();
    if (z.length != 1) continue;
    try {
      out.add(InteractionNode(_pillarForIndex(i), DiZhi.fromName(z)));
    } catch (_) {}
  }
  return out;
}

int _stemTypeSort(BaziInteraction t) => switch (t) {
      BaziInteraction.stemCombination => 0,
      BaziInteraction.stemClash => 1,
      BaziInteraction.stemRestraint => 2,
      _ => 99,
    };

int _branchTypeSort(BaziInteraction t) => switch (t) {
      BaziInteraction.branchClash => 0,
      BaziInteraction.branchCombination => 1,
      BaziInteraction.branchTripleCombination => 2,
      BaziInteraction.branchTripleDirection => 3,
      BaziInteraction.branchHalfCombination => 4,
      BaziInteraction.branchArchingCombination => 5,
      BaziInteraction.branchTriplePunishment => 6,
      BaziInteraction.branchPunishment => 7,
      BaziInteraction.branchSelfPunishment => 8,
      BaziInteraction.branchHarm => 9,
      BaziInteraction.branchDestruction => 10,
      BaziInteraction.branchHiddenCombination => 11,
      BaziInteraction.branchSeverance => 12,
      _ => 99,
    };

String _sortedGanToken(InteractionResult r) {
  final set = <String>{};
  for (final n in r.nodes) {
    final v = n.value;
    if (v is TianGan) set.add(_tianGanChar(v));
  }
  final list = set.toList()..sort((a, b) => _ganIdx(a).compareTo(_ganIdx(b)));
  return list.join('');
}

/// 地支展示用字串：除 [自刑]（午午、辰辰）外，对多柱重复支去重，避免「巳巳酉·半合」类读法。
String _sortedZhiToken(InteractionResult r) {
  final list = <String>[];
  for (final n in r.nodes) {
    final v = n.value;
    if (v is DiZhi) list.add(_diZhiChar(v));
  }
  if (list.isEmpty) return '';
  if (r.type == BaziInteraction.branchSelfPunishment) {
    if (list.length < 2) return '';
    // 自刑（辰午酉亥）典籍与界面通常写作「午午·自刑」；库会把四柱里所有午都放进 nodes，不宜写成午×4
    final z = list.first;
    if (list.every((c) => c == z)) {
      return '$z$z';
    }
    final u = list.toSet().toList()..sort((a, b) => _zhiIdx(a).compareTo(_zhiIdx(b)));
    return u.join('');
  }
  final unique = list.toSet().toList()..sort((a, b) => _zhiIdx(a).compareTo(_zhiIdx(b)));
  return unique.join('');
}

String? _formatStemLine(InteractionResult r) {
  final token = _sortedGanToken(r);
  if (token.isEmpty) return null;
  // 天干展示仅保留双字关系（如「丙壬·冲」「丁壬·合木」），过滤「丙戊壬·克」这类三字串。
  if (token.length != 2) return null;
  return switch (r.type) {
    BaziInteraction.stemCombination => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·合$wx' : '$token·合';
      }(),
    BaziInteraction.stemClash => '$token·冲',
    BaziInteraction.stemRestraint => '$token·克',
    _ => null,
  };
}

String? _formatBranchLine(InteractionResult r) {
  final token = _sortedZhiToken(r);
  if (token.isEmpty) return null;
  return switch (r.type) {
    BaziInteraction.branchClash => '$token·冲',
    BaziInteraction.branchCombination => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·合$wx' : '$token·合';
      }(),
    BaziInteraction.branchTripleCombination => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·三合$wx' : '$token·三合';
      }(),
    BaziInteraction.branchTripleDirection => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·三会$wx' : '$token·三会';
      }(),
    BaziInteraction.branchHalfCombination => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·半合$wx' : '$token·半合';
      }(),
    BaziInteraction.branchArchingCombination => () {
        final wx = _wxCn(r.combinedWuXing);
        return wx.isNotEmpty ? '$token·拱合$wx' : '$token·拱合';
      }(),
    BaziInteraction.branchTriplePunishment => '$token·三刑',
    BaziInteraction.branchPunishment => '$token·刑',
    BaziInteraction.branchSelfPunishment => '$token·自刑',
    BaziInteraction.branchHarm => '$token·害',
    BaziInteraction.branchDestruction => '$token·破',
    BaziInteraction.branchHiddenCombination => '$token·暗合',
    BaziInteraction.branchSeverance => '$token·绝',
    _ => null,
  };
}

(String ganLine, String zhiLine) buildGanZhiLiuYi(List<String> gans, List<String> zhis) {
  final n = gans.length;
  if (n != zhis.length || n < 4) return ('', '');

  final stemPool = _buildStemPool(gans);
  final branchPool = _buildBranchPool(zhis);

  final stemResults = BaziInteractionCalculator.calculateStemInteractions(stemPool);
  final branchResults = BaziInteractionCalculator.calculateBranchInteractions(branchPool);

  stemResults.sort((a, b) {
    final c = _stemTypeSort(a.type).compareTo(_stemTypeSort(b.type));
    if (c != 0) return c;
    final sa = _formatStemLine(a) ?? '';
    final sb = _formatStemLine(b) ?? '';
    return sa.compareTo(sb);
  });

  branchResults.sort((a, b) {
    final c = _branchTypeSort(a.type).compareTo(_branchTypeSort(b.type));
    if (c != 0) return c;
    final sa = _formatBranchLine(a) ?? '';
    final sb = _formatBranchLine(b) ?? '';
    return sa.compareTo(sb);
  });

  /// 四冲与同性克在乙辛、壬丙等上会同时成立；命理展示通常「有冲不再写克」。
  final stemClashTokens = <String>{};
  for (final r in stemResults) {
    if (r.type == BaziInteraction.stemClash) {
      stemClashTokens.add(_sortedGanToken(r));
    }
  }

  final ganItems = <String>[];
  final ganSeen = <String>{};
  for (final r in stemResults) {
    if (r.type == BaziInteraction.stemRestraint) {
      if (stemClashTokens.contains(_sortedGanToken(r))) continue;
    }
    final line = _formatStemLine(r);
    if (line != null && ganSeen.add(line)) ganItems.add(line);
  }

  final zhiItems = <String>[];
  final zhiSeen = <String>{};
  for (final r in branchResults) {
    final line = _formatBranchLine(r);
    if (line != null && zhiSeen.add(line)) zhiItems.add(line);
  }

  // 条目之间用全角空一格，约为普通半角空格的 2 倍，避免一行里过挤
  const sep = '\u3000';
  final ganLine = ganItems.isEmpty ? '' : '天干: ${ganItems.join(sep)}';
  final zhiLine = zhiItems.isEmpty ? '' : '地支: ${zhiItems.join(sep)}';
  return (ganLine, zhiLine);
}
