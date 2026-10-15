import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/team_home_page.dart';
import 'chat_apply_page.dart';
import 'chat_info_page.dart';
import 'chat_page.dart';
import 'create_group_page.dart';
import 'create_team_page.dart';
import 'im_workflow_request.dart';

/// 群聊与部落中心：我的、创建、管理、申请与发现统一入口。
class JoinableGroupsPage extends StatefulWidget {
  const JoinableGroupsPage(
      {super.key, this.onJoined, this.initialConversationId});

  final VoidCallback? onJoined;
  final int? initialConversationId;

  @override
  State<JoinableGroupsPage> createState() => _JoinableGroupsPageState();
}

class _JoinableGroupsPageState extends State<JoinableGroupsPage> {
  final _mine = <Map<String, dynamic>>[];
  final _teams = <Map<String, dynamic>>[];
  final _groups = <Map<String, dynamic>>[];
  bool _loading = true;
  final _applyingConvIds = <int>{};
  final _searchController = TextEditingController();
  String _query = '';
  int _loadGeneration = 0;
  final _failedParts = List.filled(3, false);
  bool _initialTargetHandled = false;
  bool _openingInitialTarget = false;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _loadGeneration++;
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _mine.clear();
      _teams.clear();
      _groups.clear();
      _applyingConvIds.clear();
      _query = '';
      _searchController.clear();
      _failedParts.fillRange(0, 3, false);
      _loading = false;
    });
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ImWorkflowRequest();
    final generation = ++_loadGeneration;
    if (apiClient.options.headers['Authorization'] == null) {
      setState(() {
        _loading = false;
        _failedParts.fillRange(0, 3, true);
      });
      return;
    }
    setState(() => _loading = true);
    final results = await Future.wait([
      '/api/im/teams/joinable',
      '/api/im/groups/joinable',
      '/api/im/groups/mine',
    ].map((path) async {
      try {
        return imResponseList(await request.get(path));
      } catch (_) {
        return null;
      }
    }));
    if (!mounted || !request.current || generation != _loadGeneration) return;
    setState(() {
      for (var i = 0; i < results.length; i++) {
        _failedParts[i] = results[i] == null;
        if (results[i] != null) {
          final target = [_teams, _groups, _mine][i];
          target
            ..clear()
            ..addAll(results[i]!);
        }
      }
      _loading = false;
    });
    _openInitialTargetIfReady();
  }

  void _openInitialTargetIfReady() {
    final id = widget.initialConversationId;
    if (id == null || _initialTargetHandled || _openingInitialTarget) return;

    Map<String, dynamic>? findIn(List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        if ((row['conversationId'] as num?)?.toInt() == id) return row;
      }
      return null;
    }

    final mine = findIn(_mine);
    final team = findIn(_teams);
    final group = findIn(_groups);
    if (mine == null && team == null && group == null) {
      if (_failedParts.any((failed) => failed)) return;
      _initialTargetHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppToast(context, '该群聊或部落不存在，或暂未开放加入');
      });
      return;
    }

    _initialTargetHandled = true;
    _openingInitialTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (mine != null) {
        final name = mine['name']?.toString() ?? '群聊';
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(
              conversationId: id,
              title: name,
              conversationType: 'group',
            ),
          ),
        );
      } else if (team != null) {
        final name = team['name']?.toString() ?? '部落';
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => TeamHomePage(
              conversationId: id,
              initialName: name,
              initialTitle: team['title']?.toString(),
              initialMemberCount: (team['memberCount'] as num?)?.toInt(),
              initialMaxMembers: (team['maxMembers'] as num?)?.toInt(),
            ),
          ),
        );
      } else if (group != null) {
        _showGroupDetail(
          group,
          id,
          group['name']?.toString() ?? '群聊',
          (group['memberCount'] as num?)?.toInt() ?? 0,
          (group['maxMembers'] as num?)?.toInt() ?? 500,
        );
      }
      if (mounted) _openingInitialTarget = false;
    });
  }

  Future<void> _apply(int conversationId, String name) async {
    if (_applyingConvIds.contains(conversationId)) return;
    final request = ImWorkflowRequest();
    setState(() => _applyingConvIds.add(conversationId));
    var note = '';
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text('申请加入「$name」'),
                content: TextFormField(
                    initialValue: note,
                    onChanged: (value) => note = value,
                    maxLength: 200,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(hintText: '介绍自己或填写加入理由（选填）')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('提交')),
                ],
              ));
      if (confirmed != true || !mounted || !request.current) return;
      note = note.trim();
      await request
          .post('/api/im/group/$conversationId/apply', data: {'note': note});
      if (!mounted || !request.current) return;
      _loadGeneration++;
      setState(() {
        for (final item in [..._teams, ..._groups]) {
          if (item['conversationId'] == conversationId) {
            item['applyStatus'] = 'pending';
          }
        }
      });
      showAppToast(context, '已提交申请');
      await _load();
      if (mounted && request.current) widget.onJoined?.call();
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(context, imFailureMessage(error, '提交失败，请重试'));
      }
    } finally {
      if (mounted && request.current) {
        setState(() => _applyingConvIds.remove(conversationId));
      }
    }
  }

  Future<void> _withdraw(int conversationId) async {
    if (_applyingConvIds.contains(conversationId)) return;
    final request = ImWorkflowRequest();
    setState(() => _applyingConvIds.add(conversationId));
    try {
      await request.post('/api/im/group/$conversationId/apply/withdraw');
      if (!mounted || !request.current) return;
      _loadGeneration++;
      setState(() {
        for (final item in [..._teams, ..._groups]) {
          if (item['conversationId'] == conversationId) {
            item['applyStatus'] = 'withdrawn';
          }
        }
      });
      showAppToast(context, '申请已撤回');
      await _load();
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(context, imFailureMessage(error, '撤回失败，请重试'));
      }
    } finally {
      if (mounted && request.current) {
        setState(() => _applyingConvIds.remove(conversationId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final teams = _teams
        .where(
          (item) =>
              query.isEmpty ||
              '${item['name'] ?? ''} ${item['title'] ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final groups = _groups
        .where(
          (item) =>
              query.isEmpty ||
              (item['name']?.toString().toLowerCase() ?? '').contains(query),
        )
        .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, title: const Text('群聊与部落')),
      body: _loading && _mine.isEmpty && _teams.isEmpty && _groups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_failedParts.any((failed) => failed))
                    ImWorkflowRetry(
                        message: '部分群聊或部落加载失败，请重试',
                        onRetry: _loading ? null : _load),
                  _buildActionGrid(),
                  const SizedBox(height: 22),
                  _buildSectionTitle('我的群聊与部落', '${_mine.length}个'),
                  const SizedBox(height: 8),
                  if (_mine.isEmpty && !_failedParts[2])
                    _buildInlineEmpty('你还没有加入群聊或部落')
                  else
                    ..._mine.map(_buildMineTile),
                  const SizedBox(height: 26),
                  _buildSectionTitle('查找并加入', '公开内容'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: '搜索部落或群聊名称',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF5F6F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (teams.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                      child: Text(
                        '推荐部落',
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...teams.map((t) => _buildTeamTile(t)),
                    if (groups.isNotEmpty) const Divider(height: 24),
                  ],
                  if (groups.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                      child: Text(
                        '推荐群聊',
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...groups.map((g) => _buildGroupTile(g)),
                  ],
                  if (teams.isEmpty &&
                      groups.isEmpty &&
                      !_failedParts[0] &&
                      !_failedParts[1])
                    _buildInlineEmpty(
                      _query.isEmpty ? '暂无开放申请的群聊或部落' : '没有匹配结果',
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionGrid() {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.group_add_outlined,
        label: '创建群聊',
        onTap: () => _openCreate(const CreateGroupPage()),
      ),
      (
        icon: Icons.shield_outlined,
        label: '创建部落',
        onTap: () => _openCreate(const CreateTeamPage()),
      ),
      (
        icon: Icons.mark_email_unread_outlined,
        label: '申请与邀请',
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ChatApplyPage()))
            .then((_) => _load()),
      ),
      (
        icon: Icons.admin_panel_settings_outlined,
        label: '管理群聊与部落',
        onTap: _openManagement,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.65,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return Material(
          color: const Color(0xFFF6FAFA),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      action.icon,
                      color: AppColors.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, String caption) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTextStyles.titleSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          caption,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
        ),
      ],
    );
  }

  Widget _buildInlineEmpty(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F9),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
      ),
    );
  }

  Widget _buildMineTile(Map<String, dynamic> item) {
    final conversationId = (item['conversationId'] as num?)?.toInt();
    final name = item['name']?.toString() ?? '群聊';
    final isTribe = item['kind'] == 'tribe';
    final canManage = item['canManage'] == true;
    final memberCount = (item['memberCount'] as num?)?.toInt() ?? 0;
    final avatarUrl = item['avatarUrl']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE9ECEF)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          onTap: conversationId == null
              ? null
              : () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        conversationId: conversationId,
                        title: name,
                        conversationType: 'group',
                      ),
                    ),
                  )
                  .then((_) => _load()),
          leading: CircleAvatar(
            backgroundColor: isTribe
                ? AppColors.accentGold.withValues(alpha: .16)
                : AppColors.primaryLight,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Icon(
                    isTribe ? Icons.shield_outlined : Icons.groups_outlined,
                    color: isTribe ? AppColors.accentGold : AppColors.primary,
                  )
                : null,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${isTribe ? '部落' : '群聊'} · $memberCount人'),
          trailing: conversationId == null
              ? null
              : canManage
                  ? TextButton(
                      onPressed: () => _openInfo(conversationId, name),
                      child: const Text('管理'),
                    )
                  : const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }

  Future<void> _openCreate(Widget page) async {
    final request = ImWorkflowRequest();
    final result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
    if (!mounted || !request.current) return;
    await _load();
    if (!mounted || !request.current) return;
    widget.onJoined?.call();
    if (result is Map && result['conversationId'] is num && mounted) {
      final conversationId = (result['conversationId'] as num).toInt();
      final title = result['title']?.toString() ?? '群聊';
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            title: title,
            conversationType: 'group',
          ),
        ),
      );
      if (mounted) await _load();
    }
  }

  void _openInfo(int conversationId, String name) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatInfoPage(
              conversationId: conversationId,
              title: name,
              onUpdated: _load,
            ),
          ),
        )
        .then((_) => _load());
  }

  void _openManagement() {
    final request = ImWorkflowRequest();
    final manageable =
        _mine.where((item) => item['canManage'] == true).toList();
    if (manageable.isEmpty) {
      showAppToast(context, '暂无可管理的群聊或部落');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => ImWorkflowSessionBoundary(
        request: request,
        expiredBuilder: (_) => _expiredSheet(sheetContext),
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('管理群聊与部落', style: AppTextStyles.titleMedium),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: manageable.length,
                itemBuilder: (_, index) {
                  final item = manageable[index];
                  final conversationId =
                      (item['conversationId'] as num?)?.toInt();
                  final isTribe = item['kind'] == 'tribe';
                  final name = item['name']?.toString() ?? '群聊';
                  return ListTile(
                    leading: Icon(
                      isTribe ? Icons.shield_outlined : Icons.groups_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(name),
                    subtitle: Text(isTribe ? '部落管理' : '群聊管理'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: conversationId == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            _openInfo(conversationId, name);
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTeamTile(Map<String, dynamic> t) {
    final id = (t['conversationId'] as num?)?.toInt();
    final name = t['name'] as String? ?? '部落';
    final title = (t['title'] as String?)?.trim() ?? '';
    final memberCount = (t['memberCount'] as num?)?.toInt() ?? 0;
    final maxMembers = (t['maxMembers'] as num?)?.toInt() ?? 500;
    final applying = id != null && _applyingConvIds.contains(id);
    final pending = t['applyStatus'] == 'pending';
    return ListTile(
      onTap: id == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeamHomePage(
                    conversationId: id,
                    initialName: name,
                    initialTitle: title,
                    initialMemberCount: memberCount,
                    initialMaxMembers: maxMembers,
                  ),
                ),
              ),
      leading: CircleAvatar(
        backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
        child: const Icon(Icons.shield_outlined, color: AppColors.accentGold),
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$memberCount / $maxMembers 人',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (title.isNotEmpty)
            Text(
              '头衔 $title',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
        ],
      ),
      isThreeLine: title.isNotEmpty,
      trailing: id != null
          ? TextButton(
              onPressed: applying
                  ? null
                  : pending
                      ? () => _withdraw(id)
                      : () => _apply(id, name),
              child: applying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(pending ? '撤回申请' : '申请加入'),
            )
          : null,
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> g) {
    final id = (g['conversationId'] as num?)?.toInt();
    final name = g['name'] as String? ?? '群聊';
    final memberCount = (g['memberCount'] as num?)?.toInt() ?? 0;
    final maxMembers = (g['maxMembers'] as num?)?.toInt() ?? 500;
    final applying = id != null && _applyingConvIds.contains(id);
    final pending = g['applyStatus'] == 'pending';
    return ListTile(
      onTap: id == null
          ? null
          : () => _showGroupDetail(g, id, name, memberCount, maxMembers),
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: AppTextStyles.titleSmall,
        ),
      ),
      title: Text(name),
      subtitle: Text(
        '$memberCount / $maxMembers 人',
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
      ),
      trailing: id != null
          ? TextButton(
              onPressed: applying
                  ? null
                  : pending
                      ? () => _withdraw(id)
                      : () => _apply(id, name),
              child: applying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(pending ? '撤回申请' : '申请加入'),
            )
          : null,
    );
  }

  void _showGroupDetail(
    Map<String, dynamic> group,
    int conversationId,
    String name,
    int memberCount,
    int maxMembers,
  ) {
    final request = ImWorkflowRequest();
    final pending = group['applyStatus'] == 'pending';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => ImWorkflowSessionBoundary(
        request: request,
        expiredBuilder: (_) => _expiredSheet(ctx),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$memberCount / $maxMembers 人',
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A7F87)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  pending
                      ? _withdraw(conversationId)
                      : _apply(conversationId, name);
                },
                child: Text(pending ? '撤回申请' : '填写申请'),
              ),
              const SizedBox(height: 8),
              const Text(
                '申请提交后可在「申请与邀请 > 我的申请」查看处理状态。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _expiredSheet(BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(imSessionChangedMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
}
