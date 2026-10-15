/// 排盘结果页共享：颜色、十神、五行、扁平模块、Tab 指示器等（统一使用 App 国风主题）
library;

import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import '../../../../core/theme/app_colors.dart';
import '../utils/bazi_result.dart';

// ——— 与 App 主题一致（朱砂红、玄采、宣纸色） ———
const Color paipanPurple = AppColors.primary;
const Color paipanGrey = AppColors.textSecondary;
const Color paipanLightBg = AppColors.background;
const Color paipanTableBorderColor = AppColors.divider;
const Color paipanTimelineSelectedBg = AppColors.primaryLight;
const Color paipanSectionHeaderBg = AppColors.cardBackground;

const Map<String, Color> paipanShishenColors = {
  '比肩': Color(0xFF2D8CF0), '劫财': Color(0xFF5B9BD5), '食神': Color(0xFF19BE6B), '伤官': Color(0xFF2DD1A0),
  '偏财': Color(0xFFED4014), '正财': Color(0xFFF2635B), '七杀': Color(0xFF8B5E3C), '正官': Color(0xFFA0522D),
  '偏印': Color(0xFFFACC14), '正印': Color(0xFFF5D547),
};

String paipanShenShort(String? full) {
  if (full == null || full.isEmpty) return '';
  const m = {
    '比肩': '比', '劫财': '劫', '食神': '食', '伤官': '伤',
    '偏财': '偏', '正财': '财', '七杀': '杀', '正官': '官', '偏印': '枭', '正印': '印',
  };
  return m[full] ?? full;
}

Color paipanShishenColor(String? shen) =>
    shen != null && shen.isNotEmpty ? (paipanShishenColors[shen] ?? paipanGrey) : paipanGrey;

// ——— 五行颜色 ———
const Color paipanColorWood = Color(0xFF2E7D32);
const Color paipanColorFire = Color(0xFFC62828);
const Color paipanColorEarth = Color(0xFF5D4037);
const Color paipanColorMetal = Color(0xFFD4A017);
const Color paipanColorWater = Color(0xFF1565C0);

int? paipanGanWuXing(String g) {
  const map = {'甲': 0, '乙': 0, '丙': 1, '丁': 1, '戊': 2, '己': 2, '庚': 3, '辛': 3, '壬': 4, '癸': 4};
  return map[g];
}

int? paipanZhiWuXing(String z) {
  const map = {'寅': 0, '卯': 0, '巳': 1, '午': 1, '辰': 2, '戌': 2, '丑': 2, '未': 2, '申': 3, '酉': 3, '亥': 4, '子': 4};
  return map[z];
}

Color paipanWuXingColor(int? wx) {
  if (wx == null) return paipanGrey;
  const colors = [paipanColorWood, paipanColorFire, paipanColorEarth, paipanColorMetal, paipanColorWater];
  return colors[wx];
}

Color paipanGanColor(String g) => paipanWuXingColor(paipanGanWuXing(g));
Color paipanZhiColor(String z) => paipanWuXingColor(paipanZhiWuXing(z));

Widget paipanColoredZhiCangText(String text, double fontSize) {
  const gans = '甲乙丙丁戊己庚辛壬癸';
  final spans = <TextSpan>[];
  final lines = text.split('\n');
  for (int L = 0; L < lines.length; L++) {
    final line = lines[L];
      if (line.isEmpty) {
        if (L < lines.length - 1) spans.add(TextSpan(text: '\n', style: TextStyle(fontSize: fontSize, color: AppColors.textPrimary)));
        continue;
      }
    if (line.isNotEmpty && gans.contains(line[0])) {
      final gan = line[0];
      final color = paipanGanColor(gan);
      spans.add(TextSpan(text: gan, style: TextStyle(fontSize: fontSize, color: color)));
      if (line.length > 1) spans.add(TextSpan(text: line.substring(1), style: TextStyle(fontSize: fontSize, color: color)));
    } else {
      spans.add(TextSpan(text: line, style: TextStyle(fontSize: fontSize, color: AppColors.textPrimary)));
    }
    if (L < lines.length - 1) spans.add(TextSpan(text: '\n', style: TextStyle(fontSize: fontSize, color: AppColors.textPrimary)));
  }
  return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
}

