import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/partner_portrait/partner_portrait_models.dart';

void main() {
  test('伴侣画像状态完整解析价格、章节、单项结果与永久解锁状态', () {
    final state = PartnerPortraitState.fromJson(<String, dynamic>{
      'profileKey': 'profile-a',
      'headline': '关系中的TA有多面性',
      'keywords': <String>['稳', '清醒', '有边界'],
      'reportOwned': true,
      'reportPrice': '29.0000',
      'bundlePrice': 39,
      'walletBalance': '88.5000',
      'purchaseRule': '一次解锁，永久保存',
      'disclaimer': '传统文化参考',
      'chapters': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': 'personality',
          'title': '性格底色',
          'unlocked': true,
          'tag': '紫微',
          'preview': '有主见',
          'detail': '详细内容',
          'relationshipTip': '说清期待',
          'evidence': '紫微、左辅',
        },
      ],
      'tests': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'emotion',
          'title': 'TA为什么沉默',
          'subtitle': '理解真实需要',
          'focusCode': 'innerWorld',
          'price': '6.0000',
          'tone': 'lilac',
          'owned': true,
          'result': <String, dynamic>{
            'headline': '沉默不等于冷淡',
            'answer': '答案',
            'keyPoints': <String>['慢热', '需要空间'],
            'action': '约定回应时间',
          },
        },
      ],
    });

    expect(state.reportOwned, isTrue);
    expect(state.reportPrice, 29);
    expect(state.walletBalance, 88.5);
    expect(state.chapters.single.unlocked, isTrue);
    expect(state.tests.single.owned, isTrue);
    expect(state.tests.single.result?.keyPoints, <String>['慢热', '需要空间']);
  });

  test('异常或缺失的数值按零处理，锁定章节不泄露内容', () {
    final state = PartnerPortraitState.fromJson(<String, dynamic>{
      'chapters': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': 'career',
          'title': '事业方向',
          'unlocked': false,
          'preview': '待解锁',
        },
      ],
      'tests': <dynamic>[],
      'reportPrice': 'not-a-number',
    });

    expect(state.reportPrice, 0);
    expect(state.chapters.single.unlocked, isFalse);
    expect(state.chapters.single.detail, isEmpty);
  });
}
