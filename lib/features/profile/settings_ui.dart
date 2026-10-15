import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

ButtonStyle settingsFilledActionStyle({bool destructive = false}) =>
    FilledButton.styleFrom(
      backgroundColor: destructive ? AppColors.error : const Color(0xFF24272D),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );

ButtonStyle settingsTextActionStyle({bool destructive = false}) =>
    TextButton.styleFrom(
      foregroundColor: destructive ? AppColors.error : const Color(0xFF24272D),
    );

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.loading = false,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: actions,
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF24272D)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: children,
            ),
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 10),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent = 64});
  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: .6,
        indent: indent,
        endIndent: 24,
        color: const Color(0xFFECEEF1),
      );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Icon(icon,
                      size: 24,
                      color: destructive
                          ? AppColors.error
                          : const Color(0xFF24272D)),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.25,
                              color: destructive
                                  ? AppColors.error
                                  : const Color(0xFF24272D),
                              fontWeight: FontWeight.w400,
                            )),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!,
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Color(0xFF9CA3AF))),
                        ],
                      ],
                    ),
                  ),
                  if (value != null)
                    Flexible(
                      child: Text(value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF9CA3AF))),
                    ),
                  if (trailing != null)
                    trailing!
                  else if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 22, color: Color(0xFFB9BDC4)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch.adaptive(
          value: value,
          activeTrackColor: const Color(0xFF24272D),
          onChanged: onChanged,
        ),
      );
}

/// 设置三级页统一使用的无卡片输入行：白底、细分隔线、小字号。
class SettingsFormField extends StatelessWidget {
  const SettingsFormField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.maxLength,
    this.suffix,
    this.textInputAction,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helperText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLength;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscureText,
              maxLength: maxLength,
              textInputAction: textInputAction,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 16, color: Color(0xFF24272D)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    const TextStyle(fontSize: 15, color: Color(0xFFB1B5BC)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                counterText: '',
                suffixIcon: suffix,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 40),
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 2),
              Text(helperText!,
                  style: const TextStyle(
                      fontSize: 12, height: 1.45, color: Color(0xFF9CA3AF))),
            ],
          ],
        ),
      );
}

class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key, this.destructive = false});

  final String text;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: destructive ? AppColors.error : const Color(0xFF7A7F87),
          ),
        ),
      );
}

class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor:
                destructive ? AppColors.error : const Color(0xFF24272D),
            disabledBackgroundColor: const Color(0xFFE5E7EB),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      );
}
