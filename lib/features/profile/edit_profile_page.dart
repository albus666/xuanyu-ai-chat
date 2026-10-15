import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/profile/account_birth_profile.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_text_styles.dart';
import '../fortune/paipan/widgets/birth_date_picker_sheet.dart';
import '../fortune/paipan/models/region.dart';
import '../fortune/paipan/utils/region_loader.dart';
import '../fortune/paipan/widgets/birth_place_picker_sheet.dart';
import '../fortune/fortune_preload_coordinator.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../virtual_goods/virtual_avatar_studio_page.dart';
import 'constitution_setting_page.dart' show kConstitutionOptions;

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    this.initialNickname = '',
    this.initialAvatarUrl,
    this.initialIntro = '',
    this.initialBirthDate,
    this.initialBirthTime,
    this.initialBirthPlace,
    this.initialBirthLongitude,
    this.initialBirthLatitude,
    this.initialBirthEditRemaining = 2,
    this.initialGender,
    this.initialConstitution,
  });

  final String initialNickname;
  final String? initialAvatarUrl;
  final String initialIntro;
  final String? initialBirthDate;
  final String? initialBirthTime;
  final String? initialBirthPlace;
  final double? initialBirthLongitude;
  final double? initialBirthLatitude;
  final int initialBirthEditRemaining;
  final int? initialGender; // 1男 2女
  final String? initialConstitution; // 中医体质，须为 kConstitutionOptions 之一

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _nicknameController;
  late TextEditingController _introController;
  String? _avatarUrl;
  String? _birthDate;
  String? _birthTime;
  Region? _birthPlace;
  int? _gender;
  String? _constitution;
  bool _loading = false;
  late int _birthEditRemaining;

  void _setBusy({bool? loading}) {
    if (!mounted) return;
    setState(() {
      if (loading != null) _loading = loading;
    });
  }

  void _toast(String message) => showAppBottomToast(context, message);

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.initialNickname);
    _introController = TextEditingController(text: widget.initialIntro);
    _avatarUrl = widget.initialAvatarUrl;
    _birthDate = widget.initialBirthDate;
    _birthTime = widget.initialBirthTime;
    final place = widget.initialBirthPlace?.trim() ?? '';
    if (place.isNotEmpty) {
      _birthPlace = Region.placeholder(
        name: place.split(RegExp(r'\s+')).last,
        extPath: place,
        lng: widget.initialBirthLongitude,
        lat: widget.initialBirthLatitude,
      );
    }
    RegionLoader.preload();
    _birthEditRemaining = widget.initialBirthEditRemaining.clamp(0, 2);
    _gender = widget.initialGender;
    _constitution = widget.initialConstitution;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _introController.dispose();
    super.dispose();
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
          _toast('出生时间不能晚于当前时间');
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

  bool get _hasCompleteBirthProfile =>
      (_birthDate ?? '').isNotEmpty && (_birthTime ?? '').isNotEmpty;

  String get _birthDateTimeText =>
      _hasCompleteBirthProfile ? '${_birthDate!}  ${_birthTime!}' : '请选择';

  Future<void> _editBirth(Future<void> Function() picker) async {
    if (!_hasCompleteBirthProfile) {
      await picker();
      return;
    }
    if (_birthEditRemaining <= 0) {
      _toast('出生日期和时辰最多只能修改两次，当前已无法继续修改');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请确认出生资料'),
        content: Text(
          '出生日期和时辰用于八字匹配，保存变更后将消耗一次修改机会。当前还可修改 $_birthEditRemaining 次。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续修改'),
          ),
        ],
      ),
    );
    if (confirmed == true) await picker();
  }

  Future<void> _pickConstitution() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('选择中医体质', style: AppTextStyles.titleSmall),
              ),
              Expanded(
                child: ListView(
                  children: kConstitutionOptions.map((option) {
                    final isSelected = _constitution == option;
                    return ListTile(
                      title: Text(option,
                          style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected ? FontWeight.w600 : null)),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary)
                          : null,
                      onTap: () {
                        setState(() => _constitution = option);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthPlace() async {
    await BirthPlacePickerSheet.show(
      context,
      title: '出生地',
      initialRegion: _birthPlace,
      onConfirm: (region) => setState(() => _birthPlace = region),
    );
  }

  Future<void> _pickImage() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VirtualAvatarStudioPage(initialGender: _gender),
      ),
    );
    if (url != null && mounted) setState(() => _avatarUrl = url);
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      _toast('请先填写昵称');
      return;
    }
    _setBusy(loading: true);
    try {
      final response = await apiClient.patch('/api/auth/updateProfile', data: {
        'nickname': nickname,
        'intro': _introController.text.trim(),
        'birthDate': _birthDate,
        'birthTime': _birthTime,
        if (_birthPlace != null) ...{
          'birthPlace': _birthPlace!.extPath,
          'birthLongitude': _birthPlace!.lng,
          'birthLatitude': _birthPlace!.lat,
          'birthTimezone': 'Asia/Shanghai',
        },
        'gender': _gender,
        'constitution': _constitution,
      });
      final responseData = (response.data as Map?)?['data'] as Map?;
      await AccountBirthProfileRepository.invalidateCurrent();
      FortunePreloadCoordinator.schedule(
        delay: Duration.zero,
        forceProfileRefresh: true,
      );
      final remaining = (responseData?['birthEditRemaining'] as num?)?.toInt();
      if (remaining != null) {
        _birthEditRemaining = remaining.clamp(0, 2);
      }
      _setBusy(loading: false);
      _toast(
        _hasCompleteBirthProfile
            ? '保存成功，出生资料还可修改 $_birthEditRemaining 次'
            : '保存成功',
      );
      if (mounted) Navigator.pop(context, true);
      // 体质变更后由首页 onConstitutionChanged 触发直接请求今日养生并更新 UI，再写缓存，此处不再单独写缓存
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      _setBusy(loading: false);
      if (mounted) _toast(msg?.isNotEmpty == true ? msg! : '保存失败，请重试');
    } catch (_) {
      _setBusy(loading: false);
      if (mounted) _toast('保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('编辑个人资料', style: AppTextStyles.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: AppButton(
                label: '保存',
                width: 70,
                height: 36,
                isFullWidth: false,
                loading: _loading,
                onPressed: _save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildAvatarSection(),
            const SizedBox(height: 40),
            _buildFormSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.cardBackground,
                backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                    ? NetworkImage(_avatarUrl!)
                    : null,
                child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                    ? const Icon(Icons.person_rounded,
                        size: 50, color: AppColors.textHint)
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.face_retouching_natural_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 15,
                offset: const Offset(0, 8))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
              label: '个性昵称', controller: _nicknameController, hint: '起个响亮的名字'),
          const SizedBox(height: 24),
          _buildGenderSelector(),
          const SizedBox(height: 24),
          _buildInfoTile(
            '出生日期时辰',
            _birthDateTimeText,
            Icons.calendar_today_rounded,
            () => _editBirth(_pickBirthDateTime),
          ),
          const SizedBox(height: 7),
          Text(
            '本人资料全局通用，八字、斗数、每日养生等功能会自动使用',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 5),
          Text(
            _hasCompleteBirthProfile
                ? (_birthEditRemaining > 0
                    ? '出生资料还可修改 $_birthEditRemaining 次，请核对准确后再保存'
                    : '出生资料已达到修改上限，不可再次修改')
                : '首次完整填写不计修改次数，之后最多可修改两次',
            style: AppTextStyles.bodySmall.copyWith(
              color: _birthEditRemaining > 0
                  ? AppColors.textHint
                  : AppColors.error,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoTile(
            '出生地',
            _birthPlace == null
                ? '请选择（星盘必填）'
                : _birthPlace!.extPath.replaceAll(' ', ' / '),
            Icons.location_on_outlined,
            _pickBirthPlace,
          ),
          const SizedBox(height: 7),
          Text(
            '用于准确换算星盘的上升、宫位与相位，不会展示给其他用户',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 20),
          _buildInfoTile('中医体质', _constitution ?? '请选择', Icons.favorite_rounded,
              _pickConstitution),
          const SizedBox(height: 24),
          AppTextField(
              label: '个人简介',
              controller: _introController,
              hint: '介绍一下自己吧...',
              suffixIcon: IconButton(
                  tooltip: '清空个人简介',
                  onPressed: _introController.clear,
                  icon: const Icon(Icons.clear_rounded)),
              maxLines: 3),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('您的性别',
            style: AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Row(
          children: [
            _genderOption(1, '男士', Icons.male_rounded, const Color(0xFFEFF6FF),
                const Color(0xFF2563EB)),
            const SizedBox(width: 16),
            _genderOption(2, '女士', Icons.female_rounded,
                const Color(0xFFFFF1F2), const Color(0xFFE11D48)),
          ],
        ),
      ],
    );
  }

  Widget _genderOption(
      int val, String label, IconData icon, Color bg, Color active) {
    bool isSelected = _gender == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = val),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? active : bg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: active.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : active),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: isSelected ? Colors.white : active,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
      String label, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(value,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: value == '请选择'
                            ? AppColors.textHint
                            : AppColors.textPrimary)),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textHint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
