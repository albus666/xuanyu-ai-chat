import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../profile/profile_background_artwork.dart';
import 'virtual_avatar_artwork.dart';
import 'virtual_avatar_catalog.dart';

class VirtualStyleTarget {
  const VirtualStyleTarget({
    required this.userId,
    required this.nickname,
    required this.conversationId,
  });

  final int userId;
  final String nickname;
  final int conversationId;
}

Future<Map<String, dynamic>?> showVirtualStyleOrderSheet(
  BuildContext context, {
  required VirtualStyleTarget target,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VirtualStyleOrderSheet(target: target),
  );
}

class _VirtualStyleOrderSheet extends StatefulWidget {
  const _VirtualStyleOrderSheet({required this.target});

  final VirtualStyleTarget target;

  @override
  State<_VirtualStyleOrderSheet> createState() =>
      _VirtualStyleOrderSheetState();
}

class _VirtualStyleOrderSheetState extends State<_VirtualStyleOrderSheet> {
  final _avatars = <Map<String, dynamic>>[];
  final _backgrounds = <Map<String, dynamic>>[];
  final _avatarScrollController = ScrollController();
  int _tab = 0;
  int _index = 0;
  int _avatarPage = 1;
  int _avatarTotal = 0;
  bool _avatarHasMore = false;
  bool _loadingMore = false;
  String _mode = 'gift';
  double _balance = 0;
  bool _loading = true;
  bool _sending = false;

  List<Map<String, dynamic>> get _items => _tab == 0 ? _avatars : _backgrounds;

