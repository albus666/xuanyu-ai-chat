import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/local/archive_account_scope.dart';
import '../../../core/local/archive_cloud_sync.dart';
import '../archive_relationship.dart';
import 'ziwei_models.dart';

class ZiweiArchiveRecord {
  const ZiweiArchiveRecord({
    required this.id,
    required this.createdAt,
    required this.profile,
    this.isSelf = false,
    this.relationship = ArchiveRelationship.other,
    this.engineName = '',
    this.engineVersion = '',
    this.ruleCode = '',
    this.caseTitle = '',
    this.reasoningNotes = '',
    this.commentary = '',
    this.caseUpdatedAt,
  });

  factory ZiweiArchiveRecord.fromJson(Map<String, dynamic> json) {
    final profile = ZiweiProfile.fromJson(
      Map<String, dynamic>.from(json['profile'] as Map),
    );
    final isSelf = json['isSelf'] == true;
    final relationship = json['relationship']?.toString().trim();
    return ZiweiArchiveRecord(
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt']?.toString() ?? ''),
      profile: profile,
      isSelf: isSelf,
      relationship: relationship?.isNotEmpty == true
          ? relationship!
          : isSelf
          ? ArchiveRelationship.self
          : ArchiveRelationship.isReservedSelfName(profile.name)
          ? ArchiveRelationship.legacy
          : ArchiveRelationship.other,
      engineName: json['engineName']?.toString() ?? '',
      engineVersion: json['engineVersion']?.toString() ?? '',
      ruleCode: json['ruleCode']?.toString() ?? '',
      caseTitle: json['caseTitle']?.toString() ?? '',
      reasoningNotes: json['reasoningNotes']?.toString() ?? '',
      commentary: json['commentary']?.toString() ?? '',
      caseUpdatedAt: json['caseUpdatedAt'] == null
          ? null
          : DateTime.tryParse(json['caseUpdatedAt'].toString()),
    );
  }

  final String id;
  final DateTime createdAt;
  final ZiweiProfile profile;
  final bool isSelf;
  final String relationship;
  final String engineName;
  final String engineVersion;
  final String ruleCode;
  final String caseTitle;
  final String reasoningNotes;
  final String commentary;
  final DateTime? caseUpdatedAt;

  bool get isCase =>
      caseTitle.trim().isNotEmpty ||
      reasoningNotes.trim().isNotEmpty ||
      commentary.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'profile': profile.toJson(),
    'isSelf': isSelf,
    'relationship': relationship,
    if (engineName.isNotEmpty) 'engineName': engineName,
    if (engineVersion.isNotEmpty) 'engineVersion': engineVersion,
    if (ruleCode.isNotEmpty) 'ruleCode': ruleCode,
    if (caseTitle.isNotEmpty) 'caseTitle': caseTitle,
    if (reasoningNotes.isNotEmpty) 'reasoningNotes': reasoningNotes,
    if (commentary.isNotEmpty) 'commentary': commentary,
    if (caseUpdatedAt != null)
      'caseUpdatedAt': caseUpdatedAt!.toIso8601String(),
  };

  ZiweiArchiveRecord copyWith({
    ZiweiProfile? profile,
    bool? isSelf,
    String? relationship,
    String? caseTitle,
    String? reasoningNotes,
    String? commentary,
    DateTime? caseUpdatedAt,
  }) => ZiweiArchiveRecord(
    id: id,
    createdAt: createdAt,
    profile: profile ?? this.profile,
    isSelf: isSelf ?? this.isSelf,
    relationship: relationship ?? this.relationship,
    engineName: engineName,
    engineVersion: engineVersion,
    ruleCode: ruleCode,
    caseTitle: caseTitle ?? this.caseTitle,
    reasoningNotes: reasoningNotes ?? this.reasoningNotes,
    commentary: commentary ?? this.commentary,
    caseUpdatedAt: caseUpdatedAt ?? this.caseUpdatedAt,
  );

  bool get isLegacySelf =>
      !isSelf && relationship == ArchiveRelationship.legacy;

  String get relationshipLabel => ArchiveRelationship.label(
    isSelf ? ArchiveRelationship.self : relationship,
  );
}

class ZiweiArchiveStore {
  ZiweiArchiveStore._();

  static const _key = 'ziwei_archive_records_v1';

