import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/cache/account_scoped_json_cache.dart';
import 'package:xuanyu/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.keyUserId: 101,
    });
    AccountScopedJsonCache.clearMemory();
  });

  test('命盘缓存按账号和请求参数隔离', () async {
    final request = <String, dynamic>{
      'birthDate': '2000-01-02',
      'gender': '女',
      'config': <String, dynamic>{'mode': 'natal'},
    };
    final firstKey = await AccountScopedJsonCache.keyFor('ziwei', request);
    await AccountScopedJsonCache.write(firstKey, <String, dynamic>{'value': 1});

    expect(await AccountScopedJsonCache.read(firstKey), {'value': 1});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 202);
    final secondKey = await AccountScopedJsonCache.keyFor('ziwei', request);
    expect(secondKey.value, isNot(firstKey.value));
    expect(await AccountScopedJsonCache.read(secondKey), isNull);

    await prefs.setInt(AppConstants.keyUserId, 101);
    final restoredKey = await AccountScopedJsonCache.keyFor('ziwei', request);
    expect(await AccountScopedJsonCache.read(restoredKey), {'value': 1});
  });

  test('清除账号缓存不会删除其他账号结果', () async {
    final request = <String, dynamic>{'birthDate': '1998-08-08'};
    final user101 = await AccountScopedJsonCache.keyFor('astrology', request);
    await AccountScopedJsonCache.write(user101, <String, dynamic>{'user': 101});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 202);
    final user202 = await AccountScopedJsonCache.keyFor('astrology', request);
    await AccountScopedJsonCache.write(user202, <String, dynamic>{'user': 202});

    await AccountScopedJsonCache.clearForUser(101);
    expect(await AccountScopedJsonCache.read(user101), isNull);
    expect(await AccountScopedJsonCache.read(user202), {'user': 202});
  });
}
