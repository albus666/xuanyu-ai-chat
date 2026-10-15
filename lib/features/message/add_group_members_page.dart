import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import 'im_workflow_request.dart';
import '../community/user_profile_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// 邀请入群：从关注的人中选择（排除已在群内的）
class AddGroupMembersPage extends StatefulWidget {
  const AddGroupMembersPage({
    super.key,
    required this.conversationId,
    required this.existingUserIds,
    this.isTribe = false,
  });

  final int conversationId;
  final Set<int> existingUserIds;
  final bool isTribe;

  @override
  State<AddGroupMembersPage> createState() => _AddGroupMembersPageState();
}

class _AddGroupMembersPageState extends State<AddGroupMembersPage> {
  final _following = <Map<String, dynamic>>[];
  final _selectedIds = <int>{};
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _loadGeneration = 0;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _loadFollowing();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _loadGeneration++;
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _following.clear();
      _selectedIds.clear();
      _loading = false;
      _submitting = false;
      _sessionExpired = true;
      _error = imSessionChangedMessage;
    });
  }

  Future<void> _loadFollowing() async {
    if (!mounted || _sessionExpired) return;
    final request = ImWorkflowRequest();
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await request.get('/api/community/user/me/following-list');
      final rows = imResponseList(data);
      final unique = <int, Map<String, dynamic>>{};
      for (final row in rows) {
        final uid = (row['userId'] as num?)?.toInt();
        if (uid != null && !widget.existingUserIds.contains(uid)) {
          unique[uid] = row;
        }
      }
      if (!mounted || !request.current || generation != _loadGeneration) return;
      setState(() {
        _following
          ..clear()
          ..addAll(unique.values);
        _selectedIds.removeWhere((id) => !unique.containsKey(id));
      });
    } catch (error) {
      if (mounted && request.current && generation == _loadGeneration) {
        setState(() => _error = imFailureMessage(error, '可邀请成员加载失败，请重试'));
      }
    } finally {
      if (mounted && request.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _invite() async {
    if (_submitting || _sessionExpired || _loading || _error != null) return;
    if (_selectedIds.isEmpty) {
      showAppToast(context, '请选择要邀请的人');
      return;
    }
    final request = ImWorkflowRequest();
    final memberIds = _selectedIds.toList(growable: false);
    setState(() => _submitting = true);
    try {
      final data = await request.post(
          '/api/im/conversation/${widget.conversationId}/add-members',
          data: {'memberIds': memberIds});
      if (!mounted || !request.current) return;
      final invited = data['invited'];
      if (invited is! num || invited < 0 || invited > memberIds.length) {
        throw const ImWorkflowFailure('邀请结果待确认，请返回群详情查看');
      }
      final skipped = <int>{
        for (final key in ['blockedUserIds', 'busyUserIds', 'invalidUserIds'])
          for (final id in (data[key] as List? ?? []))
            if (id is num) id.toInt(),
      };
      final message = data['message']?.toString() ?? '已发送$invited个邀请';
      showAppToast(
          context,
          skipped.isEmpty
              ? message
              : '$message，${skipped.length}人未能邀请；请确认对方允许群聊邀请。邀请需对方在消息申请中同意后加入');
      if (invited > 0) {
        Navigator.of(context).pop(true);
      } else {
        // 对方已在群里、隐私限制、已加入其他部落等不能继续当作成功邀请。
        setState(_selectedIds.clear);
      }
    } catch (error) {
      if (mounted && request.current) {
        final denied =
            imFailureStatus(error) == 403 || imFailureStatus(error) == 404;
        if (denied) setState(() => _error = '当前无法邀请，请返回群详情确认权限');
        showAppToast(context, imFailureMessage(error, '邀请失败，请重试'));
      }
    } finally {
      if (mounted && request.current) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTribe ? '邀请部落成员' : '邀请群成员'),
        actions: [
          TextButton(
            onPressed: _submitting ||
                    _loading ||
                    _sessionExpired ||
                    _error != null ||
                    _selectedIds.isEmpty
                ? null
                : _invite,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('完成(${_selectedIds.length})'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: ImWorkflowRetry(
                      message: _error!,
                      onRetry: _sessionExpired ? null : _loadFollowing))
              : _following.isEmpty
                  ? Center(
                      child: Text(
                        '暂无可邀请的人',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textHint),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _following.length,
                      itemBuilder: (context, index) {
                        final u = _following[index];
                        final userId = (u['userId'] as num?)?.toInt();
                        final nickname = u['nickname'] as String? ?? '用户';
                        final avatarUrl = u['avatarUrl'] as String?;
                        if (userId == null) return const SizedBox.shrink();
                        final selected = _selectedIds.contains(userId);
                        return ListTile(
                          leading: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfilePage(userId: userId)),
                            ),
                            child: CircleAvatar(
                              backgroundColor: AppColors.primaryLight,
                              backgroundImage:
                                  avatarUrl != null && avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? Text(
                                      nickname.isNotEmpty ? nickname[0] : '?')
                                  : null,
                            ),
                          ),
                          title: Text(nickname),
                          trailing: Checkbox(
                            value: selected,
                            onChanged: _submitting
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(userId);
                                      } else {
                                        _selectedIds.remove(userId);
                                      }
                                    });
                                  },
                          ),
                          onTap: _submitting
                              ? null
                              : () {
                                  setState(() {
                                    if (selected) {
                                      _selectedIds.remove(userId);
                                    } else {
                                      _selectedIds.add(userId);
                                    }
                                  });
                                },
                        );
                      },
                    ),
    );
  }
}
