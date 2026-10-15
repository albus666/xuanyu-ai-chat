import 'package:flutter/material.dart';

String shopPresaleTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '待确认';
  final date = parsed.toUtc().add(const Duration(hours: 8));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}

class ShopPresaleNotice extends StatelessWidget {
  const ShopPresaleNotice({super.key, required this.data, this.order = false});
  final Map data;
  final bool order;

  @override
  Widget build(BuildContext context) {
    final overdue = data['overdue'] == true;
    final note = data['delayNote']?.toString() ?? '';
    final limit = (data['limit'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: overdue ? const Color(0xFFFFEEE9) : const Color(0xFFFFF8EE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(overdue ? '预售已逾期 · 可申请退款' : '全款预售',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF824A28))),
        const SizedBox(height: 6),
        Text(
            '${order ? '原承诺' : '承诺'}最晚发货：${shopPresaleTime(data['shipBy'])}（北京时间）',
            style: const TextStyle(color: Color(0xFF664C38), height: 1.5)),
        Text('批次：${data['batch'] ?? ''}',
            style: const TextStyle(color: Color(0xFF664C38))),
        if (!order) ...[
          Text(
              '预售时间：${shopPresaleTime(data['startAt'])} 至 ${shopPresaleTime(data['endAt'])}',
              style: const TextStyle(color: Color(0xFF664C38), height: 1.5)),
          if (limit > 0)
            Text('本批次每人限购 $limit 件，待付款订单也占名额。',
                style: const TextStyle(color: Color(0xFF664C38), height: 1.5)),
          const Text('一次支付全款，无需尾款。未发货可申请退款；实际到账以支付渠道确认为准。',
              style: TextStyle(color: Color(0xFF664C38), height: 1.5)),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('延期说明：$note',
              style: const TextStyle(color: Color(0xFF824A28), height: 1.5)),
          Text('更新预计：${shopPresaleTime(data['revisedShipAt'])}（北京时间）',
              style: const TextStyle(color: Color(0xFF824A28), height: 1.5)),
          const Text('原承诺保留，可在订单申请退款。',
              style: TextStyle(color: Color(0xFF824A28))),
        ],
      ]),
    );
  }
}
