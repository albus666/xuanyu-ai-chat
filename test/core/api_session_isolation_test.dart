import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';

class _DelayedUnauthorized implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('未登录后台401不反复触发退出登录提示', () async {
    SharedPreferences.setMockInitialValues({});
    final original = apiClient.httpClientAdapter;
    addTearDown(() {
      apiClient.httpClientAdapter = original;
      setupApiClientToken(null);
    });
    setupApiClientToken(null);
    final trigger = unauthorizedTrigger.value;
    final session = apiSessionChanges.value;
    for (var i = 0; i < 3; i++) {
      final fake = _DelayedUnauthorized();
      apiClient.httpClientAdapter = fake;
      final pending = expectLater(apiClient.get<void>('/background-test'),
          throwsA(isA<DioException>()));
      await fake.started.future;
      fake.response
          .complete(ResponseBody.fromString('{"message":"请先登录"}', 401));
      await pending;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(unauthorizedTrigger.value, trigger);
    expect(apiSessionChanges.value, session);
  });

  test('旧账号迟到的401不能退出新账号或删除新账号缓存', () async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    final original = apiClient.httpClientAdapter;
    final fake = _DelayedUnauthorized();
    apiClient.httpClientAdapter = fake;
    addTearDown(() {
      apiClient.httpClientAdapter = original;
      setupApiClientToken(null);
    });
    setupApiClientToken('synthetic-session-a');
    final pending = apiClient.get<void>('/isolated-session-test');
    final expectation = expectLater(pending, throwsA(isA<DioException>()));
    await fake.started.future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 8);
    await prefs.setString(AppConstants.keyDailyFortuneCache, '新账号缓存');
    setupApiClientToken('synthetic-session-b');
    final trigger = unauthorizedTrigger.value;
    fake.response.complete(ResponseBody.fromString('{}', 401));
    await expectation;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(prefs.getInt(AppConstants.keyUserId), 8);
    expect(prefs.getString(AppConstants.keyDailyFortuneCache), '新账号缓存');
    expect(unauthorizedTrigger.value, trigger);
  });

  test('当前账号真实失效时仍清除登录态并通知界面', () async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    final original = apiClient.httpClientAdapter;
    final fake = _DelayedUnauthorized();
    apiClient.httpClientAdapter = fake;
    addTearDown(() {
      apiClient.httpClientAdapter = original;
      setupApiClientToken(null);
    });
    setupApiClientToken('synthetic-current-session');
    final trigger = unauthorizedTrigger.value;
    final expectation = expectLater(
        apiClient.get<void>('/isolated-session-test'),
        throwsA(isA<DioException>()));
    await fake.started.future;
    fake.response.complete(ResponseBody.fromString('{}', 401));
    await expectation;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AppConstants.keyUserId), isNull);
    expect(unauthorizedTrigger.value, trigger + 1);
  });
}
