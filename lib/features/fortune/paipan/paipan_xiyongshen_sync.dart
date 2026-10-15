import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import 'share/paipan_extra_content_service.dart';
import 'utils/bazi_result.dart';
import 'utils/wu_xing_liang_hua.dart';

/// 构造与排盘「个人信息」一致的摘要。
/// 有生日时服务端仅用公历起盘（六十甲子+量化）；无生日时摘要供豆包从条文与量化参考中提取。
String buildPaipanSummaryForXiyongshenSync(BaziResult result, PaipanExtraContent extra) {
  final buf = StringBuffer();
  buf.writeln('四柱：${result.fourPillarsStr}');
  buf.writeln('日干：${result.dayGan}');
  if (extra.wangShuai.isNotEmpty) {
    buf.writeln('旺衰（六十甲子论）：${extra.wangShuai}');
  }
  if (extra.yongShen.isNotEmpty) {
    buf.writeln('用神（六十甲子论）：${extra.yongShen}');
  }
  try {
    final s = computeWuXingLiangHua(result);
    final sq = analyzeWuXingShenQiangYongShen(s, result.dayGan, result);
    final ref = sq.xiYongShen.isEmpty ? '—' : sq.xiYongShen;
    buf.writeln('五行量化推论喜用神：$ref');
  } catch (_) {}
  return buf.toString();
}

/// 提交排盘摘要与公历生日；服务端用生日起盘写喜用神（六十甲子优先），无生日时才用豆包读摘要。
/// 未登录或失败时静默忽略。
Future<void> trySyncXiyongshenFromPaipan(
  BaziResult result,
  PaipanExtraContent extra,
  DateTime birthDateTime,
) async {
  final summary = buildPaipanSummaryForXiyongshenSync(result, extra);
  if (summary.trim().length < 12) return;

  try {
    await apiClient.post('/api/fortune/xiyongshen/sync-from-paipan', data: {
      'paipanText': summary,
      'birthDate': DateFormat('yyyy-MM-dd').format(birthDateTime),
      'birthTime': DateFormat('HH:mm').format(birthDateTime),
    });
  } on DioException catch (_) {}
}
