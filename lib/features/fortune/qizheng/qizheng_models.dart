import '../../../core/profile/account_birth_profile.dart';

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : const <Map<String, dynamic>>[];

enum QizhengChartType {
  natal('natal', '本命盘'),
  annual('annual', '流年盘'),
  monthly('monthly', '流月盘'),
  daily('daily', '流日盘'),
  current('current', '此刻星曜');

  const QizhengChartType(this.code, this.label);
  final String code;
  final String label;

  bool get supportsTimeNavigation => this != natal;

  QizhengTimeStep get defaultStep => switch (this) {
        annual => QizhengTimeStep.year,
        monthly => QizhengTimeStep.month,
        daily || current || natal => QizhengTimeStep.day,
      };

  static QizhengChartType fromCode(String? code) => values.firstWhere(
        (item) => item.code == code,
        orElse: () => natal,
      );
}

enum QizhengTimeStep {
  day('一天'),
  month('一月'),
  year('一年');

  const QizhengTimeStep(this.label);
  final String label;

  DateTime shift(DateTime value, int direction) {
    assert(direction == -1 || direction == 1);
    if (this == day) return value.add(Duration(days: direction));
    final targetYear =
        this == QizhengTimeStep.year ? value.year + direction : value.year;
    final targetMonth =
        this == QizhengTimeStep.month ? value.month + direction : value.month;
    final normalized = DateTime(targetYear, targetMonth);
    final lastDay = DateTime(normalized.year, normalized.month + 1, 0).day;
    return DateTime(
      normalized.year,
      normalized.month,
      value.day.clamp(1, lastDay).toInt(),
      value.hour,
      value.minute,
    );
  }
}

enum QizhengNodeMode {
  trueNode('true', '真罗计', '罗睺取月球真升交点，计都取其对宫'),
  meanNode('mean', '平罗计', '罗睺取月球平均升交点，运动更平滑');

  const QizhengNodeMode(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static QizhengNodeMode fromCode(String? code) => values.firstWhere(
        (item) => item.code == code,
        orElse: () => trueNode,
      );
}

enum QizhengLifeMode {
  ascSunLock(
    'asc_sun_lock',
    '与日同络',
    '地平上升点确定命宫，太阳确定宫内命度；与参考盘例一致',
  ),
  ascendant(
    'ascendant',
    '地平上升点',
    '直接以精确天文上升点立命，适合采用现代天文口径的盘例',
  );

  const QizhengLifeMode(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static QizhengLifeMode fromCode(String? code) => values.firstWhere(
        (item) => item.code == code,
        orElse: () => ascSunLock,
      );
}

class QizhengProfile {
  const QizhengProfile({
    required this.name,
    required this.birthDateTime,
    required this.birthPlace,
    required this.longitude,
    required this.latitude,
    this.isFemale,
    this.timezone = 'Asia/Shanghai',
  });

  factory QizhengProfile.fromAccount(AccountBirthProfile value) =>
      QizhengProfile(
        name: value.safeNickname,
        birthDateTime: value.birthDateTime!,
        birthPlace: value.birthPlace,
        longitude: value.birthLongitude!,
        latitude: value.birthLatitude!,
        isFemale: value.isFemale,
        timezone: value.birthTimezone,
      );

  factory QizhengProfile.fromJson(Map<String, dynamic> json) => QizhengProfile(
        name: json['name']?.toString() ?? '我的七政命盘',
        birthDateTime: DateTime.parse(json['birthDateTime'].toString()),
        birthPlace: json['birthPlace']?.toString() ?? '',
        longitude: _double(json['longitude']),
        latitude: _double(json['latitude']),
        isFemale: json['isFemale'] as bool?,
        timezone: json['timezone']?.toString() ?? 'Asia/Shanghai',
      );

  final String name;
  final DateTime birthDateTime;
  final String birthPlace;
  final double longitude;
  final double latitude;
  final bool? isFemale;
  final String timezone;

