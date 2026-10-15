import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  static const _filters = <String, String>{
    '': '全部',
    'pending': '待处理',
    'processing': '处理中',
    'completed': '已完成',
    'cancelled': '已关闭',
  };

  final _list = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _filter = '';
  int _page = 1;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (apiClient.options.headers['Authorization'] != null) {
      _load(reset: true);
    } else {
      setState(() {
        _loadSerial++;
        _list.clear();
        _loading = _loadingMore = false;
        _error = '请登录后查看订单';
      });
    }
  }

  bool _isCurrent(int serial, int session) =>
      mounted && serial == _loadSerial && session == apiSessionChanges.value;

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    final serial = ++_loadSerial;
    final session = apiSessionChanges.value;
    if (reset) {
      setState(() {
        _list.clear();
        _loading = true;
        _loadingMore = false;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }
    final page = _page;
    final filter = _filter;
    try {
      final res = await apiClient.get(
        '/api/auth/orders',
        queryParameters: {
          'page': page,
          'page_size': 20,
          if (filter.isNotEmpty) 'status_group': filter,
        },
      );
      final data = (res.data as Map?)?['data'] as Map?;
      if (data?['list'] is! List) throw const FormatException('订单响应无效');
      final items = (data?['list'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!_isCurrent(serial, session)) return;
      setState(() {
        if (reset) _list.clear();
        final ids = _list.map((item) => item['id']).toSet();
        _list.addAll(items.where((item) => ids.add(item['id'])));
        _page = page + 1;
        _hasMore = data?['hasMore'] == true;
      });
    } catch (error) {
      if (!_isCurrent(serial, session)) return;
      final body = error is DioException ? error.response?.data : null;
      final message = body is Map ? body['message']?.toString() : null;
      setState(() => _error = message?.isNotEmpty == true ? message : '订单加载失败');
    } finally {
      if (_isCurrent(serial, session)) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String _typeLabel(String? type) => switch (type) {
        'recharge' => '玄遇币充值',
        'shop_order' => '商城订单',
        'master_deposit' => '预约定金',
        'consume' => '消费记录',
        'withdraw' => '提现记录',
        _ => '订单记录',
      };

  String _statusLabel(String? value) => switch (value?.toLowerCase()) {
        'pending' || 'created' || 'unpaid' => '待支付',
        'paid' => '已支付',
        'processing' || 'shipping' => '处理中',
        'approved' || 'completed' || 'success' => '已完成',
        'cancelled' || 'canceled' || 'closed' => '已取消',
        'rejected' => '已拒绝',
        'refunded' => '已退款',
        'failed' => '支付失败',
        'expired' => '已过期',
        _ => '处理中',
      };

  String _number(dynamic value, {int decimals = 2}) {
    final number = num.tryParse(value?.toString() ?? '') ?? 0;
    var text = number.toStringAsFixed(decimals);
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return text.isEmpty ? '0' : text;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete(Map<String, dynamic> order) async {
    if (!await _confirm('删除记录', '删除后不会再显示，但不会影响真实付款、退款和账务凭证。')) return;
    final id = (order['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await apiClient.delete('/api/auth/orders/$id');
      if (!mounted) return;
      setState(() => _list.remove(order));
      showAppToast(context, '记录已删除');
    } on DioException catch (error) {
      if (mounted) {
        showAppToast(
          context,
          (error.response?.data as Map?)?['message']?.toString() ?? '删除失败',
        );
      }
    }
  }

  Future<void> _cleanVisible() async {
    final removable = _list.where((item) => item['canDelete'] == true).toList();
    if (removable.isEmpty) {
      showAppToast(context, '当前没有可清理的记录');
      return;
    }
    if (!await _confirm(
      '清理可删除记录',
      '将清理当前列表中已关闭、已完成或无效的记录，共${removable.length}条。',
    )) {
      return;
    }
    var removed = 0;
    for (final item in removable) {
      final id = (item['id'] as num?)?.toInt();
      if (id == null) continue;
      try {
        await apiClient.delete('/api/auth/orders/$id');
        removed++;
      } on DioException catch (_) {}
    }
    if (!mounted) return;
    await _load(reset: true);
    if (mounted) showAppToast(context, '已清理$removed条记录');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('我的订单'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (_) => _cleanVisible(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clean', child: Text('清理可删除记录')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final entry = _filters.entries.elementAt(index);
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) {
                      setState(() => _filter = entry.key);
                      _load(reset: true);
                    },
                  );
                },
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  Widget _body() {
    if (_loading && _list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textHint)),
            TextButton(
              onPressed: () => _load(reset: true),
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: _list.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Center(child: Text('暂无相关记录')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              itemCount: _list.length + (_hasMore ? 1 : 0),
              itemBuilder: (_, index) =>
                  index == _list.length ? _loadMore() : _card(_list[index]),
            ),
    );
  }

  Widget _loadMore() => Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: _loadingMore
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error != null) Text(_error!),
                  TextButton(
                      onPressed: _load,
                      child: Text(_error == null ? '加载更多' : '重试加载更多')),
                ]),
        ),
      );

  Widget _card(Map<String, dynamic> order) {
    final type = order['type']?.toString();
    final orderNo = order['orderNo']?.toString() ?? '';
    final subject = order['subject']?.toString() ?? '';
    final amount = type == 'recharge'
        ? '${_number(order['creditedCoins'] ?? order['amount'], decimals: 4)}币'
        : '¥${_number(order['amount'])}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_typeLabel(type)} · $amount',
                    style: AppTextStyles.titleSmall,
                  ),
                ),
                Text(
                  _statusLabel(order['status']?.toString()),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                if (order['canDelete'] == true)
                  IconButton(
                    tooltip: '删除记录',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _delete(order),
                  ),
              ],
            ),
            if (subject.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    orderNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制订单号',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: orderNo));
                    showAppToast(context, '订单号已复制');
                  },
                ),
                Text(
                  _date(order['createdAt']),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
