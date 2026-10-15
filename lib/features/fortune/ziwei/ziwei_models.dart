import 'dart:convert';

enum ZiweiLayer { natal, decadal, age, yearly, monthly, daily, hourly }

extension ZiweiLayerX on ZiweiLayer {
  String get label => switch (this) {
        ZiweiLayer.natal => '本命',
        ZiweiLayer.decadal => '大限',
        ZiweiLayer.age => '小限',
        ZiweiLayer.yearly => '流年',
        ZiweiLayer.monthly => '流月',
        ZiweiLayer.daily => '流日',
        ZiweiLayer.hourly => '流时',
      };
}

class ZiweiSettings {
  const ZiweiSettings({
    this.algorithm = 'default',
    this.astroType = 'heaven',
    this.yearDivide = 'normal',
    this.horoscopeDivide = 'normal',
    this.ageDivide = 'normal',
    this.dayDivide = 'forward',
    this.fixLeap = true,
    this.useTrueSolarTime = false,
    this.professionalMode = false,
    this.showHoroscopeStars = true,
  });

  final String algorithm;
  final String astroType;
  final String yearDivide;
  final String horoscopeDivide;
  final String ageDivide;
  final String dayDivide;
  final bool fixLeap;
  final bool useTrueSolarTime;
  final bool professionalMode;
  final bool showHoroscopeStars;

  factory ZiweiSettings.fromJson(Map<String, dynamic> json) => ZiweiSettings(
        algorithm: _text(json['algorithm']).isEmpty
            ? 'default'
            : _text(json['algorithm']),
        astroType: _text(json['astroType']).isEmpty
            ? 'heaven'
            : _text(json['astroType']),
        yearDivide: _text(json['yearDivide']).isEmpty
            ? 'normal'
            : _text(json['yearDivide']),
        horoscopeDivide: _text(json['horoscopeDivide']).isEmpty
            ? 'normal'
            : _text(json['horoscopeDivide']),
        ageDivide: _text(json['ageDivide']).isEmpty
            ? 'normal'
            : _text(json['ageDivide']),
        dayDivide: _text(json['dayDivide']).isEmpty
            ? 'forward'
            : _text(json['dayDivide']),
        fixLeap: json['fixLeap'] != false,
        useTrueSolarTime: json['useTrueSolarTime'] == true,
        professionalMode: json['professionalMode'] == true,
        showHoroscopeStars: json['showHoroscopeStars'] != false,
      );

  bool get isZhongzhou => algorithm == 'zhongzhou';

  String get presetName {
    if (algorithm == 'default' &&
        astroType == 'heaven' &&
        yearDivide == 'normal' &&
        horoscopeDivide == 'normal' &&
        ageDivide == 'normal' &&
        dayDivide == 'forward' &&
        fixLeap) {
      return '通行默认';
    }
    if (algorithm == 'zhongzhou') {
      return '中州$astroTypeLabel';
    }
    return '自定义';
  }

  String get astroTypeLabel => switch (astroType) {
        'earth' => '地盘',
        'human' => '人盘',
        _ => '天盘',
      };

  ZiweiSettings copyWith({
    String? algorithm,
    String? astroType,
    String? yearDivide,
    String? horoscopeDivide,
    String? ageDivide,
    String? dayDivide,
    bool? fixLeap,
    bool? useTrueSolarTime,
    bool? professionalMode,
    bool? showHoroscopeStars,
  }) {
    final nextAlgorithm = algorithm ?? this.algorithm;
    return ZiweiSettings(
      algorithm: nextAlgorithm,
      astroType: nextAlgorithm == 'zhongzhou'
          ? (astroType ?? this.astroType)
          : 'heaven',
      yearDivide: yearDivide ?? this.yearDivide,
      horoscopeDivide: horoscopeDivide ?? this.horoscopeDivide,
      ageDivide: ageDivide ?? this.ageDivide,
      dayDivide: dayDivide ?? this.dayDivide,
      fixLeap: fixLeap ?? this.fixLeap,
      useTrueSolarTime: useTrueSolarTime ?? this.useTrueSolarTime,
      professionalMode: professionalMode ?? this.professionalMode,
      showHoroscopeStars: showHoroscopeStars ?? this.showHoroscopeStars,
    );
  }