  Map<String, dynamic> toRequest() => <String, dynamic>{
        'name': name,
        'birthDate': _date(birthDateTime),
        'birthTime': _time(birthDateTime),
        'birthPlace': birthPlace,
        'longitude': longitude,
        'latitude': latitude,
        'timezone': timezone,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'birthDateTime': birthDateTime.toIso8601String(),
        'birthPlace': birthPlace,
        'longitude': longitude,
        'latitude': latitude,
        'timezone': timezone,
        if (isFemale != null) 'isFemale': isFemale,
      };
}

class QizhengBodyPosition {
  const QizhengBodyPosition({
    required this.key,
    required this.name,
    required this.shortName,
    required this.element,
    required this.colorHex,
    required this.longitude,
    required this.speed,
    required this.retrograde,
    required this.palace,
    required this.palaceRole,
    required this.palaceDegree,
    required this.mansion,
    required this.mansionRuler,
    required this.mansionQuadrant,
    required this.mansionDegree,
    required this.dignities,
  });

  factory QizhengBodyPosition.fromJson(Map<String, dynamic> json) =>
      QizhengBodyPosition(
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        shortName: json['shortName']?.toString() ?? '',
        element: json['element']?.toString() ?? '',
        colorHex: json['color']?.toString() ?? '#D4B56A',
        longitude: _double(json['longitude']),
        speed: _double(json['speed']),
        retrograde: json['retrograde'] == true,
        palace: json['palace']?.toString() ?? '',
        palaceRole: json['palaceRole']?.toString() ?? '',
        palaceDegree: _double(json['palaceDegree']),
        mansion: json['mansion']?.toString() ?? '',
        mansionRuler: json['mansionRuler']?.toString() ?? '',
        mansionQuadrant: json['mansionQuadrant']?.toString() ?? '',
        mansionDegree: _double(json['mansionDegree']),
        dignities: (json['dignities'] as List?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
      );

  final String key;
  final String name;
  final String shortName;
  final String element;
  final String colorHex;
  final double longitude;
  final double speed;
  final bool retrograde;
  final String palace;
  final String palaceRole;
  final double palaceDegree;
  final String mansion;
  final String mansionRuler;
  final String mansionQuadrant;
  final double mansionDegree;
  final List<String> dignities;

  String get degreeText =>
      '${palaceDegree.floor()}°${((palaceDegree % 1) * 60).round().toString().padLeft(2, '0')}′';
}

class QizhengMansion {
  const QizhengMansion({
    required this.name,
    required this.ruler,
    required this.quadrant,
    required this.determinativeStar,
    required this.determinativeStarId,
    required this.source,
    required this.longitude,
    required this.width,
  });

  factory QizhengMansion.fromJson(Map<String, dynamic> json) => QizhengMansion(
        name: json['name']?.toString() ?? '',
        ruler: json['ruler']?.toString() ?? '',
        quadrant: json['quadrant']?.toString() ?? '',
        determinativeStar: json['determinativeStar']?.toString() ?? '',
        determinativeStarId: json['determinativeStarId']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        longitude: _double(json['longitude']),
        width: _double(json['width']),
      );

  final String name;
  final String ruler;
  final String quadrant;
  final String determinativeStar;
  final String determinativeStarId;
  final String source;
  final double longitude;
  final double width;
}

class QizhengPalace {
  const QizhengPalace({
    required this.index,
    required this.name,
    required this.branch,
    required this.element,
    required this.role,
    required this.startLongitude,
    required this.occupants,
  });

  factory QizhengPalace.fromJson(Map<String, dynamic> json) => QizhengPalace(
        index: _int(json['index']),
        name: json['name']?.toString() ?? '',
        branch: json['branch']?.toString() ?? '',
        element: json['element']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        startLongitude: _double(json['startLongitude']),
        occupants: (json['occupants'] as List?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
      );

  final int index;
  final String name;
  final String branch;
  final String element;
  final String role;
  final double startLongitude;
  final List<String> occupants;
}

class QizhengRelationship {
  const QizhengRelationship({
    required this.body1,
    required this.body1Name,
    required this.body2,
    required this.body2Name,
    required this.type,
    required this.separation,
  });

  factory QizhengRelationship.fromJson(Map<String, dynamic> json) =>
      QizhengRelationship(
        body1: json['body1']?.toString() ?? '',
        body1Name: json['body1Name']?.toString() ?? '',
        body2: json['body2']?.toString() ?? '',
        body2Name: json['body2Name']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        separation: _double(json['separation']),
      );

  final String body1;
  final String body1Name;
  final String body2;
  final String body2Name;
  final String type;
  final double separation;
}

class QizhengInterpretation {
  const QizhengInterpretation({
    required this.title,
    required this.subtitle,
    required this.content,
  });

