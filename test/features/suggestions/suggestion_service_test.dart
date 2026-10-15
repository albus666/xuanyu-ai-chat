import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/suggestions/suggestion_service.dart';

class _SizedFile extends XFile {
  _SizedFile(this.bytes, String name) : super('/unused/$name');
  final int bytes;
  @override
  Future<int> length() async => bytes;
}

class _Api implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final started = Completer<void>();
  Completer<ResponseBody>? held;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    if (held != null) return held!.future;
    return body(options.path.endsWith('/upload')
        ? {'id': 'owned-attachment-id', 'url': 'https://example.invalid/signed'}
        : {'id': 17});
  }

  static ResponseBody body(Object data) => ResponseBody.fromString(
        jsonEncode({'code': 0, 'data': data}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        },
      );
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter previous;
  late _Api api;
  setUp(() {
    setupApiClientToken('synthetic-suggestion-owner');
    previous = apiClient.httpClientAdapter;
    api = _Api();
    apiClient.httpClientAdapter = api;
  });
  tearDown(() {
    apiClient.httpClientAdapter = previous;
    setupApiClientToken(null);
  });

  test('至少文字或附件，文字及图片数量按上限校验', () {
    expect(
        () => SuggestionService.validate(
            content: ' ', images: 0, hasVideo: false),
        throwsA(isA<SuggestionValidationException>()));
    expect(
        () => SuggestionService.validate(
            content: '字' * 2001, images: 0, hasVideo: false),
        throwsA(isA<SuggestionValidationException>()));
    expect(
        () =>
            SuggestionService.validate(content: '', images: 7, hasVideo: false),
        throwsA(isA<SuggestionValidationException>()));
    SuggestionService.validate(content: '字' * 2000, images: 6, hasVideo: true);
    SuggestionService.validate(content: '', images: 0, hasVideo: true);
  });

  test('附件大小边界及格式在上传前拒绝，不读取大文件进内存', () async {
    await SuggestionService.validateFile(
        _SizedFile(10 * 1024 * 1024, 'photo.jpeg'),
        isVideo: false);
    await SuggestionService.validateFile(
        _SizedFile(100 * 1024 * 1024, 'clip.MOV'),
        isVideo: true);
    for (final entry in [
      (_SizedFile(10 * 1024 * 1024 + 1, 'photo.png'), false),
      (_SizedFile(100 * 1024 * 1024 + 1, 'clip.mp4'), true),
      (_SizedFile(0, 'photo.jpg'), false),
      (_SizedFile(10, 'note.txt'), false)
    ]) {
      await expectLater(
          SuggestionService.validateFile(entry.$1, isVideo: entry.$2),
          throwsA(isA<SuggestionValidationException>()));
    }
    expect(api.requests, isEmpty);
  });

  test('上传与提交使用附件ID契约，私有外链不作为提交输入', () async {
    final directory =
        await Directory.systemTemp.createTemp('suggestion-service-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/photo.png');
    await file.writeAsBytes([1, 2, 3]);
    final service = SuggestionService();
    final id = await service.upload(XFile(file.path),
        isVideo: false, onProgress: (_, __) {});
    final requestId = SuggestionService.newRequestId();
    await service
        .submit(requestId: requestId, content: ' 改进想法 ', attachmentIds: [id]);
    expect(id, 'owned-attachment-id');
    expect(api.requests.first.path, '/api/config/suggestions/upload');
    expect(
        (api.requests.first.data as FormData)
            .fields
            .singleWhere((entry) => entry.key == 'type')
            .value,
        'image');
    expect(api.requests.last.data, {
      'requestId': requestId,
      'content': '改进想法',
      'attachmentIds': ['owned-attachment-id'],
    });
    expect(
        api.requests.every((r) =>
            r.headers['Authorization'] == 'Bearer synthetic-suggestion-owner'),
        true);
  });

  test('切换账号后旧服务不能向新账号发送建议', () async {
    final service = SuggestionService();
    setupApiClientToken('synthetic-next-account');
    await expectLater(
        service.submit(
            requestId: SuggestionService.newRequestId(),
            content: '旧账号内容',
            attachmentIds: []),
        throwsA(isA<ApiSessionChangedException>()));
    expect(api.requests, isEmpty);
  });

  test('切号后迟到提交响应不作为当前账号成功结果', () async {
    final service = SuggestionService();
    api.held = Completer<ResponseBody>();
    final pending = service.submit(
        requestId: SuggestionService.newRequestId(),
        content: '建议',
        attachmentIds: []);
    final checked =
        expectLater(pending, throwsA(isA<ApiSessionChangedException>()));
    await api.started.future;
    setupApiClientToken('synthetic-next-account');
    api.held!.complete(_Api.body({'id': 7}));
    await checked;
    expect(api.requests.single.headers['Authorization'],
        'Bearer synthetic-suggestion-owner');
  });

  test('每条新建议使用合法且不同的UUIDv4', () {
    final ids = List.generate(30, (_) => SuggestionService.newRequestId());
    final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(ids.every(uuid.hasMatch), true);
    expect(ids.toSet().length, ids.length);
  });
}
