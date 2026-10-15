import 'dart:async';
import 'dart:math';

import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';

/// 木鱼核心逻辑：纯手动敲击，无挂机
class MeritEngine {
  MeritEngine({required this.bundle, required this.data});

  final MeritBundle bundle;
  final MeritSaveData data;
  final Random _rng = Random();

  int _combo = 0;
  int _comboCycleCoins = 0;

  /// 用单调时钟避免 DateTime 抖动导致连击错位
  int? _lastTapMs;
  final List<MeritPendingEvent> _queuedEvents = [];
  Timer? _saveDebounce;

  MeritGameConfig get cfg => bundle.game;

  int get combo => _combo;
  List<MeritPendingEvent> get queuedEvents => List.unmodifiable(_queuedEvents);

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  String get reincarnationBadge {
    if (data.reincarnationCount <= 0) return '';
    final titles = bundle.reincarnationTitles
        .where((t) => data.reincarnationCount >= t.count)
        .toList();
    if (titles.isEmpty) return '${data.reincarnationCount}转';
    return '${data.reincarnationCount}转·${titles.last.name}';
  }

  String? get currentLifeTitle {
    MeritLifeTitle? best;
    for (final t in bundle.lifeTitles) {
      if (data.lifeTaps >= t.threshold) best = t;
    }
    return best?.name;
  }

  int upgradeCost() {
    final lv = data.woodenFishLevel;
    if (lv >= cfg.unlockMaxLevel) return 0;
    return (cfg.upgradeBaseCost * pow(cfg.upgradeCostFactor, lv - 1)).floor();
  }

  double coinMultiplier() {
    var m = 1.0 +
        data.karmaCoinBonus +
        (data.woodenFishLevel - 1) * cfg.levelCoinBonusPerLevel;
    if (_nowMs < data.doubleCoinBuffUntilMs) m *= 2;
    if (_combo >= cfg.comboDoubleCoin) m *= 2;
    return m;
  }

  /// 同步计数，避免快速连点 await 存档造成竞态错数
  MeritTapResult tap({
    MeritExperienceMode mode = MeritExperienceMode.calm,
  }) {
    MeritStorageService.refreshDaily(data);
    final comboBreak = _applyComboOnTap();

    data.lifeTaps += 1;
    data.totalTaps += 1;
    data.todayTaps += 1;
    data.lastPlayDate = DateTime.now().toIso8601String().split('T').first;
    _trackSessionTaps();

    var coins = _rollCoins();
    final comboRewards = _applyComboThresholds();
    coins += comboRewards.extraCoins;
    data.negativeCoins += coins;
    _comboCycleCoins += coins;

    MeritTextItem? text;
    var showEpicPoster = false;
    if (mode == MeritExperienceMode.release && data.silentTapsRemaining > 0) {
      data.silentTapsRemaining -= 1;
      if (data.silentTapsRemaining == 0 && data.pendingHardKnockReward) {
        text = _pickText(forceEpic: true, mode: mode);
        data.pendingHardKnockReward = false;
        showEpicPoster = text?.rarity == 'epic';
      }
    } else {
      final forceEpic = comboRewards.forceEpic;
      text = _pickText(forceEpic: forceEpic, mode: mode);
      if (text != null) {
        showEpicPoster = text.rarity == 'epic';
        if (text.rarity == 'epic') {
          data.consecutiveEpicTaps += 1;
        } else {
          data.consecutiveEpicTaps = 0;
        }
        if (mode == MeritExperienceMode.release &&
            data.forceToxicRemaining > 0) {
          data.forceToxicRemaining -= 1;
        }
      }
    }

    if (_combo > data.maxComboEver) data.maxComboEver = _combo;

    final newLifeTitles = _checkLifeTitles();
    final event =
        mode == MeritExperienceMode.release ? _maybeTriggerEvent() : null;
    final newLifeAch = _checkLifeAchievements();
    final newPermAch = _checkPermanentAchievements();

    final canReincarnate = data.lifeTaps >= cfg.reincarnationThreshold;

    _scheduleSave();

    return MeritTapResult(
      coinsEarned: coins,
      text: text,
      combo: _combo,
      comboBroken: comboBreak.broken,
      comboSettlementCoins: comboBreak.broken ? comboBreak.settlementCoins : 0,
      comboSettlementCount: comboBreak.broken ? comboBreak.brokenAt : 0,
      pendingEvent: event,
      newLifeTitles: newLifeTitles,
      newLifeAchievements: newLifeAch,
      newPermanentAchievements: newPermAch,
      triggerAngryFish: comboRewards.angryFish,
      triggerSpeedDemon: comboRewards.speedDemon,
      triggerGodSpeed: comboRewards.godSpeed,
      showEpicPoster: showEpicPoster,
      canReincarnate: canReincarnate,
      floatingCoins: [coins],
    );
  }

