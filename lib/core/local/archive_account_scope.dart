import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'archive_cloud_sync.dart';

/// 需要登录账号才能访问的本地命理档案隔离工具。
///
/// 旧版本把档案直接写在一个公共文件/键中。升级后第一次由某个已登录账号
/// 访问时，会把旧数据迁移给该账号；迁移完成后，其他账号永远不会再读取旧
/// 的公共数据。没有当前账号时一律返回空数据，避免退出登录后残留档案泄露。
class ArchiveAccountScope {
  ArchiveAccountScope._();

  static const legacyOwnerKey = 'fortune_archive_legacy_owner_uid_v1';

  static Future<int?> currentUserId([SharedPreferences? existing]) async {
    try {
      final prefs = existing ?? await SharedPreferences.getInstance();
      final id = prefs.getInt(AppConstants.keyUserId);
      return id == null || id <= 0 ? null : id;
    } catch (_) {
      return null;
    }
  }

  static String scopedKey(String baseKey, int userId) =>
      '${baseKey}_user_$userId';

  /// 读取 SharedPreferences 中的账号档案 JSON。
  ///
  /// [legacyKey] 是旧版本未隔离时使用的键。只有首次绑定的账号才能迁移
  /// 该键；其他账号即便设备上还存在旧键，也只能看到自己的隔离键。
  static Future<String?> readJson(String key) => ArchiveCloudSync.read(key);

  static Future<String?> readLocalJson(String legacyKey) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await currentUserId(prefs);
    if (userId == null) return null;

    await _claimLegacyOwnerIfNeeded(prefs, userId);

    final scoped = scopedKey(legacyKey, userId);
    final current = prefs.getString(scoped);
    if (current != null && current.isNotEmpty) return current;

    final legacy = prefs.getString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;
    if (!await _canMigrateLegacy(prefs, userId)) return null;

    await prefs.setString(scoped, legacy);
    await prefs.remove(legacyKey);
    return legacy;
  }

  /// Local durability first, followed by account-private cloud synchronization.
  static Future<bool> writeJson(String key, String value,
      {int? expectedUserId}) async {
    if (await currentUserId() == null) return false;
    return ArchiveCloudSync.write(key, value, expectedUserId: expectedUserId);
  }

  static Future<bool> removeJson(String baseKey) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await currentUserId(prefs);
    if (userId == null) return false;
    await prefs.remove(scopedKey(baseKey, userId));
    return true;
  }

  /// 获取当前账号的文件，并按需把旧公共文件迁移到该账号文件。
  static Future<File?> scopedFile({
    required Directory directory,
    required String baseName,
    String? legacyName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await currentUserId(prefs);
    if (userId == null) return null;

    await _claimLegacyOwnerIfNeeded(prefs, userId);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final scoped = File('${directory.path}/${_withUser(baseName, userId)}');
    if (await scoped.exists()) return scoped;

    final oldName = legacyName ?? baseName;
    final legacy = File('${directory.path}/$oldName');
    if (await legacy.exists() && await _canMigrateLegacy(prefs, userId)) {
      await legacy.copy(scoped.path);
      await legacy.delete();
    }
    return scoped;
  }

  /// 获取当前账号的隔离目录，并迁移旧公共目录中的文件（若当前账号拥有
  /// 旧数据）。迁移后删除旧文件，防止之后切换账号再次读到。
  static Future<Directory?> scopedDirectory({
    required Directory parent,
    required String baseName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await currentUserId(prefs);
    if (userId == null) return null;

    await _claimLegacyOwnerIfNeeded(prefs, userId);

    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final scoped = Directory('${parent.path}/${_withUser(baseName, userId)}');
    if (!await scoped.exists()) {
      await scoped.create(recursive: true);
    }

    final legacy = Directory('${parent.path}/$baseName');
    if (await legacy.exists() && await _canMigrateLegacy(prefs, userId)) {
      await for (final entity in legacy.list()) {
        final target = File('${scoped.path}/${_basename(entity.path)}');
        try {
          if (entity is File) {
            await entity.copy(target.path);
            await entity.delete();
          }
        } catch (_) {
          // 单个上下文文件迁移失败不影响其他档案读取。
        }
      }
      try {
        if (await legacy.list().isEmpty) await legacy.delete();
      } catch (_) {}
    }
    return scoped;
  }

  static String _withUser(String baseName, int userId) {
    final dot = baseName.lastIndexOf('.');
    if (dot <= 0) return '${baseName}_user_$userId';
    return '${baseName.substring(0, dot)}_user_$userId${baseName.substring(dot)}';
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;

  static Future<bool> _canMigrateLegacy(
    SharedPreferences prefs,
    int userId,
  ) async {
    final owner = prefs.getString(legacyOwnerKey);
    if (owner == null || owner.isEmpty) {
      await prefs.setString(legacyOwnerKey, '$userId');
      return true;
    }
    return owner == '$userId';
  }

  static Future<void> _claimLegacyOwnerIfNeeded(
    SharedPreferences prefs,
    int userId,
  ) async {
    final owner = prefs.getString(legacyOwnerKey);
    if (owner == null || owner.isEmpty) {
      await prefs.setString(legacyOwnerKey, '$userId');
    }
  }
}
