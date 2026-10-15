import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluwx/fluwx.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/network/media_review.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';

Map<String, dynamic>? shopData(Response<dynamic> response) {
  final body = response.data;
  if (body is Map && body['data'] is Map) {
    return Map<String, dynamic>.from(body['data'] as Map);
  }
  return null;
}

String shopError(Object error, [String fallback = '操作失败，请稍后重试']) {
  if (error is MediaReviewException) return error.message;
  if (error is DioException && error.response?.data is Map) {
    return ((error.response!.data as Map)['message'] ?? fallback).toString();
  }
  return fallback;
}

double shopPrice(dynamic value) =>
    double.tryParse(value?.toString() ?? '') ?? 0;

String shopMoney(dynamic value) => shopPrice(value).toStringAsFixed(2);

Future<Response<dynamic>> _uploadShopEvidence(XFile file,
    {required bool moderate}) async {
  final values = <String, dynamic>{
    'file': await MultipartFile.fromFile(file.path, filename: file.name),
  };
  if (moderate) values['moderationScope'] = 'private';
  return apiClient.post('/api/config/upload', data: FormData.fromMap(values));
}

/// 私密审核材料优先走自动媒体安全；服务尚未配置时仍可进入业务人工审核。
Future<String> uploadPrivateShopEvidence(XFile file,
    {bool acceptPending = false}) async {
  Response<dynamic> response;
  try {
    response = await _uploadShopEvidence(file, moderate: true);
  } on DioException catch (error) {
    final body = error.response?.data;
    final message = body is Map ? body['message']?.toString() ?? '' : '';
    if (error.response?.statusCode != 503 || !message.contains('媒体安全审核')) {
      rethrow;
    }
    response = await _uploadShopEvidence(file, moderate: false);
  }
  final reviewed =
      await awaitMediaReview(response.data, acceptPending: acceptPending);
  final url = reviewed['url']?.toString() ?? '';
  if (url.isEmpty) throw StateError('图片上传失败');
  return url;
}

class ShopNetworkImage extends StatelessWidget {
  const ShopNetworkImage(this.url,
      {super.key, this.fit = BoxFit.cover, this.borderRadius = 0});

  final String? url;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim() ?? '';
    final seed =
        raw.codeUnits.fold<int>(17, (value, unit) => value * 31 + unit);
    const palette = <Color>[
      Color(0xFFDFF4EF),
      Color(0xFFFFE8D9),
      Color(0xFFE6E8FF),
      Color(0xFFFFF0C7),
      Color(0xFFE6F0FF),
    ];
    final accent = palette[seed.abs() % palette.length];
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Colors.white],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined,
          color: Color.lerp(accent, const Color(0xFF314C49), .45)),
    );
    if (raw.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, Colors.white],
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final pixels = (width * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(64, 1600)
              .toInt();
          return Image.network(raw,
              cacheWidth: pixels,
              fit: fit,
              errorBuilder: (_, __, ___) => placeholder);
        }),
      ),
    );
  }
}

class ShopProductCard extends StatelessWidget {
  const ShopProductCard(
      {super.key, required this.product, required this.onTap});

  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: SizedBox(
                    width: double.infinity,
                    child: ShopNetworkImage(
                      product['coverUrl']?.toString(),
                      fit: BoxFit.contain,
                    ))),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${product['presale'] is Map ? '【预售】' : ''}${product['name'] ?? '商品'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Text('¥${shopMoney(product['price'])}',
                          style: const TextStyle(
                              color: Color(0xFFD76C45),
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('已售${product['salesCount'] ?? 0}',
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> launchShopPayment(BuildContext context, int orderId,
    {String channel = 'alipay', ApiSessionScope? scope}) async {
  try {
    final response = scope == null
        ? await apiClient.post('/api/shop/orders/$orderId/pay',
            data: {'payChannel': channel})
        : await scope.post('/api/shop/orders/$orderId/pay',
            data: {'payChannel': channel});
    final data = shopData(response);
    if (data == null) {
      if (context.mounted) showAppToast(context, '支付信息获取失败');
      return false;
    }
    final mode = data['payMode']?.toString();
    final wechat = data['wechatPayParams'];
    final alipay = data['alipayOrderString']?.toString();
    final payUrl = data['payUrl']?.toString();
    if (mode == 'app' && wechat is Map) {
      final payment = Payment(
        appId: wechat['appId'].toString(),
        partnerId: wechat['partnerId'].toString(),
        prepayId: wechat['prepayId'].toString(),
        packageValue: wechat['packageValue'].toString(),
        nonceStr: wechat['nonceStr'].toString(),
        timestamp: (wechat['timestamp'] as num).toInt(),
        sign: wechat['sign'].toString(),
        signType: wechat['signType']?.toString() ?? 'RSA',
      );
      await Fluwx().pay(which: payment);
      if (context.mounted) showAppToast(context, '已唤起微信，请完成支付');
      return true;
    }
    if (mode == 'app' && alipay != null && alipay.isNotEmpty) {
      final result = await Tobias().pay(alipay);
      final success = result['resultStatus']?.toString() == '9000';
      if (context.mounted) showAppToast(context, success ? '支付成功' : '支付尚未完成');
      return success;
    }
    final uri = Uri.tryParse(payUrl ?? '');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    if (context.mounted) {
      showAppToast(context, data['message']?.toString() ?? '暂时无法发起支付，请稍后重试');
    }
  } catch (error) {
    if (context.mounted && error is! ApiSessionChangedException) {
      showAppToast(context, shopError(error, '支付发起失败'));
    }
  }
  return false;
}

Future<String?> chooseShopPaymentChannel(BuildContext context,
    {ApiSessionScope? scope}) async {
  try {
    final response = scope == null
        ? await apiClient.get('/api/shop/payment-methods')
        : await scope.get('/api/shop/payment-methods');
    final data = shopData(response);
    final methods = (data?['list'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['code']?.toString() ?? '').isNotEmpty)
        .toList();
    if (!context.mounted) return null;
    if (methods.isEmpty) {
      showAppToast(context, '支付通道维护中，请稍后再试');
      return null;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(18),
              child: Text('选择支付方式',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ...methods.map((item) {
            final code = item['code'].toString();
            final alipay = code == 'alipay';
            return ListTile(
              leading: Icon(
                  alipay ? Icons.account_balance_wallet_rounded : Icons.wechat,
                  color: alipay
                      ? const Color(0xFF1677FF)
                      : const Color(0xFF20B85A)),
              title:
                  Text(item['name']?.toString() ?? (alipay ? '支付宝' : '微信支付')),
              onTap: () => Navigator.pop(ctx, code),
            );
          }),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (scope != null) scope.ensureCurrent();
    return selected;
  } catch (error) {
    if (context.mounted && error is! ApiSessionChangedException) {
      showAppToast(context, shopError(error, '支付方式加载失败'));
    }
    return null;
  }
}

Future<String?> waitForShopOrderStatus(int orderId,
    {int attempts = 8,
    Duration interval = const Duration(milliseconds: 750),
    ApiSessionScope? scope}) async {
  for (var index = 0; index < attempts; index++) {
    try {
      final response = scope == null
          ? await apiClient.get('/api/shop/orders/$orderId')
          : await scope.get('/api/shop/orders/$orderId');
      final data = shopData(response);
      final status = data?['status']?.toString();
      if (status != null && status != 'pending_payment') return status;
    } on ApiSessionChangedException {
      return null;
    } catch (_) {}
    if (index + 1 < attempts) await Future<void>.delayed(interval);
  }
  return null;
}
