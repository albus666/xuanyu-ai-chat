import '../../core/utils/app_toast.dart';
import '../../core/network/api_session_scope.dart';
import '../consultation/consultation_call_overlay.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../shop/shop_orders_page.dart';
import '../../core/network/api_client.dart';
import '../community/user_profile_page.dart';
import '../../core/utils/date_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/post_detail_page.dart';
import '../home/announcements_page.dart';
import '../shop/goodwill_echo_page.dart';
import '../consultation/consultation_history_page.dart';
import '../consultation/consultation_after_sales_page.dart';
import '../consultation/teacher_workbench_page.dart';

class NotificationListPage extends StatefulWidget {
  const NotificationListPage({super.key});

  @override
  State<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage> {
  /// 合并列表：每条带 "source": "interaction" | "system"
  final _list = <Map<String, dynamic>>[];
  int _unreadCount = 0;
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  final _deleting = <String>{};
  Future<void> _deleteNotification(Map<String, dynamic> notification) async {
    final scope = ApiSessionScope();
    final id = notification['id'];
    final source = notification['source'];
    final key = '$source:$id';
    if (id == null || !_deleting.add(key)) return;
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(title: const Text('删除这条通知？'), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除'))
              ]));
      if (confirmed != true || !mounted || !scope.current) return;
      final kind =
          source == 'system' ? 'system-notifications' : 'notifications';
      await scope.delete('/api/community/$kind/$id');
      if (!mounted || !scope.current) return;
      setState(() {
        _list.removeWhere((n) => n['source'] == source && n['id'] == id);
        if (notification['read'] != true && _unreadCount > 0) _unreadCount--;
      });
    } catch (_) {
      if (mounted && scope.current) showAppToast(context, '删除失败，请重试');
    } finally {
      _deleting.remove(key);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _page = 1;
    _list.clear();
    await _fetchFirstPage();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchFirstPage() async {
    try {
      final notifRes = apiClient.get(
        '/api/community/notifications',
        queryParameters: {'page': 1, 'page_size': 20},
      );
      final sysRes = apiClient.get(
        '/api/community/system-notifications',
        queryParameters: {'page': 1, 'page_size': 20},
      );
      final notif = await notifRes;
      final sys = await sysRes;
      final data = (notif.data as Map?)?['data'] as Map?;
      final items = data?['list'] as List<dynamic>?;
      final unread = (data?['unreadCount'] as num?)?.toInt();
      final sysData = (sys.data as Map?)?['data'] as Map?;
      final sysList = sysData?['list'] as List<dynamic>?;

      final combined = <Map<String, dynamic>>[];
      if (items != null) {
        for (final e in items) {
          if (e is Map<String, dynamic>) {
            final m = Map<String, dynamic>.from(e);
            m['source'] = 'interaction';
            combined.add(m);
          }
        }
      }
      if (sysList != null) {
        for (final e in sysList) {
          if (e is Map<String, dynamic>) {
            final m = Map<String, dynamic>.from(e);
            m['source'] = 'system';
            combined.add(m);
          }
        }
      }
      combined.sort((a, b) {
        final at = a['createdAt'] as String? ?? '';
        final bt = b['createdAt'] as String? ?? '';
        return bt.compareTo(at);
      });

      int totalUnread = unread ?? 0;
      try {
        final ucRes =
            await apiClient.get('/api/community/notifications/unread-count');
        final ucData = (ucRes.data as Map?)?['data'] as Map?;
        totalUnread = (ucData?['unreadCount'] as num?)?.toInt() ?? totalUnread;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _list.clear();
          _list.addAll(combined);
          _unreadCount = totalUnread;
          _hasMore = (items?.length ?? 0) >= 20;
          _page = 2;
        });
      }
    } on DioException catch (_) {}
  }

  Future<void> _fetchPage() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await apiClient.get(
        '/api/community/notifications',
        queryParameters: {'page': _page, 'page_size': 20},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final items = data?['list'] as List<dynamic>?;
      final hasMore = data?['hasMore'] as bool? ?? false;
      if (mounted && items != null && items.isNotEmpty) {
        final toAdd = <Map<String, dynamic>>[];
        for (final e in items) {
          if (e is Map<String, dynamic>) {
            final m = Map<String, dynamic>.from(e);
            m['source'] = 'interaction';
            toAdd.add(m);
          }
        }
        setState(() {
          _list.addAll(toAdd);
          _list.sort((a, b) {
            final at = a['createdAt'] as String? ?? '';
            final bt = b['createdAt'] as String? ?? '';
            return bt.compareTo(at);
          });
          _hasMore = hasMore;
          _page++;
          _loadingMore = false;
        });
      } else {
        if (mounted) setState(() => _loadingMore = false);
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markRead(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await apiClient
          .post('/api/community/notifications/read', data: {'ids': ids});
      if (mounted) {
        setState(() {
          for (final n in _list) {
            if (ids.contains((n['id'] as num?)?.toInt())) n['read'] = true;
          }
          _unreadCount = (_unreadCount - ids.length).clamp(0, 0x7fffffff);
        });
      }
    } catch (_) {}
  }

  Future<void> _markSystemRead(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await apiClient
          .post('/api/community/system-notifications/read', data: {'ids': ids});
      if (mounted) {
        setState(() {
          for (final n in _list) {
            if (n['source'] == 'system' &&
                ids.contains((n['id'] as num?)?.toInt())) {
              n['read'] = true;
            }
          }
          _unreadCount = (_unreadCount - ids.length).clamp(0, 0x7fffffff);
        });
      }
    } catch (_) {}
  }

  void _openPost(int postId, Map<String, dynamic> n) {
    final id = (n['id'] as num?)?.toInt();
    if (id != null && n['read'] != true) _markRead([id]);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailPage(postId: postId)));
  }

  Map<String, dynamic> _systemExtra(Map<String, dynamic> notification) {
    final raw = notification['extraJson'] ??
        notification['extra'] ??
        notification['extra_json'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  String _systemTypeLabel(String type, String fallback) {
    if (type.startsWith('consultation_appointment')) return '预约通知';
    if (type == 'consultation_waiting') return '专线来电';
    if (type == 'consultation_accepted') return '专线已接听';
    if (type.startsWith('consultation_dispute')) return '咨询售后';
    if (type == 'shop_presale') return '预售订单';
    if (type == 'goodwill_review') return '善意回声';
    return fallback.trim().isEmpty ? '系统通知' : fallback;
  }

  void _openSystemNotification(Map<String, dynamic> notification) {
    final id = (notification['id'] as num?)?.toInt();
    if (id != null && notification['read'] != true) _markSystemRead([id]);
    final type = notification['type']?.toString() ?? '';
    if (type == 'announcement') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
      );
      return;
    }
    if (type == 'goodwill_review') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GoodwillEchoPage()),
      );
      return;
    }
    if (type == 'shop_presale') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ShopOrdersPage()));
      return;
    }
    if (!type.startsWith('consultation_')) return;
    final extra = _systemExtra(notification);
    final destination = extra['destination']?.toString();
    final sessionId =
        int.tryParse('${extra['sessionId'] ?? extra['session_id'] ?? ''}');
    if ((type == 'consultation_accepted' || type == 'consultation_waiting') &&
        sessionId != null) {
      try {
        ConsultationCallOverlay.instance.open(sessionId);
      } catch (_) {
        showAppToast(context, '请先结束当前专线，再进入这条咨询');
      }
      return;
    }
    final Widget page = destination == 'consultation_after_sales'
        ? const ConsultationAfterSalesPage()
        : destination == 'teacher_workbench' ||
                destination == 'teacher_incoming_call' ||
                (destination == null &&
                    (type == 'consultation_appointment' ||
                        type == 'consultation_waiting'))
            ? const TeacherWorkbenchPage()
            : const ConsultationHistoryPage();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(_unreadCount > 0 ? '通知 ($_unreadCount)' : '通知',
            style: AppTextStyles.titleMedium),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: () async {
                try {
                  await apiClient.post('/api/community/notifications/read',
                      data: {'ids': []});
                  await apiClient.post(
                      '/api/community/system-notifications/read',
                      data: {'ids': []});
                  if (mounted) {
                    setState(() {
                      for (final n in _list) {
                        n['read'] = true;
                      }
                      _unreadCount = 0;
                    });
                  }
                } catch (_) {}
              },
              child: const Text('全部已读',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _list.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _list.length) {
                        _fetchPage();
                        return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final n = _list[index];
                      return Stack(children: [
                        n['source'] == 'system'
                            ? _buildSystemNotificationCard(n)
                            : _buildNotificationCard(n),
                        Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton(
                                tooltip: '删除通知',
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20),
                                onPressed: () => _deleteNotification(n))),
                      ]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 80, color: AppColors.textHint.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无通知',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildSystemNotificationCard(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final typeText = _systemTypeLabel(
      type,
      n['typeText']?.toString() ?? '系统通知',
    );
    final title = n['title'] as String? ?? '';
    final content = n['content'] as String? ?? '';
    final read = n['read'] == true;
    final createdAt = n['createdAt'] as String? ?? '';
    final canOpen = type == 'announcement' ||
        type == 'goodwill_review' ||
        type == 'shop_presale' ||
        type.startsWith('consultation_');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: InkWell(
        onTap: () => _openSystemNotification(n),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: type == 'post_removed'
                      ? const Color(0xFFFEE2E2)
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  type == 'post_removed'
                      ? Icons.warning_amber_rounded
                      : Icons.campaign_rounded,
                  color: type == 'post_removed'
                      ? const Color(0xFFDC2626)
                      : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(typeText,
                              style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: read
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary)),
                        ),
                        if (!read)
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle)),
                      ],
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(title,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(content,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppDateUtils.formatRelative(createdAt),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textHint,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (canOpen)
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final typeText = n['typeText'] as String? ?? '点赞';
    final fromUserId = (n['fromUserId'] as num?)?.toInt();
    final fromNickname = n['fromNickname'] as String? ?? '用户';
    final fromAvatarUrl = n['fromAvatarUrl'] as String?;
    final contentSnippet = n['contentSnippet'] as String? ?? '';
    final postId = (n['postId'] as num?)?.toInt();
    final read = n['read'] == true;
    final createdAt = n['createdAt'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: InkWell(
        onTap: postId != null ? () => _openPost(postId, n) : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(fromUserId, fromAvatarUrl, fromNickname),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textPrimary),
                              children: [
                                TextSpan(
                                    text: fromNickname,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                TextSpan(
                                    text: ' $typeText了您的帖子',
                                    style: TextStyle(
                                        color: read
                                            ? AppColors.textSecondary
                                            : AppColors.textPrimary)),
                              ],
                            ),
                          ),
                        ),
                        if (!read)
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (contentSnippet.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(contentSnippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary, height: 1.4)),
                      ),
                    const SizedBox(height: 8),
                    Text(AppDateUtils.formatRelative(createdAt),
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(int? userId, String? url, String name) {
    return GestureDetector(
      onTap: () {
        if (userId != null) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UserProfilePage(userId: userId)));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
            shape: BoxShape.circle),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primaryLight,
          backgroundImage:
              (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty)
              ? Text(name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold))
              : null,
        ),
      ),
    );
  }
}
