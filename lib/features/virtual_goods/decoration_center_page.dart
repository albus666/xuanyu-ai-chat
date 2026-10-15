import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/cache/page_snapshot_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../profile/profile_background_artwork.dart';
import '../profile/profile_background_presets.dart';
import 'virtual_avatar_studio_page.dart';

class DecorationCenterPage extends StatefulWidget {
  const DecorationCenterPage({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<DecorationCenterPage> createState() => _DecorationCenterPageState();
}

class _DecorationCenterPageState extends State<DecorationCenterPage> {
  final _scope = ApiSessionScope();
  late final _user = Map<String, dynamic>.from(widget.user);
  late String _selectedId = _user['homeBackgroundId']?.toString() ?? '';
  late String _equippedId = _selectedId;
  final _availableIds = <String>{};
  final _products = <String, Map<String, dynamic>>{};
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _showAvatars = false;
  bool _avatarOpened = false;
  bool _selectionChanged = false;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _products.clear();
      _availableIds.clear();
      _user.clear();
      _saving = false;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  void _applyCatalog(Map data) {
    _products
      ..clear()
      ..addEntries(
        (data['backgrounds'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) => MapEntry('${item['id']}', item)),
      );
    _availableIds
      ..clear()
      ..addAll(_products.keys);
    _equippedId = data['homeBackgroundId']?.toString() ?? '';
    if (!_selectionChanged) _selectedId = _equippedId;
  }

  Future<void> _load() async {
    if ((!mounted || !_scope.current)) return;
    final cache = PageSnapshotCache('decoration_center');
    setState(() {
      _loading = true;
      _failed = false;
    });
    if (_products.isEmpty) {
      final snapshot = await cache.read();
      if (!mounted || !_scope.current) return;
      if (snapshot?['backgrounds'] is List) {
        setState(() => _applyCatalog(snapshot!));
      }
    }
    try {
      final response = await _scope.get('/api/virtual/backgrounds');
      final data = (response.data as Map?)?['data'];
      if (data is! Map || data['backgrounds'] is! List) {
        throw StateError('background catalog unavailable');
      }
      if ((!mounted || !_scope.current)) return;
      setState(
        () => _applyCatalog(data),
      );
      await cache.write(Map<String, dynamic>.from(data));
    } catch (_) {
      if ((mounted && _scope.current)) setState(() => _failed = true);
    } finally {
      if ((mounted && _scope.current)) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    if ((!mounted || !_scope.current) || _saving || _loading || _failed) return;
    setState(() => _saving = true);
    try {
      final product = _products[_selectedId];
      final owned = product?['owned'] == true ||
          (double.tryParse('${product?['price']}') ?? 0) <= 0;
      if (_selectedId.isNotEmpty && !owned) {
        final purchase = await _scope.post(
          '/api/virtual/style-orders',
          data: {
            'productType': 'background',
            'backgroundId':
                product?['productId'] ?? product?['id'] ?? _selectedId,
            'mode': 'self',
            'requestKey':
                'background_${_selectedId}_${DateTime.now().microsecondsSinceEpoch}',
          },
        );
        final purchaseBody = purchase.data;
        if (purchaseBody is! Map || purchaseBody['code'] != 0) {
          throw StateError('purchase failed');
        }
        if ((!mounted || !_scope.current)) return;
        if (product != null) product['owned'] = true;
      }
      final response = await _scope.patch(
        '/api/virtual/backgrounds',
        data: {'backgroundId': _selectedId},
      );
      final body = response.data;
      if (body is! Map || body['code'] != 0) throw StateError('save failed');
      if ((!mounted || !_scope.current)) return;
      showAppToast(context, _selectedId.isEmpty ? '已恢复默认背景' : '主页背景已同步');
      Navigator.pop(context, true);
    } on DioException catch (error) {
      final body = error.response?.data;
      if ((mounted && _scope.current)) {
        showAppToast(
          context,
          body is Map ? '${body['message'] ?? '暂时无法应用，请重试'}' : '暂时无法应用，请重试',
        );
      }
    } catch (_) {
      if ((mounted && _scope.current)) showAppToast(context, '暂时无法应用，请重试');
    } finally {
      if ((mounted && _scope.current)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('装扮中心')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }
    final selected = profileBackgroundById(_selectedId);
    final items = <ProfileBackgroundPreset?>[
      null,
      ...platformProfileBackgrounds.where(
        (item) => _availableIds.contains(item.id),
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: AppBar(
        title: const Text('装扮中心'),
        backgroundColor: const Color(0xFFF4F8F7),
      ),
      body: _loading && _products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _failed && _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('装扮暂时没有加载出来'),
                      TextButton(onPressed: _load, child: const Text('重新加载')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    if (_failed)
                      TextButton(
                        onPressed: _load,
                        child: const Text('装扮状态更新失败，点击重试'),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Row(
                        children: [
                          _sectionButton(
                            label: '主页装扮',
                            icon: Icons.wallpaper_rounded,
                            selected: !_showAvatars,
                            onTap: _saving
                                ? null
                                : () => setState(() => _showAvatars = false),
                          ),
                          const SizedBox(width: 8),
                          _sectionButton(
                            label: '头像馆',
                            icon: Icons.face_retouching_natural,
                            selected: _showAvatars,
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      _avatarOpened = true;
                                      _showAvatars = true;
                                    }),
                          ),
                          const Spacer(),
                          Text(
                            _showAvatars
                                ? '圆形安全区预览'
                                : '${_availableIds.length}款主页装扮',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _showAvatars ? 1 : 0,
                        children: [
                          CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 0),
                                sliver: SliverToBoxAdapter(
                                  child: _preview(selected),
                                ),
                              ),
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 20),
                                sliver: SliverLayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns =
                                        constraints.crossAxisExtent >= 600
                                            ? 3
                                            : 2;
                                    return SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisExtent: 190,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                      ),
                                      delegate: SliverChildBuilderDelegate(
                                        (_, index) => _card(items[index]),
                                        childCount: items.length,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (_avatarOpened)
                            VirtualAvatarStudioPage(
                              initialGender: (_user['gender'] as num?)?.toInt(),
                              embedded: true,
                              onAvatarSaved: (url) =>
                                  setState(() => _user['avatarUrl'] = url),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _showAvatars
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(
                  onPressed: _saving || _loading || _failed ? null : _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _selectedId.isEmpty
                              ? '使用默认背景'
                              : '${_priceLabel(_selectedId)} · ${selected?.name ?? '主页背景'}',
                        ),
                ),
              ),
            ),
    );
  }

  Widget _sectionButton({
    required String label,
    required IconData icon,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final color = selected ? Colors.white : AppColors.primaryDark;
    return Material(
      color: selected ? AppColors.primaryDark : const Color(0xFFE4F1EE),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(ProfileBackgroundPreset? selected) {
    final ink = selected?.dark == true ? Colors.white : const Color(0xFF203E3A);
    final nickname = '${_user['nickname'] ?? '我的主页'}';
    final avatar = _user['avatarUrl']?.toString() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height < 500 ? 220 : 360,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProfileBackgroundArtwork(backgroundId: _selectedId),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, color: ink, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '主页效果预览',
                      style: TextStyle(color: ink, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFDDEDE7),
                      backgroundImage:
                          avatar.isEmpty ? null : NetworkImage(avatar),
                      child: avatar.isEmpty
                          ? const Icon(
                              Icons.person_outline,
                              color: AppColors.primaryDark,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Color(0xFF213E39),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selected?.description ?? '留一点温柔，给此刻的自己',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ProfileBackgroundPreset? item) {
    final id = item?.id ?? '';
    final selected = _selectedId == id;
    final product = _products[id];
    final price = double.tryParse('${product?['price']}') ?? 0;
    final owned = product?['owned'] == true || price <= 0;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${item?.name ?? '默认青绿'}，主页装扮，${owned ? '已拥有' : '${price.toStringAsFixed(0)}玄遇币'}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving ? null : () => setState(() {
            _selectionChanged = true;
            _selectedId = id;
          }),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFE3ECE8),
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProfileBackgroundArtwork(backgroundId: id),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 7),
                                Icon(
                                  Icons.account_circle,
                                  size: 16,
                                  color: Color(0xFF719B90),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item?.name ?? '默认青绿',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _equippedId == id &&
                          (_user['homeBackgroundUrl']?.toString() ?? '').isEmpty
                      ? '正在使用'
                      : owned
                          ? '已拥有 · 静态'
                          : '${price.toStringAsFixed(0)} 玄遇币 · 静态',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _priceLabel(String id) {
    final product = _products[id];
    final price = double.tryParse('${product?['price']}') ?? 0;
    if (price <= 0 || product?['owned'] == true) return '已拥有';
    return '${price.toStringAsFixed(0)}玄遇币购买';
  }
}
