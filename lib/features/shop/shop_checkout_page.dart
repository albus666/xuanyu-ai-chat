import 'dart:math';
import 'package:flutter/material.dart';
import 'shop_presale_notice.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_address_page.dart';
import 'shop_common.dart';
import 'shop_orders_page.dart';

class ShopCheckoutPage extends StatefulWidget {
  const ShopCheckoutPage({super.key, this.cartItemIds, this.items});

  final List<int>? cartItemIds;
  final List<Map<String, dynamic>>? items;

  @override
  State<ShopCheckoutPage> createState() => _ShopCheckoutPageState();
}

class _ShopCheckoutPageState extends State<ShopCheckoutPage> {
  ApiSessionScope _scope = ApiSessionScope();
  Map<String, dynamic>? _address;
  Map<String, dynamic>? _preview;
  final _remark = TextEditingController();
  bool _presaleAccepted = false;
  final String _requestId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  bool _loading = true;
  bool _submitting = false;
  bool _submitLocked = false;
  bool _sessionInvalid = false;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _remark.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    _scope = ApiSessionScope();
    _loadSerial++;
    if (!mounted) return;
    setState(() {
      _address = null;
      _preview = null;
      _loading = false;
      _submitting = false;
      _sessionInvalid = true;
    });
  }

  bool _current(ApiSessionScope scope, int serial) =>
      mounted && scope.current && serial == _loadSerial && !_sessionInvalid;

  Map<String, dynamic> get _orderPayload => {
        'cartItemIds': widget.cartItemIds,
        'items': widget.items,
      };

  Future<void> _load() async {
    final scope = _scope;
    final serial = ++_loadSerial;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _sessionInvalid = true;
        });
      }
      return;
    }
    await Future.wait([
      _loadDefaultAddress(scope, serial),
      _loadPreview(scope, serial),
    ]);
    if (_current(scope, serial)) setState(() => _loading = false);
  }

  Future<void> _loadDefaultAddress(
    ApiSessionScope scope,
    int serial,
  ) async {
    try {
      final data = shopData(await scope.get('/api/shop/addresses'));
      final list = data?['list'] as List? ?? [];
      if (list.isNotEmpty && list.first is Map && _current(scope, serial)) {
        setState(() => _address = Map<String, dynamic>.from(list.first as Map));
      }
    } catch (_) {}
  }

  Future<void> _loadPreview(ApiSessionScope scope, int serial) async {
    try {
      final data = shopData(
          await scope.post('/api/shop/orders/preview', data: _orderPayload));
      if (data == null) throw StateError('预览失败');
      if (_current(scope, serial)) setState(() => _preview = data);
    } catch (error) {
      if (mounted && _current(scope, serial)) {
        showAppToast(context, shopError(error, '订单信息加载失败'));
      }
    }
  }

  Future<void> _chooseAddress() async {
    final scope = _scope;
    if (_sessionInvalid) return;
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
          builder: (_) => const ShopAddressPage(selectMode: true)),
    );
    if (selected != null && mounted && scope.current && !_sessionInvalid) {
      setState(() => _address = selected);
    }
  }

  Future<void> _submit() async {
    if (_submitLocked || _sessionInvalid) return;
    _submitLocked = true;
    final scope = _scope;
    try {
      if (_address == null) {
        showAppToast(context, '请先选择收货地址');
        return;
      }
      if (_preview == null) {
        showAppToast(context, '订单信息尚未加载完成');
        return;
      }
      if (_preview?['presale'] is Map && !_presaleAccepted) {
        showAppToast(context, '请先确认全款预售与最晚发货时间');
        return;
      }
      final freeOrder = shopPrice(_preview?['payAmount']) == 0;
      final channel = freeOrder
          ? 'free'
          : await chooseShopPaymentChannel(context, scope: scope);
      if (channel == null || !mounted || !scope.current || _sessionInvalid) {
        return;
      }
      setState(() => _submitting = true);
      final response = await scope.post('/api/shop/orders', data: {
        'addressId': _address!['id'],
        ..._orderPayload,
        'remark': _remark.text.trim(),
        'requestId': _requestId,
        'quoteToken': _preview?['quoteToken'],
        'presaleAccepted': _presaleAccepted,
      });
      final order = shopData(response);
      final id = (order?['id'] as num?)?.toInt();
      if (id == null) throw StateError('订单创建失败');
      if (!mounted || !scope.current || _sessionInvalid) return;
      final launched = !freeOrder &&
          await launchShopPayment(
            context,
            id,
            channel: channel,
            scope: scope,
          );
      if (launched) await waitForShopOrderStatus(id, scope: scope);
      if (!mounted || !scope.current || _sessionInvalid) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ShopOrdersPage()),
        (route) => route.isFirst,
      );
    } catch (error) {
      if (mounted && scope.current && !_sessionInvalid) {
        showAppToast(context, shopError(error, '提交订单失败'));
      }
    } finally {
      _submitLocked = false;
      if (mounted && scope.current && !_sessionInvalid) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(title: const Text('确认订单')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_sessionInvalid) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '账号已切换，请返回商城重新结算',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8A5A2B)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              contentPadding: const EdgeInsets.all(15),
              leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE7F8F5),
                  child: Icon(Icons.location_on_outlined,
                      color: AppColors.primary)),
              title: Text(
                  _address == null
                      ? '请选择收货地址'
                      : '${_address!['recipient']}  ${_address!['mobile']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: _address == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(_address!['fullAddress']?.toString() ?? '')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _sessionInvalid ? null : _chooseAddress,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_preview != null)
            _OrderPreviewCard(preview: _preview!),
          if (!_loading && _preview == null)
            TextButton(
                onPressed: _sessionInvalid ? null : _load,
                child: const Text('重新加载订单信息')),
          if (_preview?['presale'] is Map) ...[
            ShopPresaleNotice(data: _preview!['presale'] as Map),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _presaleAccepted,
              onChanged: _submitting || _sessionInvalid
                  ? null
                  : (value) => setState(() => _presaleAccepted = value == true),
              title: const Text('我已确认这是全款预售，并知悉上述最晚发货时间'),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: TextField(
              controller: _remark,
              maxLength: 100,
              decoration: const InputDecoration(
                  labelText: '订单备注（选填）',
                  hintText: '颜色、配送等备注请写在这里',
                  border: InputBorder.none,
                  counterText: ''),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF8EE),
                borderRadius: BorderRadius.circular(16)),
            child: const Text('请在30分钟内付款；预售订单不晚于预售截止时间。超时关闭后收到付款，将原路退款，不再占用名额。',
                style: TextStyle(color: Color(0xFF8A6A3E), height: 1.5)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _sessionInvalid ||
                  _submitting ||
                  _loading ||
                  _preview == null ||
                  (_preview?['presale'] is Map && !_presaleAccepted)
              ? null
              : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('提交订单'),
        ),
      ),
    );
  }
}

