import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../profile/legal_document_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';

/// 启动时《隐私政策》《用户协议》强制确认弹窗 - 视觉升级版
class AgreementDialog extends StatelessWidget {
  const AgreementDialog({super.key, required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF0FAF8)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('用户服务与隐私保护', style: AppTextStyles.titleLarge),
                  const SizedBox(height: 16),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      children: [
                        const TextSpan(text: '感谢您选择玄遇！在您使用前，请认真阅读并同意'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentPage(
                                  type: LegalDocumentType.userAgreement,
                                ),
                              ),
                            ),
                            child: const Text(
                              '《用户协议》',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: '与'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentPage(
                                  type: LegalDocumentType.privacyPolicy,
                                ),
                              ),
                            ),
                            child: const Text(
                              '《隐私政策》',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(
                          text: '。' '平台对违规内容及骚扰、欺凌等滥用行为零容忍；核实后将下架内容并限制或封禁违规账号。您同意遵守用户协议中的社区规则。我们将严格保护您的个人信息安全。',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  AppButton(label: '同意并继续', onPressed: onAccept),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: Text('不同意', style: AppTextStyles.bodySmall),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
