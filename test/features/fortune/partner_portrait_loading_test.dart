import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/features/fortune/partner_portrait/partner_portrait_service.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = ZiweiProfile(
    name: '测试档案',
    gender: '男',
    clockBirthDate: DateTime(1995, 1, 1, 8),
    effectiveBirthDate: DateTime(1995, 1, 1, 8),
    calendarTypeIndex: 0,
    settings: const ZiweiSettings(),
  );
  late InterceptorsWrapper fake;
  late List<(RequestOptions, RequestInterceptorHandler)> pending;
  setUp(() {
    setupApiClientToken(null);
    pending = [];
    fake = InterceptorsWrapper(onRequest: (options, handler) {
      pending.add((options, handler));
    });
    apiClient.interceptors.insert(0, fake);
  });
  tearDown(() => apiClient.interceptors.remove(fake));

  Future<void> flush() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void reply(int index, String headline) {
    final (request, handler) = pending[index];
    handler.resolve(Response(requestOptions: request, data: {
      'code': 0,
      'data': {'headline': headline, 'reportPrice': 29},
    }));
  }

  test('同账号相同画像合并在途读取，完成后重新读取最新价格和购买状态', () async {
    final first = PartnerPortraitService.preview(profile);
    final second = PartnerPortraitService.preview(profile);
    await flush();
    expect(pending, hasLength(1));
    expect(pending.single.$1.path, '/api/fortune/partner-portrait/preview');
    reply(0, '首次结果');
    expect((await first).headline, '首次结果');
    expect((await second).headline, '首次结果');
    final fresh = PartnerPortraitService.preview(profile);
    await flush();
    expect(pending, hasLength(2));
    reply(1, '最新结果');
    expect((await fresh).headline, '最新结果');
    expect(pending.any((item) => item.$1.path.endsWith('/purchase')), isFalse);
  });

  test('切号后的相同画像不复用旧会话请求', () async {
    final old = PartnerPortraitService.preview(profile);
    final oldFailure =
        expectLater(old, throwsA(isA<ApiSessionChangedException>()));
    await flush();
    apiSessionChanges.value++;
    final current = PartnerPortraitService.preview(profile);
    await flush();
    expect(pending, hasLength(2));
    reply(0, '旧账号结果');
    reply(1, '新账号结果');
    await oldFailure;
    expect((await current).headline, '新账号结果');
  });
}
