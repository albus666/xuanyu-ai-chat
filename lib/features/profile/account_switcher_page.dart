import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/bootstrap/auth_state.dart';
import '../../core/auth/saved_account_store.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'settings_ui.dart';

class AccountSwitcherPage extends StatefulWidget {
  const AccountSwitcherPage({super.key});

  @override
  State<AccountSwitcherPage> createState() => _AccountSwitcherPageState();
}

class _AccountSwitcherPageState extends State<AccountSwitcherPage> {
  List<SavedAccountSession> _accounts = const [];
  bool _loading = true;
  int? _switchingUserId;

  AuthState get _auth => Get.find<AuthState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/me');
      final data = (response.data as Map?)?['data'];
      if (data is Map) {
        await SavedAccountStore.updateCurrentProfile(
          Map<String, dynamic>.from(data),
        );
      }
    } on DioException catch (_) {
      // 当前资料刷新失败时仍展示已经保存的账号，不把网络错误当成退出。
    }
    final accounts = await SavedAccountStore.load();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _switchTo(SavedAccountSession account) async {
    if (account.userId == _auth.userId || _switchingUserId != null) return;
    setState(() => _switchingUserId = account.userId);
    final valid = await SavedAccountStore.validate(account);
    if (!mounted) return;
    if (!valid) {
      setState(() => _switchingUserId = null);
      showAppToast(context, '暂时无法验证该账号，请检查网络或重新登录');
      return;
    }
    final switched = await _auth.activateSavedAccount(account);
    if (!mounted) return;
    if (!switched) {
      setState(() => _switchingUserId = null);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _addAccount() async {
    if (_switchingUserId != null) return;
    if (!await _auth.prepareAddAccount()) return;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _removeAccount(SavedAccountSession account) async {
    if (account.userId == _auth.userId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('只从这台设备移除「${account.displayName}」，不会注销账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SavedAccountStore.remove(account.userId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '切换账号',
      loading: _loading,
      children: [
        const SettingsSectionLabel('本机账号'),
        if (_accounts.isEmpty)
          const SettingsHint('当前设备还没有保存可切换账号。')
        else
          ..._accounts.asMap().entries.expand((entry) {
            final index = entry.key;
            final account = entry.value;
            return [
              _accountRow(account),
              if (index != _accounts.length - 1) const SettingsDivider(),
            ];
          }),
        const SettingsSectionLabel('添加账号'),
        SettingsRow(
          icon: Icons.person_add_alt_1_outlined,
          title: '登录其他账号',
          subtitle: '保留当前账号，下次可在这里一键切换',
          onTap: _addAccount,
        ),
        const SettingsHint('最多保存 5 个账号。切换不会注销账号，也不会让其他设备退出。'),
      ],
    );
  }

  Widget _accountRow(SavedAccountSession account) {
    final current = account.userId == _auth.userId;
    final switching = account.userId == _switchingUserId;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: current ? null : () => _switchTo(account),
        onLongPress: current ? null : () => _removeAccount(account),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF1F2F4),
                backgroundImage: account.avatarUrl.isNotEmpty
                    ? NetworkImage(account.avatarUrl)
                    : null,
                child: account.avatarUrl.isEmpty
                    ? Text(account.displayName.characters.first)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.displayName,
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xFF24272D))),
                    const SizedBox(height: 3),
                    Text(account.maskedAccount,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              if (switching)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (current)
                const Text('当前',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)))
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 22, color: Color(0xFFB9BDC4)),
            ],
          ),
        ),
      ),
    );
  }
}
