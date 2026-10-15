import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/community/user_profile_page.dart';
import 'package:xuanyu/features/community/post_card.dart';
import 'package:xuanyu/features/profile/collection_page.dart';
import 'package:xuanyu/features/profile/profile_page.dart';

Map<String, dynamic> post(int id, String content) => {
      'id': id,
      'userId': 8,
      'nickname': '测试用户',
      'content': content,
      'mediaUrls': [],
      'topics': [],
      'mentions': [],
      'likeCount': 0,
    };

void reply(RequestOptions request, RequestInterceptorHandler handler,
        Object? data) =>
    handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {'code': 0, 'data': data}));

void main() {
  late InterceptorsWrapper fake;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final calls = <RequestOptions>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    calls.clear();
    apiClient.options.headers['Authorization'] = 'test-profile-session';
    respond = (request, handler) => reply(
        request,
        handler,
        request.path.endsWith('/profile') || request.path == '/api/auth/me'
            ? {
                'userId': request.path == '/api/auth/me' ? 7 : 8,
                'nickname': '测试用户',
                'locationCode': '杭州',
                'following': false
              }
            : {'list': [], 'hasMore': false});
    fake = InterceptorsWrapper(onRequest: (r, h) {
      calls.add(r);
      respond(r, h);
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() {
    apiClient.interceptors.remove(fake);
    apiClient.options.headers.remove('Authorization');
  });

  testWidgets('资料网络错误可重试，不误报用户不存在', (tester) async {
    var attempts = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/profile') && attempts++ == 0) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    expect(find.text('用户不存在'), findsNothing);
    expect(find.text('重试加载资料'), findsOneWidget);
    await tester.tap(find.text('重试加载资料'));
    await tester.pumpAndSettle();
    expect(find.text('测试用户'), findsWidgets);
  });

  testWidgets('作品失败显示重试，不伪装成暂无作品', (tester) async {
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/posts')) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    expect(find.text('暂无作品发布'), findsNothing);
    expect(find.text('重试加载'), findsOneWidget);
  });

  testWidgets('刷新个人主页后迟到的旧列表不能混进新作品', (tester) async {
    RequestOptions? oldRequest;
    RequestInterceptorHandler? oldHandler;
    var loads = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/posts')) {
        if (loads++ == 0) {
          oldRequest = r;
          oldHandler = h;
          return;
        }
        reply(r, h, {
          'list': [post(2, '刷新后的作品')],
          'hasMore': false
        });
      } else {
        normal(r, h);
      }
    };
    final key = GlobalKey<ProfilePageState>();
    await tester.pumpWidget(MaterialApp(home: ProfilePage(key: key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    key.currentState!.refreshUser();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    reply(oldRequest!, oldHandler!, {
      'list': [post(1, '过期的旧作品')],
      'hasMore': false
    });
    await tester.pumpAndSettle();
    expect(find.text('刷新后的作品'), findsWidgets);
    expect(find.text('过期的旧作品'), findsNothing);
  });

  testWidgets('关注连续点击只发送一次，成功才改变关注状态', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/follow')) {
        heldRequest = r;
        heldHandler = h;
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    final follow = find.text('关注').last;
    await tester.tap(follow);
    await tester.tap(follow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls.where((r) => r.path.endsWith('/follow')).length, 1);
    expect(find.text('已关注'), findsNothing);
    reply(heldRequest!, heldHandler!, {'following': true, 'mutual': false});
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
  });

  for (final networkFailure in [true, false]) {
    testWidgets('关注失败保留未关注状态并提示：网络错误=$networkFailure', (tester) async {
      final normal = respond;
      respond = (r, h) {
        if (r.path.endsWith('/follow')) {
          if (networkFailure) {
            h.reject(DioException(
                requestOptions: r, type: DioExceptionType.connectionError));
          } else {
            h.resolve(Response(requestOptions: r, data: {
              'code': 403,
              'message': '无法关注',
              'data': {'following': true}
            }));
          }
        } else {
          normal(r, h);
        }
      };
      await tester
          .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关注').last);
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsNothing);
      expect(find.text('关注失败，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('关注前未完成的资料刷新不能覆盖关注结果', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    var profiles = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/profile') && profiles++ > 0) {
        heldRequest = r;
        heldHandler = h;
      } else if (r.path.endsWith('/follow')) {
        reply(r, h, {'following': true});
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新主页'));
    await tester.pump();
    await tester.tap(find.text('关注').last);
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
    reply(heldRequest!, heldHandler!, {
      'userId': 8,
      'nickname': '测试用户',
      'locationCode': '杭州',
      'following': false
    });
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
  });

  for (final blockSucceeds in [false, true]) {
    testWidgets('拉黑仅在接口确认成功后离开或清除主页：成功=$blockSucceeds', (tester) async {
      final normal = respond;
      respond = (r, h) {
        if (r.path.endsWith('/block')) {
          h.resolve(Response(requestOptions: r, data: {
            'code': blockSucceeds ? 0 : 500,
            'data': {'blocked': true},
          }));
        } else {
          normal(r, h);
        }
      };
      await tester
          .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉黑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.path.endsWith('/block')).length, 1);
      if (blockSucceeds) {
        expect(find.text('测试用户'), findsNothing);
        expect(find.text('暂时无法查看该用户'), findsOneWidget);
      } else {
        expect(find.text('测试用户'), findsWidgets);
        expect(find.text('拉黑失败，请重试'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('拉黑确认框期间切号，不可用新账号执行旧操作', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('拉黑'));
    await tester.pumpAndSettle();
    apiClient.options.headers['Authorization'] = 'new-profile-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path.endsWith('/block')), isEmpty);
  });

  testWidgets('点赞等待期间刷新删除原作品，失败不影响替换后的作品', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    var loads = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/posts')) {
        reply(r, h, {
          'list': [loads++ == 0 ? post(1, '旧作品') : post(2, '新作品')],
          'hasMore': false
        });
      } else if (r.path.endsWith('/like')) {
        heldRequest = r;
        heldHandler = h;
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    tester.widget<PostCard>(find.byType(PostCard).first).onLike!(1);
    await tester.pump();
    await tester.tap(find.byTooltip('刷新主页'));
    await tester.pumpAndSettle();
    heldHandler!.reject(DioException(
        requestOptions: heldRequest!, type: DioExceptionType.connectionError));
    await tester.pumpAndSettle();
    expect(find.text('旧作品'), findsNothing);
    expect(find.text('新作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('本人资料加载失败有重试入口，不一直转圈', (tester) async {
    var attempt = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path == '/api/auth/me' && attempt++ == 0) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        normal(r, h);
      }
    };
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();
    expect(find.text('重试加载资料'), findsOneWidget);
    await tester.tap(find.text('重试加载资料'));
    await tester.pumpAndSettle();
    expect(find.text('测试用户'), findsWidgets);
  });

  testWidgets('独立收藏页失败可重试，切号立即清除旧收藏', (tester) async {
    var attempt = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/favorites')) {
        if (attempt++ == 0) {
          h.reject(DioException(
              requestOptions: r, type: DioExceptionType.connectionError));
        } else {
          reply(r, h, {
            'list': [post(7, '私有收藏')],
            'hasMore': false
          });
        }
      } else {
        normal(r, h);
      }
    };
    await tester.pumpWidget(const MaterialApp(home: CollectionPage()));
    await tester.pumpAndSettle();
    expect(find.text('暂无收藏'), findsNothing);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(find.text('私有收藏'), findsOneWidget);
    apiClient.options.headers.remove('Authorization');
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('私有收藏'), findsNothing);
  });

  for (final width in [360.0, 430.0]) {
    testWidgets('主页标签栏高度与绘制一致，无布局异常：宽度$width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester
          .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('私聊重复点击只创建一次会话，切号后旧响应不能打开聊天', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    final normal = respond;
    respond = (r, h) {
      if (r.path == '/api/im/conversation/single') {
        heldRequest = r;
        heldHandler = h;
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私聊'));
    await tester.tap(find.text('私聊'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
        calls.where((r) => r.path == '/api/im/conversation/single').length, 1);
    apiClient.options.headers['Authorization'] = 'changed-chat-test-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    reply(heldRequest!, heldHandler!, {'conversationId': 99, 'title': '旧账号会话'});
    await tester.pumpAndSettle();
    expect(find.text('旧账号会话'), findsNothing);
    expect(find.text('私聊'), findsOneWidget);
    expect(calls.where((r) => r.path.contains('/messages')), isEmpty);
  });

  testWidgets('私聊业务失败不给假成功且允许重试', (tester) async {
    final normal = respond;
    respond = (r, h) {
      if (r.path == '/api/im/conversation/single') {
        h.resolve(Response(requestOptions: r, data: {
          'code': 500,
          'data': {'conversationId': 99}
        }));
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私聊'));
    await tester.pumpAndSettle();
    expect(find.text('无法发起聊天，请重试'), findsOneWidget);
    expect(find.text('私聊'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('刷新本人主页保留收藏标签并更新该列表', (tester) async {
    var version = 0;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/favorites')) {
        reply(r, h, {
          'list': [post(++version, '收藏版本$version')],
          'hasMore': false
        });
      } else {
        normal(r, h);
      }
    };
    final key = GlobalKey<ProfilePageState>();
    await tester.pumpWidget(MaterialApp(home: ProfilePage(key: key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏').first);
    await tester.pumpAndSettle();
    expect(find.text('收藏版本1'), findsWidgets);
    key.currentState!.refreshUser();
    await tester.pumpAndSettle();
    expect(find.text('收藏版本1'), findsNothing);
    expect(find.text('收藏版本2'), findsWidgets);
    expect(version, 2);
  });

  testWidgets('取消收藏后立即移除并重查第一页，避免偏移分页漏项', (tester) async {
    var removed = false;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/favorites')) {
        reply(r, h, {
          'list': removed
              ? [post(2, '剩余收藏'), post(3, '补入收藏')]
              : [post(1, '待取消收藏'), post(2, '剩余收藏')],
          'hasMore': !removed
        });
      } else if (r.path.endsWith('/favorite')) {
        removed = true;
        reply(r, h, {'favorited': false});
      } else {
        normal(r, h);
      }
    };
    await tester.pumpWidget(const MaterialApp(home: CollectionPage()));
    await tester.pumpAndSettle();
    tester.widget<PostCard>(find.byType(PostCard).first).onFavorite!(1);
    await tester.pumpAndSettle();
    expect(find.text('待取消收藏'), findsNothing);
    expect(find.text('剩余收藏'), findsOneWidget);
    expect(find.text('补入收藏'), findsOneWidget);
    expect(
        calls
            .where((r) => r.path.endsWith('/favorites'))
            .map((r) => r.queryParameters['page']),
        [1, 1]);
  });

  testWidgets('他人主页收藏不可查看，不请求自己的收藏充当对方收藏', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('对方的收藏仅自己可见'), findsOneWidget);
    expect(calls.where((r) => r.path.endsWith('/favorites')), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('本人归属地补全等待中切号，不写入新账号', (tester) async {
    RequestOptions? heldRequest;
    RequestInterceptorHandler? heldHandler;
    final normal = respond;
    respond = (r, h) {
      if (r.path.endsWith('/profile')) {
        reply(r, h, {'userId': 7, 'nickname': '本人主页', 'locationCode': ''});
      } else if (r.path == '/api/config/ipLocation') {
        heldRequest = r;
        heldHandler = h;
      } else {
        normal(r, h);
      }
    };
    await tester
        .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 7)));
    await tester.pumpAndSettle();
    expect(heldRequest, isNotNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 9);
    apiClient.options.headers['Authorization'] = 'new-location-session';
    apiSessionChanges.value++;
    await tester.pumpAndSettle();
    reply(heldRequest!, heldHandler!, {'location': '杭州'});
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.path == '/api/auth/location'), isEmpty);
  });

  for (final status in [403, 404]) {
    testWidgets('真正的权限限制与用户不存在分开提示：$status', (tester) async {
      final normal = respond;
      respond = (r, h) {
        if (r.path.endsWith('/profile')) {
          h.reject(DioException(
              requestOptions: r,
              type: DioExceptionType.badResponse,
              response: Response(
                  requestOptions: r,
                  statusCode: status,
                  data: {'code': status})));
        } else {
          normal(r, h);
        }
      };
      await tester
          .pumpWidget(const MaterialApp(home: UserProfilePage(userId: 8)));
      await tester.pumpAndSettle();
      expect(find.text(status == 403 ? '暂时无法查看该用户' : '用户不存在'), findsOneWidget);
      expect(find.text('关注'), findsNothing);
      expect(find.text('私聊'), findsNothing);
    });
  }
}
