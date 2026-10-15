import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/post_publish_settings_page.dart';

void main() {
  test('发布设置完整保存可见范围、互动权限和排除名单', () {
    const original = PostPublishSettings(
      visibility: 5,
      disableDownloadCopy: true,
      disableForward: true,
      commentPermission: 'followers',
      originalDeclaration: true,
      aiGenerated: true,
      excludedUserIds: {7, 9},
    );

    final restored = PostPublishSettings.fromJson(original.toJson());

    expect(restored.visibility, 5);
    expect(restored.visibilityLabel, '仅话题广场可见');
    expect(restored.disableDownloadCopy, isTrue);
    expect(restored.disableForward, isTrue);
    expect(restored.commentPermission, 'followers');
    expect(restored.commentPermissionLabel, '关注我的人可评');
    expect(restored.allowComment, isTrue);
    expect(restored.originalDeclaration, isTrue);
    expect(restored.aiGenerated, isTrue);
    expect(restored.excludedUserIds, {7, 9});
  });

  test('关闭评论会同步为不可评论且异常可见范围会被纠正', () {
    final restored = PostPublishSettings.fromJson({
      'visibility': 99,
      'commentPermission': 'none',
    });

    expect(restored.visibility, 1);
    expect(restored.allowComment, isFalse);
    expect(restored.commentPermissionLabel, '所有人都不可评论');
  });

  testWidgets('不给Ta看移除密友分类并保留其余三类', (tester) async {
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': {'list': <dynamic>[]},
        },
      )),
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(const MaterialApp(
      home: PostAudienceExclusionPage(initialSelection: <int>{}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('最近聊天'), findsOneWidget);
    expect(find.text('我关注的'), findsOneWidget);
    expect(find.text('关注我的'), findsOneWidget);
    expect(find.text('密友'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
