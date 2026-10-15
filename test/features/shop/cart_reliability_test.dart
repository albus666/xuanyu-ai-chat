import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/shop/shop_page.dart';
import 'package:xuanyu/features/shop/shop_product_detail_page.dart';

Map<String, dynamic> _item(String name, {int quantity = 1}) => {
      'id': 7,
      'quantity': quantity,
      'selected': true,
      'valid': true,
      'subtotal': '$quantity.00',
      'product': {'name': name, 'coverUrl': ''},
      'sku': {'id': 8, 'name': '标准规格', 'price': '1.00'},
    };

Response<dynamic> _response(RequestOptions request, Object? data,
        {int code = 0, String? message}) =>
    Response<dynamic>(
        requestOptions: request,
        statusCode: 200,
        data: {'code': code, 'message': message, 'data': data});

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    setupApiClientToken('cart-test-old');
    respond = (request, handler) => handler.resolve(_response(request, {
          'list': [_item('测试商品')]
        }));
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    dismissAllAppToasts();
    apiClient.interceptors.remove(interceptor);
    setupApiClientToken(null);
  });

  Future<void> openCart(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: ShopCartTab())));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('购物车业务加载失败显示重试而非空购物车', (tester) async {
    respond = (request, handler) => handler
        .resolve(_response(request, null, code: 403, message: '暂时无法读取购物车'));
    await openCart(tester);
    expect(find.text('暂时无法读取购物车'), findsOneWidget);
    expect(find.text('购物车还是空的'), findsNothing);
    respond = (request, handler) => handler.resolve(_response(request, {
          'list': [_item('恢复的商品')]
        }));
    await tester.tap(find.text('重新加载购物车'));
    await tester.pumpAndSettle();
    expect(find.text('恢复的商品'), findsOneWidget);
    expect(find.text('暂时无法读取购物车'), findsNothing);
  });

  testWidgets('购物车切号清旧数据且晚到旧响应不能覆盖新账号', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      if (request.headers['Authorization'] == 'Bearer cart-test-old') {
        pendingRequest = request;
        pending = handler;
      } else {
        handler.resolve(_response(request, {
          'list': [_item('新账号商品')]
        }));
      }
    };
    await openCart(tester);
    expect(pending, isNotNull);
    setupApiClientToken('cart-test-new');
    await tester.pump(const Duration(milliseconds: 100));
    pending!.resolve(_response(pendingRequest!, {
      'list': [_item('旧账号商品')]
    }));
    await tester.pumpAndSettle();
    expect(find.text('新账号商品'), findsOneWidget);
    expect(find.text('旧账号商品'), findsNothing);
  });

  testWidgets('更新数量防重复且更新期间禁止结算，业务拒绝保留原数量', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      if (request.method == 'PATCH') {
        pendingRequest = request;
        pending = handler;
      } else {
        handler.resolve(_response(request, {
          'list': [_item('测试商品')]
        }));
      }
    };
    await openCart(tester);
    final plus = find.widgetWithIcon(IconButton, Icons.add_circle_outline);
    final callback = tester.widget<IconButton>(plus).onPressed!;
    callback();
    callback();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((r) => r.method == 'PATCH'), hasLength(1));
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '结算(1)'))
            .onPressed,
        isNull);
    pending!.resolve(
        _response(pendingRequest!, null, code: 409, message: '商品库存不足'));
    await tester.pumpAndSettle();
    expect(find.text('商品库存不足'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(calls.where((r) => r.method == 'GET'), hasLength(1));
    dismissAllAppToasts();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('数量修改成功但刷新失败时禁止用旧数量结算', (tester) async {
    int reads = 0;
    respond = (request, handler) {
      if (request.method == 'PATCH') {
        handler.resolve(_response(request, {}));
      } else if (++reads == 1) {
        handler.resolve(_response(request, {
          'list': [_item('测试商品')]
        }));
      } else {
        handler.resolve(_response(request, null, code: 503, message: '刷新失败'));
      }
    };
    await openCart(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('刷新失败'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '结算(1)'))
            .onPressed,
        isNull);
  });

  testWidgets('更新超时结果不明时锁定结算直到重新加载确认', (tester) async {
    respond = (request, handler) {
      if (request.method == 'PATCH') {
        handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ));
      } else {
        handler.resolve(_response(request, {
          'list': [_item('测试商品')]
        }));
      }
    };
    await openCart(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('购物车更新结果尚未确认，请重新加载后继续'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '结算(1)'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.add_circle_outline))
            .onPressed,
        isNull);
    respond = (request, handler) => handler.resolve(_response(request, {
          'list': [_item('测试商品', quantity: 2)]
        }));
    await tester.tap(find.text('重新加载购物车'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '结算(1)'))
            .onPressed,
        isNotNull);
    dismissAllAppToasts();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('购物车条目字段损坏显示重试而不崩溃或显示空列表', (tester) async {
    respond = (request, handler) => handler.resolve(_response(request, {
          'list': [
            {..._item('损坏条目'), 'product': null},
          ]
        }));
    await openCart(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('购物车返回数据异常，请重试'), findsOneWidget);
    expect(find.text('购物车还是空的'), findsNothing);
    expect(find.text('重新加载购物车'), findsOneWidget);
  });

  Future<void> openProduct(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: ShopProductDetailPage(productId: 1)));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> product() => {
        'id': 1,
        'name': '测试商品',
        'images': <String>[],
        'skus': [
          {'id': 8, 'name': '标准规格', 'price': '1.00', 'stock': 10}
        ],
      };

  testWidgets('加购防重复并展示业务失败，不假报加入成功', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      if (request.method == 'POST') {
        pendingRequest = request;
        pending = handler;
      } else {
        handler.resolve(_response(request, product()));
      }
    };
    await openProduct(tester);
    final add = find.widgetWithText(OutlinedButton, '加入购物车');
    final callback = tester.widget<OutlinedButton>(add).onPressed!;
    callback();
    callback();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    pending!.resolve(
        _response(pendingRequest!, null, code: 409, message: '所选规格已售罄'));
    await tester.pumpAndSettle();
    expect(find.text('所选规格已售罄'), findsOneWidget);
    expect(find.text('已加入购物车'), findsNothing);
    dismissAllAppToasts();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('商品页切号后旧加购完成不提示新账号成功且不能再次加购', (tester) async {
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pending;
    respond = (request, handler) {
      if (request.method == 'POST') {
        pendingRequest = request;
        pending = handler;
      } else {
        handler.resolve(_response(request, product()));
      }
    };
    await openProduct(tester);
    await tester.tap(find.text('加入购物车'));
    await tester.pump(const Duration(milliseconds: 100));
    setupApiClientToken('cart-test-new');
    pending!.resolve(_response(pendingRequest!, {}));
    await tester.pumpAndSettle();
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(find.text('已加入购物车'), findsNothing);
    expect(find.text('加入购物车'), findsNothing);
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    expect(pendingRequest!.headers['Authorization'], 'Bearer cart-test-old');
  });
}
