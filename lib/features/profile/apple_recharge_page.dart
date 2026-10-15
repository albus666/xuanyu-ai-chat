import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/payment/apple_iap_service.dart';
import '../../core/utils/app_toast.dart';

class AppleRechargePage extends StatefulWidget {
  const AppleRechargePage({super.key});
  @override
  State<AppleRechargePage> createState() => _AppleRechargePageState();
}

class _AppleRechargePageState extends State<AppleRechargePage> {
  List<Map<String, dynamic>> _products = [];
  String? _error;
  String? _buying;
  bool _syncing = false;
  bool _loading = true;
  int? _sandboxBalance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = AppleIapService.instance;
      final products = await service.products();
      await service.sync();
      Map<String, dynamic>? diagnostics;
      if (products.isEmpty) diagnostics = await service.productDiagnostics();
      if (mounted) {
        setState(() {
          _products = products;
          if (products.isEmpty) {
            final invalid = diagnostics?['invalidProductIds'];
            final invalidCount = invalid is List ? invalid.length : 0;
            _error =
                '苹果商店暂未返回可购买的商品。\n'
                '诊断：版本 ${diagnostics?['buildNumber'] ?? '-'}，'
                '商店 ${diagnostics?['storefrontCountryCode'] ?? '-'} '
                '(${diagnostics?['storefrontId'] ?? '-'})，'
                '允许支付 ${diagnostics?['canMakePayments'] == true ? '是' : '否'}，'
                'StoreKit2 ${diagnostics?['storeKit2Count'] ?? '-'}，'
                'StoreKit1 ${diagnostics?['legacyCount'] ?? '-'}，'
                '无效商品 $invalidCount/${diagnostics?['requestedCount'] ?? '-'}。';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法加载苹果商品，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认购买玄遇币？'),
        content: Text(
          '将购买 ${product['coins']} 玄遇币，实际价格以 Apple 确认页为准。玄遇币到账后不支持站内退款，请确认后继续。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续购买'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _buying = product['id'] as String);
    try {
      final result = await AppleIapService.instance.purchase(
        product['id'] as String,
      );
      if (!mounted) return;
      if (result['status'] == 'cancelled') {
        showAppToast(context, '已取消购买');
      } else if (result['status'] == 'pending') {
        showAppToast(context, '购买待批准，完成后将自动同步');
      } else if (result['sandbox'] == true) {
        setState(() => _sandboxBalance = result['sandboxBalance'] as int);
        showAppToast(context, '沙盒购买验证成功');
      } else {
        showAppToast(context, '购买成功，${result['coins']}玄遇币已到账');
      }
    } on PlatformException catch (e) {
      if (mounted) showAppToast(context, e.message ?? '购买未完成，请重试');
    } on StateError catch (e) {
      if (mounted) showAppToast(context, e.message.toString());
    } catch (_) {
      if (mounted) showAppToast(context, '购买结果待同步，请稍后重试');
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('购买玄遇币')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('玄遇币可用于虚拟礼物、头像及特效等站内数字服务，不可提现、转赠或交易。购买的玄遇币不会过期，到账后不支持站内退款。'),
        const SizedBox(height: 20),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('重新加载')),
        ],
        for (final product in _products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton(
              onPressed: _buying == null && !_syncing
                  ? () => _buy(product)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _buying == product['id']
                      ? '正在处理…'
                      : '${product['coins']}玄遇币 · ${product['price']}',
                ),
              ),
            ),
          ),
        if (_sandboxBalance != null)
          Text('沙盒测试余额：$_sandboxBalance 测试币。测试交易不扣款，不计入正式可消费余额。'),
        const SizedBox(height: 16),
        const Text('付款前请核对苹果确认页显示的价格。支付渠道规则或法律法规另有规定的，按相应规则处理。'),
        TextButton(
          onPressed: _buying == null && !_syncing
              ? () async {
                  setState(() => _syncing = true);
                  final result = await AppleIapService.instance.sync();
                  if (!context.mounted) return;
                  setState(() => _syncing = false);
                  showAppToast(context, result.message);
                }
              : null,
          child: Text(_syncing ? '正在同步…' : '同步未到账购买'),
        ),
      ],
    ),
  );
}
