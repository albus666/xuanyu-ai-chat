import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/local/archive_account_scope.dart';
import '../../core/local/archive_cloud_sync.dart';
import '../../core/utils/app_toast.dart';
import '../fortune/paipan/models/region.dart';
import '../fortune/paipan/utils/region_loader.dart';
import '../fortune/paipan/widgets/birth_place_picker_sheet.dart';

/// 房间共用案例的补充资料，按登录账号和原始档案 ID 保存，不改账号出生资料。
class RoomChartCaseDetailsStore {
  static const _key = 'room_chart_case_details_v1';

  static Future<Map<String, dynamic>> load() async {
    final value = await ArchiveAccountScope.readJson(_key);
    if (value == null || value.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  static Future<void> save(
    Iterable<String> sourceKeys,
    Map<String, dynamic> details, {
    required int expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final prefs = await SharedPreferences.getInstance();
      if (await ArchiveAccountScope.currentUserId(prefs) != expectedUserId) {
        throw StateError('账号已变更，请重新打开命盘');
      }
      final raw = await ArchiveAccountScope.readJson(_key);
      final rows = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final key in sourceKeys) {
        final previous = rows[key];
        rows[key] = <String, dynamic>{
          if (previous is Map) ...Map<String, dynamic>.from(previous),
          ...details,
        };
      }
      if (!await ArchiveAccountScope.writeJson(_key, jsonEncode(rows),
          expectedUserId: expectedUserId)) {
        throw StateError('资料保存失败');
      }
    }, expectedUserId: expectedUserId);
  }

  static Future<void> delete(
    Iterable<String> sourceKeys, {
    required int expectedUserId,
  }) async {
    return ArchiveCloudSync.mutateJson(_key, () async {
      final prefs = await SharedPreferences.getInstance();
      if (await ArchiveAccountScope.currentUserId(prefs) != expectedUserId) {
        throw StateError('账号已变更，请重新打开命盘');
      }
      final raw = await ArchiveAccountScope.readJson(_key);
      if (raw == null || raw.isEmpty) return;
      final rows = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final key in sourceKeys) {
        rows.remove(key);
      }
      if (await ArchiveAccountScope.currentUserId(prefs) != expectedUserId) {
        throw StateError('账号已变更，请重新打开命盘');
      }
      if (!await ArchiveAccountScope.writeJson(_key, jsonEncode(rows),
          expectedUserId: expectedUserId)) {
        throw StateError('资料删除失败');
      }
    }, expectedUserId: expectedUserId);
  }
}

class RoomChartCaseDetailsDialog extends StatefulWidget {
  const RoomChartCaseDetailsDialog({super.key, this.isFemale, this.place});
  final bool? isFemale;
  final Region? place;

  @override
  State<RoomChartCaseDetailsDialog> createState() => _DetailsState();
}

class _DetailsState extends State<RoomChartCaseDetailsDialog> {
  bool? _isFemale;
  Region? _place;

  @override
  void initState() {
    super.initState();
    _isFemale = widget.isFemale;
    _place = widget.place;
    RegionLoader.preload();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('补全案例资料'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('性别'),
              const Spacer(),
              ChoiceChip(
                label: const Text('男'),
                selected: _isFemale == false,
                onSelected: widget.isFemale == null
                    ? (_) => setState(() => _isFemale = false)
                    : null,
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('女'),
                selected: _isFemale == true,
                onSelected: widget.isFemale == null
                    ? (_) => setState(() => _isFemale = true)
                    : null,
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('出生地'),
            subtitle: Text(_place?.extPath ?? '请选择出生地'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.place == null
                ? () async {
                    await BirthPlacePickerSheet.show(
                      context,
                      title: '出生地',
                      initialRegion: _place,
                      onConfirm: (value) {
                        if (mounted) setState(() => _place = value);
                      },
                    );
                  }
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_isFemale == null || _place?.lng == null || _place?.lat == null) {
            showAppToast(context, '请选择性别和出生地');
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            'isFemale': _isFemale,
            'birthPlace': _place!.extPath,
            'longitude': _place!.lng,
            'latitude': _place!.lat,
          });
        },
        child: const Text('保存并查看'),
      ),
    ],
  );
}
