import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xuanyu/core/config/app_content_config.dart';
import 'package:xuanyu/core/local/account_preference_scope.dart';
import 'package:xuanyu/core/theme/app_colors.dart';

enum MeritExperienceMode {
  calm('calm', '静心'),
  release('release', '解压'),
  sleep('sleep', '睡前');

  const MeritExperienceMode(this.key, this.label);

  final String key;
  final String label;

  static MeritExperienceMode fromKey(String? key) {
    return MeritExperienceMode.values.firstWhere(
      (mode) => mode.key == key,
      orElse: () => MeritExperienceMode.calm,
    );
  }
}

/// 木鱼玩法数据模型
class MeritTextItem {
  const MeritTextItem({
    required this.id,
    required this.content,
    required this.category,
    required this.rarity,
    required this.reincarnationTier,
    this.hidden = false,
  });

  final String id;
  final String content;
  final String category;
  final String rarity;
  final int reincarnationTier;
  final bool hidden;

  factory MeritTextItem.fromJson(Map<String, dynamic> j) => MeritTextItem(
        id: j['id'] as String,
        content: j['content'] as String,
        category: j['category'] as String,
        rarity: j['rarity'] as String,
        reincarnationTier: (j['reincarnationTier'] as num?)?.toInt() ?? 0,
        hidden: j['hidden'] as bool? ?? false,
      );
}

class MeritLifeTitle {
  const MeritLifeTitle({
    required this.id,
    required this.threshold,
    required this.name,
    required this.message,
  });

  final String id;
  final int threshold;
  final String name;
  final String message;

  factory MeritLifeTitle.fromJson(Map<String, dynamic> j) => MeritLifeTitle(
        id: j['id'] as String,
        threshold: (j['threshold'] as num).toInt(),
        name: j['name'] as String,
        message: j['message'] as String,
      );
}

class MeritReincarnationTitle {
  const MeritReincarnationTitle({
    required this.count,
    required this.name,
    required this.unlock,
  });

  final int count;
  final String name;
  final String unlock;

  factory MeritReincarnationTitle.fromJson(Map<String, dynamic> j) =>
      MeritReincarnationTitle(
        count: (j['count'] as num).toInt(),
        name: j['name'] as String,
        unlock: j['unlock'] as String,
      );
}

class MeritAchievementDef {
  const MeritAchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.threshold,
    this.reward = 0,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final int threshold;
  final int reward;

  factory MeritAchievementDef.fromJson(Map<String, dynamic> j) =>
      MeritAchievementDef(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String,
        type: j['type'] as String,
        threshold: (j['threshold'] as num).toInt(),
        reward: (j['reward'] as num?)?.toInt() ?? 0,
      );
}

class MeritGameConfig {
  const MeritGameConfig({
    required this.reincarnationThreshold,
    required this.comboContinueMs,
    required this.comboBreakMs,
    required this.eventBaseProbability,
    required this.eventPityTaps,
    required this.rarityCommon,
    required this.rarityRare,
    required this.rarityEpic,
    required this.karmaCoinMultiplier,
    required this.karmaRareBonus,
    required this.karmaEpicBonus,
    required this.karmaEventBonus,
    required this.comboDoubleCoin,
    required this.comboRareBoost,
    required this.comboAngryFish,
    required this.comboForceEpic,
    required this.comboSpeedDemon,
    required this.comboGodSpeed,
    required this.angryFishCoins,
    required this.forceEpicCoins,
    required this.coinMin,
    required this.coinMax,
    required this.upgradeBaseCost,
    required this.upgradeCostFactor,
    required this.levelCoinBonusPerLevel,
    required this.level30EpicBonus,
    required this.unlockAtlas,
    required this.unlockSkins,
    required this.unlockRarePool,
    required this.unlockComboStyle,
    required this.unlockLifeTitle,
    required this.unlockMaxLevel,
  });

  final int reincarnationThreshold;
  final int comboContinueMs;
  final int comboBreakMs;
  final double eventBaseProbability;
  final int eventPityTaps;
  final double rarityCommon;
  final double rarityRare;
  final double rarityEpic;
  final double karmaCoinMultiplier;
  final double karmaRareBonus;
  final double karmaEpicBonus;
  final double karmaEventBonus;
  final int comboDoubleCoin;
  final int comboRareBoost;
  final int comboAngryFish;
  final int comboForceEpic;
  final int comboSpeedDemon;
  final int comboGodSpeed;
  final int angryFishCoins;
  final int forceEpicCoins;
  final int coinMin;
  final int coinMax;
  final int upgradeBaseCost;
  final double upgradeCostFactor;
  final double levelCoinBonusPerLevel;
  final double level30EpicBonus;
  final int unlockAtlas;
  final int unlockSkins;
  final int unlockRarePool;
  final int unlockComboStyle;
  final int unlockLifeTitle;
  final int unlockMaxLevel;

