import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import 'im_workflow_request.dart';
import '../../core/utils/app_toast.dart';
import '../community/user_profile_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_text_field.dart';

/// 创建群聊：群名 + 从关注的人里选成员
class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _nameController = TextEditingController(text: '');
  final _following = <Map<String, dynamic>>[];
  final _selectedIds = <int>{};
  bool _loading = false;
  bool _submitting = false;
  final _scope = ImWorkflowRequest();
  String? _error;
  int _loadGeneration = 0;
  bool _uncertain = false;

  void _sessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _following.clear();
      _selectedIds.clear();
      _loading = false;
      _submitting = false;
      _error = imSessionChangedMessage;
    });
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _loadFollowing();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    if (!mounted || !_scope.current) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = imResponseList(
          await _scope.get('/api/community/user/me/following-list'));
      final unique = <int, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = (row['userId'] as num?)?.toInt();
        if (id != null) unique[id] = row;
      }
      if (!mounted || !_scope.current || generation != _loadGeneration) return;
      setState(() {
        _following
          ..clear()
          ..addAll(unique.values);
        _selectedIds.removeWhere((id) => !unique.containsKey(id));
      });
    } catch (error) {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _error = imFailureMessage(error, '可邀请成员加载失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create() async {
    if (_submitting || !_scope.current || _uncertain) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '请输入群名称');
      return;
    }
    final memberIds = _selectedIds.toList();
    setState(() => _submitting = true);
    try {
      final data = await _scope.post('/api/im/conversation/group',
          data: {'name': name, 'memberIds': memberIds});
      if (!mounted || !_scope.current) return;
      final convId = (data['conversationId'] as num?)?.toInt();
      if (convId == null || convId <= 0) {
        _uncertain = true;
        throw const ImWorkflowFailure('创建结果待确认，请返回群聊与部落查看，避免重复创建');
      }
      final added = (data['added'] as num?)?.toInt() ?? 0;
      final skipped = <Object?>{
        ...?data['blockedUserIds'] as List?,
        ...?data['invalidUserIds'] as List?,
      }.length;
      final message = skipped > 0
          ? '群聊已创建，$added位好友已加入，$skipped人因邀请权限或账号状态未加入'
          : added > 0
              ? '群聊已创建，$added位好友已加入'
              : '群聊创建成功';
      final overlay = Overlay.of(context, rootOverlay: true);
      Navigator.of(context).pop({
        'conversationId': convId,
        'title': data['title']?.toString() ?? name
      });
      showGlobalAppToast(message, overlayState: overlay);
    } catch (error) {
      if (mounted && _scope.current) {
        // 无响应无法证明服务端未创建；不允许盲目重发，先返回列表核对。
        if (error is! ImWorkflowFailure && imFailureStatus(error) == null) {
          _uncertain = true;
        }
        showAppToast(
            context,
            _uncertain
                ? '创建结果待确认，请返回群聊与部落查看，避免重复创建'
                : imFailureMessage(error, '创建失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed:
                _submitting || !_scope.current || _uncertain ? null : _create,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建'),
          ),
        ],
      ),
      body: !_scope.current
          ? const Center(child: Text(imSessionChangedMessage))
          : AbsorbPointer(
              absorbing: _submitting,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_uncertain)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('创建结果待确认，请返回群聊与部落查看，避免重复创建')),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppTextField(
                      controller: _nameController,
                      label: '群名称',
                      hint: '请输入群名称',
                      maxLength: 32,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '邀请成员（对方同意后加入）',
                      style: AppTextStyles.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: ImWorkflowRetry(
                                    message: _error!, onRetry: _loadFollowing))
                            : _following.isEmpty
                                ? Center(
                                    child: Text(
                                      '暂无关注的人，先去社区关注用户再来建群吧',
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(color: AppColors.textHint),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    itemCount: _following.length,
                                    itemBuilder: (context, index) {
                                      final u = _following[index];
                                      final userId =
                                          (u['userId'] as num?)?.toInt();
                                      final nickname =
                                          u['nickname'] as String? ?? '用户';
                                      final avatarUrl =
                                          u['avatarUrl'] as String?;
                                      if (userId == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final selected =
                                          _selectedIds.contains(userId);
                                      return ListTile(
                                        leading: GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) => UserProfilePage(
                                                    userId: userId)),
                                          ),
                                          child: CircleAvatar(
                                            backgroundColor:
                                                AppColors.primaryLight,
                                            backgroundImage:
                                                avatarUrl != null &&
                                                        avatarUrl.isNotEmpty
                                                    ? NetworkImage(avatarUrl)
                                                    : null,
                                            child: avatarUrl == null ||
                                                    avatarUrl.isEmpty
                                                ? Text(nickname.isNotEmpty
                                                    ? nickname[0]
                                                    : '?')
                                                : null,
                                          ),
                                        ),
                                        title: Text(nickname),
                                        trailing: Checkbox(
                                          value: selected,
                                          onChanged: (v) {
                                            setState(() {
                                              if (v == true) {
                                                _selectedIds.add(userId);
                                              } else {
                                                _selectedIds.remove(userId);
                                              }
                                            });
                                          },
                                        ),
                                        onTap: () {
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
                  ),
                ],
              )),
    );
  }
}
