import 'consultation_call_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../message/im_workflow_request.dart';
import '../profile/recharge_page.dart';
import 'consultation_payment_setting_page.dart';

class PrivateLineCheckoutPage extends StatefulWidget {
  const PrivateLineCheckoutPage({
    super.key,
    required this.teacherId,
    required this.teacher,
    this.roomId,
    this.mode = 'private',
    this.beforeEnterCall,
  });

  final int teacherId;
  final Map<String, dynamic> teacher;
  final int? roomId;
  final String mode;
  final Future<void> Function()? beforeEnterCall;

  @override
  State<PrivateLineCheckoutPage> createState() =>
      _PrivateLineCheckoutPageState();
}

class _PrivateLineCheckoutPageState extends State<PrivateLineCheckoutPage> {
  final _scope = ImWorkflowRequest();
  bool _loading = true;
  bool _starting = false;
  bool _openingPayment = false;
  bool _uncertain = false;
  bool _sessionEnded = false;
  int _loadGeneration = 0;
  int? _pendingSessionId;
  String? _pendingPaymentMethod;
  String? _paymentError;
  String? _actionError;
  bool _coinEnabled = false;
  bool _alipayAvailable = false;
  bool _alipaySigned = false;
  String _paymentMethod = 'coin';
  bool _agreed = false;
  double? _balance;
  int _freezeMinutes = 5;
  String _connectionNotice = '';

