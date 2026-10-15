import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/config/app_content_config.dart';
import 'package:xuanyu/core/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppContentConfig lives for the process lifetime. Exercise its disk hydration,
  // failed refresh, retry, and fresh-memory phases in order without test hooks.
  test('公共配置先显示磁盘，强制刷新合并，失败保留快照且可再次刷新', () async {
    const key = 'public_app_content_config_v1';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({
        'cachedAt': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'data': {
          'home': {'galaxyRevolutionSeconds': 420},
        },
      }),
    });
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    final interceptor = InterceptorsWrapper(
      onRequest: (request, handler) {
        expect(request.path, '/api/config/app-content');
        pending.add((request, handler));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));
    var changes = 0;
    void changed() => changes++;
    AppContentConfig.changes.addListener(changed);
    addTearDown(() => AppContentConfig.changes.removeListener(changed));

    Future<void> flush() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final cached = await AppContentConfig.load();
    expect(cached['home']['galaxyRevolutionSeconds'], 420);
    await flush();
    expect(pending, hasLength(1));
    expect(changes, 1);

    final forcedFirst = AppContentConfig.load(force: true);
    final forcedSecond = AppContentConfig.load(force: true);
    await flush();
    expect(pending, hasLength(1));
    pending[0].$2.reject(
          DioException(
            requestOptions: pending[0].$1,
            type: DioExceptionType.connectionError,
          ),
        );
    expect((await forcedFirst)['home']['galaxyRevolutionSeconds'], 420);
    expect((await forcedSecond)['home']['galaxyRevolutionSeconds'], 420);
    expect(AppContentConfig.section('home')['galaxyRevolutionSeconds'], 420);
    expect(changes, 1);

    final retryFirst = AppContentConfig.load(force: true);
    final retrySecond = AppContentConfig.load(force: true);
    await flush();
    expect(pending, hasLength(2));
    final (request, handler) = pending[1];
    handler.resolve(
      Response(
        requestOptions: request,
        data: {
          'code': 0,
          'data': {
            'home': {'galaxyRevolutionSeconds': 300},
          },
        },
      ),
    );
    expect((await retryFirst)['home']['galaxyRevolutionSeconds'], 300);
    expect((await retrySecond)['home']['galaxyRevolutionSeconds'], 300);
    expect(changes, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        prefs.getString(key)!,
      )['data']['home']['galaxyRevolutionSeconds'],
      300,
    );

    final fresh = await AppContentConfig.load();
    expect(fresh['home']['galaxyRevolutionSeconds'], 300);
    await flush();
    expect(pending, hasLength(2));
  });
}
