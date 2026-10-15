import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

/// 玄遇币原路退款：按充值订单退回支付宝/微信（非提现转账）
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key, this.availableBalance});

  final String? availableBalance;

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  ApiSessionScope _scope = ApiSessionScope();
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  bool _initialLoading = true;
  bool _submitLocked = false;
  int _loadGeneration = 0;
  String? _error;
  String _balance = '0.00';
  String _maxRefund = '0.00';
  final _orders = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _balance = widget.availableBalance ?? '0.00';
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  void _onSessionChanged() {
    final next = ApiSessionScope();
    _scope = next;
    _loadGeneration++;
    if (!mounted) return;
    setState(() {
      _amountCtrl.clear();
      _balance = '0.00';
      _maxRefund = '0.00';
      _orders.clear();
      _loading = false;
      _initialLoading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看退款额度';
    });
    if (next.authenticated) unawaited(_load());
  }

  bool _current(ApiSessionScope scope, int generation) =>
      mounted && scope.current && generation == _loadGeneration;

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = _scope;
    final generation = ++_loadGeneration;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _error = '请登录后查看退款额度';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _initialLoading = true;
        _error = null;
      });
    }
    try {
      final res = await scope.get('/api/auth/wallet/refundable');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data == null) throw const FormatException('退款额度返回异常');
      if (!_current(scope, generation)) return;
      final list = data['orders'] as List?;
      setState(() {
        _balance = (data['balance'] ?? '0').toString();
        _maxRefund = (data['maxRefundAmount'] ?? '0').toString();
        _orders
          ..clear()
          ..addAll(
            (list ?? const []).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          );
      });
    } catch (error) {
      if (_current(scope, generation)) {
        setState(() => _error = apiSessionFailureMessage(error, '加载失败'));
      }
    } finally {
      if (_current(scope, generation)) {
        setState(() => _initialLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_submitLocked) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 0.01) {
      showAppToast(context, '退款金额至少 0.01 玄遇币');
      return;
    }
    final maxV = double.tryParse(_maxRefund) ?? 0;
    if (amount > maxV + 1e-9) {
      showAppToast(context, '超过可退额度 $_maxRefund');
      return;
    }
    final scope = _scope;
    _submitLocked = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认原路退款？'),
        content: Text(
          '将退回 ${amount.toStringAsFixed(2)} 玄遇币到原支付账户（支付宝/微信），'
          '并扣减钱包余额。已消费的币不可退。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认退款')),
        ],
      ),
    );
    if (ok != true || !mounted || !scope.current) {
      _submitLocked = false;
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await scope.post('/api/auth/wallet/coin-refund', data: {
        'amount': amount.toStringAsFixed(2),
        'reason': '用户申请玄遇币原路退款',
      });
      final msg = (res.data as Map?)?['message']?.toString();
      if (!mounted || !scope.current) return;
      showAppToast(
          context, msg == null || msg == 'success' ? '退款已提交，请留意原支付账户到账' : msg);
      _amountCtrl.clear();
      await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '退款失败'));
      }
    } finally {
      _submitLocked = false;
      if (mounted && scope.current) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('退款')),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFFFFF3E8),
                    child: Row(
                      children: [
                        Expanded(child: Text(_error!)),
                        if (_scope.authenticated)
                          TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  '可用 ${_format(_balance)} 币 · 最多可退 ${_format(_maxRefund)} 币',
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 6),
                Text(
                  '未消费的玄遇币按最近充值订单依次原路退回支付宝/微信（1币=1元）。'
                  '不经过「提现转账」，无需单笔转账产品权限。',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint, height: 1.45),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '退款金额（玄遇币）',
                    hintText: '最多 ${_format(_maxRefund)}',
                    border: const OutlineInputBorder(),
                    suffixText: '币',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _amountCtrl.text = _format(_maxRefund)),
                    child: const Text('全部可退'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? '处理中…' : '确认原路退款'),
                ),
                const SizedBox(height: 28),
                Text('可退充值单', style: AppTextStyles.titleSmall),
                const SizedBox(height: 8),
                if (_orders.isEmpty)
                  Text('暂无可以原路退款的充值订单',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint))
                else
                  ..._orders.map((e) {
                    final channel = e['payChannel']?.toString() ?? '';
                    final remain = e['refundableAmount']?.toString() ?? '0';
                    final orderNo = e['orderNo']?.toString() ?? '';
                    final paidAt = e['paidAt']?.toString() ??
                        e['createdAt']?.toString() ??
                        '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('可退 ${_format(remain)} 元 · $channel',
                          style: AppTextStyles.bodyMedium),
                      subtitle: Text('$orderNo\n$paidAt',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textHint)),
                      isThreeLine: true,
                    );
                  }),
              ],
            ),
    );
  }

  String _format(String raw) => (double.tryParse(raw) ?? 0).toStringAsFixed(2);
}
