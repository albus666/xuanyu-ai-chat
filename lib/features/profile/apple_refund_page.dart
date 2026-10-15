import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/app_toast.dart';

class AppleRefundPage extends StatelessWidget {
  const AppleRefundPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('苹果内购退款')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              '通过苹果购买的玄遇币，请在 Apple「报告问题」页面登录购买时使用的 Apple 账户，选择对应订单并申请退款。是否符合退款条件及处理结果由 Apple 决定。'),
          const SizedBox(height: 16),
          const Text('退款获批后，对应玄遇币会扣回。若相关玄遇币已经消费，余额可能变为负数。其他渠道的历史订单问题，请联系平台客服。'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              try {
                final opened = await launchUrl(
                  Uri.parse('https://reportaproblem.apple.com'),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  showAppToast(context, '请在浏览器打开 reportaproblem.apple.com');
                }
              } catch (_) {
                if (context.mounted) {
                  showAppToast(context, '请在浏览器打开 reportaproblem.apple.com');
                }
              }
            },
            child: const Text('前往 Apple 申请退款'),
          ),
        ]),
      );
}
