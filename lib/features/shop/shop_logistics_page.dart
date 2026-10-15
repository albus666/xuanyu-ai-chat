import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_common.dart';

class ShopLogisticsPage extends StatefulWidget {
  const ShopLogisticsPage({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<ShopLogisticsPage> createState() => _ShopLogisticsPageState();
}

class _ShopLogisticsPageState extends State<ShopLogisticsPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final id = (widget.order['id'] as num).toInt();
      final data =
          shopData(await apiClient.get('/api/shop/orders/$id/logistics'));
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) showAppToast(context, shopError(error, '物流信息加载失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(dynamic value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.replaceFirst('T', ' ').split('.').first;
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_data?['externalQueryUrl']?.toString() ?? '');
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showAppToast(context, '暂时无法打开快递查询');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final events = (data?['events'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final company = data?['company']?.toString() ??
        widget.order['expressCompany']?.toString() ??
        '';
    final trackingNo = data?['trackingNo']?.toString() ??
        widget.order['expressNo']?.toString() ??
        '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(title: const Text('物流详情')),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF163E38),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(Icons.local_shipping_outlined,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data?['status']?.toString() ?? '已发货',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800)),
                                  if ((data?['currentLocation']?.toString() ??
                                          '')
                                      .isNotEmpty)
                                    Text(data!['currentLocation'].toString(),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            height: 1.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('$company  $trackingNo',
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: trackingNo));
                            if (context.mounted) {
                              showAppToast(context, '快递单号已复制');
                            }
                          },
                          child: const Text('复制单号',
                              style: TextStyle(
                                  color: Color(0xFF70DED0),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  if ((data?['message']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8EE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(data!['message'].toString(),
                          style: const TextStyle(
                              color: Color(0xFF80633F), height: 1.5)),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text('运输轨迹',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  if (events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无物流轨迹')),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: events.asMap().entries.map((entry) {
                          final latest = entry.key == 0;
                          final event = entry.value;
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: latest ? 13 : 9,
                                        height: latest ? 13 : 9,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: latest
                                              ? AppColors.primary
                                              : const Color(0xFFD3DEDB),
                                        ),
                                      ),
                                      if (entry.key < events.length - 1)
                                        Expanded(
                                          child: Container(
                                            width: 1.5,
                                            color: const Color(0xFFE2E9E7),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 22),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            event['description']?.toString() ??
                                                '',
                                            style: TextStyle(
                                                color: latest
                                                    ? AppColors.textPrimary
                                                    : AppColors.textSecondary,
                                                height: 1.5,
                                                fontWeight: latest
                                                    ? FontWeight.w700
                                                    : FontWeight.w400)),
                                        const SizedBox(height: 5),
                                        Text(_time(event['time']),
                                            style: const TextStyle(
                                                color: AppColors.textHint,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('通过快递100查询最新轨迹'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