  Map<String, dynamic> toRequestConfig() => <String, dynamic>{
        'algorithm': algorithm,
        'yearDivide': yearDivide,
        'horoscopeDivide': horoscopeDivide,
        'ageDivide': ageDivide,
        'dayDivide': dayDivide,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toRequestConfig(),
        'astroType': astroType,
        'fixLeap': fixLeap,
        'useTrueSolarTime': useTrueSolarTime,
        'professionalMode': professionalMode,
        'showHoroscopeStars': showHoroscopeStars,
      };
}

class ZiweiProfile {
  const ZiweiProfile({
    required this.name,
    required this.gender,
    required this.clockBirthDate,
    required this.effectiveBirthDate,
    required this.calendarTypeIndex,
    required this.settings,
    this.birthPlace,
    this.longitude,
    this.latitude,
  });

  final String name;
  final String gender;
  final DateTime clockBirthDate;
  final DateTime effectiveBirthDate;
  final int calendarTypeIndex;
  final ZiweiSettings settings;
  final String? birthPlace;
  final double? longitude;
  final double? latitude;

  factory ZiweiProfile.fromJson(Map<String, dynamic> json) {
    final clock = DateTime.parse(_text(json['clockBirthDate']));
    final effectiveRaw = _text(json['effectiveBirthDate']);
    return ZiweiProfile(
      name: _text(json['name']).isEmpty ? '未命名命盘' : _text(json['name']),
      gender: _text(json['gender']) == '女' ? '女' : '男',
      clockBirthDate: clock,
      effectiveBirthDate:
          effectiveRaw.isEmpty ? clock : DateTime.parse(effectiveRaw),
      calendarTypeIndex: _integer(json['calendarTypeIndex']).clamp(0, 2),
      settings: ZiweiSettings.fromJson(_map(json['settings'])),
      birthPlace:
          _text(json['birthPlace']).isEmpty ? null : _text(json['birthPlace']),
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : null,
      latitude:
          json['latitude'] is num ? (json['latitude'] as num).toDouble() : null,
    );
  }

  int get birthTimeIndex => timeIndexFor(effectiveBirthDate.hour);

  static int timeIndexFor(int hour) {
    if (hour == 23) return 12;
    if (hour == 0) return 0;
    return ((hour + 1) ~/ 2).clamp(1, 11);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'gender': gender,
        'clockBirthDate': clockBirthDate.toIso8601String(),
        'effectiveBirthDate': effectiveBirthDate.toIso8601String(),
        'calendarTypeIndex': calendarTypeIndex,
        'settings': settings.toJson(),
        if (birthPlace != null) 'birthPlace': birthPlace,
        if (longitude != null) 'longitude': longitude,
        if (latitude != null) 'latitude': latitude,
      };

  ZiweiProfile copyWith({String? name}) => ZiweiProfile(
        name: name ?? this.name,
        gender: gender,
        clockBirthDate: clockBirthDate,
        effectiveBirthDate: effectiveBirthDate,
        calendarTypeIndex: calendarTypeIndex,
        settings: settings,
        birthPlace: birthPlace,
        longitude: longitude,
        latitude: latitude,
      );
}

class ZiweiStar {
  const ZiweiStar({
    required this.name,
    required this.type,
    required this.scope,
    required this.brightness,
    required this.mutagen,
  });

  factory ZiweiStar.fromJson(Map<String, dynamic> json) => ZiweiStar(
        name: _text(json['name']),
        type: _text(json['type']),
        scope: _text(json['scope']),
        brightness: _text(json['brightness']),
        mutagen: _text(json['mutagen']),
      );

  final String name;
  final String type;
  final String scope;
  final String brightness;
  final String mutagen;
}

class ZiweiDecadal {
  const ZiweiDecadal({
    required this.startAge,
    required this.endAge,
    required this.heavenlyStem,
    required this.earthlyBranch,
  });

  factory ZiweiDecadal.fromJson(Map<String, dynamic> json) {
    final range = _ints(json['range']);
    return ZiweiDecadal(
      startAge: range.isEmpty ? 0 : range.first,
      endAge: range.length < 2 ? 0 : range[1],
      heavenlyStem: _text(json['heavenlyStem']),
      earthlyBranch: _text(json['earthlyBranch']),
    );
  }

  final int startAge;
  final int endAge;
  final String heavenlyStem;
  final String earthlyBranch;

  String get ganZhi => '$heavenlyStem$earthlyBranch';
}

class ZiweiPalace {
  const ZiweiPalace({
    required this.index,
    required this.name,
    required this.isBodyPalace,
    required this.isOriginalPalace,
    required this.heavenlyStem,
    required this.earthlyBranch,
    required this.majorStars,
    required this.minorStars,
    required this.adjectiveStars,
    required this.changsheng12,
    required this.boshi12,
    required this.jiangqian12,
    required this.suiqian12,
    required this.decadal,
    required this.ages,
  });