  static Future<List<ZiweiArchiveRecord>> loadAll() async {
    final raw = await ArchiveAccountScope.readJson(_key);
    if (raw == null || raw.isEmpty) return <ZiweiArchiveRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ZiweiArchiveRecord>[];
      final records = <ZiweiArchiveRecord>[];
      for (final item in decoded) {
        try {
          if (item is Map) {
            records.add(
              ZiweiArchiveRecord.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (_) {
          // 单条旧数据损坏时保留其他可用档案。
        }
      }
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } catch (_) {
      return <ZiweiArchiveRecord>[];
    }
  }

  static Future<ZiweiArchiveRecord> save(
    ZiweiProfile profile, {
    bool isSelf = false,
    String relationship = ArchiveRelationship.other,
    String engineName = '',
    String engineVersion = '',
    String ruleCode = '',
    int? expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      if (expectedUserId != null &&
          await ArchiveAccountScope.currentUserId() != expectedUserId) {
        throw StateError('档案所属账号已变更，请重新排盘');
      }
      final records = await loadAll();
      final now = DateTime.now();
      var index = -1;
      if (isSelf) {
        index = records.indexWhere((item) => item.isSelf);
        if (index < 0) {
          index = records.indexWhere(
            (item) => item.isLegacySelf && _sameBirth(item.profile, profile),
          );
        }
      } else {
        index = records.indexWhere(
          (item) =>
              !item.isSelf &&
              item.profile.name.trim().toLowerCase() ==
                  profile.name.trim().toLowerCase() &&
              item.relationship == relationship &&
              _sameBirth(item.profile, profile),
        );
      }
      final fresh = ZiweiArchiveRecord(
        id: now.microsecondsSinceEpoch.toString(),
        createdAt: now,
        profile: profile,
        isSelf: isSelf,
        relationship: relationship,
        engineName: engineName,
        engineVersion: engineVersion,
        ruleCode: ruleCode,
      );
      final saved = index < 0
          ? fresh
          : ZiweiArchiveRecord(
              id: records[index].id,
              createdAt: records[index].createdAt,
              profile: profile,
              isSelf: isSelf,
              relationship: relationship,
              engineName: engineName,
              engineVersion: engineVersion,
              ruleCode: ruleCode,
              caseTitle: records[index].caseTitle,
              reasoningNotes: records[index].reasoningNotes,
              commentary: records[index].commentary,
              caseUpdatedAt: records[index].caseUpdatedAt,
            );
      if (index >= 0) records.removeAt(index);
      if (isSelf) records.removeWhere((item) => item.isSelf);
      records.insert(0, saved);
      await _write(records, expectedUserId: expectedUserId);
      return saved;
    }, expectedUserId: expectedUserId);
  }

  static bool _sameBirth(ZiweiProfile a, ZiweiProfile b) =>
      a.clockBirthDate.year == b.clockBirthDate.year &&
      a.clockBirthDate.month == b.clockBirthDate.month &&
      a.clockBirthDate.day == b.clockBirthDate.day &&
      a.clockBirthDate.hour == b.clockBirthDate.hour &&
      a.clockBirthDate.minute == b.clockBirthDate.minute &&
      a.gender == b.gender;

  static Future<void> claimSelfProfile({
    required DateTime birthDateTime,
    required String gender,
    required String nickname,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final records = await loadAll();
      var index = records.indexWhere((item) => item.isSelf);
      index = index >= 0
          ? index
          : records.indexWhere(
              (item) =>
                  item.isLegacySelf &&
                  item.profile.gender == gender &&
                  item.profile.clockBirthDate.year == birthDateTime.year &&
                  item.profile.clockBirthDate.month == birthDateTime.month &&
                  item.profile.clockBirthDate.day == birthDateTime.day &&
                  item.profile.clockBirthDate.hour == birthDateTime.hour,
            );
      if (index < 0) return;
      final safeName = nickname.trim().isEmpty ? '我的紫微' : nickname.trim();
      records[index] = records[index].copyWith(
        profile: records[index].profile.copyWith(name: safeName),
        isSelf: true,
        relationship: ArchiveRelationship.self,
      );
      for (var i = 0; i < records.length; i++) {
        if (i != index && records[i].isSelf) {
          records[i] = records[i].copyWith(
            isSelf: false,
            relationship: ArchiveRelationship.legacy,
          );
        }
      }
      await _write(records);
    });
  }

  static Future<void> updateIdentity(
    String id, {
    required String displayName,
    required String relationship,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final records = await loadAll();
      final index = records.indexWhere((item) => item.id == id);
      if (index < 0 || records[index].isSelf) return;
      records[index] = records[index].copyWith(
        profile: records[index].profile.copyWith(name: displayName.trim()),
        isSelf: false,
        relationship: relationship,
      );
      await _write(records);
    });
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
      if (decoded is! List) throw const FormatException('紫微档案数据损坏');
      final records = decoded
          .whereType<Map>()
          .map(
            (item) =>
                ZiweiArchiveRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      records.removeWhere((record) => record.id == id);
      if (await ArchiveAccountScope.currentUserId(prefs) != userId) {
        throw StateError('档案所属账号已变更，请重新打开后操作');
      }
      await ArchiveAccountScope.writeJson(
        _key,
        jsonEncode(records.map((record) => record.toJson()).toList()),
        expectedUserId: userId,
      );
    }, expectedUserId: expectedUserId);
  }

  static Future<ZiweiArchiveRecord?> find(String id) async {
    final records = await loadAll();
    final matches = records.where((record) => record.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  static Future<ZiweiArchiveRecord> saveCase({
    required ZiweiArchiveRecord fallback,
    required String caseTitle,
    required String reasoningNotes,
    required String commentary,
    int? expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      if (expectedUserId != null &&
          await ArchiveAccountScope.currentUserId() != expectedUserId) {
        throw StateError('账号已变更，请重新打开档案');
      }
      final records = await loadAll();
      final index = records.indexWhere((record) => record.id == fallback.id);
      final saved = (index < 0 ? fallback : records[index]).copyWith(
        caseTitle: caseTitle.trim(),
        reasoningNotes: reasoningNotes.trim(),
        commentary: commentary.trim(),
        caseUpdatedAt: DateTime.now(),
      );
      if (index < 0) {
        records.insert(0, saved);
      } else {
        records[index] = saved;
      }
      await _write(records, expectedUserId: expectedUserId);
      return saved;
    }, expectedUserId: expectedUserId);
  }

  static Future<void> _write(
    List<ZiweiArchiveRecord> records, {
    int? expectedUserId,
  }) async {
    final value = jsonEncode(records.map((record) => record.toJson()).toList());
    if (expectedUserId == null) {
      await ArchiveAccountScope.writeJson(_key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (await ArchiveAccountScope.currentUserId(prefs) != expectedUserId) {
      throw StateError('档案所属账号已变更，请重新排盘');
    }
    await ArchiveAccountScope.writeJson(
      _key,
      value,
      expectedUserId: expectedUserId,
    );
  }
}
