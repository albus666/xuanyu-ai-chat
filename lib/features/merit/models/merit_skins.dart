import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';

/// 木鱼皮肤定义。产品当前只保留“云水静心”。
class MeritSkinDef {
  const MeritSkinDef({
    required this.id,
    required this.name,
    required this.unlockReincarnation,
    required this.asset,
    required this.stickAsset,
    required this.unlockHint,
    this.imageUrl = '',
    this.stickImageUrl = '',
  });

  final String id;
  final String name;
  final int unlockReincarnation;

  /// 木鱼本体
  final String asset;

  /// 木锤
  final String stickAsset;
  final String unlockHint;
  final String imageUrl;
  final String stickImageUrl;

  static const List<MeritSkinDef> defaults = [
    MeritSkinDef(
      id: 'rebirth_1',
      name: '云水静心',
      unlockReincarnation: 0,
      asset: ImageAssets.muyuCloudWave,
      stickAsset: ImageAssets.muyuCloudWaveStick,
      unlockHint: '静下心来 · 让思绪慢慢平稳',
    ),
  ];

  static List<MeritSkinDef> get all => defaults;

  static MeritSkinDef byId(String id, {List<MeritSkinDef>? source}) {
    final skins = source ?? all;
    if (id == 'default') return skins.first;
    for (final s in skins) {
      if (s.id == id) return s;
    }
    return skins.first;
  }

  /// 按当前轮回数，装备已解锁的最高档皮肤 id
  static String highestUnlockedId(int reincarnationCount) {
    MeritSkinDef best = all.first;
    for (final s in all) {
      if (reincarnationCount >= s.unlockReincarnation) best = s;
    }
    return best.id;
  }

  static MeritSkinDef _activeOrFallback(MeritSaveData data) {
    final active = byId(data.activeSkin);
    if (data.unlockedSkins.contains(active.id) ||
        active.unlockReincarnation == 0) {
      return active;
    }
    return byId(highestUnlockedId(data.reincarnationCount));
  }

  static String assetForSave(MeritSaveData data) {
    final skin = _activeOrFallback(data);
    final remote = skin.imageUrl.trim();
    return remote.isNotEmpty ? remote : skin.asset;
  }

  static String stickForSave(MeritSaveData data) {
    final skin = _activeOrFallback(data);
    final remote = skin.stickImageUrl.trim();
    return remote.isNotEmpty ? remote : skin.stickAsset;
  }
}
