import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'archive_account_scope.dart';
import 'archive_cloud_sync.dart';
import '../network/api_client.dart';
import '../../features/fortune/archive_relationship.dart';
import '../../features/fortune/paipan/models/paipan_record.dart';

/// 命理档案本地存储：八字排盘记录存于应用文档目录的 JSON 文件
class PaipanRecordStore {
  static const String _fileName = 'paipan_records.json';
  static const String _contextDirName = 'paipan_contexts';
  static Future<void>? _saveQueue;

  static Future<Directory?> _getContextDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return ArchiveAccountScope.scopedDirectory(
      parent: dir,
      baseName: _contextDirName,
    );
  }

  static Future<File?> _getContextFile(String id) async {
    final dir = await _getContextDir();
    if (dir == null) return null;
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}/$safeId.txt');
  }

  /// 加载全部记录（按创建时间倒序）
  static Future<List<PaipanRecord>> loadAll() async {
    try {
      final content = await ArchiveCloudSync.read(ArchiveCloudSync.bazi);
      if (content == null) return [];
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>?;
      if (list == null || list.isEmpty) return [];
      final records = list
          .map((e) => PaipanRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 保存新记录
  static Future<void> save(PaipanRecord record, {int? expectedUserId}) async {
    await _mutate<void>((list) {
      var index = -1;
      if (record.isSelf) {
        index = list.indexWhere((item) => item.isSelf);
        if (index < 0) {
          index = list.indexWhere(
            (item) => item.isLegacySelf && _sameBirth(item, record),
          );
        }
      } else {
        index = list.indexWhere(
          (item) =>
              !item.isSelf &&
              item.displayName.trim().toLowerCase() ==
                  record.displayName.trim().toLowerCase() &&
              item.relationship == record.relationship &&
              _sameBirth(item, record),
        );
      }
      final saved = index < 0 ? record : _merge(list[index], record);
      if (index >= 0) list.removeAt(index);
      if (record.isSelf) {
        list.removeWhere((item) => item.isSelf && item.id != saved.id);
      }
      list.insert(0, saved);
    }, expectedUserId: expectedUserId);
  }

  /// 所有主档修改共用队列、严格读取、固定账号及原子替换。
  /// loadAll 的空态只供展示，绝不能作为保存时的读取结果。
  static Future<T> _mutate<T>(
    T Function(List<PaipanRecord>) change, {
    int? expectedUserId,
  }) async {
    final session = apiSessionChanges.value;
    final userId = await ArchiveAccountScope.currentUserId();
    if (userId == null ||
        (expectedUserId != null && userId != expectedUserId)) {
      throw StateError('档案所属账号已变更，请重新操作');
    }
    Future<void> ensureOwner() async {
      if (session != apiSessionChanges.value ||
          await ArchiveAccountScope.currentUserId() != userId ||
          session != apiSessionChanges.value) {
        throw StateError('档案所属账号已变更，请重新操作');
      }
    }

    Future<T> perform() async {
      await ensureOwner();
      final dir = await getApplicationDocumentsDirectory();
      await ensureOwner();
      final file = File('${dir.path}/paipan_records_user_$userId.json');
      final resolved = await ArchiveAccountScope.scopedFile(
        directory: dir,
        baseName: _fileName,
      );
      await ensureOwner();
      if (resolved == null || resolved.path != file.path) {
        throw StateError('档案所属账号已变更，请重新操作');
      }
      final existed = await file.exists();
      final original = existed ? await file.readAsString() : null;
      final decoded = original == null ? <dynamic>[] : jsonDecode(original);
      if (decoded is! List) throw const FormatException('档案文件格式异常');
      final list = decoded
          .map(
            (item) =>
                PaipanRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      final before = {
        for (final item in list) item.id: jsonEncode(item.toJson()),
      };
      final unchanged = jsonEncode(list.map((item) => item.toJson()).toList());
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await ensureOwner();
      final result = change(list);
      final encoded = jsonEncode(list.map((item) => item.toJson()).toList());
      if (encoded == unchanged) return result;
      final staging = await dir.createTemp('.paipan-save-');
      try {
        final replacement = File('${staging.path}/records.json');
        await replacement.writeAsString(encoded, flush: true);
        await ensureOwner();
        // 只备份成功解析的原文，损坏文件从不被空列表或新笔记覆盖。
        if (original != null) {
          final backup = File('${staging.path}/previous.json');
          await backup.writeAsString(original, flush: true);
          await ensureOwner();
          await backup.rename('${file.path}.backup');
        }
        await ensureOwner();
        await replacement.rename(file.path);
      } finally {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
      // 上下文只是可再生缓存。用固定账号目录，不再重新解析当前账号。
      try {
        final contextDir = Directory(
          '${dir.path}/${_contextDirName}_user_$userId',
        );
        await contextDir.create(recursive: true);
        File context(String id) => File(
              '${contextDir.path}/${id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.txt',
            );
        for (final item in list) {
          if (before[item.id] != jsonEncode(item.toJson())) {
            await context(item.id)
                .writeAsString(item.toAiContextBlock(), flush: true);
          }
        }
        final remaining = list.map((item) => item.id).toSet();
        for (final id in before.keys.where((id) => !remaining.contains(id))) {
          final stale = context(id);
          if (await stale.exists()) await stale.delete();
        }
      } catch (_) {}
      return result;
    }

    final previous = _saveQueue;
    final completion = Completer<void>();
    _saveQueue = completion.future;
    try {
      if (previous != null) await previous;
      return await ArchiveCloudSync.mutateBazi<T>(perform,
          expectedUserId: userId);
    } finally {
      if (identical(_saveQueue, completion.future)) _saveQueue = null;
      completion.complete();
    }
  }

  static bool _sameBirth(PaipanRecord a, PaipanRecord b) =>
      a.birthDateTime.year == b.birthDateTime.year &&
      a.birthDateTime.month == b.birthDateTime.month &&
      a.birthDateTime.day == b.birthDateTime.day &&
      a.birthDateTime.hour == b.birthDateTime.hour &&
      a.birthDateTime.minute == b.birthDateTime.minute &&
      a.isFemale == b.isFemale;

  static PaipanRecord _merge(PaipanRecord existing, PaipanRecord incoming) =>
      PaipanRecord(
        id: existing.id,
        createdAt: existing.createdAt,
        displayName: incoming.displayName,
        isSelf: incoming.isSelf,
        relationship: incoming.relationship,
        birthDateTime: incoming.birthDateTime,
        isFemale: incoming.isFemale,
        calendarTypeIndex: incoming.calendarTypeIndex,
        birthPlace: incoming.birthPlace,
        summary: incoming.summary,
        caseTitle: existing.caseTitle,
        reasoningNotes: existing.reasoningNotes,
        commentary: existing.commentary,
        caseUpdatedAt: existing.caseUpdatedAt,
      );

  /// 将与账号出生资料一致的最新旧“本人”记录安全认领为唯一本人档案。
  /// 其他旧记录保留为待整理，不进行删除或覆盖。
  static Future<void> claimSelfProfile({
    required DateTime birthDateTime,
    required bool isFemale,
    required String nickname,
  }) async {
    await _mutate<void>((list) {
      final safeName = nickname.trim().isEmpty ? '我的八字' : nickname.trim();
      var index = list.indexWhere((item) => item.isSelf);
      index = index >= 0
          ? index
          : list.indexWhere(
              (item) =>
                  item.isLegacySelf &&
                  item.isFemale == isFemale &&
                  item.birthDateTime.year == birthDateTime.year &&
                  item.birthDateTime.month == birthDateTime.month &&
                  item.birthDateTime.day == birthDateTime.day &&
                  item.birthDateTime.hour == birthDateTime.hour,
            );
      if (index < 0) return;
      final current = list[index];
      list[index] = current.copyWith(
        displayName: safeName,
        isSelf: true,
        relationship: ArchiveRelationship.self,
      );
      for (var i = 0; i < list.length; i++) {
        if (i != index && list[i].isSelf) {
          list[i] = list[i].copyWith(
            isSelf: false,
            relationship: ArchiveRelationship.legacy,
          );
        }
      }
    });
  }

  static Future<void> updateIdentity(
    String id, {
    required String displayName,
    required String relationship,
  }) async {
    await _mutate<void>((list) {
      final index = list.indexWhere((item) => item.id == id);
      if (index < 0 || list[index].isSelf) return;
      list[index] = list[index].copyWith(
        displayName: displayName.trim(),
        relationship: relationship,
        isSelf: false,
      );
    });
  }

  /// 删除指定记录
  static Future<void> delete(String id, {int? expectedUserId}) async {
    await _mutate<void>(
      (list) => list.removeWhere((item) => item.id == id),
      expectedUserId: expectedUserId,
    );
  }

  /// 修改命主姓名
  static Future<void> updateDisplayName(String id, String displayName) async {
    await _mutate<void>((list) {
      final i = list.indexWhere((r) => r.id == id);
      if (i < 0) return;
      list[i] = list[i].copyWith(displayName: displayName);
    });
  }

  /// 将排盘记录保存为可继续编辑的案例。
  ///
  /// 优先按 [recordId] 更新；从旧档案打开且没有 id 时，再按出生信息与四柱定位。
  static Future<PaipanRecord> saveCase({
    required String? recordId,
    required PaipanRecord fallback,
    required String caseTitle,
    required String reasoningNotes,
    required String commentary,
    int? expectedUserId,
  }) async {
    return _mutate<PaipanRecord>((list) {
      var index = recordId == null
          ? -1
          : list.indexWhere((record) => record.id == recordId);
      if (index < 0) {
        index = list.indexWhere(
          (record) =>
              record.birthDateTime == fallback.birthDateTime &&
              record.isFemale == fallback.isFemale &&
              record.summary == fallback.summary,
        );
      }
      final now = DateTime.now();
      final base = index >= 0 ? list[index] : fallback;
      final saved = base.copyWith(
        caseTitle: caseTitle.trim(),
        reasoningNotes: reasoningNotes.trim(),
        commentary: commentary.trim(),
        caseUpdatedAt: now,
      );
      if (index >= 0) {
        list[index] = saved;
      } else {
        list.insert(0, saved);
      }
      return saved;
    }, expectedUserId: expectedUserId);
  }

  static Future<PaipanRecord?> findForChart({
    String? recordId,
    required DateTime birthDateTime,
    required bool isFemale,
    required String summary,
  }) async {
    final list = await loadAll();
    if (recordId != null) {
      final byId = list.where((record) => record.id == recordId);
      if (byId.isNotEmpty) return byId.first;
    }
    final matches = list.where(
      (record) =>
          record.birthDateTime == birthDateTime &&
          record.isFemale == isFemale &&
          record.summary == summary,
    );
    return matches.isEmpty ? null : matches.first;
  }

  /// 根据当前档案生成 AI 原文，避免云端恢复后读到旧笔记缓存。
  static Future<String> loadAiContext(PaipanRecord record) async {
    final generated = record.toAiContextBlock();
    if (generated.trim().isNotEmpty) {
      try {
        final file = await _getContextFile(record.id);
        if (file != null) {
          await file.writeAsString(generated, flush: true);
        }
      } catch (_) {}
    }
    return generated;
  }

  /// 返回 AI 档案原文 txt 路径（若文件不存在会先生成）。
  static Future<String> getAiContextFilePath(PaipanRecord record) async {
    final file = await _getContextFile(record.id);
    if (file == null) return '';
    final content = record.toAiContextBlock();
    if (content.trim().isNotEmpty) {
      await file.writeAsString(content, flush: true);
    }
    return file.path;
  }
}