  factory QizhengInterpretation.fromJson(Map<String, dynamic> json) =>
      QizhengInterpretation(
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
      );

  final String title;
  final String subtitle;
  final String content;
}

class QizhengBirthMansion {
  const QizhengBirthMansion({
    required this.name,
    required this.ruler,
    required this.quadrant,
    required this.degree,
    required this.tone,
  });

  factory QizhengBirthMansion.fromJson(Map<String, dynamic> json) =>
      QizhengBirthMansion(
        name: json['name']?.toString() ?? '',
        ruler: json['ruler']?.toString() ?? '',
        quadrant: json['quadrant']?.toString() ?? '',
        degree: _double(json['degree']),
        tone: json['tone']?.toString() ?? '',
      );

  final String name;
  final String ruler;
  final String quadrant;
  final double degree;
  final String tone;
}

class QizhengLifeDegree {
  const QizhengLifeDegree({
    required this.longitude,
    required this.palace,
    required this.mansion,
    required this.mansionRuler,
    required this.mansionDegree,
  });

  factory QizhengLifeDegree.fromJson(Map<String, dynamic> json) =>
      QizhengLifeDegree(
        longitude: _double(json['longitude']),
        palace: json['palace']?.toString() ?? '',
        mansion: json['mansion']?.toString() ?? '',
        mansionRuler: json['mansionRuler']?.toString() ?? '',
        mansionDegree: _double(json['mansionDegree']),
      );

  final double longitude;
  final String palace;
  final String mansion;
  final String mansionRuler;
  final double mansionDegree;
}

class QizhengChartData {
  const QizhengChartData({
    this.sourceJson = const {},
    required this.chartType,
    required this.chartTitle,
    required this.targetDateTime,
    required this.summary,
    required this.dayNight,
    required this.birthMansion,
    required this.lifeDegree,
    required this.bodies,
    required this.palaces,
    required this.mansions,
    required this.relationships,
    required this.interpretations,
    required this.calculation,
    required this.disclaimer,
  });

  factory QizhengChartData.fromJson(Map<String, dynamic> json) =>
      QizhengChartData(
        sourceJson: Map<String, dynamic>.from(json),
        chartType: QizhengChartType.fromCode(json['chartType']?.toString()),
        chartTitle: json['chartTitle']?.toString() ?? '本命盘',
        targetDateTime: DateTime.tryParse(
              json['targetDateTime']?.toString() ?? '',
            ) ??
            DateTime.now(),
        summary: json['summary']?.toString() ?? '',
        dayNight: json['dayNight']?.toString() ?? '',
        birthMansion: QizhengBirthMansion.fromJson(
          Map<String, dynamic>.from(json['birthMansion'] as Map? ?? {}),
        ),
        lifeDegree: QizhengLifeDegree.fromJson(
          Map<String, dynamic>.from(json['lifeDegree'] as Map? ?? {}),
        ),
        bodies:
            _maps(json['bodies']).map(QizhengBodyPosition.fromJson).toList(),
        palaces: _maps(json['palaces']).map(QizhengPalace.fromJson).toList(),
        mansions: _maps(json['mansions']).map(QizhengMansion.fromJson).toList(),
        relationships: _maps(json['relationships'])
            .map(QizhengRelationship.fromJson)
            .toList(),
        interpretations: _maps(json['interpretations'])
            .map(QizhengInterpretation.fromJson)
            .toList(),
        calculation:
            Map<String, dynamic>.from(json['calculation'] as Map? ?? {}),
        disclaimer: json['disclaimer']?.toString() ?? '',
      );

  final Map<String, dynamic> sourceJson;
  final QizhengChartType chartType;
  final String chartTitle;
  final DateTime targetDateTime;
  final String summary;
  final String dayNight;
  final QizhengBirthMansion birthMansion;
  final QizhengLifeDegree lifeDegree;
  final List<QizhengBodyPosition> bodies;
  final List<QizhengPalace> palaces;
  final List<QizhengMansion> mansions;
  final List<QizhengRelationship> relationships;
  final List<QizhengInterpretation> interpretations;
  final Map<String, dynamic> calculation;
  final String disclaimer;

  QizhengBodyPosition body(String key) =>
      bodies.firstWhere((item) => item.key == key);
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
