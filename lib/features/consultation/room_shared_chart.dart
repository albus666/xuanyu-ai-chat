import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import '../../core/network/api_session_scope.dart';
import 'room_chart_sheet.dart' show RoomChartKind;
import '../fortune/paipan/models/paipan_record.dart';
import '../fortune/paipan/paipan_detail_chart_tab.dart';
import '../fortune/paipan/utils/bazi_result.dart';
import '../fortune/astrology/astrology_archive_store.dart';
import '../fortune/astrology/astrology_models.dart';
import '../fortune/astrology/astrology_service.dart';
import '../fortune/astrology/astrology_page.dart';
import '../fortune/qizheng/qizheng_archive_store.dart';
import '../fortune/qizheng/qizheng_models.dart';
import '../fortune/qizheng/qizheng_service.dart';
import '../fortune/qizheng/qizheng_page.dart';
import '../fortune/ziwei/ziwei_archive_store.dart';
import '../fortune/ziwei/ziwei_models.dart';
import '../fortune/ziwei/ziwei_service.dart';
import '../fortune/ziwei/ziwei_chart_page.dart';

Future<Map<String, dynamic>> buildRoomProfessionalSnapshot(
    RoomChartKind kind, Map<String, dynamic> snapshot) async {
  final result = Map<String, dynamic>.from(snapshot);
  switch (kind) {
    case RoomChartKind.bazi:
      final record = PaipanRecord.fromJson(snapshot);
      final chart =
          computeBaziResult(record.birthDateTime, isFemale: record.isFemale);
      result['professionalChart'] = chart.toSharedJson();
    case RoomChartKind.ziwei:
      final record = ZiweiArchiveRecord.fromJson(snapshot);
      final now = DateTime.now();
      final profile = record.profile;
      final chart = await ZiweiService.calculate(
          profile: profile,
          targetDate: now,
          targetTimeIndex: ZiweiProfile.timeIndexFor(now.hour));
      result['professionalChart'] = chart.sourceJson;
      result['timelineBasisYear'] =
          Lunar.fromDate(profile.effectiveBirthDate).getYear();
      result['chartTargetDate'] = now.toIso8601String();
      result['chartTargetTimeIndex'] = ZiweiProfile.timeIndexFor(now.hour);
      result['engineRequest'] = {
        'birthDate': _date(profile.effectiveBirthDate),
        'birthTimeIndex': profile.birthTimeIndex,
        'gender': profile.gender,
        'fixLeap': profile.settings.fixLeap,
        'astroType': profile.settings.astroType,
        'config': profile.settings.toRequestConfig(),
      };
    case RoomChartKind.qizheng:
      final profile = QizhengArchiveRecord.fromJson(snapshot).profile;
      final chart = await QizhengService.calculate(profile);
      result['professionalChart'] = chart.sourceJson;
      result['engineRequest'] = profile.toRequest();
    case RoomChartKind.astrology:
      final profile = AstrologyArchiveRecord.fromJson(snapshot).profile;
      final chart = await AstrologyService.calculate(profile);
      result['professionalChart'] = chart.sourceJson;
      result['engineRequest'] = profile.toRequest();
  }
  if ((result['professionalChart'] as Map).isEmpty) {
    throw const FormatException('完整盘面数据缺失，请重新排盘后分享');
  }
  return result;
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _time(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// The room uses the same interactive professional pages as the original tools.
/// Hidden birth data stays on the server; changes request a new authorized chart.
class RoomSharedChart extends StatefulWidget {
  const RoomSharedChart(
      {super.key, required this.kind, required this.snapshot});
  final RoomChartKind kind;
  final Map<String, dynamic> snapshot;
  @override
  State<RoomSharedChart> createState() => _RoomSharedChartState();
}

class _RoomSharedChartState extends State<RoomSharedChart> {
  final _session = ApiSessionScope();

  Future<Map<String, dynamic>> _calculate(Map<String, dynamic> target) async {
    final ref = widget.snapshot['_roomShare'];
    if (ref is! Map) throw const FormatException('请刷新房间命盘后重试');
    final response = await _session.post(
        '/api/consultation/rooms/${ref['roomId']}/chart-shares/${ref['shareId']}/calculate',
        data: target,
        receiveTimeout: const Duration(seconds: 30));
    final payload = response.data;
    if (payload is! Map || payload['code'] != 0 || payload['data'] is! Map) {
      throw const FormatException('命盘已失效，请刷新房间后重试');
    }
    return Map<String, dynamic>.from(payload['data'] as Map);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final raw = snapshot['professionalChart'];
    if (raw is! Map) return _unavailable();
    final data = Map<String, dynamic>.from(raw);
    final profileJson =
        Map<String, dynamic>.from(snapshot['profile'] as Map? ?? {});
    switch (widget.kind) {
      case RoomChartKind.bazi:
        BaziResult result;
        try {
          result = BaziResult.fromSharedJson(data);
        } on FormatException {
          final birth =
              DateTime.tryParse(snapshot['birthDateTime']?.toString() ?? '');
          if (birth == null) return _unavailable();
          result =
              computeBaziResult(birth, isFemale: snapshot['isFemale'] == true);
        }
        return PaipanDetailChartTab(
            result: result, isFemale: snapshot['isFemale'] == true);
      case RoomChartKind.ziwei:
        final hasBirth = profileJson['clockBirthDate'] != null;
        final chart = ZiweiChartData.fromJson(data);
        if (chart.astrolabe.palaces.length != 12) return _unavailable();
        final target =
            DateTime.tryParse(snapshot['chartTargetDate']?.toString() ?? '') ??
                DateTime.now();
        // Legacy snapshots can derive the reference year from target nominal age.
        final age = chart.horoscope.age.nominalAge ?? 1;
        final year = (snapshot['timelineBasisYear'] as num?)?.toInt() ??
            Lunar.fromDate(target).getYear() - age + 1;
        final profile = hasBirth
            ? ZiweiProfile.fromJson(profileJson)
            : ZiweiProfile(
                name: '',
                gender: profileJson['gender']?.toString() ?? '男',
                clockBirthDate: DateTime(year, 7, 1),
                effectiveBirthDate: DateTime(year, 7, 1),
                calendarTypeIndex: 0,
                settings: ZiweiSettings.fromJson(Map<String, dynamic>.from(
                        profileJson['settings'] as Map? ?? {}))
                    .copyWith(professionalMode: true));
        return ZiweiChartPage(
            profile: profile,
            initialData: chart,
            initialTargetDate: target,
            initialTargetTimeIndex:
                (snapshot['chartTargetTimeIndex'] as num?)?.toInt() ??
                    ZiweiProfile.timeIndexFor(target.hour),
            professionalOnly: true,
            embedded: true,
            showBirthData: hasBirth,
            sharedChartLoader: (date, timeIndex) async {
              try {
                return ZiweiChartData.fromJson(await _calculate(
                    {'targetDate': _date(date), 'targetTimeIndex': timeIndex}));
              } catch (_) {
                throw const ZiweiServiceException('暂时无法切换运限，请刷新房间后重试');
              }
            });
      case RoomChartKind.qizheng:
        final profile = profileJson['birthDateTime'] != null
            ? QizhengProfile.fromJson(profileJson)
            : QizhengProfile(
                name: '',
                birthDateTime: DateTime(2000, 7, 1),
                birthPlace: '',
                longitude: 0,
                latitude: 0);
        final chart = QizhengChartData.fromJson(data);
        if (chart.bodies.length != 11 || chart.palaces.length != 12) {
          return _unavailable();
        }
        return QizhengChartPage(
            profile: profile,
            chart: chart,
            record: QizhengArchiveRecord(
                id: 'room-shared',
                createdAt: DateTime.now(),
                profile: profile,
                isSelf: false),
            isSelf: false,
            professionalOnly: true,
            embedded: true,
            sharedChartLoader: (type, target, nodeMode, lifeMode) async {
              try {
                return QizhengChartData.fromJson(await _calculate({
                  'chartType': type.code,
                  'targetDate': _date(target),
                  'targetTime': _time(target),
                  'nodeMode': nodeMode.code,
                  'lifeMode': lifeMode.code
                }));
              } catch (_) {
                throw const QizhengServiceException('暂时无法切换盘面，请刷新房间后重试');
              }
            });
      case RoomChartKind.astrology:
        final profile = profileJson['birthDateTime'] != null
            ? AstrologyProfile.fromJson(profileJson)
            : AstrologyProfile(
                name: '',
                birthDateTime: DateTime(2000, 7, 1),
                birthPlace: '',
                longitude: 0,
                latitude: 0,
                houseSystem: profileJson['houseSystem']?.toString() ?? 'P');
        final chart = AstrologyChartData.fromJson(data);
        if (chart.planets.length != 10 || chart.houses.length != 12) {
          return _unavailable();
        }
        return AstrologyChartPage(
            profile: profile,
            chart: chart,
            record: AstrologyArchiveRecord(
                id: 'room-shared',
                createdAt: DateTime.now(),
                profile: profile,
                isSelf: false),
            isSelf: false,
            professionalOnly: true,
            embedded: true,
            sharedChartLoader: (type, target, place) async {
              try {
                return AstrologyChartData.fromJson(await _calculate({
                  'chartType': type.code,
                  'targetDate': _date(target),
                  'targetTime': _time(target),
                  if (place != null) 'targetPlace': place.extPath,
                  if (place != null) 'targetLongitude': place.lng,
                  if (place != null) 'targetLatitude': place.lat
                }));
              } catch (_) {
                throw const AstrologyServiceException('暂时无法切换盘面，请刷新房间后重试');
              }
            });
    }
  }

  Widget _unavailable() => const Center(
      child: Padding(
          padding: EdgeInsets.all(24), child: Text('此旧分享缺少完整专业盘数据，请发布者重新分享。')));
}
