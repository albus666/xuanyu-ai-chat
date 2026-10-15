import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_sheet.dart';

void main() {
  test('礼物动效严格使用后台时长并限制异常值', () {
    expect(virtualGiftEffectDuration({'effectDurationMs': 3200}), 3200);
    expect(virtualGiftEffectDuration({'effectDurationMs': 99}), 1200);
    expect(virtualGiftEffectDuration({'effectDurationMs': 99999}), 8000);
  });

  test('礼物数量输入和总价展示保持稳定', () {
    expect(normalizeVirtualGiftQuantity(null), 1);
    expect(normalizeVirtualGiftQuantity(0), 1);
    expect(normalizeVirtualGiftQuantity(26), 26);
    expect(normalizeVirtualGiftQuantity(1000), 999);
    expect(virtualGiftCoinAmount(60), '60');
    expect(virtualGiftCoinAmount(12.5), '12.50');
    expect(virtualGiftCoinAmount(1.2345), '1.2345');
  });

  test('历史礼物可从礼物编号恢复稳定云端素材地址', () {
    final url = virtualGiftMediaUrl(
      {'giftCode': 'moon_rabbit'},
      effect: true,
    );
    expect(
      url,
      'https://www.lingshu.uno/api/virtual/gifts/moon_rabbit/asset?kind=effect',
    );
  });

  test('优先使用稳定路径而不是会过期的签名地址', () {
    final url = virtualGiftMediaUrl({
      'assetPath': '/api/virtual/gifts/star_whale/asset?kind=asset',
      'assetUrl': 'https://temporary.example/expired.webp',
    });
    expect(
      url,
      'https://www.lingshu.uno/api/virtual/gifts/star_whale/asset?kind=asset',
    );
  });

  test('礼物视频优先使用不会过期的后端稳定路径', () {
    final url = virtualGiftVideoUrl({
      'effectVideoPath': '/api/virtual/gifts/star_whale/asset?kind=video',
      'effectVideoUrl': 'https://temporary.example/expired.mp4',
    });
    expect(
      url,
      'https://www.lingshu.uno/api/virtual/gifts/star_whale/asset?kind=video',
    );
  });

  test('未配置动态视频时使用空地址触发图片动效降级', () {
    expect(virtualGiftVideoUrl({'giftCode': 'heart_light'}), isEmpty);
  });
}
