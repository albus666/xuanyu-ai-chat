import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/wish/models/wish_feed_state.dart';

void main() {
  test('鱼食状态解析价格、余额和套餐', () {
    final state = WishFeedState.fromJson(<String, dynamic>{
      'walletBalance': '21.50',
      'foodBalance': 14,
      'totalPurchased': 15,
      'totalFed': 1,
      'feedQuantities': <int>[1, 3, 5, 10],
      'maxFeedQuantity': 10,
      'packages': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'companion',
          'name': '陪伴鱼食包',
          'price': '6.00',
          'quantity': 15,
        },
      ],
    });

    expect(state.walletBalance, 21.5);
    expect(state.foodBalance, 14);
    expect(state.totalFed, 1);
    expect(state.packages.single.id, 'companion');
    expect(state.packages.single.price, 6);
    expect(state.packages.single.quantity, 15);
    expect(state.feedQuantities, <int>[1, 3, 5, 10]);
    expect(state.availableFeedQuantities(), <int>[1, 3, 5, 10]);
  });

  test('购买或投喂响应只更新余额并保留套餐', () {
    final original = WishFeedState.fromJson(<String, dynamic>{
      'walletBalance': '10.00',
      'foodBalance': 0,
      'totalPurchased': 0,
      'totalFed': 0,
      'packages': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'gentle',
          'name': '轻享鱼食包',
          'price': '3.00',
          'quantity': 6,
        },
      ],
    });

    final updated = original.mergeBalance(<String, dynamic>{
      'walletBalance': '7.00',
      'foodBalance': 6,
      'totalPurchased': 6,
    });

    expect(updated.walletBalance, 7);
    expect(updated.foodBalance, 6);
    expect(updated.totalPurchased, 6);
    expect(updated.packages.single.id, 'gentle');
  });

  test('可投喂份数同时受后台上限和用户余额限制', () {
    final state = WishFeedState.fromJson(<String, dynamic>{
      'foodBalance': 4,
      'feedQuantities': <int>[10, 1, 3, 5, 3],
      'maxFeedQuantity': 5,
    });

    expect(state.feedQuantities, <int>[1, 3, 5]);
    expect(state.availableFeedQuantities(), <int>[1, 3]);
  });
}
