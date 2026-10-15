import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/profile/destiny_archive_repository.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';

enum MatchGender { all, male, female }

enum MatchRegion { sameCity, designated }

enum MatchIntent { friend, love, marriage, culture }

extension MatchIntentText on MatchIntent {
  String get label => switch (this) {
        MatchIntent.friend => '交朋友',
        MatchIntent.love => '认真恋爱',
        MatchIntent.marriage => '长期关系',
        MatchIntent.culture => '文化同好',
      };
  String get value => name;
}

class FateUser {
  final int? userId;
  final int? gender;
  final String? avatarUrl;
  final String name;
  final String age;
  final String zodiac;
  final String constellation;
  final String region;
  final String intro;
  final String tag1;
  final String tag2;
  final int matchScore;
  final String matchTitle;
  final String matchReason;
  final Map<String, int> dimensions;
  final List<String> highlights;
  final List<String> watchouts;
  final List<String> topics;

  const FateUser({
    this.userId,
    this.gender,
    this.avatarUrl,
    required this.name,
    required this.age,
    required this.zodiac,
    required this.constellation,
    required this.region,
    required this.intro,
    required this.tag1,
    required this.tag2,
    required this.matchScore,
    required this.matchTitle,
    required this.matchReason,
    required this.dimensions,
    required this.highlights,
    required this.watchouts,
    required this.topics,
  });

