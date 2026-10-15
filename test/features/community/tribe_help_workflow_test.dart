import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/features/community/create_post_page.dart';
import 'package:xuanyu/features/community/post_card.dart';

void main() {
  testWidgets('发布作品不再展示请求部落协助入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: CreatePostPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('post-setting-tribe-help')), findsNothing);
    expect(find.text('请求部落协助'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('部落求助卡片显示目标部落和已解决状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: {
              'id': 9,
              'userId': 3,
              'nickname': '求助者',
              'content': '请帮忙核对线索',
              'helpRequest': {
                'requested': true,
                'teamId': 8,
                'teamName': '寻宠信息部落',
                'status': 'resolved',
              },
            },
            integrated: true,
            showActionRow: false,
          ),
        ),
      ),
    );

    expect(find.text('寻宠信息部落已协助解决'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('部落标志紧跟在社区帖子昵称后面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: {
              'id': 10,
              'userId': 4,
              'nickname': '向日葵',
              'teamTitle': '寻宠',
              'content': '测试内容',
              'createdAt': '2026-09-27T07:20:00Z',
            },
            showActionRow: false,
            showMoreMenu: false,
          ),
        ),
      ),
    );

    final nickname = find.text('向日葵');
    final tribe = find.text('寻宠');
    expect(nickname, findsOneWidget);
    expect(tribe, findsOneWidget);

    final nicknameRect = tester.getRect(nickname);
    final tribeRect = tester.getRect(tribe);
    expect(tribeRect.left, greaterThan(nicknameRect.right));
    expect(tribeRect.left - nicknameRect.right, lessThan(16));
    expect((tribeRect.center.dy - nicknameRect.center.dy).abs(), lessThan(3));
    expect(tester.takeException(), isNull);
  });
}
