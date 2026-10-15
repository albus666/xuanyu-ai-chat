import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ProfileBackgroundPreset {
  const ProfileBackgroundPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.colors,
    this.accent = Colors.white,
    this.dark = false,
    this.motion = ProfileBackgroundMotion.none,
    this.assetPath,
    this.foregroundAsset = false,
  });

  final String id;
  final String name;
  final String description;
  final List<Color> colors;
  final Color accent;
  final bool dark;
  final ProfileBackgroundMotion motion;
  final String? assetPath;
  final bool foregroundAsset;
}

enum ProfileBackgroundMotion {
  none,
  aurora,
  tide,
  fireflies,
  stars,
  swim,
  drift,
  pulse,
  orbit,
  flutter,
  bob,
  sway,
  glide,
  snowfall,
}

ProfileBackgroundPreset? profileBackgroundById(String? id) {
  for (final preset in platformProfileBackgrounds) {
    if (preset.id == id) return preset;
  }
  return null;
}

const platformProfileBackgrounds = <ProfileBackgroundPreset>[
  ProfileBackgroundPreset(
    id: 'celadon_mountains',
    name: '青山入画',
    description: '云水留白之间，收好一片青山',
    colors: [Color(0xFFDDE2D5), Color(0xFFA7C1B8), Color(0xFFF2EAD8)],
    accent: Color(0xFFE8D6A9),
    assetPath: 'assets/decorations/celadon_mountains.webp',
  ),
  ProfileBackgroundPreset(
    id: 'bamboo_moon_court',
    name: '竹庭听月',
    description: '竹影轻落，把喧嚣留在月色之外',
    colors: [Color(0xFF142C34), Color(0xFF25414A), Color(0xFF0C1D27)],
    accent: Color(0xFFCACBAA),
    dark: true,
    assetPath: 'assets/decorations/bamboo_moon_court.webp',
  ),
  ProfileBackgroundPreset(
    id: 'starlit_sailing',
    name: '星海归舟',
    description: '沿着星光慢慢航行，总有温柔的归处',
    colors: [Color(0xFF102342), Color(0xFF293F68), Color(0xFF10233E)],
    accent: Color(0xFFEBD3A0),
    dark: true,
    assetPath: 'assets/decorations/starlit_sailing.webp',
  ),
  ProfileBackgroundPreset(
    id: 'peach_cloud_moon',
    name: '云月桃笺',
    description: '桃花与云月相逢，写下今天的温柔',
    colors: [Color(0xFFF2DAD3), Color(0xFFF9EDE0), Color(0xFFEACFCC)],
    accent: Color(0xFFFFE4C6),
    assetPath: 'assets/decorations/peach_cloud_moon.webp',
  ),
  ProfileBackgroundPreset(
    id: 'star_sea_whale',
    name: '星鲸云海',
    description: '星鲸穿过云海，把遥远的光带到你身边',
    colors: [Color(0xFF101F38), Color(0xFF254B70), Color(0xFF7799AE)],
    accent: Color(0xFFFFE2A7),
    dark: true,
    motion: ProfileBackgroundMotion.stars,
    assetPath: 'assets/decorations/star_sea_fantasy/star_whale.webp',
  ),
  ProfileBackgroundPreset(
    id: 'star_sea_jellyfish',
    name: '月海浮光',
    description: '水母在月海间轻轻呼吸，守住今夜的安静',
    colors: [Color(0xFF111C38), Color(0xFF334C79), Color(0xFF8B8EBD)],
    accent: Color(0xFFE6E2FF),
    dark: true,
    motion: ProfileBackgroundMotion.pulse,
    assetPath: 'assets/decorations/star_sea_fantasy/moon_jellyfish.webp',
  ),
  ProfileBackgroundPreset(
    id: 'star_sea_deer',
    name: '极光鹿境',
    description: '白鹿站在极光之下，愿你始终有方向可往',
    colors: [Color(0xFF10282E), Color(0xFF2E6267), Color(0xFF91BEB3)],
    accent: Color(0xFFF2D69A),
    dark: true,
    motion: ProfileBackgroundMotion.aurora,
    assetPath: 'assets/decorations/star_sea_fantasy/aurora_deer.webp',
  ),
  ProfileBackgroundPreset(
    id: 'star_sea_fox',
    name: '星月守候',
    description: '银狐抱着一弯月光，陪你安放每一份心事',
    colors: [Color(0xFF151B38), Color(0xFF45486F), Color(0xFF9694B1)],
    accent: Color(0xFFFFE4B0),
    dark: true,
    motion: ProfileBackgroundMotion.stars,
    assetPath: 'assets/decorations/star_sea_fantasy/moon_fox.webp',
  ),
  ProfileBackgroundPreset(
    id: 'dolphin_companions',
    name: '海豚逐浪',
    description: '两只海豚追着浪花，把好心情游到你身边',
    colors: [Color(0xFF62BFD1), Color(0xFFA8DFE3), Color(0xFFE8F5EF)],
    accent: Color(0xFFFFE39B),
    motion: ProfileBackgroundMotion.swim,
    assetPath: 'assets/decorations/animal_motion/dolphin_companions.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'whale_companions',
    name: '星鲸同行',
    description: '星鲸缓缓经过，陪你把心事放进远方',
    colors: [Color(0xFF182C54), Color(0xFF334F79), Color(0xFF718DA9)],
    accent: Color(0xFFF0D48E),
    dark: true,
    motion: ProfileBackgroundMotion.glide,
    assetPath: 'assets/decorations/animal_motion/whale_companions.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'jellyfish_lullaby',
    name: '水母晚歌',
    description: '微光一呼一吸，替夜晚留一片安静',
    colors: [Color(0xFF23335F), Color(0xFF526390), Color(0xFFAAA7CA)],
    accent: Color(0xFFCBEFFF),
    dark: true,
    motion: ProfileBackgroundMotion.pulse,
    assetPath: 'assets/decorations/animal_motion/jellyfish_lullaby.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'koi_ripple',
    name: '锦鲤流光',
    description: '两尾锦鲤绕光而游，好运也在慢慢靠近',
    colors: [Color(0xFF779F94), Color(0xFFB8CFC1), Color(0xFFF1E8D8)],
    accent: Color(0xFFD7A85E),
    motion: ProfileBackgroundMotion.orbit,
    assetPath: 'assets/decorations/animal_motion/koi_ripple.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'butterfly_breeze',
    name: '蝶遇花风',
    description: '轻轻振翅，让今天也有一点春天',
    colors: [Color(0xFFA9C89D), Color(0xFFD6E6C3), Color(0xFFFFF2DC)],
    accent: Color(0xFFFFD787),
    motion: ProfileBackgroundMotion.flutter,
    assetPath: 'assets/decorations/animal_motion/butterfly_breeze.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'cloud_rabbits',
    name: '云端兔眠',
    description: '云朵轻轻起伏，安心依偎就很好',
    colors: [Color(0xFF87C7E1), Color(0xFFC6E4EF), Color(0xFFF6ECD8)],
    accent: Color(0xFFFFD68B),
    motion: ProfileBackgroundMotion.bob,
    assetPath: 'assets/decorations/animal_motion/cloud_rabbits.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'penguin_warmth',
    name: '极地相依',
    description: '雪落得很慢，靠在一起就不会冷',
    colors: [Color(0xFF40536F), Color(0xFF7D91AA), Color(0xFFDCE7EC)],
    accent: Color(0xFFFFFFFF),
    dark: true,
    motion: ProfileBackgroundMotion.snowfall,
    assetPath: 'assets/decorations/animal_motion/penguin_warmth.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'red_panda_autumn',
    name: '秋枝小熊猫',
    description: '在暖暖的秋色里，放心发一会儿呆',
    colors: [Color(0xFF8C6945), Color(0xFFC9A36D), Color(0xFFEDE0BD)],
    accent: Color(0xFFFFD78A),
    motion: ProfileBackgroundMotion.sway,
    assetPath: 'assets/decorations/animal_motion/red_panda_autumn.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'moon_cat',
    name: '月钩守候',
    description: '小猫坐在月亮上，替你守住今晚的梦',
    colors: [Color(0xFF17284D), Color(0xFF35476E), Color(0xFF7B7896)],
    accent: Color(0xFFF2D184),
    dark: true,
    motion: ProfileBackgroundMotion.bob,
    assetPath: 'assets/decorations/animal_motion/moon_cat.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'crane_mist',
    name: '鹤影清岚',
    description: '双鹤掠过晨雾，心也跟着舒展开来',
    colors: [Color(0xFF6D8D89), Color(0xFFB2C9BF), Color(0xFFF0EEE5)],
    accent: Color(0xFFD3AA64),
    motion: ProfileBackgroundMotion.glide,
    assetPath: 'assets/decorations/animal_motion/crane_mist.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'aurora_fox',
    name: '极光银狐',
    description: '银狐踏着极光，把勇气悄悄送给你',
    colors: [Color(0xFF123A43), Color(0xFF28626B), Color(0xFF6C9E9B)],
    accent: Color(0xFFAFECDD),
    dark: true,
    motion: ProfileBackgroundMotion.glide,
    assetPath: 'assets/decorations/animal_motion/aurora_fox.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'otter_holding_paws',
    name: '海獭牵手',
    description: '牵住彼此的小爪子，潮水也冲不散陪伴',
    colors: [Color(0xFF66AFA9), Color(0xFFA9D8CC), Color(0xFFE8E3C8)],
    accent: Color(0xFFFFD27B),
    motion: ProfileBackgroundMotion.drift,
    assetPath: 'assets/decorations/animal_motion/otter_holding_paws.webp',
    foregroundAsset: true,
  ),
  ProfileBackgroundPreset(
    id: 'sunny_hug',
    name: '晴天抱抱',
    description: '今天也有一朵云，轻轻接住你',
    colors: [Color(0xFF96C9E4), Color(0xFFCBE5F0), Color(0xFFEAF4F7)],
    accent: Color(0xFFFFE6A3),
    motion: ProfileBackgroundMotion.fireflies,
    assetPath: 'assets/decorations/sunny_hug.png',
  ),
  ProfileBackgroundPreset(
    id: 'cream_rest',
    name: '奶油小憩',
    description: '不用一直赶路，也可以歇一会儿',
    colors: [Color(0xFFEDD5B4), Color(0xFFF5E7D6), Color(0xFFFFF7ED)],
    accent: Color(0xFFD6AB72),
    motion: ProfileBackgroundMotion.fireflies,
    assetPath: 'assets/decorations/cream_rest.png',
  ),
  ProfileBackgroundPreset(
    id: 'bloom_slowly',
    name: '花开慢慢',
    description: '按自己的节奏，慢慢长大',
    colors: [Color(0xFFA6CEAC), Color(0xFFD2E8CE), Color(0xFFF2F6E9)],
    accent: Color(0xFFFFE5A5),
    motion: ProfileBackgroundMotion.fireflies,
    assetPath: 'assets/decorations/bloom_slowly.png',
  ),
  ProfileBackgroundPreset(
    id: 'jade_flow',
    name: '玉青流光',
    description: '玄遇默认 · 清透明亮',
    colors: [Color(0xFF2A9B9C), Color(0xFF66C9C2), Color(0xFFC1E4D5)],
    accent: Color(0xFFE9FFF9),
  ),
  ProfileBackgroundPreset(
    id: 'moon_white',
    name: '月白云影',
    description: '安静柔和 · 男女适用',
    colors: [Color(0xFF739DB3), Color(0xFFAFC9D2), Color(0xFFE7E5DF)],
    accent: Color(0xFFF9FCFF),
  ),
  ProfileBackgroundPreset(
    id: 'mist_violet',
    name: '淡紫夜雾',
    description: '低饱和紫 · 温柔神秘',
    colors: [Color(0xFF645B87), Color(0xFF9D91B9), Color(0xFFD8D2E8)],
    accent: Color(0xFFF2ECFF),
    dark: true,
  ),
  ProfileBackgroundPreset(
    id: 'sunset_gold',
    name: '暖金日落',
    description: '温暖松弛 · 轻熟质感',
    colors: [Color(0xFFB56E61), Color(0xFFD9A778), Color(0xFFF0D5A8)],
    accent: Color(0xFFFFF0CC),
  ),
  ProfileBackgroundPreset(
    id: 'star_river',
    name: '青蓝星河',
    description: '明净深邃 · 中性表达',
    colors: [Color(0xFF244B69), Color(0xFF397F98), Color(0xFF69B9B2)],
    accent: Color(0xFFBFF8EC),
    dark: true,
  ),
  ProfileBackgroundPreset(
    id: 'ink_jade',
    name: '墨玉新中式',
    description: '克制东方 · 适合老师主页',
    colors: [Color(0xFF173D3A), Color(0xFF356C66), Color(0xFF8DAA98)],
    accent: Color(0xFFD7BA78),
    dark: true,
  ),
  ProfileBackgroundPreset(
    id: 'urban_light',
    name: '城市微光',
    description: '冷静利落 · 现代轻潮',
    colors: [Color(0xFF344657), Color(0xFF62788D), Color(0xFFB1C7CC)],
    accent: Color(0xFF8FE0DC),
    dark: true,
  ),
  ProfileBackgroundPreset(
    id: 'healing_garden',
    name: '治愈花园',
    description: '轻盈鲜活 · 情绪友好',
    colors: [Color(0xFF68A990), Color(0xFFA9D0A7), Color(0xFFE7D4C5)],
    accent: Color(0xFFFFE8EE),
  ),
  ProfileBackgroundPreset(
    id: 'pearl_minimal',
    name: '珍珠极简',
    description: '干净留白 · 不抢头像',
    colors: [Color(0xFF789F9D), Color(0xFFB9D1CC), Color(0xFFE6E7DF)],
    accent: Color(0xFFFFFFFF),
  ),
  ProfileBackgroundPreset(
    id: 'coral_breeze',
    name: '珊瑚微风',
    description: '温柔明亮 · 亲和自然',
    colors: [Color(0xFFB96F7B), Color(0xFFDCA3A6), Color(0xFFF3D9C7)],
    accent: Color(0xFFFFF3DD),
  ),
  ProfileBackgroundPreset(
    id: 'deep_professional',
    name: '深青专业',
    description: '稳重可信 · 专业身份',
    colors: [Color(0xFF123936), Color(0xFF27605E), Color(0xFF527F78)],
    accent: Color(0xFFD4B977),
    dark: true,
  ),
  ProfileBackgroundPreset(
    id: 'sky_lavender',
    name: '晴空浅紫',
    description: '年轻清爽 · 社交轻盈',
    colors: [Color(0xFF6AA7C2), Color(0xFFA7BADC), Color(0xFFDCCFEB)],
    accent: Color(0xFFEFFFFB),
  ),
  ProfileBackgroundPreset(
    id: 'jade_aurora',
    name: '青岚流光',
    description: '青绿光带，缓缓流转',
    colors: [Color(0xFF163F43), Color(0xFF327D7C), Color(0xFF9BCAC1)],
    accent: Color(0xFFA9F3DD),
    dark: true,
    motion: ProfileBackgroundMotion.aurora,
  ),
  ProfileBackgroundPreset(
    id: 'moon_tide',
    name: '月白潮汐',
    description: '月色映海，波纹轻漾',
    colors: [Color(0xFF304F65), Color(0xFF719BAA), Color(0xFFCCDAD8)],
    accent: Color(0xFFF5F1DC),
    motion: ProfileBackgroundMotion.tide,
  ),
  ProfileBackgroundPreset(
    id: 'firefly_garden',
    name: '萤火青庭',
    description: '几点萤光，陪伴此刻',
    colors: [Color(0xFF1E4F46), Color(0xFF53977D), Color(0xFFBED2B0)],
    accent: Color(0xFFE5EBA3),
    motion: ProfileBackgroundMotion.fireflies,
  ),
  ProfileBackgroundPreset(
    id: 'quiet_galaxy',
    name: '静夜星河',
    description: '星光轻闪，安静深远',
    colors: [Color(0xFF162B42), Color(0xFF31546B), Color(0xFF7BADA9)],
    accent: Color(0xFFDADDC4),
    dark: true,
    motion: ProfileBackgroundMotion.stars,
  ),
  ProfileBackgroundPreset(
    id: 'moon_companion',
    name: '今晚好眠',
    description: '把心事放轻一点，今晚好好休息',
    colors: [Color(0xFF103A43), Color(0xFF28595B), Color(0xFF477A72)],
    accent: Color(0xFFF4DEA3),
    dark: true,
    motion: ProfileBackgroundMotion.stars,
    assetPath: 'assets/decorations/moon_companion.png',
  ),
];

