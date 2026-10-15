/// 人工智能生成合成内容的显式标识（法规要求：含 AI/人工智能 + 生成/合成）。
class AiGeneratedMark {
  static const textSuffix = '【本内容由AI生成】';
  static const imageWatermark = 'AI生成内容';

  static const _errorHints = <String>[
    '请先登录',
    '请求异常',
    '出错了',
    '网络异常',
    '服务暂时',
    '连接超时',
    '无法连接',
    '生成失败',
    '回复生成失败',
  ];

  static bool hasTextMark(String text) => text.contains(textSuffix);

  static bool looksLikeSystemError(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return _errorHints.any(t.contains);
  }

  /// 将标识追加到正文末尾；复制/导出应使用返回值，而不是裸正文。
  static String ensureTextMark(String text) {
    final trimmed = text.trimRight();
    if (looksLikeSystemError(trimmed)) return text;
    if (hasTextMark(trimmed)) return trimmed;
    if (trimmed.isEmpty) return textSuffix;
    return '$trimmed\n\n$textSuffix';
  }
}