  factory FateUser.fromJson(Map<String, dynamic> value) {
    String text(dynamic data, [String fallback = '']) {
      final result = data?.toString().trim() ?? '';
      return result.isEmpty ? fallback : result;
    }

    List<String> textList(dynamic data) => data is List
        ? data.map((item) => item.toString()).toList()
        : const <String>[];
    final dimensions = <String, int>{};
    if (value['dimensions'] is Map) {
      for (final entry in (value['dimensions'] as Map).entries) {
        if (entry.value is num) {
          dimensions[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }
    final age = value['age'];
    return FateUser(
      userId:
          (value['userId'] as num?)?.toInt() ?? (value['id'] as num?)?.toInt(),
      gender: (value['gender'] as num?)?.toInt(),
      avatarUrl:
          text(value['avatarUrl']).isEmpty ? null : text(value['avatarUrl']),
      name: text(value['nickname'], '用户'),
      age: age == null ? '年龄未公开' : '$age岁',
      zodiac: text(value['zodiac'], '-'),
      constellation: text(value['constellation'], '-'),
      region: text(value['region']),
      intro: text(value['intro'], '还没有填写个人介绍'),
      tag1: text(value['喜神']).isEmpty ? '' : '喜${text(value['喜神'])}',
      tag2: text(value['用神']).isEmpty ? '' : '用${text(value['用神'])}',
      matchScore: (value['matchScore'] as num?)?.toInt() ?? 0,
      matchTitle: text(value['matchTitle'], '初见有缘'),
      matchReason: text(value['matchReason']),
      dimensions: dimensions,
      highlights: textList(value['highlights']),
      watchouts: textList(value['watchouts']),
      topics: textList(value['topics']),
    );
  }
}

class DestinyMatchController extends GetxController {
  DestinyMatchController({SharedPreferences? preferences})
      : _preferences = preferences;

  SharedPreferences? _preferences;
  final _scope = ApiSessionScope();
  int? _userId;
  bool _localStateRestored = false;
  bool archiveReady = false;
  bool privacyReady = false;
  String? archiveError;

  @override
  void onInit() {
    super.onInit();
    final prefs = _preferences;
    if (prefs != null) _restoreLocalState(prefs);
  }

  void _restoreLocalState(SharedPreferences prefs) {
    if (_localStateRestored || !_scope.current || isClosed) return;
    _preferences = prefs;
    _userId = prefs.getInt(AppConstants.keyUserId);
    hideMyBirthDate = prefs.getBool(
          '${DestinyArchiveRepository.hideBirthDatePrefix}$_userId',
        ) ??
        false;
    final snapshot = DestinyArchiveRepository.peek(prefs);
    if (snapshot != null) _applyArchive(snapshot);
    _localStateRestored = true;
  }

  void _applyArchive(DestinyArchiveSnapshot snapshot) {
    myBirth = snapshot.birthDate;
    minglingTitle = snapshot.title;
    minglingTemperament = snapshot.temperament;
    minglingAssetPath = snapshot.assetPath;
    xishen = snapshot.xishen;
    yongshen = snapshot.yongshen;
    zodiac = snapshot.zodiac;
    constellation = snapshot.constellation;
    ziweiPattern = snapshot.ziweiPattern;
    archiveReady = true;
    archiveError = null;
  }

  final GlobalKey archiveCardKey = GlobalKey(
    debugLabel: 'destiny-archive-card',
  );
  bool savingArchiveCard = false;

  String myBirth = '--';
  String xishen = '';
  String yongshen = '';
  String minglingTitle = '八字命灵';
  String minglingTemperament = '正在读取本人命盘';
  String? minglingAssetPath;
  String zodiac = '';
  String constellation = '';
  String ziweiPattern = '';
  bool hideMyBirthDate = false;
  String? currentLocation;
  bool loading = false;
  bool enabling = false;
  bool allowFateMatch = false;
  String? loadError;
  int total = 0;
  int page = 1;
  bool hasMore = false;

  MatchGender gender = MatchGender.all;
  MatchRegion? region;
  MatchIntent intent = MatchIntent.friend;
  String? designatedRegionCode;
  String? designatedRegionLabel;
  final minAgeCtrl = TextEditingController();
  final maxAgeCtrl = TextEditingController();
  bool sameBirth = false;
  String? filterZodiac;
  String? filterConstellation;
  final List<String> filterStems = [];
  final List<String> filterBranches = [];
  final List<String> filterElements = [];
  final List<FateUser> users = [];

  String get visibleBirthDate => hideMyBirthDate ? '' : myBirth;

  static String dayPillarGreeting(String dayGan, String dayZhi) {
    final pillar = '${dayGan.trim()}${dayZhi.trim()}';
    return pillar.isEmpty ? '八字命灵' : '你好，我是$pillar';
  }

  void toggleBirthDateVisibility() {
    hideMyBirthDate = !hideMyBirthDate;
    update(['destiny']);
    unawaited(_saveBirthDateVisibility());
  }

  static const zodiacOptions = [
    '鼠',
    '牛',
    '虎',
    '兔',
    '龙',
    '蛇',
    '马',
    '羊',
    '猴',
    '鸡',
    '狗',
    '猪',
  ];
  static const constellationOptions = [
    '白羊',
    '金牛',
    '双子',
    '巨蟹',
    '狮子',
    '处女',
    '天秤',
    '天蝎',
    '射手',
    '摩羯',
    '水瓶',
    '双鱼',
  ];
  static const stemOptions = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  static const branchOptions = [
    '子',
    '丑',
    '寅',
    '卯',
    '辰',
    '巳',
    '午',
    '未',
    '申',
    '酉',
    '戌',
    '亥',
  ];
  static const elementOptions = ['木', '火', '土', '金', '水'];

  void setGender(MatchGender value) {
    gender = value;
    update(['destiny']);
  }

  void setIntent(MatchIntent value) {
    intent = value;
    update(['destiny']);
  }

  void setRegion(MatchRegion value) {
    if (region == value) {
      region = null;
      if (value == MatchRegion.designated) {
        designatedRegionCode = null;
        designatedRegionLabel = null;
      }
    } else {
      region = value;
    }
    update(['destiny']);
  }

  void setDesignatedRegion({required String code, required String label}) {
    region = MatchRegion.designated;
    designatedRegionCode = code;
    designatedRegionLabel = label;
    update(['destiny']);
  }

  void clearDesignatedRegion() {
    designatedRegionCode = null;
    designatedRegionLabel = null;
    if (region == MatchRegion.designated) region = null;
    update(['destiny']);
  }

  void setFilterZodiac(String? value) {
    filterZodiac = value;
    update(['destiny']);
  }

  void setFilterConstellation(String? value) {
    filterConstellation = value;
    update(['destiny']);
  }

  void toggleFilterStem(String value) {
    filterStems.contains(value)
        ? filterStems.remove(value)
        : filterStems.add(value);
    update(['destiny']);
  }

  void toggleFilterBranch(String value) {
    filterBranches.contains(value)
        ? filterBranches.remove(value)
        : filterBranches.add(value);
    update(['destiny']);
  }

  void clearFilterStems() {
    filterStems.clear();
    update(['destiny']);
  }

  void clearFilterBranches() {
    filterBranches.clear();
    update(['destiny']);
  }

  void toggleFilterElement(String value) {
    if (filterElements.contains(value)) {
      filterElements.remove(value);
    } else if (filterElements.length < 2) {
      filterElements.add(value);
    } else {
      Get.snackbar('提示', '五行最多选择两个', snackPosition: SnackPosition.BOTTOM);
    }
    update(['destiny']);
  }

  void toggleSameBirth() {
    sameBirth = !sameBirth;
    update(['destiny']);
  }

  Future<void> enableMatching() async {
    if (enabling) return;
    enabling = true;
    update(['destiny']);
    try {
      await _scope.patch('/api/auth/privacy', data: {'allowFateMatch': 1});
      allowFateMatch = true;
      await loadUsers();
    } on DioException catch (_) {
      loadError = '开启失败，请稍后重试';
    } on ApiSessionChangedException catch (_) {
      return;
    } finally {
      enabling = false;
      if (!isClosed && _scope.current) update(['destiny']);
    }
  }

  Future<void> onSearch() => loadUsers();

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    await loadUsers(reset: false);
  }

  Map<String, dynamic> _query(int queryPage) {
    final query = <String, dynamic>{
      'intent': intent.value,
      'page': queryPage,
      'page_size': 20,
    };
    if (gender == MatchGender.male) query['gender'] = 1;
    if (gender == MatchGender.female) query['gender'] = 2;
    final minAge = int.tryParse(minAgeCtrl.text.trim());
    final maxAge = int.tryParse(maxAgeCtrl.text.trim());
    if (minAge != null) query['age_min'] = minAge;
    if (maxAge != null) query['age_max'] = maxAge;
    if (sameBirth) query['same_birth_date'] = 1;
    if (filterStems.isNotEmpty) query['stems'] = filterStems.join(',');
    if (filterBranches.isNotEmpty) query['branches'] = filterBranches.join(',');
    if (filterElements.isNotEmpty) query['elements'] = filterElements.join(',');
    if (region == MatchRegion.sameCity && (currentLocation ?? '').isNotEmpty) {
      query['region'] = currentLocation;
    }
    if (region == MatchRegion.designated &&
        (designatedRegionCode ?? '').isNotEmpty) {
      query['region'] = designatedRegionCode;
    }
    if ((filterZodiac ?? '').isNotEmpty) query['zodiac'] = filterZodiac;
    if ((filterConstellation ?? '').isNotEmpty) {
      query['constellation'] = filterConstellation;
    }
    return query;
  }

  Future<void> loadUsers({bool reset = true}) async {
    if (!allowFateMatch) return;
    loading = true;
    loadError = null;
    final targetPage = reset ? 1 : page + 1;
    update(['destiny']);
    try {
      final res = await _scope.get(
        '/api/fortune/fate-match',
        queryParameters: _query(targetPage),
      );
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null) {
        final parsed = (data['list'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => FateUser.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        if (reset) users.clear();
        users.addAll(
          parsed.where(
            (item) => !users.any((existing) => existing.userId == item.userId),
          ),
        );
        page = (data['page'] as num?)?.toInt() ?? targetPage;
        total = (data['total'] as num?)?.toInt() ?? users.length;
        hasMore = data['hasMore'] == true;
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      if (response is Map &&
          response['data'] is Map &&
          (response['data'] as Map)['requiresOptIn'] == true) {
        allowFateMatch = false;
      }
      loadError = response is Map && response['message'] != null
          ? response['message'].toString()
          : '加载失败';
    } catch (_) {
      loadError = '加载失败';
    } finally {
      loading = false;
      update(['destiny']);
    }
  }

  Future<Map<String, dynamic>?> createConversation(FateUser user) async {
    if (user.userId == null) return null;
    final res = await _scope.post(
      '/api/im/conversation/single',
      data: {'targetUserId': user.userId},
    );
    final data = (res.data as Map?)?['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<void> _loadLocation() async {
    try {
      final res = await _scope.get('/api/auth/location');
      final data = (res.data as Map?)?['data'] as Map?;
      currentLocation = data?['locationCode']?.toString().trim();
      if ((currentLocation ?? '').isEmpty) {
        currentLocation = data?['location']?.toString().trim();
      }
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
  }

  Future<void> _saveBirthDateVisibility() async {
    final hidden = hideMyBirthDate;
    final userId = _userId;
    try {
      final prefs = _preferences ?? await SharedPreferences.getInstance();
      if (!_scope.current ||
          userId == null ||
          prefs.getInt(AppConstants.keyUserId) != userId) {
        return;
      }
      await prefs.setBool(
        '${DestinyArchiveRepository.hideBirthDatePrefix}$userId',
        hidden,
      );
    } catch (_) {}
  }

  Future<void> loadArchive() async {
    if (!_scope.current || isClosed) return;
    archiveError = null;
    update(['destiny']);
    try {
      final snapshot = await DestinyArchiveRepository.load();
      if (!_scope.current || isClosed) return;
      _applyArchive(snapshot);
    } catch (_) {
      if (!_scope.current || isClosed) return;
      // 已有卡片在断网时继续展示，不退回占位文字。
      if (!archiveReady) archiveError = '档案暂时读取失败，点击重试';
    }
    if (!isClosed && _scope.current) update(['destiny']);
  }

  Future<void> _loadProfileAndPrivacy() async {
    try {
      final response = await _scope.get('/api/auth/privacy');
      final privacy = (response.data as Map?)?['data'] as Map?;
      allowFateMatch =
          privacy?['allowFateMatch'] == 1 || privacy?['allowFateMatch'] == true;
    } catch (_) {}
    if (isClosed || !_scope.current) return;
    privacyReady = true;
    update(['destiny']);
  }

  @override
  void onReady() {
    super.onReady();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    if (isClosed || !_scope.current) return;
    _restoreLocalState(prefs);
    update(['destiny']);
    // 匹配列表不等待命盘计算；首张卡片则待各字段齐备后一次展示。
    unawaited(loadArchive());
    await Future.wait([_loadProfileAndPrivacy(), _loadLocation()]);
    if (!isClosed && _scope.current && allowFateMatch) await loadUsers();
  }

  @override
  void onClose() {
    minAgeCtrl.dispose();
    maxAgeCtrl.dispose();
    super.onClose();
  }
}
