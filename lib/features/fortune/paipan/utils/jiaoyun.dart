import 'package:lunar/lunar.dart';

/// 起运 / 交运 计算结果模块
class DaYunJiaoYunInfo {
  final int startXuSui;
  final String daYunStartDesc;
  final String jiaoYunDesc;

  const DaYunJiaoYunInfo({
    required this.startXuSui,
    required this.daYunStartDesc,
    required this.jiaoYunDesc,
  });
}

const List<String> _gan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];

const Map<String, String> _jieQiKeyToCn = {
  'XIAO_HAN': '小寒', 'DA_HAN': '大寒', 'LI_CHUN': '立春', 'YU_SHUI': '雨水',
  'JING_ZHE': '惊蛰', 'CHUN_FEN': '春分', 'QING_MING': '清明', 'GU_YU': '谷雨',
  'LI_XIA': '立夏', 'XIAO_MAN': '小满', 'MANG_ZHONG': '芒种', 'XIA_ZHI': '夏至',
  'XIAO_SHU': '小暑', 'DA_SHU': '大暑', 'LI_QIU': '立秋', 'CHU_SHU': '处暑',
  'BAI_LU': '白露', 'QIU_FEN': '秋分', 'HAN_LU': '寒露', 'SHUANG_JIANG': '霜降',
  'LI_DONG': '立冬', 'XIAO_XUE': '小雪', 'DA_XUE': '大雪', 'DONG_ZHI': '冬至',
};

const Set<String> _jieOnlyCn = {
  '立春', '惊蛰', '清明', '立夏', '芒种', '小暑',
  '立秋', '白露', '寒露', '立冬', '大雪', '小寒',
};

(String, String, int) buildDaYunStartAndJiaoYun(
  dynamic eightChar,
  bool isFemale,
  DateTime birth, {
  int yunSect = 1,
}) {
  try {
    final yun = eightChar.getYun(isFemale ? 0 : 1, yunSect);
    final start = yun.getStartSolar();
    final years = yun.getStartYear();
    final months = yun.getStartMonth();
    final days = yun.getStartDay();
    final hours = yun.getStartHour();
    final startXuSui = (start.getYear() - birth.year + 1).clamp(1, 99);
    final daYunStart = '出生后$years年$months月$days日$hours时';

    final startYear = start.getYear();
    final ganIdx = ((startYear - 4) % 10 + 10) % 10;
    final gan1 = _gan[ganIdx];
    final gan2 = _gan[(ganIdx + 5) % 10];
    final lunarStart = Lunar.fromDate(DateTime(startYear, start.getMonth(), start.getDay()));
    final jieQiTable = lunarStart.getJieQiTable();
    final startMoment = DateTime(
      start.getYear(),
      start.getMonth(),
      start.getDay(),
      start.getHour(),
      start.getMinute(),
      start.getSecond(),
    );
    final sortedJie = jieQiTable.entries
        .where((e) {
          final keyStr = e.key.toString();
          final rawKey = keyStr.contains('.') ? keyStr.split('.').last : keyStr;
          final cn = _jieQiKeyToCn[keyStr] ?? _jieQiKeyToCn[rawKey] ?? keyStr;
          return _jieOnlyCn.contains(cn);
        })
        .map((e) => MapEntry(
              DateTime(
                e.value.getYear(),
                e.value.getMonth(),
                e.value.getDay(),
                e.value.getHour(),
                e.value.getMinute(),
                e.value.getSecond(),
              ),
              e.key,
            ))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    String jieName = '';
    int daysFromJie = 0;
    bool afterJie = true;
    int? prevIdx;
    for (int i = 0; i < sortedJie.length; i++) {
      if (sortedJie[i].key.isBefore(startMoment) || sortedJie[i].key.isAtSameMomentAs(startMoment)) prevIdx = i;
    }
    if (prevIdx != null) {
      jieName = sortedJie[prevIdx].value.toString() ?? '';
      daysFromJie = startMoment.difference(sortedJie[prevIdx].key).inDays;
      afterJie = true;
    } else if (sortedJie.isNotEmpty) {
      jieName = sortedJie.first.value.toString() ?? '';
      daysFromJie = sortedJie.first.key.difference(startMoment).inDays;
      afterJie = false;
    }
    final rawKey = jieName.contains('.') ? jieName.split('.').last : jieName;
    jieName = _jieQiKeyToCn[jieName] ?? _jieQiKeyToCn[rawKey] ?? jieName;
    final jiaoYun = jieName.isNotEmpty ? '逢$gan1、$gan2年$jieName${afterJie ? '后' : '前'}$daysFromJie天' : '';
    return (daYunStart, jiaoYun, startXuSui);
  } catch (_) {
    return ('', '', 7);
  }
}

DaYunJiaoYunInfo computeDaYunJiaoYun(dynamic eightChar, bool isFemale, DateTime birth) {
  final (daYunStart, jiaoYun, startXuSui) = buildDaYunStartAndJiaoYun(
    eightChar,
    isFemale,
    birth,
  );
  return DaYunJiaoYunInfo(
    startXuSui: startXuSui,
    daYunStartDesc: daYunStart,
    jiaoYunDesc: jiaoYun,
  );
}
