import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/payment/apple_iap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xuanyu/apple_iap');
  const transaction = {
    'transactionId': 'test-transaction',
    'signedTransaction': 'test-fixture'
  };
  var finishCount = 0;
  var verifyCount = 0;
  var serverAccepts = true;
  var purchaseResult = <String, dynamic>{};
  var pending = <Map<String, dynamic>>[];
  var nativeFails = false;
  var wrongTransaction = false;
  Completer<void>? verificationGate;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    finishCount = 0;
    verifyCount = 0;
    serverAccepts = true;
    purchaseResult = Map<String, dynamic>.from(transaction);
    pending = [];
    nativeFails = false;
    wrongTransaction = false;
    verificationGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'unfinished':
          if (nativeFails) throw PlatformException(code: 'unavailable');
          return pending;
        case 'purchase':
          return purchaseResult;
        case 'finish':
          finishCount++;
          return null;
        default:
          return [];
      }
    });
    apiClient.interceptors.clear();
    apiClient.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.path.endsWith('/products')) {
        handler.resolve(Response(requestOptions: options, data: {
          'code': 0,
          'data': {'appAccountToken': 'test-account', 'products': []}
        }));
      } else if (options.path.endsWith('/verify')) {
        verifyCount++;
        await verificationGate?.future;
        handler.resolve(Response(
            requestOptions: options,
            data: serverAccepts
                ? {
                    'code': 0,
                    'data': {
                      'transactionId':
                          wrongTransaction ? 'wrong' : 'test-transaction',
                      'coins': 30,
                      'sandbox': false
                    }
                  }
                : {'code': 400, 'message': 'verification failed'}));
      } else {
        handler.reject(DioException(requestOptions: options));
      }
    }));
    setupApiClientToken('isolated-test-token');
    AppleIapService.instance.initialize();
  });

  tearDown(() {
    setupApiClientToken(null);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('does not finish a transaction the server rejects', () async {
    serverAccepts = false;
    await expectLater(
        AppleIapService.instance.purchase('coins.30'), throwsStateError);
    expect(finishCount, 0);
    serverAccepts = true;
    await AppleIapService.instance.purchase('coins.30');
    expect(finishCount, 1);
  });

  test('concurrent delivery verifies and finishes only once', () async {
    verificationGate = Completer<void>();
    final first = AppleIapService.instance.purchase('coins.30');
    final second = AppleIapService.instance.purchase('coins.30');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(verifyCount, 1);
    expect(finishCount, 0);
    verificationGate!.complete();
    await Future.wait([first, second]);
    expect(finishCount, 1);
  });

  test('account change keeps a pending transaction unfinished', () async {
    verificationGate = Completer<void>();
    final purchase = AppleIapService.instance.purchase('coins.30');
    final assertion = expectLater(purchase, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    setupApiClientToken(null);
    verificationGate!.complete();
    await assertion;
    expect(finishCount, 0);
  });

  for (final status in ['cancelled', 'pending']) {
    test('$status purchase does not verify or finish', () async {
      purchaseResult = {'status': status};
      final result = await AppleIapService.instance.purchase('coins.30');
      expect(result['status'], status);
      expect(verifyCount, 0);
      expect(finishCount, 0);
    });
  }

  test('mismatched server transaction is never finished', () async {
    wrongTransaction = true;
    await expectLater(
        AppleIapService.instance.purchase('coins.30'), throwsStateError);
    expect(finishCount, 0);
  });

  test('sync reports failure and later retries the unfinished purchase',
      () async {
    pending = [transaction];
    serverAccepts = false;
    final failed = await AppleIapService.instance.sync();
    expect(failed.failed, 1);
    expect(failed.delivered, 0);
    expect(finishCount, 0);
    serverAccepts = true;
    final retried = await AppleIapService.instance.sync();
    expect(retried.failed, 0);
    expect(retried.delivered, 1);
    expect(finishCount, 1);
  });

  test('native sync failure cannot be reported as success', () async {
    nativeFails = true;
    final result = await AppleIapService.instance.sync();
    expect(result.failed, 1);
    expect(result.delivered, 0);
    expect(finishCount, 0);
  });

  test('empty sync is distinct from delivered purchases', () async {
    final result = await AppleIapService.instance.sync();
    expect(result.failed, 0);
    expect(result.delivered, 0);
    expect(result.message, '没有待同步的购买');
  });
}
