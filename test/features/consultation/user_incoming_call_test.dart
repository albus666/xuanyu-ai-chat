import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/consultation_call_overlay.dart';
import 'package:xuanyu/features/consultation/consultation_incoming_call_host.dart';

void main() {
  StartupGate.markReady();
  for (final accept in [false, true]) {
    testWidgets('普通用户任意页面看到老师来电并可${accept ? '接听' : '拒绝'}', (tester) async {
      apiClient.interceptors.clear();
      var waiting = true;
      final actions = <String>[];
      final interceptor = InterceptorsWrapper(onRequest: (r, h) {
        final path = r.path;
        if (path.endsWith('/accept') || path.endsWith('/reject')) {
          actions.add(path);
          waiting = false;
        }
        final session = {
          'id': 77,
          'status': 'waiting',
          'initiatorRole': 'teacher',
          'canAnswer': true,
          'peer': {'nickname': '预约老师'},
          'mode': 'private'
        };
        h.resolve(Response(requestOptions: r, statusCode: 200, data: {
          'code': 0,
          'data': path == '/api/auth/me'
              ? {'isMaster': false}
              : {'session': waiting ? session : null}
        }));
      });
      apiClient.interceptors.insert(0, interceptor);
      addTearDown(() => apiClient.interceptors.remove(interceptor));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter/platform', JSONMethodCodec()),
              (_) async => null);
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) =>
              ConsultationIncomingCallHost(child: child!),
          home: const Scaffold(body: Text('任意页面'))));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('预约老师'), findsOneWidget);
      expect(find.text('接听'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(actions, isEmpty);
      expect(ConsultationCallOverlay.instance.sessionId, isNull);
      await tester.tap(find.text(accept ? '接听' : '拒绝'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(actions,
          ['/api/consultation/sessions/77/${accept ? 'accept' : 'reject'}']);
      expect(ConsultationCallOverlay.instance.sessionId, accept ? 77 : null);
      await tester.pumpWidget(const SizedBox());
      ConsultationCallOverlay.instance.close();
      await tester.pump();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter/platform', JSONMethodCodec()), null);
    });
  }
}
