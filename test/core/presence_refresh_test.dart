import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/foreground_refresh.dart';
import 'package:xuanyu/core/network/presence_heartbeat.dart';

void main() {
  testWidgets('在线状态刷新只在前台可见时执行，不重叠，退出后停止', (tester) async {
    var calls = 0;
    var visible = true;
    Completer<void>? pending;
    final refresh = ForegroundRefresh(
      interval: const Duration(seconds: 2),
      isVisible: () => visible,
      refresh: () async {
        calls++;
        await pending?.future;
      },
    )..attach();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    visible = false;
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    visible = true;
    pending = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 2);
    pending.complete();
    await tester.pump();
    pending = null;
    refresh.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 2);
    refresh.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 3);
    refresh.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 3);
  });

  testWidgets('登录和切号立即心跳，后台与未登录不发送，前台恢复立即发送', (tester) async {
    setupApiClientToken(null);
    var calls = 0;
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      calls++;
      handler.resolve(Response(
          requestOptions: options, statusCode: 200, data: {'code': 0}));
    });
    apiClient.interceptors.insert(0, interceptor);
    final heartbeat = PresenceHeartbeat(interval: const Duration(seconds: 5))
      ..attach();
    addTearDown(() {
      heartbeat.detach();
      apiClient.interceptors.remove(interceptor);
      setupApiClientToken(null);
    });
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 0);
    setupApiClientToken('synthetic-a');
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    setupApiClientToken('synthetic-b');
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    heartbeat.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2);
    heartbeat.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 3);
    setupApiClientToken(null);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 3);
    heartbeat.detach();
    setupApiClientToken('synthetic-after-dispose');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 3);
  });
}
