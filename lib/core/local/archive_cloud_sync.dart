import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/api_session_scope.dart';
import '../utils/app_toast.dart';
import 'archive_account_scope.dart';

/// Account-private cloud records with a persistent local synchronization baseline.
/// No local absence becomes a delete unless this device previously saw that row.
class ArchiveCloudSync {
  static const bazi = 'paipan_records_v1';
  static const collections = [
    bazi,
    'ziwei_archive_records_v1',
    'astrology_archive_records_v1',
    'qizheng_archive_records_v1',
    'room_chart_case_details_v1'
  ];
  static final changes = ValueNotifier<int>(0);
  static final status = ValueNotifier<Map<String, String>>({});
  static final _queues = <String, Future<void>>{};
  static final _checked = <String, DateTime>{};
  static _ArchiveLifecycle? _lifecycle;

  static void start() {
    _lifecycle ??= _ArchiveLifecycle();
    unawaited(syncAll());
  }

  static Future<void> syncAll() async {
    for (final collection in collections) {
      try {
        await read(collection, force: true);
      } catch (_) {}
    }
  }

  static Future<void> resolveConflicts({required bool useLocal}) async {
    final ownerScope = ApiSessionScope();
    for (final collection in collections) {
      ownerScope.ensureCurrent();
      await _exclusive(collection, (uid, scope) async {
        ownerScope.ensureCurrent();
        final prefs = await SharedPreferences.getInstance();
        final key = 'archive_cloud_baseline_v1_${uid}_$collection';
        final raw = prefs.getString(key);
        if (raw == null) return;
        final baseline = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final conflicts = baseline['conflicts'] as Map? ?? {};
        if (conflicts.isEmpty) return;
        final local = _rows(collection, await _readLocal(collection));
        final rows = Map<String, dynamic>.from(baseline['rows'] as Map);
        final revisions =
            Map<String, dynamic>.from(baseline['revisions'] as Map);
        for (final id in conflicts.keys) {
          final item = conflicts[id] as Map;
          revisions[id.toString()] = item['revision'];
          if (item['deleted'] == true) {
            rows.remove(id);
            if (!useLocal) local.remove(id);
          } else {
            rows[id.toString()] = item['payload'];
            if (!useLocal) local[id.toString()] = item['payload'];
          }
        }
        await _writeLocal(collection, _encode(collection, local), uid, scope);
        await _ensure(uid, scope);
        await prefs.setString(
            key, jsonEncode({'rows': rows, 'revisions': revisions}));
        await _trySync(collection, uid, scope);
      });
    }
  }

  static Future<void> _refresh(
      String collection, int uid, ApiSessionScope scope) async {
    final key = '$uid:${scope.session}:$collection';
    final checked = _checked[key];
    if (checked == null ||
        DateTime.now().difference(checked) > const Duration(seconds: 30)) {
      await _trySync(collection, uid, scope);
      if (scope.current) _checked[key] = DateTime.now();
    }
  }

  static void _scheduleSync(String collection, ApiSessionScope scope) {
    if (!scope.authenticated) return;
    _state(scope, collection, 'pending');
    unawaited(read(collection, force: true).catchError((_) => null));
  }

  static String? get message {
    final messages = status.value.values;
    if (messages.contains('conflict')) {
      return '部分案例在另一台设备上有修改，本地内容已保留，请勿清除应用数据';
    }
    if (messages.contains('pending')) {
      return '案例已保存在本机，云端同步未完成，联网后自动重试';
    }
    if (messages.contains('syncing')) return '正在同步账号案例…';
    return null;
  }

  static void _state(ApiSessionScope scope, String collection, String state) {
    if (scope.current) status.value = {...status.value, collection: state};
  }

