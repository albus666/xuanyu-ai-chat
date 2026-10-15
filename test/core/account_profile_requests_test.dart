import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/account_profile_requests.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Interceptor interceptor;
  late List<(RequestOptions, RequestInterceptorHandler)> pending;

  setUp(() {
    pending = [];
    AccountProfileRequests.invalidate();
    setupApiClientToken('synthetic-profile-a');
    interceptor = InterceptorsWrapper(
      onRequest: (request, handler) {
        expect(request.path, '/api/auth/me');
        pending.add((request, handler));
      },
    );
    apiClient.interceptors.insert(0, interceptor);
  });
  tearDown(() {
    apiClient.interceptors.remove(interceptor);
    AccountProfileRequests.invalidate();
    setupApiClientToken(null);
  });

  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void reply(int index, String name) {
    final (request, handler) = pending[index];
    handler.resolve(
      Response(
        requestOptions: request,
        data: {
          'code': 0,
          'data': {'nickname': name},
        },
      ),
    );
  }

  String nameOf(Response<dynamic> response) =>
      (response.data as Map)['data']['nickname'] as String;

  test('同会话并发资料请求合并，完成后重新读取不复用旧响应', () async {
    final first = AccountProfileRequests.fetch(ApiSessionScope());
    final second = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    expect(pending, hasLength(1));
    reply(0, '第一次资料');
    expect(nameOf(await first), '第一次资料');
    expect(nameOf(await second), '第一次资料');

    final next = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    expect(pending, hasLength(2));
    reply(1, '更新后的资料');
    expect(nameOf(await next), '更新后的资料');
  });

  test('编辑失效后旧响应加入新请求，两个调用者都只收到新资料', () async {
    final old = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    AccountProfileRequests.invalidate();
    final replacement = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    expect(pending, hasLength(2));
    reply(0, '编辑前旧资料');
    await flush();
    expect(pending, hasLength(2));
    reply(1, '编辑后新资料');
    expect(nameOf(await replacement), '编辑后新资料');
    expect(nameOf(await old), '编辑后新资料');
  });

  test('新资料先完成后旧响应才到，也不能把旧资料交给调用方', () async {
    final old = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    AccountProfileRequests.invalidate();
    final replacement = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    reply(1, '编辑后资料');
    expect(nameOf(await replacement), '编辑后资料');
    reply(0, '过期资料');
    await flush();
    // Completed responses are not cached. The outdated caller performs a new
    // live read when the replacement has already completed.
    expect(pending, hasLength(3));
    reply(2, '最新资料');
    expect(nameOf(await old), '最新资料');
  });

  test('切号不合并账号请求，旧响应失败且不影响新账号在途请求', () async {
    final old = AccountProfileRequests.fetch(ApiSessionScope());
    final oldFailure = expectLater(
      old,
      throwsA(isA<ApiSessionChangedException>()),
    );
    await flush();
    setupApiClientToken('synthetic-profile-b');
    final next = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    expect(pending, hasLength(2));
    expect(
      pending[0].$1.headers['Authorization'],
      'Bearer synthetic-profile-a',
    );
    expect(
      pending[1].$1.headers['Authorization'],
      'Bearer synthetic-profile-b',
    );
    reply(0, '旧账号资料');
    await oldFailure;
    final shared = AccountProfileRequests.fetch(ApiSessionScope());
    await flush();
    expect(pending, hasLength(2));
    reply(1, '新账号资料');
    expect(nameOf(await next), '新账号资料');
    expect(nameOf(await shared), '新账号资料');
  });
}
