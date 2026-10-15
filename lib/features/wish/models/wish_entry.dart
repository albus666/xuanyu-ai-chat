class WishPrayerCopy {
  WishPrayerCopy._();

  static const String title = '心有所念';
  static const String prompt = '请静下心来，写下此刻最真切的期盼';
  static const String completion = '心念已寄\n天地共知';
}

class WishEntry {
  const WishEntry({
    required this.id,
    required this.category,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String category;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'category': category,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WishEntry.fromJson(Map<String, dynamic> json) {
    return WishEntry(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? '为自己',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