LinearGradient profileBackgroundGradient(ProfileBackgroundPreset preset) =>
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: preset.colors,
      stops: const [0, .54, 1],
    );

Future<Uint8List> renderProfileBackgroundPng(
  ProfileBackgroundPreset preset, {
  int width = 1440,
  int height = 900,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        preset.colors,
        const [.0, .54, 1.0],
      ),
  );

  final glow = Paint()
    ..shader = ui.Gradient.radial(
      Offset(size.width * .78, size.height * .2),
      size.shortestSide * .52,
      [preset.accent.withValues(alpha: .5), Colors.transparent],
    );
  canvas.drawCircle(
      Offset(size.width * .78, size.height * .2), size.height * .52, glow);

  final softPaint = Paint()
    ..color = preset.accent.withValues(alpha: preset.dark ? .12 : .18)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(4, width / 220);
  for (var index = 0; index < 3; index++) {
    final path = Path()
      ..moveTo(-size.width * .08, size.height * (.66 + index * .1))
      ..cubicTo(
        size.width * .25,
        size.height * (.47 + index * .08),
        size.width * .6,
        size.height * (.92 + index * .04),
        size.width * 1.08,
        size.height * (.58 + index * .1),
      );
    canvas.drawPath(path, softPaint);
  }

  final particlePaint = Paint()
    ..color = preset.accent.withValues(alpha: preset.dark ? .4 : .5);
  for (var index = 0; index < 22; index++) {
    final x = ((index * 193) % width).toDouble();
    final y = ((index * 127 + 83) % height).toDouble();
    final radius = 2.0 + (index % 4) * 1.2;
    canvas.drawCircle(Offset(x, y), radius, particlePaint);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('背景生成失败');
  return bytes.buffer.asUint8List();
}
