import 'package:flutter/material.dart';

import '../../core/cache/page_snapshot_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_share_more_button.dart';
import 'shop_checkout_page.dart';
import 'shop_common.dart';
import 'shop_presale_notice.dart';

class ShopProductDetailPage extends StatefulWidget {
  const ShopProductDetailPage({super.key, required this.productId});

  final int productId;

  @override
  State<ShopProductDetailPage> createState() => _ShopProductDetailPageState();
}

class _ShopProductDetailPageState extends State<ShopProductDetailPage> {
  final _session = ApiSessionScope();
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _sku;
  bool _loading = true;
  bool _fresh = false;
  bool _acting = false;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final cache = PageSnapshotCache(
      'shop_product_detail',
      parameters: {'id': widget.productId},
      persist: true,
    );
    if (!_session.current) return;
    setState(() {
      _loading = true;
      _fresh = false;
    });
    if (_product == null) {
      final snapshot = await cache.read();
      if (!mounted || !_session.current) return;
      if (snapshot != null) {
        setState(() {
          _product = snapshot;
          final skus = snapshot['skus'] as List? ?? [];
          if (skus.isNotEmpty && skus.first is Map) {
            _sku = Map<String, dynamic>.from(skus.first as Map);
          }
        });
      }
    }
    try {
      final data = shopData(
        await _session.get('/api/shop/products/${widget.productId}'),
      );
      if (data != null && mounted && _session.current) {
        final skus = data['skus'] as List? ?? [];
        setState(() {
          _product = data;
          _fresh = true;
          _loading = false;
          _sku = null;
          if (skus.isNotEmpty && skus.first is Map) {
            _sku = Map<String, dynamic>.from(skus.first as Map);
          }
          final stock = (_sku?['stock'] as num?)?.toInt() ?? 0;
          _quantity = stock > 0 ? _quantity.clamp(1, stock) : 1;
        });
        await cache.write(data);
      }
    } catch (error) {
      if (mounted && _session.current) {
        showAppToast(context, shopError(error, '商品加载失败'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseSku() async {
    final skus = _product?['skus'] as List? ?? [];
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择规格',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: skus.whereType<Map>().map((raw) {
                      final item = Map<String, dynamic>.from(raw);
                      final disabled = (item['stock'] as num?)?.toInt() == 0;
                      final selected = item['id'] == _sku?['id'];
                      return ChoiceChip(
                        label: Text(_skuLabel(item)),
                        selected: selected,
                        selectedColor: AppColors.primary.withValues(alpha: .16),
                        backgroundColor: const Color(0xFFF7FAF9),
                        disabledColor: const Color(0xFFECEFF0),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : const Color(0xFFE1EAE7),
                          width: selected ? 1.4 : 1,
                        ),
                        labelStyle: TextStyle(
                          color: disabled
                              ? AppColors.textHint
                              : selected
                                  ? AppColors.primaryDark
                                  : AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        checkmarkColor: AppColors.primaryDark,
                        onSelected:
                            disabled ? null : (_) => Navigator.pop(ctx, item),
                      );
                    }).toList()),
              ]),
        ),
      ),
    );
    if (result != null && mounted && _session.current) {
      setState(() {
        _sku = result;
        _quantity = 1;
      });
    }
  }

  Future<void> _addCart() async {
    if (_sku == null || _acting || !_fresh || !_session.current) return;
    setState(() => _acting = true);
    try {
      final response = await _session.post('/api/shop/cart',
          data: {'skuId': _sku!['id'], 'quantity': _quantity});
      final body = response.data;
      if (body is! Map || body['code'] != 0) {
        throw StateError(
            body is Map ? body['message']?.toString() ?? '加入购物车失败' : '加入购物车失败');
      }
      if (mounted && _session.current) showAppToast(context, '已加入购物车');
    } catch (error) {
      if (mounted && _session.current) {
        showAppToast(
            context,
            error is StateError
                ? error.message.toString()
                : shopError(error, '加入购物车失败'));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _buyNow() {
    if (_sku == null || !_fresh || !_session.current) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShopCheckoutPage(items: [
        {'skuId': _sku!['id'], 'quantity': _quantity}
      ]),
    ));
  }

  String _skuLabel(Map<String, dynamic> sku) {
    final name = sku['name']?.toString().trim() ?? '';
    final spec = sku['spec'];
    final values = spec is Map
        ? spec.entries
            .map((entry) => '${entry.key}：${entry.value}')
            .where((value) => value.trim().isNotEmpty)
            .join(' · ')
        : '';
    final label = values.isEmpty ? name : '$name · $values';
    return '$label  ¥${shopMoney(sku['price'])}';
  }

  Widget _selectedSpecChips(Map<String, dynamic>? sku) {
    final spec = sku?['spec'];
    if (spec is! Map || spec.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: spec.entries.map((entry) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFE9F7F3),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: .28)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text('${entry.key}：${entry.value}',
                  style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('商品详情')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }
    if (_loading && _product == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final product = _product;
    if (product == null) {
      return const Scaffold(body: Center(child: Text('商品不存在或已下架')));
    }
    final images =
        (product['images'] as List? ?? []).map((x) => x.toString()).toList();
    final stock = (_sku?['stock'] as num?)?.toInt() ?? 0;
    final presale =
        product['presale'] is Map ? product['presale'] as Map : null;
    final available = presale == null || presale['state'] == 'open';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text('商品详情'),
        actions: [
          if (!_fresh && !_loading)
            IconButton(
                onPressed: _load,
                tooltip: '更新商品状态',
                icon: const Icon(Icons.refresh)),
          AppShareMoreButton(
            title: product['name']?.toString() ?? '玄遇商品',
            shareText:
                '我在玄遇发现了「${product['name']?.toString() ?? '这件商品'}」，来看看详情。',
          ),
        ],
      ),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF4FBF9), Color(0xFFFFF8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: images.length <= 1
                ? ShopNetworkImage(
                    images.isEmpty
                        ? product['coverUrl']?.toString()
                        : images.first,
                    fit: BoxFit.contain,
                  )
                : PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (_, i) => ShopNetworkImage(
                          images[i],
                          fit: BoxFit.contain,
                        )),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          color: Colors.white,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('¥${shopMoney(_sku?['price'] ?? product['price'])}',
                style: const TextStyle(
                    fontSize: 26,
                    color: Color(0xFFD76C45),
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(product['name']?.toString() ?? '',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            if ((product['subtitle']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(product['subtitle'].toString(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, height: 1.4)),
            ],
            _selectedSpecChips(_sku),
          ]),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          child: ListTile(
            title: const Text('选择规格'),
            subtitle: Text(
                '${_sku?['name'] ?? '暂无规格'} · 库存$stock${_sku?['spec'] is Map && (_sku!['spec'] as Map).isNotEmpty ? ' · 已选规格' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _chooseSku,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (presale != null) ShopPresaleNotice(data: presale),
            const Text('商品详情',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
                product['detail']?.toString().isNotEmpty == true
                    ? product['detail'].toString()
                    : '暂无更多商品介绍。',
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.7)),
            if ((product['serviceNote']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('服务说明：${product['serviceNote']}',
                  style:
                      const TextStyle(color: AppColors.textHint, height: 1.5)),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              IconButton(
                  onPressed:
                      _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove)),
              Text('$_quantity',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                  onPressed: _quantity < stock
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add)),
            ]),
          ),
          if (presale == null) ...[
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton(
                    onPressed:
                        _acting || !_fresh || stock == 0 ? null : _addCart,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('加入购物车'))),
          ],
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton(
                  onPressed:
                      !_fresh || stock == 0 || !available || !_session.current
                          ? null
                          : _buyNow,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: Text(!available
                      ? (presale['state'] == 'scheduled' ? '尚未开始' : '预售已截止')
                      : stock == 0
                          ? '已售罄'
                          : presale != null
                              ? '全款预订'
                              : '立即购买'))),
        ]),
      ),
    );
  }
}
