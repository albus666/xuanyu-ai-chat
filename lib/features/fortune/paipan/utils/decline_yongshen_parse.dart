/// 与后端 `paipan_60decline_xiyongshen.parse_yongshen_ys_to_xiyong` 对齐：
/// 从「用神（六十甲子论）」条文解析 用神/喜神（金木水火土）。
library;

const _ganToWx = {
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

const _zhiWx = {
  '寅': '木',
  '卯': '木',
  '巳': '火',
  '午': '火',
  '申': '金',
  '酉': '金',
  '亥': '水',
  '子': '水',
  '辰': '土',
  '戌': '土',
  '丑': '土',
  '未': '土',
};

String? _scanFirstGan(String text) {
  for (final c in text.split('')) {
    if (_ganToWx.containsKey(c)) return c;
  }
  return null;
}

/// (记号, 五行)；先天干再地支，避免「辰中乙」误取辰。
(String, String)? _scanFirstWxSymbol(String text) {
  for (final c in text.split('')) {
    final w = _ganToWx[c];
    if (w != null) return (c, w);
  }
  for (final c in text.split('')) {
    final w = _zhiWx[c];
    if (w != null) return (c, w);
  }
  return null;
}

final _secondarySplit = RegExp(r'(?:其次|次而|次之|次选|次用|再次|再而|再选)');
final _weiXian = RegExp(r'([甲乙丙丁戊己庚辛壬癸])[水火木金土]?(?:为先|为要)');

/// 条文非空且能解析时返回 `{用神, 喜神}`；否则返回 null。
Map<String, String>? parseYongshenYsToXiYong(String ys) {
  final s = ys.trim();
  if (s.isEmpty) return null;

  final secM = _secondarySplit.firstMatch(s);
  final head = secM != null ? s.substring(0, secM.start) : s;
  final tail = secM != null ? s.substring(secM.end) : '';

  String? yongSym;
  String? yongWx;
  for (final kw in ['首用', '首取', '首喜', '最喜']) {
    final i = head.indexOf(kw);
    if (i >= 0) {
      final end = (i + kw.length + 30).clamp(0, head.length);
      final chunk = head.substring(i + kw.length, end);
      final got = _scanFirstWxSymbol(chunk);
      if (got != null) {
        yongSym = got.$1;
        yongWx = got.$2;
        break;
      }
    }
  }

  if (yongWx == null) {
    final m = _weiXian.firstMatch(head);
    if (m != null) {
      yongSym = m.group(1);
      yongWx = yongSym != null ? _ganToWx[yongSym] : null;
    }
  }

  if (yongWx == null || yongSym == null) return null;

  String? xiWx;
  if (tail.trim().isNotEmpty) {
    final gotTail = _scanFirstWxSymbol(tail);
    if (gotTail != null) xiWx = gotTail.$2;
  }
  if (xiWx == null) {
    final idx = head.indexOf(yongSym);
    if (idx >= 0) {
      final end = (idx + yongSym.length + 44).clamp(0, head.length);
      final rest = head.substring(idx + yongSym.length, end);
      for (final c in rest.split('')) {
        final gw = _ganToWx[c];
        if (gw != null && gw != yongWx) {
          xiWx = gw;
          break;
        }
        final zw = _zhiWx[c];
        if (zw != null && zw != yongWx) {
          xiWx = zw;
          break;
        }
      }
    }
  }
  xiWx ??= yongWx;

  return {'用神': yongWx, '喜神': xiWx};
}
