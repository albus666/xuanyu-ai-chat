/// Tab2：基本命盘（表格：主星/天干/地支/藏干/星运/自坐/空亡/纳音/神煞）
library;
import 'package:flutter/material.dart';
import 'utils/bazi_result.dart';
import 'share/paipan_shared.dart';

class PaipanBasicChartTab extends StatelessWidget {
  final BaziResult result;
  final bool isFemale;

  const PaipanBasicChartTab({super.key, required this.result, required this.isFemale});

  static const double _tableFontSize = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Table(
            columnWidths: const {
              0: FixedColumnWidth(56),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
            },
            border: const TableBorder(),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: paipanSectionHeaderBg),
                children: [
                  _cell('日期', isHeader: true, rightBorder: true),
                  _cell('年柱', isHeader: true, rightBorder: true),
                  _cell('月柱', isHeader: true, rightBorder: true),
                  _cell('日柱', isHeader: true, rightBorder: false),
                  _cell('时柱', isHeader: true, rightBorder: false),
                ],
              ),
              _tableRow('主星', result.mainStars),
              TableRow(
                decoration: const BoxDecoration(color: paipanSectionHeaderBg),
                children: [
                  _cell('天干', isHeader: true, fontSize: _tableFontSize * 1.25, rightBorder: true),
                  _cell(result.gans[0], color: paipanGanColor(result.gans[0]), fontSize: _tableFontSize * 2, rightBorder: true),
                  _cell(result.gans[1], color: paipanGanColor(result.gans[1]), fontSize: _tableFontSize * 2, rightBorder: true),
                  _cell(result.gans[2], color: paipanGanColor(result.gans[2]), fontSize: _tableFontSize * 2, rightBorder: false),
                  _cell(result.gans[3], color: paipanGanColor(result.gans[3]), fontSize: _tableFontSize * 2, rightBorder: false),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: paipanSectionHeaderBg),
                children: [
                  _cell('地支', isHeader: true, fontSize: _tableFontSize * 1.25, rightBorder: true),
                  _cell(result.zhis[0], color: paipanZhiColor(result.zhis[0]), fontSize: _tableFontSize * 2, rightBorder: true),
                  _cell(result.zhis[1], color: paipanZhiColor(result.zhis[1]), fontSize: _tableFontSize * 2, rightBorder: true),
                  _cell(result.zhis[2], color: paipanZhiColor(result.zhis[2]), fontSize: _tableFontSize * 2, rightBorder: false),
                  _cell(result.zhis[3], color: paipanZhiColor(result.zhis[3]), fontSize: _tableFontSize * 2, rightBorder: false),
                ],
              ),
              TableRow(
                children: [
                  _cell('藏干', isHeader: true, fontSize: _tableFontSize * 1.25, rightBorder: true),
                  ...List.generate(4, (i) => _cellWithChild(paipanColoredZhiCangText(result.zhiCangGanWithShen[i].join('\n'), _tableFontSize - 2), rightBorder: i < 2)),
                ],
              ),
              _tableRow('星运', result.xingYun, rowBg: true),
              _tableRow('自坐', result.ziZuo),
              _tableRow('空亡', result.pillarEmpties, rowBg: true),
              _tableRow('纳音', result.pillarNayins, contentFontSize: _tableFontSize - 1),
              TableRow(
                decoration: const BoxDecoration(color: paipanSectionHeaderBg),
                children: [
                  _cell('神煞', isHeader: true, fontSize: _tableFontSize * 1.25, rightBorder: true),
                  ...List.generate(4, (i) => _cell(
                    result.shenSha[i].isEmpty ? '—' : result.shenSha[i].join('\n'),
                    rightBorder: i < 2,
                  )),
                ],
              ),
            ],
          ),
          paipanFlatSection(
            '干支留意',
            // 基本命盘只论四柱，不含大运/流年/流月
            paipanBuildGanZhiLiuYiContent(result, isFemale, '', '', ''),
          ),
          const SizedBox(height: 24),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PaipanDisclaimer()),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool isHeader = false, Color? color, double? fontSize, bool rightBorder = true}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize ?? _tableFontSize,
              fontWeight: FontWeight.normal,
              color: color ?? Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellWithChild(Widget child, {bool rightBorder = true}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: child),
      ),
    );
  }

  TableRow _tableRow(String label, List<String> values, {bool rowBg = false, double? contentFontSize}) {
    final list = values.toList();
    final fs = contentFontSize ?? _tableFontSize;
    return TableRow(
      decoration: rowBg ? const BoxDecoration(color: paipanSectionHeaderBg) : null,
      children: [
        _cell(label, isHeader: true, fontSize: _tableFontSize * 1.25, rightBorder: true),
        list.isNotEmpty ? _cell(list[0], rightBorder: true, fontSize: fs) : _cell('', rightBorder: true, fontSize: fs),
        list.length > 1 ? _cell(list[1], rightBorder: true, fontSize: fs) : _cell('', rightBorder: true, fontSize: fs),
        list.length > 2 ? _cell(list[2], rightBorder: false, fontSize: fs) : _cell('', rightBorder: false, fontSize: fs),
        list.length > 3 ? _cell(list[3], rightBorder: false, fontSize: fs) : _cell('', rightBorder: false, fontSize: fs),
      ],
    );
  }
}