class _OrderPreviewCard extends StatelessWidget {
  const _OrderPreviewCard({required this.preview});

  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final items = (preview['items'] as List? ?? const []).whereType<Map>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        ...items.map((raw) {
          final item = Map<String, dynamic>.from(raw);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 58,
                  height: 58,
                  child: ShopNetworkImage(item['coverUrl']?.toString(),
                      borderRadius: 9)),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item['productName']?.toString() ?? '商品',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(item['skuName']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ])),
              Text('¥${shopMoney(item['price'])} × ${item['quantity'] ?? 1}'),
            ]),
          );
        }),
        const Divider(height: 12),
        _amountRow('商品金额', preview['goodsAmount']),
        const SizedBox(height: 7),
        _amountRow('运费', preview['freightAmount']),
        const SizedBox(height: 10),
        _amountRow('应付合计', preview['payAmount'], emphasized: true),
      ]),
    );
  }

  Widget _amountRow(String label, dynamic amount, {bool emphasized = false}) =>
      Row(children: [
        Text(label,
            style: TextStyle(
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.normal)),
        const Spacer(),
        Text('¥${shopMoney(amount)}',
            style: TextStyle(
                color: emphasized ? const Color(0xFFD76C45) : null,
                fontSize: emphasized ? 18 : 14,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.normal)),
      ]);
}
