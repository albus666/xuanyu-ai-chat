import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/profile/account_birth_profile.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../fortune/fortune_preload_coordinator.dart';

/// 新用户三段式问卷：昵称、出生日期、简介，每步可跳过
class OnboardingQuestionnairePage extends StatefulWidget {
  const OnboardingQuestionnairePage({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<OnboardingQuestionnairePage> createState() =>
      _OnboardingQuestionnairePageState();
}

class _OnboardingQuestionnairePageState
    extends State<OnboardingQuestionnairePage> {
  final _pageController = PageController();
  final _nicknameController = TextEditingController();
  final _introController = TextEditingController();
  String? _birthDate;
  String? _birthTime;
  int? _gender; // 0未知 1男 2女
  int _currentStep = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    _introController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthTime() async {
    int hour = DateTime.now().hour;
    int minute = DateTime.now().minute;
    if (_birthTime != null && _birthTime!.isNotEmpty) {
      try {
        final p = _birthTime!.split(':');
        if (p.length >= 2) {
          hour = int.parse(p[0]);
          minute = int.parse(p[1]);
        }
      } catch (_) {}
    }
    final result = await showModalBottomSheet<DateTime?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimePickerSheet(
        initialHour: hour,
        initialMinute: minute,
        onConfirm: (h, m) => Navigator.pop(context, DateTime(2000, 1, 1, h, m)),
        onCancel: () => Navigator.pop(context, null),
      ),
    );
    if (result != null && mounted) {
      setState(() => _birthTime =
          '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _pickBirthDate() async {
    DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 25));
    if (_birthDate != null && _birthDate!.isNotEmpty) {
      try {
        initial = DateTime.parse(_birthDate!);
      } catch (_) {}
    }
    DateTime picked = initial;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: 320,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  const Text('选择出生日期'),
                  TextButton(
                    onPressed: () {
                      if (mounted) {
                        setState(() => _birthDate =
                            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                      }
                      Navigator.pop(context);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
              SizedBox(
                height: 260,
                child: CupertinoTheme(
                  data: const CupertinoThemeData(brightness: Brightness.light),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initial,
                    minimumDate: DateTime(1900),
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (v) {
                      picked = v;
                      setModalState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndNext() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_currentStep == 0) {
        final nickname = _nicknameController.text.trim();
        if (nickname.isNotEmpty) {
          await apiClient
              .patch('/api/auth/updateProfile', data: {'nickname': nickname});
        }
      } else if (_currentStep == 1) {
        final data = <String, dynamic>{};
        if (_birthDate != null && _birthDate!.isNotEmpty) {
          data['birthDate'] = _birthDate;
        }
        if (_birthTime != null && _birthTime!.isNotEmpty) {
          data['birthTime'] = _birthTime;
        }
        if (_gender != null) data['gender'] = _gender;
        if (data.isNotEmpty) {
          await apiClient.patch('/api/auth/updateProfile', data: data);
          await AccountBirthProfileRepository.invalidateCurrent();
          FortunePreloadCoordinator.schedule(
            delay: Duration.zero,
            forceProfileRefresh: true,
          );
        }
      } else if (_currentStep == 2) {
        final intro = _introController.text.trim();
        if (intro.isNotEmpty) {
          await apiClient
              .patch('/api/auth/updateProfile', data: {'intro': intro});
        }
      }
    } on DioException catch (_) {}
    if (!mounted) return;
    setState(() => _saving = false);
    _goNext();
  }

  void _skip() {
    _goNext();
  }

  void _goNext() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      widget.onComplete(); // 完成或跳过最后一步后回调，会 pop 并触发登录成功
    }
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return '设置昵称';
      case 1:
        return '出生日期';
      case 2:
        return '个人简介';
      default:
        return '';
    }
  }

  String get _stepSubtitle {
    switch (_currentStep) {
      case 0:
        return '让大家认识你';
      case 1:
        return '用于八字排盘与今日运势，请精确到分钟';
      case 2:
        return '简单介绍一下自己';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Text('${_currentStep + 1}/3',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentStep + 1) / 3,
                        backgroundColor: AppColors.divider,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep0(),
                  _buildStep1(),
                  _buildStep2(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  AppButton(
                    label: _currentStep < 2 ? '下一步' : '完成',
                    onPressed: _saveAndNext,
                    loading: _saving,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _skip,
                    child: Text('跳过',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textHint)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(_stepTitle, style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text(_stepSubtitle,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 48),
          AppTextField(
            controller: _nicknameController,
            label: '昵称',
            hint: '请输入昵称',
            maxLength: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(_stepTitle, style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text(_stepSubtitle,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 48),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('男'),
                selected: _gender == 1,
                onSelected: (v) => setState(() => _gender = v ? 1 : null),
              ),
              ChoiceChip(
                label: const Text('女'),
                selected: _gender == 2,
                onSelected: (v) => setState(() => _gender = v ? 2 : null),
              ),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: _pickBirthDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.textSecondary, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    _birthDate ?? '点击选择出生日期',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _birthDate != null
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickBirthTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      color: AppColors.textSecondary, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    _birthTime ?? '点击选择出生时间（时:分）',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _birthTime != null
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(_stepTitle, style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text(_stepSubtitle,
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 48),
          AppTextField(
            controller: _introController,
            label: '简介',
            hint: '写一句介绍自己吧',
            maxLines: 4,
            maxLength: 200,
          ),
        ],
      ),
    );
  }
}

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({
    required this.initialHour,
    required this.initialMinute,
    required this.onConfirm,
    required this.onCancel,
  });
  final int initialHour;
  final int initialMinute;
  final void Function(int hour, int minute) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialHour;
    _minute = widget.initialMinute;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: widget.onCancel, child: const Text('取消')),
              const Text('选择出生时间'),
              TextButton(
                onPressed: () => widget.onConfirm(_hour, _minute),
                child: const Text('确定'),
              ),
            ],
          ),
          SizedBox(
            height: 220,
            child: CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.light),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: DateTime(
                    2000, 1, 1, widget.initialHour, widget.initialMinute),
                onDateTimeChanged: (v) {
                  setState(() {
                    _hour = v.hour;
                    _minute = v.minute;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
