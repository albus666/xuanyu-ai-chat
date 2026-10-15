import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_artwork.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_catalog.dart';
import 'package:xuanyu/features/virtual_goods/virtual_avatar_spec.dart';

void main() {
  test('安装包只内置 24 张完整成品图，云端头像不会增加包体积', () {
    expect(VirtualAvatarCatalog.finishedAssets, hasLength(24));
    for (final path in VirtualAvatarCatalog.finishedAssets.values) {
      expect(path, startsWith('assets/avatars/finished/'));
      expect(path, endsWith('.webp'));
    }
  });

  testWidgets('24 张成品头像全部可解码', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    await tester.runAsync(() async {
      for (final entry in VirtualAvatarCatalog.finishedAssets.entries) {
        final style = entry.key.split('_').first;
        final config = VirtualAvatarSpec.normalize({
          'productType': 'finished',
          'categoryCode': style,
          'renderStyle': style,
          'assetCode': entry.key,
        });
        expect(VirtualAvatarArtwork.assetPaths(config), [entry.value]);
        await VirtualAvatarArtwork.precache(context, config);
      }
    });
  });

  test('未知成品和旧分层都不会再进入拼装渲染', () {
    final invalid = VirtualAvatarSpec.normalize({
      'productType': 'finished',
      'assetCode': '../../private',
      'eyes': 11,
      'glasses': 8,
    });
    final legacy = VirtualAvatarSpec.normalize({
      'productType': 'editable',
      'eyes': 11,
      'glasses': 8,
    });
    expect(invalid['assetCode'], 'micro_jinglan');
    expect(legacy['assetCode'], 'micro_jinglan');
    expect(VirtualAvatarArtwork.assetPaths(invalid), hasLength(1));
    expect(VirtualAvatarArtwork.assetPaths(legacy), hasLength(1));
  });

  testWidgets('真实头像预览使用圆形裁切', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox.square(
        dimension: 120,
        child: VirtualAvatarArtwork(
          config: VirtualAvatarSpec.defaults(),
          circular: true,
        ),
      ),
    ));

    expect(find.byType(ClipOval), findsOneWidget);
  });
}