  factory MeritGameConfig.fromJson(Map<String, dynamic> j) {
    final karma = j['karmaPerReincarnation'] as Map<String, dynamic>;
    final combo = j['comboThresholds'] as Map<String, dynamic>;
    final rewards = j['comboRewards'] as Map<String, dynamic>;
    final rarity = j['rarityBase'] as Map<String, dynamic>;
    final coin = j['coinDrop'] as Map<String, dynamic>;
    final levels = j['woodenFishUnlockLevels'] as Map<String, dynamic>;
    return MeritGameConfig(
      reincarnationThreshold: (j['reincarnationThreshold'] as num).toInt(),
      comboContinueMs: (j['comboContinueMs'] as num).toInt(),
      comboBreakMs: (j['comboBreakMs'] as num).toInt(),
      eventBaseProbability: (j['eventBaseProbability'] as num).toDouble(),
      eventPityTaps: (j['eventPityTaps'] as num).toInt(),
      rarityCommon: (rarity['common'] as num).toDouble(),
      rarityRare: (rarity['rare'] as num).toDouble(),
      rarityEpic: (rarity['epic'] as num).toDouble(),
      karmaCoinMultiplier: (karma['coinMultiplier'] as num).toDouble(),
      karmaRareBonus: (karma['rareBonus'] as num).toDouble(),
      karmaEpicBonus: (karma['epicBonus'] as num).toDouble(),
      karmaEventBonus: (karma['eventBonus'] as num).toDouble(),
      comboDoubleCoin: (combo['doubleCoin'] as num).toInt(),
      comboRareBoost: (combo['rareBoost'] as num).toInt(),
      comboAngryFish: (combo['angryFish'] as num).toInt(),
      comboForceEpic: (combo['forceEpic'] as num).toInt(),
      comboSpeedDemon: (combo['speedDemon'] as num).toInt(),
      comboGodSpeed: (combo['godSpeed'] as num).toInt(),
      angryFishCoins: (rewards['angryFishCoins'] as num).toInt(),
      forceEpicCoins: (rewards['forceEpicCoins'] as num).toInt(),
      coinMin: (coin['min'] as num).toInt(),
      coinMax: (coin['max'] as num).toInt(),
      upgradeBaseCost: (j['upgradeBaseCost'] as num).toInt(),
      upgradeCostFactor: (j['upgradeCostFactor'] as num).toDouble(),
      levelCoinBonusPerLevel: (j['levelCoinBonusPerLevel'] as num).toDouble(),
      level30EpicBonus: (j['level30EpicBonus'] as num).toDouble(),
      unlockAtlas: (levels['atlas'] as num).toInt(),
      unlockSkins: (levels['skins'] as num).toInt(),
      unlockRarePool: (levels['rarePool'] as num).toInt(),
      unlockComboStyle: (levels['comboStyle'] as num).toInt(),
      unlockLifeTitle: (levels['lifeTitle'] as num).toInt(),
      unlockMaxLevel: (levels['max'] as num).toInt(),
    );
  }
}

class MeritBundle {
  const MeritBundle({
    required this.game,
    required this.texts,
    required this.lifeTitles,
    required this.reincarnationTitles,
    required this.lifeAchievements,
    required this.permanentAchievements,
  });

  final MeritGameConfig game;
  final List<MeritTextItem> texts;
  final List<MeritLifeTitle> lifeTitles;
  final List<MeritReincarnationTitle> reincarnationTitles;
  final List<MeritAchievementDef> lifeAchievements;
  final List<MeritAchievementDef> permanentAchievements;
}

/// 随机事件类型
enum MeritEventType {
  buddhaPass,
  bossCheck,
  fishMood,
  karmaBacklash,
  fortuneGod,
}

class MeritPendingEvent {
  const MeritPendingEvent({required this.type, this.payload});

  final MeritEventType type;
  final Map<String, dynamic>? payload;
}

/// 敲击一次的结果（供 UI 反馈）
class MeritTapResult {
  const MeritTapResult({
    required this.coinsEarned,
    this.text,
    required this.combo,
    this.comboBroken = false,
    this.comboSettlementCoins = 0,
    this.comboSettlementCount = 0,
    this.pendingEvent,
    this.newLifeTitles = const [],
    this.newLifeAchievements = const [],
    this.newPermanentAchievements = const [],
    this.triggerAngryFish = false,
    this.triggerSpeedDemon = false,
    this.triggerGodSpeed = false,
    this.showEpicPoster = false,
    this.canReincarnate = false,
    this.floatingCoins = const [],
  });

