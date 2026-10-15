import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/profile/settings_subpages.dart';

class _SafetyAdapter implements HttpClientAdapter {
  final writes = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object data;
    if (options.path.endsWith('/api/config/safety-center/appeals')) {
      writes.add(Map<String, dynamic>.from(options.data as Map));
      data = {
        'code': 0,
        'data': {'id': 9, 'status': 'pending'},
      };
    } else if (options.path.endsWith('/api/config/safety-center')) {
      data = {
        'code': 0,
        'data': {
          'accountStatus': 'restricted',
          'violationCount30d': 1,
          'penalties': [
            {
              'id': 2,
              'type': 'mute',
              'reason': '短时间内多次发送高风险违规内容',
              'expireAt': '2099-01-01T12:30:00',
            }
          ],
          'violations': [
            {
              'id': 7,
              'category': '违法交易',
              'severity': 'high',
              'excerpt': '我要毒品',
              'createdAt': '2026-09-10T19:04:00',
            }
          ],
          'appeals': [],
          'guidelines': [
            {
              'title': '违法违禁与危险品',
              'description': '禁止发布、索取或交易违法违禁品。',
            }
          ],
        },
      };
    } else {
      data = {
        'code': 0,
        'data': {'list': <Object>[]},
      };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('安全中心展示真实状态、违规、处罚并可提交申诉', (tester) async {
    final original = apiClient.httpClientAdapter;
    final adapter = _SafetyAdapter();
    apiClient.httpClientAdapter = adapter;
    addTearDown(() => apiClient.httpClientAdapter = original);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SafetyCenterPage()));
    await tester.pumpAndSettle();

    expect(find.text('功能受限'), findsOneWidget);
    expect(find.text('近30天拦截记录 1 条'), findsOneWidget);
    expect(find.text('违法违禁与危险品'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('safety-violation-7')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('safety-violation-7')));
    await tester.pumpAndSettle();
    expect(find.text('我要毒品'), findsWidgets);
    expect(find.text('对本次判定申诉'), findsOneWidget);

    await tester.tap(find.text('对本次判定申诉'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '这是用于测试正常讨论语境，请平台重新核实判定。',
    );
    await tester.tap(find.widgetWithText(TextButton, '提交'));
    await tester.pumpAndSettle();

    expect(adapter.writes, [
      {
        'violationId': 7,
        'reason': '这是用于测试正常讨论语境，请平台重新核实判定。',
      }
    ]);
    await tester.scrollUntilVisible(
      find.text('联系内容安全团队'), 300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('2254741308@qq.com'), findsOneWidget);
    expect(find.text('举报处理时限：24小时'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('社区规则与用户协议'), 150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('社区规则与用户协议'));
    await tester.pumpAndSettle();
    expect(find.text('玄遇用户协议'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
