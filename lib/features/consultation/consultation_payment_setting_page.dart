import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

class ConsultationPaymentSettingPage extends StatefulWidget {
  const ConsultationPaymentSettingPage({super.key});

  @override
  State<ConsultationPaymentSettingPage> createState() =>
      _ConsultationPaymentSettingPageState();
}

class _ConsultationPaymentSettingPageState
    extends State<ConsultationPaymentSettingPage> {
  ApiSessionScope _scope = ApiSessionScope();
  bool _loading = true;
  bool _saving = false;
  int _loadGeneration = 0;
  String? _error;
  bool _coinEnabled = false;
  bool _alipayAvailable = false;
  bool _alipaySigned = false;
  String _alipayStatus = 'unsigned';
  String _preferredMethod = 'coin';

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
      _loading = next.authenticated;
      _saving = false;
      _error = next.authenticated ? null : '请登录后查看支付设置';
      _coinEnabled = false;
      _alipayAvailable = false;
      _alipaySigned = false;
      _alipayStatus = 'unsigned';
      _preferredMethod = 'coin';
    });
    if (next.authenticated) unawaited(_load());
  }

  void _applyData(dynamic raw) {
    if (raw is! Map) return;
    final alipay = raw['alipay'];
    _coinEnabled = raw['coinEnabled'] == true || raw['enabled'] == true;
    _preferredMethod = raw['preferredMethod'] == 'alipay' ? 'alipay' : 'coin';
    _alipayAvailable = alipay is Map && alipay['available'] == true;
    _alipaySigned = alipay is Map && alipay['signed'] == true;
    _alipayStatus =
        alipay is Map ? '${alipay['status'] ?? 'unsigned'}' : 'unsigned';
  }

  Future<void> _load({bool refreshing = false}) async {
    final scope = _scope;
    final generation = ++_loadGeneration;
    if (!scope.authenticated) {
      if (mounted) setState(() => _error = '请登录后查看支付设置');
      return;
    }
    if (!refreshing && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = refreshing
          ? await scope.post('/api/consultation/payment-setting/alipay/refresh')
          : await scope.get('/api/consultation/payment-setting');
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('支付设置返回异常');
      if (!mounted || !scope.current || generation != _loadGeneration) return;
      setState(() {
        _applyData(data);
        _error = null;
      });
      if (refreshing) {
        showAppToast(context, _alipaySigned ? '支付宝免密支付已开通' : '暂未查询到签约结果');
      }
    } catch (error) {
      if (mounted && scope.current && generation == _loadGeneration) {
        final message = apiSessionFailureMessage(error, '支付设置加载失败');
        setState(() => _error = message);
        if (refreshing) showAppToast(context, message);
      }
    } finally {
      if (mounted && scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _confirmRules(String title, List<String> rules) async {
    var agreed = false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...rules.map((rule) => _Rule(text: rule)),
                    CheckboxListTile(
                      value: agreed,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) =>
                          setDialogState(() => agreed = value == true),
                      title: const Text('我已阅读并同意以上规则'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('暂不开通'),
                ),
                FilledButton(
                  onPressed:
                      agreed ? () => Navigator.pop(dialogContext, true) : null,
                  child: const Text('同意并继续'),
                ),
              ],
            ),
          ),
        ) ==
        true;
  }

  Future<void> _toggleCoin() async {
    if (_saving) return;
    final scope = _scope;
    if (!_coinEnabled) {
      final agreed = await _confirmRules('开通玄遇币支付', const [
        '连接前需有不少于5分钟费用的玄遇币；不足时不会建立连接。',
        '等待接听、排队和建立连接期间不收费。',
        '双方音频接通后按实际有效时长结算，未使用的预留金额自动释放。',
      ]);
      if (!agreed) return;
    }
    if (!scope.current) return;
    setState(() => _saving = true);
    try {
      final next = !_coinEnabled;
      final preferred = !next && _alipaySigned ? 'alipay' : _preferredMethod;
      final response =
          await scope.put('/api/consultation/payment-setting', data: {
        'coinEnabled': next,
        'enabled': next,
        'preferredMethod': preferred,
        'agreed': next,
      });
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('设置结果异常');
      if (!mounted || !scope.current) return;
      setState(() => _applyData(data));
      showAppToast(context, next ? '玄遇币支付已开通' : '玄遇币支付已关闭');
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '设置失败'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _saving = false);
    }
  }

  Future<void> _signAlipay() async {
    final scope = _scope;
    if (!_alipayAvailable) {
      showAppToast(context, '商户免密能力开通后可用，请先使用玄遇币支付');
      return;
    }
    final agreed = await _confirmRules('开通支付宝免密支付', const [
      '等待接听、排队和连接期间不扣款。',
      '通话结束后按实际有效时长从已签约支付宝账户扣款。',
      '若扣款失败，需先补缴本次订单后才能再次使用付费连线。',
      '可随时在本页解除签约，已产生的待支付账单不受影响。',
    ]);
    if (!agreed || !mounted || !scope.current) return;
    setState(() => _saving = true);
    try {
      final response = await scope.post(
          '/api/consultation/payment-setting/alipay/sign',
          data: {'agreed': true});
      final data = (response.data as Map?)?['data'];
      final signUrl = data is Map ? data['signUrl']?.toString() : null;
      if (signUrl == null || signUrl.isEmpty) {
        if (scope.current) await _load(refreshing: true);
        return;
      }
      final uri = Uri.tryParse(signUrl);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('无法打开支付宝签约页面');
      }
      if (!mounted || !scope.current) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('请在支付宝完成签约'),
          content: const Text('完成后返回玄遇，点击“查询签约结果”。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍后查询'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (scope.current) _load(refreshing: true);
              },
              child: const Text('查询签约结果'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(
          context,
          error is FormatException
              ? error.message
              : apiSessionFailureMessage(error, '签约发起失败'),
        );
      }
    } finally {
      if (mounted && scope.current) setState(() => _saving = false);
    }
  }

  Future<void> _unsignAlipay() async {
    final scope = _scope;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('解除支付宝免密支付？'),
            content: const Text('解除后不能再选择支付宝发起付费连线。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('确认解除')),
            ],
          ),
        ) ==
        true;
    if (!confirmed || !mounted || !scope.current) return;
    setState(() => _saving = true);
    try {
      final response =
          await scope.post('/api/consultation/payment-setting/alipay/unsign');
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('解除结果异常');
      if (!mounted || !scope.current) return;
      setState(() => _applyData(data));
      showAppToast(context, '支付宝免密支付已解除');
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '解除失败'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _saving = false);
    }
  }

  Future<void> _prefer(String method) async {
    if (_saving || method == _preferredMethod) return;
    final scope = _scope;
    if (method == 'coin' && !_coinEnabled) {
      await _toggleCoin();
      return;
    }
    if (method == 'alipay' && !_alipaySigned) {
      await _signAlipay();
      return;
    }
    setState(() => _saving = true);
    try {
      final response =
          await scope.put('/api/consultation/payment-setting', data: {
        'coinEnabled': _coinEnabled,
        'enabled': _coinEnabled,
        'preferredMethod': method,
        'agreed': true,
      });
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('设置结果异常');
      if (!mounted || !scope.current) return;
      setState(() => _applyData(data));
      showAppToast(context, '已设为默认支付方式');
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '设置失败'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _saving = false);
    }
  }

  String get _alipayHint {
    if (!_alipayAvailable) return '商户免密能力开通后可用';
    if (_alipaySigned) return '已签约 · 通话结束按实际时长扣款';
    if (_alipayStatus == 'pending') return '签约处理中，可查询签约结果';
    return '未签约 · 需跳转支付宝授权';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFFF6F3EC),
        title: const Text('连线支付设置'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      if (_scope.authenticated)
                        TextButton(
                          onPressed: _load,
                          child: const Text('重新加载'),
                        ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  children: [
                    Text('选择支付方式', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 5),
                    Text('私人专线、公开连麦和私密连麦均使用这里的设置',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    _PaymentCard(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFF1677FF),
                      title: '支付宝免密支付',
                      subtitle: _alipayHint,
                      preferred: _preferredMethod == 'alipay' && _alipaySigned,
                      enabled: _alipaySigned,
                      actionText: _alipaySigned
                          ? '解除'
                          : _alipayStatus == 'pending'
                              ? '查询'
                              : '去开通',
                      onTap: _saving ? null : () => _prefer('alipay'),
                      onAction: _alipaySigned
                          ? (_saving ? null : _unsignAlipay)
                          : _alipayStatus == 'pending'
                              ? (_saving ? null : () => _load(refreshing: true))
                              : (_saving ? null : _signAlipay),
                    ),
                    const SizedBox(height: 12),
                    _PaymentCard(
                      icon: Icons.auto_awesome_rounded,
                      iconColor: const Color(0xFFB6812D),
                      title: '玄遇币支付',
                      subtitle: _coinEnabled
                          ? '已开通 · 连接前余额须满足至少5分钟'
                          : '未开通 · 按实际时长结算并释放余款',
                      preferred: _preferredMethod == 'coin' && _coinEnabled,
                      enabled: _coinEnabled,
                      actionText: _coinEnabled ? '关闭' : '去开通',
                      onTap: _saving ? null : () => _prefer('coin'),
                      onAction: _saving ? null : _toggleCoin,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8E1D4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('共同计费规则', style: AppTextStyles.titleSmall),
                          const SizedBox(height: 12),
                          const _Rule(text: '等待老师接听、排队和连接期间不收费。'),
                          const _Rule(text: '双方音频接通后，服务端按实际有效时长计费。'),
                          const _Rule(text: '发起每次服务前仍会显示单价、支付方式和连麦须知。'),
                          const _Rule(text: '异常断线有保护时间；重新连接失败会自动结束并结算。'),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.preferred,
    required this.enabled,
    required this.actionText,
    required this.onTap,
    required this.onAction,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool preferred;
  final bool enabled;
  final String actionText;
  final VoidCallback? onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: preferred
                      ? const Color(0xFF2C7566)
                      : const Color(0xFFE8E1D4),
                  width: preferred ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(title, style: AppTextStyles.titleSmall),
                      if (preferred) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE8F3EF),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Text('默认',
                              style: TextStyle(
                                  color: Color(0xFF2C7566), fontSize: 10)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 5),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              TextButton(
                onPressed: onAction,
                child: Text(actionText,
                    style: TextStyle(
                        color: enabled
                            ? AppColors.textSecondary
                            : const Color(0xFF2C7566))),
              ),
            ]),
          ),
        ),
      );
}

class _Rule extends StatelessWidget {
  const _Rule({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child:
                  CircleAvatar(radius: 2.5, backgroundColor: Color(0xFFB6812D)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary, height: 1.55)),
            ),
          ],
        ),
      );
}
