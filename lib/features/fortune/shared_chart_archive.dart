import '../../core/local/archive_account_scope.dart';
import '../../core/local/paipan_record_store.dart';
import '../consultation/room_chart_case_details.dart';
import 'archive_relationship.dart';
import 'astrology/astrology_archive_store.dart';
import 'astrology/astrology_models.dart';
import 'paipan/models/paipan_record.dart';
import 'paipan/models/region.dart';
import 'paipan/utils/bazi_result.dart';
import 'qizheng/qizheng_archive_store.dart';
import 'qizheng/qizheng_models.dart';
import 'ziwei/ziwei_archive_store.dart';
import 'ziwei/ziwei_models.dart';

enum RoomChartKind {
  bazi('bazi', '八字'),
  ziwei('ziwei', '紫微斗数'),
  qizheng('qizheng', '七政四余'),
  astrology('astrology', '星盘');

  const RoomChartKind(this.code, this.label);
  final String code;
  final String label;

  static RoomChartKind fromCode(String? code) => values.firstWhere(
        (value) => value.code == code,
        orElse: () => RoomChartKind.bazi,
      );
}

class RoomChartArchive {
  const RoomChartArchive({
    required this.id,
    required this.kind,
    required this.name,
    required this.subtitle,
    required this.snapshot,
    this.unavailableReason,
  });

  final String id;
  final RoomChartKind kind;
  final String name;
  final String subtitle;
  final Map<String, dynamic> snapshot;
  final String? unavailableReason;
}

/// 四种命盘共同使用的“人物案例”。
///
/// 旧版本仍各自保留原始档案；这里按明确出生资料做非破坏性合并，避免升级后
/// 丢失笔记或把同名但不是同一个人的档案误合并。
class RoomChartCase {
  const RoomChartCase({
    required this.id,
    required this.createdAt,
    required this.name,
    required this.isSelf,
    required this.relationship,
    required this.birthDateTime,
    required this.calendarTypeIndex,
    required this.snapshots,
    this.isFemale,
    this.birthPlace = '',
    this.longitude,
    this.latitude,
    this.timezone = 'Asia/Shanghai',
    this.houseSystem = 'P',
    this.ziweiSettings,
  });

  final String id;
  final DateTime createdAt;
  final String name;
  final bool isSelf;
  final String relationship;
  final DateTime birthDateTime;
  final bool? isFemale;
  final int calendarTypeIndex;
  final String birthPlace;
  final double? longitude;
  final double? latitude;
  final String timezone;
  final String houseSystem;
  final ZiweiSettings? ziweiSettings;
  final Map<RoomChartKind, Map<String, dynamic>> snapshots;

  Iterable<String> get sourceKeys => snapshots.entries.map(
        (entry) => '${entry.key.code}:${entry.value['id']}',
      );

  RoomChartCase withDetails(Map<String, dynamic> details) {
    final detailName = details['name']?.toString().trim() ?? '';
    final detailRelationship = details['relationship']?.toString().trim() ?? '';
    return RoomChartCase(
      id: id,
      createdAt: createdAt,
      name: detailName.isEmpty ? name : detailName,
      isSelf: isSelf,
      relationship: isSelf || detailRelationship.isEmpty
          ? relationship
          : detailRelationship,
      birthDateTime: birthDateTime,
      calendarTypeIndex: calendarTypeIndex,
      snapshots: snapshots,
      isFemale: isFemale ?? details['isFemale'] as bool?,
      birthPlace: birthPlace.isEmpty
          ? details['birthPlace']?.toString() ?? ''
          : birthPlace,
      longitude: longitude ?? (details['longitude'] as num?)?.toDouble(),
      latitude: latitude ?? (details['latitude'] as num?)?.toDouble(),
      timezone: timezone,
      houseSystem: houseSystem,
      ziweiSettings: ziweiSettings,
    );
  }

  String get subtitle {
    final value = birthDateTime;
    final date = '${value.year.toString().padLeft(4, '0')}年'
        '${value.month.toString().padLeft(2, '0')}月'
        '${value.day.toString().padLeft(2, '0')}日 '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    final gender = isFemale == null ? '' : (isFemale! ? '女' : '男');
    return gender.isEmpty ? date : '$date · $gender';
  }

