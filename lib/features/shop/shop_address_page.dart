import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'shop_common.dart';

class ShopAddressPage extends StatefulWidget {
  const ShopAddressPage({super.key, this.selectMode = false});

  final bool selectMode;

  @override
  State<ShopAddressPage> createState() => _ShopAddressPageState();
}

class _ShopAddressPageState extends State<ShopAddressPage> {
  ApiSessionScope _scope = ApiSessionScope();
  final List<Map<String, dynamic>> _items = [];
  final Set<int> _operatingIds = {};
  bool _loading = true;
  bool _creating = false;
  String? _error;
  int _loadSerial = 0;

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
    _loadSerial++;
    if (!mounted) return;
    setState(() {
      _items.clear();
      _operatingIds.clear();
      _creating = false;
      _loading = next.authenticated;
      _error = next.authenticated ? null : '请登录后查看收货地址';
    });
    if (next.authenticated) unawaited(_load());
  }

  bool _current(ApiSessionScope scope, int serial) =>
      mounted && scope.current && serial == _loadSerial;

  Future<void> _load() async {
    final scope = _scope;
    final serial = ++_loadSerial;
    if (!scope.authenticated) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请登录后查看收货地址';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = shopData(await scope.get('/api/shop/addresses'));
      final list = data?['list'];
      if (list is! List) throw const FormatException('地址返回异常');
      if (_current(scope, serial)) {
        setState(() {
          _items
            ..clear()
            ..addAll(
                list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        });
      }
    } catch (error) {
      if (_current(scope, serial)) {
        setState(() => _error = shopError(error, '地址加载失败'));
      }
    } finally {
      if (_current(scope, serial)) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? original]) async {
    final scope = _scope;
    final id = (original?['id'] as num?)?.toInt();
    if (id == null) {
      if (_creating) return;
      _creating = true;
    } else if (!_operatingIds.add(id)) {
      return;
    }
    if (mounted) setState(() {});
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddressEditor(original: original),
    );
    if (result == null || !scope.current) {
      if (mounted && scope.current) {
        setState(() {
          if (id == null) {
            _creating = false;
          } else {
            _operatingIds.remove(id);
          }
        });
      }
      return;
    }
    try {
      if (original == null) {
        await scope.post('/api/shop/addresses', data: result);
      } else {
        await scope.patch('/api/shop/addresses/${original['id']}',
            data: result);
      }
      if (scope.current) await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '地址保存失败'));
      }
    } finally {
      if (mounted && scope.current) {
        setState(() {
          if (id == null) {
            _creating = false;
          } else {
            _operatingIds.remove(id);
          }
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final scope = _scope;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地址'),
        content: const Text('确定删除这个收货地址吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !scope.current) return;
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !_operatingIds.add(id)) return;
    if (mounted) setState(() {});
    try {
      await scope.delete('/api/shop/addresses/$id');
      if (scope.current) await _load();
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '删除失败'));
      }
    } finally {
      if (mounted && scope.current) {
        setState(() => _operatingIds.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(title: Text(widget.selectMode ? '选择收货地址' : '收货地址')),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null && _items.isEmpty
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
                  child: _items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 180),
                          Center(child: Text('还没有收货地址'))
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = _items[index];
                            final operating = _operatingIds.contains(
                              (item['id'] as num?)?.toInt(),
                            );
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: widget.selectMode
                                    ? () => Navigator.pop(context, item)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Color(0xFFE7F8F5),
                                        foregroundColor: AppColors.primary,
                                        child: Icon(Icons.location_on_outlined),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(
                                                  item['recipient']
                                                          ?.toString() ??
                                                      '',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              const SizedBox(width: 8),
                                              Text(
                                                  item['mobile']?.toString() ??
                                                      '',
                                                  style: const TextStyle(
                                                      color: AppColors
                                                          .textSecondary)),
                                              if (item['isDefault'] ==
                                                  true) ...[
                                                const SizedBox(width: 8),
                                                const Text('默认',
                                                    style: TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontSize: 12)),
                                              ],
                                            ]),
                                            const SizedBox(height: 6),
                                            Text(
                                                item['fullAddress']
                                                        ?.toString() ??
                                                    '',
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.textSecondary,
                                                    height: 1.4)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        enabled: !operating,
                                        onSelected: (value) => value == 'edit'
                                            ? _edit(item)
                                            : _delete(item),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'edit', child: Text('编辑')),
                                          PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _creating ? null : () => _edit(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('新增收货地址'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }
}

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({this.original});

  final Map<String, dynamic>? original;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  late final TextEditingController _recipient;
  late final TextEditingController _mobile;
  late final TextEditingController _province;
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _detail;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    final source = widget.original ?? const <String, dynamic>{};
    _recipient = TextEditingController(text: source['recipient']?.toString());
    _mobile = TextEditingController(text: source['mobile']?.toString());
    _province = TextEditingController(text: source['province']?.toString());
    _city = TextEditingController(text: source['city']?.toString());
    _district = TextEditingController(text: source['district']?.toString());
    _detail = TextEditingController(text: source['detail']?.toString());
    _isDefault = source['isDefault'] == true;
  }

  @override
  void dispose() {
    _recipient.dispose();
    _mobile.dispose();
    _province.dispose();
    _city.dispose();
    _district.dispose();
    _detail.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label,
          {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: const Color(0xFFF7F9F8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none)),
        ),
      );

  void _save() {
    if ([_recipient, _mobile, _province, _city, _detail]
        .any((x) => x.text.trim().isEmpty)) {
      showAppToast(context, '请完整填写收货信息');
      return;
    }
    Navigator.pop(context, {
      'recipient': _recipient.text.trim(),
      'mobile': _mobile.text.trim(),
      'province': _province.text.trim(),
      'city': _city.text.trim(),
      'district': _district.text.trim(),
      'detail': _detail.text.trim(),
      'isDefault': _isDefault,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFDDE3E1),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Text(widget.original == null ? '新增收货地址' : '编辑收货地址',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            _field(_recipient, '收货人'),
            _field(_mobile, '手机号码', keyboard: TextInputType.phone),
            Row(children: [
              Expanded(child: _field(_province, '省')),
              const SizedBox(width: 8),
              Expanded(child: _field(_city, '市'))
            ]),
            _field(_district, '区/县（选填）'),
            _field(_detail, '详细地址'),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设为默认地址'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v)),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
