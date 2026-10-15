import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../community/user_profile_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'chat_page.dart';
import 'im_workflow_request.dart';

class ChatApplyPage extends StatefulWidget {
  const ChatApplyPage({super.key});

  @override
  State<ChatApplyPage> createState() => _ChatApplyPageState();
}

class _ChatApplyPageState extends State<ChatApplyPage>
    with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _list = [];
  final List<Map<String, dynamic>> _sent = [];
  final List<Map<String, dynamic>> _history = [];
  final Set<String> _selected = {};
  late final TabController _tabController;
  bool _loading = true;
  bool _busy = false;
  int _loadGeneration = 0;
  final _sources = List.generate(7, (_) => <Map<String, dynamic>>[]);
  final _sourceErrors = List.filled(7, false);
  final _hiddenKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging && mounted) {
          setState(_selected.clear);
        }
      });
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _loadGeneration++;
    _tabController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      for (final source in _sources) {
        source.clear();
      }
      _list.clear();
      _sent.clear();
      _history.clear();
      _selected.clear();
      _hiddenKeys.clear();
      _sourceErrors.fillRange(0, 7, false);
      _busy = false;
      _loading = false;
    });
    _load();
  }

  void _mergeSources() {
    List<Map<String, dynamic>> merge(List<int> slots) {
      final unique = <String, Map<String, dynamic>>{};
      for (final slot in slots) {
        for (final item in _sources[slot]) {
          final key = _recordKey(item);
          if (!_hiddenKeys.contains(key)) unique[key] = item;
        }
      }
      return unique.values.toList();
    }

    _list
      ..clear()
      ..addAll(merge([0, 1, 2]));
    _list.sort((a, b) => (b['createdAt']?.toString() ?? '')
        .compareTo(a['createdAt']?.toString() ?? ''));
    _sent
      ..clear()
      ..addAll(merge([3]));
    _history
      ..clear()
      ..addAll(merge([4, 5, 6]));
    _history.sort((a, b) => (b['updatedAt']?.toString() ?? '')
        .compareTo(a['updatedAt']?.toString() ?? ''));
    final available =
        [..._sent, ..._history].where(_isDeletable).map(_recordKey).toSet();
    _selected.removeWhere((key) => !available.contains(key));
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final request = ImWorkflowRequest();
    if (apiClient.options.headers['Authorization'] == null) {
      setState(() {
        _loading = false;
        _sourceErrors.fillRange(0, 7, true);
      });
      return;
    }
    setState(() => _loading = true);
    final specs = [
      ('/api/im/chat/applies', <String, dynamic>{}, 'chatApply', 'single'),
      (
        '/api/im/group/join-applies',
        <String, dynamic>{},
        'groupApply',
        'group'
      ),
      (
        '/api/im/group/invites',
        <String, dynamic>{},
        'groupInvite',
        'groupInvite'
      ),
      (
        '/api/im/group/join-applies',
        <String, dynamic>{'scope': 'sent'},
        'groupApply',
        'group'
      ),
      (
        '/api/im/group/join-applies',
        <String, dynamic>{'scope': 'received', 'status': 'processed'},
        'groupApply',
        'group'
      ),
      (
        '/api/im/chat/applies',
        <String, dynamic>{'status': 'processed'},
        'chatApply',
        'single'
      ),
      (
        '/api/im/group/invites',
        <String, dynamic>{'status': 'processed'},
        'groupInvite',
        'groupInvite'
      ),
    ];
    final results = await Future.wait(specs.map((spec) async {
      try {
        final data = await request.get(spec.$1, query: spec.$2);
        final rows = imResponseList(data);
        if (rows.any((row) => row['id'] is! num)) {
          throw const ImWorkflowFailure('记录数据异常');
        }
        return rows
            .map((row) => {...row, 'recordType': spec.$3, 'type': spec.$4})
            .toList();
      } catch (_) {
        return null;
      }
    }));
    if (!mounted || !request.current || generation != _loadGeneration) return;
    setState(() {
      for (var i = 0; i < results.length; i++) {
        _sourceErrors[i] = results[i] == null;
        if (results[i] != null) _sources[i] = results[i]!;
      }
      _mergeSources();
      _loading = false;
    });
  }

  bool _startAction() {
    if (!mounted ||
        _busy ||
        apiClient.options.headers['Authorization'] == null) {
      return false;
    }
    setState(() => _busy = true);
    return true;
  }

  void _finishAction(ImWorkflowRequest request) {
    if (mounted && request.current) setState(() => _busy = false);
  }

  String _recordKey(Map<String, dynamic> item) =>
      '${item['recordType']}:${item['id']}';

  bool _isDeletable(Map<String, dynamic> item) =>
      const {'approved', 'rejected', 'withdrawn', 'cancelled', 'expired'}
          .contains(item['status']?.toString()) &&
      item['recordType'] != null &&
      item['id'] != null;

  Future<bool> _hideRecords(List<Map<String, dynamic>> records,
      {bool confirm = true}) async {
    if (!_startAction()) return false;
    final request = ImWorkflowRequest();
    final unique = <String, Map<String, dynamic>>{
      for (final item in records.where(_isDeletable)) _recordKey(item): item,
    };
    final deletable = unique.values.toList();
    var hidden = 0;
    try {
      if (deletable.isEmpty) {
        showAppToast(context, '待处理记录需先处理或撤回');
        return false;
      }
      if (confirm) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(deletable.length == 1 ? '删除这条记录？' : '删除所选记录？'),
            content: const Text('只会从你的列表中移除，不影响对方记录和群聊、部落关系。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除')),
            ],
          ),
        );
        if (accepted != true || !mounted || !request.current) return false;
      }
      // 接口每次最多 100 条；只移除明确成功的记录，跳过项继续保留。
      for (var start = 0; start < deletable.length; start += 100) {
        if (!mounted || !request.current) return false;
        final end = (start + 100).clamp(0, deletable.length);
        final chunk = deletable
            .sublist(start, end)
            .map((item) =>
                <String, dynamic>{'type': item['recordType'], 'id': item['id']})
            .toList();
        final data = await request
            .post('/api/im/application-records/hide', data: {'records': chunk});
        if (!mounted || !request.current) return false;
        final keys = imConfirmedHiddenKeys(chunk, data);
        hidden += keys.length;
        setState(() {
          _hiddenKeys.addAll(keys);
          _mergeSources();
        });
      }
      if (mounted && request.current) {
        showAppToast(
            context,
            hidden == deletable.length
                ? (hidden == 1 ? '已删除' : '已删除所选记录')
                : '已删除$hidden条，${deletable.length - hidden}条未删除，请刷新后重试');
      }
      return hidden == deletable.length;
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(
            context,
            hidden > 0
                ? '已删除$hidden条，其余删除失败，请重试'
                : imFailureMessage(error, '删除失败，请重试'));
      }
      return false;
    } finally {
      _finishAction(request);
    }
  }

  List<Map<String, dynamic>> get _visibleTabItems =>
      _tabController.index == 1 ? _sent : _history;

  Future<void> _deleteSelected() async {
    final records = _visibleTabItems
        .where((item) => _selected.contains(_recordKey(item)))
        .toList();
    await _hideRecords(records);
  }

  Future<void> _clearProcessed() async {
    final records = _visibleTabItems.where(_isDeletable).toList();
    if (records.isEmpty) {
      showAppToast(context, '暂无可删除的已处理记录');
      return;
    }
    await _hideRecords(records);
  }

  Future<void> _approve(Map<String, dynamic> item) =>
      _process(item, approve: true);
  Future<void> _reject(Map<String, dynamic> item) =>
      _process(item, approve: false);

  Future<void> _process(Map<String, dynamic> item,
      {required bool approve}) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !_startAction()) return;
    final request = ImWorkflowRequest();
    final route = switch (item['recordType']) {
      'groupInvite' => '/api/im/group/invite/$id',
      'groupApply' => '/api/im/group/join-apply/$id',
      _ => '/api/im/chat/apply/$id',
    };
    try {
      final data =
          await request.post('$route/${approve ? 'approve' : 'reject'}');
      if (!mounted || !request.current) return;
      _loadGeneration++;
      setState(() {
        for (final slot in [0, 1, 2]) {
          _sources[slot]
              .removeWhere((row) => _recordKey(row) == _recordKey(item));
        }
        _mergeSources();
      });
      await _load();
      if (!mounted || !request.current) return;
      if (approve) {
        final convId = (data['conversationId'] as num?)?.toInt();
        if (convId == null || convId <= 0) {
          showAppToast(context, '申请已处理，请从消息列表进入会话');
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatPage(
                  conversationId: convId,
                  title: data['title']?.toString() ?? '会话',
                  conversationType: data['type'] == 'group' ||
                          item['recordType'] != 'chatApply'
                      ? 'group'
                      : 'single',
                )));
      }
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(context, imFailureMessage(error, '操作失败，请重试'));
        if (imFailureStatus(error) == 404 || imFailureStatus(error) == 403) {
          await _load();
        }
      }
    } finally {
      _finishAction(request);
    }
  }

  Future<void> _withdrawSent(Map<String, dynamic> item) async {
    final id = (item['conversationId'] as num?)?.toInt();
    if (id == null || !_startAction()) return;
    final request = ImWorkflowRequest();
    try {
      await request.post('/api/im/group/$id/apply/withdraw');
      if (!mounted || !request.current) return;
      _loadGeneration++;
      setState(() => item['status'] = 'withdrawn');
      showAppToast(context, '申请已撤回');
      await _load();
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(context, imFailureMessage(error, '撤回失败，请重试'));
      }
    } finally {
      _finishAction(request);
    }
  }

  Future<void> _applyAgain(Map<String, dynamic> item) async {
    final id = (item['conversationId'] as num?)?.toInt();
    if (id == null || !_startAction()) return;
    final request = ImWorkflowRequest();
    var note = item['note']?.toString() ?? '';
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重新提交申请'),
          content: TextFormField(
              initialValue: note,
              onChanged: (value) => note = value,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '填写加入理由（选填）')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('提交')),
          ],
        ),
      );
      if (ok != true || !mounted || !request.current) return;
      note = note.trim();
      await request.post('/api/im/group/$id/apply', data: {'note': note});
      if (!mounted || !request.current) return;
      _loadGeneration++;
      setState(() => item['status'] = 'pending');
      showAppToast(context, '已重新提交');
      await _load();
    } catch (error) {
      if (mounted && request.current) {
        showAppToast(context, imFailureMessage(error, '提交失败，请重试'));
      }
    } finally {
      _finishAction(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _selected.isEmpty ? '申请与邀请' : '已选择 ${_selected.length} 条',
          style: AppTextStyles.titleMedium,
        ),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              tooltip: '取消选择',
              onPressed: () => setState(_selected.clear),
              icon: const Icon(Icons.close_rounded),
            ),
            IconButton(
              tooltip: '删除所选',
              onPressed: _busy ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ] else if (_tabController.index != 0)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'clear' && !_busy) _clearProcessed();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('清空已处理')),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF24272D),
          labelColor: const Color(0xFF24272D),
          unselectedLabelColor: const Color(0xFF8D9299),
          tabs: const [
            Tab(text: '待我处理'),
            Tab(text: '我的申请'),
            Tab(text: '处理记录'),
          ],
        ),
      ),
      body: _loading && _list.isEmpty && _sent.isEmpty && _history.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_list, _buildApplyTile,
                    allowDelete: false,
                    failed: [0, 1, 2].any((i) => _sourceErrors[i])),
                _buildList(_sent, _buildSentTile, failed: _sourceErrors[3]),
                _buildList(_history, _buildHistoryTile,
                    failed: [4, 5, 6].any((i) => _sourceErrors[i])),
              ],
            ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> items,
    Widget Function(Map<String, dynamic>) builder, {
    bool allowDelete = true,
    bool failed = false,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                  height: MediaQuery.sizeOf(context).height * .5,
                  child: Center(
                      child: failed
                          ? ImWorkflowRetry(
                              message: '记录加载失败，请重试',
                              onRetry: _loading ? null : _load)
                          : _buildEmptyState()))
            ],
          ));
    }
    return AbsorbPointer(
        absorbing: _busy,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length + (failed ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
            itemBuilder: (_, index) {
              if (failed && index == 0) {
                return ImWorkflowRetry(
                    message: '部分记录加载失败，请重试', onRetry: _loading ? null : _load);
              }
              final item = items[index - (failed ? 1 : 0)];
              final key = _recordKey(item);
              final deletable = allowDelete && _isDeletable(item);
              final selected = _selected.contains(key);
              final tile = ColoredBox(
                color: selected ? AppColors.primaryLight : Colors.white,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: deletable
                      ? () => setState(() => _selected.add(key))
                      : null,
                  onTap: _selected.isNotEmpty && deletable
                      ? () => setState(() {
                            if (!_selected.add(key)) _selected.remove(key);
                          })
                      : null,
                  child: Stack(
                    children: [
                      builder(item),
                      if (selected)
                        const Positioned(
                          left: 8,
                          top: 8,
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              );
              if (!deletable) return tile;
              return Dismissible(
                key: ValueKey<String>('application-record-$key'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _hideRecords([item]),
                background: Container(
                  color: const Color(0xFFEF4444),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                  ),
                ),
                child: tile,
              );
            },
          ),
        ));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 46,
            color: AppColors.textHint.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无记录',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyTile(Map<String, dynamic> a) {
    final fromUserId = (a['fromUserId'] as num?)?.toInt();
    final nickname = a['fromNickname'] as String? ?? '用户';
    final avatarUrl = a['fromAvatarUrl'] as String?;
    final type = a['type'] as String? ?? 'single';
    final groupName = a['groupName'] as String? ?? '群聊';
    final groupKind = a['groupKind'] as String? ?? a['inviteKind'] as String?;

    final titleText = type == 'groupInvite'
        ? '邀请你加入${groupKind == 'tribe' ? '部落' : '群聊'} 「$groupName」'
        : type == 'group'
            ? '申请加入${groupKind == 'tribe' ? '部落' : '群聊'} 「$groupName」'
            : '请求与你聊天';

    final note = a['note']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (fromUserId != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: fromUserId),
                  ),
                );
              }
            },
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(nickname.isNotEmpty ? nickname[0] : '?',
                      style: const TextStyle(fontSize: 14))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nickname, style: AppTextStyles.titleSmall),
                const SizedBox(height: 2),
                Text(titleText, style: AppTextStyles.bodySmall),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '申请理由：$note',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _reject(a),
                child: const Text(
                  '拒绝',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13),
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _busy ? null : () => _approve(a),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(60, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '同意',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentTile(Map<String, dynamic> item) {
    final name = item['groupName']?.toString() ?? '群聊';
    final isTribe = item['groupKind'] == 'tribe';
    final status = item['status']?.toString() ?? '';
    final note = item['note']?.toString().trim() ?? '';
    final conversationId = (item['conversationId'] as num?)?.toInt();
    final isMember = item['isMember'] == true;
    final statusText = const {
          'pending': '等待处理',
          'approved': '已同意',
          'rejected': '已拒绝',
          'withdrawn': '已撤回',
        }[status] ??
        '已处理';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFF1F2F4),
        child: Icon(
          isTribe ? Icons.shield_outlined : Icons.groups_outlined,
          color: const Color(0xFF24272D),
        ),
      ),
      title: Text('${isTribe ? '部落' : '群聊'} · $name'),
      subtitle: Text(
        note.isEmpty ? statusText : '$statusText\n申请理由：$note',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: note.isNotEmpty,
      trailing: status == 'pending'
          ? TextButton(
              onPressed: () => _withdrawSent(item),
              child: const Text('撤回'),
            )
          : isMember && conversationId != null
              ? TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        conversationId: conversationId,
                        title: name,
                        conversationType: 'group',
                      ),
                    ),
                  ),
                  child: const Text('进入'),
                )
              : TextButton(
                  onPressed:
                      item['isPublic'] == true ? () => _applyAgain(item) : null,
                  child: const Text('再次申请'),
                ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> item) {
    final nickname = item['fromNickname']?.toString() ?? '用户';
    final groupName = item['groupName']?.toString() ?? '群聊';
    final type = item['type']?.toString() ?? 'group';
    final isTribe =
        item['groupKind'] == 'tribe' || item['inviteKind'] == 'tribe';
    final status = const {
          'approved': '已同意',
          'rejected': '已拒绝',
          'withdrawn': '已撤回',
          'cancelled': '已撤销',
        }[item['status']?.toString()] ??
        '已处理';
    final note = item['note']?.toString().trim() ?? '';
    final title = type == 'single'
        ? '$nickname · 私聊申请'
        : type == 'groupInvite'
            ? '$nickname · ${isTribe ? '部落' : '群聊'}邀请'
            : '$nickname · ${isTribe ? '部落' : '群聊'}申请';
    final subtitle = type == 'single'
        ? status
        : note.isEmpty
            ? '$groupName · $status'
            : '$groupName · $status\n申请理由：$note';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFF1F2F4),
        child: Icon(
          type == 'single'
              ? Icons.person_outline_rounded
              : isTribe
                  ? Icons.shield_outlined
                  : Icons.groups_outlined,
          color: const Color(0xFF24272D),
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      isThreeLine: type != 'single' && note.isNotEmpty,
    );
  }
}
