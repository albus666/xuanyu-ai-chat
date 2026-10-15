import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/foreground_refresh.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/user_profile_page.dart';
import '../profile/recharge_page.dart';
import 'chat_page.dart';
import 'master_deposit_pay_page.dart';

/// 名师接单状态（与后端 `consultStatus` / `availability` 等字段对齐）
enum MasterAvailability {
  idle,
  busy,
  offline,
}

/// 真人名师列表：任意状态均先「付定金」（说明 + 备注）再支付；空闲且在支付页确认成功后自动发起咨询会话。
class RealMasterListPage extends StatefulWidget {
  const RealMasterListPage({super.key});

  @override
  State<RealMasterListPage> createState() => _RealMasterListPageState();
}

class _RealMasterListPageState extends State<RealMasterListPage> {
  late final ForegroundRefresh _presenceRefresh;
  final _list = <Map<String, dynamic>>[];
  bool _loading = true;
  /// 正在拉取在线状态的导师 userId（用于行内小菊花）
  int? _presenceLoadingUserId;

  @override
  void initState() {
    super.initState();
    _presenceRefresh = ForegroundRefresh(
      refresh: () async {
        final ids = _list
            .map((e) => (e['userId'] as num?)?.toInt())
            .whereType<int>()
            .toList();
        await _applyBatchPresence(ids);
      },
      isVisible: () =>
          mounted &&
          !_loading &&
          _presenceLoadingUserId == null &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    )..attach();
    _load();
  }

  @override
  void dispose() {
    _presenceRefresh.dispose();
    super.dispose();
  }

  Future<void> _load({bool showGlobalLoading = true}) async {
    if (showGlobalLoading) setState(() => _loading = true);
    try {
      final res = await apiClient.get('/api/community/masters');
      final data = (res.data as Map?)?['data'] as Map?;
      final raw = data?['list'] as List<dynamic>?;
      if (mounted && raw != null) {
        setState(() {
          _list.clear();
          for (final e in raw) {
            if (e is Map<String, dynamic>) _list.add(Map<String, dynamic>.from(e));
          }
        });
        final ids = _list.map((e) => (e['userId'] as num?)?.toInt()).whereType<int>().toList();
        if (ids.isNotEmpty) await _applyBatchPresence(ids);
      }
    } on DioException catch (e) {
      if (mounted && showGlobalLoading) {
        final msg = (e.response?.data is Map && (e.response!.data as Map).containsKey('message'))
            ? (e.response!.data as Map)['message']?.toString()
            : null;
        showAppToast(context, msg ?? '名师列表加载失败，请检查网络或稍后重试');
      }
    }
    if (mounted && showGlobalLoading) setState(() => _loading = false);
  }

