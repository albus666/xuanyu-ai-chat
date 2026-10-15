import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_after_sale_page.dart';
import 'shop_common.dart';
import 'shop_presale_notice.dart';
import 'shop_logistics_page.dart';

class ShopOrdersPage extends StatefulWidget {
  const ShopOrdersPage({super.key, this.initialStatus});

  final String? initialStatus;

  @override
  State<ShopOrdersPage> createState() => _ShopOrdersPageState();
}

class _ShopOrdersPageState extends State<ShopOrdersPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _statuses = <String?>[
    null,
    'pending_payment',
    'pending_shipment',
    'shipped',
    'completed',
    'cancelled',
    'refunded',
  ];
  static const _labels = ['全部', '待付款', '待发货', '待收货', '已完成', '已取消', '已退款'];
  late final TabController _tab;
  ApiSessionScope _scope = ApiSessionScope();
  final List<Map<String, dynamic>> _orders = [];
  final Set<int> _operatingIds = {};
  bool _loading = true;
  String? _error;
  int _loadSerial = 0;
  int? _displayedTab;

  @override
  void initState() {
    super.initState();
    var index = _statuses.indexOf(widget.initialStatus);
    if (index < 0) index = 0;
    _tab =
        TabController(length: _labels.length, vsync: this, initialIndex: index)
          ..addListener(() {
            if (!_tab.indexIsChanging) _load();
          });
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_onSessionChanged);
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _onSessionChanged() {
    final next = ApiSessionScope();
    _scope = next;
    _loadSerial++;
    if (!mounted) return;
    setState(() {
      _orders.clear();
      _operatingIds.clear();
      _loading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看商城订单';
    });
    if (next.authenticated) unawaited(_load());
  }

  bool _current(ApiSessionScope scope, int serial) =>
      mounted && scope.current && serial == _loadSerial;

  Future<void> _load() async {
    final scope = _scope;
    final serial = ++_loadSerial;
    final requestedTab = _tab.index;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请登录后查看商城订单';
        });
      }
      return;
    }
    setState(() {
      if (_displayedTab != requestedTab) _orders.clear();
      _loading = true;
      _error = null;
    });
    try {
      final response = await scope.get(
        '/api/shop/orders',
        queryParameters: {
          if (_statuses[requestedTab] != null)
            'status': _statuses[requestedTab],
          'page_size': 50,
        },
      );
      final list = shopData(response)?['list'];
      if (list is! List) throw const FormatException('订单返回异常');
      if (_current(scope, serial)) {
        setState(() {
          _displayedTab = requestedTab;
          _orders
            ..clear()
            ..addAll(
              list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        });
      }
    } catch (error) {
      if (_current(scope, serial)) {
        setState(() => _error = shopError(error, '订单加载失败'));
      }
    } finally {
      if (_current(scope, serial)) setState(() => _loading = false);
    }
  }

  String _statusLabel(String? value) =>
      const {
        'pending_payment': '待付款',
        'pending_shipment': '待发货',
        'shipped': '待收货',
        'in_transit': '运输中',
        'completed': '已完成',
        'cancelled': '已取消',
        'after_sale': '售后中',
        'refunded': '已退款',
        'refund_pending': '超时付款退款中',
      }[value] ??
      value ??
      '';

  Future<void> _operate(Map<String, dynamic> order, String action) async {
    final id = (order['id'] as num?)?.toInt();
    if (id == null || !_operatingIds.add(id)) return;
    final scope = _scope;
    if (mounted) setState(() {});
    try {
      if (action == 'pay') {
        final channel = await chooseShopPaymentChannel(context, scope: scope);
        if (channel != null && mounted && scope.current) {
          final launched = await launchShopPayment(
            context,
            id,
            channel: channel,
            scope: scope,
          );
          if (launched) await waitForShopOrderStatus(id, scope: scope);
        }
      } else {
        await scope.post('/api/shop/orders/$id/$action');
        if (mounted && scope.current) {
          showAppToast(context, action == 'confirm' ? '已确认收货' : '订单已取消');
        }
      }
      if (scope.current) await _load();
    } catch (error) {
      if (mounted && scope.current) showAppToast(context, shopError(error));
    } finally {
      if (mounted && scope.current) {
        setState(() => _operatingIds.remove(id));
      }
    }
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
    final scope = _scope;
    final status = order['status']?.toString();
    final message = status == 'pending_payment'
        ? '将取消这笔待付款订单并从列表删除。真实交易凭证不会被删除。'
        : '删除后不再显示，真实订单、支付和售后凭证仍会保留。';
    if (!await _confirm('删除订单记录', message)) return;
    if (!scope.current) return;
    final id = (order['id'] as num?)?.toInt();
    if (id == null || !_operatingIds.add(id)) return;
    if (mounted) setState(() {});
    try {
      await scope.delete('/api/shop/orders/$id');
      if (!mounted || !scope.current) return;
      setState(() => _orders.remove(order));
      showAppToast(context, '订单记录已删除');
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '删除失败'));
      }
    } finally {
      if (mounted && scope.current) {
        setState(() => _operatingIds.remove(id));
      }
    }
  }

  Future<void> _cleanVisible() async {
    final scope = _scope;
    final removable =
        _orders.where((item) => item['canDelete'] == true).toList();
    if (removable.isEmpty) {
      showAppToast(context, '当前没有可清理的订单');
      return;
    }
    if (!await _confirm('清理可删除订单', '将清理当前列表中${removable.length}笔可删除订单。')) {
      return;
    }
    if (!scope.current) return;
    var removed = 0;
    for (final order in removable) {
      final id = (order['id'] as num?)?.toInt();
      if (id == null) continue;
      try {
        await scope.delete('/api/shop/orders/$id');
        removed++;
      } catch (_) {}
    }
    if (!mounted || !scope.current) return;
    await _load();
    if (mounted) showAppToast(context, '已清理$removed笔订单');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text('商城订单'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _cleanVisible(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clean', child: Text('清理可删除订单')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: _labels.map((x) => Tab(text: x)).toList(),
        ),
      ),
      body: _loading && (_orders.isEmpty || _displayedTab != _tab.index)
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null && _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      if (_scope.authenticated)
                        TextButton(onPressed: _load, child: const Text('重新加载')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _orders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('暂无相关订单')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _orders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final order = _orders[index];
                            final items = order['items'] as List? ?? [];
                            final first = items.isNotEmpty && items.first is Map
                                ? Map<String, dynamic>.from(items.first as Map)
                                : <String, dynamic>{};
                            final status = order['status']?.toString();
                            final operating = _operatingIds.contains(
                              (order['id'] as num?)?.toInt(),
                            );
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      if (order['source'] == 'goodwill')
                                        Container(
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF1E7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            '善意赠礼',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFC2683B),
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          order['orderNo']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _statusLabel(status),
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 22),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: ShopNetworkImage(
                                          first['coverUrl']?.toString(),
                                          borderRadius: 10,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              first['productName']
                                                      ?.toString() ??
                                                  '商品',
                                              maxLines: 2,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              first['skuName']?.toString() ??
                                                  '',
                                              style: const TextStyle(
                                                color: AppColors.textHint,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (items.length > 1)
                                              Text(
                                                '等${items.length}件商品',
                                                style: const TextStyle(
                                                  color: AppColors.textHint,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            if ((order['expressNo']
                                                        ?.toString() ??
                                                    '')
                                                .isNotEmpty)
                                              Text(
                                                '${order['expressCompany'] ?? ''} ${order['expressNo']}',
                                                style: const TextStyle(
                                                  color: AppColors.textHint,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '¥${shopMoney(order['payAmount'])}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (order['presale'] is Map)
                                    ShopPresaleNotice(
                                      data: order['presale'] as Map,
                                      order: true,
                                    ),
                                  if (status == 'refund_pending')
                                    const Padding(
                                      padding: EdgeInsets.only(top: 10),
                                      child:
                                          Text('订单关闭后收到付款，正在原路退款。到账以支付渠道确认为准。'),
                                    ),
                                  if (status == 'pending_payment' ||
                                      status == 'pending_shipment' ||
                                      status == 'shipped' ||
                                      status == 'in_transit' ||
                                      status == 'completed' ||
                                      order['canDelete'] == true ||
                                      (order['expressNo']?.toString() ?? '')
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          if (status == 'pending_payment')
                                            OutlinedButton(
                                              onPressed: operating
                                                  ? null
                                                  : () =>
                                                      _operate(order, 'cancel'),
                                              child: const Text('取消订单'),
                                            ),
                                          if (status == 'pending_payment')
                                            FilledButton(
                                              onPressed: operating
                                                  ? null
                                                  : () =>
                                                      _operate(order, 'pay'),
                                              child: const Text('立即付款'),
                                            ),
                                          if ((order['expressNo']?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            OutlinedButton(
                                              onPressed: () =>
                                                  Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ShopLogisticsPage(
                                                    order: order,
                                                  ),
                                                ),
                                              ),
                                              child: const Text('查看物流'),
                                            ),
                                          if (status == 'shipped' ||
                                              status == 'in_transit')
                                            FilledButton(
                                              onPressed: operating
                                                  ? null
                                                  : () => _operate(
                                                      order, 'confirm'),
                                              child: const Text('确认收货'),
                                            ),
                                          if (status == 'pending_shipment' ||
                                              status == 'shipped' ||
                                              status == 'in_transit' ||
                                              status == 'completed')
                                            OutlinedButton(
                                              onPressed: () =>
                                                  Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ShopAfterSalePage(
                                                    order: order,
                                                  ),
                                                ),
                                              ),
                                              child: const Text('退款/售后'),
                                            ),
                                          if (order['canDelete'] == true)
                                            TextButton.icon(
                                              onPressed: operating
                                                  ? null
                                                  : () => _delete(order),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                status == 'pending_payment'
                                                    ? '取消并删除'
                                                    : '删除记录',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
