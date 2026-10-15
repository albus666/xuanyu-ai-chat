/// 把 PDF 导出式硬换行的法律文本恢复为可排版的段落结构。

enum LegalBlockKind {
  heading,
  subheading,
  body,
  bullet,
  field,
  notice,
  item,
}

class LegalBlock {
  const LegalBlock({required this.kind, required this.text});

  final LegalBlockKind kind;
  final String text;

  String? get fieldLabel {
    if (kind != LegalBlockKind.field) return null;
    final match = _fieldSplit.firstMatch(text);
    return match?.group(1)?.trim();
  }

  String get fieldValue {
    if (kind != LegalBlockKind.field) return text;
    final match = _fieldSplit.firstMatch(text);
    return (match?.group(2) ?? text).trim();
  }
}

class ParsedLegalDocument {
  const ParsedLegalDocument({
    required this.title,
    required this.blocks,
    this.version,
    this.effectiveDate,
  });

  final String title;
  final String? version;
  final String? effectiveDate;
  final List<LegalBlock> blocks;

  List<LegalBlock> get sectionHeadings => blocks
      .where((block) => block.kind == LegalBlockKind.heading)
      .toList(growable: false);
}

final _fieldSplit = RegExp(r'^(.+?)[：:](.*)$');
final _sectionRe = RegExp(r'^\d+\.\s+\S');
final _subsectionRe = RegExp(r'^\d+(?:\.\d+)+\s+\S');
final _numberedItemRe = RegExp(r'^（[一二三四五六七八九十百]+）');
const _fieldPrefixes = [
  '个人信息处理者：',
  '个人信息保护负责人邮箱：',
  '儿童个人信息保护专人邮箱：',
  '个人信息权利请求受理渠道：',
  '响应时限：',
  '个人信息种类：',
  '收集目的：',
  '调用权限：',
  '收集频度：',
  '敏感信息必要性：',
  '对用户权益的影响：',
  '处理场景：',
  '单独同意获取方式：',
  '撤回路径：',
  '权限名称：',
  '使用场景：',
  '是否可关闭：',
  '关闭后的影响：',
  'SDK 名称：',
  'SDK名称：',
  '开发者:',
  '目的：',
  '收集信息范围：',
  'SDK隐私政策链接：',
  '提供方公司全称：',
  '使用目的：',
  '处理的个人信息类型：',
  '隐私政策链接：',
  '敏感信息类型：',
];
const _cardTitleLabels = {
  'SDK名称',
  'SDK 名称',
  '权限名称',
  '敏感信息类型',
};

bool _isDocumentTitle(String line) {
  if (line.length >= 32) return false;
  if (line.endsWith('。') || line.endsWith('！') || line.endsWith('？')) {
    return false;
  }
  return !_sectionRe.hasMatch(line) &&
      !_subsectionRe.hasMatch(line) &&
      !line.contains('：') &&
      !line.startsWith('开发者:') &&
      !line.startsWith('· ') &&
      !line.startsWith('☐');
}

LegalBlockKind _classify(String line) {
  if (_subsectionRe.hasMatch(line)) return LegalBlockKind.subheading;
  if (_sectionRe.hasMatch(line)) return LegalBlockKind.heading;
  if (line.startsWith('· ')) return LegalBlockKind.bullet;
  if (line.startsWith('☐') || _numberedItemRe.hasMatch(line)) {
    return LegalBlockKind.item;
  }
  if (_fieldPrefixes.any(line.startsWith)) return LegalBlockKind.field;
  if (line == '重要提示' ||
      line.startsWith('重要提示：') ||
      line.startsWith('重要说明：') ||
      line.startsWith('特别说明：')) {
    return LegalBlockKind.notice;
  }
  return LegalBlockKind.body;
}

bool _shouldFlushLine(String line, LegalBlockKind kind) {
  return kind == LegalBlockKind.heading ||
      kind == LegalBlockKind.subheading ||
      line.endsWith('。') ||
      line.endsWith('！') ||
      line.endsWith('？') ||
      line.endsWith('；') ||
      line.endsWith('：');
}

ParsedLegalDocument parseLegalDocument(
  String raw, {
  String fallbackTitle = '',
}) {
  final lines = raw
      .replaceAll('\f', '\n')
      .split('\n')
      .map((line) => line.trim())
      .toList(growable: false);

  String title = fallbackTitle;
  String? version;
  String? effectiveDate;
  var seenTitle = false;
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('版本号：')) {
      version = line.substring('版本号：'.length).trim();
      continue;
    }
    if (line.startsWith('生效日期：')) {
      effectiveDate = line.substring('生效日期：'.length).trim();
      continue;
    }
    if (!seenTitle && _isDocumentTitle(line)) {
      title = line;
      seenTitle = true;
      continue;
    }
    break;
  }
  if (title.isEmpty) title = fallbackTitle;

  final blocks = <LegalBlock>[];
  final current = StringBuffer();
  var currentKind = LegalBlockKind.body;

  void flush() {
    if (current.isEmpty) return;
    blocks.add(LegalBlock(kind: currentKind, text: current.toString()));
    current.clear();
    currentKind = LegalBlockKind.body;
  }

  for (final line in lines) {
    if (line.isEmpty ||
        line == title ||
        line.startsWith('版本号：') ||
        line.startsWith('生效日期：')) {
      flush();
      continue;
    }
    final kind = _classify(line);
    if (kind != LegalBlockKind.body) {
      flush();
      currentKind = kind;
    }
    current.write(line);
    if (_shouldFlushLine(line, kind)) flush();
  }
  flush();

  return ParsedLegalDocument(
    title: title,
    version: version,
    effectiveDate: effectiveDate,
    blocks: List<LegalBlock>.unmodifiable(blocks),
  );
}

/// 连续字段收成卡片；SDK / 权限 / 敏感信息条目各自独立成卡。
List<List<LegalBlock>> groupFieldCards(List<LegalBlock> fields) {
  final cards = <List<LegalBlock>>[];
  var current = <LegalBlock>[];
  for (final field in fields) {
    final label = field.fieldLabel ?? '';
    if (current.isNotEmpty && _cardTitleLabels.contains(label)) {
      cards.add(current);
      current = [];
    }
    current.add(field);
  }
  if (current.isNotEmpty) cards.add(current);
  return cards;
}
