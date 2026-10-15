import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/ai_master_chat_page.dart';
import 'package:xuanyu/features/message/ai_square_page.dart';
import 'package:xuanyu/features/message/message_page.dart';

void main() {
  late Interceptor fakeApi;
  late List<String> requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    fakeApi = InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options.path);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'code': 0,
              'data': {'list': [], 'messages': [], 'unreadCount': 0},
            },
          ),
        );
      },
    );
    apiClient.interceptors.insert(0, fakeApi);
  });

  tearDown(() => apiClient.interceptors.remove(fakeApi));

  testWidgets('消息页可进入 AI 广场和名师，返回后保留原消息页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MessagePage()));
    await tester.pumpAndSettle();
    expect(find.text('咨询'), findsOneWidget);
    await tester.tap(find.text('AI 聊天'));
    await tester.pumpAndSettle();
    expect(find.byType(AiSquarePage), findsOneWidget);
    await tester.tap(find.text('AI 名师'));
    await tester.pumpAndSettle();
    expect(find.byType(AiMasterChatPage), findsOneWidget);
    final chat = tester.widget<AiMasterChatPage>(find.byType(AiMasterChatPage));
    expect(chat.scene, 'master');
    expect(chat.enableArchive, isTrue);
    expect(requests, contains('/api/fortune/ai-master-chat/history'));
    expect(requests, isNot(contains('/api/fortune/ai-master-chat/stream')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MessagePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
