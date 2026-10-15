import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:xuanyu/features/community/post_media_cache.dart';

void main() {
  test('缩略图按物理像素分档，超大屏限制解码大小且保持原始比例', () async {
    expect(postPreviewEdge(360, 1), 480);
    expect(postPreviewEdge(360, 3), 1080);
    expect(postPreviewEdge(390, 3), 1440);
    expect(postPreviewEdge(2048, 3), 1440);
    final image = postPreviewImage('https://e.test/photo', 1080);
    expect(image.width, 1080);
    expect(image.height, 1080);
    expect(image.policy, ResizeImagePolicy.fit);
    expect(image.allowUpscaling, isFalse);
    expect(
      await image.obtainKey(ImageConfiguration.empty),
      await postPreviewImage(
        'https://e.test/photo',
        postPreviewEdge(360, 3),
      ).obtainKey(ImageConfiguration.empty),
    );
    expect(
      await image.obtainKey(ImageConfiguration.empty),
      isNot(
        await const NetworkImage('https://e.test/photo')
            .obtainKey(ImageConfiguration.empty),
      ),
    );
  });

  test('同帖签名变化复用已解码图片，保留新的权限和正文', () {
    const oldUrl = 'https://media.example/photo.jpg?Expires=1&Signature=old';
    const newUrl = 'https://media.example/photo.jpg?Expires=2&Signature=new';
    final result = reuseLoadedPostMedia(
      {
        'id': 1,
        'mediaUrls': [oldUrl],
        'content': 'old',
      },
      {
        'id': 1,
        'mediaUrls': [newUrl],
        'content': 'new',
        'allowComment': false,
      },
      isLoaded: (_) => true,
    );
    expect(result['mediaUrls'], [oldUrl]);
    expect(result['content'], 'new');
    expect(result['allowComment'], false);
  });

  test('未加载、图片版本/处理变化以及不同帖子都使用新链接', () {
    const oldUrl = 'https://media.example/photo.jpg?v=1&Signature=old';
    for (final scenario in [
      (1, 'https://media.example/photo.jpg?v=1&Signature=new', false),
      (1, 'https://media.example/photo.jpg?v=2&Signature=new', true),
      (1, 'https://media.example/photo.jpg?v=1&x-oss-process=resize', true),
      (2, 'https://media.example/photo.jpg?v=1&Signature=new', true),
    ]) {
      final result = reuseLoadedPostMedia(
        {'id': 1, 'avatarUrl': oldUrl},
        {'id': scenario.$1, 'avatarUrl': scenario.$2},
        isLoaded: (_) => scenario.$3,
      );
      expect(result['avatarUrl'], scenario.$2);
    }
  });

  test('支持对象形式媒体，删除图片不残留旧内容', () {
    final result = reuseLoadedPostMedia(
      {
        'id': 1,
        'mediaUrls': [
          {'url': 'https://e.test/a?Signature=1'},
        ],
      },
      {
        'id': 1,
        'mediaUrls': [
          {'url': 'https://e.test/a?Signature=2', 'width': 200},
        ],
      },
      isLoaded: (_) => true,
    );
    expect(result['mediaUrls'][0]['url'], 'https://e.test/a?Signature=1');
    expect(result['mediaUrls'][0]['width'], 200);
    expect(
      reuseLoadedPostMedia(result, {'id': 1, 'mediaUrls': []})['mediaUrls'],
      isEmpty,
    );
  });

  test('预加载去重且最多六张，视频音频只取封面不下载文件', () {
    final urls = postPreviewUrls([
      {
        'avatarUrl': 'https://e.test/avatar',
        'mediaType': 'video',
        'mediaUrls': ['https://e.test/movie.mp4'],
        'mediaCoverUrls': ['https://e.test/cover.jpg'],
      },
      {
        'avatarUrl': 'https://e.test/avatar',
        'mediaType': 'audio',
        'mediaUrls': ['https://e.test/sound.mp3'],
      },
      for (var i = 0; i < 10; i++)
        {
          'mediaUrls': ['https://e.test/$i.jpg'],
        },
    ]).toList();
    expect(urls.length, 6);
    expect(urls.toSet().length, 6);
    expect(urls, isNot(contains('https://e.test/movie.mp4')));
    expect(urls, isNot(contains('https://e.test/sound.mp3')));
  });
}
