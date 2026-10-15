import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/cultural_reference_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/common/values/images.dart';
import 'package:xuanyu/features/wish/models/wish_feed_state.dart';
import 'package:xuanyu/features/wish/models/wish_entry.dart';
import 'package:xuanyu/features/wish/services/wish_storage_service.dart';
import 'package:xuanyu/features/wish/services/wish_feed_service.dart';
import 'package:xuanyu/features/wish/wish_prayer_page.dart';

class _FakeWishFeedService extends WishFeedService {
  int? lastFeedQuantity;
  int feedCalls = 0;

  @override
  Future<WishFeedState> loadStatus() async {
    return const WishFeedState(
      walletBalance: 20,
      foodBalance: 4,
      totalPurchased: 6,
      totalFed: 2,
      feedQuantities: <int>[1, 3],
      maxFeedQuantity: 3,
      packages: <WishFoodPackage>[
        WishFoodPackage(
          id: 'gentle',
          name: '轻享鱼食包',
          price: 3,
          quantity: 6,
        ),
        WishFoodPackage(
          id: 'companion',
          name: '陪伴鱼食包',
          price: 6,
          quantity: 15,
        ),
        WishFoodPackage(
          id: 'abundant',
          name: '丰盈鱼食包',
          price: 18,
          quantity: 50,
        ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> purchase(String packageId) async {
    return <String, dynamic>{'walletBalance': '14.00', 'foodBalance': 19};
  }

  @override
  Future<Map<String, dynamic>> feed(int quantity) async {
    feedCalls++;
    lastFeedQuantity = quantity;
    return <String, dynamic>{
      'foodBalance': 4 - quantity,
      'totalFed': 2 + quantity,
    };
  }
}

class _EmptyWishFeedService extends WishFeedService {
  const _EmptyWishFeedService();

  @override
  Future<WishFeedState> loadStatus() async {
    return const WishFeedState(
      walletBalance: 0,
      foodBalance: 0,
      totalPurchased: 0,
      totalFed: 0,
      packages: <WishFoodPackage>[
        WishFoodPackage(
          id: 'gentle',
          name: '轻享鱼食包',
          price: 3,
          quantity: 6,
        ),
      ],
    );
  }
}

class _BalanceWishFeedService extends _FakeWishFeedService {
  _BalanceWishFeedService(this.balance);
  final int balance;
  @override
  Future<WishFeedState> loadStatus() async =>
      (await super.loadStatus()).mergeBalance({'foodBalance': balance});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('心愿完成文案不包含结果承诺', () {
    expect(WishPrayerCopy.title, '心有所念');
    expect(WishPrayerCopy.completion, '心念已寄\n天地共知');
    expect(WishPrayerCopy.completion, isNot(contains('必有回音')));
  });

  test('水生物使用统一水墨素材', () {
    final assets = <String>{
      ImageAssets.wishKoiKohaku,
      ImageAssets.wishKoiGold,
      ImageAssets.wishKoiSanke,
      ImageAssets.wishPondTurtle,
    };
    expect(assets, hasLength(4));
  });

  test('心愿只在本地保存并按时间倒序读取', () async {
    final earlier = WishEntry(
      id: 'earlier',
      category: '为自己',
      content: '希望今晚好好睡一觉',
      createdAt: DateTime(2026, 8, 4, 20),
    );
    final later = WishEntry(
      id: 'later',
      category: '重新开始',
      content: '愿我有勇气走出第一步',
      createdAt: DateTime(2026, 8, 4, 21),
    );

    await WishStorageService.add(earlier);
    await WishStorageService.add(later);
    final entries = await WishStorageService.load();

    expect(entries.map((item) => item.id), <String>['later', 'earlier']);
    expect(entries.first.content, '愿我有勇气走出第一步');
  });

  test('可以删除单条本地心愿', () async {
    await WishStorageService.add(
      WishEntry(
        id: 'wish-1',
        category: '为家人',
        content: '愿家人平安顺心',
        createdAt: DateTime(2026, 8, 4),
      ),
    );

    final entries = await WishStorageService.remove('wish-1');
    expect(entries, isEmpty);
    expect(await WishStorageService.load(), isEmpty);
  });

  testWidgets('寄出心愿后进入指定完成文案', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WishPrayerPage(feedingEnabled: false),
      ),
    );
    await tester.pump();

    expect(find.text('天地祈福'), findsNothing);
    expect(find.byKey(const ValueKey<String>('wish-gate')), findsOneWidget);
    expect(find.text('轻触山门'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('wish-input')), findsNothing);
    expect(find.text(WishPrayerCopy.title), findsNothing);
    expect(find.text('为自己'), findsNothing);
    expect(find.text('为家人'), findsNothing);
    expect(find.text('感情'), findsNothing);
    expect(find.text('工作学业'), findsNothing);
    expect(find.text('心愿簿'), findsNothing);
    expect(find.text('查看心愿簿'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('wish-gate')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey<String>('wish-input')), findsOneWidget);
    expect(find.text(WishPrayerCopy.title), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('wish-input')),
      '愿我安心走好今天的每一步',
    );
    await tester.tap(find.byKey(const ValueKey<String>('send-wish')));
    await tester.pump();

    expect(find.text('心愿正在凝成一束微光'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3000));
    expect(find.text('愿光正沿水面缓缓前行'), findsOneWidget);
    expect(find.text(WishPrayerCopy.completion), findsNothing);

    await tester.pump(const Duration(milliseconds: 6300));
    await tester.pump();
    expect(find.text(WishPrayerCopy.completion), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('wish_prayer_entries_v1'), isNull);

    await tester.tapAt(const Offset(12, 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(WishPrayerCopy.completion), findsNothing);
    expect(find.byKey(const ValueKey<String>('wish-gate')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('水域展示鱼食余额和三个付费套餐', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final feedService = _FakeWishFeedService();
    await tester.pumpWidget(
      MaterialApp(home: WishPrayerPage(feedService: feedService)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey<String>('wish-feed-control')), findsOne);
    expect(find.text('4份'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '鱼食剩余4份'),
        findsOneWidget);
    expect(find.text(CulturalReferenceNotice.text), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull);

    await tester.tap(find.byKey(const ValueKey<String>('wish-feed-shop')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('wish-feed-packages')), findsOne);
    expect(find.text('轻享鱼食包'), findsOne);
    expect(find.text('陪伴鱼食包'), findsOne);
    expect(find.text('丰盈鱼食包'), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final balance in [0, 1, 2]) {
    testWidgets('$balance份鱼食也弹出选择，确认前不投喂', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _BalanceWishFeedService(balance);
      await tester
          .pumpWidget(MaterialApp(home: WishPrayerPage(feedService: service)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('wish-feed-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('这次投喂多少？'), findsOneWidget);
      expect(find.text('现有 $balance 份鱼食，选择后会一次撒下'), findsOneWidget);
      expect(service.feedCalls, 0);
      expect(find.byKey(const ValueKey('wish-feed-packages')), findsNothing);
      if (balance > 0) {
        await tester.tap(find.byKey(const ValueKey('wish-feed-quantity-1')));
        await tester.pump();
        expect(service.feedCalls, 1);
      } else {
        expect(find.byType(ActionChip), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('尚未吃完时上方继续喂食，下方仍打开购买鱼食', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeWishFeedService();
    await tester
        .pumpWidget(MaterialApp(home: WishPrayerPage(feedService: service)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('wish-feed-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byKey(const ValueKey('wish-feed-quantity-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(service.feedCalls, 1);
    await tester.tap(find.byKey(const ValueKey('wish-feed-button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));
    expect(service.feedCalls, 1);
    await tester.tap(find.byKey(const ValueKey('wish-feed-quantity-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.feedCalls, 2);
    expect(find.byKey(const ValueKey('wish-feed-packages')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wish-feed-shop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('wish-feed-packages')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('可选择多份投喂且动画期间不显示长时间转圈', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final feedService = _FakeWishFeedService();

    await tester.pumpWidget(
      MaterialApp(home: WishPrayerPage(feedService: feedService)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey<String>('wish-feed-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.byKey(const ValueKey<String>('wish-feed-quantity-sheet')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('wish-feed-quantity-3')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(feedService.lastFeedQuantity, 3);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '鱼食剩余1份'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('鱼儿正在靠近'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('wish-feed-shop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('wish-feed-packages')),
        findsOneWidget);
    Navigator.of(tester
            .element(find.byKey(const ValueKey<String>('wish-feed-packages'))))
        .pop();
    await tester.pump(const Duration(milliseconds: 300));

    for (var frame = 0; frame < 450; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('鱼儿正在靠近'), findsNothing);
    expect(find.text('鱼儿正在吃食'), findsNothing);
    expect(find.text('鱼儿正在慢慢游开'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('wish-feed-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byKey(const ValueKey('wish-feed-quantity-1')));
    await tester.pump();
    expect(feedService.lastFeedQuantity, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('余额不足弹窗点击遮罩即可关闭', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WishPrayerPage(feedService: _EmptyWishFeedService()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey<String>('wish-feed-shop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('轻享鱼食包'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('余额不足'), findsOneWidget);

    await tester.tapAt(const Offset(12, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('余额不足'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
