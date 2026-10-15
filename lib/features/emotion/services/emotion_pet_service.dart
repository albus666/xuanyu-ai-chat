import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/models/identity_type.dart';

/// 情绪宠物牛 + 打卡数据（本地持久化，后续可接后端）
class EmotionPetService {
  EmotionPetService._();

  static const _keyHealth = 'emotion_pet_health';
  static const _keyLastFeedDate = 'emotion_pet_last_feed';
  static const _keyLastEmotion = 'emotion_pet_last_emotion';
  static const _keyPetName = 'emotion_pet_name';
  static const _keyCheckIns = 'emotion_map_checkins';
  static const _keyLastIdentity = 'emotion_last_identity';

  static Future<PetState> loadPetState() async {
    final prefs = await SharedPreferences.getInstance();
    var health = prefs.getInt(_keyHealth) ?? 80;
    final lastFeed = prefs.getString(_keyLastFeedDate);
    final today = _todayKey();

    if (lastFeed != null && lastFeed != today) {
      final last = DateTime.tryParse(lastFeed);
      if (last != null) {
        final gap = DateTime.now().difference(last).inDays;
        health = (health - gap * 12).clamp(10, 100);
        await prefs.setInt(_keyHealth, health);
      }
    }

    final emotionIdx = prefs.getInt(_keyLastEmotion);
    return PetState(
      health: health,
      fedToday: lastFeed == today,
      lastEmotion: emotionIdx != null &&
              emotionIdx >= 0 &&
              emotionIdx < EmotionType.values.length
          ? EmotionType.values[emotionIdx]
          : null,
      name: prefs.getString(_keyPetName) ?? '哞哞',
    );
  }

  static Future<PetState> feed(EmotionType emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    var health = prefs.getInt(_keyHealth) ?? 80;

    if (prefs.getString(_keyLastFeedDate) != today) {
      health = (health + emotion.feedBoost).clamp(0, 100);
    } else {
      health = (health + (emotion.feedBoost ~/ 2)).clamp(0, 100);
    }

    await prefs.setInt(_keyHealth, health);
    await prefs.setString(_keyLastFeedDate, today);
    await prefs.setInt(_keyLastEmotion, emotion.index);

    return PetState(
      health: health,
      fedToday: true,
      lastEmotion: emotion,
      name: prefs.getString(_keyPetName) ?? '哞哞',
    );
  }

