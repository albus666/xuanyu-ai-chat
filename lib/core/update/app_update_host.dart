import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bootstrap/startup_gate.dart';
import '../utils/app_toast.dart';
import 'app_update_service.dart';

class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost({super.key, required this.child, this.navigatorKey});

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> checkNow(BuildContext context) async {
    final state = context.findAncestorStateOfType<_AppUpdateHostState>();
    if (state == null) {
      showAppToast(context, '更新服务暂时不可用');
      return;
    }
    await state.check(manual: true);
  }

  @override
  State<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  bool _dialogVisible = false;
  bool _checking = false;

  BuildContext get _dialogContext =>
      widget.navigatorKey?.currentState?.overlay?.context ?? context;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdateService.instance.setPlayCoreHandler(_showInstallReady);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_checkAfterStartup()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppUpdateService.instance.setPlayCoreHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkAfterStartup());
    }
  }

  Future<void> _checkAfterStartup() async {
    await StartupGate.ready;
    if (mounted) await check();
  }

  Future<void> check({bool manual = false}) async {
    if (!mounted || _dialogVisible || _checking) return;
    _checking = true;
    try {
      final result = await AppUpdateService.instance.check(manual: manual);
      if (!mounted) return;
      if (result == null) {
        if (manual) showAppToast(context, '暂时无法检查更新，请稍后重试');
        return;
      }
      if (!result.policy.available) {
        if (manual) {
          showAppToast(
            context,
            '已是最新版本 ${result.packageInfo.version} (${result.packageInfo.buildNumber})',
          );
        }
        return;
      }
      if (!await AppUpdateService.instance.shouldPrompt(
            result.policy,
            manual: manual,
          ) ||
          !mounted) {
        return;
      }
      await _showUpdateDialog(result.policy);
    } catch (_) {
      if (manual && mounted) showAppToast(context, '检查更新失败，请稍后重试');
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdateDialog(AppUpdatePolicy policy) async {
    if (_dialogVisible || !mounted) return;
    _dialogVisible = true;
    var snoozeToday = false;
    var opening = false;
    try {
      await showDialog<void>(
        context: _dialogContext,
        barrierDismissible: !policy.required,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => PopScope(
            canPop: !policy.required,
            child: AlertDialog(
              title: Text(policy.title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (policy.message.isNotEmpty) Text(policy.message),
                    if (policy.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        '更新内容',
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...policy.releaseNotes.map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $note'),
                        ),
                      ),
                    ],
                    if (policy.latestVersion.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '最新版本 ${policy.latestVersion} (${policy.latestBuild})',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    if (!policy.required) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('今日不再提示'),
                        value: snoozeToday,
                        onChanged: opening
                            ? null
                            : (value) => setDialogState(() {
                                  snoozeToday = value ?? false;
                                }),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!policy.required)
                  TextButton(
                    onPressed: opening
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('稍后'),
                  ),
                FilledButton(
                  onPressed: opening
                      ? null
                      : () async {
                          setDialogState(() => opening = true);
                          try {
                            final opened = await AppUpdateService.instance
                                .startUpdate(policy);
                            if (!dialogContext.mounted) return;
                            if (opened && !policy.required) {
                              Navigator.of(dialogContext).pop();
                            } else if (!opened) {
                              showAppToast(dialogContext, '无法打开更新地址，请稍后重试');
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              showAppToast(dialogContext, '无法打开更新地址，请稍后重试');
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => opening = false);
                            }
                          }
                        },
                  child: Text(opening ? '正在打开…' : '立即更新'),
                ),
              ],
            ),
          ),
        ),
      );
      if (snoozeToday && !policy.required) {
        await AppUpdateService.instance.snoozeToday();
      }
    } finally {
      _dialogVisible = false;
    }
  }

  Future<void> _showInstallReady() async {
    if (!mounted) return;
    await showDialog<void>(
      context: _dialogContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新版本已下载'),
        content: const Text('更新包已在后台下载完成，重启应用即可完成安装。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await AppUpdateService.instance.completeFlexibleUpdate();
            },
            child: const Text('立即重启'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
