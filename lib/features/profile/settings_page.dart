import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/bootstrap/auth_state.dart';
import '../../core/widgets/app_share_more_button.dart';
import 'account_switcher_page.dart';
import 'help_support_page.dart';
import 'notification_settings_page.dart';
import 'privacy_settings_page.dart';
import 'settings_subpages.dart';
import 'settings_ui.dart';

/// 黑白扁平设置中心：一级只做清晰分组，具体开关在对应二级页管理。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.isMinorMode, this.onMinorModeChanged});

  final bool? isMinorMode;
  final ValueChanged<bool>? onMinorModeChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _minorMode;

  @override
  void initState() {
    super.initState();
    _minorMode = widget.isMinorMode ?? false;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMinorMode != widget.isMinorMode &&
        widget.isMinorMode != null) {
      _minorMode = widget.isMinorMode!;
    }
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出当前账号吗？'),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            style: settingsTextActionStyle(destructive: true),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (Get.isRegistered<AuthState>() && !await Get.find<AuthState>().logout()) return;
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openMinorProtection(BuildContext context) async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MinorProtectionPage()));
    if (!mounted || !Get.isRegistered<AuthState>()) return;
    final next = Get.find<AuthState>().isMinorMode;
    if (next == _minorMode) return;
    setState(() => _minorMode = next);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '设置',
        children: [
          const SettingsSectionLabel('账号与个人设置'),
          SettingsRow(
            icon: Icons.person_outline_rounded,
            title: '账号与安全',
            subtitle: '手机号、密码、登录设备与账号数据',
            onTap: () => _push(context, const AccountSecurityPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.lock_outline_rounded,
            title: '隐私与在线状态',
            subtitle: '主页展示、私信权限及派对状态',
            onTap: () => _push(context, const PrivacySettingsPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.notifications_none_rounded,
            title: '消息通知',
            subtitle: '系统通知、通话提醒与免打扰',
            onTap: () => _push(context, const NotificationSettingsPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.child_care_rounded,
            title: '未成年人保护',
            value: _minorMode ? '已开启' : '未开启',
            onTap: () => _openMinorProtection(context),
          ),
          const SettingsSectionLabel('安全与服务'),
          SettingsRow(
            icon: Icons.health_and_safety_outlined,
            title: '安全中心',
            subtitle: '安全指南、举报进度、黑名单与申诉',
            onTap: () => _push(context, const SafetyCenterPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.troubleshoot_rounded,
            title: '消息与语音诊断',
            subtitle: '检查网络、权限、录音和语音服务',
            onTap: () => _push(context, const MessageDiagnosticsPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.account_balance_wallet_outlined,
            title: '玄遇币与支付安全',
            subtitle: '余额、订单、送礼确认与连线支付',
            onTap: () => _push(context, const WalletSecurityPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.workspace_premium_outlined,
            title: '创作者与认证',
            subtitle: '老师认证、服务工作台与虚拟头像',
            onTap: () => _push(context, const CreatorServicesPage()),
          ),
          const SettingsSectionLabel('通用与支持'),
          SettingsRow(
            icon: Icons.accessibility_new_rounded,
            title: '通用与辅助功能',
            subtitle: '大号文字、减少动效、权限与缓存',
            onTap: () => _push(context, const GeneralAccessibilityPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.more_horiz_rounded,
            title: '邀请好友',
            subtitle: '分享玄遇给好友',
            onTap: () => showAppShareSheet(
              context,
              title: '邀请好友使用玄遇',
              shareText: '邀请你来玄遇，一起交流、加入群聊与部落，使用专业排盘等实用功能。',
            ),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.support_agent_rounded,
            title: '帮助与反馈',
            onTap: () => _push(context, const HelpSupportPage()),
          ),
          const SettingsDivider(),
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: '关于玄遇',
            subtitle: '版本、协议、备案和第三方信息清单',
            onTap: () => _push(context, const AboutSettingsPage()),
          ),
          const SettingsSectionLabel('登录'),
          SettingsRow(
            icon: Icons.switch_account_outlined,
            title: '切换账号',
            subtitle: '保留登录状态，在本机账号之间切换',
            onTap: () => _push(context, const AccountSwitcherPage()),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: OutlinedButton(
              onPressed: () => _logout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF24272D),
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFFE2E5E9)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('退出登录'),
            ),
          ),
        ],
      );
}