  double get _rate =>
      (widget.teacher['privatePricePerMin'] as num?)?.toDouble() ?? 0;
  bool get _current => mounted && _scope.current;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _loadPayment();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    _loadGeneration++;
    setState(() {
      _loading = false;
      _starting = false;
      _balance = null;
      _coinEnabled = false;
      _alipaySigned = false;
      _pendingSessionId = null;
      _pendingPaymentMethod = null;
      _actionError = null;
      _paymentError = imSessionChangedMessage;
    });
  }

  Future<void> _loadPayment() async {
    if (!_current) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _paymentError = null;
    });
    try {
      final responses = await Future.wait([
        _scope.get('/api/consultation/payment-setting'),
        _scope.get('/api/auth/wallet/balance'),
        _scope.get('/api/consultation/config'),
      ]);
      final setting = responses[0];
      final wallet = responses[1];
      final config = responses[2];
      final enabled = setting['coinEnabled'] ?? setting['enabled'];
      final balance = double.tryParse('${wallet['balance']}');
      if (enabled is! bool ||
          balance == null ||
          !balance.isFinite ||
          balance < 0 ||
          config.isEmpty) {
        throw const ImWorkflowFailure('支付状态返回异常，请重试加载');
      }
      if (!_current || generation != _loadGeneration) return;
      setState(() {
        _coinEnabled = enabled;
        final alipay = setting['alipay'];
        _alipayAvailable = alipay is Map && alipay['available'] == true;
        _alipaySigned = alipay is Map && alipay['signed'] == true;
        final preferred = setting['preferredMethod']?.toString();
        _paymentMethod =
            preferred == 'alipay' && _alipaySigned ? 'alipay' : 'coin';
        _balance = balance;
        _freezeMinutes =
            ((config['freezeMinutes'] as num?)?.toInt() ?? 5).clamp(5, 60);
        _connectionNotice = (config[widget.mode == 'private_mic'
                    ? 'privateMicNotice'
                    : 'privateLineNotice']
                ?.toString() ??
            '');
      });
    } catch (error) {
      if (!_current || generation != _loadGeneration) return;
      setState(() {
        _balance = null;
        _coinEnabled = false;
        _alipaySigned = false;
        _paymentError = imFailureMessage(error, '支付状态加载失败，请重试');
      });
    } finally {
      if (_current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openPaymentSetting() async {
    if (!_current || _openingPayment) return;
    _openingPayment = true;
    try {
      await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const ConsultationPaymentSettingPage(),
      ));
      if (_current) await _loadPayment();
    } finally {
      _openingPayment = false;
    }
  }

  Future<void> _showInsufficientBalance({
    double? requiredAmount,
    double? availableBalance,
  }) async {
    if (!_current) return;
    final required = requiredAmount ?? _rate * _freezeMinutes;
    final available = availableBalance ?? _balance ?? 0;
    final recharge = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('玄遇币余额不足'),
        content: Text(
          '当前有${available.toStringAsFixed(2)}玄遇币，本次需先预冻结'
          '${required.toStringAsFixed(2)}玄遇币。不会自动扣微信、支付宝或银行卡。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去充值'),
          ),
        ],
      ),
    );
    if (recharge == true && mounted && _scope.current) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RechargePage()));
      if (_current) await _loadPayment();
    }
  }

  Future<void> _start() async {
    if (!_current ||
        _starting ||
        _loading ||
        _paymentError != null ||
        _sessionEnded) {
      return;
    }
    setState(() {
      _starting = true;
      _actionError = null;
    });
    var attemptedCreation = false;
    try {
      if (_pendingSessionId != null) {
        await _resumePendingSession();
        return;
      }
      if (_uncertain) {
        await _reconcileSession();
        return;
      }
      final methodReady =
          _paymentMethod == 'alipay' ? _alipaySigned : _coinEnabled;
      if (!methodReady) {
        await _openPaymentSetting();
        return;
      }
      if (_paymentMethod == 'coin' && _balance! < _rate * _freezeMinutes) {
        await _showInsufficientBalance();
        return;
      }
      if (!_agreed) {
        showAppToast(context, '请先确认服务与计费规则');
        return;
      }
      _pendingPaymentMethod = _paymentMethod;
      attemptedCreation = true;
      final data = await _scope.post('/api/consultation/sessions', data: {
        'teacherId': widget.teacherId,
        'mode': widget.mode,
        if (widget.roomId != null) 'roomId': widget.roomId,
        'paymentMethod': _paymentMethod,
        'agreementAccepted': true,
      });
      final id = _sessionId(data);
      if (id == null) {
        throw const ImWorkflowFailure('咨询创建结果待确认');
      }
      if (!_current) return;
      // Persist the confirmed ID before any room/audio callback can fail.
      _pendingSessionId = id;
      await _enterPendingSession();
    } catch (error) {
      if (!_current) return;
      final code = imFailureStatus(error);
      if (_pendingSessionId != null) {
        setState(() => _actionError = _sessionEnded
            ? '该咨询已结束或不可进入，请返回“我的咨询”查看记录'
            : '咨询已创建，暂未进入。请点击继续进入，不能重复发起。');
      } else if (attemptedCreation &&
          (code == null || code >= 500 || code == 408)) {
        setState(() {
          _uncertain = true;
          _actionError = '创建结果待确认，请核对咨询状态，勿重复发起。';
        });
      } else if (code == 428) {
        await _openPaymentSetting();
      } else if (code == 402 && _paymentMethod == 'coin') {
        final body = error is DioException ? error.response?.data : null;
        final payload = body is Map ? body['data'] : null;
        await _showInsufficientBalance(
          requiredAmount: payload is Map
              ? (payload['requiredAmount'] as num?)?.toDouble()
              : null,
          availableBalance: payload is Map
              ? (payload['availableBalance'] as num?)?.toDouble()
              : null,
        );
      } else {
        setState(() => _actionError = imFailureMessage(
            error, _uncertain ? '暂未核实咨询状态，请稍后再核对' : '发起失败，请稍后重试'));
      }
    } finally {
      if (_current) setState(() => _starting = false);
    }
  }

  int? _sessionId(Map data) {
    final value = data['id'];
    return value is num && value > 0 && value.isFinite && value == value.toInt()
        ? value.toInt()
        : null;
  }

  bool _matchesSession(Map data) =>
      data['teacherId'] == widget.teacherId &&
      data['mode'] == widget.mode &&
      data['roomId'] == widget.roomId &&
      data['paymentMethod'] == (_pendingPaymentMethod ?? _paymentMethod);

  bool _activeSession(Map data) => const {
        'waiting',
        'accepted',
        'connecting',
        'active'
      }.contains(data['status']);

  Future<void> _resumePendingSession() async {
    final id = _pendingSessionId!;
    final data = await _scope.get('/api/consultation/sessions/$id');
    if (!_current) return;
    if (_sessionId(data) != id ||
        !_matchesSession(data) ||
        !_activeSession(data)) {
      _sessionEnded = true;
      throw const ImWorkflowFailure('咨询已结束或不可进入');
    }
    await _enterPendingSession();
  }

  Future<void> _reconcileSession() async {
    final data =
        await _scope.get('/api/consultation/sessions', query: {'role': 'user'});
    if (!_current) return;
    final matches = imResponseList(data)
        .where((row) =>
            _sessionId(row) != null &&
            _matchesSession(row) &&
            _activeSession(row))
        .toList();
    if (matches.length != 1) {
      setState(() => _actionError = matches.isEmpty
          ? '尚未确认创建结果，请稍后再核对，或返回“我的咨询”查看。'
          : '有多条待确认咨询，请返回“我的咨询”选择，勿重复发起。');
      return;
    }
    _pendingSessionId = _sessionId(matches.single);
    _uncertain = false;
    await _enterPendingSession();
  }

  Future<void> _enterPendingSession() async {
    if (!_current || _pendingSessionId == null) return;
    final id = _pendingSessionId!;
    await widget.beforeEnterCall?.call();
    if (!mounted || !_scope.current || _pendingSessionId != id) return;
    final call = ConsultationCallOverlay.instance.open(id);
    Navigator.of(context).pop();
    await call;
  }

  @override
  Widget build(BuildContext context) {
    final teacher = widget.teacher;
    final avatar = teacher['avatarUrl']?.toString() ?? '';
    final name = teacher['nickname']?.toString() ?? '认证老师';
    final availableMinutes =
        _balance != null && _rate > 0 ? (_balance! / _rate).floor() : null;
    final reserveAmount = _rate * _freezeMinutes;
    final balanceInsufficient = _balance != null && _balance! < reserveAmount;
    final payingWithCoin = _paymentMethod == 'coin';
    final paymentReady = payingWithCoin ? _coinEnabled : _alipaySigned;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3EC),
        elevation: 0,
        title: const Text('确认语音咨询'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _paymentError != null
              ? Center(
                  child: ImWorkflowRetry(
                  message: _paymentError!,
                  onRetry: _scope.current ? _loadPayment : null,
                ))
              : AbsorbPointer(
                  absorbing:
                      _starting || _uncertain || _pendingSessionId != null,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE8E1D4)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 31,
                              backgroundColor: const Color(0xFFE8EFEA),
                              backgroundImage: avatar.isNotEmpty
                                  ? NetworkImage(avatar)
                                  : null,
                              child: avatar.isEmpty
                                  ? const Icon(Icons.person_rounded,
                                      color: Color(0xFF173F3B), size: 30)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(name,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.titleMedium),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.verified_rounded,
                                        size: 18, color: Color(0xFFB6812D)),
                                  ]),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${teacher['serviceStatus'] == 'online' ? '当前在线' : '当前忙碌'} · 评分 ${(teacher['rating'] as num?)?.toStringAsFixed(1) ?? '5.0'}',
                                    style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF173F3B), Color(0xFF285E55)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.graphic_eq_rounded,
                                    color: Color(0xFFF0D49B)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('语音沟通',
                                        style: AppTextStyles.titleSmall
                                            .copyWith(color: Colors.white)),
                                    const SizedBox(height: 3),
                                    const Text(
                                      '仅双方可听',
                                      style: TextStyle(
                                          color: Colors.white60, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                  '${_rate.toStringAsFixed(2)}${payingWithCoin ? '币' : '元'}/分钟',
                                  style: const TextStyle(
                                      color: Color(0xFFF0D49B),
                                      fontWeight: FontWeight.w800)),
                            ]),
                            const SizedBox(height: 16),
                            const Divider(color: Colors.white12, height: 1),
                            const SizedBox(height: 12),
                            const _CheckoutRow(label: '开始计费', value: '双方音频接通后'),
                            const _CheckoutRow(label: '等待接听', value: '不收费'),
                            if (payingWithCoin) ...[
                              _CheckoutRow(
                                label: '玄遇币余额',
                                value: _balance == null
                                    ? '请以钱包为准'
                                    : _balance!.toStringAsFixed(2),
                              ),
                              _CheckoutRow(
                                label: '连接门槛',
                                value:
                                    '${reserveAmount.toStringAsFixed(2)}币（至少$_freezeMinutes分钟）',
                              ),
                            ] else
                              const _CheckoutRow(
                                  label: '结算方式', value: '结束后按实际时长免密扣款'),
                            if (payingWithCoin && availableMinutes != null)
                              _CheckoutRow(
                                  label: '预计可通话',
                                  value: '约$availableMinutes分钟'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('结算方式', style: AppTextStyles.titleSmall),
                      const SizedBox(height: 10),
                      _CheckoutPaymentOption(
                        selected: _paymentMethod == 'alipay',
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFF1677FF),
                        title: '支付宝免密支付',
                        subtitle: !_alipayAvailable
                            ? '商户能力开通后可用'
                            : _alipaySigned
                                ? '已签约，结束后按实际时长扣款'
                                : '未签约，点击去开通',
                        onTap: () async {
                          if (!_alipaySigned) {
                            await _openPaymentSetting();
                          } else {
                            setState(() => _paymentMethod = 'alipay');
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _CheckoutPaymentOption(
                        selected: _paymentMethod == 'coin',
                        icon: Icons.auto_awesome_rounded,
                        color: const Color(0xFFB6812D),
                        title: '玄遇币支付',
                        subtitle: _coinEnabled
                            ? '余额需满足至少$_freezeMinutes分钟，未用部分自动释放'
                            : '未开通，点击去开通',
                        onTap: () async {
                          if (!_coinEnabled) {
                            await _openPaymentSetting();
                          } else {
                            setState(() => _paymentMethod = 'coin');
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCF6),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE8E1D4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('连麦须知', style: AppTextStyles.titleSmall),
                            const SizedBox(height: 9),
                            ...(_connectionNotice.isNotEmpty
                                    ? _connectionNotice.split('\n')
                                    : const [
                                        '私人沟通仅双方可以听见。',
                                        '等待接听和建立连接期间不收费。',
                                        '服务内容仅供交流参考，请勿线下交易。',
                                      ])
                                .where((line) => line.trim().isNotEmpty)
                                .map((line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Text('• ${line.trim()}',
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                  height: 1.55)),
                                    )),
                            if ((teacher['serviceNotice']?.toString() ?? '')
                                .isNotEmpty)
                              Text('老师说明：${teacher['serviceNotice']}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textHint, height: 1.55)),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agreed,
                        onChanged: (value) =>
                            setState(() => _agreed = value == true),
                        title: Text('我已了解语音服务、计费、取消和退款规则',
                            style: AppTextStyles.bodySmall),
                      ),
                    ],
                  )),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_actionError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_actionError!,
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center),
              ),
            FilledButton(
              onPressed: _starting ||
                      !_scope.current ||
                      _loading ||
                      _paymentError != null ||
                      _sessionEnded
                  ? null
                  : _start,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xFF173F3B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _starting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(!_scope.current
                      ? '请返回后重新进入'
                      : _loading
                          ? '正在加载支付状态'
                          : _paymentError != null
                              ? '暂不可发起咨询'
                              : _sessionEnded
                                  ? '请返回查看咨询记录'
                                  : _pendingSessionId != null
                                      ? '继续进入咨询'
                                      : _uncertain
                                          ? '核对咨询状态'
                                          : !paymentReady
                                              ? '先开通${payingWithCoin ? '玄遇币' : '支付宝免密'}支付'
                                              : payingWithCoin &&
                                                      balanceInsufficient
                                                  ? '余额不足 · 去充值'
                                                  : widget.mode == 'private_mic'
                                                      ? '发起私密连麦'
                                                      : '发起私人专线'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CheckoutRow extends StatelessWidget {
  const _CheckoutRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _CheckoutPaymentOption extends StatelessWidget {
  const _CheckoutPaymentOption({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? const Color(0xFF2C7566) : AppColors.divider,
                  width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleSmall),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color:
                      selected ? const Color(0xFF2C7566) : AppColors.textHint),
            ]),
          ),
        ),
      );
}
