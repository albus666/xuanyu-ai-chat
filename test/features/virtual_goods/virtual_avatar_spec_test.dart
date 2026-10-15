import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_catalog.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_spec.dart';

void main() {
  test('头像馆包含星海幻想分类', () {
    expect(VirtualAvatarCatalog.styleNames['starsea'], '星海幻想');
  });

  test('动态头像保留原图与静态缩略图，且要求逐帧安全区验收', () {
    final input = <String, dynamic>{
      'productType': 'finished',
      'assetCode': 'cloud_moving_cat',
      'assetUrl': 'https://static.example.com/moving.webp',
      'thumbnailUrl': 'https://static.example.com/still.webp',
      'safeCircleApproved': true,
      'safeCircleInsetPercent': 13,
      'mediaType': 'animated',
    };
    expect(VirtualAvatarSpec.normalize(input).containsKey('assetUrl'), isFalse);
    input['animationSafeCircleApproved'] = true;
    final config = VirtualAvatarSpec.normalize(input);
    expect(config['mediaType'], 'animated');
    expect(VirtualAvatarCatalog.assetUrl(config), input['assetUrl']);
    expect(VirtualAvatarCatalog.thumbnailUrl(config), input['thumbnailUrl']);
  });
  test('旧版分层配置会迁移到完整的免费初始款', () {
    final config = VirtualAvatarSpec.normalize({
      'style': 'oriental',
      'presentation': 'female',
      'face': 99,
      'skin': -1,
      'hair': 3,
    });

    expect(config['schemaVersion'], VirtualAvatarSpec.schemaVersion);
    expect(config['renderStyle'], 'micro');
    expect(config['productType'], 'finished');
    expect(config['categoryCode'], 'micro');
    expect(config['assetCode'], 'micro_jinglan');
    expect(config['face'], 3);
    expect(config['skin'], 7);
    for (final key in VirtualAvatarSpec.partCounts.keys) {
      expect(config[key], isA<int>(), reason: key);
    }
  });

  test('随机头像的所有部件都落在协议范围内', () {
    final config = VirtualAvatarSpec.normalize({
      for (final entry in VirtualAvatarSpec.partCounts.entries)
        entry.key: entry.value * 10 + 1,
    });

    for (final entry in VirtualAvatarSpec.partCounts.entries) {
      expect(config[entry.key], inInclusiveRange(0, entry.value - 1),
          reason: entry.key);
    }
  });

  test('旧微卡通迁移到新微卡通初始款，成品资源编号会保留', () {
    final legacy = VirtualAvatarSpec.normalize({'renderStyle': 'micro'});
    expect(legacy['renderStyle'], 'micro');
    expect(legacy['assetCode'], 'micro_jinglan');

    final finished = VirtualAvatarSpec.normalize({
      'renderStyle': 'urban',
      'productType': 'finished',
      'categoryCode': 'urban',
      'assetCode': 'urban_chengye',
    });
    expect(finished['assetCode'], 'urban_chengye');
    expect(VirtualAvatarCatalog.assetPath(finished),
        'assets/avatars/finished/urban_chengye.webp');
  });

  test('三张初始款分别适配三种展现方式', () {
    expect(VirtualAvatarSpec.defaults(1)['assetCode'], 'micro_qinghe');
    expect(VirtualAvatarSpec.defaults(2)['assetCode'], 'micro_nuanxi');
    expect(VirtualAvatarSpec.defaults()['assetCode'], 'micro_jinglan');
    expect(VirtualAvatarSpec.outputPixels, 1024);
  });

  test('赠送消息中的头像商品编号均能还原成真实成品图', () {
    for (final productCode in VirtualAvatarCatalog.productAssetCodes.keys) {
      final config = VirtualAvatarCatalog.configForProductCode(productCode);
      expect(
        VirtualAvatarCatalog.assetPath(config),
        isNotNull,
        reason: productCode,
      );
    }
  });

  test('后台云端成品头像会保留安全地址与自定义分类', () {
    final config = VirtualAvatarSpec.normalize({
      'productType': 'finished',
      'renderStyle': 'couple',
      'categoryCode': 'couple',
      'assetCode': 'remote_couple_001',
      'assetUrl': 'https://static.example.com/avatar/full.webp',
      'thumbnailUrl': 'https://static.example.com/avatar/thumb.webp',
      'safeCircleApproved': true,
      'safeCircleInsetPercent': 13,
    });

    expect(config['assetCode'], 'remote_couple_001');
    expect(config['categoryCode'], 'couple');
    expect(config['assetUrl'], 'https://static.example.com/avatar/full.webp');
    expect(
      VirtualAvatarCatalog.thumbnailUrl(config),
      'https://static.example.com/avatar/thumb.webp',
    );
  });

  test('未通过圆形安全区验收的云端头像不会进入头像馆', () {
    final config = VirtualAvatarSpec.normalize({
      'productType': 'finished',
      'categoryCode': 'cute',
      'assetCode': 'remote_cute_unsafe',
      'assetUrl': 'https://static.example.com/avatar/full.webp',
    });

    expect(config['assetCode'], 'micro_jinglan');
    expect(config.containsKey('assetUrl'), isFalse);
  });

  test('非 HTTPS 云端头像不会进入头像馆', () {
    final config = VirtualAvatarSpec.normalize({
      'productType': 'finished',
      'categoryCode': 'cute',
      'assetCode': 'remote_cute_001',
      'assetUrl': 'http://static.example.com/avatar/full.webp',
    });

    expect(config['assetCode'], 'micro_jinglan');
    expect(config.containsKey('assetUrl'), isFalse);
  });
}