  static Future<T> _exclusive<T>(String collection,
      Future<T> Function(int uid, ApiSessionScope scope) action,
      {int? expectedUserId}) async {
    final scope = ApiSessionScope();
    final uid = await ArchiveAccountScope.currentUserId();
    scope.ensureCurrent();
    if (uid == null || (expectedUserId != null && uid != expectedUserId)) {
      throw StateError('档案所属账号已变更，请重新操作');
    }
    final key = '$uid:$collection';
    final previous = _queues[key];
    final completion = Completer<void>();
    _queues[key] = completion.future;
    try {
      if (previous != null) await previous;
      await _ensure(uid, scope);
      return await action(uid, scope);
    } finally {
      completion.complete();
      if (identical(_queues[key], completion.future)) _queues.remove(key);
    }
  }

  static Future<void> _ensure(int uid, ApiSessionScope scope) async {
    scope.ensureCurrent();
    if (await ArchiveAccountScope.currentUserId() != uid) {
      throw const ApiSessionChangedException();
    }
    scope.ensureCurrent();
  }

  static Future<String?> read(String collection, {bool force = false}) async {
    final locked = Zone.current[#archiveMutation];
    if (locked is _ArchiveMutation && locked.collection == collection) {
      await _ensure(locked.uid, locked.scope);
      return _readLocal(collection);
    }
    if (await ArchiveAccountScope.currentUserId() == null) return null;
    return _exclusive(collection, (uid, scope) async {
      if (collections.contains(collection)) {
        final key = '$uid:${scope.session}:$collection';
        final checked = _checked[key];
        if (force ||
            checked == null ||
            DateTime.now().difference(checked) > const Duration(seconds: 30)) {
          await _trySync(collection, uid, scope);
          if (scope.current) _checked[key] = DateTime.now();
        }
      }
      await _ensure(uid, scope);
      return _readLocal(collection);
    });
  }

  static Future<bool> write(String collection, String value,
      {int? expectedUserId}) async {
    final locked = Zone.current[#archiveMutation];
    if (locked is _ArchiveMutation && locked.collection == collection) {
      if (expectedUserId != null && expectedUserId != locked.uid) {
        throw const ApiSessionChangedException();
      }
      _rows(collection, value);
      await _writeLocal(collection, value, locked.uid, locked.scope);
      if (locked.scope.current) changes.value++;
      return true;
    }
    return _exclusive(collection, (uid, scope) async {
      // Validate existing storage before a replacement; never overwrite corruption.
      final old = await _readLocal(collection);
      _rows(collection, old);
      _rows(collection, value);
      await _writeLocal(collection, value, uid, scope);
      if (scope.current) changes.value++;
      await _trySync(collection, uid, scope);
      return true;
    }, expectedUserId: expectedUserId);
  }

  static Future<T> mutateJson<T>(
          String collection, Future<T> Function() mutation,
          {int? expectedUserId}) =>
      _exclusive(collection, (uid, scope) async {
        await _refresh(collection, uid, scope);
        await _ensure(uid, scope);
        _rows(collection, await _readLocal(collection));
        final result = await runZoned(mutation, zoneValues: {
          #archiveMutation: _ArchiveMutation(collection, uid, scope),
        });
        await _ensure(uid, scope);
        _scheduleSync(collection, scope);
        return result;
      }, expectedUserId: expectedUserId);

  /// Bazi's existing strict atomic writer shares the same lock as cloud restores.
  static Future<T> mutateBazi<T>(Future<T> Function() mutation,
          {int? expectedUserId}) =>
      _exclusive(bazi, (uid, scope) async {
        await _refresh(bazi, uid, scope);
        await _ensure(uid, scope);
        final result = await mutation();
        await _ensure(uid, scope);
        changes.value++;
        _scheduleSync(bazi, scope);
        return result;
      }, expectedUserId: expectedUserId);

  static Future<String?> _readLocal(String collection) async {
    if (collection != bazi) {
      return ArchiveAccountScope.readLocalJson(collection);
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = await ArchiveAccountScope.scopedFile(
        directory: dir, baseName: 'paipan_records.json');
    if (file == null || !await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> _writeLocal(
      String collection, String value, int uid, ApiSessionScope scope) async {
    await _ensure(uid, scope);
    if (collection != bazi) {
      final prefs = await SharedPreferences.getInstance();
      await _ensure(uid, scope);
      if (!await prefs.setString(
          ArchiveAccountScope.scopedKey(collection, uid), value)) {
        throw StateError('档案缓存保存失败');
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/paipan_records_user_$uid.json');
    final temp = await dir.createTemp('.archive-cloud-');
    try {
      final staged = File('${temp.path}/records.json');
      await staged.writeAsString(value, flush: true);
      await _ensure(uid, scope);
      if (await file.exists()) await file.copy('${file.path}.backup');
      await _ensure(uid, scope);
      await staged.rename(file.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Map<String, dynamic> _rows(String collection, String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (collection == 'room_chart_case_details_v1') {
      if (decoded is! Map) throw const FormatException('案例资料格式异常');
      final rows = Map<String, dynamic>.from(decoded);
      if (rows.values.any((value) => value is! Map)) {
        throw const FormatException('案例资料格式异常');
      }
      return rows;
    }
    if (decoded is! List) throw const FormatException('档案格式异常');
    final rows = <String, dynamic>{};
    for (final value in decoded) {
      if (value is! Map ||
          value['id'] is! String ||
          (value['id'] as String).isEmpty) {
        throw const FormatException('档案编号异常');
      }
      final id = value['id'] as String;
      if (rows.containsKey(id)) throw const FormatException('档案编号重复');
      rows[id] = Map<String, dynamic>.from(value);
    }
    return rows;
  }

  static String _encode(String collection, Map<String, dynamic> rows) =>
      jsonEncode(collection == 'room_chart_case_details_v1'
          ? rows
          : rows.values.toList());

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static bool _same(Object? a, Object? b) =>
      jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

  static Future<void> _trySync(
      String collection, int uid, ApiSessionScope scope) async {
    if (!scope.authenticated || !collections.contains(collection)) return;
    _state(scope, collection, 'syncing');
    try {
      await _sync(collection, uid, scope);
    } catch (_) {
      _state(scope, collection, 'pending');
    }
  }

  static Future<void> _sync(
      String collection, int uid, ApiSessionScope scope) async {
    final local = _rows(collection, await _readLocal(collection));
    await _ensure(uid, scope);
    final prefs = await SharedPreferences.getInstance();
    final stateKey = 'archive_cloud_baseline_v1_${uid}_$collection';
    final raw = prefs.getString(stateKey);
    final baseline = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final oldRows = Map<String, dynamic>.from(baseline['rows'] as Map? ?? {});
    final oldRevisions =
        Map<String, dynamic>.from(baseline['revisions'] as Map? ?? {});
    final changes = <Map<String, dynamic>>[];
    for (final id in {...oldRows.keys, ...local.keys}) {
      if (_same(local[id], oldRows[id])) continue;
      changes.add({
        'id': id,
        'revision': oldRevisions[id] ?? 0,
        'deleted': !local.containsKey(id),
        'payload': local[id]
      });
    }
    Map<String, dynamic>? responseData;
    final conflicts = <String>{};
    // Small batches keep long-standing archives within the request size limit.
    final batches = changes.isEmpty ? 1 : (changes.length / 50).ceil();
    for (var batch = 0; batch < batches; batch++) {
      await _ensure(uid, scope);
      final response = await scope.post('/api/fortune/archives/sync', data: {
        'collection': collection,
        'changes': changes.skip(batch * 50).take(50).toList(),
      });
      final payload = response.data;
      if (payload is! Map || payload['code'] != 0 || payload['data'] is! Map) {
        throw const FormatException('云端档案响应异常');
      }
      responseData = Map<String, dynamic>.from(payload['data'] as Map);
      if (responseData['items'] is! List ||
          responseData['conflicts'] is! List) {
        throw const FormatException('云端档案响应异常');
      }
      conflicts.addAll((responseData['conflicts'] as List).cast<String>());
    }
    final remote = <String, dynamic>{};
    final revisions = <String, dynamic>{};
    final conflictRows = <String, dynamic>{};
    for (final item in responseData!['items'] as List) {
      if (item is! Map ||
          item['id'] is! String ||
          item['revision'] is! int ||
          item['deleted'] is! bool ||
          (item['deleted'] != true && item['payload'] is! Map)) {
        throw const FormatException('云端档案格式异常');
      }
      final id = item['id'] as String;
      if (conflicts.contains(id)) conflictRows[id] = item;
      revisions[id] = item['revision'];
      if (item['deleted'] != true) remote[id] = item['payload'];
    }
    final merged = {...remote};
    // A stale device may not overwrite a newer edit or resurrect a deletion.
    // Keep its unsynced local edit and original revision until explicitly resolved.
    for (final id in conflicts) {
      if (local.containsKey(id)) {
        merged[id] = local[id];
      } else {
        merged.remove(id);
      }
      revisions[id] = oldRevisions[id] ?? 0;
      if (oldRows.containsKey(id)) {
        remote[id] = oldRows[id];
      } else {
        remote.remove(id);
      }
    }
    final encoded = _encode(collection, merged);
    _rows(collection, encoded);
    await _ensure(uid, scope);
    await _writeLocal(collection, encoded, uid, scope);
    await _ensure(uid, scope);
    if (!await prefs.setString(
        stateKey,
        jsonEncode({
          'rows': remote,
          'revisions': revisions,
          'conflicts': conflictRows
        }))) {
      throw StateError('同步状态保存失败');
    }
    _state(scope, collection, conflicts.isEmpty ? 'synced' : 'conflict');
  }
}

class _ArchiveMutation {
  const _ArchiveMutation(this.collection, this.uid, this.scope);
  final String collection;
  final int uid;
  final ApiSessionScope scope;
}

class _ArchiveLifecycle with WidgetsBindingObserver {
  _ArchiveLifecycle() {
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(() {
      ArchiveCloudSync.status.value = {};
      unawaited(ArchiveCloudSync.syncAll());
    });
    Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(ArchiveCloudSync.syncAll());
      }
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ArchiveCloudSync.syncAll());
    }
  }
}

class ArchiveSyncNotice extends StatelessWidget {
  const ArchiveSyncNotice({super.key, this.onChanged});
  final Future<void> Function()? onChanged;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, String>>(
          valueListenable: ArchiveCloudSync.status,
          builder: (_, value, __) {
            final message = ArchiveCloudSync.message;
            if (message == null) return const SizedBox.shrink();
            return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                      child: Text(message,
                          style: Theme.of(context).textTheme.bodySmall)),
                  TextButton(
                      onPressed: () async {
                        final scope = ApiSessionScope();
                        try {
                          if (!value.values.contains('conflict')) {
                            await ArchiveCloudSync.syncAll();
                            if (scope.current) await onChanged?.call();
                            return;
                          }
                          final choice = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                      title: const Text('选择案例版本'),
                                      content: const Text(
                                          '同一案例在不同设备上有修改。选择保留本机修改，或使用云端版本；其余案例不受影响。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('取消')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('使用云端版本')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('保留本机修改')),
                                      ]));
                          if (choice != null && scope.current) {
                            await ArchiveCloudSync.resolveConflicts(
                                useLocal: choice);
                            if (scope.current) await onChanged?.call();
                          }
                        } catch (_) {
                          if (context.mounted && scope.current) {
                            showAppToast(context, '同步未完成，本地案例已保留');
                          }
                        }
                      },
                      child:
                          Text(value.values.contains('conflict') ? '处理' : '重试'))
                ]));
          });
}
