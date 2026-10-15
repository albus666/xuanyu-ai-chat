import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:xuanyu/features/shop/shop_common.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/shop/goodwill_echo_page.dart';

void main() {
  testWidgets('善意申请可查看详情并取消待审核记录', (tester) async {
    var cancelled = false;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/api/shop/goodwill/campaigns')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {'list': <dynamic>[]},
            },
          ));
          return;
        }
        if (options.path.endsWith('/api/shop/goodwill/applications') &&
            options.method == 'GET') {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'list': [
                  {
                    'id': 7,
                    'campaignId': null,
                    'campaignTitle': '善意回声',
                    'description': '帮助迷路的老人找到车站',
                    'evidenceUrls': <dynamic>[],
                    'status': cancelled ? 'cancelled' : 'pending',
                    'auditRemark': '',
                    'orderId': null,
                    'createdAt': '2026-09-11T12:00:00Z',
                  },
                ],
              },
            },
          ));
          return;
        }
        if (options.path.endsWith('/api/shop/goodwill/applications/7/cancel')) {
          cancelled = true;
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {'code': 0},
          ));
          return;
        }
        handler.reject(DioException(
          requestOptions: options,
          message: 'unexpected request: ${options.path}',
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();

    expect(find.text('等待审核'), findsOneWidget);
    expect(find.text('取消申请'), findsOneWidget);
    await tester.tap(find.text('帮助迷路的老人找到车站'));
    await tester.pumpAndSettle();
    expect(find.text('审核反馈'), findsOneWidget);
    expect(find.text('平台正在核验，请耐心等待'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    tester
        .widget<TextButton>(find.widgetWithText(TextButton, '取消申请'))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('取消这次申请？'), findsOneWidget);
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('取消申请'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('赠礼卡片可进入商品式详情后再发起申请', (tester) async {
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/api/shop/goodwill/campaigns')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'list': [
                  {
                    'id': 4,
                    'title': '善意回声·符箓赠礼测试',
                    'subtitle': '上传善意证明，审核通过后仅支付测试运费',
                    'description': '赠品本身不收取费用。',
                    'proofHint': '请上传真实善意凭证。',
                    'minProofCount': 1,
                    'maxProofCount': 3,
                    'claimLimit': 1,
                    'maxQuantity': 3,
                    'shippingType': 'paid',
                    'shippingFee': '0.01',
                    'open': true,
                    'canApply': true,
                    'unavailableReason': '',
                    'reward': {
                      'productId': 16,
                      'skuId': 16,
                      'name': '【赠礼测试】善意符箓',
                      'skuName': '符箓测试款',
                      'coverUrl': '',
                      'stock': 100,
                      'skus': [
                        {
                          'id': 16,
                          'name': '随身款',
                          'spec': {'尺寸': '7×15cm'},
                          'stock': 94,
                          'active': true,
                        },
                        {
                          'id': 17,
                          'name': '居家款',
                          'spec': {'尺寸': '10×20cm'},
                          'stock': 6,
                          'active': true,
                        },
                      ],
                    },
                  },
                ],
              },
            },
          ));
          return;
        }
        if (options.path.endsWith('/api/shop/goodwill/applications')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {'list': <dynamic>[]},
            },
          ));
          return;
        }
        if (options.path.endsWith('/api/shop/products/16')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {
                'id': 16,
                'name': '【赠礼测试】善意符箓',
                'coverUrl': '',
                'images': <dynamic>[],
                'detail': '符箓赠礼详情',
              },
            },
          ));
          return;
        }
        handler.reject(DioException(
          requestOptions: options,
          message: 'unexpected request: ${options.path}',
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(home: GoodwillEchoPage()));
    await tester.pumpAndSettle();

    expect(find.text('查看赠礼详情'), findsOneWidget);
    expect(find.text('每一份善意，都有回声!'), findsOneWidget);
    expect(find.text('愿每一份善意，都被认真看见'), findsNothing);
    expect(find.textContaining('上传真实善意凭证，审核通过后可领取'), findsNothing);
    expect(find.text('赠礼¥0 · 仅付邮费¥0.01'), findsNothing);
    expect(find.text('善意回声·符箓赠礼测试'), findsNothing);
    expect(find.text('上传善意证明，审核通过后仅支付测试运费'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看赠礼详情'));
    await tester.tap(find.text('查看赠礼详情'));
    await tester.pumpAndSettle();

    expect(find.text('赠礼详情'), findsOneWidget);
    expect(find.text('申请领取'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('赠礼 ¥0'), findsOneWidget);
    expect(find.text('仅付运费 ¥0.01'), findsOneWidget);
    expect(find.text('库存 100'), findsOneWidget);
    expect(find.text('随身款 · 尺寸:7×15cm'), findsOneWidget);
    expect(find.text('居家款 · 尺寸:10×20cm'), findsOneWidget);
    await tester.tap(find.text('居家款 · 尺寸:10×20cm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('领取流程'), 260,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('领取流程'), findsOneWidget);

    await tester.tap(find.text('申请领取'));
    await tester.pumpAndSettle();
    expect(find.text('提交善意凭证'), findsOneWidget);
    expect(find.text('居家款 × 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('人工复核凭证可随善意申请提交，明确拒绝的凭证仍拦截', () async {
    final dir = await Directory.systemTemp.createTemp('goodwill-proof-test');
    final file = File('${dir.path}/proof.jpg');
    await file.writeAsBytes([1, 2, 3]);
    var rejected = false;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'reviewId': 1,
          'reviewStatus': rejected ? 'rejected' : 'manual_review',
          'url': 'https://example.test/image/7/proof.jpg',
          'message': '凭证被拒绝'
        }
      }));
    });
    apiClient.interceptors.insert(0, interceptor);
    try {
      expect(
          await uploadPrivateShopEvidence(XFile(file.path),
              acceptPending: true),
          'https://example.test/image/7/proof.jpg');
      rejected = true;
      await expectLater(
          uploadPrivateShopEvidence(XFile(file.path), acceptPending: true),
          throwsA(isA<Exception>()));
    } finally {
      apiClient.interceptors.remove(interceptor);
      await dir.delete(recursive: true);
    }
  });

  test('善意凭证与售后证据共用自动审核及人工兜底上传', () {
    final goodwill =
        File('lib/features/shop/goodwill_echo_page.dart').readAsStringSync();
    final afterSale =
        File('lib/features/shop/shop_after_sale_page.dart').readAsStringSync();
    final notifications =
        File('lib/features/message/notification_list_page.dart')
            .readAsStringSync();
    final common =
        File('lib/features/shop/shop_common.dart').readAsStringSync();

    expect(goodwill,
        contains('uploadPrivateShopEvidence(file, acceptPending: true)'));
    expect(afterSale, contains('uploadPrivateShopEvidence(file)'));
    expect(common, contains("values['moderationScope'] = 'private'"));
    expect(common, contains("error.response?.statusCode != 503"));
    expect(
        common,
        contains(
            'awaitMediaReview(response.data, acceptPending: acceptPending)'));
    expect(notifications, contains("type == 'goodwill_review'"));
    expect(notifications, contains('GoodwillEchoPage'));
    expect(goodwill, isNot(contains("'赠礼¥0 · 仅付邮费¥")));
    expect(goodwill, contains('class GoodwillGiftDetailPage'));
    expect(goodwill, contains("aspectRatio: 16 / 9"));
    expect(goodwill, contains('aspectRatio: 1'));
    expect(goodwill, isNot(contains('class GoodwillEchoApplyPage')));
    expect(goodwill, isNot(contains("'/api/shop/goodwill/echo'")));
  });
}
