import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';

class _SettingsAdapter implements HttpClientAdapter {
  late Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  ResponseBody body(Map<String, dynamic> data, {int status = 200}) =>
      ResponseBody.fromString(
          jsonEncode({'code': status == 200 ? 0 : status, 'data': data}),
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppSettingsStore.instance;
  late SharedPreferences prefs;
  late _SettingsAdapter fake;
  late HttpClientAdapter previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    prefs = await SharedPreferences.getInstance();
    previous = apiClient.httpClientAdapter;
    fake = _SettingsAdapter();
    apiClient.httpClientAdapter = fake;
    setupApiClientToken('synthetic-settings-a');
    await store.initialize(prefs);
  });
  tearDown(() {
    apiClient.httpClientAdapter = previous;
    setupApiClientToken(null);
  });

  test('旧账号迟到的设置响应不覆盖新账号', () async {
    final old = Completer<ResponseBody>();
    final started = Completer<void>();
    fake.respond = (_) {
      if (!started.isCompleted) {
        started.complete();
        return old.future;
      }
      return Future.value(fake
          .body({...AppSettingsStore.defaults, 'allowDirectMessages': 'none'}));
    };
    final first = store.syncFromServer();
    await started.future;
    await prefs.setInt(AppConstants.keyUserId, 8);
    setupApiClientToken('synthetic-settings-b');
    await store.syncFromServer();
    old.complete(fake.body(
        {...AppSettingsStore.defaults, 'allowDirectMessages': 'everyone'}));
    await first;
    expect(store.stringValue('allowDirectMessages'), 'none');
  });

  test('一个开关失败不会撤销另一个成功的设置', () async {
    final slow = Completer<ResponseBody>();
    final started = Completer<void>();
    fake.respond = (request) {
      if ((request.data as Map).containsKey('showOnlineStatus')) {
        started.complete();
        return slow.future;
      }
      return Future.value(fake
          .body({...AppSettingsStore.defaults, 'allowDirectMessages': 'none'}));
    };
    final first = store.update({'showOnlineStatus': false});
    final failed = expectLater(first, throwsA(isA<DioException>()));
    await started.future;
    final second = store.update({'allowDirectMessages': 'none'});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    slow.complete(fake.body({}, status: 503));
    await failed;
    await second;
    expect(store.boolValue('showOnlineStatus'), isTrue);
    expect(store.stringValue('allowDirectMessages'), 'none');
  });

  test('切换账号立即恢复各自的隐私缓存而非沿用上一人', () async {
    fake.respond = (request) async => fake.body({
          ...AppSettingsStore.defaults,
          if (request.data is Map)
            ...Map<String, dynamic>.from(request.data as Map),
        });
    await store.update({'allowDirectMessages': 'none'});
    await prefs.setInt(AppConstants.keyUserId, 8);
    setupApiClientToken('synthetic-settings-b');
    expect(store.stringValue('allowDirectMessages'), 'everyone');
    await prefs.setInt(AppConstants.keyUserId, 7);
    setupApiClientToken('synthetic-settings-a');
    expect(store.stringValue('allowDirectMessages'), 'none');
  });

  test('早于用户修改的刷新响应不会把开关改回旧值', () async {
    final old = Completer<ResponseBody>();
    final started = Completer<void>();
    fake.respond = (request) {
      if (request.method == 'GET') {
        started.complete();
        return old.future;
      }
      return Future.value(
          fake.body({...AppSettingsStore.defaults, 'showOnlineStatus': false}));
    };
    final refresh = store.syncFromServer();
    await started.future;
    await store.update({'showOnlineStatus': false});
    old.complete(fake.body(AppSettingsStore.defaults));
    await refresh;
    expect(store.boolValue('showOnlineStatus'), isFalse);
  });

  for (final firstSucceeds in [false, true]) {
    test('同一开关连续修改，失败时回到最后确认的值（首次成功=$firstSucceeds）', () async {
      final slow = Completer<ResponseBody>();
      final started = Completer<void>();
      var calls = 0;
      fake.respond = (_) {
        if (calls++ == 0) {
          started.complete();
          return slow.future;
        }
        return Future.value(fake.body({}, status: 503));
      };
      final first = store.update({'showOnlineStatus': false});
      final firstResult = firstSucceeds
          ? first
          : expectLater(first, throwsA(isA<DioException>()));
      await started.future;
      final second = store.update({'showOnlineStatus': true});
      final secondResult = expectLater(second, throwsA(isA<DioException>()));
      slow.complete(firstSucceeds
          ? fake.body({...AppSettingsStore.defaults, 'showOnlineStatus': false})
          : fake.body({}, status: 503));
      await firstResult;
      await secondResult;
      expect(store.boolValue('showOnlineStatus'), !firstSucceeds);
    });
  }

  test('切换账号丢弃未发送的旧设置，不会借用新账号提交', () async {
    final slow = Completer<ResponseBody>();
    final started = Completer<void>();
    fake.respond = (_) {
      started.complete();
      return slow.future;
    };
    final first = store.update({'allowDirectMessages': 'none'});
    final firstResult = expectLater(first, throwsStateError);
    await started.future;
    final queued = store.update({'showOnlineStatus': false});
    final queuedResult = expectLater(queued, throwsStateError);
    await prefs.setInt(AppConstants.keyUserId, 8);
    setupApiClientToken('synthetic-settings-b');
    slow.complete(fake
        .body({...AppSettingsStore.defaults, 'allowDirectMessages': 'none'}));
    await firstResult;
    await queuedResult;
    expect(fake.requests, hasLength(1));
    expect(store.stringValue('allowDirectMessages'), 'everyone');
    expect(store.boolValue('showOnlineStatus'), isTrue);
  });

  test('旧版未分账号的隐私缓存不分配给新账号，字号偏好保留', () async {
    await prefs.setString('app_setting_allowDirectMessages', 'none');
    await prefs.setBool('app_setting_largerText', true);
    await store.initialize(prefs);
    expect(store.stringValue('allowDirectMessages'), 'everyone');
    expect(store.boolValue('largerText'), isTrue);
  });
}
