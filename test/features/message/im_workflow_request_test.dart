import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/message/im_workflow_request.dart';

void main() {
  test('HTTP成功仍必须校验业务状态', () {
    expect(
        () => imResponseData({'code': 403, 'message': '没有权限'}),
        throwsA(isA<ImWorkflowFailure>()
            .having((e) => e.code, 'code', 403)
            .having((e) => e.message, 'message', '没有权限')));
    expect(
        imResponseData({
          'code': 0,
          'data': {'invited': 1}
        }),
        {'invited': 1});
  });

  test('异常数据不会伪装成空成功', () {
    for (final body in [
      null,
      [],
      {},
      {'code': 'error'},
      {'code': 0, 'data': []}
    ]) {
      expect(() => imResponseData(body), throwsA(isA<ImWorkflowFailure>()));
    }
    expect(imResponseData({'code': 0}), isEmpty);
  });

  test('列表格式异常不降级为空列表', () {
    for (final body in <Map<String, dynamic>>[
      {},
      {'list': null},
      {
        'list': [1]
      }
    ]) {
      expect(() => imResponseList(body), throwsA(isA<ImWorkflowFailure>()));
    }
    expect(imResponseList({'list': []}), isEmpty);
  });

  final records = [
    {'type': 'chatApply', 'id': 1},
    {'type': 'groupApply', 'id': 1},
  ];
  test('同号不同类型记录分开，只隐藏服务端确认的项目', () {
    expect(
        imConfirmedHiddenKeys(records, {
          'hiddenCount': 1,
          'skipped': [
            {'type': 'groupApply', 'id': 1}
          ]
        }),
        {'chatApply:1'});
  });

  test('全部跳过就不隐藏任何记录', () {
    expect(
        imConfirmedHiddenKeys(records, {'hiddenCount': 0, 'skipped': records}),
        isEmpty);
  });

  test('删除数量不匹配或跳过未知记录，需要刷新确认', () {
    for (final body in [
      {'hiddenCount': 1, 'skipped': []},
      {
        'hiddenCount': 2,
        'skipped': [
          {'type': 'groupInvite', 'id': 8}
        ]
      },
      {'hiddenCount': 2},
    ]) {
      expect(() => imConfirmedHiddenKeys(records, body),
          throwsA(isA<ImWorkflowFailure>()));
    }
  });

  test('业务错误与网络错误分别保留可识别状态和消息', () {
    final error = DioException(
        requestOptions: RequestOptions(path: '/local-test'),
        response: Response(
            requestOptions: RequestOptions(path: '/local-test'),
            statusCode: 404,
            data: {'message': '成员已退出'}));
    expect(imFailureStatus(error), 404);
    expect(imFailureMessage(error, '默认错误'), '成员已退出');
    expect(imFailureMessage(StateError('unexpected'), '请重试'), '请重试');
  });

  group('请求账号隔离', () {
    late InterceptorsWrapper fake;
    late void Function(RequestOptions, RequestInterceptorHandler) respond;
    final calls = <RequestOptions>[];
    setUp(() {
      calls.clear();
      apiClient.options.headers['Authorization'] = 'local-test-session-a';
      respond = (r, h) => h.resolve(Response(requestOptions: r, data: {
            'code': 0,
            'data': {'value': 1}
          }));
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

    test('已经切号的请求不能再发出', () async {
      final request = ImWorkflowRequest();
      apiSessionChanges.value++;
      await expectLater(
          request.get('/local-test'), throwsA(isA<ImWorkflowFailure>()));
      await expectLater(
          request.post('/local-test'), throwsA(isA<ImWorkflowFailure>()));
      await expectLater(
          request.patch('/local-test'), throwsA(isA<ImWorkflowFailure>()));
      await expectLater(
          request.delete('/local-test'), throwsA(isA<ImWorkflowFailure>()));
      expect(calls, isEmpty);
    });

    test('认证头固定在操作发起时，不借用变化后的头', () async {
      final request = ImWorkflowRequest();
      apiClient.options.headers['Authorization'] = 'local-test-session-b';
      await request.get('/local-test');
      expect(calls.single.headers['Authorization'], 'local-test-session-a');
    });

    test('请求中途切号，旧结果失效', () async {
      final started = Completer<void>();
      late RequestOptions held;
      late RequestInterceptorHandler handler;
      respond = (r, h) {
        held = r;
        handler = h;
        started.complete();
      };
      final request = ImWorkflowRequest();
      final result = request.get('/local-test');
      final rejected = expectLater(result, throwsA(isA<ImWorkflowFailure>()));
      await started.future;
      apiSessionChanges.value++;
      handler.resolve(Response(requestOptions: held, data: {
        'code': 0,
        'data': {'value': 1}
      }));
      await rejected;
    });
  });
}
