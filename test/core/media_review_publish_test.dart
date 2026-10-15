import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/media_review.dart';

void main() {
  test('公开媒体处于人工复核时不使用上传地址提前发布', () async {
    var fetched = false;
    await expectLater(
      awaitMediaReview(
        {
          'data': {'reviewId': 1, 'reviewStatus': 'manual_review'}
        },
        fallbackUrl: 'https://invalid.test/uploaded.jpg',
        fetchReview: (_) async {
          fetched = true;
          throw StateError('不应轮询');
        },
      ),
      throwsA(isA<MediaReviewException>()
          .having((e) => e.message, 'message', contains('人工复核'))),
    );
    expect(fetched, isFalse);
  });

  test('已通过媒体正常返回服务端地址', () async {
    final result = await awaitMediaReview({
      'data': {
        'reviewId': 2,
        'reviewStatus': 'approved',
        'url': 'https://invalid.test/approved.jpg'
      }
    });
    expect(result['url'], 'https://invalid.test/approved.jpg');
  });

  test('私聊允许等待审核的流程保持不变', () async {
    final result = await awaitMediaReview(
      {
        'data': {'reviewId': 3, 'reviewStatus': 'scanning'}
      },
      fallbackUrl: 'https://invalid.test/private.jpg',
      acceptPending: true,
    );
    expect(result['url'], 'https://invalid.test/private.jpg');
  });
}
