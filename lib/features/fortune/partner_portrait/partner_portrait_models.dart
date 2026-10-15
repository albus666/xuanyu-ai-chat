class PartnerPortraitChapter {
  const PartnerPortraitChapter({
    required this.code,
    required this.title,
    required this.unlocked,
    required this.tag,
    required this.preview,
    required this.detail,
    required this.relationshipTip,
    required this.evidence,
  });

  factory PartnerPortraitChapter.fromJson(Map<String, dynamic> json) =>
      PartnerPortraitChapter(
        code: _text(json['code']),
        title: _text(json['title']),
        unlocked: json['unlocked'] == true,
        tag: _text(json['tag']),
        preview: _text(json['preview']),
        detail: _text(json['detail']),
        relationshipTip: _text(json['relationshipTip']),
        evidence: _text(json['evidence']),
      );

  final String code;
  final String title;
  final bool unlocked;
  final String tag;
  final String preview;
  final String detail;
  final String relationshipTip;
  final String evidence;
}

class PartnerPortraitTestResult {
  const PartnerPortraitTestResult({
    required this.headline,
    required this.answer,
    required this.keyPoints,
    required this.action,
  });

  factory PartnerPortraitTestResult.fromJson(Map<String, dynamic> json) =>
      PartnerPortraitTestResult(
        headline: _text(json['headline']),
        answer: _text(json['answer']),
        keyPoints: _strings(json['keyPoints']),
        action: _text(json['action']),
      );

  final String headline;
  final String answer;
  final List<String> keyPoints;
  final String action;
}

class PartnerPortraitTestItem {
  const PartnerPortraitTestItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.focusCode,
    required this.price,
    required this.tone,
    required this.owned,
    this.result,
  });

  factory PartnerPortraitTestItem.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'];
    return PartnerPortraitTestItem(
      id: _text(json['id']),
      title: _text(json['title']),
      subtitle: _text(json['subtitle']),
      focusCode: _text(json['focusCode']),
      price: _number(json['price']),
      tone: _text(json['tone']),
      owned: json['owned'] == true,
      result: rawResult is Map
          ? PartnerPortraitTestResult.fromJson(
              Map<String, dynamic>.from(rawResult),
            )
          : null,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String focusCode;
  final double price;
  final String tone;
  final bool owned;
  final PartnerPortraitTestResult? result;
}

class PartnerPortraitState {
  const PartnerPortraitState({
    required this.profileKey,
    required this.headline,
    required this.keywords,
    required this.reportOwned,
    required this.chapters,
    required this.tests,
    required this.reportPrice,
    required this.bundlePrice,
    required this.walletBalance,
    required this.purchaseRule,
    required this.disclaimer,
  });

  factory PartnerPortraitState.fromJson(Map<String, dynamic> json) =>
      PartnerPortraitState(
        profileKey: _text(json['profileKey']),
        headline: _text(json['headline']),
        keywords: _strings(json['keywords']),
        reportOwned: json['reportOwned'] == true,
        chapters: _maps(json['chapters'])
            .map(PartnerPortraitChapter.fromJson)
            .toList(),
        tests:
            _maps(json['tests']).map(PartnerPortraitTestItem.fromJson).toList(),
        reportPrice: _number(json['reportPrice']),
        bundlePrice: _number(json['bundlePrice']),
        walletBalance: _number(json['walletBalance']),
        purchaseRule: _text(json['purchaseRule']),
        disclaimer: _text(json['disclaimer']),
      );

  final String profileKey;
  final String headline;
  final List<String> keywords;
  final bool reportOwned;
  final List<PartnerPortraitChapter> chapters;
  final List<PartnerPortraitTestItem> tests;
  final double reportPrice;
  final double bundlePrice;
  final double walletBalance;
  final String purchaseRule;
  final String disclaimer;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;

List<String> _strings(dynamic value) => value is List
    ? value.map(_text).where((item) => item.isNotEmpty).toList()
    : const <String>[];

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : const <Map<String, dynamic>>[];
