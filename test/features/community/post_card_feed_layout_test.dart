import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xuanyu/features/community/post_card.dart';
import 'package:xuanyu/features/community/post_text_cover_preview.dart';

void main() {
  for (final type in ['image', 'video']) {
    testWidgets('私密作品$type媒体点击进入作品详情', (tester) async {
      var opens = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PostCard(
        item: {
          'id': 98,
          'nickname': '我',
          'content': '私密作品',
          'mediaType': type,
          'mediaUrls': ['https://example.com/private.$type']
        },
        showActionRow: false,
        openMediaAsPost: true,
        onTap: () => opens++,
      )))));
      await tester.pump();
      final target = type == 'video'
          ? find.byIcon(Icons.play_circle_fill_rounded)
          : find.byType(Image);
      await tester.ensureVisible(target.first);
      await tester.tap(target.first);
      await tester.pump();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('在线作者头像右下角显示绿色圆点', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: {
              'id': 99,
              'userId': 2,
              'nickname': '在线用户',
              'isOnline': true,
              'content': '在线状态示例',
            },
            integrated: true,
            showActionRow: false,
          ),
        ),
      ),
    );

    final dot = tester.widget<Container>(
      find.byKey(const ValueKey('community-online-dot')),
    );
    final decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF35C96F));
  });

  testWidgets('窄屏信息流的纯文字帖紧凑展示且操作栏不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              item: const {
                'id': 1,
                'userId': 2,
                'nickname': '测试用户',
                'content': '这是一条用于验证广场纯文字内容紧凑布局的动态。'
                    '内容较长时也不应该再撑出一整块方形封面。',
                'likeCount': 12,
                'commentCount': 3,
                'shareCount': 0,
                'createdAt': '2026-09-07T08:00:00Z',
              },
              integrated: true,
              showPrivateAction: true,
              onLike: (_) {},
              onFavorite: (_) {},
              onShare: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PostTextCoverPreview), findsNothing);
    expect(find.text('收藏'), findsNothing);
    expect(find.text('分享'), findsNothing);
    expect(find.text('私聊'), findsOneWidget);
    final actionRow = find.ancestor(
      of: find.text('私聊'),
      matching: find.byType(Row),
    );
    expect(actionRow, findsWidgets);
    final outerActionRow = actionRow.first;
    expect(tester.getTopRight(outerActionRow).dx, lessThanOrEqualTo(304));
    expect(tester.takeException(), isNull);
  });

  testWidgets('广场单图保留原始比例且不裁切', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              item: {
                'id': 2,
                'userId': 3,
                'nickname': '清和',
                'content': '单图动态',
                'mediaUrls': ['https://example.com/single.jpg'],
              },
              integrated: true,
              showActionRow: false,
            ),
          ),
        ),
      ),
    );

    final image = find.byType(Image);
    expect(image, findsOneWidget);
    expect(tester.getSize(image).width, 200);
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
  });

  testWidgets('长截图等比例缩小后不会撑满信息流', (tester) async {
    const url = 'https://example.com/tall-regression.jpg';
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 100, 1000),
        ui.Paint()..color = const Color(0xFF123456));
    final picture = recorder.endRecording();
    final bitmap = picture.toImageSync(100, 1000);
    picture.dispose();
    final provider = NetworkImage(url);
    PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: bitmap))));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: PostCard(
      item: {
        'id': 456,
        'nickname': '长图',
        'mediaUrls': [url]
      },
      integrated: true,
      showActionRow: false,
    )))));
    await tester.pump();
    final image = find.byType(Image);
    expect(tester.getSize(image).height, lessThanOrEqualTo(280));
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.evict(provider);
  });
  testWidgets('两张图使用两列正方形布局', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              item: {
                'id': 3,
                'userId': 4,
                'nickname': '星河',
                'content': '两图动态',
                'mediaUrls': [
                  'https://example.com/first.jpg',
                  'https://example.com/second.jpg',
                ],
              },
              integrated: true,
              showActionRow: false,
            ),
          ),
        ),
      ),
    );

    final gridView = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.childAspectRatio, 1);

    final images = find.byType(Image);
    expect(images, findsNWidgets(2));
    for (final element in images.evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == element));
      expect(size.width, size.height);
    }
  });

  testWidgets('作品详情保留图片比例并将图片排在正文前', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              item: {
                'id': 4,
                'userId': 5,
                'nickname': '作品作者',
                'content': '图片下方的作品正文',
                'mediaUrls': ['https://example.com/detail.jpg'],
              },
              integrated: true,
              detailLayout: true,
              showHeader: false,
              showActionRow: false,
            ),
          ),
        ),
      ),
    );

    final image = find.byType(Image);
    expect(image, findsOneWidget);
    expect(tester.getTopLeft(image).dy,
        lessThan(tester.getTopLeft(find.text('图片下方的作品正文')).dy));
    expect(tester.getSize(image).width / tester.getSize(image).height,
        closeTo(1.45, 0.01));
  });
}