  factory ZiweiPalace.fromJson(Map<String, dynamic> json) => ZiweiPalace(
        index: _integer(json['index']),
        name: _text(json['name']),
        isBodyPalace: json['isBodyPalace'] == true,
        isOriginalPalace: json['isOriginalPalace'] == true,
        heavenlyStem: _text(json['heavenlyStem']),
        earthlyBranch: _text(json['earthlyBranch']),
        majorStars: _stars(json['majorStars']),
        minorStars: _stars(json['minorStars']),
        adjectiveStars: _stars(json['adjectiveStars']),
        changsheng12: _text(json['changsheng12']),
        boshi12: _text(json['boshi12']),
        jiangqian12: _text(json['jiangqian12']),
        suiqian12: _text(json['suiqian12']),
        decadal: ZiweiDecadal.fromJson(_map(json['decadal'])),
        ages: _ints(json['ages']),
      );

  final int index;
  final String name;
  final bool isBodyPalace;
  final bool isOriginalPalace;
  final String heavenlyStem;
  final String earthlyBranch;
  final List<ZiweiStar> majorStars;
  final List<ZiweiStar> minorStars;
  final List<ZiweiStar> adjectiveStars;
  final String changsheng12;
  final String boshi12;
  final String jiangqian12;
  final String suiqian12;
  final ZiweiDecadal decadal;
  final List<int> ages;
}

class ZiweiScope {
  const ZiweiScope({
    required this.index,
    required this.name,
    required this.heavenlyStem,
    required this.earthlyBranch,
    required this.palaceNames,
    required this.mutagen,
    required this.stars,
    this.nominalAge,
    this.suiqian12 = const [],
    this.jiangqian12 = const [],
  });

  factory ZiweiScope.fromJson(Map<String, dynamic> json) {
    final yearly = _map(json['yearlyDecStar']);
    return ZiweiScope(
      index: _integer(json['index']),
      name: _text(json['name']),
      heavenlyStem: _text(json['heavenlyStem']),
      earthlyBranch: _text(json['earthlyBranch']),
      palaceNames: _strings(json['palaceNames']),
      mutagen: _strings(json['mutagen']),
      stars: _starGroups(json['stars']),
      nominalAge: json['nominalAge'] is num
          ? (json['nominalAge'] as num).toInt()
          : null,
      suiqian12: _strings(yearly['suiqian12']),
      jiangqian12: _strings(yearly['jiangqian12']),
    );
  }

  final int index;
  final String name;
  final String heavenlyStem;
  final String earthlyBranch;
  final List<String> palaceNames;
  final List<String> mutagen;
  final List<List<ZiweiStar>> stars;
  final int? nominalAge;
  final List<String> suiqian12;
  final List<String> jiangqian12;

  String get ganZhi => '$heavenlyStem$earthlyBranch';
}

class ZiweiAstrolabe {
  const ZiweiAstrolabe({
    required this.gender,
    required this.solarDate,
    required this.lunarDate,
    required this.chineseDate,
    required this.time,
    required this.timeRange,
    required this.sign,
    required this.zodiac,
    required this.bodyPalaceBranch,
    required this.soulPalaceBranch,
    required this.soul,
    required this.body,
    required this.fiveElementsClass,
    required this.palaces,
  });

  factory ZiweiAstrolabe.fromJson(Map<String, dynamic> json) => ZiweiAstrolabe(
        gender: _text(json['gender']),
        solarDate: _text(json['solarDate']),
        lunarDate: _text(json['lunarDate']),
        chineseDate: _text(json['chineseDate']),
        time: _text(json['time']),
        timeRange: _text(json['timeRange']),
        sign: _text(json['sign']),
        zodiac: _text(json['zodiac']),
        bodyPalaceBranch: _text(json['earthlyBranchOfBodyPalace']),
        soulPalaceBranch: _text(json['earthlyBranchOfSoulPalace']),
        soul: _text(json['soul']),
        body: _text(json['body']),
        fiveElementsClass: _text(json['fiveElementsClass']),
        palaces: _maps(json['palaces']).map(ZiweiPalace.fromJson).toList(),
      );

  final String gender;
  final String solarDate;
  final String lunarDate;
  final String chineseDate;
  final String time;
  final String timeRange;
  final String sign;
  final String zodiac;
  final String bodyPalaceBranch;
  final String soulPalaceBranch;
  final String soul;
  final String body;
  final String fiveElementsClass;
  final List<ZiweiPalace> palaces;
}

