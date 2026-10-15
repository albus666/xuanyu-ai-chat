import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'account_cancellation_page.dart';
import 'settings_ui.dart';

class PrivacyRightsPage extends StatefulWidget {
  const PrivacyRightsPage({super.key});

  @override
  State<PrivacyRightsPage> createState() => _PrivacyRightsPageState();
}

class _PrivacyRightsPageState extends State<PrivacyRightsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];

  static const _items =
      <({String type, String title, String subtitle, IconData icon})>[
    (
      type: 'access',
      title: '查询个人信息',
      subtitle: '了解平台保存了哪些与您有关的信息',
      icon: Icons.manage_search_rounded
    ),
    (
      type: 'copy',
      title: '获取个人信息副本',
      subtitle: '申请导出可依法提供的数据副本',
      icon: Icons.file_download_outlined
    ),
    (
      type: 'correct',
      title: '申请更正信息',
      subtitle: '无法自行修改的信息可提交人工核验',
      icon: Icons.edit_note_rounded
    ),
    (
      type: 'revoke',
      title: '撤回非必要授权',
      subtitle: '不会影响依法或履约必须处理的信息',
      icon: Icons.no_accounts_outlined
    ),
    (
      type: 'appeal',
      title: '账号与内容申诉',
      subtitle: '对内容处理、功能限制或账号状态提出申诉',
      icon: Icons.gavel_outlined
    ),
    (
      type: 'cancel',
      title: '申请注销账号',
      subtitle: '核验余额、订单与争议后进入注销流程',
      icon: Icons.person_off_outlined
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/api/auth/privacy/requests');
      final list = (response.data as Map?)?['data']?['list'];
      if (list is List && mounted) {
        setState(() => _requests = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    } catch (_) {
      if (mounted) showAppToast(context, '暂时无法读取申请记录');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit(String type, String title) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: '可补充说明（选填）', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(
              style: settingsTextActionStyle(),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: settingsFilledActionStyle(),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认提交')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await apiClient.post('/api/auth/privacy/requests',
          data: {'type': type, 'remark': controller.text.trim()});
      if (!mounted) return;
      showAppToast(context,
          (response.data as Map?)?['message']?.toString() ?? '申请已提交，可在本页查看进度');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '提交失败，请稍后重试');
    }
  }

  String _statusName(String value) =>
      const {
        'pending': '待受理',
        'processing': '处理中',
        'completed': '已完成',
        'rejected': '无法处理',
        'withdrawn': '已撤销',
      }[value] ??
      value;

  String _typeName(String value) {
    for (final item in _items) {
      if (item.type == value) return item.title;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '个人信息权利中心',
        loading: _loading,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 4),
            child: Text(
              '统一提交查询、复制、更正、撤回授权和注销申请，平台会记录处理过程并反馈状态。',
              style: TextStyle(
                  fontSize: 13, height: 1.55, color: Color(0xFF7A7F87)),
            ),
          ),
          const SettingsSectionLabel('可申请的权利'),
          for (var i = 0; i < _items.length; i++) ...[
            SettingsRow(
              icon: _items[i].icon,
              title: _items[i].title,
              subtitle: _items[i].subtitle,
              destructive: _items[i].type == 'cancel',
              onTap: () {
                final item = _items[i];
                if (item.type == 'cancel') {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AccountCancellationPage(),
                  ));
                  return;
                }
                _submit(item.type, item.title);
              },
            ),
            if (i != _items.length - 1) const SettingsDivider(),
          ],
          if (_requests.isNotEmpty) ...[
            const SettingsSectionLabel('处理记录'),
            for (var i = 0; i < _requests.length; i++) ...[
              SettingsRow(
                icon: Icons.history_rounded,
                title: _typeName('${_requests[i]['type']}'),
                subtitle: _requests[i]['createdAt']
                        ?.toString()
                        .replaceFirst('T', ' ') ??
                    '',
                value: _statusName('${_requests[i]['status']}'),
              ),
              if (i != _requests.length - 1) const SettingsDivider(),
            ],
          ],
        ],
      );
}
