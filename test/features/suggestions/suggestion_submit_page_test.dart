import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/suggestions/suggestion_service.dart';
import 'package:xuanyu/features/suggestions/suggestion_submit_page.dart';

class _Service extends SuggestionService {
  final submissions =
      <({String requestId, String content, List<String> ids})>[];
  final uploads = <String>[];
  bool failNext = false;
  Completer<void>? holdSubmit;
  Completer<void>? holdUpload;
  @override
  Future<String> upload(XFile file,
      {required bool isVideo, required ProgressCallback onProgress}) async {
    uploads.add(file.path);
    onProgress(10, 20);
    if (holdUpload != null) await holdUpload!.future;
    return 'attachment-${uploads.length}';
  }

  @override
  Future<void> submit(
      {required String requestId,
      required String content,
      required List<String> attachmentIds}) async {
    submissions.add(
        (requestId: requestId, content: content, ids: List.of(attachmentIds)));
    if (holdSubmit != null) await holdSubmit!.future;
    if (failNext) {
      failNext = false;
      throw const SuggestionValidationException('网络暂不可用，请重试');
    }
  }
}

class _Picker extends ImagePicker {
  List<XFile> images = [];
  XFile? video;
  @override
  Future<List<XFile>> pickMultiImage(
          {double? maxWidth,
          double? maxHeight,
          int? imageQuality,
          int? limit,
          bool requestFullMetadata = true}) async =>
      images;
  @override
  Future<XFile?> pickVideo(
          {required ImageSource source,
          CameraDevice preferredCameraDevice = CameraDevice.rear,
          Duration? maxDuration}) async =>
      video;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Service service;
  late _Picker picker;
  setUp(() async {
    setupApiClientToken('synthetic-suggestion-page');
    service = _Service();
    picker = _Picker();
    directory = await Directory.systemTemp.createTemp('suggestion-page-');
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/S2kAAAAASUVORK5CYII=');
    for (var i = 0; i < 7; i++) {
      await File('${directory.path}/image$i.png').writeAsBytes(bytes);
    }
    await File('${directory.path}/clip.mp4').writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    setupApiClientToken(null);
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {bool routed = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final page = SuggestionSubmitPage(service: service, picker: picker);
    await tester.pumpWidget(MaterialApp(
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => page)),
                        child: const Text('打开建议'))))
            : page));
    if (routed) await tester.tap(find.text('打开建议'));
    await tester.pumpAndSettle();
  }

  Future<void> flushFiles(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('suggestion-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('提交失败保留文字附件，重试复用请求ID及已上传附件', (tester) async {
    picker.images = [XFile('${directory.path}/image0.png')];
    service.failNext = true;
    await mount(tester);
    await tester.enterText(
        find.byKey(const ValueKey('suggestion-content')), '希望按钮更容易找到');
    await tester.tap(find.byKey(const ValueKey('suggestion-add-images')));
    await flushFiles(tester);
    await submit(tester);
    expect(find.text('网络暂不可用，请重试'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '希望按钮更容易找到');
    expect(find.byTooltip('删除图片1'), findsOneWidget);
    expect(service.uploads, hasLength(1));
    await submit(tester);
    expect(service.submissions, hasLength(2));
    expect(service.submissions[0].requestId, service.submissions[1].requestId);
    expect(service.submissions[1].ids, ['attachment-1']);
    expect(service.uploads, hasLength(1));
    expect(find.text('建议已提交'), findsOneWidget);
  });

  testWidgets('连点提交只发一次，切号后隐藏旧文字且迟到成功不串账号', (tester) async {
    service.holdSubmit = Completer<void>();
    await mount(tester);
    await tester.enterText(
        find.byKey(const ValueKey('suggestion-content')), '私有建议内容');
    final button = find.byKey(const ValueKey('suggestion-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(service.submissions, hasLength(1));
    setupApiClientToken('synthetic-next-account');
    await tester.pumpAndSettle();
    expect(find.text(apiSessionChangedMessage), findsOneWidget);
    expect(find.text('私有建议内容'), findsNothing);
    service.holdSubmit!.complete();
    await tester.pumpAndSettle();
    expect(find.text('建议已提交'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未提交内容返回时确认，继续填写保留内容', (tester) async {
    await mount(tester, routed: true);
    await tester.enterText(
        find.byKey(const ValueKey('suggestion-content')), '不要丢掉这句话');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃这条建议？'), findsOneWidget);
    await tester.tap(find.text('继续填写'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '不要丢掉这句话');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并离开'));
    await tester.pumpAndSettle();
    expect(find.text('打开建议'), findsOneWidget);
    expect(service.submissions, isEmpty);
  });

  testWidgets('选择上限6图和1视频，可删除附件且不触发提交', (tester) async {
    picker.images =
        List.generate(7, (i) => XFile('${directory.path}/image$i.png'));
    picker.video = XFile('${directory.path}/clip.mp4');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('suggestion-add-images')));
    await flushFiles(tester);
    expect(find.text('补充图片（6/6）'), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-add-images')), findsNothing);
    final video = find.byKey(const ValueKey('suggestion-add-video'));
    await tester.ensureVisible(video);
    await tester.tap(video);
    await flushFiles(tester);
    expect(find.text('clip.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('删除视频'));
    await tester.pumpAndSettle();
    expect(find.text('clip.mp4'), findsNothing);
    await tester.ensureVisible(find.byTooltip('删除图片1'));
    await tester.tap(find.byTooltip('删除图片1'));
    await tester.pumpAndSettle();
    expect(find.text('补充图片（5/6）'), findsOneWidget);
    expect(service.submissions, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('上传进度可见且上传期间禁用提交', (tester) async {
    picker.images = [XFile('${directory.path}/image0.png')];
    service.holdUpload = Completer<void>();
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('suggestion-add-images')));
    await flushFiles(tester);
    final button = find.byKey(const ValueKey('suggestion-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .5);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(service.submissions, isEmpty);
    service.holdUpload!.complete();
    await tester.pumpAndSettle();
    expect(find.text('建议已提交'), findsOneWidget);
  });

  testWidgets('窄屏键盘和底部导航区域不遮挡可滚动提交按钮', (tester) async {
    await mount(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('suggestion-submit'));
    await tester.scrollUntilVisible(button, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(606));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    tester.view.padding = const FakeViewPadding();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('suggestion-content')), -160,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byKey(const ValueKey('suggestion-content')), '小屏也能提交');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(button, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(service.submissions.single.content, '小屏也能提交');
    expect(tester.takeException(), isNull);
  });
}
