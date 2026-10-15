import '../../../core/profile/account_birth_profile.dart';
import '../paipan/models/region.dart';

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

enum AstrologyChartType {
  current('current', '此刻天象'),
  natal('natal', '本命盘'),
  transit('transit', '行运盘'),
  tertiary('tertiary', '三限盘'),
  secondary('secondary', '次限盘'),
  lunarReturn('lunar_return', '月亮返照'),
  solarReturn('solar_return', '太阳返照'),
  solarArc('solar_arc', '太阳弧'),
  firdaria('firdaria', '法达盘'),
  minor('minor', '小限盘'),
  relocated('relocated', '重置盘');

  const AstrologyChartType(this.code, this.label);

  final String code;
  final String label;

  bool get usesTargetDate =>
      this != current && this != natal && this != relocated;

  bool get supportsTimeNavigation => this != natal && this != relocated;

  bool get usesEventPlace =>
      this == current ||
      this == lunarReturn ||
      this == solarReturn ||
      this == relocated;

  String get placePickerTitle => switch (this) {
        current => '选择天象观测地点',
        lunarReturn => '选择月亮返照地点',
        solarReturn => '选择太阳返照地点',
        relocated => '选择重置地点',
        _ => '选择计算地点',
      };

  AstrologyTimeStep get defaultTimeStep => switch (this) {
        current || transit => AstrologyTimeStep.day,
        lunarReturn => AstrologyTimeStep.month,
        natal || relocated => AstrologyTimeStep.day,
        _ => AstrologyTimeStep.year,
      };

  static AstrologyChartType fromCode(String? value) => values.firstWhere(
        (item) => item.code == value,
        orElse: () => natal,
      );
}

enum AstrologyTimeStep {
  day('一天'),
  month('一月'),
  year('一年');

  const AstrologyTimeStep(this.label);

  final String label;

