import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'teacher_settlement_amount.dart';

class TeacherIncomePage extends StatefulWidget {
  const TeacherIncomePage({super.key});

  @override
  State<TeacherIncomePage> createState() => _TeacherIncomePageState();
}

class _TeacherIncomePageState extends State<TeacherIncomePage> {
  ApiSessionScope _scope = ApiSessionScope();
  Map<String, dynamic> _settlement = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _withdrawing = false;
  int _loadGeneration = 0;
  String? _error;

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  Future<void> _load() async {
    final scope = _scope;
    final generation = ++_loadGeneration;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请登录后查看收益';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await scope.get('/api/consultation/teacher/income');
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('收益返回异常');
      if (mounted && scope.current && generation == _loadGeneration) {
        setState(() {
          _settlement = data['settlement'] is Map
              ? Map<String, dynamic>.from(data['settlement'])
              : const {};
          _items = data['list'] is List
              ? (data['list'] as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
              : const [];
        });
      }
    } catch (error) {
      if (mounted && scope.current && generation == _loadGeneration) {
        setState(() => _error = apiSessionFailureMessage(error, '收益加载失败'));
        showAppToast(
          context,
          apiSessionFailureMessage(error, '收益加载失败'),
        );
      }
    } finally {
      if (mounted && scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

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
    final next = ApiSessionScope();
    _scope = next;
    _loadGeneration++;
    if (!mounted) return;
    setState(() {
      _settlement = const {};
      _items = const [];
      _withdrawing = false;
      _loading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看收益';
    });
    if (next.authenticated) unawaited(_load());
  }

  Future<void> _withdraw() async {
    if (_withdrawing) return;
    final scope = _scope;
    setState(() => _withdrawing = true);
    final available = double.parse(
      withdrawableAmountText(_settlement['availableAmount']),
    );
    final minimum = _number(_settlement['minimumWithdrawal']);
    final amountController = TextEditingController(
      text: available >= minimum ? available.toStringAsFixed(2) : '',
    );
    final realNameController = TextEditingController();
    final accountController = TextEditingController();
    const method = 'alipay';
    bool agreed = false;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('申请收益提现', style: AppTextStyles.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '可提现 ¥${available.toStringAsFixed(2)} · 最低 ¥${minimum.toStringAsFixed(2)}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '提现金额（元）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: '收款方式',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                  ],
                  onChanged: null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: realNameController,
                  decoration: const InputDecoration(
                    labelText: '实名姓名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: accountController,
                  decoration: const InputDecoration(
                    labelText: '收款账号',
                    helperText: '提交后仅展示脱敏账号，平台审核后打款',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: agreed,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我确认收款信息真实，并同意平台结算与依法纳税规则'),
                  onChanged: (value) =>
                      setSheetState(() => agreed = value == true),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        agreed ? () => Navigator.pop(sheetContext, true) : null,
                    child: const Text('提交申请'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submitted != true) {
      amountController.dispose();
      realNameController.dispose();
      accountController.dispose();
      if (mounted && scope.current) setState(() => _withdrawing = false);
      return;
    }
    if (!mounted || !scope.current) {
      amountController.dispose();
      realNameController.dispose();
      accountController.dispose();
      return;
    }
    try {
      await scope.post('/api/consultation/teacher/withdrawals', data: {
        'amount': amountController.text.trim(),
        'payoutMethod': method,
        'realName': realNameController.text.trim(),
        'payoutAccount': accountController.text.trim(),
        'agreementAccepted': true,
      });
      if (mounted && scope.current) showAppToast(context, '提现申请已提交');
      if (scope.current) await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '提交失败'),
        );
      }
    } finally {
      amountController.dispose();
      realNameController.dispose();
      accountController.dispose();
      if (mounted && scope.current) setState(() => _withdrawing = false);
    }
  }

  String _status(String value) => switch (value) {
        'pending' => '待结算',
        'available' => '可提现',
        'settled' => '已结算',
        'frozen' => '售后冻结',
        _ => value,
      };

  String _time(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '';
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final available = double.parse(withdrawableAmountText(_settlement['availableAmount']));
    final debt = _number(_settlement['debtAmount']) > 0
        ? _number(_settlement['debtAmount'])
        : -_number(_settlement['availableAmount']);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('收益与结算')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _settlement.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      if (_scope.authenticated)
                        TextButton(
                          onPressed: _load,
                          child: const Text('重新加载'),
                        ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF123F44), Color(0xFF1B6C6C)],
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('可提现人民币收益',
                                style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 8),
                            Text(
                              '¥${withdrawableAmountText(_settlement['availableAmount'])}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (debt > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '待抵扣金额 ¥${debt.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                            const SizedBox(height: 15),
                            Row(children: [
                              _amountStat('待结算', _settlement['pendingAmount']),
                              _amountStat(
                                  '提现中', _settlement['withdrawingAmount']),
                              _amountStat(
                                  '累计提现', _settlement['withdrawnAmount']),
                            ]),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: available > 0 &&
                                        available >= _number(_settlement['minimumWithdrawal']) &&
                                        !_withdrawing
                                        ? _withdraw
                                        : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF4D89E),
                                  foregroundColor: const Color(0xFF173E3D),
                                ),
                                child: const Text('申请提现'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '用户支付玄遇币；平台按订单创建时的服务费规则（当前${_number(_settlement['commissionRate'] ?? 20)}%）折算老师人民币收益。当前新订单的售后观察期为${_settlement['settlementHoldDays'] ?? 7}天，期满后收益转为可提现；历史订单按下单规则处理，退款与争议订单会相应调整，已提现退款部分从后续收益抵扣。',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('收益明细', style: AppTextStyles.titleSmall),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(30),
                          child: Center(child: Text('暂无收益记录')),
                        )
                      else
                        ..._items.map((item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item['remark']?.toString() ?? '咨询收益'),
                              subtitle: Text(
                                '${item['customerNickname'] ?? ''} · ${_time(item['createdAt'])}\n${_status(item['status']?.toString() ?? '')}',
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                '${_number(item['amount']) >= 0 ? '+' : ''}¥${_number(item['amount']).toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: _number(item['amount']) >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _amountStat(String label, Object? amount) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¥${_number(amount).toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
      );
}
