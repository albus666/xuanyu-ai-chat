import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../features/main/main_shell_page.dart';

void minimizeCallToHome(VoidCallback minimize) {
  minimize();
  MainShellPage.showHome();
  Get.key.currentState?.popUntil((route) => route.isFirst);
}

Future<bool?> showCallBackChoice(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('是否结束通话？'),
        content: const Text('继续通话将缩小为浮窗并返回主页。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续通话')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('结束通话')),
        ],
      ),
    );
