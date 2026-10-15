import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluwx/fluwx.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/app_button.dart';

/// 名师预约定金支付（与充值共用下单接口，type 区分业务）
class MasterDepositPayPage extends StatefulWidget {
  const MasterDepositPayPage({
    super.key,
    required this.targetUserId,
    required this.masterNickname,
    required this.depositAmount,
    this.reserveRemark = '',
  });

  final int targetUserId;
  final String masterNickname;
  final double depositAmount;
  final String reserveRemark;

  @override
  State<MasterDepositPayPage> createState() => _MasterDepositPayPageState();
}

class _MasterDepositPayPageState extends State<MasterDepositPayPage> {
  bool _loading = false;
  String _selectedChannel = 'wechat';

  Future<void> _submit() async {
    if (widget.depositAmount < 0.01) {
      showAppToast(context, '定金金额无效');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await apiClient.post('/api/auth/order/create', data: {
        // 与后端 master_deposit / master_consult_deposit 均可；DB 存为 master_deposit
        'type': 'master_deposit',
        'targetUserId': widget.targetUserId,
        'amount': widget.depositAmount.toStringAsFixed(2),
        'payChannel': _selectedChannel,
        'payMode': 'app',
        if (widget.reserveRemark.trim().isNotEmpty) 'reserveRemark': widget.reserveRemark.trim(),
      });
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        final payUrl = data['payUrl'] as String?;
        final message = data['message'] as String?;
        final payMode = data['payMode'] as String?;
        final wechatPayParams = data['wechatPayParams'] as Map?;
        final alipayOrderString = data['alipayOrderString'] as String?;
        final fluwx = Fluwx();

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
          await fluwx.pay(which: payment);
          if (mounted) showAppToast(context, '已唤起微信，请完成定金支付');
        } else if (payMode == 'app' && alipayOrderString != null && alipayOrderString.isNotEmpty) {
          final result = await Tobias().pay(alipayOrderString);
          final status = result['resultStatus']?.toString();
          if (mounted) {
            if (status == '9000') {
              showAppToast(context, '定金支付成功');
              Navigator.of(context).pop(true);
            } else if (status == '6001') {
              showAppToast(context, '已取消支付');
            } else {
              showAppToast(context, '支付未完成，请重试');
            }
          }
        } else if (payUrl != null && payUrl.isNotEmpty) {
          final uri = Uri.tryParse(payUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (mounted) showAppToast(context, '请在浏览器中完成定金支付');
          }
        } else {
          if (mounted) showAppToast(context, message ?? '订单已创建，请按提示完成支付');
        }
      } else {
        if (mounted) showAppToast(context, '创建订单失败，请稍后重试');
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map) ? e.response!.data['message']?.toString() : null;
      if (mounted) showAppToast(context, msg ?? '创建订单失败');
    } catch (_) {
      if (mounted) showAppToast(context, '网络异常');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amt = widget.depositAmount.toStringAsFixed(2);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text('付定金', style: AppTextStyles.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('名师预约 · 定金', style: AppTextStyles.titleSmall),
            const SizedBox(height: 8),
            Text(widget.masterNickname, style: AppTextStyles.titleMedium),
            if (widget.reserveRemark.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('备注：${widget.reserveRemark.trim()}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF059669).withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('应付定金', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                  const SizedBox(height: 8),
                  Text('¥$amt', style: AppTextStyles.displayLarge.copyWith(fontSize: 36, color: const Color(0xFF059669))),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('支付方式', style: AppTextStyles.titleSmall),
            const SizedBox(height: 12),
            _buildPayOption('wechat', '微信支付', Icons.chat_rounded, const Color(0xFF07C160)),
            const SizedBox(height: 12),
            _buildPayOption('alipay', '支付宝', Icons.account_balance_wallet_rounded, const Color(0xFF1677FF)),
            const SizedBox(height: 40),
            AppButton(
              label: _loading ? '处理中…' : '确认付定金',
              onPressed: _loading ? null : _submit,
              loading: _loading,
            ),
            const SizedBox(height: 16),
            Text(
              '支付成功后，名师将在方便时与你联系；若暂时无法支付，请稍后重试。',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayOption(String channel, String label, IconData icon, Color color) {
    final selected = _selectedChannel == channel;
    return GestureDetector(
      onTap: () => setState(() => _selectedChannel = channel),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
            Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? AppColors.primary : AppColors.textHint, size: 24),
          ],
        ),
      ),
    );
  }
}