  RoomChartArchive archiveFor(RoomChartKind kind) {
    final stored = snapshots[kind];
    if (stored != null) {
      return RoomChartArchive(
        id: id,
        kind: kind,
        name: name,
        subtitle: subtitle,
        snapshot: _normalizedStoredSnapshot(kind, stored),
      );
    }

    final generated = _generatedSnapshot(kind);
    return RoomChartArchive(
      id: id,
      kind: kind,
      name: name,
      subtitle: generated.reason ?? subtitle,
      snapshot: generated.snapshot,
      unavailableReason: generated.reason,
    );
  }

  Map<String, dynamic> _normalizedStoredSnapshot(
    RoomChartKind kind,
    Map<String, dynamic> stored,
  ) {
    final value = Map<String, dynamic>.from(stored);
    switch (kind) {
      case RoomChartKind.bazi:
        value['displayName'] = name;
        value['relationship'] = relationship;
      case RoomChartKind.ziwei:
        final profile = value['profile'];
        if (profile is Map) {
          value['profile'] = <String, dynamic>{
            ...Map<String, dynamic>.from(profile),
            'name': name,
          };
        }
        value['relationship'] = relationship;
      case RoomChartKind.qizheng || RoomChartKind.astrology:
        final profile = value['profile'];
        if (profile is Map) {
          value['profile'] = <String, dynamic>{
            ...Map<String, dynamic>.from(profile),
            'name': name,
            if (isFemale != null) 'isFemale': isFemale,
          };
        }
    }
    return value;
  }

  _GeneratedSnapshot _generatedSnapshot(RoomChartKind kind) {
    final generatedId = 'shared-case-$id-${kind.code}';
    switch (kind) {
      case RoomChartKind.bazi:
        if (isFemale == null) {
          return const _GeneratedSnapshot.unavailable('此案例缺少性别，请补充后查看八字盘');
        }
        final result = computeBaziResult(birthDateTime, isFemale: isFemale!);
        return _GeneratedSnapshot(
          PaipanRecord(
            id: generatedId,
            createdAt: createdAt,
            displayName: name,
            isSelf: isSelf,
            relationship: relationship,
            birthDateTime: birthDateTime,
            isFemale: isFemale!,
            calendarTypeIndex: calendarTypeIndex,
            birthPlace: birthPlace.isEmpty
                ? null
                : Region.placeholder(
                    name: birthPlace,
                    extPath: birthPlace,
                    lng: longitude,
                    lat: latitude,
                  ),
            summary: result.fourPillarsStr,
          ).toJson(),
        );
      case RoomChartKind.ziwei:
        if (isFemale == null) {
          return const _GeneratedSnapshot.unavailable('此案例缺少性别，请补充后查看斗数盘');
        }
        final profile = ZiweiProfile(
          name: name,
          gender: isFemale! ? '女' : '男',
          clockBirthDate: birthDateTime,
          effectiveBirthDate: birthDateTime,
          calendarTypeIndex: calendarTypeIndex,
          settings: ziweiSettings ?? const ZiweiSettings(),
          birthPlace: birthPlace.isEmpty ? null : birthPlace,
          longitude: longitude,
          latitude: latitude,
        );
        return _GeneratedSnapshot(
          ZiweiArchiveRecord(
            id: generatedId,
            createdAt: createdAt,
            profile: profile,
            isSelf: isSelf,
            relationship: relationship,
          ).toJson(),
        );
      case RoomChartKind.qizheng:
        if (birthPlace.isEmpty || longitude == null || latitude == null) {
          return const _GeneratedSnapshot.unavailable(
            '此案例缺少出生地经纬度，请补充后查看七政四余盘',
          );
        }
        return _GeneratedSnapshot(
          QizhengArchiveRecord(
            id: generatedId,
            createdAt: createdAt,
            profile: QizhengProfile(
              name: name,
              birthDateTime: birthDateTime,
              birthPlace: birthPlace,
              longitude: longitude!,
              latitude: latitude!,
              isFemale: isFemale,
              timezone: timezone,
            ),
            isSelf: isSelf,
          ).toJson(),
        );
      case RoomChartKind.astrology:
        if (birthPlace.isEmpty || longitude == null || latitude == null) {
          return const _GeneratedSnapshot.unavailable('此案例缺少出生地经纬度，请补充后查看星盘');
        }
        return _GeneratedSnapshot(
          AstrologyArchiveRecord(
            id: generatedId,
            createdAt: createdAt,
            profile: AstrologyProfile(
              name: name,
              birthDateTime: birthDateTime,
              birthPlace: birthPlace,
              longitude: longitude!,
              latitude: latitude!,
              isFemale: isFemale,
              timezone: timezone,
              houseSystem: houseSystem,
            ),
            isSelf: isSelf,
          ).toJson(),
        );
    }
  }
}

