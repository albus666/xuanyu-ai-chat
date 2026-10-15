import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/cache/page_snapshot_cache.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/shop/shop_page.dart';
import 'package:xuanyu/features/shop/shop_product_detail_page.dart';

Map<String, dynamic> product(String name) => {
      'id': 7,
      'name': name,
      'price': '18.00',
      'coverUrl': '',
      'images': <String>[],
      'stock': 5,
      'sales': 0,
      'skus': [
        {'id': 8, 'name': '标准款', 'stock': 5, 'price': '18.00'}
      ],
    };
Map<String, dynamic> home(String name) => {
      'products': [product(name)],
      'categories': [],
      'banners': [],
    };
Response<dynamic> response(RequestOptions request, Object data) => Response(
    requestOptions: request, statusCode: 200, data: {'code': 0, 'data': data});

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PageSnapshotCache.clearMemory();
    setupApiClientToken('shop-loading-account-a');
    calls.clear();
    respond = (request, handler) => handler.resolve(response(request, {}));
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
    PageSnapshotCache.clearMemory();
    dismissAllAppToasts();
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(480, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('商城首页不请求未打开的分类和购物车', (tester) async {
    respond = (request, handler) {
      final data = request.path.endsWith('/home')
          ? home('首页商品')
          : request.path.endsWith('/categories')
              ? {
                  'list': [
                    {'id': 1, 'name': '香薰'}
                  ]
                }
              : {'list': []};
      handler.resolve(response(request, data));
    };
    await open(tester, const ShopPage());
    expect(calls.map((r) => r.path), ['/api/shop/home']);
    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path == '/api/shop/categories'), hasLength(1));
    expect(calls.where((r) => r.path == '/api/shop/products'), hasLength(1));
    expect(calls.where((r) => r.path == '/api/shop/cart'), isEmpty);
    await tester.tap(find.text('购物车'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path == '/api/shop/cart'), hasLength(1));
  });

  testWidgets('商城先显示快照，实时响应到达后替换', (tester) async {
    await tester
        .runAsync(() => PageSnapshotCache('shop_home').write(home('上次商品')));
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      pendingRequest = request;
      pending = handler;
    };
    await open(tester, const ShopPage());
    expect(find.text('上次商品'), findsOneWidget);
    expect(pending, isNotNull);
    pending!.resolve(response(pendingRequest!, home('实时商品')));
    await tester.pumpAndSettle();
    expect(find.text('实时商品'), findsOneWidget);
    expect(find.text('上次商品'), findsNothing);
  });

  testWidgets('切号立即移除旧快照且旧账号响应不得回填', (tester) async {
    await tester
        .runAsync(() => PageSnapshotCache('shop_home').write(home('旧快照')));
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    respond = (request, handler) => pending.add((request, handler));
    await open(tester, const ShopPage());
    expect(find.text('旧快照'), findsOneWidget);
    setupApiClientToken('shop-loading-account-b');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('旧快照'), findsNothing);
    expect(pending, hasLength(2));
    pending[1].$2.resolve(response(pending[1].$1, home('新账号商品')));
    await tester.pump(const Duration(milliseconds: 120));
    pending[0].$2.resolve(response(pending[0].$1, home('晚到旧账号商品')));
    await tester.pumpAndSettle();
    expect(find.text('新账号商品'), findsOneWidget);
    expect(find.text('晚到旧账号商品'), findsNothing);
  });

  testWidgets('快速切换分类时晚到的旧分类不能覆盖当前分类', (tester) async {
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    respond = (request, handler) {
      if (request.path.endsWith('/categories')) {
        handler.resolve(response(request, {
          'list': [
            {'id': 1, 'name': '香薰'},
            {'id': 2, 'name': '茶器'}
          ]
        }));
      } else if (request.queryParameters['category_id'] == 1) {
        oldRequest = request;
        oldHandler = handler;
      } else {
        handler.resolve(response(request, {
          'list': [product('茶器商品')]
        }));
      }
    };
    await open(tester, Scaffold(body: ShopCategoryTab(onProduct: (_) {})));
    await tester.tap(find.text('茶器'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('茶器商品'), findsOneWidget);
    oldHandler!.resolve(response(oldRequest!, {
      'list': [product('香薰旧响应')]
    }));
    await tester.pumpAndSettle();
    expect(find.text('茶器商品'), findsOneWidget);
    expect(find.text('香薰旧响应'), findsNothing);
  });

  testWidgets('商品详情快照可以先看但实时校验前不能下单', (tester) async {
    await tester.runAsync(() =>
        PageSnapshotCache('shop_product_detail', parameters: {'id': 7})
            .write(product('快照商品')));
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      pendingRequest = request;
      pending = handler;
    };
    await open(tester, const ShopProductDetailPage(productId: 7));
    expect(find.text('快照商品'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '立即购买'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '加入购物车'))
            .onPressed,
        isNull);
    pending!.resolve(response(pendingRequest!, product('实时商品')));
    await tester.pumpAndSettle();
    expect(find.text('实时商品'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '立即购买'))
            .onPressed,
        isNotNull);
    expect(calls.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets('实时商品已撤下规格时不能沿用快照里的库存购买', (tester) async {
    await tester.runAsync(() =>
        PageSnapshotCache('shop_product_detail', parameters: {'id': 7})
            .write(product('快照有库存')));
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      pendingRequest = request;
      pending = handler;
    };
    await open(tester, const ShopProductDetailPage(productId: 7));
    pending!.resolve(response(pendingRequest!, {
      ...product('规格已下架'),
      'skus': <Map<String, dynamic>>[],
    }));
    await tester.pumpAndSettle();
    expect(find.text('已售罄'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '已售罄'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '加入购物车'))
            .onPressed,
        isNull);
  });
  for (final empty in [false, true]) {
    testWidgets(empty ? '实时分类为空时清除快照商品' : '缓存分类已删除时切到实时首个分类', (tester) async {
      await tester.runAsync(() => PageSnapshotCache('shop_categories').write({
        'list': [{'id': 1, 'name': '旧分类'}],
      }));
      RequestOptions? categoryRequest;
      RequestInterceptorHandler? categoryHandler;
      respond = (request, handler) {
        if (request.path.endsWith('/categories')) {
          categoryRequest = request;
          categoryHandler = handler;
        } else {
          final name = request.queryParameters['category_id'] == 1 ? '旧分类商品' : '新分类商品';
          handler.resolve(response(request, {'list': [product(name)]}));
        }
      };
      await open(tester, Scaffold(body: ShopCategoryTab(onProduct: (_) {})));
      expect(find.text('旧分类商品'), findsOneWidget);
      categoryHandler!.resolve(response(categoryRequest!, {
        'list': empty ? [] : [{'id': 2, 'name': '新分类'}],
      }));
      await tester.pumpAndSettle();
      expect(find.text('旧分类商品'), findsNothing);
      if (empty) {
        expect(find.text('该分类暂未上架商品'), findsOneWidget);
      } else {
        expect(find.text('新分类商品'), findsOneWidget);
        expect(calls.where((r) => r.path.endsWith('/products') && r.queryParameters['category_id'] == 2), hasLength(1));
      }
    });
  }

}
