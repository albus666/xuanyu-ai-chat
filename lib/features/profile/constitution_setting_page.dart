import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 中医体质设置：用于今日养生推荐，可与体质测试结果一致或手动选择
const List<String> kConstitutionOptions = [
  '气虚',
  '阳虚',
  '阴虚',
  '痰湿',
  '湿热',
  '血瘀',
  '气郁',
  '特禀',
  '平和',
];

class ConstitutionSettingPage extends StatefulWidget {
  const ConstitutionSettingPage({super.key, this.initialConstitution});

  final String? initialConstitution;

  @override
  State<ConstitutionSettingPage> createState() => _ConstitutionSettingPageState();
}

class _ConstitutionSettingPageState extends State<ConstitutionSettingPage> {
  String? _current;
  String? _saving;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialConstitution;
    if (_current == null || _current!.isEmpty) {
      _loadFromApi();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadFromApi() async {
    try {
      final res = await apiClient.get('/api/auth/me');
      final data = (res.data as Map?)?['data'] as Map?;
      final c = data?['constitution'] as String?;
      if (mounted) {
        setState(() {
        _current = (c != null && c.isNotEmpty) ? c : null;
        _loading = false;
      });
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String value) async {
    if (_saving != null) return;
    setState(() => _saving = value);
    try {
      await apiClient.patch('/api/auth/updateProfile', data: {'constitution': value});
      try { await apiClient.get('/api/fortune/daily-health'); } catch (_) {}
      if (mounted) {
        setState(() {
        _current = value;
        _saving = null;
      });
      }
      if (mounted) Navigator.of(context).pop(value);
    } on DioException catch (_) {
      if (mounted) setState(() => _saving = null);
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
        title: Text('中医体质', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '用于「今日养生」的饮食推荐。可先做体质测试自动识别，或在此手动选择。',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                  ),
                ),
                ...kConstitutionOptions.map((option) {
                  final isSelected = _current == option;
                  final isSaving = _saving == option;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isSaving ? null : () => _save(option),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_rounded, color: AppColors.primary, size: 22),
                            if (isSaving)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
