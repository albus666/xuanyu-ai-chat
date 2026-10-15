import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/app_toast.dart';
import 'legal_document_page.dart';
import 'settings_subpages.dart';
import 'settings_ui.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  void _answer(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Text(body, style: const TextStyle(fontSize: 15, height: 1.65)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '帮助与反馈',
        children: [
          const SettingsSectionLabel('常见问题'),
          SettingsRow(
              icon: Icons.person_outline_rounded,
              title: '账号与隐私',
              onTap: () => _answer(context, '账号与隐私',
                  '手机号、密码、登录设备、在线状态、社交权限、黑名单和注销都可在设置中管理。隐私开关会同步到账号并由服务端执行。')),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.payments_outlined,
              title: '付费与订单',
              onTap: () => _answer(context, '付费与订单',
                  '付费前会展示价格和规则。余额、消费记录、订单及送礼二次确认位于“玄遇币与支付安全”。')),
          const SettingsDivider(),
          SettingsRow(
              icon: Icons.mic_none_rounded,
              title: '语音或消息异常',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const MessageDiagnosticsPage()))),
          const SettingsSectionLabel('联系平台'),
          SettingsRow(
              icon: Icons.copy_rounded,
              title: '复制联系邮箱',
              value: LegalDocumentPage.contactEmail,
              onTap: () async {
                await Clipboard.setData(
                    const ClipboardData(text: LegalDocumentPage.contactEmail));
                if (context.mounted) showAppToast(context, '联系邮箱已复制');
              }),
        ],
      );
}