  final int coinsEarned;
  final MeritTextItem? text;
  final int combo;
  final bool comboBroken;
  final int comboSettlementCoins;
  final int comboSettlementCount;
  final MeritPendingEvent? pendingEvent;
  final List<MeritLifeTitle> newLifeTitles;
  final List<MeritAchievementDef> newLifeAchievements;
  final List<MeritAchievementDef> newPermanentAchievements;
  final bool triggerAngryFish;
  final bool triggerSpeedDemon;
  final bool triggerGodSpeed;
  final bool showEpicPoster;
  final bool canReincarnate;
  final List<int> floatingCoins;
}

/// 存档
class MeritSaveData {
  /// Runtime ownership only: never serialized or uploaded.
  AccountPreferenceScope? accountScope;
  MeritSaveData({
    this.totalTaps = 0,
    this.reincarnationCount = 0,
    this.karmaCoinBonus = 0,
    this.karmaRareBonus = 0,
    this.karmaEpicBonus = 0,
    this.karmaEventBonus = 0,
    Set<String>? collectedTextIds,
    Set<String>? permanentAchievements,
    Set<String>? unlockedSkins,
    this.activeSkin = 'rebirth_1',
    this.lifeTaps = 0,
    this.negativeCoins = 0,
    this.woodenFishLevel = 1,
    Set<String>? lifeTitles,
    Set<String>? lifeAchievements,
    List<String>? todayShownTextIds,
    this.tapsSinceLastEvent = 0,
    this.lifeEventsTriggered = 0,
    this.lastDailyDate = '',
    this.todayTaps = 0,
    this.dailyStreak = 0,
    this.lastPlayDate = '',
    this.maxComboEver = 0,
    this.workdayTaps = 0,
    this.nightSessionTaps = 0,
    this.mondaySessionTaps = 0,
    this.consecutiveEpicTaps = 0,
    this.skinFragments = 0,
    this.soundEnabled = true,
    this.soundVolume = 0.52,
    this.vibrationEnabled = true,
    this.autoKnockIntervalMs = 280,
    this.comboEffectsEnabled = true,
    this.experienceMode = MeritExperienceMode.calm,
    this.doubleCoinBuffUntilMs = 0,
    this.silentTapsRemaining = 0,
    this.forceToxicRemaining = 0,
    this.pendingHardKnockReward = false,
    this.lifeTextCollectedCount = 0,
  })  : collectedTextIds = collectedTextIds ?? {},
        permanentAchievements = permanentAchievements ?? {},
        unlockedSkins = unlockedSkins ?? {'rebirth_1'},
        lifeTitles = lifeTitles ?? {},
        lifeAchievements = lifeAchievements ?? {},
        todayShownTextIds = todayShownTextIds ?? [];

  int totalTaps;
  int reincarnationCount;
  double karmaCoinBonus;
  double karmaRareBonus;
  double karmaEpicBonus;
  double karmaEventBonus;
  Set<String> collectedTextIds;
  Set<String> permanentAchievements;
  Set<String> unlockedSkins;
  String activeSkin;
  int lifeTaps;
  int negativeCoins;
  int woodenFishLevel;
  Set<String> lifeTitles;
  Set<String> lifeAchievements;
  List<String> todayShownTextIds;
  int tapsSinceLastEvent;
  int lifeEventsTriggered;
  String lastDailyDate;
  int todayTaps;
  int dailyStreak;
  String lastPlayDate;
  int maxComboEver;
  int workdayTaps;
  int nightSessionTaps;
  int mondaySessionTaps;
  int consecutiveEpicTaps;
  int skinFragments;
  bool soundEnabled;
  double soundVolume;
  bool vibrationEnabled;
  int autoKnockIntervalMs;
  bool comboEffectsEnabled;
  MeritExperienceMode experienceMode;
  int doubleCoinBuffUntilMs;
  int silentTapsRemaining;
  int forceToxicRemaining;
  bool pendingHardKnockReward;
  int lifeTextCollectedCount;

