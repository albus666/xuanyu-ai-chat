import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../profile/recharge_page.dart';
import 'virtual_gift_media.dart';
import 'virtual_gift_intent.dart';

export 'virtual_gift_effect.dart';
export 'virtual_gift_media.dart';

class VirtualGiftTarget {
  const VirtualGiftTarget({
    required this.userId,
    required this.nickname,
    this.roomId,
    this.conversationId,
  });

  final int userId;
  final String nickname;
  final int? roomId;
  final int? conversationId;
}

Future<Map<String, dynamic>?> showVirtualGiftSheet(
  BuildContext context, {
  required List<VirtualGiftTarget> targets,
  int initialTargetIndex = 0,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VirtualGiftSheet(
      targets: targets,
      initialTargetIndex: initialTargetIndex,
    ),
  );
}

class _VirtualGiftSheet extends StatefulWidget {
  const _VirtualGiftSheet({
    required this.targets,
    required this.initialTargetIndex,
  });

  final List<VirtualGiftTarget> targets;
  final int initialTargetIndex;

  @override
  State<_VirtualGiftSheet> createState() => _VirtualGiftSheetState();
}

class _VirtualGiftSheetState extends State<_VirtualGiftSheet> {
  final _session = ApiSessionScope();
  final _gifts = <Map<String, dynamic>>[];
  final _quantityController = TextEditingController(text: '1');
  int _targetIndex = 0;
  int _giftIndex = 0;
  int _quantity = 1;
  double _balance = 0;
  bool _loading = true;
  bool _sending = false;
  bool _posting = false;
  String? _loadError;
  String? _sendError;
  VirtualGiftIntentStore? _intentStore;
  VirtualGiftIntent? _pending;
  bool get _current =>
      mounted && _session.current && (_intentStore?.current ?? true);
  bool get _locked => _sending || _pending != null || !_current;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _targetIndex = widget.initialTargetIndex.clamp(
      0,
      math.max(0, widget.targets.length - 1),
    );
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _quantityController.dispose();
    super.dispose();
  }

  void _setQuantity(int value) {
    if (_locked) return;
    final normalized = normalizeVirtualGiftQuantity(value);
    setState(() => _quantity = normalized);
    _quantityController.value = TextEditingValue(
      text: '$normalized',
      selection: TextSelection.collapsed(offset: '$normalized'.length),
    );
  }

  Future<void> _load() async {
    if (!_current) return;
    var pendingLoaded = false;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (widget.targets.isEmpty) throw StateError('当前没有可赠送的对象');
      final first = widget.targets.first;
      _intentStore ??= await VirtualGiftIntentStore.open(
          session: _session,
          roomId: first.roomId,
          conversationId: first.conversationId);
      final pending = _intentStore!.read();
      pendingLoaded = true;
      if (!_current) return;
      setState(() {
        _pending = pending;
      });
      final response = await _session.get('/api/virtual/catalog',
          queryParameters: const {'avatarPageSize': 12});
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      if (body is! Map ||
          body['code'] != 0 ||
          data is! Map ||
          data['gifts'] is! List) {
        throw StateError('礼物加载失败，请重试');
      }
      final balance = double.tryParse('${data['balance']}');
      final catalog = (data['gifts'] as List).whereType<Map>().toList();
      if (balance == null ||
          !balance.isFinite ||
          balance < 0 ||
          catalog.length != (data['gifts'] as List).length ||
          catalog.any((gift) {
            final price = double.tryParse('${gift['price']}');
            return '${gift['code'] ?? ''}'.isEmpty ||
                price == null ||
                !price.isFinite ||
                price < 0;
          })) {
        throw const FormatException('Invalid gift catalog');
      }
      if (_current) {
        final list = data['gifts'];
        setState(() {
          _balance = balance;
          _gifts
            ..clear()
            ..addAll(list is List
                ? list.whereType<Map>().map(Map<String, dynamic>.from)
                : const <Map<String, dynamic>>[]);
          _giftIndex = _giftIndex.clamp(0, math.max(0, _gifts.length - 1));
          _loading = false;
          if (pending != null) {
            final index =
                _gifts.indexWhere((g) => g['code'] == pending.giftCode);
            if (index >= 0) _giftIndex = index;
            final target = widget.targets
                .indexWhere((t) => t.userId == pending.receiverId);
            if (target >= 0) _targetIndex = target;
            _quantity = pending.quantity;
            _quantityController.text = '${pending.quantity}';
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current) return;
          for (final gift in _gifts.take(6)) {
            final url = virtualGiftMediaUrl(gift, thumbnail: true);
            if (url.isNotEmpty) {
              precacheImage(NetworkImage(url), context, onError: (_, __) {});
            }
          }
        });
      }
    } catch (error) {
      if (_current) {
        setState(() {
          _loading = false;
          _loadError = error is FormatException && !pendingLoaded
              ? '上次赠送记录暂时无法读取，请勿重复赠送，请联系客服核对'
              : apiSessionFailureMessage(error, '礼物加载失败，请重试');
        });
      }
    }
  }

  Future<void> _send() async {
    if (!_current ||
        _sending ||
        _loading ||
        (_pending == null && (_loadError != null || _gifts.isEmpty)) ||
        widget.targets.isEmpty ||
        _intentStore == null) {
      return;
    }
    // Lock before any await, including recharge.
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      if (_pending == null) {
        _quantity = normalizeVirtualGiftQuantity(
            int.tryParse(_quantityController.text));
        _quantityController.text = '$_quantity';
        final gift = _gifts[_giftIndex];
        final target = widget.targets[_targetIndex];
        final price = double.tryParse(gift['price']?.toString() ?? '') ?? 0;
        final total = price * _quantity;
        if (_balance + .0001 < total) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RechargePage()),
          );
          if (_current) await _load();
          return;
        }
        if (!_current) return;
        final intent = VirtualGiftIntent.create(
            giftCode: '${gift['code']}',
            giftName: '${gift['name'] ?? '礼物'}',
            receiverId: target.userId,
            receiverName: target.nickname,
            quantity: _quantity,
            total: total,
            roomId: target.roomId,
            conversationId: target.conversationId);
        setState(() => _pending = intent);
      }
      final intent = _pending!;
      // SharedPreferences updates its memory cache before disk persistence.
      // Re-save even a restored pending intent: a prior failed disk write
      // must never become an apparently durable request after reopening.
      await _intentStore!.save(intent);
      if (!_current) return;
      setState(() => _posting = true);
      final response =
          await _session.post('/api/virtual/gifts/send', data: intent.request);
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      if (body is! Map ||
          body['code'] != 0 ||
          data is! Map ||
          !intent.matchesReceipt(data)) {
        throw StateError('赠送结果尚未确认');
      }
      if (_current) {
        await _intentStore!.resolve(intent);
        if (!mounted || !_current) return;
        final result = Map<String, dynamic>.from(data);
        result['receiverUserId'] ??= intent.receiverId;
        result['receiverName'] ??= intent.receiverName;
        Navigator.pop(context, result);
      }
    } catch (error) {
      if (!_current) return;
      final status = error is DioException ? error.response?.statusCode : null;
      final body = error is DioException ? error.response?.data : null;
      final priceChanged = status == 409 &&
          body is Map &&
          body['data'] is Map &&
          body['data']['reason'] == 'price_changed' &&
          body['data']['notCharged'] == true;
      // Known validation/permission/balance failures have not charged this
      // request. Timeouts, server errors and invalid responses stay pending.
      if (_pending != null &&
          (const [400, 402, 403, 404].contains(status) || priceChanged)) {
        try {
          await _intentStore!.resolve(_pending!);
          if (_current) setState(() => _pending = null);
        } catch (_) {/* Keep the durable intent until it can be resolved. */}
      }
      if (!_current) return;
      setState(() => _sendError = _pending != null
          ? '暂未收到发送结果，请重试发送。'
          : apiSessionFailureMessage(error, '赠送未完成，请稍后重试'));
      if (priceChanged && _pending == null) await _load();
    } finally {
      if (_current) {
        setState(() {
          _sending = false;
          _posting = false;
        });
      }
    }
  }

  void _onSessionChanged() {
    if (!mounted || _session.current) return;
    setState(() {
      _gifts.clear();
      _balance = 0;
      _pending = null;
      _loading = false;
      _sending = false;
      _posting = false;
      _sendError = null;
      _loadError = apiSessionChangedMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final selected = _gifts.isEmpty ? null : _gifts[_giftIndex];
    final price = double.tryParse(selected?['price']?.toString() ?? '') ?? 0;
    final total = _pending?.total ?? price * _quantity;
    final sheetHeight = math.max(180.0,
        math.min((MediaQuery.sizeOf(context).height - bottom) * .92, 690.0));
    final contentHeight = math.max(
        sheetHeight,
        540.0 +
            (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) * 180 +
            (_sendError == null ? 0 : 90));
    return Container(
      height: sheetHeight,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFEFE), Color(0xFFF4F8F8)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
          child: SizedBox(
              height: contentHeight,
              child: Column(children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD3DDDC),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 7),
                  child: Row(children: [
                    Expanded(
                        child: Text('送一份心意',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMedium)),
                    const Icon(Icons.auto_awesome_rounded,
                        size: 15, color: Color(0xFFC6A55B)),
                    const SizedBox(width: 4),
                    Text(_balance.toStringAsFixed(2),
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700)),
                    TextButton(
                      onPressed: _locked
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const RechargePage()),
                              );
                              if (_current) await _load();
                            },
                      child: const Text('充值'),
                    ),
                  ]),
                ),
                if (widget.targets.length == 1 && _current)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 5),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('送给 ${widget.targets.first.nickname}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)))),
                if (widget.targets.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.targets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final isSelected = index == _targetIndex;
                        return ChoiceChip(
                          selected: isSelected,
                          label: Text(widget.targets[index].nickname),
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _targetIndex = index),
                          selectedColor: const Color(0xFFDDF7F3),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.divider,
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _loadError != null || _gifts.isEmpty
                          ? _GiftEmptyState(
                              message: _loadError,
                              onRetry: _current ? _load : null)
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    MediaQuery.sizeOf(context).width < 380 ||
                                            MediaQuery.textScalerOf(context)
                                                    .scale(1) >
                                                1.3
                                        ? 3
                                        : 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: .72,
                              ),
                              itemCount: _gifts.length,
                              itemBuilder: (_, index) {
                                final gift = _gifts[index];
                                return _GiftTile(
                                  gift: gift,
                                  selected: index == _giftIndex,
                                  onTap: () {
                                    if (!_current || _sending) return;
                                    setState(() => _giftIndex = index);
                                    final url =
                                        virtualGiftMediaUrl(gift, effect: true);
                                    if (url.isNotEmpty) {
                                      precacheImage(NetworkImage(url), context,
                                          onError: (_, __) {});
                                    }
                                  },
                                );
                              },
                            ),
                ),
                if (selected != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE3EBE9)),
                    ),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                        selected['description']?.toString().trim().isNotEmpty ==
                                true
                            ? selected['description'].toString()
                            : '让这一刻，被温柔地记住',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF73817E), fontSize: 11),
                      )),
                    ]),
                  ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                      16, 9, 16, 10 + MediaQuery.of(context).padding.bottom),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE9EEEE))),
                  ),
                  child: Column(children: [
                    if (_pending != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '发送中：${_pending!.giftName} ×${_pending!.quantity} → ${_pending!.receiverName}',
                              style: const TextStyle(
                                  color: AppColors.primaryDark, fontSize: 12))),
                    if (_sendError != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_sendError!,
                              style: const TextStyle(
                                  color: Color(0xFFA36928), fontSize: 12))),
                    Row(children: [
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7F7),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFFE2E9E8)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            onPressed: !_locked && _quantity > 1
                                ? () => _setQuantity(_quantity - 1)
                                : null,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_rounded, size: 18),
                          ),
                          const Text('×',
                              style: TextStyle(
                                  color: Color(0xFF60706D),
                                  fontWeight: FontWeight.w700)),
                          SizedBox(
                            width: 48,
                            child: TextField(
                              enabled: !_locked,
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                if (parsed != null && parsed > 0) {
                                  setState(() => _quantity =
                                      normalizeVirtualGiftQuantity(parsed));
                                }
                              },
                              onEditingComplete: () {
                                _setQuantity(
                                    int.tryParse(_quantityController.text) ??
                                        1);
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: !_locked && _quantity < 999
                                ? () => _setQuantity(_quantity + 1)
                                : null,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_rounded, size: 18),
                          ),
                        ]),
                      ),
                      const Spacer(),
                      Flexible(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                            const Text('总花费',
                                style: TextStyle(
                                    color: Color(0xFF899692), fontSize: 10)),
                            const SizedBox(height: 2),
                            Text(
                              '${virtualGiftCoinAmount(total)}币',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ])),
                    ]),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: !_current ||
                                _loading ||
                                _sending ||
                                (_pending == null &&
                                    (selected == null || _loadError != null))
                            ? null
                            : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF18AAA8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _posting
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(_pending == null ? '赠送' : '重试发送',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _pending != null
                          ? '网络异常重试不会重复扣币'
                          : '赠送后余额 ${(math.max(0, _balance - total)).toStringAsFixed(2)}币 · 礼物不可提现或交易',
                      style: const TextStyle(
                          color: Color(0xFF98A3A1), fontSize: 9),
                    ),
                  ]),
                ),
              ]))),
    );
  }
}

