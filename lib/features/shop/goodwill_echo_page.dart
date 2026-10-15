import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_address_page.dart';
import 'shop_common.dart';
import 'shop_orders_page.dart';

class GoodwillEchoPage extends StatefulWidget {
  const GoodwillEchoPage({super.key});

  @override
  State<GoodwillEchoPage> createState() => _GoodwillEchoPageState();
}

class _GoodwillEchoPageState extends State<GoodwillEchoPage> {
  final List<Map<String, dynamic>> _campaigns = [];
  final List<Map<String, dynamic>> _applications = [];
  bool _loading = true;
  String? _loadError;
  final Set<int> _cancellingIds = {};
  final Set<int> _deletingIds = {};
  ApiSessionScope _scope = ApiSessionScope();
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    _scope = ApiSessionScope();
    _loadVersion++;
    setState(() {
      _campaigns.clear();
      _applications.clear();
      _cancellingIds.clear();
      _deletingIds.clear();
      _loadError = null;
      _loading = _scope.authenticated;
    });
    if (_scope.authenticated) _load();
  }

  Future<void> _load() async {
    final scope = _scope;
    final version = ++_loadVersion;
    bool current() => mounted && scope.current && version == _loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final responses = await Future.wait([
        scope.get('/api/shop/goodwill/campaigns'),
        scope.get('/api/shop/goodwill/applications'),
      ]);
      final campaigns = shopData(responses[0])?['list'] as List? ?? [];
      final applications = shopData(responses[1])?['list'] as List? ?? [];
      if (current()) {
        setState(() {
          _campaigns
            ..clear()
            ..addAll(campaigns
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
          _applications
            ..clear()
            ..addAll(applications
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
        });
      }
    } catch (error) {
      if (mounted && current()) {
        final message = shopError(error, '善意回声加载失败');
        setState(() => _loadError = message);
        showAppToast(context, message);
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  String _status(String? value) =>
      const {
        'pending': '等待审核',
        'approved': '审核通过',
        'rejected': '未通过',
        'cancelled': '已取消',
      }[value] ??
      '';

  Color _statusColor(String? value) =>
      const {
        'pending': Color(0xFFC2683B),
        'approved': AppColors.primary,
        'rejected': Color(0xFFB54747),
        'cancelled': AppColors.textHint,
      }[value] ??
      AppColors.textHint;

  Future<void> _cancelApplication(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null ||
        _cancellingIds.contains(id) ||
        _deletingIds.contains(id)) {
      return;
    }
    final scope = _scope;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消这次申请？'),
        content: const Text('取消后不会进入审核；如仍需申请，可以重新提交。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !scope.current) return;
    setState(() => _cancellingIds.add(id));
    try {
      await scope.post('/api/shop/goodwill/applications/$id/cancel');
      if (!mounted || !scope.current) return;
      showAppToast(context, '申请已取消');
      await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '取消失败'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _cancellingIds.remove(id));
    }
  }

  Future<void> _deleteApplication(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null ||
        _deletingIds.contains(id) ||
        _cancellingIds.contains(id)) {
      return;
    }
    final scope = _scope;
    setState(() => _deletingIds.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除这条申请记录？'),
          content: Text(item['status'] == 'pending'
              ? '删除后将从“我的申请”中移除，审核仍会继续。如需终止审核，请先取消申请。'
              : '删除后将从“我的申请”中移除，已生成的赠礼订单不受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !scope.current) return;
      final response =
          await scope.delete('/api/shop/goodwill/applications/$id');
      if (!mounted || !scope.current) return;
      final body = response.data;
      if (body is! Map || body['code'] != 0) {
        showAppToast(
            context,
            body is Map
                ? (body['message']?.toString() ?? '删除失败，请重试')
                : '删除失败，请重试');
        return;
      }
      setState(() => _applications.removeWhere((item) => item['id'] == id));
      showAppToast(context, '申请记录已删除');
      await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '删除失败，请重试'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _deletingIds.remove(id));
    }
  }

  void _showApplicationDetail(Map<String, dynamic> item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApplicationDetailSheet(
        item: item,
        statusText: _status(item['status']?.toString()),
        statusColor: _statusColor(item['status']?.toString()),
        onOrders: item['orderId'] == null
            ? null
            : () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ShopOrdersPage(),
                ));
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(title: const Text('善意回声')),
      body: _loading && _campaigns.isEmpty && _applications.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFE6F8F4), Color(0xFFFFF3E8)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('每一份善意，都有回声!',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF355B55))),
                  ),
                  const SizedBox(height: 22),
                  if (_loadError != null) ...[
                    _LoadErrorCard(message: _loadError!, onRetry: _load),
                    const SizedBox(height: 16),
                  ],
                  const Text('善意赠礼',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (_campaigns.isEmpty)
                    const _EmptyCard(text: '暂无可领取的善意纪念')
                  else
                    ..._campaigns.map((campaign) => _CampaignCard(
                          campaign: campaign,
                          onOpen: () async {
                            final ok = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => GoodwillGiftDetailPage(
                                  campaign: campaign,
                                ),
                              ),
                            );
                            if (ok == true) _load();
                          },
                        )),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(
                        child: Text('我的申请',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700))),
                    TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ShopOrdersPage())),
                        child: const Text('查看赠礼订单')),
                  ]),
                  if (_applications.isEmpty)
                    const _EmptyCard(text: '还没有提交过申请')
                  else
                    ..._applications.map((item) => _ApplicationCard(
                          item: item,
                          statusText: _status(item['status']?.toString()),
                          statusColor: _statusColor(item['status']?.toString()),
                          cancelling: _cancellingIds
                              .contains((item['id'] as num?)?.toInt()),
                          deleting: _deletingIds
                              .contains((item['id'] as num?)?.toInt()),
                          onDelete: () => _deleteApplication(item),
                          onTap: () => _showApplicationDetail(item),
                          onCancel: item['status'] == 'pending'
                              ? () => _cancelApplication(item)
                              : null,
                          onOrders: item['orderId'] == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const ShopOrdersPage(),
                                    ),
                                  ),
                        )),
                  const SizedBox(height: 20),
                  const Text('说明：赠礼是对善意行为的纪念与感谢，不具有宗教、医疗或改变现实结果的功效。',
                      style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                          height: 1.5)),
                ],
              ),
            ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign, required this.onOpen});

  final Map<String, dynamic> campaign;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final reward = campaign['reward'] is Map
        ? Map<String, dynamic>.from(campaign['reward'] as Map)
        : <String, dynamic>{};
    final canApply = campaign['canApply'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Hero(
                    tag: 'goodwill-gift-${campaign['id']}',
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ShopNetworkImage(reward['coverUrl']?.toString()),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F8F4).withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        '善意赠礼 · ¥0',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          canApply
                              ? '查看赠礼详情'
                              : (campaign['unavailableReason']?.toString() ??
                                  '暂不可申请'),
                          style: TextStyle(
                            color: canApply
                                ? AppColors.primary
                                : AppColors.textHint,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textHint,
                          size: 20,
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
}

class GoodwillGiftDetailPage extends StatefulWidget {
  const GoodwillGiftDetailPage({super.key, required this.campaign});

  final Map<String, dynamic> campaign;

  @override
  State<GoodwillGiftDetailPage> createState() => _GoodwillGiftDetailPageState();
}

class _GoodwillGiftDetailPageState extends State<GoodwillGiftDetailPage> {
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _selectedSku;
  bool _loadingProduct = true;
  int _imageIndex = 0;
  int _quantity = 1;

  Map<String, dynamic> get _reward => widget.campaign['reward'] is Map
      ? Map<String, dynamic>.from(widget.campaign['reward'] as Map)
      : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _selectInitialSku();
    _loadProduct();
  }

  List<Map<String, dynamic>> get _skus {
    final values =
        _reward['skus'] as List? ?? _product?['skus'] as List? ?? const [];
    return values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['active'] != false)
        .toList();
  }

  void _selectInitialSku() {
    final skus = _skus;
    final preferredId = (_reward['skuId'] as num?)?.toInt();
    for (final sku in skus) {
      if ((sku['id'] as num?)?.toInt() == preferredId &&
          ((sku['stock'] as num?)?.toInt() ?? 0) > 0) {
        _selectedSku = sku;
        return;
      }
    }
    for (final sku in skus) {
      if (((sku['stock'] as num?)?.toInt() ?? 0) > 0) {
        _selectedSku = sku;
        return;
      }
    }
  }

  Future<void> _loadProduct() async {
    final productId = (_reward['productId'] as num?)?.toInt();
    if (productId == null) {
      setState(() => _loadingProduct = false);
      return;
    }
    try {
      final data =
          shopData(await apiClient.get('/api/shop/products/$productId'));
      if (mounted && data != null) {
        setState(() {
          _product = data;
          if (_selectedSku == null) {
            for (final sku in _skus) {
              if (((sku['stock'] as num?)?.toInt() ?? 0) > 0) {
                _selectedSku = sku;
                break;
              }
            }
          }
        });
      }
    } catch (_) {
      // 活动接口已有完整兜底信息，商品详情加载失败不阻断赠礼申请。
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  List<String> get _images {
    final result = <String>[];
    void add(dynamic value) {
      final url = value?.toString().trim() ?? '';
      if (url.isNotEmpty && !result.contains(url)) result.add(url);
    }

    for (final value in _product?['images'] as List? ?? const []) {
      add(value);
    }
    add(_product?['coverUrl']);
    add(_reward['coverUrl']);
    add(widget.campaign['coverUrl']);
    return result;
  }

  Future<void> _apply() async {
    final selectedSku = _selectedSku;
    if (selectedSku == null) return;
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GoodwillApplyPage(
          campaign: widget.campaign,
          selectedSku: selectedSku,
          quantity: _quantity,
        ),
      ),
    );
    if (submitted == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    final images = _images;
    final canApply = campaign['canApply'] == true;
    final stock = (_reward['stock'] as num?)?.toInt() ?? 0;
    final minProof = (campaign['minProofCount'] as num?)?.toInt() ?? 1;
    final maxProof = (campaign['maxProofCount'] as num?)?.toInt() ?? 3;
    final claimLimit = (campaign['claimLimit'] as num?)?.toInt() ?? 1;
    final paidShipping = campaign['shippingType'] == 'paid';
    final shipping =
        paidShipping ? '仅付运费 ¥${shopMoney(campaign['shippingFee'])}' : '平台包邮';
    final unavailable = campaign['unavailableReason']?.toString().trim() ?? '';
    final selectedStock = (_selectedSku?['stock'] as num?)?.toInt() ?? 0;
    final maxQuantity = (campaign['maxQuantity'] as num?)?.toInt() ?? 1;
    final quantityLimit =
        maxQuantity < selectedStock ? maxQuantity : selectedStock;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(title: const Text('赠礼详情')),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Hero(
                tag: 'goodwill-gift-${campaign['id']}',
                child: AspectRatio(
                  aspectRatio: 1,
                  child: images.isEmpty
                      ? ShopNetworkImage(_reward['coverUrl']?.toString())
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            PageView.builder(
                              itemCount: images.length,
                              onPageChanged: (value) =>
                                  setState(() => _imageIndex = value),
                              itemBuilder: (_, index) =>
                                  ShopNetworkImage(images[index]),
                            ),
                            if (images.length > 1)
                              Positioned(
                                right: 14,
                                bottom: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    '${_imageIndex + 1}/${images.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          if (_loadingProduct) const LinearProgressIndicator(minHeight: 2),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '赠礼 ¥0',
                      style: TextStyle(
                        color: Color(0xFFD76C45),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        shipping,
                        style: const TextStyle(
                          color: Color(0xFFC2683B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  campaign['title']?.toString() ?? '善意赠礼',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _GiftFactChip(
                        icon: Icons.inventory_2_outlined, text: '库存 $stock'),
                    _GiftFactChip(
                      icon: Icons.photo_library_outlined,
                      text: '凭证 $minProof–$maxProof 张',
                    ),
                    _GiftFactChip(
                      icon: Icons.person_outline_rounded,
                      text: claimLimit == 0 ? '不限领取次数' : '每人限领 $claimLimit 次',
                    ),
                  ],
                ),
                if (_skus.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Text('选择规格',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: _skus.map((sku) {
                      final selected = (_selectedSku?['id'] as num?)?.toInt() ==
                          (sku['id'] as num?)?.toInt();
                      final skuStock = (sku['stock'] as num?)?.toInt() ?? 0;
                      final spec = sku['spec'] is Map
                          ? (sku['spec'] as Map)
                              .entries
                              .map((e) => '${e.key}:${e.value}')
                              .join(' · ')
                          : '';
                      return ChoiceChip(
                        selected: selected,
                        onSelected: skuStock <= 0
                            ? null
                            : (_) => setState(() {
                                  _selectedSku = sku;
                                  _quantity = 1;
                                }),
                        label: Text([
                          sku['name']?.toString() ?? '默认规格',
                          if (spec.isNotEmpty) spec,
                          if (skuStock <= 0) '已领完',
                        ].join(' · ')),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text('领取数量',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    _GiftQuantityButton(
                      icon: Icons.remove,
                      enabled: _quantity > 1,
                      onTap: () => setState(() => _quantity--),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text('$_quantity',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    _GiftQuantityButton(
                      icon: Icons.add,
                      enabled: _quantity < quantityLimit,
                      onTap: () => setState(() => _quantity++),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('该规格库存 $selectedStock · 单次最多 $maxQuantity 件',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _GiftDetailSection(
            title: '赠礼说明',
            text: campaign['description']?.toString().trim().isNotEmpty == true
                ? campaign['description'].toString()
                : (_product?['detail']?.toString().trim().isNotEmpty == true
                    ? _product!['detail'].toString()
                    : '这是平台对真实善意行为的一份纪念与感谢。'),
          ),
          const SizedBox(height: 10),
          _GiftDetailSection(
            title: '申请凭证',
            text: campaign['proofHint']?.toString().trim().isNotEmpty == true
                ? campaign['proofHint'].toString()
                : '请上传能够说明善意行为的真实图片，并遮挡无关隐私信息。',
          ),
          const SizedBox(height: 10),
          const _GiftDetailSection(
            title: '领取流程',
            text: '上传证明并选择收货地址 → 平台审核 → 生成赠礼订单 → 支付运费 → 平台发货。赠品本身不收取费用。',
          ),
          const SizedBox(height: 26),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: FilledButton(
          onPressed: canApply && _selectedSku != null && selectedStock > 0
              ? _apply
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(
            canApply
                ? '申请领取'
                : (unavailable.isNotEmpty ? unavailable : '暂不可申请'),
          ),
        ),
      ),
    );
  }
}

class _GiftFactChip extends StatelessWidget {
  const _GiftFactChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F7F5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF4E6964),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _GiftQuantityButton extends StatelessWidget {
  const _GiftQuantityButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF1F7F5) : const Color(0xFFF2F3F3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDE7E4)),
          ),
          child: Icon(icon,
              size: 19,
              color: enabled ? AppColors.primary : AppColors.textHint),
        ),
      );
}

class _GiftDetailSection extends StatelessWidget {
  const _GiftDetailSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.7,
              ),
            ),
          ],
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(color: AppColors.textHint)));
}

class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFB54747)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.item,
    required this.statusText,
    required this.statusColor,
    required this.cancelling,
    required this.deleting,
    required this.onDelete,
    required this.onTap,
    this.onCancel,
    this.onOrders,
  });

  final Map<String, dynamic> item;
  final String statusText;
  final Color statusColor;
  final bool cancelling;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onOrders;

  @override
  Widget build(BuildContext context) {
    final description = item['description']?.toString().trim() ?? '';
    final remark = item['auditRemark']?.toString().trim() ?? '';
    final evidenceCount = (item['evidenceUrls'] as List?)?.length ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['campaignTitle']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if ((item['selectedSkuName']?.toString() ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${item['selectedSkuName']} × ${item['quantity'] ?? 1}',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          remark.isNotEmpty
                              ? remark
                              : (description.isNotEmpty
                                  ? description
                                  : '平台会认真核验你提交的信息'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(statusText, style: TextStyle(color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  if (evidenceCount > 0)
                    Text(
                      '$evidenceCount张凭证',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  if (onOrders != null)
                    TextButton(
                        onPressed: onOrders, child: const Text('查看赠礼订单')),
                  if (onCancel != null)
                    TextButton(
                      onPressed: cancelling || deleting ? null : onCancel,
                      child: Text(cancelling ? '取消中…' : '取消申请'),
                    ),
                  TextButton(
                    onPressed: deleting || cancelling ? null : onDelete,
                    child: Text(deleting ? '删除中…' : '删除记录'),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textHint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationDetailSheet extends StatelessWidget {
  const _ApplicationDetailSheet({
    required this.item,
    required this.statusText,
    required this.statusColor,
    this.onOrders,
  });

  final Map<String, dynamic> item;
  final String statusText;
  final Color statusColor;
  final VoidCallback? onOrders;

  String _time(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '-';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final evidence = (item['evidenceUrls'] as List? ?? [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final description = item['description']?.toString().trim() ?? '';
    final remark = item['auditRemark']?.toString().trim() ?? '';
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAF9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4DDDA),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['campaignTitle']?.toString() ?? '善意回声',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusText, style: TextStyle(color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if ((item['selectedSkuName']?.toString() ?? '').isNotEmpty) ...[
              const Text('赠礼内容', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('${item['selectedSkuName']} × ${item['quantity'] ?? 1}',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
            ],
            const Text('善意记录', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(description.isEmpty ? '未填写文字说明' : description,
                style: const TextStyle(height: 1.6)),
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('提交凭证', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: evidence
                    .map((url) => SizedBox(
                          width: 88,
                          height: 88,
                          child: ShopNetworkImage(url, borderRadius: 10),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            const Text('审核反馈', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              remark.isEmpty
                  ? (item['status'] == 'pending' ? '平台正在核验，请耐心等待' : '暂无审核说明')
                  : remark,
              style: TextStyle(
                color: remark.isEmpty
                    ? AppColors.textHint
                    : AppColors.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            Text('提交时间：${_time(item['createdAt'])}',
                style:
                    const TextStyle(color: AppColors.textHint, fontSize: 12)),
            if (item['auditedAt'] != null)
              Text('处理时间：${_time(item['auditedAt'])}',
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 12)),
            if (onOrders != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onOrders, child: const Text('查看赠礼订单')),
            ],
          ],
        ),
      ),
    );
  }
}

class GoodwillApplyPage extends StatefulWidget {
  const GoodwillApplyPage({
    super.key,
    required this.campaign,
    required this.selectedSku,
    required this.quantity,
  });

  final Map<String, dynamic> campaign;
  final Map<String, dynamic> selectedSku;
  final int quantity;

  @override
  State<GoodwillApplyPage> createState() => _GoodwillApplyPageState();
}

class _GoodwillApplyPageState extends State<GoodwillApplyPage> {
  final _description = TextEditingController();
  final List<XFile> _files = [];
  Map<String, dynamic>? _address;
  bool _submitting = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final max = (widget.campaign['maxProofCount'] as num?)?.toInt() ?? 3;
    final selected =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1600);
    if (selected.isEmpty) return;
    setState(() {
      for (final file in selected) {
        if (_files.length >= max) break;
        _files.add(file);
      }
    });
  }

  Future<void> _chooseAddress() async {
    final address = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
            builder: (_) => const ShopAddressPage(selectMode: true)));
    if (address != null && mounted) setState(() => _address = address);
  }

  Future<String> _upload(XFile file) async {
    return uploadPrivateShopEvidence(file, acceptPending: true);
  }

  Future<void> _submit() async {
    final min = (widget.campaign['minProofCount'] as num?)?.toInt() ?? 1;
    if (_files.length < min) {
      showAppToast(context, '请至少上传$min张凭证');
      return;
    }
    if (_address == null) {
      showAppToast(context, '请选择赠礼收货地址');
      return;
    }
    setState(() => _submitting = true);
    try {
      final urls = <String>[];
      for (final file in _files) {
        urls.add(await _upload(file));
      }
      await apiClient.post('/api/shop/goodwill/applications', data: {
        'campaignId': widget.campaign['id'],
        'selectedSkuId': widget.selectedSku['id'],
        'quantity': widget.quantity,
        'addressId': _address!['id'],
        'description': _description.text.trim(),
        'evidenceUrls': urls,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.volunteer_activism_rounded,
              color: AppColors.primary, size: 42),
          title: const Text('善意已被认真收下'),
          content: const Text('资料已提交审核。审核通过后，赠礼订单会自动出现在商城订单中。'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showAppToast(context, shopError(error, '申请提交失败'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = (widget.campaign['maxProofCount'] as num?)?.toInt() ?? 3;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(title: const Text('提交善意凭证')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.campaign['title']?.toString() ?? '',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F7F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.selectedSku['name'] ?? '默认规格'} × ${widget.quantity}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Text('赠礼 ¥0',
                  style: TextStyle(
                      color: Color(0xFFC2683B), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ..._files.asMap().entries.map((entry) => Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(entry.value.path),
                        width: 96, height: 96, fit: BoxFit.cover)),
                Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                        onTap: () => setState(() => _files.removeAt(entry.key)),
                        child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white)))),
              ])),
          if (_files.length < max)
            InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDE7E4))),
                    child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.primary),
                          SizedBox(height: 6),
                          Text('上传凭证', style: TextStyle(fontSize: 12))
                        ]))),
        ]),
        const SizedBox(height: 14),
        TextField(
            controller: _description,
            maxLength: 500,
            maxLines: 4,
            decoration: InputDecoration(
                labelText: '说说这份善意（选填）',
                hintText: '简单描述时间、行为或相关机构',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none))),
        const SizedBox(height: 10),
        Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
                leading: const Icon(Icons.location_on_outlined,
                    color: AppColors.primary),
                title: Text(_address == null
                    ? '选择赠礼收货地址'
                    : '${_address!['recipient']}  ${_address!['mobile']}'),
                subtitle: _address == null
                    ? null
                    : Text(_address!['fullAddress']?.toString() ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseAddress)),
      ]),
      bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('提交审核'))),
    );
  }
}