// ——— 默认大运/流年/流月、干支留意 ———
(String, String, String) paipanDefaultDaYunLiuNianLiuYue(BaziResult result, bool isFemale) {
  final startXuSui = result.daYunStartXuSui;
  final birthYear = result.solarDate.year;
  final now = DateTime.now();
  final xuSui = now.year - birthYear + 1;
  int idx = 0;
  for (int i = 0; i < result.daYun.length; i++) {
    if (xuSui >= startXuSui + i * 10 && xuSui < startXuSui + i * 10 + 10) { idx = i; break; }
  }
  final start = birthYear + (startXuSui - 1) + idx * 10;
  final liuNianList = List.generate(10, (i) => start + i);
  final selYear = liuNianList.contains(now.year) ? now.year : (liuNianList.isNotEmpty ? liuNianList.first : null);
  int yueIdx = 0;
  if (selYear != null) {
    final m = now.month, d = now.day;
    if (m < 2 || (m == 2 && d < 4)) {
      yueIdx = 11;
    } else if (m < 3 || (m == 3 && d < 5)) yueIdx = 0;
    else if (m < 4 || (m == 4 && d < 5)) yueIdx = 1;
    else if (m < 5 || (m == 5 && d < 5)) yueIdx = 2;
    else if (m < 6 || (m == 6 && d < 6)) yueIdx = 3;
    else if (m < 7 || (m == 7 && d < 7)) yueIdx = 4;
    else if (m < 8 || (m == 8 && d < 7)) yueIdx = 5;
    else if (m < 9 || (m == 9 && d < 7)) yueIdx = 6;
    else if (m < 10 || (m == 10 && d < 8)) yueIdx = 7;
    else if (m < 11 || (m == 11 && d < 7)) yueIdx = 8;
    else if (m < 12 || (m == 12 && d < 7)) yueIdx = 9;
    else if (d < 22) yueIdx = 10;
    else yueIdx = 11;
  }
  final daYunGanZhi = result.daYun[idx];
  final yearSeq = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'].indexOf(result.yearGan);
  final shun = (isFemale && (yearSeq % 2 == 1)) || (!isFemale && (yearSeq % 2 == 0));
  final liuNianGanZhi = selYear != null ? liuNianGanZhiFromMingPan(birthYear, selYear, result.yearGan, result.yearZhi, shun) : '';
  final liuYueGanZhi = selYear != null ? ganZhiForLiuYue(selYear, yueIdx) : '';
  return (daYunGanZhi, liuNianGanZhi, liuYueGanZhi);
}

List<Widget> paipanBuildGanZhiLiuYiContent(BaziResult result, bool isFemale, String daYunGanZhi, String liuNianGanZhi, String liuYueGanZhi) {
  final gans7 = List<String>.from(result.gans);
  final zhis7 = List<String>.from(result.zhis);
  if (daYunGanZhi.length >= 2) { gans7.add(daYunGanZhi[0]); zhis7.add(daYunGanZhi.substring(1)); }
  if (liuNianGanZhi.length >= 2) { gans7.add(liuNianGanZhi[0]); zhis7.add(liuNianGanZhi.substring(1)); }
  if (liuYueGanZhi.length >= 2) { gans7.add(liuYueGanZhi[0]); zhis7.add(liuYueGanZhi.substring(1)); }
  final (ganLine, zhiLine) = buildGanZhiLiuYi(gans7, zhis7);
  return [
    if (ganLine.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(ganLine, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
    if (zhiLine.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(zhiLine, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
    if (ganLine.isEmpty && zhiLine.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('—', style: TextStyle(color: AppColors.textPrimary, fontSize: 13))),
  ];
}

// ——— 扁平模块 ———
Widget paipanFlatSection(String title, List<Widget> children) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: double.infinity,
        height: 50,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFFF8F7F4),
        child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.black87)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
    ],
  );
}

// ——— 时间轴干支展示 ———
const double paipanKTimelinePillarFontSize = 14;
const double paipanKTimelinePillarShenFontSize = 10;
const double paipanKTimelineBlockWidth = 90;
const double paipanKTimelineBlockSpacing = 12;
const double paipanKTimelineBlockRadius = 12;

Widget paipanTimelinePillarText(String gz, String? ganShen, String? zhiShen, {double fontSize = 13}) {
  if (gz.length < 2) return Text(gz, style: TextStyle(fontSize: fontSize, color: paipanGrey));
  final g = gz[0];
  final z = gz.substring(1);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: g, style: TextStyle(fontSize: fontSize, color: paipanGanColor(g))),
        TextSpan(text: paipanShenShort(ganShen), style: TextStyle(fontSize: fontSize - 1, color: AppColors.textPrimary)),
        TextSpan(text: z, style: TextStyle(fontSize: fontSize, color: paipanZhiColor(z))),
        TextSpan(text: paipanShenShort(zhiShen), style: TextStyle(fontSize: fontSize - 1, color: AppColors.textPrimary)),
      ],
    ),
  );
}

Widget paipanTimelinePillarTextTwoLines(String gz, String? ganShen, String? zhiShen, {double fontSize = 12, double? shenFontSize}) {
  if (gz.length < 2) return Text(gz, style: TextStyle(fontSize: fontSize, color: paipanGrey));
  final g = gz[0];
  final z = gz.substring(1);
  final shenSize = shenFontSize ?? fontSize - 1;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(TextSpan(
        children: [
          TextSpan(text: g, style: TextStyle(fontSize: fontSize, color: paipanGanColor(g))),
          TextSpan(text: paipanShenShort(ganShen), style: TextStyle(fontSize: shenSize, color: AppColors.textPrimary)),
        ],
      )),
      const SizedBox(height: 2),
      Text.rich(TextSpan(
        children: [
          TextSpan(text: z, style: TextStyle(fontSize: fontSize, color: paipanZhiColor(z))),
          TextSpan(text: paipanShenShort(zhiShen), style: TextStyle(fontSize: shenSize, color: AppColors.textPrimary)),
        ],
      )),
    ],
  );
}

