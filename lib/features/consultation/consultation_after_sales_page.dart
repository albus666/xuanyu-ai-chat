import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

class ConsultationAfterSalesPage extends StatefulWidget {
  const ConsultationAfterSalesPage({super.key, this.initialSession});

  final Map<String, dynamic>? initialSession;

  @override
  State<ConsultationAfterSalesPage> createState() =>
      _ConsultationAfterSalesPageState();
}

class _ConsultationAfterSalesPageState
    extends State<ConsultationAfterSalesPage> {
  static const _reasons = <String, String>{
    'not_provided': '服务未完成',
    'connection_issue': '连接或音质异常',
    'billing_issue': '计费存在疑问',
    'service_quality': '服务体验问题',
    'conduct': '不当言行或违规',
    'privacy': '隐私与信息安全',
    'other': '其他问题',
  };

  final _description = TextEditingController();
  final _items = <Map<String, dynamic>>[];
  String _reasonType = 'connection_issue';
  bool _loading = true;
  bool _submitting = false;
  bool _acting = false;

  final _scope = ApiSessionScope();

  void _accountChanged() {
    if (mounted && !_scope.current) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    try {
      final response = await _scope.get('/api/consultation/disputes');
      final raw = ((response.data as Map?)?['data'] as Map?)?['list'];
      if (mounted && _scope.current) {
        setState(() {
          _items
            ..clear()
            ..addAll((raw as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)));
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && _scope.current) {
        setState(() => _loading = false);
        showAppToast(
          context, apiSessionFailureMessage(error, '售后记录加载失败'));
      }
    }
  }

  Future<void> _submit() async {
    if (!mounted || !_scope.current || _submitting) return;
    final session = widget.initialSession;
    final sessionId = (session?['id'] as num?)?.toInt();
    final text = _description.text.trim();
    if (sessionId == null) return;
    if (text.length < 10) {
      showAppToast(context, '请用至少10个字说明实际情况');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _scope.post('/api/consultation/disputes', data: {
        'sessionId': sessionId,
        'reasonType': _reasonType,
        'reason': text,
        if (session?['viewerRole'] != 'teacher')
          'requestedAmount': session?['chargedAmount'] ?? 0,
      });
      if (!mounted || !_scope.current) return;
      _description.clear();
      if (mounted && _scope.current) showAppToast(context, '售后申请已提交，平台会在记录中更新进度');
      await _load();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(
          context, apiSessionFailureMessage(error, '提交失败'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _submitting = false);
    }
  }

  Future<void> _action(Map<String, dynamic> item, String action) async {
    if (!mounted || !_scope.current || _acting) return;
    setState(() => _acting = true);
    try {
      await _performAction(item, action);
    } finally {
      if (mounted && _scope.current) setState(() => _acting = false);
    }
  }

  Future<void> _performAction(Map<String, dynamic> item, String action) async {
    String? reply;
    if (action == 'supplement') {
      final controller = TextEditingController();
      reply = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('补充资料'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 7,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: '针对平台的要求，补充时间、经过或其他可核实信息',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('提交'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reply == null || reply.length < 5) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('撤销售后申请'),
          content: const Text('撤销后，对应冻结收益会按原结算状态恢复。确定继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不撤销'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认撤销'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted || !_scope.current) return;
    try {
      await _scope.post(
        '/api/consultation/disputes/${item['id']}/$action',
        data: reply == null ? null : {'reply': reply},
      );
      await _load();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(
          context, apiSessionFailureMessage(error, '操作失败'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('账号已切换')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }

    final initialId = (widget.initialSession?['id'] as num?)?.toInt();
    final alreadyApplied = initialId != null &&
        _items.any((item) =>
            item['sessionId'] == initialId &&
            ['pending', 'reviewing', 'need_info', 'pending_refund']
                .contains(item['status']));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('咨询售后'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                children: [
                  if (widget.initialSession != null && !alreadyApplied)
                    _applicationForm(widget.initialSession!),
                  if (widget.initialSession != null && !alreadyApplied)
                    const SizedBox(height: 24),
                  Text('处理记录', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    _box(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '暂无售后记录',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint),
                        ),
                      ),
                    )
                  else
                    ..._items.map(_recordCard),
                ],
              ),
            ),
    );
  }

  Widget _applicationForm(Map<String, dynamic> session) {
    final teacher = session['viewerRole'] == 'teacher';
    final paid = (session['chargedAmount'] as num?)?.toDouble() ?? 0;
    final unit = session['paymentMethod'] == 'alipay' ? '元' : '玄遇币';
    return _box(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teacher ? '反馈订单问题' : '申请售后', style: AppTextStyles.titleSmall),
          const SizedBox(height: 5),
          Text(
            teacher
                ? '提交后平台会核查订单、连接及计费记录。'
                : paid > 0
                    ? '本单实付 $paid$unit；申请期间对应老师收益会冻结。'
                    : '本单未产生扣费，仍可反馈服务或连接问题。',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _reasonType,
            decoration: const InputDecoration(
              labelText: '问题类型',
              border: OutlineInputBorder(),
            ),
            items: _reasons.entries
                .map((entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _reasonType = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: '情况说明',
              hintText: '请写明发生时间、实际经过、期望处理方式，避免只写“有问题”',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? '提交中…' : '提交平台核查'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _box(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _reasons[item['reasonType']] ?? '咨询售后',
                    style: AppTextStyles.titleSmall,
                  ),
                ),
                Text(
                  _statusText(item['status']?.toString()),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _statusColor(item['status']?.toString()),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              Text('售后单 ${item['disputeNo'] ?? ''}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint)),
              const SizedBox(height: 9),
              Text(item['reason']?.toString() ?? ''),
              if ((item['handlerRemark']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '平台回复：${item['handlerRemark']}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (item['viewerIsApplicant'] == true &&
                  item['status'] == 'need_info')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed:
                          _acting ? null : () => _action(item, 'supplement'),
                    child: const Text('补充资料'),
                  ),
                )
              else if (item['viewerIsApplicant'] == true &&
                  item['status'] == 'pending')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _acting ? null : () => _action(item, 'cancel'),
                    child: const Text('撤销申请'),
                  ),
                ),
            ]),
          ),
        ),
      );

  Widget _box({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: child,
      );

  String _statusText(String? status) => switch (status) {
        'pending' => '待受理',
        'reviewing' => '核查中',
        'need_info' => '待补充',
        'pending_refund' => '退款复核中',
        'resolved' => '已处理',
        'rejected' => '未通过',
        'refunded' => '已退款',
        'cancelled' => '已撤销',
        _ => '处理中',
      };

  Color _statusColor(String? status) =>
      ['resolved', 'refunded'].contains(status)
          ? AppColors.success
          : ['rejected', 'cancelled'].contains(status)
              ? AppColors.textHint
              : const Color(0xFF8D621E);
}
