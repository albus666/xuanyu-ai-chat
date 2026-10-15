import 'dart:async';
import '../../core/local/archive_cloud_sync.dart';
import 'room_shared_chart.dart';
import 'package:flutter/material.dart';

import '../../core/local/paipan_record_store.dart';
import '../../core/local/archive_account_scope.dart';
import 'room_chart_case_details.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../fortune/archive_relationship.dart';
import '../fortune/astrology/astrology_archive_store.dart';
import '../fortune/astrology/astrology_models.dart';
import '../fortune/astrology/astrology_page.dart';
import '../fortune/astrology/astrology_service.dart';
import '../fortune/bazi_input_page.dart';
import '../fortune/paipan/models/paipan_record.dart';
import '../fortune/paipan/models/region.dart';
import '../fortune/paipan/paipan_detail_chart_tab.dart';
import '../fortune/paipan/utils/bazi_result.dart';
import '../fortune/qizheng/qizheng_archive_store.dart';
import '../fortune/qizheng/qizheng_models.dart';
import '../fortune/qizheng/qizheng_page.dart';
import '../fortune/qizheng/qizheng_service.dart';
import '../fortune/ziwei/ziwei_archive_store.dart';
import '../fortune/ziwei/ziwei_chart_page.dart';
import '../fortune/ziwei/ziwei_input_page.dart';
import '../fortune/ziwei/ziwei_models.dart';
import '../fortune/ziwei/ziwei_service.dart';

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

  RoomChartCase withDetails(Map<String, dynamic> details) => RoomChartCase(
        id: id,
        createdAt: createdAt,
        name: name,
        isSelf: isSelf,
        relationship: relationship,
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
      final normalized = Map<String, dynamic>.from(stored);
      switch (kind) {
        case RoomChartKind.bazi:
          normalized['displayName'] = name;
          normalized['relationship'] = relationship;
        case RoomChartKind.ziwei:
          final profile = normalized['profile'];
          if (profile is Map) {
            normalized['profile'] = <String, dynamic>{
              ...Map<String, dynamic>.from(profile),
              'name': name,
            };
          }
          normalized['relationship'] = relationship;
        case RoomChartKind.qizheng || RoomChartKind.astrology:
          final profile = normalized['profile'];
          if (profile is Map) {
            normalized['profile'] = <String, dynamic>{
              ...Map<String, dynamic>.from(profile),
              'name': name,
              if (isFemale != null) 'isFemale': isFemale,
            };
          }
      }
      return RoomChartArchive(
        id: id,
        kind: kind,
        name: name,
        subtitle: subtitle,
        snapshot: normalized,
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

  _GeneratedSnapshot _generatedSnapshot(RoomChartKind kind) {
    final generatedId = 'room-case-$id-${kind.code}';
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
        isFemale: isFemale,
        calendarTypeIndex: calendarTypeIndex,
        birthPlace: birthPlace,
        longitude: longitude,
        latitude: latitude,
        timezone: timezone,
        houseSystem: houseSystem,
        ziweiSettings: ziweiSettings,
        snapshots: Map.unmodifiable(snapshots),
      );
}

class RoomChartShare {
  const RoomChartShare({
    required this.id,
    required this.kind,
    required this.ownerNickname,
    required this.displayName,
    required this.scope,
    required this.recipientUserIds,
    required this.allowSaveCopy,
    required this.canManage,
    required this.snapshot,
  });

  factory RoomChartShare.fromJson(Map<String, dynamic> json) => RoomChartShare(
        id: (json['id'] as num?)?.toInt() ?? 0,
        kind: RoomChartKind.fromCode(json['chartType']?.toString()),
        ownerNickname: json['ownerNickname']?.toString() ?? '房间成员',
        displayName: json['displayName']?.toString() ?? '命盘',
        scope: json['scope']?.toString() ?? 'self',
        recipientUserIds: (json['recipientUserIds'] as List?)
                ?.whereType<num>()
                .map((value) => value.toInt())
                .toList() ??
            const <int>[],
        allowSaveCopy: json['allowSaveCopy'] == true,
        canManage: json['canManage'] == true,
        snapshot: json['snapshot'] is Map
            ? Map<String, dynamic>.from(json['snapshot'] as Map)
            : const <String, dynamic>{},
      );

  final int id;
  final RoomChartKind kind;
  final String ownerNickname;
  final String displayName;
  final String scope;
  final List<int> recipientUserIds;
  final bool allowSaveCopy;
  final bool canManage;
  final Map<String, dynamic> snapshot;
}

class _RoomChartRequestFailure implements Exception {
  const _RoomChartRequestFailure(this.message);
  final String message;
}

Map<String, dynamic> _roomChartResponseData(dynamic body) {
  if (body is! Map) throw const _RoomChartRequestFailure('返回数据异常，请重试');
  if (body['code'] != 0) {
    throw _RoomChartRequestFailure(body['message']?.toString() ?? '操作失败，请重试');
  }
  final data = body['data'];
  if (data == null) return <String, dynamic>{};
  if (data is! Map) throw const _RoomChartRequestFailure('返回数据异常，请重试');
  return Map<String, dynamic>.from(data);
}

String _roomChartFailureMessage(Object error, String fallback) =>
    error is _RoomChartRequestFailure
        ? error.message
        : apiSessionFailureMessage(error, fallback);

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
  result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

Future<void> showRoomChartSheet(
  BuildContext context, {
  required int roomId,
  required List<Map<String, dynamic>> members,
  Future<List<RoomChartCase>> Function()? caseLoader,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RoomChartSheet(
      roomId: roomId,
      members: members,
      caseLoader: caseLoader,
    ),
  );
}

Future<void> showRoomChartSnapshot(
  BuildContext context, {
  required RoomChartKind kind,
  required Map<String, dynamic> snapshot,
  required String title,
}) async {
  final session = ApiSessionScope();
  if (snapshot['professionalChart'] is Map) {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _RoomChartSessionBoundary(
            session: session,
            child:
                _RedactedChart(kind: kind, title: title, snapshot: snapshot)));
    return;
  }
  try {
    switch (kind) {
      case RoomChartKind.bazi:
        final birth = DateTime.tryParse(
          snapshot['birthDateTime']?.toString() ?? '',
        );
        if (birth == null) throw const FormatException();
        final record = PaipanRecord.fromJson(snapshot);
        final result = computeBaziResult(
          record.birthDateTime,
          isFemale: record.isFemale,
        );
        if (!context.mounted || !session.current) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _RoomChartSessionBoundary(
              session: session,
              child: FractionallySizedBox(
                heightFactor: .9,
                child: Material(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _ChartHeader(title: title, label: '八字专业盘'),
                      Expanded(
                        child: PaipanDetailChartTab(
                          result: result,
                          isFemale: record.isFemale,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        );
      case RoomChartKind.ziwei:
        final record = ZiweiArchiveRecord.fromJson(snapshot);
        final now = DateTime.now();
        final data = await ZiweiService.calculate(
          profile: record.profile,
          targetDate: now,
          targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
        );
        if (!context.mounted || !session.current) return;
        await _showProfessionalChartSheet(
          context,
          ZiweiChartPage(
            profile: record.profile,
            initialData: data,
            initialTargetDate: now,
            initialTargetTimeIndex: ZiweiProfile.timeIndexFor(now.hour),
            archiveRecord: record,
            professionalOnly: true,
          ),
        );
      case RoomChartKind.qizheng:
        final record = QizhengArchiveRecord.fromJson(snapshot);
        final chart = await QizhengService.calculate(record.profile);
        if (!context.mounted || !session.current) return;
        await _showProfessionalChartSheet(
          context,
          QizhengChartPage(
            profile: record.profile,
            chart: chart,
            record: record,
            isSelf: record.isSelf,
            professionalOnly: true,
          ),
        );
      case RoomChartKind.astrology:
        final record = AstrologyArchiveRecord.fromJson(snapshot);
        final chart = await AstrologyService.calculate(record.profile);
        if (!context.mounted || !session.current) return;
        await _showProfessionalChartSheet(
          context,
          AstrologyChartPage(
            profile: record.profile,
            chart: chart,
            record: record,
            isSelf: record.isSelf,
            professionalOnly: true,
          ),
        );
    }
  } catch (_) {
    if (!context.mounted || !session.current) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _RoomChartSessionBoundary(
          session: session,
          child: _RedactedChart(kind: kind, title: title, snapshot: snapshot)),
    );
  }
}

Future<void> _showProfessionalChartSheet(
  BuildContext context,
  Widget chart,
) async {
  final session = ApiSessionScope();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomChartSessionBoundary(
        session: session,
        child: FractionallySizedBox(
          heightFactor: .9,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: chart,
          ),
        )),
  );
}

class RoomChartSheet extends StatefulWidget {
  const RoomChartSheet({
    super.key,
    required this.roomId,
    required this.members,
    this.caseLoader,
    this.onChooseArchive,
  });
  final void Function(RoomChartArchive archive)? onChooseArchive;
  final int roomId;
  final List<Map<String, dynamic>> members;
  final Future<List<RoomChartCase>> Function()? caseLoader;

  @override
  State<RoomChartSheet> createState() => _RoomChartSheetState();
}

class _RoomChartSheetState extends State<RoomChartSheet> {
  final _scope = ApiSessionScope();
  RoomChartKind _kind = RoomChartKind.bazi;
  List<RoomChartCase> _cases = const [];
  List<RoomChartShare> _shares = const [];
  String? _selectedId;
  bool _loading = true;
  bool _publishing = false;
  bool _sharesLoading = true;
  String? _sharesError;
  final Set<int> _revokingIds = <int>{};
  final Set<int> _savingShareIds = <int>{};
  int _caseGeneration = 0;
  int _shareGeneration = 0;

  List<RoomChartArchive> get _current =>
      _cases.map((item) => item.archiveFor(_kind)).toList();
  RoomChartArchive? get _selected =>
      _current.cast<RoomChartArchive?>().firstWhere(
            (item) => item?.id == _selectedId,
            orElse: () => _current.isEmpty ? null : _current.first,
          );

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    ArchiveCloudSync.changes.addListener(_onArchiveChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    ArchiveCloudSync.changes.removeListener(_onArchiveChanged);
    _caseGeneration++;
    _shareGeneration++;
    super.dispose();
  }

  bool get _active => mounted && _scope.current;

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    _caseGeneration++;
    _shareGeneration++;
    setState(() {
      _cases = const [];
      _shares = const [];
      _selectedId = null;
      _loading = false;
      _publishing = false;
      _sharesLoading = false;
      _sharesError = null;
      _revokingIds.clear();
      _savingShareIds.clear();
    });
  }

  Future<void> _load() async {
    if (!_active) return;
    setState(() => _loading = true);
    await _refreshCases();
    if (_active) setState(() => _loading = false);
    await _refreshShares();
  }

  Future<void> _refreshCases({bool selectNewest = false}) async {
    final generation = ++_caseGeneration;
    try {
      final cases = await (widget.caseLoader?.call() ?? loadRoomChartCases());
      if (!_active || generation != _caseGeneration) return;
      setState(() {
        _cases = cases;
        if (selectNewest || !_cases.any((item) => item.id == _selectedId)) {
          _selectedId = _cases.firstOrNull?.id;
        }
      });
    } catch (_) {
      if (!mounted || !_scope.current || generation != _caseGeneration) return;
      showAppToast(context, '案例记录加载失败');
    }
  }

  Future<void> _refreshShares() async {
    if (!_active || widget.onChooseArchive != null) return;
    final generation = ++_shareGeneration;
    setState(() {
      _sharesLoading = true;
      _sharesError = null;
    });
    try {
      final response = await _scope.get(
        '/api/consultation/rooms/${widget.roomId}/chart-shares',
      );
      final raw = _roomChartResponseData(response.data);
      final list = raw['list'];
      if (list is! List) {
        throw const _RoomChartRequestFailure('房间命盘数据异常，请重试');
      }
      if (!_active || generation != _shareGeneration) return;
      setState(() {
        _shares = list
            .whereType<Map>()
            .map(
              (item) =>
                  RoomChartShare.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      });
    } catch (error) {
      if (!mounted || !_scope.current || generation != _shareGeneration) return;
      setState(
          () => _sharesError = _roomChartFailureMessage(error, '房间命盘加载失败'));
    } finally {
      if (_active && generation == _shareGeneration) {
        setState(() => _sharesLoading = false);
      }
    }
  }

  void _onArchiveChanged() {
    if (_active) unawaited(_refreshCases(selectNewest: true));
  }

  Future<void> _createCase() async {
    if (!_active) return;
    final route = switch (_kind) {
      RoomChartKind.bazi => MaterialPageRoute<void>(
          builder: (_) =>
              const BaziInputPage(forOther: true, replaceInputWithResult: true),
        ),
      RoomChartKind.ziwei => MaterialPageRoute<void>(
          builder: (_) => const ZiweiInputPage(
            loadAccountProfile: false,
            forOther: true,
            professionalOnlyResult: true,
          ),
        ),
      RoomChartKind.qizheng => MaterialPageRoute<void>(
          builder: (_) => const QizhengInputPage(professionalOnlyResult: true),
        ),
      RoomChartKind.astrology => MaterialPageRoute<void>(
          builder: (_) =>
              const AstrologyInputPage(professionalOnlyResult: true),
        ),
    };
    await Navigator.of(context).push(route);
    if (!_active) return;
    await _refreshCases(selectNewest: true);
  }

  Future<void> _openCase(RoomChartArchive archive) async {
    if (!_active) return;
    setState(() => _selectedId = archive.id);
    if (archive.unavailableReason != null) {
      final record = _cases.firstWhere((item) => item.id == archive.id);
      final userId = await ArchiveAccountScope.currentUserId();
      if (!mounted || !_scope.current || userId == null) return;
      final hasPlace = record.birthPlace.isNotEmpty &&
          record.longitude != null &&
          record.latitude != null;
      final details = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => RoomChartCaseDetailsDialog(
          isFemale: record.isFemale,
          place: hasPlace
              ? Region.placeholder(
                  name: record.birthPlace,
                  extPath: record.birthPlace,
                  lng: record.longitude,
                  lat: record.latitude,
                )
              : null,
        ),
      );
      if (!mounted || !_scope.current || details == null) return;
      try {
        await RoomChartCaseDetailsStore.save(
          record.sourceKeys,
          details,
          expectedUserId: userId,
        );
        await _refreshCases();
        if (!_active) return;
        final sourceKeys = record.sourceKeys.toSet();
        final completed = _cases
            .firstWhere((item) => item.sourceKeys.any(sourceKeys.contains))
            .archiveFor(archive.kind);
        if (completed.unavailableReason == null) await _openCase(completed);
      } catch (_) {
        if (!mounted || !_scope.current) return;
        showAppToast(context, '资料保存失败，请重试');
      }
      return;
    }
    await showRoomChartSnapshot(
      context,
      kind: archive.kind,
      snapshot: archive.snapshot,
      title: archive.name,
    );
  }

  Future<void> _publish() async {
    if (_publishing || !_active) return;
    final archive = _selected;
    if (archive == null) {
      showAppToast(context, '请先新增或选择一个案例');
      return;
    }
    if (archive.unavailableReason != null) {
      showAppToast(context, archive.unavailableReason!);
      return;
    }
    if (widget.onChooseArchive != null) {
      widget.onChooseArchive!(archive);
      return;
    }
    final settings = await showModalBottomSheet<_PublishSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PublishSheet(members: widget.members, scope: _scope),
    );
    if (settings == null || !_active) return;
    setState(() => _publishing = true);
    try {
      final fullSnapshot =
          await buildRoomProfessionalSnapshot(archive.kind, archive.snapshot);
      if (!_active) return;
      final response = await _scope.post(
        '/api/consultation/rooms/${widget.roomId}/chart-shares',
        data: {
          'chartType': archive.kind.code,
          'displayName': archive.name,
          'snapshot': fullSnapshot,
          'scope': settings.scope,
          'recipientUserIds': settings.recipientIds,
          'displayBirthData': settings.displayBirthData,
          'allowSaveCopy': settings.allowSaveCopy,
          'expiresMinutes': 1440,
        },
      );
      _roomChartResponseData(response.data);
      if (!mounted || !_scope.current) return;
      showAppToast(context, settings.scope == 'self' ? '命盘仅自己可见' : '命盘已发布');
      await _load();
    } catch (error) {
      if (!mounted || !_scope.current) return;
      showAppToast(context, _roomChartFailureMessage(error, '命盘发布失败'));
    } finally {
      if (_active) setState(() => _publishing = false);
    }
  }

  Future<void> _revoke(RoomChartShare share) async {
    if (!_active || _revokingIds.contains(share.id)) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (_, __, ___) => !_scope.current
            ? AlertDialog(
                content: const Text(apiSessionChangedMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('关闭'),
                  )
                ],
              )
            : AlertDialog(
                title: const Text('撤回房间命盘？'),
                content: Text('撤回后，已获得查看权限的成员将无法继续打开「${share.displayName}」。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认撤回'),
                  ),
                ],
              ),
      ),
    );
    if (yes != true || !_active) return;
    setState(() => _revokingIds.add(share.id));
    try {
      final response = await _scope.delete(
        '/api/consultation/rooms/${widget.roomId}/chart-shares/${share.id}',
      );
      _roomChartResponseData(response.data);
      if (!mounted || !_scope.current) return;
      ++_shareGeneration;
      setState(() =>
          _shares = _shares.where((item) => item.id != share.id).toList());
      showAppToast(context, '命盘已撤回');
      await _load();
    } catch (error) {
      if (!mounted || !_scope.current) return;
      showAppToast(context, _roomChartFailureMessage(error, '撤回失败'));
    } finally {
      if (_active) setState(() => _revokingIds.remove(share.id));
    }
  }

  Future<void> _saveCopy(RoomChartShare share) async {
    if (!_active || !share.allowSaveCopy || _savingShareIds.isNotEmpty) return;
    setState(() => _savingShareIds.add(share.id));
    try {
      final expectedUserId = await ArchiveAccountScope.currentUserId();
      if (!_active || expectedUserId == null) return;
      final response = await _scope.post(
          '/api/consultation/rooms/${widget.roomId}/chart-shares/${share.id}/copy');
      final raw = _roomChartResponseData(response.data)['snapshot'];
      if (raw is! Map) throw const FormatException();
      final snapshot = Map<String, dynamic>.from(raw);
      if (!_active) return;
      switch (share.kind) {
        case RoomChartKind.bazi:
          final birth = DateTime.tryParse(
            snapshot['birthDateTime']?.toString() ?? '',
          );
          if (birth == null) throw const FormatException();
          final source = PaipanRecord.fromJson(snapshot);
          await PaipanRecordStore.save(
            PaipanRecord(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              createdAt: DateTime.now(),
              displayName: '${share.displayName}（副本）',
              relationship: ArchiveRelationship.other,
              birthDateTime: birth,
              isFemale: source.isFemale,
              calendarTypeIndex: source.calendarTypeIndex,
              birthPlace: source.birthPlace,
              summary: source.summary,
            ),
            expectedUserId: expectedUserId,
          );
        case RoomChartKind.ziwei:
          final source = ZiweiArchiveRecord.fromJson(snapshot);
          await ZiweiArchiveStore.save(
            source.profile.copyWith(name: '${share.displayName}（副本）'),
            isSelf: false,
            relationship: ArchiveRelationship.other,
            expectedUserId: expectedUserId,
          );
        case RoomChartKind.qizheng:
          final source = QizhengArchiveRecord.fromJson(snapshot);
          await QizhengArchiveStore.save(
            QizhengProfile(
              name: '${share.displayName}（副本）',
              birthDateTime: source.profile.birthDateTime,
              birthPlace: source.profile.birthPlace,
              longitude: source.profile.longitude,
              latitude: source.profile.latitude,
              isFemale: source.profile.isFemale,
              timezone: source.profile.timezone,
            ),
            isSelf: false,
            expectedUserId: expectedUserId,
          );
        case RoomChartKind.astrology:
          final source = AstrologyArchiveRecord.fromJson(snapshot);
          await AstrologyArchiveStore.save(
            AstrologyProfile(
              name: '${share.displayName}（副本）',
              birthDateTime: source.profile.birthDateTime,
              birthPlace: source.profile.birthPlace,
              longitude: source.profile.longitude,
              latitude: source.profile.latitude,
              isFemale: source.profile.isFemale,
              timezone: source.profile.timezone,
              houseSystem: source.profile.houseSystem,
            ),
            isSelf: false,
            expectedUserId: expectedUserId,
          );
      }
      if (_active) {
        await _refreshCases(selectNewest: true);
        if (!mounted || !_scope.current) return;
        showAppToast(context, '已另存为本账号的独立案例');
      }
    } on FormatException {
      if (!mounted || !_scope.current) return;
      showAppToast(context, '该命盘缺少排盘资料，请发布者重新分享');
    } on StateError {
      if (!mounted || !_scope.current) return;
      showAppToast(context, apiSessionChangedMessage);
    } catch (error) {
      if (!mounted || !_scope.current) return;
      showAppToast(context, _roomChartFailureMessage(error, '保存案例失败，请重试'));
    } finally {
      if (_active) setState(() => _savingShareIds.remove(share.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) return const _ExpiredRoomChartSheet();
    final rows = _current;
    final selected = _selected;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .55,
      maxChildSize: .96,
      builder: (_, controller) => Material(
        color: const Color(0xFFF6F9FA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.paddingOf(context).bottom + 22,
          ),
          children: [
            const Center(child: _Handle()),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.onChooseArchive == null ? '房间命盘' : '选择本次咨询命盘',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: RoomChartKind.values
                    .map(
                      (kind) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(kind.label),
                          selected: _kind == kind,
                          onSelected: (_) => setState(() {
                            _kind = kind;
                            _selectedId ??= _cases.firstOrNull?.id;
                          }),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            _CasePanel(
              loading: _loading,
              rows: rows,
              selected: selected,
              onCreate: _createCase,
              onSelect: _openCase,
              onPublish: selected == null || _publishing ? null : _publish,
              publishing: _publishing,
              privateSelection: widget.onChooseArchive != null,
            ),
            if (widget.onChooseArchive == null) ...[
              const SizedBox(height: 18),
              const Text(
                '房间命盘',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 9),
              if (_sharesLoading) const LinearProgressIndicator(minHeight: 2),
              if (_sharesError != null)
                Column(children: [
                  Text(_sharesError!, textAlign: TextAlign.center),
                  TextButton(
                      onPressed: _refreshShares, child: const Text('重试加载命盘')),
                ]),
              if (!_loading &&
                  !_sharesLoading &&
                  _sharesError == null &&
                  _shares.isEmpty)
                const _Empty()
              else
                ..._shares.map(
                  (share) => _ShareCard(
                    share: share,
                    onOpen: () => showRoomChartSnapshot(
                      context,
                      kind: share.kind,
                      snapshot: share.snapshot,
                      title: share.displayName,
                    ),
                    onSave: share.allowSaveCopy ? () => _saveCopy(share) : null,
                    onRevoke:
                        share.canManage && !_revokingIds.contains(share.id)
                            ? () => _revoke(share)
                            : null,
                    saving: _savingShareIds.contains(share.id),
                    revoking: _revokingIds.contains(share.id),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PublishSettings {
  const _PublishSettings(
    this.scope,
    this.recipientIds,
    this.displayBirthData,
    this.allowSaveCopy,
  );
  final String scope;
  final List<int> recipientIds;
  final bool displayBirthData;
  final bool allowSaveCopy;
}

class _RoomChartSessionBoundary extends StatelessWidget {
  const _RoomChartSessionBoundary({required this.session, required this.child});
  final ApiSessionScope session;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (_, __, ___) =>
            session.current ? child : const _ExpiredRoomActionSheet(),
      );
}

class _ExpiredRoomChartSheet extends StatelessWidget {
  const _ExpiredRoomChartSheet();

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .42,
        minChildSize: .32,
        maxChildSize: .5,
        builder: (_, controller) => Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              const Center(child: _Handle()),
              const SizedBox(height: 28),
              const Icon(
                Icons.manage_accounts_outlined,
                size: 42,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              const Text(
                apiSessionChangedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
}

class _ExpiredRoomActionSheet extends StatelessWidget {
  const _ExpiredRoomActionSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Handle(),
                const SizedBox(height: 24),
                const Icon(
                  Icons.manage_accounts_outlined,
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  apiSessionChangedMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.members, required this.scope});
  final List<Map<String, dynamic>> members;
  final ApiSessionScope scope;
  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  String _scope = 'self';
  final Set<int> _recipients = {};
  bool _displayBirthData = false;
  bool _allowSaveCopy = true;

  List<Map<String, dynamic>> get _targets => widget.members
      .where((item) => item['isMe'] != true && item['userId'] is num)
      .toList();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (_, __, ___) => widget.scope.current
            ? _buildCurrent(context)
            : const _ExpiredRoomActionSheet(),
      );

  Widget _buildCurrent(BuildContext context) => SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _Handle()),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '发布到本房间',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                RadioGroup<String>(
                  groupValue: _scope,
                  onChanged: (value) =>
                      setState(() => _scope = value ?? _scope),
                  child: const Column(
                    children: [
                      _Scope(
                          value: 'self', title: '仅自己查看', subtitle: '不通知其他成员'),
                      _Scope(
                        value: 'all',
                        title: '房间全部成员',
                        subtitle: '当前房间内所有成员均可查看',
                      ),
                      _Scope(
                        value: 'selected',
                        title: '指定成员',
                        subtitle: '选择一位或多位成员',
                      ),
                      _Scope(
                        value: 'owner',
                        title: '房主/老师',
                        subtitle: '只有发布者和房主可以查看',
                      ),
                    ],
                  ),
                ),
                if (_scope == 'selected')
                  ..._targets.map((member) {
                    final id = (member['userId'] as num).toInt();
                    return CheckboxListTile(
                      dense: true,
                      value: _recipients.contains(id),
                      title: Text(member['nickname']?.toString() ?? '房间成员'),
                      onChanged: (value) => setState(
                        () => value == true
                            ? _recipients.add(id)
                            : _recipients.remove(id),
                      ),
                    );
                  }),
                const Divider(height: 20),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.schedule_rounded),
                  title: Text('有效时间'),
                  trailing: Text('本次房间'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _displayBirthData,
                  activeThumbColor: AppColors.primary,
                  title: const Text('显示出生资料'),
                  subtitle: const Text('关闭后只展示专业盘面，不展示出生日期、时辰和地点'),
                  onChanged: (value) =>
                      setState(() => _displayBirthData = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowSaveCopy,
                  activeThumbColor: AppColors.primary,
                  title: const Text('允许另存为案例'),
                  subtitle: const Text('允许对方保存独立副本，副本包含重新排盘所需的出生资料'),
                  onChanged: (value) => setState(() => _allowSaveCopy = value),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (_scope == 'selected' && _recipients.isEmpty) {
                            showAppToast(context, '请至少选择一位房间成员');
                            return;
                          }
                          Navigator.pop(
                            context,
                            _PublishSettings(
                              _scope,
                              _recipients.toList(),
                              _displayBirthData,
                              _allowSaveCopy,
                            ),
                          );
                        },
                        child: const Text('确认发布'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _Scope extends StatelessWidget {
  const _Scope({
    required this.value,
    required this.title,
    required this.subtitle,
  });
  final String value;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => RadioListTile<String>(
        value: value,
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      );
}

class _CasePanel extends StatelessWidget {
  const _CasePanel({
    required this.loading,
    required this.rows,
    required this.selected,
    required this.onCreate,
    required this.onSelect,
    required this.onPublish,
    required this.publishing,
    this.privateSelection = false,
  });
  final bool loading;
  final List<RoomChartArchive> rows;
  final RoomChartArchive? selected;
  final VoidCallback onCreate;
  final ValueChanged<RoomChartArchive> onSelect;
  final VoidCallback? onPublish;
  final bool publishing;
  final bool privateSelection;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3EAEC)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.folder_copy_outlined,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '案例记录',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增案例'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (rows.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('还没有案例'),
                subtitle: Text('点击“新增案例”排盘，保存后会自动出现在这里'),
              )
            else ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已有案例 · 点击直接查看专业盘面',
                  style: TextStyle(color: Color(0xFF7A8490), fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: (rows.length > 3 ? 3 : rows.length) * 78.0 - 6,
                child: ListView.separated(
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: rows.length > 3
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, index) => SizedBox(
                    height: 72,
                    child: Material(
                      color: rows[index].id == selected?.id
                          ? AppColors.primary.withValues(alpha: .08)
                          : const Color(0xFFF8FAFA),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        key: ValueKey('room-chart-case-${rows[index].id}'),
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(
                          Icons.grid_view_rounded,
                          color: rows[index].id == selected?.id
                              ? AppColors.primary
                              : const Color(0xFF7A8490),
                        ),
                        title: Text(
                          rows[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          rows[index].subtitle.isEmpty
                              ? '${rows[index].kind.label}专业盘'
                              : rows[index].subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          rows[index].unavailableReason == null
                              ? Icons.chevron_right_rounded
                              : Icons.info_outline_rounded,
                        ),
                        onTap: () => onSelect(rows[index]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (selected != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPublish,
                  icon: publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(privateSelection
                      ? '授权「${selected!.name}」给老师'
                      : '发布「${selected!.name}」到本房间'),
                ),
              ),
            ],
          ],
        ),
      );
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.share,
    required this.onOpen,
    this.onSave,
    this.onRevoke,
    this.saving = false,
    this.revoking = false,
  });
  final RoomChartShare share;
  final VoidCallback onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onRevoke;
  final bool saving;
  final bool revoking;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE3EAEC)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onOpen,
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: .12),
              foregroundColor: AppColors.primaryDark,
              child: const Icon(Icons.grid_view_rounded),
            ),
            title: Text(
              share.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${share.ownerNickname} · ${share.kind.label} · ${switch (share.scope) {
                'all' => '全部成员可见',
                'selected' => '指定成员可见',
                'owner' => '房主/老师可见',
                _ => '仅自己可见',
              }}',
            ),
            trailing: saving || revoking
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : onSave == null && onRevoke == null
                    ? const Icon(Icons.chevron_right_rounded)
                    : PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'save') onSave?.call();
                          if (value == 'revoke') onRevoke?.call();
                        },
                        itemBuilder: (_) => [
                          if (onSave != null)
                            const PopupMenuItem(
                                value: 'save', child: Text('另存为我的案例')),
                          if (onRevoke != null)
                            const PopupMenuItem(
                                value: 'revoke', child: Text('撤回命盘')),
                        ],
                      ),
          ),
        ),
      );
}

class _RedactedChart extends StatelessWidget {
  const _RedactedChart({
    required this.kind,
    required this.title,
    required this.snapshot,
  });
  final RoomChartKind kind;
  final String title;
  final Map<String, dynamic> snapshot;
  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            _ChartHeader(title: title, label: '${kind.label}专业盘'),
            Expanded(
              child: SafeArea(
                  top: false,
                  child: RoomSharedChart(kind: kind, snapshot: snapshot)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.title, required this.label});
  final String title;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
        child: Row(
          children: [
            const _Handle(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    label,
                    style:
                        const TextStyle(color: Color(0xFF7A8490), fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.grid_view_outlined, color: Color(0xFF8B97A3)),
            SizedBox(width: 10),
            Text('还没有发布到当前房间的命盘'),
          ],
        ),
      );
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFC8D1D5),
          borderRadius: BorderRadius.circular(99),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