class _GeneratedSnapshot {
  const _GeneratedSnapshot(this.snapshot) : reason = null;
  const _GeneratedSnapshot.unavailable(this.reason)
      : snapshot = const <String, dynamic>{};

  final Map<String, dynamic> snapshot;
  final String? reason;
}

class _RoomChartCaseBuilder {
  _RoomChartCaseBuilder({
    required this.id,
    required this.createdAt,
    required this.name,
    required this.isSelf,
    required this.relationship,
    required this.birthDateTime,
    required this.calendarTypeIndex,
    required this.isFemale,
    required this.birthPlace,
    required this.longitude,
    required this.latitude,
    required this.timezone,
    required this.houseSystem,
    required this.ziweiSettings,
  });

  final String id;
  DateTime createdAt;
  String name;
  final bool isSelf;
  String relationship;
  DateTime birthDateTime;
  int calendarTypeIndex;
  bool? isFemale;
  String birthPlace;
  double? longitude;
  double? latitude;
  String timezone;
  String houseSystem;
  ZiweiSettings? ziweiSettings;
  final Map<RoomChartKind, Map<String, dynamic>> snapshots = {};

  RoomChartCase build() => RoomChartCase(
        id: id,
        createdAt: createdAt,
        name: name,
        isSelf: isSelf,
        relationship: relationship,
        birthDateTime: birthDateTime,
        calendarTypeIndex: calendarTypeIndex,
        snapshots: Map.unmodifiable(snapshots),
        isFemale: isFemale,
        birthPlace: birthPlace,
        longitude: longitude,
        latitude: latitude,
        timezone: timezone,
        houseSystem: houseSystem,
        ziweiSettings: ziweiSettings,
      );
}