Widget paipanBuildTimelineBlock({
  required String topText,
  required Widget bottom,
  bool isSelected = false,
  double width = paipanKTimelineBlockWidth,
  VoidCallback? onTap,
}) {
  final content = Container(
    width: width,
    margin: const EdgeInsets.only(right: paipanKTimelineBlockSpacing),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: isSelected ? paipanTimelineSelectedBg : Colors.transparent,
      borderRadius: BorderRadius.circular(paipanKTimelineBlockRadius),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (topText.isNotEmpty) Text(topText, style: const TextStyle(fontSize: 11, color: paipanGrey)),
        if (topText.isNotEmpty) const SizedBox(height: 4),
        DefaultTextStyle(style: const TextStyle(fontSize: 14, color: AppColors.textPrimary), child: bottom),
      ],
    ),
  );
  if (onTap != null) return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
  return content;
}

// ——— Tab 下划线、Sliver 委托 ———
class PaipanCenterWidthUnderlineIndicator extends Decoration {
  final BorderSide borderSide;
  final double width;

  const PaipanCenterWidthUnderlineIndicator({required this.borderSide, this.width = 64});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PaipanCenterWidthUnderlinePainter(borderSide: borderSide, width: width);
}

class _PaipanCenterWidthUnderlinePainter extends BoxPainter {
  final BorderSide borderSide;
  final double width;

  _PaipanCenterWidthUnderlinePainter({required this.borderSide, required this.width});

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size ?? Size.zero;
    final lineLeft = offset.dx + (size.width - width) / 2;
    final lineTop = offset.dy + size.height - borderSide.width;
    final rect = Rect.fromLTWH(lineLeft, lineTop, width, borderSide.width);
    final radius = Radius.circular(borderSide.width / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = borderSide.color);
  }
}

class PaipanSliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  PaipanSliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: 44,
      child: Container(color: AppColors.surface, child: tabBar),
    );
  }

  @override
  bool shouldRebuild(covariant PaipanSliverTabBarDelegate old) => tabBar != old.tabBar;
}

// ——— 十神/地支表（专业细盘用） ———
const Map<String, Map<String, String>> paipanKShenFullMap = {
  '甲': {'甲': '比肩', '乙': '劫财', '丙': '食神', '丁': '伤官', '戊': '偏财', '己': '正财', '庚': '七杀', '辛': '正官', '壬': '偏印', '癸': '正印'},
  '乙': {'甲': '劫财', '乙': '比肩', '丙': '伤官', '丁': '食神', '戊': '正财', '己': '偏财', '庚': '正官', '辛': '七杀', '壬': '正印', '癸': '偏印'},
  '丙': {'甲': '偏印', '乙': '正印', '丙': '比肩', '丁': '劫财', '戊': '食神', '己': '伤官', '庚': '偏财', '辛': '正财', '壬': '七杀', '癸': '正官'},
  '丁': {'甲': '正印', '乙': '偏印', '丙': '劫财', '丁': '比肩', '戊': '伤官', '己': '食神', '庚': '正财', '辛': '偏财', '壬': '正官', '癸': '七杀'},
  '戊': {'甲': '七杀', '乙': '正官', '丙': '偏印', '丁': '正印', '戊': '比肩', '己': '劫财', '庚': '食神', '辛': '伤官', '壬': '偏财', '癸': '正财'},
  '己': {'甲': '正官', '乙': '七杀', '丙': '正印', '丁': '偏印', '戊': '劫财', '己': '比肩', '庚': '伤官', '辛': '食神', '壬': '正财', '癸': '偏财'},
  '庚': {'甲': '偏财', '乙': '正财', '丙': '七杀', '丁': '正官', '戊': '偏印', '己': '正印', '庚': '比肩', '辛': '劫财', '壬': '食神', '癸': '伤官'},
  '辛': {'甲': '正财', '乙': '偏财', '丙': '正官', '丁': '七杀', '戊': '正印', '己': '偏印', '庚': '劫财', '辛': '比肩', '壬': '伤官', '癸': '食神'},
  '壬': {'甲': '食神', '乙': '伤官', '丙': '偏财', '丁': '正财', '戊': '七杀', '己': '正官', '庚': '偏印', '辛': '正印', '壬': '比肩', '癸': '劫财'},
  '癸': {'甲': '伤官', '乙': '食神', '丙': '正财', '丁': '偏财', '戊': '正官', '己': '七杀', '庚': '正印', '辛': '偏印', '壬': '劫财', '癸': '比肩'},
};

const Map<String, String> paipanZhi5ListFirst = {
  '子': '癸', '丑': '己', '寅': '甲', '卯': '乙', '辰': '戊', '巳': '丙', '午': '丁', '未': '己', '申': '庚', '酉': '辛', '戌': '戊', '亥': '壬',
};

String paipanShenFullName(String? s) => s ?? '';

// ——— 免责声明 ———
class PaipanDisclaimer extends StatelessWidget {
  const PaipanDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return const CulturalReferenceNotice();
  }
}
