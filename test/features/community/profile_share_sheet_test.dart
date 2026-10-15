import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/profile_share.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

void main() {
  testWidgets('别人主页三点面板紧凑展示六个分享渠道和五项关系功能', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response<dynamic>(
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
        ),
      ),
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUserProfileShareSheet(
                context,
                {'userId': 8, 'nickname': '玄遇'},
                onRemark: () {},
                onStealth: () {},
                onQuietFollow: () {},
                onSpecialCare: () {},
                onBlock: () {},
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('分享至好友'), findsOneWidget);
    for (final label in ['微信', '朋友圈', 'QQ', 'QQ空间', '微博', '更多']) {
      expect(
        find.byKey(ValueKey('profile-share-channel-$label')),
        findsOneWidget,
      );
    }
    expect(find.byType(ReferenceShareBrandIcon), findsNWidgets(5));
    expect(find.byType(ReferenceShareMoreIcon), findsOneWidget);
    final weChat = tester.widget<ReferenceShareBrandIcon>(find.byKey(
      const ValueKey('profile-share-channel-icon-微信'),
    ));
    expect(weChat.diameter, 48);
    for (final label in ['备注', '对Ta隐身', '悄悄关注', '特别关心', '拉黑']) {
      expect(find.byKey(ValueKey('profile-action-$label')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
