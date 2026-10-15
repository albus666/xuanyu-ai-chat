import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/cache/page_snapshot_cache.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserId: 7,
      AppConstants.keyToken: 'synthetic-seven',
    });
    setupApiClientToken('synthetic-seven');
    PageSnapshotCache.clearMemory();
  });
  tearDown(() => setupApiClientToken(null));

  test('同会话复用但不同查询参数隔离，返回值修改不污染快照', () async {
    final cache = PageSnapshotCache(
      'catalog',
      parameters: {'page': 1, 'type': 'all'},
    );
    await cache.write({
      'items': [
        {'name': '原始'},
      ],
    });
    final reordered = PageSnapshotCache(
      'catalog',
      parameters: {'type': 'all', 'page': 1},
    );
    final first = (await reordered.read())!;
    (first['items'] as List).clear();
    expect((await cache.read())!['items'], hasLength(1));
    expect(
      await PageSnapshotCache('catalog', parameters: {'page': 2}).read(),
      isNull,
    );
    expect(
      (await SharedPreferences.getInstance()).getKeys().where(
            (k) => k.startsWith('page_snapshot_'),
          ),
      isEmpty,
    );
  });

  test('持久快照按账号隔离，旧会话读写失效', () async {
    final old = PageSnapshotCache('catalog', persist: true);
    await old.write({'title': '甲'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 8);
    // Preference writes can precede the session-version update during switching.
    await prefs.setString(AppConstants.keyToken, 'synthetic-eight');
    await old.write({'title': '切号窗口旧内容'});
    setupApiClientToken('synthetic-eight');
    expect(await old.read(), isNull);
    await old.write({'title': '旧请求'});
    expect(await PageSnapshotCache('catalog', persist: true).read(), isNull);
    await prefs.setInt(AppConstants.keyUserId, 7);
    await prefs.setString(AppConstants.keyToken, 'synthetic-seven');
    setupApiClientToken('synthetic-seven');
    expect(
      (await PageSnapshotCache('catalog', persist: true).read())!['title'],
      '甲',
    );
  });

  test('过期、损坏及超限数据不用于回显', () async {
    final expired = PageSnapshotCache(
      'expired',
      maxAge: Duration.zero,
      persist: true,
    );
    await expired.write({'title': '过期'});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(await expired.read(), isNull);
    final oversized = PageSnapshotCache('oversized', persist: true);
    await oversized.write({'large': '大' * 300000});
    expect(await oversized.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    final diskKey = prefs.getKeys().firstWhere(
          (k) => k.startsWith('page_snapshot_'),
        );
    await prefs.setString(diskKey, '{invalid');
    PageSnapshotCache.clearMemory();
    expect(await expired.read(), isNull);
  });

  test('条目有界且显式移除同时清除磁盘和内存', () async {
    for (var i = 0; i < 28; i++) {
      await PageSnapshotCache(
        'catalog',
        parameters: {'page': i},
        persist: true,
      ).write({'page': i});
    }
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('page_snapshot_')).length,
      lessThanOrEqualTo(24),
    );
    final cache = PageSnapshotCache(
      'catalog',
      parameters: {'page': 27},
      persist: true,
    );
    await cache.remove();
    expect(await cache.read(), isNull);
  });
}
