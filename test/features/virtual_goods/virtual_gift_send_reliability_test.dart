import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only fault injection for the existing shared_preferences plugin.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_intent.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_sheet.dart';

class _GiftAdapter implements HttpClientAdapter {
  final requests = <Map<String, dynamic>>[];
  bool timeoutOnce = false;
  bool priceChangedOnce = false;
  bool invalidCatalog = false;
  bool invalidSuccess = false;
  Completer<void>? sendGate;
  double price = 1;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    if (options.path == '/api/virtual/catalog') {
      return _body({
        'code': invalidCatalog ? 500 : 0,
        'data': {
          'balance': '99999',
          'gifts': [
            {
              'code': 'test_gift',
              'name': '测试心光',
              'price': price,
              'description': '测试赠送',
              'tier': 'small',
              'iconText': '心',
              'effectDurationMs': 1200,
            }
          ],
        }
      });
    }
    if (options.path == '/api/virtual/gifts/send') {
      requests.add(Map<String, dynamic>.from(options.data as Map));
      if (sendGate != null) await sendGate!.future;
      if (timeoutOnce) {
        timeoutOnce = false;
        throw DioException(
            requestOptions: options, type: DioExceptionType.receiveTimeout);
      }
      if (priceChangedOnce) {
        priceChangedOnce = false;
        price = 2;
        return _body({
          'code': 409,
          'message': '礼物价格已更新，请重新确认',
          'data': {'reason': 'price_changed', 'notCharged': true}
        }, status: 409);
      }
      return _body({
        'code': 0,
        'data': invalidSuccess
            ? {}
            : {
                'orderNo': 'isolated-order-1',
                'orderId': 1,
                'quantity': options.data['quantity'],
                'giftCode': options.data['giftCode'],
                'receiverUserId': options.data['receiverUserId'],
                'roomId': options.data['roomId'],
                'conversationId': options.data['conversationId'],
                'totalAmount': options.data['expectedTotal'],
              }
      });
    }
    throw StateError('Unexpected isolated endpoint: ${options.path}');
  }

  ResponseBody _body(Map<String, dynamic> data, {int status = 200}) =>
      ResponseBody.fromString(jsonEncode(data), status, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
  @override
  void close({bool force = false}) {}
}

class _FailingGiftPreferences extends InMemorySharedPreferencesStore {
  _FailingGiftPreferences() : super.empty();
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key.contains('pending_gift_')) return false;
    return super.setValue(valueType, key, value);
  }
}

Future<void> _open(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () =>
                      showVirtualGiftSheet(context, targets: const [
                        VirtualGiftTarget(
                            userId: 8, nickname: '接收者', conversationId: 30),
                      ]),
                  child: const Text('打开礼物'))))));
  await tester.tap(find.text('打开礼物'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, '赠送'));
  await tester.tap(find.widgetWithText(FilledButton, '赠送'));
  await tester.pumpAndSettle();
}