class _GiftTile extends StatelessWidget {
  const _GiftTile({
    required this.gift,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> gift;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(gift['color']?.toString());
    final tier = gift['tier']?.toString() ?? 'small';
    final url = virtualGiftMediaUrl(gift, thumbnail: true);
    return Semantics(
      button: true,
      selected: selected,
      label: '${gift['name'] ?? '礼物'}，${gift['price'] ?? 0}玄遇币',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 7),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [
                    color.withValues(alpha: .17),
                    Colors.white,
                  ])
                : null,
            color: selected ? null : Colors.white.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: .72)
                  : const Color(0xFFE7EDEC),
              width: selected ? 1.4 : .8,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .14),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _GiftNetworkImage(
                  url: url,
                  fallback: gift['iconText']?.toString() ?? '礼',
                  color: color,
                ),
              ),
            ),
            Text(
              gift['name']?.toString() ?? '礼物',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (tier != 'small') ...[
                Icon(Icons.auto_awesome_rounded,
                    size: 9,
                    color: tier == 'large' ? const Color(0xFFC69D43) : color),
                const SizedBox(width: 2),
              ],
              Text('${gift['price']}币',
                  style:
                      const TextStyle(color: Color(0xFF9A7A3E), fontSize: 9.5)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _GiftEmptyState extends StatelessWidget {
  const _GiftEmptyState({required this.onRetry, this.message});
  final VoidCallback? onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.card_giftcard_rounded,
              color: Color(0xFFB9C7C5), size: 42),
          const SizedBox(height: 8),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(message ?? '暂时没有可赠送的礼物',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF74827F)))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重新加载')),
        ]),
      );
}

class _GiftNetworkImage extends StatelessWidget {
  const _GiftNetworkImage({
    required this.url,
    required this.fallback,
    required this.color,
  });

  final String url;
  final String fallback;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _GiftFallback(text: fallback, color: color);
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, syncLoaded) => AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: syncLoaded || frame != null ? 1 : 0,
        child: child,
      ),
      errorBuilder: (_, __, ___) => _GiftFallback(text: fallback, color: color),
    );
  }
}

class _GiftFallback extends StatelessWidget {
  const _GiftFallback({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              Colors.white,
              color.withValues(alpha: .25),
            ]),
          ),
          alignment: Alignment.center,
          child: Text(text.characters.take(1).toString(),
              style: TextStyle(
                  color: color, fontSize: 19, fontWeight: FontWeight.w800)),
        ),
      );
}

Color _parseColor(String? value) {
  final raw = (value ?? '').replaceAll('#', '');
  final number = int.tryParse(raw, radix: 16);
  return number == null ? AppColors.primary : Color(0xFF000000 | number);
}
