import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/features/community/create_post_page.dart';
import 'package:xuanyu/features/community/post_draft_store.dart';
import 'package:xuanyu/features/community/post_publish_task.dart';

// 仅下方显式指向 127.0.0.1 的上传用例使用真实 HttpClient。
class _LoopbackHttpOverrides extends HttpOverrides {}

Map<String, dynamic> draft(String content,
        {String? video, List<String> images = const []}) =>
    {
      'id': PostDraftStore.newId(),
      'content': content,
      'images': images,
      'video': video,
      'settings': {'visibility': 2, 'commentPermission': 'none'},
      'topics': <String, int>{},
      'mentions': <String, int>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporary;
  late InterceptorsWrapper fake;
  late List<RequestOptions> requests;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserId: 7,
      AppConstants.keyPostPublishNotificationEnabled: false,
    });
    apiClient.options.headers['Authorization'] = 'test-account-a';
    apiSessionChanges.value++;
    temporary = Directory.systemTemp.createTempSync('xuanyu-draft-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      provider,
      (_) async => temporary.path,
    );
    requests = [];
    respond = (request, handler) => handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'code': 0,
            'data': request.path == '/api/community/post'
                ? {'id': 11}
                : {'list': []}
          },
        ));
    fake = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      respond(request, handler);
    });
    apiClient.interceptors.insert(0, fake);
  });

  tearDown(() async {
    await PostDraftStore(7).pending(); // 等待异步 dispose 保存完成。
    apiClient.interceptors.remove(fake);
    apiClient.options.headers.remove('Authorization');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    dismissAllAppToasts();
    temporary.deleteSync(recursive: true); // 仅本测试创建的临时夹具。
  });

  Future<void> mountComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CreatePostPage())),
                  child: const Text('新建'),
                )))));
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
  }

  Future<void> leave(WidgetTester tester, {bool save = true}) async {
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    if (find.text('保存草稿').evaluate().isNotEmpty) {
      await tester.tap(find.text(save ? '保存草稿' : '不保存草稿'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('保存的草稿不能串账号，返回原账号仍能恢复', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await mountComposer(tester);
    await tester.enterText(find.byType(TextField), '账号甲的私密草稿');
    await leave(tester);
    await prefs.setInt(AppConstants.keyUserId, 8);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(find.byType(TextField), '账号乙的编辑稿');
    await leave(tester);
    await prefs.setInt(AppConstants.keyUserId, 7);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '账号甲的私密草稿');
    await leave(tester);
    expect((await PostDraftStore(8).active())!['content'], '账号乙的编辑稿');
  });

  testWidgets('旧版无归属草稿不泄露给当前账号且不删除原始内容', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('community_post_draft_content', '未知账号的旧草稿');
    await mountComposer(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await leave(tester);
    expect(prefs.getString('community_post_draft_content'), '未知账号的旧草稿');
  });

  test('图片和纯视频草稿使用持久副本，临时原文件消失仍可恢复', () async {
    for (final extension in ['jpg', 'mp4']) {
      final original = File('${temporary.path}/picked.$extension');
      await original.writeAsBytes([1, 2, 3, extension.length]);
      final store = PostDraftStore(7);
      final saved = draft('',
          video: extension == 'mp4' ? original.path : null,
          images: extension == 'jpg' ? [original.path] : []);
      await store.save(saved);
      await original.delete();
      final restored = await store.active();
      final path = extension == 'jpg'
          ? (restored!['images'] as List).single as String
          : restored!['video'] as String;
      expect(path, contains('/post_drafts/7/media/'));
      expect(path, endsWith('.$extension'));
      expect(await File(path).readAsBytes(), [1, 2, 3, extension.length]);
    }
  });

  test('已录音草稿保留时长和音频副本', () async {
    final audio =
        await File('${temporary.path}/sound.m4a').writeAsBytes([9, 8]);
    final saved = draft('')..addAll({'audio': audio.path, 'audioSeconds': 27});
    await PostDraftStore(7).save(saved);
    final restored = (await PostDraftStore(7).active())!;
    expect(restored['audioSeconds'], 27);
    expect(await File(restored['audio'] as String).readAsBytes(), [9, 8]);
  });

  test('缺失附件不会降级成纯文字发布并保留恢复记录', () async {
    final store = PostDraftStore(7);
    await PostPublishTask.run(PostPublishTask(
        store: store, draft: draft('必须带视频', video: '/missing-test-video.mp4')));
    expect(requests.where((r) => r.path == '/api/community/post'), isEmpty);
    final pending = (await store.pending()).single;
    expect(pending['status'], 'failed');
    expect(pending['error'], contains('附件已失效'));
    expect(pending['video'], '/missing-test-video.mp4');
  });

  test('创建任务后切号：不发帖、不跨账号保存、不保存认证信息', () async {
    final store = PostDraftStore(7);
    final task = PostPublishTask(store: store, draft: draft('甲的内容'));
    apiClient.options.headers['Authorization'] = 'test-account-b';
    apiSessionChanges.value++;
    await PostPublishTask.run(task);
    expect(requests, isEmpty);
    expect((await store.pending()).single['content'], '甲的内容');
    expect(await PostDraftStore(8).pending(), isEmpty);
    final raw =
        (await SharedPreferences.getInstance()).getString(store.storageKey)!;
    expect(raw, isNot(contains('test-account-')));
    expect(raw, isNot(contains('Authorization')));
  });

  test('获取上传链接中切号：不继续上传确认和发帖', () async {
    final image =
        await File('${temporary.path}/image.jpg').writeAsBytes([1, 2]);
    respond = (request, handler) {
      apiClient.options.headers['Authorization'] = 'test-account-b';
      apiSessionChanges.value++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'uploadUrl': 'http://invalid.test/no-network',
          'url': 'https://invalid.test/a',
          'objectKey': 'test'
        }
      }));
    };
    final store = PostDraftStore(7);
    await PostPublishTask.run(PostPublishTask(
        store: store, draft: draft('图片', images: [image.path])));
    expect(requests.map((r) => r.path), ['/api/config/presign-upload']);
    expect(requests.single.headers['Authorization'], 'test-account-a');
    expect((await store.pending()).single['status'], 'failed');
  });

  test('发帖请求中切号：旧账号成功只清理自己的任务，不清理新草稿', () async {
    final store = PostDraftStore(7);
    final newer = draft('甲后来写的稿');
    await store.save(newer);
    await PostDraftStore(8).save(draft('乙正在写的稿'));
    respond = (request, handler) {
      expect(request.headers['Authorization'], 'test-account-a');
      apiClient.options.headers['Authorization'] = 'test-account-b';
      apiSessionChanges.value++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {'id': 21}
      }));
    };
    await PostPublishTask.run(
        PostPublishTask(store: store, draft: draft('正在提交的旧稿')));
    expect(await store.pending(), isEmpty);
    expect((await store.active())!['content'], '甲后来写的稿');
    expect((await PostDraftStore(8).active())!['content'], '乙正在写的稿');
  });

  test('同一任务连续调用只发一次，成功后不能重复调用重发', () async {
    final task =
        PostPublishTask(store: PostDraftStore(7), draft: draft('只发一次'));
    await Future.wait([PostPublishTask.run(task), PostPublishTask.run(task)]);
    await PostPublishTask.run(task);
    expect(requests.where((r) => r.path == '/api/community/post').length, 1);
    expect(await PostDraftStore(7).pending(), isEmpty);
  });

  test('超时结果不明保留 uncertain，后续不自动重发', () async {
    respond = (request, handler) => handler.reject(DioException(
        requestOptions: request, type: DioExceptionType.receiveTimeout));
    final task = PostPublishTask(store: PostDraftStore(7), draft: draft('超时稿'));
    await PostPublishTask.run(task);
    await PostPublishTask.run(task);
    expect(requests.length, 1);
    final pending = (await PostDraftStore(7).pending()).single;
    expect(pending['status'], 'uncertain');
    expect(pending['error'], contains('先查看自己的作品'));
  });

  test('HTTP 拒绝和业务失败不误报成功，多个失败记录互不覆盖', () async {
    var count = 0;
    respond = (request, handler) {
      if (count++ == 0) {
        handler.reject(DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: request, statusCode: 403)));
      } else {
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'code': 1, 'message': '拒绝'}));
      }
    };
    final store = PostDraftStore(7);
    await PostPublishTask.run(
        PostPublishTask(store: store, draft: draft('失败一')));
    await PostPublishTask.run(
        PostPublishTask(store: store, draft: draft('失败二')));
    expect(
        (await store.pending()).map((p) => p['status']), ['failed', 'failed']);
  });

  test('恢复未完成记录前另存当前编辑稿，权限/位置/实体不丢', () async {
    final store = PostDraftStore(7);
    final failed = draft('旧稿 #话题 @好友')
      ..addAll({
        'topics': {'话题': 9},
        'mentions': {'好友': 18},
        'location': '杭州',
        'component': {'key': 'room', 'title': '房间', 'referenceId': 3},
      });
    await store.stage(failed);
    await store.mark(failed['id'] as String, 'failed');
    final current = draft('新稿');
    final recovered = await store.recover(failed['id'] as String, current);
    expect(recovered['content'], failed['content']);
    expect(
        recovered['settings'], {'visibility': 2, 'commentPermission': 'none'});
    expect(recovered['topics'], {'话题': 9});
    expect(recovered['mentions'], {'好友': 18});
    expect(recovered['location'], '杭州');
    expect(recovered['component']['referenceId'], 3);
    expect((await store.pending()).single['content'], '新稿');
    expect((await store.active())!['id'], failed['id']);
  });

  test('快照捕获同步，调用后修改原对象不影响落盘', () async {
    final store = PostDraftStore(7);
    final snapshot = draft('捕获时内容');
    final writing = store.save(snapshot);
    snapshot['content'] = '后来改的';
    await writing;
    expect((await store.active())!['content'], '捕获时内容');
  });

  test('损坏草稿不会按空白覆盖', () async {
    final store = PostDraftStore(7);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(store.storageKey, '{broken');
    await expectLater(store.save(draft('新内容')), throwsFormatException);
    expect(prefs.getString(store.storageKey), '{broken');
    // 恢复测试夹具，避免 tearDown 读取损坏数据。
    await prefs.remove(store.storageKey);
  });

  test('成功/丢弃只回收不再引用的私有副本，保留原文件及其他账号', () async {
    final original =
        await File('${temporary.path}/source.jpg').writeAsBytes([5, 6]);
    final a = PostDraftStore(7);
    final b = PostDraftStore(8);
    final first = draft('', images: [original.path]);
    await a.save(first);
    await b.save(draft('', images: [original.path]));
    final aPath = ((await a.active())!['images'] as List).single as String;
    final bPath = ((await b.active())!['images'] as List).single as String;
    await a.stage(first);
    await a.save(draft('仍在编辑', images: [aPath]));
    await a.complete(first['id'] as String);
    expect(await File(aPath).exists(), isTrue);
    final active = (await a.active())!;
    await a.discard(active['id'] as String);
    expect(await File(aPath).exists(), isFalse);
    expect(await File(bPath).exists(), isTrue);
    expect(await original.exists(), isTrue);
  });

  testWidgets('发布页能恢复失败内容，不自动发帖，并另存当前编辑稿', (tester) async {
    final store = PostDraftStore(7);
    final failed = draft('之前发布失败的内容');
    await store.stage(failed);
    await store.mark(failed['id'] as String, 'failed');
    await mountComposer(tester);
    await tester.enterText(find.byType(TextField), '当前没有发的内容');
    await tester.tap(find.text('未完成发布（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('之前发布失败的内容'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会被覆盖'), findsOneWidget);
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '之前发布失败的内容');
    expect((await store.pending()).single['content'], '当前没有发的内容');
    expect(requests.where((r) => r.path == '/api/community/post'), isEmpty);
    await leave(tester);
  });

  testWidgets('结果不明恢复前要求确认，不自动重发', (tester) async {
    final store = PostDraftStore(7);
    final uncertain = draft('结果不明的内容');
    await store.stage(uncertain);
    await store.mark(uncertain['id'] as String, 'uncertain');
    await mountComposer(tester);
    await tester.tap(find.text('未完成发布（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结果不明的内容'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请先查看个人主页作品'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect((await store.pending()).length, 1);
    await leave(tester);
  });

  testWidgets('关闭通知也继续发布，连续点击不重复提交', (tester) async {
    RequestInterceptorHandler? waiting;
    RequestOptions? checked;
    respond = (request, handler) {
      if (request.path == '/api/community/post') {
        checked = request;
        waiting = handler;
      } else {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data':
              request.path == '/api/community/post' ? {'id': 55} : {'list': []}
        }));
      }
    };
    await mountComposer(tester);
    await tester.enterText(find.byType(TextField), '通知不阻断发布');
    await tester.pump();
    final publishPosition = tester.getCenter(find.text('发布'));
    await tester.tap(find.text('发布'));
    await tester.pump();
    for (var attempt = 0; attempt < 20 && waiting == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(waiting, isNotNull);
    await tester.tapAt(publishPosition);
    await tester.pump();
    waiting!.resolve(Response(requestOptions: checked!, statusCode: 200, data: {
      'code': 0,
      'data': {'id': 55}
    }));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.path == '/api/community/post').length, 1);
    expect(find.byType(CreatePostPage), findsNothing);
    expect(await PostDraftStore(7).pending(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('强制离开编辑页仍保存快照，不读已销毁的 Controller', (tester) async {
    await mountComposer(tester);
    await tester.enterText(find.byType(TextField), '离开时保留');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect((await PostDraftStore(7).active())!['content'], '离开时保留');
    expect(tester.takeException(), isNull);
  });

  test('通知插件不可用不把已经成功的作品判为失败', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyPostPublishNotificationEnabled, true);
    final store = PostDraftStore(7);
    await PostPublishTask.run(
        PostPublishTask(store: store, draft: draft('通知失败不重复发布')));
    expect(requests.length, 1);
    expect(await store.pending(), isEmpty);
  });

  for (final failUpload in [false, true]) {
    test('本机 HTTP 上传实测：上传失败=$failUpload，附件完整且失败不发帖', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final uploaded = Completer<List<int>>();
      server.listen((request) async {
        final bytes = await request
            .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
        request.response.statusCode = failUpload ? 500 : 200;
        await request.response.close();
        uploaded.complete(bytes);
      });
      final media =
          await File('${temporary.path}/upload.jpg').writeAsBytes([11, 12, 13]);
      respond = (request, handler) {
        final data = request.path == '/api/config/presign-upload'
            ? {
                'uploadUrl': 'http://127.0.0.1:${server.port}/upload',
                'url': 'https://invalid.test/test-image',
                'objectKey': 'test-image'
              }
            : request.path == '/api/config/confirm-upload'
                ? {
                    'url': 'https://invalid.test/test-image',
                    'reviewId': 987,
                    'reviewStatus': 'approved'
                  }
                : request.path == '/api/config/media-review/987'
                    ? {
                        'reviewId': 987,
                        'reviewStatus': 'approved',
                        'url': 'https://invalid.test/test-image'
                      }
                    : {'id': 66};
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'code': 0, 'data': data}));
      };
      final store = PostDraftStore(7);
      await HttpOverrides.runWithHttpOverrides(
          () => PostPublishTask.run(PostPublishTask(
              store: store, draft: draft('带图', images: [media.path]))),
          _LoopbackHttpOverrides());
      expect(await uploaded.future.timeout(const Duration(seconds: 5)),
          [11, 12, 13]);
      if (failUpload) {
        expect(requests.map((r) => r.path), ['/api/config/presign-upload']);
        expect((await store.pending()).single['status'], 'failed');
      } else {
        expect(requests.map((r) => r.path), [
          '/api/config/presign-upload',
          '/api/config/confirm-upload',
          '/api/community/post'
        ]);
        expect((requests.last.data as Map)['mediaUrls'],
            ['https://invalid.test/test-image']);
        expect((requests.last.data as Map)['mediaType'], 'image_text');
        expect(await store.pending(), isEmpty);
      }
      expect(await media.exists(), isTrue);
    });
  }

  test('持久快照可直接转发布任务，临时原件被清理也不丢附件', () async {
    final original =
        await File('${temporary.path}/temporary.mp4').writeAsBytes([1, 3, 5]);
    final store = PostDraftStore(7);
    final saved = await store.save(draft('', video: original.path));
    await original.delete();
    final staged = await store.stage(saved);
    expect(await File(staged['video'] as String).readAsBytes(), [1, 3, 5]);
    // 页面离开时迟到的自动保存不能让同一个已提交草稿复活。
    await store.save(saved);
    expect(await store.active(), isNull);
    expect((await store.pending()).length, 1);
  });

  testWidgets('空白发布页直接返回，不弹草稿选项', (tester) async {
    await mountComposer(tester);
    await leave(tester);
    expect(find.text('保存草稿'), findsNothing);
    expect(find.byType(CreatePostPage), findsNothing);
    expect(await PostDraftStore(7).active(), isNull);
  });

  testWidgets('发布作品不调用内容审核接口且能正常提交', (tester) async {
    await mountComposer(tester);
    await tester.enterText(find.byType(TextField), '无需审核的测试作品');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(
        requests.where((r) => r.path == '/api/config/content-check'), isEmpty);
    expect(
        requests.where((r) => r.path == '/api/community/post'), hasLength(1));
    expect(await PostDraftStore(7).active(), isNull);
    expect(await PostDraftStore(7).pending(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  test('请求载荷保留权限、话题、提及与组件，过滤已删文字实体', () async {
    final snapshot = draft('内容 #保留 @好友')
      ..addAll({
        'topics': {'保留': 1, '已删': 2},
        'mentions': {'好友': 5, '已删用户': 6},
        'location': '杭州',
        'component': {'key': 'room', 'title': '测试'},
      });
    await PostPublishTask.run(
        PostPublishTask(store: PostDraftStore(7), draft: snapshot));
    final data = requests.single.data as Map;
    expect(data['visibility'], 2);
    expect(data['allowComment'], false);
    expect(data['topicIds'], [1]);
    expect(data['mentionedUserIds'], [5]);
    expect(data['locationCode'], '杭州');
    expect(data['component']['title'], '测试');
    expect(jsonEncode(data), isNot(contains('test-account')));
  });
}