void main() {
  late _GiftAdapter adapter;
  late HttpClientAdapter original;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_id': 7});
    final prefs = await SharedPreferences.getInstance();
    setupApiClientToken('isolated-gift-session-a');
    await AppSettingsStore.instance.initialize(prefs);
    original = apiClient.httpClientAdapter;
    adapter = _GiftAdapter();
    apiClient.httpClientAdapter = adapter;
  });
  tearDown(() {
    apiClient.httpClientAdapter = original;
    apiClient.options.headers.remove('Authorization');
  });

  testWidgets('直接赠送并锁定按钮，同帧点击只赠送一次', (tester) async {
    await _open(tester);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '赠送'));
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('确认送出礼物'), findsNothing);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single['expectedTotal'], '1.0000');
  });

  testWidgets('999个金额与请求一致', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await _send(tester);
    expect(adapter.requests.single['quantity'], 999);
    expect(adapter.requests.single['expectedTotal'], '999.0000');
  });

  testWidgets('超时后关闭重开仍沿用同一笔请求且锁定参数', (tester) async {
    adapter.timeoutOnce = true;
    await _open(tester);
    await _send(tester);
    expect(find.text('重试发送'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final first = Map<String, dynamic>.from(adapter.requests.single);
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开礼物'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重试发送'));
    await tester.tap(find.text('重试发送'));
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last, first);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.startsWith('pending_gift_')),
        isEmpty);
  });

  testWidgets('价格变化不自动重扣，刷新价格后重新确认', (tester) async {
    adapter.priceChangedOnce = true;
    await _open(tester);
    await _send(tester);
    expect(adapter.requests, hasLength(1));
    expect(find.text('赠送'), findsOneWidget);
    expect(find.text('2币'), findsWidgets);
    await _send(tester);
    expect(adapter.requests.last['expectedTotal'], '2.0000');
    expect(adapter.requests.last['requestKey'],
        isNot(adapter.requests.first['requestKey']));
  });

  testWidgets('待确认请求落盘失败，关闭重开也不能绕过持久化发送', (tester) async {
    final originalStore = SharedPreferencesStorePlatform.instance;
    final failing = _FailingGiftPreferences();
    SharedPreferencesStorePlatform.instance = failing;
    addTearDown(() => SharedPreferencesStorePlatform.instance = originalStore);
    await _open(tester);
    await _send(tester);
    expect(adapter.requests, isEmpty);
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开礼物'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重试发送'));
    await tester.tap(find.text('重试发送'));
    await tester.pumpAndSettle();
    expect(adapter.requests, isEmpty);
    failing.fail = false;
    await tester.ensureVisible(find.text('重试发送'));
    await tester.tap(find.text('重试发送'));
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('发送前切号不会借用新账号发礼物', (tester) async {
    await _open(tester);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', 9);
    setupApiClientToken('isolated-gift-session-b');
    await tester.pumpAndSettle();
    expect(find.text('确认送出'), findsNothing);
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(adapter.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('礼物选择界面不再提供预览入口', (tester) async {
    await _open(tester);
    expect(find.text('预览'), findsNothing);
    expect(find.text('赠送'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('请求发出后切号，迟到成功不关闭新页面且保留原账号待确认记录', (tester) async {
    adapter.sendGate = Completer<void>();
    await _open(tester);
    await tester.tap(find.text('赠送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(adapter.requests, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', 9);
    setupApiClientToken('isolated-gift-session-b');
    adapter.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(prefs.getString('pending_gift_v1_chat_30_user_7'), isNotNull);
    expect(prefs.getString('pending_gift_v1_chat_30_user_9'), isNull);
    expect(adapter.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载业务错误不伪装空目录或允许赠送', (tester) async {
    adapter.invalidCatalog = true;
    await _open(tester);
    expect(find.text('礼物加载失败，请重试'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '赠送'))
            .onPressed,
        isNull);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('异常成功响应不清除待确认记录', (tester) async {
    adapter.invalidSuccess = true;
    await _open(tester);
    await _send(tester);
    expect(find.text('重试发送'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.startsWith('pending_gift_')),
        hasLength(1));
  });

  testWidgets('小屏大字与软键盘不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await _open(tester, textScale: 1.8);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('待确认订单按账号与场景隔离，失效页面不能改写', () async {
    final scope = ApiSessionScope();
    final store =
        await VirtualGiftIntentStore.open(session: scope, conversationId: 30);
    final intent = VirtualGiftIntent.create(
        giftCode: 'test_gift',
        giftName: '心光',
        receiverId: 8,
        receiverName: '接收者',
        quantity: 1,
        total: 1,
        conversationId: 30);
    await store.save(intent);
    final otherScene =
        await VirtualGiftIntentStore.open(session: scope, conversationId: 31);
    expect(otherScene.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', 9);
    setupApiClientToken('isolated-gift-session-b');
    final other = await VirtualGiftIntentStore.open(
        session: ApiSessionScope(), conversationId: 30);
    expect(other.read(), isNull);
    await expectLater(
        store.resolve(intent), throwsA(isA<ApiSessionChangedException>()));
    await prefs.setInt('user_id', 7);
    setupApiClientToken('isolated-gift-session-a');
    final restored = await VirtualGiftIntentStore.open(
        session: ApiSessionScope(), conversationId: 30);
    expect(restored.read()!.requestKey, intent.requestKey);
  });

  test('损坏的待确认记录保留且阻止创建新单', () async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'pending_gift_v1_chat_30_user_7';
    await prefs.setString(key, '{corrupt');
    final store = await VirtualGiftIntentStore.open(
        session: ApiSessionScope(), conversationId: 30);
    expect(store.read, throwsFormatException);
    final intent = VirtualGiftIntent.create(
        giftCode: 'test_gift',
        giftName: '心光',
        receiverId: 8,
        receiverName: '接收者',
        quantity: 1,
        total: 1,
        conversationId: 30);
    await expectLater(store.save(intent), throwsFormatException);
    expect(prefs.getString(key), '{corrupt');
  });

  test('只认同一礼物对象场景数量金额的成功回执', () {
    final intent = VirtualGiftIntent.create(
        giftCode: 'test_gift',
        giftName: '心光',
        receiverId: 8,
        receiverName: '接收者',
        quantity: 2,
        total: 3.125,
        conversationId: 30);
    final receipt = <String, dynamic>{
      'orderNo': 'test-order',
      'giftCode': 'test_gift',
      'receiverUserId': 8,
      'quantity': 2,
      'totalAmount': '3.1250',
      'roomId': null,
      'conversationId': 30
    };
    expect(intent.matchesReceipt(receipt), isTrue);
    for (final change in <Map<String, dynamic>>[
      {'orderNo': ''},
      {'giftCode': 'another'},
      {'receiverUserId': 9},
      {'quantity': 1},
      {'totalAmount': '3.13'},
      {'roomId': 7},
      {'conversationId': 31},
    ]) {
      expect(intent.matchesReceipt({...receipt, ...change}), isFalse);
    }
  });
}