class ZiweiHoroscope {
  const ZiweiHoroscope({
    required this.solarDate,
    required this.lunarDate,
    required this.decadal,
    required this.age,
    required this.yearly,
    required this.monthly,
    required this.daily,
    required this.hourly,
  });

  factory ZiweiHoroscope.fromJson(Map<String, dynamic> json) => ZiweiHoroscope(
        solarDate: _text(json['solarDate']),
        lunarDate: _text(json['lunarDate']),
        decadal: ZiweiScope.fromJson(_map(json['decadal'])),
        age: ZiweiScope.fromJson(_map(json['age'])),
        yearly: ZiweiScope.fromJson(_map(json['yearly'])),
        monthly: ZiweiScope.fromJson(_map(json['monthly'])),
        daily: ZiweiScope.fromJson(_map(json['daily'])),
        hourly: ZiweiScope.fromJson(_map(json['hourly'])),
      );

  final String solarDate;
  final String lunarDate;
  final ZiweiScope decadal;
  final ZiweiScope age;
  final ZiweiScope yearly;
  final ZiweiScope monthly;
  final ZiweiScope daily;
  final ZiweiScope hourly;

  ZiweiScope? scopeFor(ZiweiLayer layer) => switch (layer) {
        ZiweiLayer.natal => null,
        ZiweiLayer.decadal => decadal,
        ZiweiLayer.age => age,
        ZiweiLayer.yearly => yearly,
        ZiweiLayer.monthly => monthly,
        ZiweiLayer.daily => daily,
        ZiweiLayer.hourly => hourly,
      };
}

class ZiweiChartData {
  const ZiweiChartData({
    this.sourceJson = const {},
    required this.engineName,
    required this.engineVersion,
    required this.ruleCode,
    required this.astrolabe,
    required this.horoscope,
  });

  factory ZiweiChartData.fromJson(Map<String, dynamic> json) {
    final engine = _map(json['engine']);
    return ZiweiChartData(
      sourceJson: Map<String, dynamic>.from(json),
      engineName: _text(engine['name']),
      engineVersion: _text(engine['version']),
      ruleCode: _text(json['ruleCode']),
      astrolabe: ZiweiAstrolabe.fromJson(_map(json['astrolabe'])),
      horoscope: ZiweiHoroscope.fromJson(_map(json['horoscope'])),
    );
  }

  final Map<String, dynamic> sourceJson;
  final String engineName;
  final String engineVersion;
  final String ruleCode;
  final ZiweiAstrolabe astrolabe;
  final ZiweiHoroscope horoscope;

  ZiweiPalace palaceAt(int index) =>
      astrolabe.palaces.firstWhere((palace) => palace.index == index);

  ZiweiPalace oppositePalaceOf(ZiweiPalace palace) =>
      palaceAt((palace.index + 6) % 12);

  /// 空宫统一借用对宫十四主星，后续展示与解读都以这组星为本宫主星。
  List<ZiweiStar> effectiveMajorStarsFor(ZiweiPalace palace) =>
      palace.majorStars.isNotEmpty
          ? palace.majorStars
          : oppositePalaceOf(palace).majorStars;

  bool borrowsOppositeMajorStars(ZiweiPalace palace) =>
      palace.majorStars.isEmpty &&
      oppositePalaceOf(palace).majorStars.isNotEmpty;

  List<ZiweiPalace> get decadals {
    final result = [...astrolabe.palaces];
    result.sort((a, b) => a.decadal.startAge.compareTo(b.decadal.startAge));
    return result;
  }
}

String ziweiRequestCacheKey(Map<String, dynamic> request) =>
    jsonEncode(request);

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

String _text(dynamic value) => value?.toString() ?? '';

int _integer(dynamic value) => value is num ? value.toInt() : 0;

List<String> _strings(dynamic value) =>
    value is List ? value.map((e) => _text(e)).toList() : <String>[];

List<int> _ints(dynamic value) => value is List
    ? value.whereType<num>().map((e) => e.toInt()).toList()
    : <int>[];

List<ZiweiStar> _stars(dynamic value) =>
    _maps(value).map(ZiweiStar.fromJson).toList();

List<List<ZiweiStar>> _starGroups(dynamic value) => value is List
    ? value
        .map((group) => group is List ? _stars(group) : <ZiweiStar>[])
        .toList()
    : <List<ZiweiStar>>[];