  Map<String, dynamic> toJson() => {
        'totalTaps': totalTaps,
        'reincarnationCount': reincarnationCount,
        'karmaCoinBonus': karmaCoinBonus,
        'karmaRareBonus': karmaRareBonus,
        'karmaEpicBonus': karmaEpicBonus,
        'karmaEventBonus': karmaEventBonus,
        'collectedTextIds': collectedTextIds.toList(),
        'permanentAchievements': permanentAchievements.toList(),
        'unlockedSkins': unlockedSkins.toList(),
        'activeSkin': activeSkin,
        'lifeTaps': lifeTaps,
        'negativeCoins': negativeCoins,
        'woodenFishLevel': woodenFishLevel,
        'lifeTitles': lifeTitles.toList(),
        'lifeAchievements': lifeAchievements.toList(),
        'todayShownTextIds': todayShownTextIds,
        'tapsSinceLastEvent': tapsSinceLastEvent,
        'lifeEventsTriggered': lifeEventsTriggered,
        'lastDailyDate': lastDailyDate,
        'todayTaps': todayTaps,
        'dailyStreak': dailyStreak,
        'lastPlayDate': lastPlayDate,
        'maxComboEver': maxComboEver,
        'workdayTaps': workdayTaps,
        'nightSessionTaps': nightSessionTaps,
        'mondaySessionTaps': mondaySessionTaps,
        'consecutiveEpicTaps': consecutiveEpicTaps,
        'skinFragments': skinFragments,
        'soundEnabled': soundEnabled,
        'soundVolume': soundVolume,
        'vibrationEnabled': vibrationEnabled,
        'autoKnockIntervalMs': autoKnockIntervalMs,
        'comboEffectsEnabled': comboEffectsEnabled,
        'experienceMode': experienceMode.key,
        'doubleCoinBuffUntilMs': doubleCoinBuffUntilMs,
        'silentTapsRemaining': silentTapsRemaining,
        'forceToxicRemaining': forceToxicRemaining,
        'pendingHardKnockReward': pendingHardKnockReward,
        'lifeTextCollectedCount': lifeTextCollectedCount,
      };

  static String _migrateSkinId(String? id) {
    if (id == null || id.isEmpty || id == 'default') return 'rebirth_1';
    return id;
  }

  factory MeritSaveData.fromJson(Map<String, dynamic> j) => MeritSaveData(
        totalTaps: (j['totalTaps'] as num?)?.toInt() ?? 0,
        reincarnationCount: (j['reincarnationCount'] as num?)?.toInt() ?? 0,
        karmaCoinBonus: (j['karmaCoinBonus'] as num?)?.toDouble() ?? 0,
        karmaRareBonus: (j['karmaRareBonus'] as num?)?.toDouble() ?? 0,
        karmaEpicBonus: (j['karmaEpicBonus'] as num?)?.toDouble() ?? 0,
        karmaEventBonus: (j['karmaEventBonus'] as num?)?.toDouble() ?? 0,
        collectedTextIds:
            Set<String>.from(j['collectedTextIds'] as List? ?? []),
        permanentAchievements:
            Set<String>.from(j['permanentAchievements'] as List? ?? []),
        unlockedSkins:
            Set<String>.from(j['unlockedSkins'] as List? ?? ['rebirth_1']),
        activeSkin: _migrateSkinId(j['activeSkin'] as String?),
        lifeTaps: (j['lifeTaps'] as num?)?.toInt() ?? 0,
        negativeCoins: (j['negativeCoins'] as num?)?.toInt() ?? 0,
        woodenFishLevel: (j['woodenFishLevel'] as num?)?.toInt() ?? 1,
        lifeTitles: Set<String>.from(j['lifeTitles'] as List? ?? []),
        lifeAchievements:
            Set<String>.from(j['lifeAchievements'] as List? ?? []),
        todayShownTextIds:
            List<String>.from(j['todayShownTextIds'] as List? ?? []),
        tapsSinceLastEvent: (j['tapsSinceLastEvent'] as num?)?.toInt() ?? 0,
        lifeEventsTriggered: (j['lifeEventsTriggered'] as num?)?.toInt() ?? 0,
        lastDailyDate: j['lastDailyDate'] as String? ?? '',
        todayTaps: (j['todayTaps'] as num?)?.toInt() ?? 0,
        dailyStreak: (j['dailyStreak'] as num?)?.toInt() ?? 0,
        lastPlayDate: j['lastPlayDate'] as String? ?? '',
        maxComboEver: (j['maxComboEver'] as num?)?.toInt() ?? 0,
        workdayTaps: (j['workdayTaps'] as num?)?.toInt() ?? 0,
        nightSessionTaps: (j['nightSessionTaps'] as num?)?.toInt() ?? 0,
        mondaySessionTaps: (j['mondaySessionTaps'] as num?)?.toInt() ?? 0,
        consecutiveEpicTaps: (j['consecutiveEpicTaps'] as num?)?.toInt() ?? 0,
        skinFragments: (j['skinFragments'] as num?)?.toInt() ?? 0,
        soundEnabled: j['soundEnabled'] as bool? ?? true,
        soundVolume:
            ((j['soundVolume'] as num?)?.toDouble() ?? 0.52).clamp(0.2, 1.0),
        vibrationEnabled: j['vibrationEnabled'] as bool? ?? true,
        autoKnockIntervalMs:
            ((j['autoKnockIntervalMs'] as num?)?.toInt() ?? 280)
                .clamp(160, 650),
        comboEffectsEnabled: j['comboEffectsEnabled'] as bool? ?? true,
        experienceMode:
            MeritExperienceMode.fromKey(j['experienceMode'] as String?),
        doubleCoinBuffUntilMs:
            (j['doubleCoinBuffUntilMs'] as num?)?.toInt() ?? 0,
        silentTapsRemaining: (j['silentTapsRemaining'] as num?)?.toInt() ?? 0,
        forceToxicRemaining: (j['forceToxicRemaining'] as num?)?.toInt() ?? 0,
        pendingHardKnockReward: j['pendingHardKnockReward'] as bool? ?? false,
        lifeTextCollectedCount:
            (j['lifeTextCollectedCount'] as num?)?.toInt() ?? 0,
      );
}

