import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xuanyu/features/message/chat_search_page.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/chat_message_sync.dart';
import 'package:xuanyu/features/message/chat_page.dart';

class FakeMessages implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int count = 120;
  bool callRecords = false;
  bool groupInfo = false;
  bool peerMessages = false;
  Completer<ResponseBody>? sending;
  Completer<ResponseBody>? refreshing;
  Completer<ResponseBody>? uploading;
  bool failImages = false;
  final uploadStarted = Completer<void>();
  Map<String, dynamic> message(int id, {String? content}) => {
        'id': id,
        'senderId': peerMessages ? 8 : 7,
        'nickname': '测试用户',
        'avatarUrl': '',
        'type': 'text',
        'content': content ??
            (callRecords && id >= 119
                ? '【${id == 119 ? '语音' : '视频'}通话】发起方已取消'
                : '消息$id'),
        'createdAt': DateTime(2026, 9, 28, 8, 0, id).toIso8601String(),
      };
  ResponseBody body(dynamic data) =>
      ResponseBody.fromString(jsonEncode({'code': 0, 'data': data}), 200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (options.path.endsWith('/info')) {
      return body({
        'type': groupInfo ? 'group' : 'single',
        'isMember': true,
        'name': '测试会话',
        'nickname': '测试好友',
        'memberCount': 3
      });
    }
    if (options.path.endsWith('/members')) return body({'list': []});
    if (options.path == '/api/im/social-call') {
      return ResponseBody.fromString('{"code":403,"message":"测试拦截呼叫"}', 403,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    if (options.path.endsWith('/upload')) {
      if (!uploadStarted.isCompleted) uploadStarted.complete();
      return uploading!.future;
    }
    if (options.path.endsWith('/messages')) {
      if (refreshing != null) {
        final pending = refreshing!;
        refreshing = null;
        return pending.future;
      }
      if (options.queryParameters['keyword'] == '消息10') {
        return body({
          'list': [message(10)],
          'hasMore': false
        });
      }
      final before = options.queryParameters['before_id'] as int? ?? count + 1;
      final last = (before - 1).clamp(0, count);
      final start = (last - 49).clamp(1, count);
      return body({
        'list': [for (var i = start; i <= last; i++) message(i)],
        'hasMore': start > 1
      });
    }
    if (options.path.endsWith('/message')) {
      if (failImages && (options.data as Map)['type'] == 'image') {
        return ResponseBody.fromString('{"message":"模拟网络失败"}', 503, headers: {
          Headers.contentTypeHeader: ['application/json']
        });
      }
      return ((options.data as Map)['type'] == 'text'
              ? sending?.future
              : null) ??
          body(message(++count,
              content: (options.data as Map)['content'] as String));
    }
    return body(<String, dynamic>{});
  }

  @override
  void close({bool force = false}) {}
}

class _Picker extends ImagePickerPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource(
          {required ImageSource source,
          ImagePickerOptions options = const ImagePickerOptions()}) async =>
      XFile(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeMessages fake;
  late HttpClientAdapter previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 7});
    previous = apiClient.httpClientAdapter;
    fake = FakeMessages();
    apiClient.httpClientAdapter = fake;
    setupApiClientToken(
        null); // no network socket, API adapter is fully isolated
  });
  tearDown(() {
    apiClient.httpClientAdapter = previous;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ChatPage(conversationId: 42, title: '测试会话')));
    await tester.pumpAndSettle();
  }

  for (final group in [false, true]) {
    testWidgets('${group ? '群聊' : '私聊'}搜索返回后定位未加载的旧消息', (tester) async {
      fake.groupInfo = group;
      await tester.pumpWidget(MaterialApp(
          home: ChatPage(
        conversationId: 42,
        title: '测试会话',
        peerUserId: group ? null : 8,
        conversationType: group ? 'group' : 'single',
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      final search = find.text(group ? '查找聊天记录' : '查找聊天内容');
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '消息10');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('消息10').last);
      await tester.pumpAndSettle();
      expect(
          fake.requests.any((r) => r.queryParameters['before_id'] == 21), true);
      expect(find.text('消息10').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchPage), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '消息10');
      expect(find.text('消息10'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchPage), findsNothing);
      expect(find.byType(ChatPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('单击头像不拍一拍，双击只发送一次并使用轻触反馈', (tester) async {
    fake.count = 1;
    fake.peerMessages = true;
    var haptics = 0;
    const channel = MethodChannel('xuanyu/haptics');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'nudge') haptics++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await open(tester);
    final avatar = find
        .byWidgetPredicate((w) => w is GestureDetector && w.onDoubleTap != null)
        .first;
    await tester.tap(avatar);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.requests.where((r) => r.path.endsWith('/message')), isEmpty);
    expect(haptics, 0);
    await tester.tap(avatar);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(
        fake.requests.where((r) =>
            r.path.endsWith('/message') && (r.data as Map)['type'] == 'nudge'),
        hasLength(1));
    expect(haptics, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点击语音或视频通话记录按对应模式重新发起', (tester) async {
    fake.callRecords = true;
    await tester.pumpWidget(const MaterialApp(
        home: ChatPage(
      conversationId: 42,
      title: '测试会话',
      peerUserId: 8,
    )));
    await tester.pumpAndSettle();
    for (final label in ['语音', '视频']) {
      final record = find.text('【$label通话】发起方已取消');
      await tester.ensureVisible(record);
      await tester.tap(record);
      await tester.pumpAndSettle();
    }
    expect(
        fake.requests
            .where((r) => r.path == '/api/im/social-call')
            .map((r) => (r.data as Map)['mode']),
        ['voice', 'video']);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  test('断网期间超过两页的新消息可以全部补回', () async {
    fake.count = 180;
    final sync = ChatMessageSync(apiClient, 42);
    final data = await sync.refresh(latestKnownId: 30);
    final ids = (data['list'] as List).map((m) => m['id']).toSet();
    for (var id = 31; id <= 180; id++) {
      expect(ids.contains(id), isTrue);
    }
    expect(fake.requests.length, 4);
    expect(
        fake.requests
            .skip(1)
            .every((r) => r.queryParameters.containsKey('before_id')),
        isTrue);
  });

  testWidgets('慢网发送成功不会清空新输入内容', (tester) async {
    await open(tester);
    fake.sending = Completer<ResponseBody>();
    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '下一条不能丢');
    fake.sending!.complete(fake.body(fake.message(121, content: '第一条')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条不能丢');
  });

  testWidgets('超长文字明确阻止发送并保留完整草稿', (tester) async {
    await open(tester);
    final text = List.filled(2001, '字').join();
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(fake.requests.where((r) => r.path.endsWith('/message')), isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        text);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('上翻历史使用游标，前台恢复有新消息不打断阅读', (tester) async {
    await open(tester);
    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-load-history')));
    await tester.pumpAndSettle();
    expect(
        fake.requests.any((r) => r.queryParameters['before_id'] == 71), isTrue);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('消息21'), findsOneWidget);
    fake.count = 121;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(0, 1));
    expect(find.text('有新消息'), findsOneWidget);
    expect(find.text('消息21'), findsOneWidget);
    await tester.tap(find.text('有新消息'));
    await tester.pumpAndSettle();
    expect(find.text('消息121'), findsOneWidget);
  });

  testWidgets('刷新期间再次触发刷新会补做请求', (tester) async {
    await open(tester);
    final slow = Completer<ResponseBody>();
    fake.refreshing = slow;
    final before = fake.requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    slow.complete(fake.body({
      'list': [fake.message(120)],
      'hasMore': false
    }));
    await tester.pumpAndSettle();
    expect(
        fake.requests
            .skip(before)
            .where((r) => r.path.endsWith('/messages'))
            .length,
        2);
  });

  Future<void> startImageUpload(WidgetTester tester) async {
    final oldPicker = ImagePickerPlatform.instance;
    final dir = await tester
        .runAsync(() => Directory.systemTemp.createTemp('chat-media-test-'));
    final file = File('${dir!.path}/image.png');
    await tester.runAsync(() => file.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2kAAAAABJRU5ErkJggg==')));
    ImagePickerPlatform.instance = _Picker(file.path);
    addTearDown(() async {
      ImagePickerPlatform.instance = oldPicker;
      await dir.delete(recursive: true);
    });
    await open(tester);
    fake.uploading = Completer<ResponseBody>();
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('图片'));
      await fake.uploadStarted.future.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
  }

  testWidgets('图片上传完成时文字仍在发送，图片也会真正提交', (tester) async {
    await startImageUpload(tester);
    fake.sending = Completer<ResponseBody>();
    await tester.enterText(find.byType(TextField), '文字慢网发送');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    for (var i = 0;
        i < 10 &&
            !fake.requests.any((r) =>
                r.path.endsWith('/message') &&
                (r.data as Map)['type'] == 'text');
        i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
        fake.requests.where((r) =>
            r.path.endsWith('/message') && (r.data as Map)['type'] == 'text'),
        hasLength(1));
    expect(fake.sending!.isCompleted, isFalse);
    await tester.runAsync(() async {
      fake.uploading!
          .complete(fake.body({'url': 'https://example.invalid/test.png'}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final imageRequests = fake.requests.where((request) =>
        request.path.endsWith('/message') &&
        (request.data as Map)['type'] == 'image');
    expect(imageRequests, hasLength(1));
    fake.sending!.complete(fake.body(fake.message(122, content: '文字慢网发送')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('图片发送失败保留占位并可重试，不重复上传文件', (tester) async {
    await startImageUpload(tester);
    fake.failImages = true;
    await tester.runAsync(() async {
      fake.uploading!
          .complete(fake.body({'url': 'https://example.invalid/test.png'}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('发送失败，点击重试'), findsOneWidget);
    fake.failImages = false;
    await tester.ensureVisible(find.text('发送失败，点击重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('发送失败，点击重试'), findsNothing);
    expect(
        fake.requests.where((r) => r.path.endsWith('/upload')), hasLength(1));
    expect(
        fake.requests.where((r) =>
            r.path.endsWith('/message') && (r.data as Map)['type'] == 'image'),
        hasLength(2));
  });

  testWidgets('刷新迟到的旧快照不吞掉刚刚发送成功的消息', (tester) async {
    await open(tester);
    final pending = Completer<ResponseBody>();
    fake.refreshing = pending;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '刚刚发送的内容');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    pending.complete(fake.body({
      'list': [fake.message(120)],
      'hasMore': true
    }));
    await tester.pumpAndSettle();
    expect(find.text('刚刚发送的内容'), findsOneWidget);
  });
}
