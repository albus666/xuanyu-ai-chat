class ArchiveRelationship {
  ArchiveRelationship._();

  static const String self = 'self';
  static const String family = 'family';
  static const String partner = 'partner';
  static const String friend = 'friend';
  static const String client = 'client';
  static const String caseRecord = 'case';
  static const String other = 'other';
  static const String legacy = 'legacy';

  static const List<String> selectableForOthers = <String>[
    family,
    partner,
    friend,
    client,
    caseRecord,
    other,
  ];

  static String label(String value) => switch (value) {
        self => '本人',
        family => '家人',
        partner => '伴侣',
        friend => '朋友',
        client => '客户',
        caseRecord => '案例',
        legacy => '待整理',
        _ => '其他',
      };

  static bool isReservedSelfName(String value) {
    final normalized = value.trim().replaceAll(' ', '');
    return const <String>{'本人', '我', '自己', '我的八字', '我的紫微', '我的命盘'}
        .contains(normalized);
  }
}
