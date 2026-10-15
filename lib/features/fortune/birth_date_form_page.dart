import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/profile/account_birth_profile.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import 'fortune_preload_coordinator.dart';
import 'paipan/widgets/birth_date_picker_sheet.dart';
import 'paipan/models/region.dart';
import 'paipan/utils/region_loader.dart';
import 'paipan/widgets/birth_place_picker_sheet.dart';

/// 统一补充账号本人的性别、出生日期与时辰。
class BirthDateFormPage extends StatefulWidget {
  const BirthDateFormPage({
    super.key,
    this.initialBirthDate,
    this.initialBirthTime,
    this.initialGender,
    this.initialBirthPlace,
    this.requireBirthPlace = false,
    this.onlyBirthPlace = false,
    this.reason = '用于本人八字、斗数等功能',
  });

  final String? initialBirthDate;
  final String? initialBirthTime;
  final int? initialGender;
  final Region? initialBirthPlace;
  final bool requireBirthPlace;
  final bool onlyBirthPlace;
  final String reason;

  @override
  State<BirthDateFormPage> createState() => _BirthDateFormPageState();
}

class _BirthDateFormPageState extends State<BirthDateFormPage> {
  String? _birthDate;
  String? _birthTime;
  int? _gender;
  Region? _birthPlace;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _birthDate = widget.initialBirthDate;
    _birthTime = widget.initialBirthTime;
    _gender = widget.initialGender;
    _birthPlace = widget.initialBirthPlace;
    if (widget.requireBirthPlace) RegionLoader.preload();
  }

  DateTime get _birthDateTime {
    final date = DateTime.tryParse((_birthDate ?? '').trim());
    final parts = (_birthTime ?? '').split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts.first) ?? 12 : 12;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final base = date ?? DateTime(2000, 1, 1);
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  Future<void> _pickBirthDateTime() async {
    await BirthDatePickerSheet.show(
      context,
      initialDate: _birthDateTime,
      onConfirm: (picked) {
        if (picked.isAfter(DateTime.now())) {
          showAppToast(context, '出生时间不能晚于当前时间');
          return;
        }
        setState(() {
          _birthDate =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          _birthTime =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        });
      },
    );
  }

  Future<void> _save() async {
    if ((_birthDate ?? '').isEmpty || (_birthTime ?? '').isEmpty) {
      showAppToast(context, '请选择出生日期时辰');
      return;
    }
    if (_gender != 1 && _gender != 2) {
      showAppToast(context, '请选择性别');
      return;
    }
    if (widget.requireBirthPlace &&
        (_birthPlace == null ||
            _birthPlace!.lng == null ||
            _birthPlace!.lat == null)) {
      showAppToast(context, '请选择出生地，星盘不能使用猜测坐标');
      return;
    }
    setState(() => _saving = true);
    try {
      await apiClient.patch('/api/auth/updateProfile', data: {
        'birthDate': _birthDate,
        'birthTime': _birthTime,
        'gender': _gender,
        if (widget.requireBirthPlace) ...{
          'birthPlace': _birthPlace!.extPath,
          'birthLongitude': _birthPlace!.lng,
          'birthLatitude': _birthPlace!.lat,
          'birthTimezone': 'Asia/Shanghai',
        },
      });
      await AccountBirthProfileRepository.invalidateCurrent();
      FortunePreloadCoordinator.schedule(
        delay: Duration.zero,
        forceProfileRefresh: true,
      );
      if (mounted) {
        showAppToast(context, '保存成功');
        Navigator.of(context).pop(true);
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : '保存失败';
      if (mounted) showAppToast(context, msg ?? '保存失败');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.onlyBirthPlace ? '补充出生地' : '完善本人资料'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.reason),
              const SizedBox(height: 24),
              if (widget.onlyBirthPlace) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '出生资料已从本人档案读取',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_gender == 2 ? '女' : '男'} · ${_birthDate ?? ''}  ${_birthTime ?? ''}',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: _genderButton(1, '男')),
                    const SizedBox(width: 12),
                    Expanded(child: _genderButton(2, '女')),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickBirthDateTime,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '出生日期时辰',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    child: Text(
                      (_birthDate ?? '').isEmpty || (_birthTime ?? '').isEmpty
                          ? '点击选择'
                          : '$_birthDate  $_birthTime',
                      style: TextStyle(
                        color: (_birthDate ?? '').isNotEmpty &&
                                (_birthTime ?? '').isNotEmpty
                            ? null
                            : AppColors.textHint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.requireBirthPlace) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => BirthPlacePickerSheet.show(
                    context,
                    title: '出生地',
                    initialRegion: _birthPlace,
                    onConfirm: (region) => setState(() => _birthPlace = region),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '出生地',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    child: Text(
                      _birthPlace == null
                          ? '点击选择省 / 市 / 区县'
                          : _birthPlace!.extPath.replaceAll(' ', ' / '),
                      style: TextStyle(
                        color: _birthPlace == null ? AppColors.textHint : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '出生地只用于换算时区、上升与宫位，不会展示给其他用户',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
              Text(
                '保存后会自动同步到“我的资料”，以后无需重复填写',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(height: 32),
              AppButton(
                label: '保存',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _genderButton(int value, String label) {
    final selected = _gender == value;
    return OutlinedButton(
      onPressed: () => setState(() => _gender = value),
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? AppColors.primary.withValues(alpha: .08) : Colors.white,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.divider,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
