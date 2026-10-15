import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/payment/apple_iap_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'legal_document_page.dart';
import 'recharge_page.dart';

class BalancePage extends StatefulWidget {
  const BalancePage({super.key});

  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage> {
  ApiSessionScope _scope = ApiSessionScope();
  String _balance = '0.00';
  String _frozen = '0.00';
  final _logs = <Map<String, dynamic>>[];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    AppleIapService.instance.changes.addListener(_refreshBalance);
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    AppleIapService.instance.changes.removeListener(_refreshBalance);
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final next = ApiSessionScope();
    _scope = next;
    _loadGeneration++;
    if (!mounted) return;
    setState(() {
      _balance = '0.00';
      _frozen = '0.00';
      _logs.clear();
      _page = 1;
      _hasMore = true;
      _loadingMore = false;
      _loading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看钱包';
    });
    if (next.authenticated) unawaited(_load());
  }

  bool _current(ApiSessionScope scope, int generation) =>
      mounted && scope.current && generation == _loadGeneration;

  Future<void> _refreshBalance() async {
    final scope = _scope;
    final generation = _loadGeneration;
    try {
      final response = await scope.get('/api/auth/wallet/balance');
      final data = (response.data as Map?)?['data'] as Map?;
      if (!_current(scope, generation) || data == null) return;
      setState(() {
        _balance = (data['balance'] ?? '0').toString();
        _frozen = (data['frozenAmount'] ?? '0').toString();
      });
    } on DioException catch (_) {}
  }

  Future<void> _load() async {
    final scope = _scope;
    final generation = ++_loadGeneration;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请登录后查看钱包';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _logs.clear();
      _page = 1;
      _hasMore = true;
      _loadingMore = false;
    });
    try {
      final res = await scope.get('/api/auth/wallet/balance');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data == null) throw const FormatException('钱包返回异常');
      if (_current(scope, generation)) {
        setState(() {
          _balance = (data['balance'] ?? '0').toString();
          _frozen = (data['frozenAmount'] ?? '0').toString();
        });
      }
      await _loadLogs(scope: scope, generation: generation);
    } catch (error) {
      if (_current(scope, generation)) {
        setState(() => _error = apiSessionFailureMessage(error, '加载失败'));
      }
    } finally {
      if (_current(scope, generation)) setState(() => _loading = false);
    }
  }

  Future<void> _loadLogs({ApiSessionScope? scope, int? generation}) async {
    if (_loadingMore || !_hasMore) return;
    final requestScope = scope ?? _scope;
    final requestGeneration = generation ?? _loadGeneration;
    setState(() => _loadingMore = true);
    try {
      final res = await requestScope.get(
        '/api/auth/wallet/log',
        queryParameters: {'page': _page, 'page_size': 20},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>?;
      if (list == null) throw const FormatException('钱包流水返回异常');
      if (_current(requestScope, requestGeneration)) {
        setState(() {
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              _logs.add(Map<String, dynamic>.from(e));
            }
          }
          _page++;
          _hasMore = data?['hasMore'] == true;
        });
      }
    } catch (error) {
      if (_current(requestScope, requestGeneration)) {
        setState(() => _error = apiSessionFailureMessage(error, '流水加载失败'));
      }
    }
    if (_current(requestScope, requestGeneration)) {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('玄遇币'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const LegalDocumentPage(type: LegalDocumentType.coinRules),
              ),
            ),
            child: const Text('规则'),
          ),
        ],
      ),
      body: _loading && _logs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _logs.isEmpty
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '可用玄遇币',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${double.tryParse(_balance)?.toStringAsFixed(2) ?? _balance} 币',
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            if (double.tryParse(_frozen) != null &&
                                double.parse(_frozen) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '服务预冻结 ${double.tryParse(_frozen)?.toStringAsFixed(2) ?? _frozen} 币',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (_) => const RechargePage(),
                                      ),
                                    )
                                    .then((_) => _load()),
                                child: const Text('充值'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              usesAppleIap
                                  ? '苹果内购价格以购买确认页为准。玄遇币到账后不支持站内退款；支付渠道或法律另有规定的除外。'
                                  : '1元=1玄遇币。购买到账后不支持退款，请在付款前核对金额。异常重复扣款或未到账可联系客服核查。',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textHint,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('玄遇币明细', style: AppTextStyles.titleSmall),
                      const SizedBox(height: 8),
                      if (_logs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              '暂无流水',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._logs.map((e) {
                          final type = e['type'] as String? ?? '';
                          final amount = e['amount'] as String? ?? '0';
                          final remark = e['remark'] as String? ?? '';
                          final createdAt = e['createdAt'] as String? ?? '';
                          final amountValue = double.tryParse(amount) ?? 0;
                          final isIn = amountValue >= 0 || type == 'recharge';
                          final amountText =
                              amountValue.abs().toStringAsFixed(2);
                          return ListTile(
                            title: Text(
                              remark.isNotEmpty ? remark : type,
                              style: AppTextStyles.bodyMedium,
                            ),
                            subtitle: Text(
                              createdAt,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textHint,
                              ),
                            ),
                            trailing: Text(
                              '${isIn ? '+' : '-'}$amountText币',
                              style: AppTextStyles.titleSmall.copyWith(
                                color: isIn
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                            ),
                          );
                        }),
                      if (_loadingMore)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (_hasMore && _logs.isNotEmpty && !_loadingMore)
                        Center(
                          child: TextButton(
                            onPressed: _loadLogs,
                            child: const Text('加载更多'),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
