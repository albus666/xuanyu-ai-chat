import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../community/user_profile_page.dart';
import 'im_workflow_request.dart';

/// 群成员管理：查看成员、踢出（仅群主）
class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({
    super.key,
    required this.conversationId,
    required this.title,
    this.isTribe = false,
    this.onKicked,
  });

  final int conversationId;
  final String title;
  final bool isTribe;
  final VoidCallback? onKicked;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _loading = true;
  bool _isOwner = false;
  bool _canManage = false;
  int? _myUserId;
  int? _teamId;
  bool _busy = false;
  bool _sessionExpired = false;
  bool _permissionsValid = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _loadMembers();
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
      _sessionExpired = true;
      _permissionsValid = false;
      _busy = false;
      _loading = false;
      _isOwner = false;
      _canManage = false;
      _myUserId = null;
      _teamId = null;
      _members.clear();
      _pendingInvites.clear();
      _error = imSessionChangedMessage;
    });
  }

  Future<void> _loadMembers() async {
    if (!mounted || _sessionExpired) return;
    final request = ImWorkflowRequest();
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _permissionsValid = false;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !request.current || generation != _loadGeneration) return;
      final myId = prefs.getInt(AppConstants.keyUserId);
      final data = await request
          .get('/api/im/conversation/${widget.conversationId}/members');
      final members = imResponseList(data);
      final pending = data['pendingInvites'] == null
          ? <Map<String, dynamic>>[]
          : imResponseList(data, key: 'pendingInvites');
      if (members.any((m) => m['userId'] is! num)) {
        throw const ImWorkflowFailure('成员数据异常，请重试');
      }
      if (!mounted || !request.current || generation != _loadGeneration) return;
      setState(() {
        _members = members;
        _myUserId = myId;
        _isOwner = data['isOwner'] == true;
        _canManage = data['canManage'] == true || _isOwner;
        _pendingInvites = _canManage ? pending : [];
        _teamId = (data['teamId'] as num?)?.toInt();
        _permissionsValid = true;
      });
    } catch (error) {
      if (mounted && request.current && generation == _loadGeneration) {
        setState(() {
          _permissionsValid = false;
          _isOwner = false;
          _canManage = false;
          _pendingInvites.clear();
          final denied = {401, 403, 404}.contains(imFailureStatus(error));
          if (denied) _members.clear();
          _error = imFailureMessage(error, '成员加载失败，请重试');
        });
      }
    } finally {
      if (mounted && request.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  bool _allowed({int? target, bool ownerOnly = false}) {
    if (_sessionExpired || !_permissionsValid || _myUserId == null) {
      return false;
    }
    if (ownerOnly ? !_isOwner : !_canManage) return false;
    if (target == null) return true;
    return target != _myUserId &&
        _members.any((m) =>
            (m['userId'] as num?)?.toInt() == target && m['role'] != 'owner');
  }

  Future<Map<String, dynamic>?> _confirm(
      String title, String content, Map<String, dynamic> data,
      {String confirmText = '确定'}) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(confirmText)),
              ],
            ));
    return ok == true ? data : null;
  }

  Future<void> _memberAction(
    String path, {
    required String success,
    int? target,
    bool ownerOnly = false,
    Map<String, dynamic>? data,
    Future<Map<String, dynamic>?> Function()? prepare,
    bool refreshParent = false,
  }) async {
    if (_busy || !mounted) return;
    if (!_allowed(target: target, ownerOnly: ownerOnly)) {
      showAppToast(context, '管理权限已变更，请刷新后重试');
      return;
    }
    final request = ImWorkflowRequest();
    setState(() => _busy = true);
    try {
      final payload = prepare == null ? data : await prepare();
      if (prepare != null && payload == null) return;
      if (!mounted ||
          !request.current ||
          !_allowed(target: target, ownerOnly: ownerOnly)) {
        return;
      }
      await request.post(path, data: payload);
      if (!mounted || !request.current) return;
      // 成功后先撤下旧管理权限，重新读取失败时也不能继续显示旧群主权限。
      _loadGeneration++;
      setState(() {
        _permissionsValid = false;
        _isOwner = false;
        _canManage = false;
      });
      showAppToast(context, success);
      await _loadMembers();
      if (mounted && request.current && refreshParent) widget.onKicked?.call();
    } catch (error) {
      if (mounted && request.current) {
        if ({401, 403, 404}.contains(imFailureStatus(error))) {
          _loadGeneration++;
          setState(() {
            _loading = false;
            _permissionsValid = false;
            _isOwner = false;
            _canManage = false;
            _pendingInvites.clear();
            _error = '管理权限或成员状态已变化，请刷新';
          });
        }
        showAppToast(context, imFailureMessage(error, '操作失败，请重试'));
      }
    } finally {
      if (mounted && request.current) setState(() => _busy = false);
    }
  }

  Future<void> _kickMember(int userId, String nickname) => _memberAction(
        '/api/im/conversation/${widget.conversationId}/kick',
        target: userId,
        ownerOnly: true,
        success: '已踢出',
        refreshParent: true,
        prepare: () => _confirm(
            '踢出成员',
            '确定将「$nickname」移出${widget.isTribe ? '部落' : '群聊'}？',
            {'userId': userId}),
      );

  Future<void> _setAdmin(int userId, bool admin) => _memberAction(
        '/api/im/conversation/${widget.conversationId}/admin',
        target: userId,
        ownerOnly: true,
        data: {'userId': userId, 'admin': admin},
        success: admin ? '已设为管理员' : '已取消管理员',
      );

  Future<void> _setMuted(int userId, bool muted) => _memberAction(
        '/api/im/conversation/${widget.conversationId}/mute-member',
        target: userId,
        data: {'userId': userId, 'muted': muted},
        success: muted ? '已禁言' : '已解除禁言',
      );

  Future<void> _transferOwner(int userId, String nickname) => _memberAction(
        '/api/im/conversation/${widget.conversationId}/transfer-owner',
        target: userId,
        ownerOnly: true,
        success: '群主已转让',
        refreshParent: true,
        prepare: () => _confirm(
            '转让群主', '确定将群主转让给「$nickname」？转让后你将成为普通成员。', {'userId': userId},
            confirmText: '确认转让'),
      );

  Future<void> _cancelInvite(int inviteId) => _memberAction(
        '/api/im/group/invite/$inviteId/cancel',
        success: '邀请已撤销',
      );

  Future<void> _editTribeMember(int userId, String nickname,
      String currentTitle, String currentStatus) async {
    final teamId = _teamId;
    if (teamId == null) return;
    await _memberAction(
      '/api/im/team/$teamId/member/$userId',
      target: userId,
      success: '部落身份已更新',
      prepare: () async {
        var title = currentTitle;
        var memberStatus =
            currentStatus == 'probation' ? 'probation' : 'active';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                    title: Text('设置$nickname的部落身份'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          initialValue: title,
                          maxLength: 32,
                          onChanged: (value) => title = value,
                          decoration: const InputDecoration(
                              labelText: '成员职能称号', hintText: '例如：寻宠信息核查')),
                      DropdownButtonFormField<String>(
                        initialValue: memberStatus,
                        decoration: const InputDecoration(labelText: '成员阶段'),
                        items: const [
                          DropdownMenuItem(
                              value: 'probation',
                              child: Text('实习成员（同样显示部落标识）')),
                          DropdownMenuItem(
                              value: 'active', child: Text('正式成员')),
                        ],
                        onChanged: (value) =>
                            update(() => memberStatus = value ?? 'active'),
                      ),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('保存')),
                    ],
                  )),
        );
        return confirmed == true
            ? {'skillTitle': title.trim(), 'membershipStatus': memberStatus}
            : null;
      },
    );
  }

  void _showMemberActions(
    int userId,
    String nickname,
    bool canKick, {
    required bool canManage,
    required bool isAdmin,
    required bool muted,
    String memberTitle = '',
    String membershipStatus = 'active',
  }) {
    if (_sessionExpired || _busy) return;
    final request = ImWorkflowRequest();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => ImWorkflowSessionBoundary(
        request: request,
        expiredBuilder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(imSessionChangedMessage,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.person_outline_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text('查看主页'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const ReferenceActionGlyph(
                type: ReferenceActionIconType.report,
                size: 24,
                color: AppColors.textSecondary,
              ),
              title: const Text('举报用户'),
              onTap: () {
                Navigator.pop(ctx);
                showReportSheet(
                  context,
                  targetType: 'user',
                  targetId: userId,
                  title: '举报用户',
                );
              },
            ),
            if (canKick)
              if (_isOwner)
                ListTile(
                  leading: Icon(
                    isAdmin
                        ? Icons.admin_panel_settings_outlined
                        : Icons.admin_panel_settings_rounded,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(isAdmin ? '取消管理员' : '设为管理员'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setAdmin(userId, !isAdmin);
                  },
                ),
            if (canKick && _isOwner)
              ListTile(
                leading: const Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.textSecondary,
                ),
                title: const Text('转让群主'),
                onTap: () {
                  Navigator.pop(ctx);
                  _transferOwner(userId, nickname);
                },
              ),
            if (canManage)
              if (widget.isTribe)
                ListTile(
                  leading: const Icon(
                    Icons.badge_outlined,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('设置部落职能与阶段'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editTribeMember(
                      userId,
                      nickname,
                      memberTitle,
                      membershipStatus,
                    );
                  },
                ),
            if (canManage)
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.record_voice_over_rounded
                      : Icons.mic_off_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(muted ? '解除禁言' : '禁言成员'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setMuted(userId, !muted);
                },
              ),
            if (canKick)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: Colors.red,
                ),
                title: Text(
                  '移出${widget.isTribe ? '部落' : '群聊'}',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _kickMember(userId, nickname);
                },
              ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTribe ? '部落成员' : '${widget.title} - 群成员'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessionExpired
              ? const Center(
                  child: ImWorkflowRetry(
                      message: imSessionChangedMessage, onRetry: null))
              : Column(children: [
                  if (_error != null)
                    ImWorkflowRetry(
                        message: _error!, onRetry: _busy ? null : _loadMembers),
                  if (_members.isEmpty && _error == null)
                    const Padding(
                        padding: EdgeInsets.all(24), child: Text('暂无成员')),
                  Expanded(
                      child: RefreshIndicator(
                          onRefresh: _loadMembers,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _members.length +
                                (_pendingInvites.isEmpty
                                    ? 0
                                    : _pendingInvites.length + 1),
                            itemBuilder: (context, index) {
                              if (_pendingInvites.isNotEmpty && index == 0) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                  child: Text(
                                    '待确认邀请',
                                    style: AppTextStyles.titleSmall.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }
                              if (_pendingInvites.isNotEmpty &&
                                  index <= _pendingInvites.length) {
                                final invite = _pendingInvites[index - 1];
                                final inviteId =
                                    (invite['inviteId'] as num?)?.toInt();
                                final nickname =
                                    invite['nickname'] as String? ?? '用户';
                                final avatarUrl =
                                    invite['avatarUrl'] as String?;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    backgroundImage: avatarUrl != null &&
                                            avatarUrl.isNotEmpty
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child:
                                        avatarUrl == null || avatarUrl.isEmpty
                                            ? Text(nickname.isNotEmpty
                                                ? nickname[0]
                                                : '?')
                                            : null,
                                  ),
                                  title: Text(nickname),
                                  subtitle: const Text('等待对方确认'),
                                  trailing: TextButton(
                                    onPressed: _busy ||
                                            !_permissionsValid ||
                                            inviteId == null
                                        ? null
                                        : () => _cancelInvite(inviteId),
                                    child: const Text('撤销'),
                                  ),
                                );
                              }
                              final memberIndex = index -
                                  (_pendingInvites.isEmpty
                                      ? 0
                                      : _pendingInvites.length + 1);
                              final m = _members[memberIndex];
                              final userId = (m['userId'] as num?)?.toInt();
                              final nickname = m['nickname'] as String? ?? '用户';
                              final avatarUrl = m['avatarUrl'] as String?;
                              final role = m['role'] as String? ?? 'member';
                              final muted = m['muted'] == true;
                              final isMe = userId == _myUserId;
                              final canKick = _permissionsValid &&
                                  _isOwner &&
                                  !isMe &&
                                  role != 'owner';
                              final canManageMember = _permissionsValid &&
                                  _canManage &&
                                  !isMe &&
                                  role != 'owner';
                              final memberTitle =
                                  m['skillTitle']?.toString() ?? '';
                              final membershipStatus =
                                  m['membershipStatus']?.toString() ?? 'active';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primaryLight,
                                  backgroundImage:
                                      avatarUrl != null && avatarUrl.isNotEmpty
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? Text(nickname.isNotEmpty
                                          ? nickname[0]
                                          : '?')
                                      : null,
                                ),
                                onTap: userId != null
                                    ? () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                UserProfilePage(userId: userId),
                                          ),
                                        )
                                    : null,
                                onLongPress: userId != null
                                    ? () => _showMemberActions(
                                          userId,
                                          nickname,
                                          canKick,
                                          canManage: canManageMember,
                                          isAdmin: role == 'admin',
                                          muted: muted,
                                          memberTitle: memberTitle,
                                          membershipStatus: membershipStatus,
                                        )
                                    : null,
                                title: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  runSpacing: 4,
                                  children: [
                                    Text(nickname,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    if (role == 'owner') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          widget.isTribe ? '部落主' : '群主',
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (role == 'admin') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '管理员',
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (muted) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '禁言',
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (widget.isTribe &&
                                        membershipStatus == 'probation') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF2D6),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '实习',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9B6816),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle:
                                    widget.isTribe && memberTitle.isNotEmpty
                                        ? Text(memberTitle)
                                        : null,
                                trailing: IconButton(
                                  icon: Icon(
                                    (canKick || canManageMember)
                                        ? Icons.more_horiz_rounded
                                        : Icons.chevron_right_rounded,
                                  ),
                                  onPressed: userId != null
                                      ? () => _showMemberActions(
                                            userId,
                                            nickname,
                                            canKick,
                                            canManage: canManageMember,
                                            isAdmin: role == 'admin',
                                            muted: muted,
                                            memberTitle: memberTitle,
                                            membershipStatus: membershipStatus,
                                          )
                                      : null,
                                ),
                              );
                            },
                          ))),
                ]),
    );
  }
}