Future<List<RoomChartCase>> loadRoomChartCases() async {
  final loaded = await Future.wait<dynamic>([
    PaipanRecordStore.loadAll(),
    ZiweiArchiveStore.loadAll(),
    QizhengArchiveStore.loadAll(),
    AstrologyArchiveStore.loadAll(),
  ]);
  final cases = <String, List<_RoomChartCaseBuilder>>{};
  final details = await RoomChartCaseDetailsStore.load();

  String safeName(bool self, String value) =>
      self ? '我的命盘' : (value.trim().isEmpty ? '未命名案例' : value.trim());
  String identity(bool self, String value, DateTime birth) {
    final normalized =
        value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return '${self ? 'self' : normalized}|${birth.toIso8601String()}';
  }

  _RoomChartCaseBuilder upsert({
    required RoomChartKind kind,
    required String sourceId,
    required DateTime createdAt,
    required String name,
    required bool isSelf,
    required String relationship,
    required DateTime birthDateTime,
    required int calendarTypeIndex,
    bool? isFemale,
    String birthPlace = '',
    double? longitude,
    double? latitude,
    String timezone = 'Asia/Shanghai',
    String houseSystem = 'P',
    ZiweiSettings? ziweiSettings,
  }) {
    final extra = details['${kind.code}:$sourceId'];
    if (extra is Map) {
      final detailName = extra['name']?.toString().trim() ?? '';
      final detailRelationship = extra['relationship']?.toString().trim() ?? '';
      if (detailName.isNotEmpty) name = detailName;
      if (!isSelf && detailRelationship.isNotEmpty) {
        relationship = detailRelationship;
      }
      isFemale ??= extra['isFemale'] as bool?;
      longitude ??= (extra['longitude'] as num?)?.toDouble();
      latitude ??= (extra['latitude'] as num?)?.toDouble();
      if (birthPlace.isEmpty) {
        birthPlace = extra['birthPlace']?.toString() ?? '';
      }
    }
    final key = identity(isSelf, name, birthDateTime);
    final group = cases.putIfAbsent(key, () => []);
    final matches = group
        .where(
          (candidate) =>
              !candidate.snapshots.containsKey(kind) &&
              (isFemale == null ||
                  candidate.isFemale == null ||
                  candidate.isFemale == isFemale) &&
              (longitude == null ||
                  candidate.longitude == null ||
                  (candidate.longitude! - longitude).abs() < 0.000001) &&
              (latitude == null ||
                  candidate.latitude == null ||
                  (candidate.latitude! - latitude).abs() < 0.000001) &&
              candidate.timezone == timezone,
        )
        .toList();
    // 信息冲突或有多个同名候选时不猜测归属，避免把另一人的盘面/笔记覆盖。
    final existing = matches.length == 1 ? matches.single : null;
    if (existing == null) {
      final fresh = _RoomChartCaseBuilder(
        id: '$key|${kind.code}|$sourceId',
        createdAt: createdAt,
        name: safeName(isSelf, name),
        isSelf: isSelf,
        relationship: relationship,
        birthDateTime: birthDateTime,
        calendarTypeIndex: calendarTypeIndex,
        isFemale: isFemale,
        birthPlace: birthPlace.trim(),
        longitude: longitude,
        latitude: latitude,
        timezone: timezone,
        houseSystem: houseSystem,
        ziweiSettings: ziweiSettings,
      );
      group.add(fresh);
      return fresh;
    }
    if (createdAt.isAfter(existing.createdAt)) existing.createdAt = createdAt;
    if (!isSelf && existing.name == '未命名案例' && name.trim().isNotEmpty) {
      existing.name = name.trim();
    }
    existing.isFemale ??= isFemale;
    if (existing.birthPlace.isEmpty && birthPlace.trim().isNotEmpty) {
      existing.birthPlace = birthPlace.trim();
    }
    existing.longitude ??= longitude;
    existing.latitude ??= latitude;
    if (existing.timezone == 'Asia/Shanghai' && timezone != existing.timezone) {
      existing.timezone = timezone;
    }
    if (existing.houseSystem == 'P' && houseSystem != existing.houseSystem) {
      existing.houseSystem = houseSystem;
    }
    existing.ziweiSettings ??= ziweiSettings;
    return existing;
  }

  for (final record in loaded[0] as List<PaipanRecord>) {
    final place = record.birthPlace;
    upsert(
      kind: RoomChartKind.bazi,
      sourceId: record.id,
      createdAt: record.createdAt,
      name: record.displayName,
      isSelf: record.isSelf,
      relationship: record.relationship,
      birthDateTime: record.birthDateTime,
      calendarTypeIndex: record.calendarTypeIndex,
      isFemale: record.isFemale,
      birthPlace: place?.extPath ?? place?.name ?? '',
      longitude: place?.lng,
      latitude: place?.lat,
    ).snapshots[RoomChartKind.bazi] = record.toJson();
  }
  for (final record in loaded[1] as List<ZiweiArchiveRecord>) {
    final profile = record.profile;
    upsert(
      kind: RoomChartKind.ziwei,
      sourceId: record.id,
      createdAt: record.createdAt,
      name: profile.name,
      isSelf: record.isSelf,
      relationship: record.relationship,
      birthDateTime: profile.clockBirthDate,
      calendarTypeIndex: profile.calendarTypeIndex,
      isFemale: profile.gender == '女',
      birthPlace: profile.birthPlace ?? '',
      longitude: profile.longitude,
      latitude: profile.latitude,
      ziweiSettings: profile.settings,
    ).snapshots[RoomChartKind.ziwei] = record.toJson();
  }
  for (final record in loaded[2] as List<QizhengArchiveRecord>) {
    final profile = record.profile;
    upsert(
      kind: RoomChartKind.qizheng,
      sourceId: record.id,
      createdAt: record.createdAt,
      name: profile.name,
      isSelf: record.isSelf,
      relationship:
          record.isSelf ? ArchiveRelationship.self : ArchiveRelationship.other,
      birthDateTime: profile.birthDateTime,
      calendarTypeIndex: 0,
      isFemale: profile.isFemale,
      birthPlace: profile.birthPlace,
      longitude: profile.longitude,
      latitude: profile.latitude,
      timezone: profile.timezone,
    ).snapshots[RoomChartKind.qizheng] = record.toJson();
  }
  for (final record in loaded[3] as List<AstrologyArchiveRecord>) {
    final profile = record.profile;
    upsert(
      kind: RoomChartKind.astrology,
      sourceId: record.id,
      createdAt: record.createdAt,
      name: profile.name,
      isSelf: record.isSelf,
      relationship:
          record.isSelf ? ArchiveRelationship.self : ArchiveRelationship.other,
      birthDateTime: profile.birthDateTime,
      calendarTypeIndex: 0,
      isFemale: profile.isFemale,
      birthPlace: profile.birthPlace,
      longitude: profile.longitude,
      latitude: profile.latitude,
      timezone: profile.timezone,
      houseSystem: profile.houseSystem,
    ).snapshots[RoomChartKind.astrology] = record.toJson();
  }

  final result = cases.values.expand((group) => group).map((item) {
    var record = item.build();
    for (final key in record.sourceKeys) {
      final extra = details[key];
      if (extra is Map) {
        record = record.withDetails(Map<String, dynamic>.from(extra));
      }
    }
    return record;
  }).toList();
  result.sort((a, b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return result;
}

Future<List<RoomChartArchive>> loadRoomChartArchives() async {
  final cases = await loadRoomChartCases();
  return [
    for (final kind in RoomChartKind.values)
      for (final item in cases)
        if (item.snapshots.containsKey(kind)) item.archiveFor(kind),
  ];
}

Future<void> updateRoomChartCaseIdentity(
  RoomChartCase record, {
  required String displayName,
  required String relationship,
}) async {
  final userId = await ArchiveAccountScope.currentUserId();
  if (userId == null) throw StateError('登录状态已失效，请重新登录');
  await RoomChartCaseDetailsStore.save(
      record.sourceKeys,
      <String, dynamic>{
        'name': displayName.trim(),
        'relationship': relationship,
      },
      expectedUserId: userId);
}

Future<void> deleteRoomChartCase(RoomChartCase record) async {
  final userId = await ArchiveAccountScope.currentUserId();
  if (userId == null) throw StateError('登录状态已失效，请重新登录');
  for (final entry in record.snapshots.entries) {
    final id = entry.value['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    switch (entry.key) {
      case RoomChartKind.bazi:
        await PaipanRecordStore.delete(id, expectedUserId: userId);
      case RoomChartKind.ziwei:
        await ZiweiArchiveStore.delete(id, expectedUserId: userId);
      case RoomChartKind.qizheng:
        await QizhengArchiveStore.delete(id, expectedUserId: userId);
      case RoomChartKind.astrology:
        await AstrologyArchiveStore.delete(id, expectedUserId: userId);
    }
  }
  await RoomChartCaseDetailsStore.delete(
    record.sourceKeys,
    expectedUserId: userId,
  );
}

/// Keep notebook edits on actual source records so all chart archive lists agree.
Future<void> updateRoomChartCaseNotes(
  RoomChartCase record, {
  required String caseTitle,
  required String reasoningNotes,
  required String commentary,
  required int expectedUserId,
}) async {
  for (final entry in record.snapshots.entries) {
    if (await ArchiveAccountScope.currentUserId() != expectedUserId) {
      throw StateError('账号已变更，请重新打开档案');
    }
    final id = entry.value['id']?.toString() ?? '';
    switch (entry.key) {
      case RoomChartKind.bazi:
        await PaipanRecordStore.saveCase(
            recordId: id,
            fallback: PaipanRecord.fromJson(entry.value),
            caseTitle: caseTitle,
            reasoningNotes: reasoningNotes,
            commentary: commentary,
            expectedUserId: expectedUserId);
      case RoomChartKind.ziwei:
        await ZiweiArchiveStore.saveCase(
            fallback: ZiweiArchiveRecord.fromJson(entry.value),
            caseTitle: caseTitle,
            reasoningNotes: reasoningNotes,
            commentary: commentary,
            expectedUserId: expectedUserId);
      case RoomChartKind.astrology:
        await AstrologyArchiveStore.updateCase(id,
            caseTitle: caseTitle,
            reasoningNotes: reasoningNotes,
            commentary: commentary,
            expectedUserId: expectedUserId);
      case RoomChartKind.qizheng:
        await QizhengArchiveStore.updateCase(id,
            caseTitle: caseTitle,
            reasoningNotes: reasoningNotes,
            commentary: commentary,
            expectedUserId: expectedUserId);
    }
  }
}
