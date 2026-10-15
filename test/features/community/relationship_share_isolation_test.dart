import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/post_share.dart';
import 'package:xuanyu/core/utils/profile_share.dart';
import 'package:xuanyu/features/community/share_post_to_users_page.dart';
import 'package:xuanyu/features/community/user_relationship_settings.dart';

void main() {
  late InterceptorsWrapper interceptor;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];

  void success(
    RequestOptions request,
    RequestInterceptorHandler handler,
    Object? data,
  ) {
    handler.resolve(
      Response<dynamic>(
        requestOptions: request,
        statusCode: 200,
        data: {'code': 0, 'data': data},
      ),
    );
  }

  setUp(() {
    calls.clear();
    apiClient.options.headers['Authorization'] = 'relationship-account-a';
    respond = (request, handler) {
      if (request.path == '/api/im/conversations') {
        success(request, handler, {
          'list': [
            {
              'conversationId': 11,
              'type': 'single',
              'title': '好友1',
            },
            {'conversationId': 12, 'type': 'group', 'title': '群聊1'},
          ],
        });
      } else if (request.path ==
          '/api/community/user/me/following-list') {
        success(request, handler, {
          'list': [
            {'userId': 9, 'nickname': '好友9'},
          ],
        });
      } else {
        success(request, handler, <String, dynamic>{});
      }
    };
    interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    apiClient.options.headers.remove('Authorization');
  });

  testWidgets('备注子页切换账号后立即禁用保存且不借用新账号', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UserRemarkPage(userId: 8, initialData: {}),
      ),
    );

    apiClient.options.headers['Authorization'] = 'relationship-account-b';
    apiSessionChanges.value++;
    await tester.pump();

    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    final confirm = tester.widget<TextButton>(
      find.byKey(const ValueKey('remark-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(calls.where((request) => request.method == 'PATCH'), isEmpty);
  });

  testWidgets('备注与特别关心的业务失败不会假保存', (tester) async {
    respond = (request, handler) {
      if (request.method == 'PATCH') {
        handler.resolve(
          Response<dynamic>(
            requestOptions: request,
            statusCode: 200,
            data: {
              'code': 500,
              'message': '服务端拒绝保存',
              'data': {'remark': '错误结果', 'specialCare': true},
            },
          ),
        );
      } else {
        success(request, handler, <String, dynamic>{});
      }
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: UserRemarkPage(userId: 8, initialData: {}),
      ),
    );
    tester
        .widget<TextButton>(find.byKey(const ValueKey('remark-confirm')))
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(UserRemarkPage), findsOneWidget);
    expect(
      calls.map((request) => '${request.method} ${request.path}'),
      contains('PATCH /api/community/user/8/remark'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SpecialCareSettingsPage(
          userId: 8,
          initialData: {'specialCare': false, 'specialCareSound': 'default'},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('special-care-switch')));
    await tester.pump(const Duration(milliseconds: 100));
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('special-care-switch')),
    );
    expect(tile.value, isFalse);
    await tester.pump(const Duration(seconds: 3));
  });

  for (final kind in ['主页', '帖子']) {
    testWidgets('$kind快捷分享等待中切号时固定旧认证且不显示假成功', (tester) async {
      RequestOptions? heldRequest;
      RequestInterceptorHandler? heldHandler;
      final normal = respond;
      respond = (request, handler) {
        if (request.path == '/api/im/conversation/11/message') {
          heldRequest = request;
          heldHandler = handler;
        } else {
          normal(request, handler);
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  if (kind == '主页') {
                    showUserProfileShareSheet(
                      context,
                      const {'userId': 8, 'nickname': '旧主页'},
                    );
                  } else {
                    showPostMoreActionSheet(
                      context,
                      const {
                        'id': 7,
                        'nickname': '旧帖子作者',
                        'content': '旧帖子',
                      },
                    );
                  }
                },
                child: const Text('打开分享'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开分享'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('好友1'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(heldRequest, isNotNull);
      expect(
        heldRequest!.headers['Authorization'],
        'relationship-account-a',
      );

      apiClient.options.headers['Authorization'] = 'relationship-account-b';
      apiSessionChanges.value++;
      await tester.pumpAndSettle();
      success(heldRequest!, heldHandler!, <String, dynamic>{});
      await tester.pump();

      expect(find.textContaining('已分享'), findsNothing);
      expect(find.text('打开分享'), findsOneWidget);
    });
  }

  testWidgets('完整分享选择器切号后旧响应不能继续发进新账号会话', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    final normal = respond;
    respond = (request, handler) {
      if (request.path == '/api/im/conversation/single') {
        heldRequest = request;
        heldHandler = handler;
      } else {
        normal(request, handler);
      }
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SharePostToUsersPage.profile(
            profileItem: {'userId': 8, 'nickname': '旧主页'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('分享(1)'), findsOneWidget);
    await tester.tap(find.text('分享(1)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      calls.map((request) => '${request.method} ${request.path}'),
      contains('POST /api/im/conversation/single'),
    );
    expect(heldRequest, isNotNull);
    expect(
      heldRequest!.headers['Authorization'],
      'relationship-account-a',
    );

    apiClient.options.headers['Authorization'] = 'relationship-account-b';
    apiSessionChanges.value++;
    await tester.pump();
    success(heldRequest!, heldHandler!, {'conversationId': 99});
    await tester.pumpAndSettle();

    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(
      calls.where((request) => request.path == '/api/im/conversation/99/message'),
      isEmpty,
    );
  });

  testWidgets('分享对象业务加载失败有重试，不伪装成空列表', (tester) async {
    final normal = respond;
    respond = (request, handler) {
      if (request.path == '/api/community/user/me/following-list') {
        handler.resolve(
          Response<dynamic>(
            requestOptions: request,
            statusCode: 200,
            data: {'code': 500, 'message': '暂时不可用'},
          ),
        );
      } else {
        normal(request, handler);
      }
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SharePostToUsersPage.profile(
            profileItem: {'userId': 8, 'nickname': '主页'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无关注的人，先关注喜欢的用户吧'), findsNothing);
    expect(find.byKey(const ValueKey('share-target-retry')), findsOneWidget);
  });
}