  Map<String, dynamic>? get _selected => _items.isEmpty
      ? null
      : _items[_index.clamp(0, _items.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _avatarScrollController.addListener(_handleAvatarScroll);
    _load();
  }

  @override
  void dispose() {
    _avatarScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get(
        '/api/virtual/catalog',
        queryParameters: const {'avatarPage': 1, 'avatarPageSize': 32},
      );
      final data = (response.data as Map?)?['data'];
      if (data is! Map || !mounted) return;
      setState(() {
        _balance = double.tryParse('${data['balance']}') ?? 0;
        _avatars
          ..clear()
          ..addAll(
            (data['avatars'] as List? ?? const []).whereType<Map>().map(
                  (item) => Map<String, dynamic>.from(item),
                ),
          );
        _backgrounds
          ..clear()
          ..addAll(
            (data['backgrounds'] as List? ?? const []).whereType<Map>().map(
                  (item) => Map<String, dynamic>.from(item),
                ),
          );
        _index = 0;
        final pageInfo = data['avatarPageInfo'];
        if (pageInfo is Map) {
          _avatarPage = (pageInfo['page'] as num?)?.toInt() ?? 1;
          _avatarTotal =
              (pageInfo['total'] as num?)?.toInt() ?? _avatars.length;
          _avatarHasMore = pageInfo['hasMore'] == true;
        } else {
          _avatarTotal = _avatars.length;
          _avatarHasMore = false;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAvatarScroll() {
    if (_tab != 0 ||
        !_avatarScrollController.hasClients ||
        _loadingMore ||
        !_avatarHasMore ||
        _avatarScrollController.position.extentAfter > 420) {
      return;
    }
    _loadMoreAvatars();
  }

  Future<void> _loadMoreAvatars() async {
    if (_loadingMore || !_avatarHasMore) return;
    setState(() => _loadingMore = true);
    try {
      final response = await apiClient.get(
        '/api/virtual/catalog',
        queryParameters: {'avatarPage': _avatarPage + 1, 'avatarPageSize': 32},
      );
      final data = (response.data as Map?)?['data'];
      if (!mounted) return;
      if (data is! Map) {
        setState(() {
          _avatarHasMore = false;
          _loadingMore = false;
        });
        return;
      }
      final more = (data['avatars'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          );
      final pageInfo = data['avatarPageInfo'];
      setState(() {
        _avatars.addAll(more);
        if (pageInfo is Map) {
          _avatarPage = (pageInfo['page'] as num?)?.toInt() ?? _avatarPage + 1;
          _avatarTotal = (pageInfo['total'] as num?)?.toInt() ?? _avatarTotal;
          _avatarHasMore = pageInfo['hasMore'] == true;
        } else {
          _avatarHasMore = false;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _submit() async {
    final product = _selected;
    if (_sending || product == null) return;
    setState(() => _sending = true);
    try {
      final isAvatar = _tab == 0;
      final response = await apiClient.post(
        '/api/virtual/style-orders',
        data: {
          'productType': isAvatar ? 'avatar' : 'background',
          if (isAvatar) 'productId': product['id'],
          if (!isAvatar) 'backgroundId': product['productId'] ?? product['id'],
          'receiverUserId': widget.target.userId,
          'conversationId': widget.target.conversationId,
          'mode': _mode,
          'requestKey':
              'style_${DateTime.now().microsecondsSinceEpoch}_${widget.target.userId}',
        },
      );
      final body = response.data;
      if (body is! Map || body['code'] != 0) {
        throw StateError(body is Map ? '${body['message'] ?? '提交失败'}' : '提交失败');
      }
      if (!mounted) return;
      final result = Map<String, dynamic>.from((body['data'] as Map?) ?? {});
      result['productName'] = product['name']?.toString() ?? '装扮';
      result['receiverName'] = widget.target.nickname;
      Navigator.pop(context, result);
    } on DioException catch (error) {
      final body = error.response?.data;
      if (mounted) {
        showAppToast(
          context,
          body is Map ? '${body['message'] ?? '提交失败，请稍后重试'}' : '提交失败，请稍后重试',
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final product = _selected;
    final price = double.tryParse('${product?['price']}') ?? 0;
    final owned = product?['owned'] == true || price <= 0;
    return Container(
      height: math.min(MediaQuery.sizeOf(context).height * .86, 650),
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FCFB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD2DDDA),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '给 ${widget.target.nickname} 一份装扮',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium,
                  ),
                ),
                Text(
                  '${_balance.toStringAsFixed(0)} 玄遇币',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            child: Row(
              children: [
                _tabButton(_avatarTotal > 0 ? '头像 $_avatarTotal' : '头像', 0),
                const SizedBox(width: 8),
                _tabButton(
                  _backgrounds.isNotEmpty
                      ? '主页装扮 ${_backgrounds.length}'
                      : '主页装扮',
                  1,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('暂时没有可用装扮'))
                    : GridView.builder(
                        controller: _tab == 0 ? _avatarScrollController : null,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: .78,
                        ),
                        itemCount:
                            _items.length + (_tab == 0 && _loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _items.length) {
                            return const Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          return _productCard(_items[i], i);
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _modeButton('gift', '我来赠送', Icons.redeem_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _modeButton(
                        'request',
                        '发给 TA 付款',
                        Icons.receipt_long_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sending || product == null ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: _sending
                        ? const SizedBox.square(
                            dimension: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            owned
                                ? (_mode == 'request'
                                    ? '发起人已拥有'
                                    : '已拥有，可直接发送请求')
                                : '${price.toStringAsFixed(0)} 玄遇币 · ${_mode == 'gift' ? '送给 TA' : '请 TA 付款'}',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int value) {
    final selected = _tab == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _tab = value;
          _index = 0;
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDark : const Color(0xFFE6F1EE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.primaryDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product, int index) {
    final selected = index == _index;
    final price = double.tryParse('${product['price']}') ?? 0;
    return InkWell(
      onTap: () => setState(() => _index = index),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE0EBE7),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: _buildProductArtwork(product),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product['name']?.toString() ?? '装扮',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              price <= 0 ? '免费' : '${price.toStringAsFixed(0)}币',
              style: TextStyle(
                fontSize: 10,
                color: product['owned'] == true || price <= 0
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductArtwork(Map<String, dynamic> product) {
    if (_tab == 0) {
      final rawConfig = product['config'];
      final config = rawConfig is Map
          ? Map<String, dynamic>.from(rawConfig)
          : VirtualAvatarCatalog.initialConfig();
      return VirtualAvatarArtwork(config: config, thumbnail: true);
    }
    return ProfileBackgroundArtwork(
      backgroundId: product['code']?.toString(),
      fit: BoxFit.cover,
    );
  }

  Widget _modeButton(String value, String label, IconData icon) {
    final selected = _mode == value;
    return InkWell(
      onTap: () => setState(() => _mode = value),
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2ED) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE1E9E6),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryDark),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
