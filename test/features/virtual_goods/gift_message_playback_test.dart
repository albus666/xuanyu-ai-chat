import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/consultation/voice_plaza_room_page.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';
import 'package:xuanyu/features/message/chat_page.dart';
import 'package:xuanyu/features/virtual_goods/virtual_gift_sheet.dart';

import '../consultation/voice_room_recovery_test.dart'
    show FakeRoomRtc, FakeRoomSocket;

Map<String, dynamic> _giftMessage(int id, {bool isMe = false}) => {
      'id': id,
      'userId': isMe ? 7 : 8,
      'senderId': isMe ? 7 : 8,
      'nickname': isMe ? '本人' : '送礼测试者',
      'avatarUrl': '',
      'type': 'gift',
      'isMe': isMe,
      'status': 'visible',
      'content': jsonEncode({
        'orderId': id,
        'orderNo': 'VG$id',
        'giftName': '小心意$id',
        'tier': 'small',
        'iconText': '礼',
        'quantity': 3,
        'receiverName': '接收者',
        'effectDurationMs': 8000,
      }),
      'createdAt': DateTime(2026, 9, 29, 8, 0, id).toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InterceptorsWrapper interceptor;
  late List<Map<String, dynamic>> messages;
  late FakeRoomRtc rtc;
  late List<FakeRoomSocket> sockets;
  final overlay = VoiceRoomOverlayController.instance;

  void ok(RequestOptions request, RequestInterceptorHandler handler,
          Map<String, dynamic> data) =>
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {'code': 0, 'data': data},
      ));

  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    // No auth header means ChatPage will never open a real WebSocket.
    apiClient.options.headers.remove('Authorization');
    messages = [_giftMessage(1)];
    rtc = FakeRoomRtc();
    sockets = [];
    if (overlay.roomId != null) overlay.didClose(overlay.roomId!);
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/messages')) {
        final after = request.queryParameters['after_id'] as int? ?? 0;
        return ok(request, handler, {
          'list': messages.where((row) => (row['id'] as int) > after).toList(),
          'hasMore': false,
          'revokedIds': [],
          'recalledIds': [],
        });
      }
      if (request.path == '/api/consultation/rooms/1') {
        return ok(request, handler, {
          'id': 1,
          'title': '礼物测试房间',
          'status': 'live',
          'roomType': 'party',
          'members': [
            {
              'userId': 7,
              'isMe': true,
              'role': 'listener',
              'nickname': '本人',
              'micStatus': 'none',
            }
          ],
          'owner': {'nickname': '房主'},
        });
      }
      if (request.path.endsWith('/join')) {
        return ok(request, handler, {
          'rtcToken': 'mock-gift-test-only',
          'channel': 'mock-gift-room',
          'uid': 7,
          'publisher': false,
        });
      }
      // Fully isolated: reject unknown mutations, never fall through to HTTP.
      if (request.method != 'GET' && !request.path.endsWith('/read')) {
        handler.reject(DioException(
          requestOptions: request,
          error: 'Unexpected test mutation',
        ));
        return;
      }
      ok(request, handler, {});
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() async {
    apiClient.interceptors.remove(interceptor);
    apiClient.options.headers.remove('Authorization');
    if (overlay.roomId != null) overlay.didClose(overlay.roomId!);
    for (final socket in sockets) {
      await socket.close();
    }
  });

  Future<void> frames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  VirtualGiftEffect effect(WidgetTester tester) =>
      tester.widget<VirtualGiftEffect>(find.byType(VirtualGiftEffect));

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final type in ['single', 'group']) {
    testWidgets('$type 聊天初次不播旧礼物，双方新礼物排队且切号清除', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: ChatPage(
        conversationId: 42,
        title: '礼物测试会话',
        conversationType: type,
        peerUserId: 8,
      )));
      await frames(tester);
      expect(find.byType(VirtualGiftEffect), findsNothing);

      messages.addAll([_giftMessage(2), _giftMessage(3, isMe: true)]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(effect(tester).payload['orderNo'], 'VG2');
      expect(effect(tester).payload['senderName'], '送礼测试者');
      expect(effect(tester).payload['quantity'], 3);
      effect(tester).onCompleted?.call();
      await tester.pump();
      expect(effect(tester).payload['orderNo'], 'VG3');
      effect(tester).onCompleted?.call();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(find.byType(VirtualGiftEffect), findsNothing);

      messages.add(_giftMessage(4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(find.byType(VirtualGiftEffect), findsOneWidget);
      apiSessionChanges.value++;
      await tester.pump();
      expect(find.byType(VirtualGiftEffect), findsNothing);
      await finish(tester);
    });
  }

  testWidgets('房间不回放历史，自方回流和对方新礼物都播放，切号停止', (tester) async {
    apiClient.options.headers['Authorization'] = 'Bearer mock-gift-test';
    overlay.open(1);
    await tester.pumpWidget(MaterialApp(
        home: VoicePlazaRoomPage(
      roomId: 1,
      rtcEngineFactory: () => rtc,
      audioServiceUpdater: (_, __) async {},
      roomEventsConnector: (_, __) async {
        final socket = FakeRoomSocket();
        sockets.add(socket);
        return socket;
      },
    )));
    await frames(tester, count: 12);
    expect(find.byType(VirtualGiftEffect), findsNothing);

    messages.addAll([_giftMessage(2), _giftMessage(3, isMe: true)]);
    final state = tester.state(find.byType(VoicePlazaRoomPage));
    (state as WidgetsBindingObserver)
        .didChangeAppLifecycleState(AppLifecycleState.resumed);
    await frames(tester, count: 12);
    expect(effect(tester).payload['orderNo'], 'VG2');
    effect(tester).onCompleted?.call();
    await tester.pump();
    expect(effect(tester).payload['orderNo'], 'VG3');

    apiSessionChanges.value++;
    await frames(tester);
    expect(find.byType(VirtualGiftEffect), findsNothing);
    await finish(tester);
  });
}
