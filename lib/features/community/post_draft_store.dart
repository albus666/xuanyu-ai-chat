import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 普通草稿与未完成发布分开保存；一次发布结束不能清掉后来新建的草稿。
class PostDraftStore {
  PostDraftStore(this.ownerId);

  final int? ownerId;
  String get storageKey => 'community_drafts_v3_${ownerId ?? 'guest'}';
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _queue;

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  static Map<String, dynamic> copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  static bool hasContent(Map draft) =>
      (draft['content']?.toString().trim().isNotEmpty ?? false) ||
      (draft['images'] is List && (draft['images'] as List).isNotEmpty) ||
      draft['video'] != null ||
      draft['audio'] != null ||
      (draft['location']?.toString().trim().isNotEmpty ?? false) ||
      draft['component'] != null;

  Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    if (raw == null) return {'pending': <String, dynamic>{}};
    // 损坏的存档不能按空白覆盖，保留原始数据以便恢复。
    final value = jsonDecode(raw);
    if (value is! Map || value['pending'] is! Map) {
      throw const FormatException('草稿存档读取失败');
    }
    return copy(value);
  }

  Future<T> _change<T>(Future<T> Function(Map<String, dynamic>) change) {
    final result = (_queue ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final state = _read(prefs);
      final hadMedia = _hasMedia(state);
      final value = await change(state);
      if (!await prefs.setString(storageKey, jsonEncode(state))) {
        throw const FileSystemException('草稿保存失败，请检查剩余空间');
      }
      // 只有记录成功落盘后才回收本账号草稿区内不再引用的副本。
      // 不触碰相册原文件、其他账号或仍在发布的附件。
      if (hadMedia || _hasMedia(state)) {
        try {
          await _collectUnusedMedia(state);
        } catch (_) {}
      }
      changes.value++;
      return value;
    });
    late final Future<void> queued;
    void release() {
      if (identical(_queue, queued)) _queue = null;
    }

    queued = result.then<void>((_) => release(),
        onError: (Object _, StackTrace __) => release());
    _queue = queued;
    return result;
  }

  Future<Map<String, dynamic>?> active() async {
    await _queue;
    final value = _read(await SharedPreferences.getInstance())['active'];
    return value is Map ? copy(value) : null;
  }

  Future<List<Map<String, dynamic>>> pending() async {
    await _queue;
    final state = _read(await SharedPreferences.getInstance());
    final result =
        (state['pending'] as Map).values.whereType<Map>().map(copy).toList();
    result.sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));
    return result;
  }

  Future<Map<String, dynamic>> save(Map<String, dynamic> snapshot) {
    final captured = copy(snapshot);
    return _change((state) async {
      final pending = (state['pending'] as Map)[captured['id']];
      if (pending is Map) return copy(pending);
      if (hasContent(captured)) {
        final saved = await _keepMedia(captured);
        state['active'] = saved;
        return copy(saved);
      } else if ((state['active'] as Map?)?['id'] == captured['id']) {
        state.remove('active');
      }
      return captured;
    });
  }

  Future<void> discard(String id) => _change((state) async {
        if ((state['active'] as Map?)?['id'] == id) state.remove('active');
      });

  Future<Map<String, dynamic>> stage(Map<String, dynamic> snapshot) {
    final captured = copy(snapshot);
    return _change((state) async {
      final ready = await _keepMedia(captured);
      ready['status'] = 'queued';
      (state['pending'] as Map)[ready['id']] = ready;
      if ((state['active'] as Map?)?['id'] == ready['id']) {
        state.remove('active');
      }
      return copy(ready);
    });
  }

  Future<void> mark(String id, String status, {String? error}) =>
      _change((state) async {
        final pending = state['pending'] as Map;
        final value = pending[id];
        if (value is Map) {
          value['status'] = status;
          value['error'] = error;
        }
      });

  Future<void> complete(String id) => _change((state) async {
        (state['pending'] as Map).remove(id);
      });

  /// 恢复任务前先保留当前编辑稿，避免“恢复”覆盖用户新写的内容。
  Future<Map<String, dynamic>> recover(
      String id, Map<String, dynamic> current) {
    final captured = copy(current);
    return _change((state) async {
      final pending = state['pending'] as Map;
      final selected = pending[id];
      if (selected is! Map) throw StateError('这条发布记录已处理');
      if (hasContent(captured) && captured['id'] != id) {
        final saved = await _keepMedia(captured);
        saved['status'] = 'saved';
        pending[saved['id']] = saved;
      }
      final restored = copy(selected)..remove('error');
      restored['status'] = 'draft';
      state['active'] = restored;
      pending.remove(id);
      return copy(restored);
    });
  }

  Future<void> _collectUnusedMedia(Map<String, dynamic> state) async {
    final base = await getApplicationSupportDirectory();
    final directory =
        Directory('${base.path}/post_drafts/${ownerId ?? 'guest'}/media');
    if (!await directory.exists()) return;
    final referenced = <String>{};
    for (final draft in [state['active'], ...(state['pending'] as Map).values]
        .whereType<Map>()) {
      referenced.addAll(((draft['images'] as List?) ?? [])
          .whereType<String>()
          .map((p) => File(p).absolute.path));
      for (final key in ['video', 'audio']) {
        if (draft[key] is String) {
          referenced.add(File(draft[key] as String).absolute.path);
        }
      }
    }
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          RegExp(r'^[a-f0-9]{64}\.[a-zA-Z0-9]{1,8}$').hasMatch(name) &&
          !referenced.contains(entity.absolute.path)) {
        await entity.delete();
      }
    }
  }

  bool _hasMedia(Map<String, dynamic> state) => [
        state['active'],
        ...(state['pending'] as Map).values
      ].whereType<Map>().any((draft) =>
          ((draft['images'] as List?)?.isNotEmpty ?? false) ||
          draft['video'] != null ||
          draft['audio'] != null);

  Future<Map<String, dynamic>> _keepMedia(Map<String, dynamic> draft) async {
    draft['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final paths = <String>[
      ...((draft['images'] as List?) ?? []).whereType<String>(),
      if (draft['video'] is String) draft['video'] as String,
      if (draft['audio'] is String) draft['audio'] as String,
    ];
    if (paths.isEmpty) return draft;
    final base = await getApplicationSupportDirectory();
    final directory =
        Directory('${base.path}/post_drafts/${ownerId ?? 'guest'}/media');
    await directory.create(recursive: true);
    final kept = <String, String>{};
    for (final path in paths) {
      final file = File(path);
      // 保留失效引用，并由发布前完整性校验提示重选，不能静默丢掉附件。
      if (!await file.exists()) {
        kept[path] = path;
        continue;
      }
      if (file.absolute.path.startsWith('${directory.absolute.path}/')) {
        kept[path] = path;
        continue;
      }
      final hash = await sha256.bind(file.openRead()).first;
      final extension =
          RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(path)?.group(0) ?? '.bin';
      final target = File('${directory.path}/$hash$extension');
      if (!await target.exists()) {
        final temporary = await file.copy('${target.path}.${newId()}.part');
        await temporary.rename(target.path);
      }
      kept[path] = target.path;
    }
    draft['images'] = [
      for (final path in (draft['images'] as List?) ?? []) kept[path] ?? path
    ];
    if (draft['video'] != null) {
      draft['video'] = kept[draft['video']] ?? draft['video'];
    }
    if (draft['audio'] != null) {
      draft['audio'] = kept[draft['audio']] ?? draft['audio'];
    }
    return draft;
  }
}
