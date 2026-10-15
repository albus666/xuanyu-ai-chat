import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/theme/app_colors.dart';
import 'package:xuanyu/features/community/post_entity_text.dart';
import 'package:xuanyu/features/community/post_detail_page.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

void main() {
  testWidgets('评论与回复在360宽度分层清晰且输入区使用中性主色', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 99});

    final post = <String, dynamic>{
      'id': 7,
      'userId': 2,
      'nickname': '发布者',
      'content': '这是一条示例作品。',
      'createdAt': '2026-09-06T09:30:00Z',
      'mediaUrls': <dynamic>[],
      'topics': <dynamic>[],
      'mentions': <dynamic>[],
      'likeCount': 3,
      'commentCount': 2,
      'liked': false,
      'favorited': false,
      'favoriteCount': 1,
      'following': false,
    };
    final comments = <Map<String, dynamic>>[
      {
        'id': 10,
        'parentId': null,
        'userId': 3,
        'nickname': '金陵小锦鲤',
        'content': '主评论内容要清晰展示。',
        'createdAt': '2026-09-06T09:32:00Z',
        'locationCode': '江苏省',
        'likeCount': 8,
        'dislikeCount': 1,
        'liked': false,
        'disliked': false,
        'isFirst': true,
      },
      {
        'id': 11,
        'parentId': 10,
        'userId': 2,
        'nickname': '发布者',
        'content': '回复 @朋友：这是作者的楼中楼回复。',
        'createdAt': '2026-09-06T09:35:00Z',
        'locationCode': '河北省',
        'likeCount': 2,
        'dislikeCount': 0,
        'liked': false,
        'disliked': false,
      },
    ];

    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.path.endsWith('/comments')
            ? {
                'code': 0,
                'data': {'list': comments, 'hasMore': false}
              }
            : {'code': 0, 'data': post};
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: data,
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(MaterialApp(
      home: PostDetailPage(postId: 7, initialItem: post),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('comment-10')), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.text('共 2 条评论'), findsOneWidget);
    expect(find.text('主评论内容要清晰展示。'), findsOneWidget);
    expect(find.text('回复 @朋友：这是作者的楼中楼回复。'), findsOneWidget);
    expect(find.text('作者'), findsOneWidget);
    expect(find.text('首评'), findsOneWidget);
    expect(find.text('江苏'), findsOneWidget);
    expect(find.text('河北'), findsOneWidget);
    expect(find.text('江苏省'), findsNothing);
    expect(find.text('私聊'), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ReferenceActionGlyph &&
            widget.type == ReferenceActionIconType.dislike,
      ),
      findsNWidgets(3),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, 62);
    final postBody = tester.widget<ExpandablePostEntityText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExpandablePostEntityText && widget.content == '这是一条示例作品。',
      ),
    );
    expect(postBody.style.fontSize, 15);
    final commentBody = tester.widget<ExpandablePostEntityText>(
      find.byKey(const ValueKey('comment-body-10')),
    );
    expect(commentBody.style.fontSize, 14);
    final replyBody = tester.widget<ExpandablePostEntityText>(
      find.byKey(const ValueKey('reply-body-11')),
    );
    expect(replyBody.mentionColor, AppColors.communityText);

    final privateChatIcon = tester.widget<ReferenceActionGlyph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ReferenceActionGlyph &&
            widget.type == ReferenceActionIconType.privateChat,
      ),
    );
    expect(privateChatIcon.size, 23);

    final inputFinder = find.byKey(const ValueKey<String>('comment-input'));
    final compactHeight = tester.getSize(inputFinder).height;
    await tester.tap(
      find.byKey(const ValueKey<String>('comment-text-field')),
    );
    await tester.pump();
    expect(tester.getSize(inputFinder).height, compactHeight);
    expect(compactHeight, 40);
    final sendButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('send-comment')),
    );
    expect(
      sendButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.primaryDark,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('send-comment'))).dx,
      greaterThan(tester.getTopLeft(inputFinder).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击发送时不会因收起输入框而丢掉评论', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 99});

    final post = <String, dynamic>{
      'id': 7,
      'userId': 2,
      'nickname': '发布者',
      'content': '这是一条示例作品。',
      'createdAt': '2026-09-06T09:30:00Z',
      'mediaUrls': <dynamic>[],
      'topics': <dynamic>[],
      'mentions': <dynamic>[],
      'likeCount': 0,
      'commentCount': 0,
      'liked': false,
      'favorited': false,
      'favoriteCount': 0,
      'following': false,
    };
    var commentPosted = false;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'POST' && options.path.endsWith('/comment')) {
          commentPosted = true;
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'code': 0,
              'data': {'id': 21, 'createdAt': '2026-09-22T13:00:00Z'}
            },
          ));
          return;
        }
        final data = options.path.endsWith('/comments')
            ? {
                'code': 0,
                'data': {'list': <dynamic>[], 'hasMore': false}
              }
            : {'code': 0, 'data': post};
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: data,
        ));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
    addTearDown(() => apiClient.interceptors.remove(interceptor));

    await tester.pumpWidget(MaterialApp(
      home: PostDetailPage(postId: 7, initialItem: post),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('comment-text-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('comment-text-field')),
      '这条评论应该发出去',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('send-comment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(commentPosted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
