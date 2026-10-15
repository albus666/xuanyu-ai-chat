import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/post_share.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

void main() {
  testWidgets('帖子分享面板紧凑展示六个分享渠道和五项内容操作', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'data': {
              'list': List.generate(
                5,
                (index) => {
                  'conversationId': index + 1,
                  'type': 'single',
                  'title': '好友${index + 1}',
                },
              ),
            },
          },
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPostMoreActionSheet(
              context,
              const {'id': 7, 'nickname': '示例用户', 'content': '示例内容'},
              following: true,
              onPrivateChat: () {},
              onToggleFollow: () {},
              onNotInterested: () {},
              onReport: () {},
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('分享至好友'), findsOneWidget);
    for (final label in ['微信', '朋友圈', 'QQ', 'QQ空间', '微博', '更多']) {
      expect(find.byKey(ValueKey('share-channel-$label')), findsOneWidget);
    }
    expect(find.byType(ReferenceShareBrandIcon), findsNWidgets(5));
    expect(find.byType(ReferenceShareMoreIcon), findsOneWidget);
    for (final label in ['私聊', '生成分享图', '取消关注', '不喜欢', '举报']) {
      expect(find.byKey(ValueKey('post-action-$label')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('post-action-复制链接')), findsNothing);

    const expectedBrands = {
      '微信': ReferenceShareBrand.weChat,
      '朋友圈': ReferenceShareBrand.moments,
      'QQ': ReferenceShareBrand.qq,
      'QQ空间': ReferenceShareBrand.qzone,
      '微博': ReferenceShareBrand.weibo,
    };
    for (final entry in expectedBrands.entries) {
      final icon = tester.widget<ReferenceShareBrandIcon>(
        find.byKey(ValueKey('share-channel-icon-${entry.key}')),
      );
      expect(icon.brand, entry.value);
      expect(icon.diameter, 48);
    }
    final privateChatCircle = tester.widget<Container>(
      find.byKey(const ValueKey('post-action-icon-私聊')),
    );
    expect(privateChatCircle.constraints?.maxWidth, 50);
    expect(privateChatCircle.constraints?.maxHeight, 50);
    expect(find.byType(ReferenceActionCircleIcon), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('作者禁止转发后隐藏好友和外部分享入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPostMoreActionSheet(
              context,
              const {
                'id': 8,
                'nickname': '示例用户',
                'content': '示例内容',
                'disableForward': true,
              },
              onPrivateChat: () {},
              onNotInterested: () {},
              onReport: () {},
            ),
            child: const Text('打开限制面板'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开限制面板'));
    await tester.pump();

    expect(find.text('更多操作'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-channel-微信')), findsNothing);
    expect(find.byKey(const ValueKey('post-action-生成分享图')), findsNothing);
    expect(find.byKey(const ValueKey('post-action-私聊')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-action-不喜欢')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-action-举报')), findsOneWidget);
  });
}
