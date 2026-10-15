import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/local/archive_account_scope.dart';
import '../../../core/local/archive_cloud_sync.dart';
import 'astrology_models.dart';

class AstrologyArchiveRecord {
  const AstrologyArchiveRecord({
    required this.id,
    required this.createdAt,
    required this.profile,
    required this.isSelf,
    this.note = '',
    this.caseTitle = '',
    String? reasoningNotes,
    this.commentary = '',
  }) : reasoningNotes = reasoningNotes ?? note;

  factory AstrologyArchiveRecord.fromJson(Map<String, dynamic> json) =>
      AstrologyArchiveRecord(
        id: json['id']?.toString() ?? '',
        createdAt: DateTime.parse(json['createdAt'].toString()),
        profile: AstrologyProfile.fromJson(
          Map<String, dynamic>.from(json['profile'] as Map),
        ),
        isSelf: json['isSelf'] == true,
        note: json['note']?.toString() ?? '',
        caseTitle: json['caseTitle']?.toString() ?? '',
        reasoningNotes: json['reasoningNotes']?.toString(),
        commentary: json['commentary']?.toString() ?? '',
      );

  final String id;
  final DateTime createdAt;
  final AstrologyProfile profile;
  final bool isSelf;
  final String note;
  final String caseTitle;
  final String reasoningNotes;
  final String commentary;

  bool get hasCaseNotes =>
      caseTitle.trim().isNotEmpty ||
      reasoningNotes.trim().isNotEmpty ||
      commentary.trim().isNotEmpty;

  AstrologyArchiveRecord copyWith(
          {AstrologyProfile? profile,
          String? note,
          String? caseTitle,
          String? reasoningNotes,
          String? commentary}) =>
      AstrologyArchiveRecord(
        id: id,
        createdAt: createdAt,
        profile: profile ?? this.profile,
        isSelf: isSelf,
        note: note ?? this.note,
        caseTitle: caseTitle ?? this.caseTitle,
        reasoningNotes: reasoningNotes ?? note ?? this.reasoningNotes,
        commentary: commentary ?? this.commentary,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'profile': profile.toJson(),
        'isSelf': isSelf,
        if (note.isNotEmpty) 'note': note,
        'caseTitle': caseTitle,
        'reasoningNotes': reasoningNotes,
        'commentary': commentary,
      };
}

class AstrologyArchiveStore {
  AstrologyArchiveStore._();
  static const _key = 'astrology_archive_records_v1';

  static Future<List<AstrologyArchiveRecord>> loadAll() async {
    final raw = await ArchiveAccountScope.readJson(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final rows = <AstrologyArchiveRecord>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          rows.add(
            AstrologyArchiveRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {}
      }
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows;
    } catch (_) {
      return [];
    }
  }

  static Future<AstrologyArchiveRecord> save(
    AstrologyProfile profile, {
    required bool isSelf,
    int? expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      if (expectedUserId != null &&
          await ArchiveAccountScope.currentUserId() != expectedUserId) {
        throw StateError('档案所属账号已变更，请重新排盘');
      }
      final rows = await loadAll();
      var index = isSelf
          ? rows.indexWhere((item) => item.isSelf)
          : rows.indexWhere(
              (item) =>
                  !item.isSelf &&
                  item.profile.name == profile.name &&
                  item.profile.birthDateTime == profile.birthDateTime &&
                  (item.profile.isFemale == null ||
                      profile.isFemale == null ||
                      item.profile.isFemale == profile.isFemale) &&
                  (item.profile.longitude - profile.longitude).abs() <
                      0.000001 &&
                  (item.profile.latitude - profile.latitude).abs() < 0.000001,
            );
      final previous = index >= 0 ? rows.removeAt(index) : null;
      final saved = AstrologyArchiveRecord(
        id: previous?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: previous?.createdAt ?? DateTime.now(),
        profile: profile,
        isSelf: isSelf,
        note: previous?.note ?? '',
        caseTitle: previous?.caseTitle ?? '',
        reasoningNotes: previous?.reasoningNotes,
        commentary: previous?.commentary ?? '',
      );
      if (isSelf) rows.removeWhere((item) => item.isSelf);
      rows.insert(0, saved);
      await _write(rows, expectedUserId: expectedUserId);
      return saved;
    }, expectedUserId: expectedUserId);
  }

  static Future<void> updateNote(String id, String note) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final rows = await loadAll();
      final index = rows.indexWhere((item) => item.id == id);
      if (index < 0) return;
      rows[index] = rows[index].copyWith(note: note.trim());
      await _write(rows);
    });
  }

  static Future<void> updateCase(
    String id, {
    required String caseTitle,
    required String reasoningNotes,
    required String commentary,
    required int expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      if (await ArchiveAccountScope.currentUserId() != expectedUserId) {
        throw StateError('账号已变更，请重新打开命盘');
      }
      final raw = await ArchiveAccountScope.readJson(_key);
      if (raw == null || raw.isEmpty) throw StateError('当前档案不存在');
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('档案数据损坏');
      final rows = decoded
          .map((item) => AstrologyArchiveRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
      final index = rows.indexWhere((item) => item.id == id);
      if (index < 0) throw StateError('当前档案不存在');
      rows[index] = rows[index].copyWith(
        caseTitle: caseTitle.trim(),
        reasoningNotes: reasoningNotes.trim(),
        commentary: commentary.trim(),
      );
      await _write(rows, expectedUserId: expectedUserId);
    }, expectedUserId: expectedUserId);
  }

  static Future<void> delete(String id, {int? expectedUserId}) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final prefs = await SharedPreferences.getInstance();
      final userId = await ArchiveAccountScope.currentUserId(prefs);
      if (userId == null ||
          (expectedUserId != null && expectedUserId != userId)) {
        throw StateError('档案所属账号已变更，请重新打开后操作');
      }
      final raw = await ArchiveAccountScope.readJson(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('星盘档案数据损坏');
      final rows = decoded
          .whereType<Map>()
          .map(
            (item) => AstrologyArchiveRecord.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList()
        ..removeWhere((item) => item.id == id);
      if (await ArchiveAccountScope.currentUserId(prefs) != userId) {
        throw StateError('档案所属账号已变更，请重新打开后操作');
      }
      await ArchiveAccountScope.writeJson(
        _key,
        jsonEncode(rows.map((item) => item.toJson()).toList()),
        expectedUserId: userId,
      );
    }, expectedUserId: expectedUserId);
  }

  static Future<void> _write(
    List<AstrologyArchiveRecord> rows, {
    int? expectedUserId,
  }) async {
    final value = jsonEncode(rows.map((item) => item.toJson()).toList());
    if (expectedUserId == null) {
      await ArchiveAccountScope.writeJson(_key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (await ArchiveAccountScope.currentUserId(prefs) != expectedUserId) {
      throw StateError('档案所属账号已变更，请重新排盘');
    }
    if (!await ArchiveAccountScope.writeJson(
      _key,
      value,
      expectedUserId: expectedUserId,
    )) {
      throw StateError('笔记保存失败');
    }
  }
}