  /// 批量拉取名师在线状态（与后端 `POST /api/community/masters/presence/batch` 对齐）
  Future<bool> _applyBatchPresence(List<int> userIds) async {
    if (userIds.isEmpty || !mounted) return true;
    try {
      final res = await apiClient.post('/api/community/masters/presence/batch', data: {'userIds': userIds});
      final data = (res.data as Map?)?['data'] as Map?;
      final items = data?['items'] as List<dynamic>?;
      if (items == null || !mounted) return true;
      setState(() {
        for (final e in items) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final uid = (m['userId'] as num?)?.toInt();
          if (uid != null) _mergeMasterRow(uid, m);
        }
      });
      return true;
    } on DioException catch (_) {
      return false;
    }
  }

  void _mergeMasterRow(int userId, Map<String, dynamic> patch) {
    final idx = _list.indexWhere((e) => (e['userId'] as num?)?.toInt() == userId);
    if (idx < 0) return;
    setState(() {
      final row = Map<String, dynamic>.from(_list[idx]);
      for (final e in patch.entries) {
        if (e.value != null) row[e.key] = e.value;
      }
      _list[idx] = row;
    });
  }

  /// 检查导师是否在线：优先批量接口（单 id 亦走 batch），失败则回退单用户 GET。
  Future<void> _refreshMasterPresence(int userId, {bool quiet = false}) async {
    if (!mounted) return;
    setState(() => _presenceLoadingUserId = userId);
    try {
      final ok = await _applyBatchPresence([userId]);
      if (ok && mounted && !quiet) {
        showAppToast(context, '状态已更新');
        return;
      }
      for (final path in [
        '/api/community/masters/$userId/presence',
        '/api/community/masters/$userId/online-status',
      ]) {
        try {
          final res = await apiClient.get(path);
          final data = (res.data as Map?)?['data'] as Map?;
          if (data != null && mounted) {
            _mergeMasterRow(userId, Map<String, dynamic>.from(data));
            if (!quiet) showAppToast(context, '状态已更新');
            return;
          }
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code != 404 && code != 405) break;
        }
      }
      await _load(showGlobalLoading: false);
      if (mounted && !quiet) showAppToast(context, '列表已刷新');
    } on DioException catch (_) {
      if (mounted && !quiet) showAppToast(context, '状态检查失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _presenceLoadingUserId = null);
    }
  }

  static MasterAvailability _parseAvailability(Map<String, dynamic> m) {
    final online = m['isOnline'] ?? m['online'];
    if (online == false || online == 'false' || online == 0 || online == '0') {
      return MasterAvailability.offline;
    }
    final v = m['consultStatus'] ?? m['availability'] ?? m['onlineStatus'] ?? m['status'];
    if (v == null) return MasterAvailability.idle;
    final s = v.toString().trim().toLowerCase();
    if (s.contains('忙') || s == 'busy') return MasterAvailability.busy;
    if (s.contains('离线') || s == 'offline' || s == 'away') return MasterAvailability.offline;
    if (s.contains('空闲') || s == 'idle' || s == 'free' || s == 'online') return MasterAvailability.idle;
    return MasterAvailability.idle;
  }

  static String _statusLabel(MasterAvailability a) {
    switch (a) {
      case MasterAvailability.idle:
        return '空闲';
      case MasterAvailability.busy:
        return '忙';
      case MasterAvailability.offline:
        return '离线';
    }
  }

  static Color _statusColor(MasterAvailability a) {
    switch (a) {
      case MasterAvailability.idle:
        return const Color(0xFF059669);
      case MasterAvailability.busy:
        return const Color(0xFFD97706);
      case MasterAvailability.offline:
        return AppColors.textHint;
    }
  }

  /// 定金：优先 `depositPrice` / `consultDeposit`，否则按咨询价约 20% 估算（仅展示与支付用，以后端为准）
  static double _depositAmount(Map<String, dynamic> m) {
    final d = m['depositPrice'] ?? m['consultDeposit'];
    if (d is num && d.toDouble() >= 0.01) return d.toDouble();
    final c = (m['consultPrice'] as num?)?.toDouble() ?? 10;
    return (c * 0.2).clamp(1.0, 500.0);
  }

  Future<void> _openChat(Map<String, dynamic> master) async {
    final userId = (master['userId'] as num?)?.toInt();
    final nickname = master['nickname'] as String? ?? '名师';
    if (userId == null) return;
    try {
      final res = await apiClient.post('/api/im/conversation/single-with-master', data: {'targetUserId': userId});
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        final convId = (data['conversationId'] as num?)?.toInt();
        final title = data['title'] as String? ?? nickname;
        if (convId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(
                conversationId: convId,
                title: title,
                conversationType: 'single',
                peerUserId: userId,
                isPeerMaster: true,
              ),
            ),
          );
        }
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map && (e.response!.data as Map).containsKey('message'))
          ? (e.response!.data as Map)['message']?.toString()
          : '发起咨询失败';
      if (mounted) {
        showAppToast(context, msg ?? '发起咨询失败');
        if (msg?.contains('余额不足') == true) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RechargePage()));
        }
      }
    }
  }

  Future<void> _showReserveSheet(Map<String, dynamic> master) async {
    final userId = (master['userId'] as num?)?.toInt();
    final nickname = master['nickname'] as String? ?? '名师';
    if (userId == null) return;
    await _refreshMasterPresence(userId, quiet: true);
    if (!mounted) return;
    final idx = _list.indexWhere((e) => (e['userId'] as num?)?.toInt() == userId);
    final fresh = idx >= 0 ? _list[idx] : master;
    final deposit = _depositAmount(fresh);
    final isIdle = _parseAvailability(fresh) == MasterAvailability.idle;
    final remarkController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('预约 $nickname', style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                Text(
                  isIdle
                      ? '名师当前空闲，也需先支付定金后再进入一对一咨询；支付页将显示「付定金」。'
                      : '名师当前非空闲，请先提交预约意向并支付定金；支付页将显示「付定金」。',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 16),
                Text('参考定金 ¥${deposit.toStringAsFixed(2)}（以支付页为准）', style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF059669))),
                const SizedBox(height: 16),
                TextField(
                  controller: remarkController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '选填：期望沟通时间、简要需求等',
                    hintStyle: AppTextStyles.hint,
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final remark = remarkController.text;
                    Navigator.pop(sheetCtx);
                    if (!mounted) return;
                    final paid = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => MasterDepositPayPage(
                          targetUserId: userId,
                          masterNickname: nickname,
                          depositAmount: deposit,
                          reserveRemark: remark,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    if (paid == true) {
                      if (isIdle) {
                        await _openChat(fresh);
                      } else {
                        showAppToast(context, '预约已提交，名师稍后将联系您');
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('下一步：付定金'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('取消', style: TextStyle(color: AppColors.textHint)),
                ),
              ],
            ),
          ),
        );
      },
    );
    remarkController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('真人名师', style: AppTextStyles.titleMedium),
        actions: [
          IconButton(
            tooltip: '刷新列表与在线状态',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_search_rounded, size: 64, color: AppColors.textHint.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('暂无名师', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final m = _list[i];
                      final uid = (m['userId'] as num?)?.toInt();
                      final nickname = m['nickname'] as String? ?? '名师';
                      final avatarUrl = m['avatarUrl'] as String?;
                      final intro = m['intro'] as String? ?? '认证名师';
                      final avail = _parseAvailability(m);
                      final consultPrice = (m['consultPrice'] as num?)?.toStringAsFixed(0) ?? '10';
                      final deposit = _depositAmount(m);
                      final checking = uid != null && _presenceLoadingUserId == uid;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    final uid = (m['userId'] as num?)?.toInt();
                                    if (uid != null) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => UserProfilePage(userId: uid)),
                                      );
                                    }
                                  },
                                  child: CircleAvatar(
                                    radius: 28,
                                    backgroundColor: const Color(0xFF059669).withValues(alpha: 0.2),
                                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                    child: avatarUrl == null || avatarUrl.isEmpty
                                        ? Text(nickname.isNotEmpty ? nickname[0] : '师', style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF059669)))
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(nickname, style: AppTextStyles.titleSmall, overflow: TextOverflow.ellipsis)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF059669).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('名师', style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _statusColor(avail).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _statusLabel(avail),
                                              style: AppTextStyles.bodySmall.copyWith(color: _statusColor(avail), fontWeight: FontWeight.w600, fontSize: 11),
                                            ),
                                          ),
                                          if (uid != null) ...[
                                            const SizedBox(width: 2),
                                            Tooltip(
                                              message: '检查是否在线',
                                              child: InkWell(
                                                onTap: checking ? null : () => _refreshMasterPresence(uid),
                                                borderRadius: BorderRadius.circular(16),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(4),
                                                  child: checking
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: AppColors.textHint,
                                                          ),
                                                        )
                                                      : const Icon(Icons.sync_rounded, size: 18, color: AppColors.textHint),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(intro, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Text(
                                        '咨询 ¥$consultPrice/次 · 定金 ¥${deposit.toStringAsFixed(2)}',
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Material(
                                      color: const Color(0xFF059669).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      child: InkWell(
                                        onTap: () => _showReserveSheet(m),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          child: Text(
                                            '付定金',
                                            style: AppTextStyles.bodySmall.copyWith(
                                              color: const Color(0xFF059669),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