class MeritConfigLoader {
  MeritConfigLoader._();
  static MeritBundle? _cached;

  static Future<MeritBundle> load() async {
    if (_cached != null) return _cached!;
    await AppContentConfig.load();
    final gameRaw =
        await rootBundle.loadString('assets/merit/game_config.json');
    final textRaw =
        await rootBundle.loadString('assets/merit/text_config.json');
    final titleRaw =
        await rootBundle.loadString('assets/merit/title_config.json');
    final achRaw =
        await rootBundle.loadString('assets/merit/achievement_config.json');

    final gameJson = jsonDecode(gameRaw) as Map<String, dynamic>;
    final textJson = jsonDecode(textRaw) as Map<String, dynamic>;
    final titleJson = jsonDecode(titleRaw) as Map<String, dynamic>;
    final achJson = jsonDecode(achRaw) as Map<String, dynamic>;
    final remoteMerit = AppContentConfig.section('merit');
    final remoteGame = remoteMerit['game'];
    if (remoteGame is Map) {
      gameJson.addAll(Map<String, dynamic>.from(remoteGame));
    }
    List<dynamic> listOrDefault(String key, List<dynamic> fallback) {
      final value = remoteMerit[key];
      return value is List && value.isNotEmpty ? value : fallback;
    }

    List<dynamic> mergedTexts() {
      final local = textJson['texts'] as List<dynamic>;
      final remote = remoteMerit['texts'];
      if (remote is! List || remote.isEmpty) return local;
      final byId = <String, dynamic>{};
      for (final item in local) {
        if (item is Map && item['id'] != null) {
          byId[item['id'].toString()] = item;
        }
      }
      // 服务端仍可覆盖同 id 文案，但本地新增的静心/睡前文案不会被旧配置抹掉。
      for (final item in remote) {
        if (item is Map && item['id'] != null) {
          byId[item['id'].toString()] = item;
        }
      }
      return byId.values.toList();
    }

    _cached = MeritBundle(
      game: MeritGameConfig.fromJson(gameJson),
      texts: mergedTexts()
          .map((e) => MeritTextItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      lifeTitles: listOrDefault('lifeTitles', titleJson['lifeTitles'] as List)
          .map((e) => MeritLifeTitle.fromJson(e as Map<String, dynamic>))
          .toList(),
      reincarnationTitles: listOrDefault(
              'reincarnationTitles', titleJson['reincarnationTitles'] as List)
          .map((e) =>
              MeritReincarnationTitle.fromJson(e as Map<String, dynamic>))
          .toList(),
      lifeAchievements: listOrDefault(
              'lifeAchievements', achJson['lifeAchievements'] as List)
          .map((e) => MeritAchievementDef.fromJson(e as Map<String, dynamic>))
          .toList(),
      permanentAchievements: listOrDefault(
              'permanentAchievements', achJson['permanentAchievements'] as List)
          .map((e) => MeritAchievementDef.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return _cached!;
  }
}

/// 木鱼页配色（与首页 AppColors 统一）
class MeritColors {
  MeritColors._();

  static const bg = AppColors.background;
  static const card = AppColors.surface;
  static const cardBorder = AppColors.divider;
  static const gold = AppColors.primary;
  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const epic = Color(0xFF7C3AED);
  static const rare = AppColors.accentGold;

  static const LinearGradient bodyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF2FCFB),
      Color(0xFFE4F6F4),
      Color(0xFFE9EEF5),
    ],
    stops: [0.0, 0.55, 1.0],
  );
}