  static Future<void> saveCheckIn({
    required IdentityType identity,
    required EmotionType emotion,
    String? province,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readCheckIns(prefs);
    list.add({
      'identity': identity.index,
      'emotion': emotion.index,
      'province': province ?? '未知',
      'ts': DateTime.now().toIso8601String(),
    });
    if (list.length > 500) {
      list.removeRange(0, list.length - 500);
    }
    await prefs.setString(_keyCheckIns, jsonEncode(list));
    await prefs.setInt(_keyLastIdentity, identity.index);
  }

  static Future<List<Map<String, dynamic>>> getCheckIns() async {
    final prefs = await SharedPreferences.getInstance();
    return _readCheckIns(prefs);
  }

  static Future<Map<String, dynamic>> getMapStats(
      {IdentityType? filter}) async {
    final checkIns = await getCheckIns();
    final provinceEmotions = <String, Map<int, int>>{};
    final identityEmotions = <int, Map<int, int>>{};

    for (final c in checkIns) {
      final prov = c['province'] as String? ?? '未知';
      final emo = c['emotion'] as int? ?? 0;
      final id = c['identity'] as int? ?? 0;

      if (filter != null && id != filter.index) continue;

      provinceEmotions.putIfAbsent(prov, () => {});
      provinceEmotions[prov]![emo] = (provinceEmotions[prov]![emo] ?? 0) + 1;

      identityEmotions.putIfAbsent(id, () => {});
      identityEmotions[id]![emo] = (identityEmotions[id]![emo] ?? 0) + 1;
    }

    // 合并模拟全国数据，让地图看起来有内容
    final mock = _mockNationalData(filter);
    for (final e in mock.entries) {
      final prov = e.key;
      for (final emoEntry in e.value.entries) {
        provinceEmotions.putIfAbsent(prov, () => {});
        provinceEmotions[prov]![emoEntry.key] =
            (provinceEmotions[prov]![emoEntry.key] ?? 0) + emoEntry.value;
      }
    }

    final provinceDominant = <String, EmotionType>{};
    for (final e in provinceEmotions.entries) {
      var maxCount = 0;
      var dominant = EmotionType.tired.index;
      for (final emo in e.value.entries) {
        if (emo.value > maxCount) {
          maxCount = emo.value;
          dominant = emo.key;
        }
      }
      if (maxCount > 0) {
        provinceDominant[e.key] = EmotionType
            .values[dominant.clamp(0, EmotionType.values.length - 1)];
      }
    }

    return {
      'provinceDominant': provinceDominant,
      'totalCheckIns': checkIns.length + _mockTotal,
      'identityEmotions': identityEmotions,
    };
  }

  static List<Map<String, dynamic>> _readCheckIns(SharedPreferences prefs) {
    final raw = prefs.getString(_keyCheckIns);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static const _mockTotal = 12847;

  static Map<String, Map<int, int>> _mockNationalData(IdentityType? filter) {
    const provinces = {
      '北京': EmotionType.anxious,
      '天津': EmotionType.tired,
      '河北': EmotionType.tired,
      '山西': EmotionType.zen,
      '内蒙古': EmotionType.slacking,
      '辽宁': EmotionType.emo,
      '吉林': EmotionType.tired,
      '黑龙江': EmotionType.emo,
      '上海': EmotionType.tired,
      '江苏': EmotionType.tired,
      '浙江': EmotionType.slacking,
      '安徽': EmotionType.anxious,
      '福建': EmotionType.happy,
      '江西': EmotionType.excited,
      '山东': EmotionType.tired,
      '河南': EmotionType.anxious,
      '湖北': EmotionType.angry,
      '湖南': EmotionType.excited,
      '广东': EmotionType.excited,
      '广西': EmotionType.happy,
      '海南': EmotionType.happy,
      '重庆': EmotionType.slacking,
      '四川': EmotionType.happy,
      '贵州': EmotionType.zen,
      '云南': EmotionType.happy,
      '西藏': EmotionType.zen,
      '陕西': EmotionType.zen,
      '甘肃': EmotionType.slacking,
      '青海': EmotionType.zen,
      '宁夏': EmotionType.zen,
      '新疆': EmotionType.slacking,
      '台湾': EmotionType.emo,
      '香港': EmotionType.excited,
      '澳门': EmotionType.happy,
    };

    final identityBias = switch (filter) {
      IdentityType.worker => EmotionType.tired,
      IdentityType.entrepreneur => EmotionType.anxious,
      IdentityType.examTaker => EmotionType.anxious,
      IdentityType.parent => EmotionType.tired,
      IdentityType.loveBrain => EmotionType.emo,
      IdentityType.commuting => EmotionType.tired,
      IdentityType.sleepless => EmotionType.emo,
      IdentityType.alone => EmotionType.zen,
      IdentityType.resting => EmotionType.happy,
      null => null,
    };

    final result = <String, Map<int, int>>{};
    var i = 0;
    for (final e in provinces.entries) {
      final emo = identityBias ?? e.value;
      final count = 80 + (i * 17) % 120;
      result[e.key] = {emo.index: count};
      i++;
    }
    return result;
  }
}

class PetState {
  const PetState({
    required this.health,
    required this.fedToday,
    this.lastEmotion,
    this.name = '哞哞',
  });

  final int health;
  final bool fedToday;
  final EmotionType? lastEmotion;
  final String name;

  bool get isWilting => health < 40;
  bool get isThriving => health >= 75;

  String get statusText {
    if (!fedToday && health < 50) return '好久没投喂了，牛牛快枯萎了…';
    if (fedToday) return '今天已投喂，牛牛元气满满！';
    if (health < 40) return '牛牛有点蔫，快来喂一口情绪吧';
    return '牛牛状态还行，记得每天喂一次哦';
  }
}
