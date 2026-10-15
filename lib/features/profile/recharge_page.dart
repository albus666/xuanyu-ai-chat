import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluwx/fluwx.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/app_button.dart';
import '../../core/payment/apple_iap_service.dart';
import 'apple_recharge_page.dart';

/// 充值入口：微信、支付宝
class RechargePage extends StatefulWidget {
  const RechargePage({super.key});

  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  ApiSessionScope _scope = ApiSessionScope();
  final _amountController = TextEditingController();
  bool _loading = false;
  bool _submitLocked = false;
  bool _sessionInvalid = false;
  List<String> _channels = [];
  bool _loadingChannels = true;
  bool _channelsFailed = false;
  String _selectedChannel = 'alipay'; // 默认支付宝（当前已配置）
  final _fluwx = Fluwx();
  static const _presets = ['30', '50', '100', '200', '500'];

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    if (!usesAppleIap) _loadChannels();
  }

  Future<void> _loadChannels() async {
    final scope = _scope;
    setState(() {
      _loadingChannels = true;
      _channelsFailed = false;
    });
    try {
      final response = await scope.get('/api/auth/payment/channels');
      final body = response.data as Map?;
      final raw = (body?['data'] as Map?)?['channels'];
      if (body?['code'] != 0 || raw is! List) {
        throw const FormatException('Invalid payment channel response');
      }
      final channels = raw
          .whereType<String>()
          .where((channel) => channel == 'alipay' || channel == 'wechat')
          .toSet()
          .toList();
      if (!mounted || !scope.current || _sessionInvalid) return;
      setState(() {
        _channels = channels;
        if (!channels.contains(_selectedChannel) && channels.isNotEmpty) {
          _selectedChannel = 'alipay';
        }
      });
    } catch (_) {
      if (mounted && scope.current && !_sessionInvalid) {
        setState(() {
          _channelsFailed = true;
          _channels = [];
        });
      }
    } finally {
      if (mounted && scope.current && !_sessionInvalid) {
        setState(() => _loadingChannels = false);
      }
    }
  }

  void _onSessionChanged() {
    _scope = ApiSessionScope();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sessionInvalid = true;
      _amountController.clear();
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedChannel == 'alipay') {
      showAppToast(context, '上线后才可申请支付宝支付');
      return;
    }
    if (_selectedChannel == 'wechat') {
      showAppToast(context, '上线后才可申请微信支付');
      return;
    }
    if (_sessionInvalid ||
        _submitLocked ||
        _loadingChannels ||
        !_channels.contains(_selectedChannel)) {
      return;
    }
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 0.01) {
      showAppToast(context, '请输入有效金额');
      return;
    }
    if (amount > 10000) {
      showAppToast(context, '单笔最多充值10000元');
      return;
    }
    _submitLocked = true;
    final scope = _scope;
    try {
      setState(() => _loading = true);
      final res = await scope.post(
        '/api/auth/order/create',
        data: {
          'type': 'recharge',
          'amount': amount.toStringAsFixed(2),
          'payChannel': _selectedChannel,
          'payMode': 'app', // APP 支付，直接唤起微信/支付宝
        },
      );
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted && scope.current && !_sessionInvalid) {
        final payUrl = data['payUrl'] as String?;
        final orderNo = data['orderNo'] as String?;
        final message = data['message'] as String?;
        final payMode = data['payMode'] as String?;
        final wechatPayParams = data['wechatPayParams'] as Map?;
        final alipayOrderString = data['alipayOrderString'] as String?;

        if (payMode == 'app' && wechatPayParams != null) {
          final p = wechatPayParams;
          final payment = Payment(
            appId: p['appId'] as String,
            partnerId: p['partnerId'] as String,
            prepayId: p['prepayId'] as String,
            packageValue: p['packageValue'] as String,
            nonceStr: p['nonceStr'] as String,
            timestamp: p['timestamp'] as int,
            sign: p['sign'] as String,
            signType: p['signType'] as String? ?? 'RSA',
          );
          if (!await _fluwx.registerApi(appId: payment.appId)) {
            throw PlatformException(code: 'wechat_registration_failed');
          }
          if (!await _fluwx.isWeChatInstalled) {
            if (mounted && scope.current) showAppToast(context, '请先安装微信后再支付');
            return;
          }
          if (!scope.current || !mounted || _sessionInvalid) return;
          final launched = await _fluwx.pay(which: payment);
          if (!launched) throw PlatformException(code: 'wechat_launch_failed');
          if (mounted && scope.current && !_sessionInvalid) {
            showAppToast(context, '已唤起微信，请完成支付');
          }
        } else if (payMode == 'app' &&
            alipayOrderString != null &&
            alipayOrderString.isNotEmpty) {
          final result = await Tobias().pay(alipayOrderString);
          final status = result['resultStatus']?.toString();
          if (mounted && scope.current && !_sessionInvalid) {
            if (status == '9000') {
              showAppToast(context, '支付完成，到账结果请查看余额和订单');
            } else if (status == '6001') {
              showAppToast(context, '已取消支付');
            } else {
              showAppToast(context, status == null ? '支付异常' : '支付失败，请重试');
            }
          }
        } else if (payUrl != null && payUrl.isNotEmpty) {
          final uri = Uri.tryParse(payUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (mounted && scope.current && !_sessionInvalid) {
              showAppToast(context, '请在浏览器中完成支付');
            }
          } else {
            if (mounted && scope.current && !_sessionInvalid) {
              showAppToast(context, '无法打开支付页面，请稍后重试');
            }
          }
        } else if (orderNo != null) {
          if (mounted && scope.current && !_sessionInvalid) {
            showAppToast(context, message ?? '订单已创建，暂时无法调起支付，请稍后重试');
          }
        } else {
          if (mounted && scope.current && !_sessionInvalid) {
            showAppToast(context, message ?? '暂时无法发起充值，请稍后重试');
          }
        }
      } else {
        if (mounted && scope.current && !_sessionInvalid) {
          showAppToast(context, '暂时无法发起充值，请稍后重试');
        }
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? e.response!.data['message']?.toString()
          : null;
      if (mounted && scope.current && !_sessionInvalid) {
        showAppToast(context, msg ?? '创建订单失败');
      }
    } on PlatformException catch (e) {
      final message = e.code == 'AliPay UrlScheme Not Found'
          ? '当前版本支付宝配置异常，请更新 App 后重试'
          : '无法唤起支付，请稍后重试';
      if (mounted && scope.current && !_sessionInvalid) {
        showAppToast(context, message);
      }
    } on MissingPluginException catch (_) {
      if (mounted && scope.current && !_sessionInvalid) {
        showAppToast(context, '当前版本支付组件不可用，请更新 App 后重试');
      }
    } catch (_) {
      if (mounted && scope.current && !_sessionInvalid) {
        showAppToast(context, '发起支付异常，请稍后重试');
      }
    } finally {
      _submitLocked = false;
      if (mounted && scope.current && !_sessionInvalid) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (usesAppleIap) return const AppleRechargePage();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('充值玄遇币', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_sessionInvalid) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '账号已切换，请返回后重新进入充值页',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A5A2B)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '1元购买1玄遇币。可用于咨询、虚拟头像、虚拟礼物和进房特效等站内数字服务，不可提现、转赠或交易；购买到账后不支持退款。',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('充值金额（自定义）', style: AppTextStyles.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              enabled: !_sessionInvalid,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: '输入金额，单位：元（1元=1玄遇币）',
                prefixText: '¥ ',
                suffixText: '元',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '快捷选择',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _presets.map((s) {
                final selected = _amountController.text.trim() == s;
                return GestureDetector(
                  onTap: _sessionInvalid
                      ? null
                      : () => setState(() => _amountController.text = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryLight
                          : AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.divider,
                      ),
                    ),
                    child: Text('$s元', style: AppTextStyles.bodyMedium),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            Text('支付方式（人民币）', style: AppTextStyles.titleSmall),
            const SizedBox(height: 12),
            _buildPayOption(
              'alipay',
              '支付宝',
              Icons.account_balance_wallet_rounded,
              const Color(0xFF1677FF),
              onTap: () => showAppToast(context, '上线后才可申请支付宝支付'),
            ),
            const SizedBox(height: 12),
            _buildPayOption(
              'wechat',
              '微信支付',
              Icons.chat_rounded,
              const Color(0xFF07C160),
              onTap: () => showAppToast(context, '上线后才可申请微信支付'),
            ),
            if (_loadingChannels)
              const Text('正在加载支付方式…')
            else if (_channelsFailed) ...[
              const Text('支付方式加载失败，请重试'),
              TextButton(onPressed: _loadChannels, child: const Text('重试')),
            ] else if (_channels.isEmpty)
              const Text('充值暂不可用，请稍后重试'),
            const SizedBox(height: 40),
            AppButton(
              label: _loading ? '处理中…' : '确认支付并充值',
              onPressed: _loading ||
                      _sessionInvalid ||
                      _loadingChannels ||
                      !_channels.contains(_selectedChannel)
                  ? null
                  : _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayOption(
    String channel,
    String label,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final selected = _selectedChannel == channel;
    return GestureDetector(
      onTap: _sessionInvalid
          ? null
          : onTap ?? () => setState(() => _selectedChannel = channel),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.textHint,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
