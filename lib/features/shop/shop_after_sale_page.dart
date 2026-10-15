import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_common.dart';

class ShopAfterSalePage extends StatefulWidget {
  const ShopAfterSalePage({super.key, this.order});
  final Map<String, dynamic>? order;

  @override
  State<ShopAfterSalePage> createState() => _ShopAfterSalePageState();
}

class _ShopAfterSalePageState extends State<ShopAfterSalePage> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  ApiSessionScope _scope = ApiSessionScope();
  final Set<int> _operatingIds = {};
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _load();
    if (widget.order != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _apply(widget.order!),
      );
    }
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    _scope = ApiSessionScope();
    _loadSerial++;
    setState(() {
      _items.clear();
      _operatingIds.clear();
      _loading = _scope.authenticated;
    });
    if (_scope.authenticated) _load();
  }

  Future<void> _load() async {
    final scope = _scope;
    final serial = ++_loadSerial;
    bool current() => mounted && scope.current && serial == _loadSerial;
    try {
      final list =
          shopData(await scope.get('/api/shop/after-sales'))?['list']
              as List? ??
          [];
      if (current()) {
        setState(() {
          _items
            ..clear()
            ..addAll(
              list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        });
      }
    } catch (error) {
      if (mounted && current()) {
        showAppToast(context, shopError(error, '售后记录加载失败'));
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> order) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AfterSaleEditor(order: order),
    );
    if (ok == true) _load();
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    final scope = _scope;
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !_operatingIds.add(id)) return;
    setState(() {});
    try {
      await scope.post('/api/shop/after-sales/$id/cancel');
      if (!mounted || !scope.current) return;
      showAppToast(context, '售后申请已取消');
      await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '取消失败'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _operatingIds.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final scope = _scope;
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !_operatingIds.add(id)) return;
    setState(() {});
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除售后记录'),
          content: const Text('删除后不再显示这条记录，订单及售后处理凭据仍会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !scope.current) return;
      await scope.delete('/api/shop/after-sales/$id');
      if (!mounted || !scope.current) return;
      _loadSerial++;
      setState(() {
        _items.removeWhere((row) => row['id'] == id);
        _loading = false;
      });
      showAppToast(context, '售后记录已删除');
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '删除失败，请稍后重试'));
      }
    } finally {
      if (mounted && scope.current) setState(() => _operatingIds.remove(id));
    }
  }

  bool _canDelete(Map<String, dynamic> item) =>
      item['canDelete'] == true ||
      (item['canDelete'] == null &&
          const [
            'rejected',
            'cancelled',
            'completed',
          ].contains(item['status']));

  String _typeLabel(String? value) =>
      const {'refund': '仅退款', 'return': '退货退款', 'replace': '换货/补发'}[value] ??
      '';
  String _statusLabel(String? value) =>
      const {
        'pending': '待处理',
        'approved': '已同意',
        'rejected': '未同意',
        'completed': '已完成',
        'cancelled': '已取消'
      }[value] ??
      '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(title: const Text('退款与售后')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 180),
                      Center(child: Text('暂无售后申请'))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        final operating = _operatingIds.contains(item['id']);
                        return Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          '${_typeLabel(item['type']?.toString())} · ${item['orderNo']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700))),
                                  Text(_statusLabel(item['status']?.toString()),
                                      style: const TextStyle(
                                          color: AppColors.primary)),
                                ]),
                                const SizedBox(height: 8),
                                Text(item['reason']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                                if ((item['adminRemark']?.toString() ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('处理说明：${item['adminRemark']}',
                                      style: const TextStyle(
                                          color: Color(0xFFC2683B),
                                          fontSize: 12)),
                                ],
                                if (_canDelete(item)) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: operating
                                          ? null
                                          : () => _delete(item),
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                      label: const Text('删除记录'),
                                    ),
                                  ),
                                ],
                                if (item['status'] == 'pending') ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: operating
                                          ? null
                                          : () => _cancel(item),
                                      child: const Text('取消申请'),
                                    ),
                                  ),
                                ],
                              ]),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AfterSaleEditor extends StatefulWidget {
  const _AfterSaleEditor({required this.order});
  final Map<String, dynamic> order;
  @override
  State<_AfterSaleEditor> createState() => _AfterSaleEditorState();
}

class _AfterSaleEditorState extends State<_AfterSaleEditor> {
  String _type = 'return';
  final _reason = TextEditingController();
  final List<XFile> _files = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.order['source'] == 'goodwill' &&
        shopPrice(widget.order['payAmount']) == 0) {
      _type = 'replace';
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<String> _upload(XFile file) async {
    return uploadPrivateShopEvidence(file);
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      showAppToast(context, '请填写售后原因');
      return;
    }
    setState(() => _submitting = true);
    try {
      final urls = <String>[];
      for (final file in _files) {
        urls.add(await _upload(file));
      }
      await apiClient.post('/api/shop/after-sales', data: {
        'orderId': widget.order['id'],
        'type': _type,
        'reason': _reason.text.trim(),
        'evidenceUrls': urls
      });
      if (mounted) {
        showAppToast(context, '售后申请已提交');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) showAppToast(context, shopError(error, '提交失败'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goodwillFree = widget.order['source'] == 'goodwill' &&
        shopPrice(widget.order['payAmount']) == 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 16, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Center(
                child: Text('申请退款/售后',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            const SizedBox(height: 18),
            Wrap(spacing: 8, children: [
              if (!goodwillFree)
                ChoiceChip(
                    label: const Text('仅退款'),
                    selected: _type == 'refund',
                    onSelected: (_) => setState(() => _type = 'refund')),
              if (!goodwillFree)
                ChoiceChip(
                    label: const Text('退货退款'),
                    selected: _type == 'return',
                    onSelected: (_) => setState(() => _type = 'return')),
              ChoiceChip(
                  label: const Text('换货/补发'),
                  selected: _type == 'replace',
                  onSelected: (_) => setState(() => _type = 'replace')),
            ]),
            const SizedBox(height: 14),
            TextField(
                controller: _reason,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                    labelText: '售后原因',
                    hintText: '请说明商品问题和你的处理诉求',
                    filled: true,
                    fillColor: const Color(0xFFF7F9F8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._files.asMap().entries.map((entry) => Stack(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(entry.value.path),
                            width: 76, height: 76, fit: BoxFit.cover)),
                    Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                            onTap: () =>
                                setState(() => _files.removeAt(entry.key)),
                            child: const CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    size: 12, color: Colors.white)))),
                  ])),
              if (_files.length < 6)
                InkWell(
                    onTap: () async {
                      final list = await ImagePicker()
                          .pickMultiImage(imageQuality: 85, maxWidth: 1600);
                      if (mounted) {
                        setState(
                            () => _files.addAll(list.take(6 - _files.length)));
                      }
                    },
                    child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                            color: const Color(0xFFF7F9F8),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.add_photo_alternate_outlined,
                            color: AppColors.primary))),
            ]),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('提交申请')),
          ])),
    );
  }
}
