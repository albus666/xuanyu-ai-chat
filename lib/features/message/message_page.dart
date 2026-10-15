import 'conversation_preview.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/date_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/user_profile_page.dart';
import '../consultation/voice_room_overlay_controller.dart';
import 'chat_apply_page.dart';
import 'ai_square_page.dart';
import 'chat_page.dart';
import 'joinable_groups_page.dart';
import 'master_consult_entry_page.dart';
import 'create_group_page.dart';
import 'create_team_page.dart';
import 'notification_list_page.dart';
import 'im_workflow_request.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key, this.onBadgeChanged});

  final ValueChanged<int>? onBadgeChanged;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> with WidgetsBindingObserver {
  final _conversations = <Map<String, dynamic>>[];
  final _partyUsers = <Map<String, dynamic>>[];
  int _applyCount = 0;
  int _notificationUnreadCount = 0;
  bool _loading = true;
  bool _partyLoading = false;
  bool _notificationRefreshing = false;
  String _partySnapshot = '';
  Timer? _partyRefreshTimer;
  Future<void>? _loadFuture;
  int _loadRevision = 0;
  int _conversationRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
    _loadPartyPresence();
    _partyRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _loadPartyPresence();
        _refreshNotificationCount();
      }
    });
  }

  @override
  void dispose() {
    _partyRefreshTimer?.cancel();
    apiSessionChanges.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPartyPresence();
      _refreshNotificationCount();
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadPartyPresence()]);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _loadRevision++;
    _conversationRevision++;
    _loadFuture = null;
    setState(() {
      _conversations.clear();
      _partyUsers.clear();
      _partySnapshot = '';
      _partyLoading = false;
      _applyCount = _notificationUnreadCount = 0;
      _loading = false;
    });
    _notifyBadge();
    if (apiClient.options.headers['Authorization'] != null) {
      _load();
      _loadPartyPresence();
    }
  }

  Future<void> _refreshNotificationCount() async {
    if (!mounted ||
        _notificationRefreshing ||
        apiClient.options.headers['Authorization'] == null) {
      return;
    }
    _notificationRefreshing = true;
    final request = ImWorkflowRequest();
    final revision = _loadRevision;
    try {
      final data = await request.get(
        '/api/community/notifications/unread-count',
      );
      if (!mounted || !request.current || revision != _loadRevision) return;
      setState(
        () => _notificationUnreadCount =
            (data['unreadCount'] as num?)?.toInt() ?? 0,
      );
      _notifyBadge();
    } on DioException catch (_) {
    } on ImWorkflowFailure catch (_) {
    } finally {
      _notificationRefreshing = false;
    }
  }

  Future<void> _loadPartyPresence() async {
    if (_partyLoading || !mounted) return;
    _partyLoading = true;
    final request = ImWorkflowRequest();
    try {
      final data = await request.get('/api/im/party-presence');
      final next = imResponseList(data)
          .where(
            (item) =>
                (item['userId'] as num?)?.toInt() != null &&
                (item['roomId'] as num?)?.toInt() != null,
          )
          .toList();
      final snapshot = next
          .map(
            (item) =>
                '${item['userId']}:${item['roomId']}:${item['nickname']}:${item['avatarUrl']}',
          )
          .join('|');
      if (!mounted || !request.current || snapshot == _partySnapshot) return;
      setState(() {
        _partySnapshot = snapshot;
        _partyUsers
          ..clear()
          ..addAll(next);
      });
    } on DioException catch (_) {
      // 派对动态加载失败不影响消息会话本身。
    } on ImWorkflowFailure catch (_) {
    } finally {
      if (request.current) _partyLoading = false;
    }
  }

  Future<void> _reload() {
    // Returning from a screen can change read/deletion state on the server.
    // Do not join a read that started before that change.
    _loadRevision++;
    _loadFuture = null;
    return _load();
  }

  Future<void> _load() {
    if (!mounted) return Future.value();
    final pending = _loadFuture;
    if (pending != null) return pending;
    final revision = ++_loadRevision;
    final future = _loadSections(revision);
    _loadFuture = future;
    return future.whenComplete(() {
      if (revision == _loadRevision) _loadFuture = null;
    });
  }

  Future<void> _loadSections(int revision) async {
    final request = ImWorkflowRequest();
    final conversationRevision = _conversationRevision;
    bool current() => mounted && request.current && revision == _loadRevision;
    setState(() => _loading = true);

    Future<Map<String, dynamic>?> read(String path) async {
      try {
        return await request.get(path);
      } on DioException catch (_) {
        return null;
      } on ImWorkflowFailure catch (_) {
        return null;
      }
    }

    Future<void> conversations() async {
      try {
        final data = await read('/api/im/conversations');
        if (!current() || conversationRevision != _conversationRevision) return;
        if (data != null && data['list'] is List) {
          setState(() {
            _conversations
              ..clear()
              ..addAll(
                (data['list'] as List).whereType<Map>().map(
                      (item) => Map<String, dynamic>.from(item),
                    ),
              );
          });
          _notifyBadge();
        }
      } finally {
        // The conversation list need not wait for slower shortcut counts.
        if (current()) setState(() => _loading = false);
      }
    }

    Future<void> applications() async {
      final sections = await Future.wait([
        read('/api/im/chat/applies'),
        read('/api/im/group/join-applies'),
        read('/api/im/group/invites'),
      ]);
      if (!current() || sections.any((data) => data == null)) return;
      setState(
        () => _applyCount = sections.fold<int>(
          0,
          (sum, data) => sum + ((data?['list'] as List?)?.length ?? 0),
        ),
      );
      _notifyBadge();
    }

    Future<void> notifications() async {
      final data = await read('/api/community/notifications/unread-count');
      if (!current() || data == null) return;
      setState(
        () => _notificationUnreadCount =
            (data['unreadCount'] as num?)?.toInt() ?? 0,
      );
      _notifyBadge();
    }

    await Future.wait([conversations(), applications(), notifications()]);
  }

  void _notifyBadge() {
    final total = _applyCount +
        _notificationUnreadCount +
        _conversations.fold<int>(
            0, (sum, c) => sum + ((c['unreadCount'] as num?)?.toInt() ?? 0));
    widget.onBadgeChanged?.call(total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        title: Text('我的消息', style: AppTextStyles.titleLarge),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiSquarePage()),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('AI 聊天'),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.textPrimary),
            onPressed: _showCreateMenu,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildShortcutItem(
                      icon: Icons.notifications_none_rounded,
                      label: '通知',
                      color: const Color(0xFFFEE2E2),
                      iconColor: const Color(0xFFDC2626),
                      badge: _notificationUnreadCount,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => const NotificationListPage()))
                          .then((_) => _reload()),
                    ),
                    _buildShortcutItem(
                      icon: Icons.person_add_outlined,
                      label: '申请与邀请',
                      color: const Color(0xFFECFDF5),
                      iconColor: const Color(0xFF059669),
                      badge: _applyCount,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => const ChatApplyPage()))
                          .then((_) => _reload()),
                    ),
                    _buildShortcutItem(
                      icon: Icons.groups_outlined,
                      label: '群聊与部落',
                      color: const Color(0xFFF0F9FF),
                      iconColor: const Color(0xFF2563EB),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) =>
                                  JoinableGroupsPage(onJoined: _load)))
                          .then((_) => _reload()),
                    ),
                    _buildShortcutItem(
                      icon: Icons.school_outlined,
                      label: '咨询',
                      color: const Color(0xFFFFFBEB),
                      iconColor: const Color(0xFFD97706),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => const MasterConsultEntryPage()))
                          .then((_) => _reload()),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && _conversations.isEmpty)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
            else if (_conversations.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 64,
                          color: AppColors.textHint.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('暂无消息记录',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final c = _conversations[index];
                    return _buildConversationTile(c);
                  },
                  childCount: _conversations.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openParty(Map<String, dynamic> user) {
    final roomId = (user['roomId'] as num?)?.toInt();
    if (roomId == null) return;
    final opened = VoiceRoomOverlayController.instance.open(roomId);
    if (!opened && mounted) showAppToast(context, '请先退出当前语音房');
  }

  Widget _buildShortcutItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5)),
                    child: Text(badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 会话列表最后一条展示文案：帖子类不显示后端/字典原始数据，统一为 [帖子]
  static String _conversationLastMessageLabel(String last) =>
      conversationPreview(last);

  Widget _buildConversationTile(Map<String, dynamic> c) {
    final id = (c['conversationId'] as num?)?.toInt();
    final title = c['title'] as String? ?? '会话';
    final convType = c['type'] as String? ?? 'single';
    final peerUserId = (c['peerUserId'] as num?)?.toInt();
    final partyUser = _partyUserFor(peerUserId);
    final last = c['lastMessage'] as String? ?? '';
    final time = c['lastMessageAt'] as String? ?? '';
    final unread = (c['unreadCount'] as num?)?.toInt() ?? 0;
    final pinned = c['pinned'] == true || c['top'] == true;
    final muted = c['mute'] == true || c['muted'] == true;

    // 自动适配多种可能的字段名 (兼容 Django 常见的下划线命名)
    String? rawAvatar =
        c['avatarUrl'] ?? c['peerAvatarUrl'] ?? c['avatar'] ?? c['peer_avatar'];

    // 如果是相对路径，自动补全 BaseURL
    String? avatarUrl = rawAvatar;
    if (avatarUrl != null && !avatarUrl.startsWith('http')) {
      final baseUrl = apiClient.options.baseUrl;
      avatarUrl = baseUrl + (avatarUrl.startsWith('/') ? '' : '/') + avatarUrl;
    }

    if (id == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () => Navigator.of(context)
          .push(
            MaterialPageRoute(
                builder: (_) => ChatPage(
                      conversationId: id,
                      title: title,
                      conversationType: convType,
                      peerUserId: peerUserId,
                    )),
          )
          .then((_) => _reload()),
      onLongPress: () => _showConversationMenu(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(title, avatarUrl, peerUserId, unread, partyUser),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (pinned) ...[
                              const Icon(Icons.push_pin_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: AppTextStyles.titleSmall.copyWith(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (muted) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.notifications_off_outlined,
                                  size: 14, color: AppColors.textHint),
                            ],
                          ],
                        ),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(AppDateUtils.formatRelative(time),
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textHint, fontSize: 11)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_conversationLastMessageLabel(last),
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationMenu(Map<String, dynamic> c) {
    final id = (c['conversationId'] as num?)?.toInt();
    if (id == null) return;
    final request = ImWorkflowRequest();
    final title = c['title'] as String? ?? '会话';
    final pinned = c['pinned'] == true || c['top'] == true;
    final muted = c['mute'] == true || c['muted'] == true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: AppColors.textSecondary),
              title: Text(pinned ? '取消置顶' : '置顶会话'),
              onTap: () {
                Navigator.pop(ctx);
                if (!mounted || !request.current) return;
                _toggleConversationFlag(id, 'pinned', !pinned);
              },
            ),
            ListTile(
              leading: Icon(
                  muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: AppColors.textSecondary),
              title: Text(muted ? '取消免打扰' : '消息免打扰'),
              onTap: () {
                Navigator.pop(ctx);
                if (!mounted || !request.current) return;
                _toggleConversationFlag(id, 'mute', !muted);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('删除会话', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                if (!mounted || !request.current) return;
                _confirmDeleteConversation(id, title);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleConversationFlag(
    int conversationId,
    String key,
    bool value,
  ) async {
    final request = ImWorkflowRequest();
    try {
      await request.patch(
        '/api/im/conversation/$conversationId',
        data: {key: value},
      );
      if (!mounted || !request.current) return;
      _conversationRevision++;
      setState(() {
        final i = _conversations.indexWhere(
          (e) => (e['conversationId'] as num?)?.toInt() == conversationId,
        );
        if (i >= 0) _conversations[i][key] = value;
      });
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      if (mounted && request.current) showAppToast(context, msg ?? '操作失败');
    } on ImWorkflowFailure catch (error) {
      if (mounted && request.current) showAppToast(context, error.message);
    }
  }

  Future<void> _confirmDeleteConversation(
    int conversationId,
    String title,
  ) async {
    final request = ImWorkflowRequest();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「$title」这条会话记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !request.current) return;
    try {
      await request.post('/api/im/conversation/$conversationId/delete');
      if (mounted && request.current) {
        _conversationRevision++;
        setState(
          () => _conversations.removeWhere(
            (e) => e['conversationId'] == conversationId,
          ),
        );
        _notifyBadge();
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      if (mounted && request.current) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除失败'),
            content: Text(msg ?? '当前服务暂不支持删除会话，请稍后再试。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } on ImWorkflowFailure catch (error) {
      if (mounted && request.current) showAppToast(context, error.message);
    }
  }

  Map<String, dynamic>? _partyUserFor(int? userId) {
    if (userId == null) return null;
    for (final item in _partyUsers) {
      if ((item['userId'] as num?)?.toInt() == userId) return item;
    }
    return null;
  }

  Widget _buildAvatar(String title, String? avatarUrl, int? peerUserId,
      int unread, Map<String, dynamic>? partyUser) {
    final inParty = partyUser != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: inParty
              ? () => _openParty(partyUser)
              : peerUserId != null
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => UserProfilePage(userId: peerUserId)))
                  : null,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: inParty
                    ? const Color(0xFF328DF4)
                    : AppColors.divider.withValues(alpha: 0.5),
                width: inParty ? 2.5 : 1,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(
                      title.isNotEmpty ? title[0] : '?',
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.primary),
                    )
                  : null,
            ),
          ),
        ),
        if (inParty)
          Positioned(
            left: 1,
            right: 1,
            bottom: -7,
            child: Container(
              height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF328DF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Text(
                '在派对中',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.groups_outlined, color: AppColors.primary),
              title: const Text('创建群聊'),
              onTap: () {
                Navigator.pop(ctx);
                _toCreateGroup();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.shield_outlined, color: AppColors.primary),
              title: const Text('创建部落'),
              subtitle: Text('自带部落群聊，群主可设置部落头像与头衔',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint)),
              onTap: () {
                Navigator.pop(ctx);
                _toCreateTeam();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _toCreateGroup() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(builder: (_) => const CreateGroupPage()),
    )
        .then((result) {
      if (!mounted) return;
      if (result is Map && result['conversationId'] != null) {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                  builder: (_) => ChatPage(
                      conversationId: result['conversationId'],
                      title: result['title'],
                      conversationType: 'group')),
            )
            .then((_) => _reload());
      } else {
        _load();
      }
    });
  }

  void _toCreateTeam() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(builder: (_) => const CreateTeamPage()),
    )
        .then((result) {
      if (!mounted) return;
      if (result is Map && result['conversationId'] != null) {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                  builder: (_) => ChatPage(
                      conversationId: result['conversationId'],
                      title: result['title'],
                      conversationType: 'group')),
            )
            .then((_) => _reload());
      } else {
        _load();
      }
    });
  }
}
