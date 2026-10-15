import 'package:flutter/material.dart';
import 'package:xuanyu/core/theme/app_colors.dart';

import 'ziwei_models.dart';

class ZiweiSettingsSheet extends StatefulWidget {
  const ZiweiSettingsSheet({super.key, required this.initial});

  final ZiweiSettings initial;

  static Future<ZiweiSettings?> show(
    BuildContext context,
    ZiweiSettings initial,
  ) {
    return showModalBottomSheet<ZiweiSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ZiweiSettingsSheet(initial: initial),
    );
  }

  @override
  State<ZiweiSettingsSheet> createState() => _ZiweiSettingsSheetState();
}

class _ZiweiSettingsSheetState extends State<ZiweiSettingsSheet> {
  late ZiweiSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '排盘规则',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '规则会随命盘保存，切换后重新排盘',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _choiceSection(
                    title: '安星方法',
                    value: _settings.algorithm,
                    choices: const {'default': '通行', 'zhongzhou': '中州'},
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(algorithm: value);
                      });
                    },
                  ),
                  if (_settings.isZhongzhou)
                    _choiceSection(
                      title: '星盘类型',
                      value: _settings.astroType,
                      choices: const {
                        'heaven': '天盘',
                        'earth': '地盘',
                        'human': '人盘',
                      },
                      onChanged: (value) {
                        setState(() {
                          _settings = _settings.copyWith(astroType: value);
                        });
                      },
                    ),
                  _choiceSection(
                    title: '生年分界',
                    value: _settings.yearDivide,
                    choices: const {'normal': '正月初一', 'exact': '立春'},
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(yearDivide: value);
                      });
                    },
                  ),
                  _choiceSection(
                    title: '运限分界',
                    value: _settings.horoscopeDivide,
                    choices: const {'normal': '正月初一', 'exact': '立春'},
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(horoscopeDivide: value);
                      });
                    },
                  ),
                  _choiceSection(
                    title: '小限分界',
                    value: _settings.ageDivide,
                    choices: const {'normal': '自然年', 'birthday': '生日'},
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(ageDivide: value);
                      });
                    },
                  ),
                  _choiceSection(
                    title: '晚子时换日',
                    value: _settings.dayDivide,
                    choices: const {'forward': '算次日', 'current': '算当日'},
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(dayDivide: value);
                      });
                    },
                  ),
                  _switchRow(
                    title: '闰月月中分界',
                    subtitle: '十五日及以前按本月，之后按下月',
                    value: _settings.fixLeap,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(fixLeap: value);
                      });
                    },
                  ),
                  _switchRow(
                    title: '专业盘面',
                    subtitle: '显示杂曜、十二神与完整运限流曜',
                    value: _settings.professionalMode,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(professionalMode: value);
                      });
                    },
                  ),
                  _switchRow(
                    title: '显示运限流曜',
                    subtitle: '盘面中展示当前层级的动态星曜',
                    value: _settings.showHoroscopeStars,
                    onChanged: (value) {
                      setState(() {
                        _settings =
                            _settings.copyWith(showHoroscopeStars: value);
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, bottom + 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(_settings),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '应用设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceSection({
    required String title,
    required String value,
    required Map<String, String> choices,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.entries.map((entry) {
              final selected = value == entry.key;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppColors.primaryLight,
                backgroundColor: AppColors.background,
                side: BorderSide(
                  color: selected ? AppColors.primary : AppColors.divider,
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                onSelected: (_) => onChanged(entry.key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
