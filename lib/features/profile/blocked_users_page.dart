import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../community/user_profile_page.dart';
import 'settings_ui.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final _items = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await apiClient.get('/api/community/user/blocks',
          queryParameters: {'page': 1, 'page_size': 100});
      final data = (res.data as Map?)?['data'];
      final rawList = data is Map ? data['list'] : data;
      final parsed = <Map<String, dynamic>>[];
      if (rawList is List) {
        for (final e in rawList) {
          if (e is Map) parsed.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(parsed);
        });
      }
    } on DioException {
      if (mounted) showAppToast(context, '拉黑名单暂时无法加载');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _userIdOf(Map<String, dynamic> item) {
    for (final key in const ['userId', 'id', 'targetUserId', 'blockedUserId']) {
      final id = (item[key] as num?)?.toInt();
      if (id != null) return id;
    }
    final user = item['user'];
    if (user is Map) return (user['id'] as num?)?.toInt();
    return null;
  }

  String _nicknameOf(Map<String, dynamic> item) {
    final user = item['user'];
    if (user is Map) {
      return user['nickname']?.toString() ??
          user['name']?.toString() ??
          item['nickname']?.toString() ??
          '用户';
    }
    return item['nickname']?.toString() ?? item['name']?.toString() ?? '用户';
  }

  String? _avatarOf(Map<String, dynamic> item) {
    final user = item['user'];
    if (user is Map) {
      return user['avatarUrl']?.toString() ?? user['avatar']?.toString();
    }
    return item['avatarUrl']?.toString() ?? item['avatar']?.toString();
  }

  Future<void> _unblock(Map<String, dynamic> item) async {
    final userId = _userIdOf(item);
    if (userId == null) {
      showAppToast(context, '用户信息不完整');
      return;
    }
    try {
      await apiClient.post('/api/community/user/$userId/unblock');
      if (!mounted) return;
      setState(() => _items.remove(item));
      showAppToast(context, '已取消拉黑');
    } on DioException {
      if (mounted) showAppToast(context, '操作失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '拉黑名单',
        loading: _loading,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
        ],
        children: [
          SettingsSectionLabel('已拉黑 ${_items.length} 人'),
          if (_items.isEmpty)
            const SettingsHint(
              '暂无拉黑用户。拉黑后，对方无法向你发送私信，也不会出现在你的社区推荐和互动入口中。',
            ),
          for (var index = 0; index < _items.length; index++) ...[
            Builder(builder: (context) {
              final item = _items[index];
              final userId = _userIdOf(item);
              final nickname = _nicknameOf(item);
              final avatarUrl = _avatarOf(item);
              return ListTile(
                minTileHeight: 68,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                leading: CircleAvatar(
                  radius: 21,
                  backgroundColor: const Color(0xFFF1F2F4),
                  backgroundImage:
                      avatarUrl != null && avatarUrl.trim().isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                  child: avatarUrl == null || avatarUrl.trim().isEmpty
                      ? Text(
                          nickname.isNotEmpty ? nickname[0] : '?',
                          style: const TextStyle(
                              color: Color(0xFF24272D), fontSize: 15),
                        )
                      : null,
                ),
                title: Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: const Text('已拉黑',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                onTap: userId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => UserProfilePage(userId: userId),
                          ),
                        ),
                trailing: OutlinedButton(
                  onPressed: () => _unblock(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF24272D),
                    side: const BorderSide(color: Color(0xFFD8DBE0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('解除'),
                ),
              );
            }),
            if (index != _items.length - 1) const SettingsDivider(indent: 86),
          ],
        ],
      );
}