  DateTime shift(DateTime value, int direction) {
    assert(direction == -1 || direction == 1);
    if (this == day) return value.add(Duration(days: direction));

    final targetYear = this == year ? value.year + direction : value.year;
    final targetMonth = this == month ? value.month + direction : value.month;
    final normalized = DateTime(targetYear, targetMonth);
    final lastDay = DateTime(normalized.year, normalized.month + 1, 0).day;
    return DateTime(
      normalized.year,
      normalized.month,
      value.day.clamp(1, lastDay).toInt(),
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
}

class AstrologyProfile {
  const AstrologyProfile({
    required this.name,
    required this.birthDateTime,
    required this.birthPlace,
    required this.longitude,
    required this.latitude,
    this.isFemale,
    this.timezone = 'Asia/Shanghai',
    this.houseSystem = 'P',
  });

  factory AstrologyProfile.fromAccount(AccountBirthProfile profile) {
    return AstrologyProfile(
      name: profile.safeNickname,
      birthDateTime: profile.birthDateTime!,
      birthPlace: profile.birthPlace,
      longitude: profile.birthLongitude!,
      latitude: profile.birthLatitude!,
      isFemale: profile.isFemale,
      timezone: profile.birthTimezone,
    );
  }

  factory AstrologyProfile.fromJson(Map<String, dynamic> json) {
    return AstrologyProfile(
      name: json['name']?.toString() ?? '我的星盘',
      birthDateTime: DateTime.parse(json['birthDateTime'].toString()),
      birthPlace: json['birthPlace']?.toString() ?? '',
      longitude: _number(json['longitude']),
      latitude: _number(json['latitude']),
      isFemale: json['isFemale'] as bool?,
      timezone: json['timezone']?.toString() ?? 'Asia/Shanghai',
      houseSystem: json['houseSystem']?.toString() ?? 'P',
    );
  }

  final String name;
  final DateTime birthDateTime;
  final String birthPlace;
  final double longitude;
  final double latitude;
  final bool? isFemale;
  final String timezone;
  final String houseSystem;

  Region get region => Region.placeholder(
        name: birthPlace.split(RegExp(r'\s+')).last,
        extPath: birthPlace,
        lng: longitude,
        lat: latitude,
      );

  AstrologyProfile copyWith({String? houseSystem}) => AstrologyProfile(
        name: name,
        birthDateTime: birthDateTime,
        birthPlace: birthPlace,
        longitude: longitude,
        latitude: latitude,
        isFemale: isFemale,
        timezone: timezone,
        houseSystem: houseSystem ?? this.houseSystem,
      );

  Map<String, dynamic> toRequest() => <String, dynamic>{
        'name': name,
        'birthDate':
            '${birthDateTime.year.toString().padLeft(4, '0')}-${birthDateTime.month.toString().padLeft(2, '0')}-${birthDateTime.day.toString().padLeft(2, '0')}',
        'birthTime':
            '${birthDateTime.hour.toString().padLeft(2, '0')}:${birthDateTime.minute.toString().padLeft(2, '0')}',
        'birthPlace': birthPlace,
        'longitude': longitude,
        'latitude': latitude,
        'timezone': timezone,
        'houseSystem': houseSystem,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'birthDateTime': birthDateTime.toIso8601String(),
        'birthPlace': birthPlace,
        'longitude': longitude,
        'latitude': latitude,
        'timezone': timezone,
        'houseSystem': houseSystem,
        if (isFemale != null) 'isFemale': isFemale,
      };
}

class AstrologyPosition {
  const AstrologyPosition({
    required this.key,
    required this.name,
    required this.symbol,
    required this.longitude,
    required this.sign,
    required this.signSymbol,
    required this.signIndex,
    required this.degree,
    this.house,
    this.retrograde = false,
  });

  factory AstrologyPosition.fromJson(Map<String, dynamic> json) {
    return AstrologyPosition(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      longitude: _number(json['longitude']),
      sign: json['sign']?.toString() ?? '',
      signSymbol: json['signSymbol']?.toString() ?? '',
      signIndex: _integer(json['signIndex']),
      degree: _number(json['degree']),
      house: json['house'] == null ? null : _integer(json['house']),
      retrograde: json['retrograde'] == true,
    );
  }

  final String key;
  final String name;
  final String symbol;
  final double longitude;
  final String sign;
  final String signSymbol;
  final int signIndex;
  final double degree;
  final int? house;
  final bool retrograde;

  String get degreeText {
    final whole = degree.floor();
    final minute = ((degree - whole) * 60).floor().clamp(0, 59);
    return '$whole°${minute.toString().padLeft(2, '0')}′';
  }
}

class AstrologyAspect {
  const AstrologyAspect({
    required this.body1,
    required this.body1Name,
    required this.body2,
    required this.body2Name,
    required this.type,
    required this.typeName,
    required this.symbol,
    required this.orb,
    required this.applying,
  });

  factory AstrologyAspect.fromJson(Map<String, dynamic> json) {
    return AstrologyAspect(
      body1: json['body1']?.toString() ?? '',
      body1Name: json['body1Name']?.toString() ?? '',
      body2: json['body2']?.toString() ?? '',
      body2Name: json['body2Name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      typeName: json['typeName']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      orb: _number(json['orb']),
      applying: json['applying'] is bool ? json['applying'] as bool : null,
    );
  }

  final String body1;
  final String body1Name;
  final String body2;
  final String body2Name;
  final String type;
  final String typeName;
  final String symbol;
  final double orb;
  final bool? applying;
}

class AstrologyInterpretation {
  const AstrologyInterpretation({
    required this.title,
    required this.subtitle,
    required this.content,
  });

  factory AstrologyInterpretation.fromJson(Map<String, dynamic> json) =>
      AstrologyInterpretation(
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
      );

  final String title;
  final String subtitle;
  final String content;
}

class AstrologyTimePeriod {
  const AstrologyTimePeriod({
    required this.level,
    required this.planet,
    required this.planetName,
    required this.majorPlanetName,
    required this.startDate,
    required this.endDate,
    required this.active,
  });

  factory AstrologyTimePeriod.fromJson(Map<String, dynamic> json) =>
      AstrologyTimePeriod(
        level: _integer(json['level']),
        planet: json['planet']?.toString() ?? '',
        planetName: json['planetName']?.toString() ?? '',
        majorPlanetName: json['majorPlanetName']?.toString() ?? '',
        startDate: DateTime.tryParse(json['startDate']?.toString() ?? ''),
        endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
        active: json['active'] == true,
      );

  final int level;
  final String planet;
  final String planetName;
  final String majorPlanetName;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool active;
}

class AstrologyChartData {
  const AstrologyChartData({
    this.sourceJson = const {},
    required this.summary,
    required this.planets,
    required this.houses,
    required this.ascendant,
    required this.midheaven,
    required this.aspects,
    required this.interpretations,
    required this.elements,
    required this.modes,
    required this.calculation,
    required this.disclaimer,
    this.chartType = AstrologyChartType.natal,
    this.chartTitle = '本命盘',
    this.targetDateTime,
    this.targetPlace = '',
    this.firdaria = const [],
    this.comparisonPlanets = const [],
    this.crossAspects = const [],
    this.comparisonLabel = '',
    this.activeLabel = '',
  });

  factory AstrologyChartData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic value) => value is List
        ? value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    Map<String, int> counts(dynamic value) {
      if (value is! Map) return <String, int>{};
      return value.map((key, item) => MapEntry(key.toString(), _integer(item)));
    }

    final angles = Map<String, dynamic>.from(json['angles'] as Map? ?? {});
    final distribution =
        Map<String, dynamic>.from(json['distribution'] as Map? ?? {});
    return AstrologyChartData(
      sourceJson: Map<String, dynamic>.from(json),
      summary: json['summary']?.toString() ?? '',
      planets: maps(json['planets']).map(AstrologyPosition.fromJson).toList(),
      houses: maps(json['houses']).map(AstrologyPosition.fromJson).toList(),
      ascendant: AstrologyPosition.fromJson(
        Map<String, dynamic>.from(angles['ascendant'] as Map? ?? {}),
      ),
      midheaven: AstrologyPosition.fromJson(
        Map<String, dynamic>.from(angles['midheaven'] as Map? ?? {}),
      ),
      aspects: maps(json['aspects']).map(AstrologyAspect.fromJson).toList(),
      interpretations: maps(json['interpretations'])
          .map(AstrologyInterpretation.fromJson)
          .toList(),
      elements: counts(distribution['elements']),
      modes: counts(distribution['modes']),
      calculation: Map<String, dynamic>.from(json['calculation'] as Map? ?? {}),
      disclaimer: json['disclaimer']?.toString() ?? '',
      chartType: AstrologyChartType.fromCode(json['chartType']?.toString()),
      chartTitle: json['chartTitle']?.toString() ?? '本命盘',
      targetDateTime:
          DateTime.tryParse(json['targetDateTime']?.toString() ?? ''),
      targetPlace: json['targetPlace']?.toString() ?? '',
      firdaria:
          maps(json['firdaria']).map(AstrologyTimePeriod.fromJson).toList(),
      comparisonPlanets: maps(json['comparisonPlanets'])
          .map(AstrologyPosition.fromJson)
          .toList(),
      crossAspects:
          maps(json['crossAspects']).map(AstrologyAspect.fromJson).toList(),
      comparisonLabel: json['comparisonLabel']?.toString() ?? '',
      activeLabel: json['activeLabel']?.toString() ?? '',
    );
  }

  final Map<String, dynamic> sourceJson;
  final String summary;
  final List<AstrologyPosition> planets;
  final List<AstrologyPosition> houses;
  final AstrologyPosition ascendant;
  final AstrologyPosition midheaven;
  final List<AstrologyAspect> aspects;
  final List<AstrologyInterpretation> interpretations;
  final Map<String, int> elements;
  final Map<String, int> modes;
  final Map<String, dynamic> calculation;
  final String disclaimer;
  final AstrologyChartType chartType;
  final String chartTitle;
  final DateTime? targetDateTime;
  final String targetPlace;
  final List<AstrologyTimePeriod> firdaria;
  final List<AstrologyPosition> comparisonPlanets;
  final List<AstrologyAspect> crossAspects;
  final String comparisonLabel;
  final String activeLabel;

  bool get hasComparison => comparisonPlanets.isNotEmpty;

  AstrologyPosition position(String key) =>
      planets.firstWhere((item) => item.key == key);
}