  /// 停手超时后结算连击（不需要再点一下才清零）
  MeritTapResult? settleIdleCombo() {
    if (_combo <= 1 || _lastTapMs == null) return null;
    final gap = _nowMs - _lastTapMs!;
    if (gap <= cfg.comboBreakMs) return null;

    final brokenAt = _combo;
    final settlementCoins = _comboCycleCoins;
    _combo = 0;
    _comboCycleCoins = 0;
    _scheduleSave();
    return MeritTapResult(
      coinsEarned: 0,
      combo: 0,
      comboBroken: true,
      comboSettlementCoins: settlementCoins,
      comboSettlementCount: brokenAt,
    );
  }

  /// 统一窗口：间隔 ≤ comboBreakMs 续连；＞ 则断连结算后从 1 开始。
  /// （原先 300–500ms「灰区」静默清零，会造成显示连击与手感对不上）
  _ComboBreak _applyComboOnTap() {
    final now = _nowMs;
    var broken = false;
    var brokenAt = 0;
    var settlementCoins = 0;

    if (_lastTapMs != null) {
      final gap = now - _lastTapMs!;
      if (gap > cfg.comboBreakMs) {
        if (_combo > 1) {
          broken = true;
          brokenAt = _combo;
          settlementCoins = _comboCycleCoins;
        }
        _combo = 1;
        _comboCycleCoins = 0;
      } else {
        _combo += 1;
      }
    } else {
      _combo = 1;
    }
    _lastTapMs = now;
    return _ComboBreak(
        broken: broken, brokenAt: brokenAt, settlementCoins: settlementCoins);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      MeritStorageService.save(data);
    });
  }

  Future<void> flushSave() async {
    _saveDebounce?.cancel();
    await MeritStorageService.save(data, immediateCloud: true);
  }

  int _rollCoins() {
    final base = cfg.coinMin + _rng.nextInt(cfg.coinMax - cfg.coinMin + 1);
    return (base * coinMultiplier()).round().clamp(1, 999999);
  }

  _ComboReward _applyComboThresholds() {
    var extra = 0;
    var forceEpic = false;
    var angry = false;
    var speed = false;
    var god = false;

    if (_combo == cfg.comboForceEpic) {
      forceEpic = true;
      extra += cfg.forceEpicCoins;
    }
    if (_combo == cfg.comboAngryFish) {
      angry = true;
      extra += cfg.angryFishCoins;
    }
    if (_combo == cfg.comboSpeedDemon) {
      speed = true;
    }
    if (_combo == cfg.comboGodSpeed) {
      god = true;
      data.skinFragments += 1;
    }

    return _ComboReward(
      extraCoins: extra,
      forceEpic: forceEpic,
      angryFish: angry,
      speedDemon: speed,
      godSpeed: god,
    );
  }

  MeritTextItem? _pickText({
    bool forceEpic = false,
    MeritExperienceMode mode = MeritExperienceMode.calm,
  }) {
    final pool = bundle.texts.where((t) {
      final isCalm = t.category == 'calm' || t.category == 'warm';
      final isSleep = t.category == 'sleep';
      final allowedForMode = switch (mode) {
        MeritExperienceMode.calm => isCalm,
        MeritExperienceMode.sleep => isCalm || isSleep,
        MeritExperienceMode.release => !isCalm && !isSleep,
      };
      if (!allowedForMode) return false;
      if (t.reincarnationTier > data.reincarnationCount) return false;
      if (t.hidden && !data.permanentAchievements.contains('perm_rebirth1')) {
        // hidden unlocked via events
      }
      if (data.woodenFishLevel < cfg.unlockRarePool && t.rarity != 'common') {
        if (!forceEpic) return false;
      }
      return true;
    }).toList();

    if (pool.isEmpty) {
      final content = switch (mode) {
        MeritExperienceMode.calm => '慢一点也没关系，此刻先照顾好自己。',
        MeritExperienceMode.sleep => '今天已经辛苦了，把剩下的交给夜晚。',
        MeritExperienceMode.release => '敲一下，把不开心留在这里。',
      };
      return MeritTextItem(
        id: '${mode.key}_fallback',
        content: content,
        category: mode.key,
        rarity: 'common',
        reincarnationTier: 0,
      );
    }

    var candidates =
        pool.where((t) => !data.todayShownTextIds.contains(t.id)).toList();
    if (candidates.isEmpty) {
      data.todayShownTextIds.clear();
      candidates = List.of(pool);
    }
    if (candidates.isEmpty) return null;

    MeritTextItem picked;
    if (forceEpic) {
      final epics = candidates.where((t) => t.rarity == 'epic').toList();
      picked = epics.isNotEmpty
          ? epics[_rng.nextInt(epics.length)]
          : candidates[_rng.nextInt(candidates.length)];
      picked = MeritTextItem(
        id: picked.id,
        content: picked.content,
        category: picked.category,
        rarity: 'epic',
        reincarnationTier: picked.reincarnationTier,
        hidden: picked.hidden,
      );
    } else if (data.forceToxicRemaining > 0) {
      final toxic = candidates.where((t) => t.category == 'toxic').toList();
      picked = toxic.isNotEmpty
          ? toxic[_rng.nextInt(toxic.length)]
          : candidates[_rng.nextInt(candidates.length)];
    } else {
      picked = _rollRarityPick(candidates);
    }

    data.todayShownTextIds.add(picked.id);
    if (!data.collectedTextIds.contains(picked.id)) {
      data.collectedTextIds.add(picked.id);
      data.lifeTextCollectedCount += 1;
    }
    return picked;
  }

  MeritTextItem _rollRarityPick(List<MeritTextItem> candidates) {
    var rareP = cfg.rarityRare + data.karmaRareBonus;
    var epicP = cfg.rarityEpic + data.karmaEpicBonus;
    if (_combo >= cfg.comboRareBoost) rareP += 0.2;
    if (data.woodenFishLevel >= cfg.unlockRarePool) {
      epicP += cfg.level30EpicBonus;
    }
    var commonP = 1.0 - rareP - epicP;
    if (commonP < 0.5) {
      final scale = 0.5 / (rareP + epicP);
      rareP *= scale;
      epicP *= scale;
      commonP = 0.5;
    }

    final roll = _rng.nextDouble();
    String rarity;
    if (roll < epicP) {
      rarity = 'epic';
    } else if (roll < epicP + rareP) {
      rarity = 'rare';
    } else {
      rarity = 'common';
    }

    var filtered = candidates.where((t) => t.rarity == rarity).toList();
    if (filtered.isEmpty) filtered = candidates;
    return filtered[_rng.nextInt(filtered.length)];
  }

  List<MeritLifeTitle> _checkLifeTitles() {
    final unlocked = <MeritLifeTitle>[];
    for (final t in bundle.lifeTitles) {
      if (data.lifeTaps >= t.threshold && !data.lifeTitles.contains(t.id)) {
        data.lifeTitles.add(t.id);
        unlocked.add(t);
      }
    }
    return unlocked;
  }

  MeritPendingEvent? _maybeTriggerEvent() {
    data.tapsSinceLastEvent += 1;
    final prob = cfg.eventBaseProbability + data.karmaEventBonus;
    final pity = data.tapsSinceLastEvent > cfg.eventPityTaps;
    if (!pity && _rng.nextDouble() > prob) return null;

    data.tapsSinceLastEvent = 0;
    data.lifeEventsTriggered += 1;

    const types = MeritEventType.values;
    final type = types[_rng.nextInt(types.length)];
    final event = MeritPendingEvent(type: type);
    // 即时状态效果直接生效，不打断敲击；红包/选择类入队待领
    switch (type) {
      case MeritEventType.karmaBacklash:
        data.forceToxicRemaining = 10;
        data.negativeCoins += 20;
      case MeritEventType.fishMood:
        // 默认硬敲到底，用户可稍后再付币取消沉默
        data.silentTapsRemaining = 15;
        data.pendingHardKnockReward = true;
        _queuedEvents.add(event);
      case MeritEventType.buddhaPass:
      case MeritEventType.bossCheck:
      case MeritEventType.fortuneGod:
        _queuedEvents.add(event);
    }
    return event;
  }

  List<MeritAchievementDef> _checkLifeAchievements() {
    final out = <MeritAchievementDef>[];
    for (final a in bundle.lifeAchievements) {
      if (data.lifeAchievements.contains(a.id)) continue;
      var ok = false;
      switch (a.type) {
        case 'combo':
          ok = _combo >= a.threshold || data.maxComboEver >= a.threshold;
        case 'textCount':
          ok = data.lifeTextCollectedCount >= a.threshold;
        case 'level':
          ok = data.woodenFishLevel >= a.threshold;
        case 'events':
          ok = data.lifeEventsTriggered >= a.threshold;
      }
      if (ok) {
        data.lifeAchievements.add(a.id);
        data.negativeCoins += a.reward;
        out.add(a);
      }
    }
    return out;
  }

  List<MeritAchievementDef> _checkPermanentAchievements() {
    final out = <MeritAchievementDef>[];
    for (final a in bundle.permanentAchievements) {
      if (data.permanentAchievements.contains(a.id)) continue;
      var ok = false;
      switch (a.type) {
        case 'totalTaps':
          ok = data.totalTaps >= a.threshold;
        case 'maxCombo':
          ok = data.maxComboEver >= a.threshold;
        case 'nightSession':
          ok = data.nightSessionTaps >= a.threshold;
        case 'mondaySession':
          ok = data.mondaySessionTaps >= a.threshold;
        case 'dailyStreak':
          ok = data.dailyStreak >= a.threshold;
        case 'epicStreak':
          ok = data.consecutiveEpicTaps >= a.threshold;
        case 'workdayTaps':
          ok = data.workdayTaps >= a.threshold;
        case 'reincarnation':
          ok = data.reincarnationCount >= a.threshold;
        case 'textCollected':
          ok = data.collectedTextIds.length >= a.threshold;
      }
      if (ok) {
        data.permanentAchievements.add(a.id);
        out.add(a);
      }
    }
    return out;
  }

  void _trackSessionTaps() {
    final now = DateTime.now();
    final wd = now.weekday;
    final h = now.hour;
    if (wd >= DateTime.monday && wd <= DateTime.friday && h >= 9 && h < 18) {
      data.workdayTaps += 1;
    }
    if (h >= 2 && h < 5) data.nightSessionTaps += 1;
    if (wd == DateTime.monday && h >= 9 && h < 11) data.mondaySessionTaps += 1;
  }

  /// 连击中断结算（兼容旧调用）
  Future<void> settleComboBreak() async {
    settleIdleCombo();
    await flushSave();
  }

  Future<bool> upgradeWoodenFish() async {
    if (data.woodenFishLevel >= cfg.unlockMaxLevel) return false;
    final cost = upgradeCost();
    if (data.negativeCoins < cost) return false;
    data.negativeCoins -= cost;
    data.woodenFishLevel += 1;
    _checkLifeAchievements();
    await MeritStorageService.save(data);
    return true;
  }

  Future<MeritReincarnationSummary?> reincarnate() async {
    if (data.lifeTaps < cfg.reincarnationThreshold) return null;

    final summary = MeritReincarnationSummary(
      lifeTaps: data.lifeTaps,
      coinsEarned: data.negativeCoins,
      titlesUnlocked: data.lifeTitles.length,
      textsCollected: data.lifeTextCollectedCount,
    );

    data.reincarnationCount += 1;
    data.karmaCoinBonus += cfg.karmaCoinMultiplier;
    data.karmaRareBonus += cfg.karmaRareBonus;
    data.karmaEpicBonus += cfg.karmaEpicBonus;
    data.karmaEventBonus += cfg.karmaEventBonus;

    data.unlockedSkins.add('rebirth_1');
    if (data.reincarnationCount >= 3) data.unlockedSkins.add('rebirth_3');
    if (data.reincarnationCount >= 5) data.unlockedSkins.add('rebirth_5');
    if (data.reincarnationCount >= 7) data.unlockedSkins.add('rebirth_7');
    if (data.reincarnationCount >= 10) data.unlockedSkins.add('rebirth_10');

    // 轮回后保留当前皮肤，不自动换装
    data.lifeTaps = 0;
    data.negativeCoins = 0;
    data.woodenFishLevel = 1;
    data.lifeTitles.clear();
    data.lifeAchievements.clear();
    data.todayShownTextIds.clear();
    data.lifeTextCollectedCount = 0;
    data.lifeEventsTriggered = 0;
    data.tapsSinceLastEvent = 0;
    data.silentTapsRemaining = 0;
    data.forceToxicRemaining = 0;
    data.pendingHardKnockReward = false;
    data.doubleCoinBuffUntilMs = 0;
    _combo = 0;
    _comboCycleCoins = 0;
    _queuedEvents.clear();

    _checkPermanentAchievements();
    await MeritStorageService.save(data);
    return summary;
  }

  Future<String> resolveEvent(MeritEventType type, String choice) async {
    var message = '';
    switch (type) {
      case MeritEventType.buddhaPass:
        if (choice == 'accept') {
          data.doubleCoinBuffUntilMs = DateTime.now()
              .add(const Duration(seconds: 30))
              .millisecondsSinceEpoch;
          message = '双倍负功德已生效 30 秒';
        } else {
          final hidden = bundle.texts.where((t) => t.hidden).toList();
          if (hidden.isNotEmpty) {
            final t = hidden.first;
            data.collectedTextIds.add(t.id);
            data.todayShownTextIds.add(t.id);
          }
          message = '拒绝赐福，解锁隐藏史诗文案';
        }
      case MeritEventType.bossCheck:
        if (choice == 'success') {
          data.negativeCoins += 30;
          message = '切屏成功，+30 负功德币';
        } else {
          final lost = (data.negativeCoins * 0.1).floor();
          data.negativeCoins -= lost;
          message = '被老板抓住，损失 $lost 币';
        }
      case MeritEventType.fishMood:
        if (choice == 'pay') {
          if (data.negativeCoins >= 80) {
            data.negativeCoins -= 80;
            data.silentTapsRemaining = 0;
            data.pendingHardKnockReward = false;
            message = '花 80 币哄好木鱼';
          } else {
            message = '币不够，继续硬敲';
          }
        } else {
          message = '硬敲到底，敲完 15 下有史诗碎片';
        }
      case MeritEventType.karmaBacklash:
        message = '业力反噬生效：接下来文案更扎心';
      case MeritEventType.fortuneGod:
        final gain = 50 + _rng.nextInt(151);
        data.negativeCoins += gain;
        message = '红包开出 $gain 负功德币';
    }
    _queuedEvents.removeWhere((e) => e.type == type);
    await MeritStorageService.save(data);
    return message;
  }

  void dismissQueuedEvent(MeritEventType type) {
    _queuedEvents.removeWhere((e) => e.type == type);
  }
}

class _ComboReward {
  const _ComboReward({
    required this.extraCoins,
    required this.forceEpic,
    required this.angryFish,
    required this.speedDemon,
    required this.godSpeed,
  });

  final int extraCoins;
  final bool forceEpic;
  final bool angryFish;
  final bool speedDemon;
  final bool godSpeed;
}

class _ComboBreak {
  const _ComboBreak({
    required this.broken,
    required this.brokenAt,
    required this.settlementCoins,
  });

  final bool broken;
  final int brokenAt;
  final int settlementCoins;
}

class MeritReincarnationSummary {
  const MeritReincarnationSummary({
    required this.lifeTaps,
    required this.coinsEarned,
    required this.titlesUnlocked,
    required this.textsCollected,
  });

  final int lifeTaps;
  final int coinsEarned;
  final int titlesUnlocked;
  final int textsCollected;
}
