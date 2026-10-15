import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/cache/page_snapshot_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/network/media_review.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../profile/recharge_page.dart';
import 'virtual_avatar_artwork.dart';
import 'virtual_avatar_catalog.dart';
import 'virtual_avatar_spec.dart';

class VirtualAvatarStudioPage extends StatefulWidget {
  const VirtualAvatarStudioPage({
    super.key,
    this.initialGender,
    this.embedded = false,
    this.onAvatarSaved,
  });

  final int? initialGender;
  final bool embedded;
  final ValueChanged<String>? onAvatarSaved;

  @override
  State<VirtualAvatarStudioPage> createState() =>
      _VirtualAvatarStudioPageState();
}

class _VirtualAvatarStudioPageState extends State<VirtualAvatarStudioPage>
    with SingleTickerProviderStateMixin {
  final _scope = ApiSessionScope();
  late final TabController _tabController =
      TabController(length: 2, vsync: this);
  final _presets = <Map<String, dynamic>>[];
  final _entryEffects = <Map<String, dynamic>>[];
  final _galleryScrollController = ScrollController();
  final _styleCategories = <String, String>{
    'all': '全部',
    ...VirtualAvatarCatalog.styleNames,
  };
  late Map<String, dynamic> _config;
  int? _productId;
  int? _equippedEntryEffectId;
  String _selectedStyle = 'all';
  double _balance = 0;
  bool _loading = true;
  bool _catalogFresh = false;
  bool _previewChanged = false;
  bool _loadingMore = false;
  bool _avatarHasMore = false;
  int _avatarPage = 1;
  int _catalogQueryId = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _config = VirtualAvatarSpec.defaults(widget.initialGender);
    _replaceProducts(const []);
    _galleryScrollController.addListener(_handleGalleryScroll);
    _load();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _presets.clear();
      _entryEffects.clear();
      _balance = 0;
      _config = VirtualAvatarSpec.defaults(widget.initialGender);
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _tabController.dispose();
    _galleryScrollController.dispose();
    super.dispose();
  }

  Future<Map<dynamic, dynamic>?> _loadData(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _scope.get(
        path,
        queryParameters: queryParameters,
      );
      final data = (response.data as Map?)?['data'];
      return data is Map ? data : null;
    } catch (_) {
      return null;
    }
  }

  void _applyCatalog(Map<dynamic, dynamic> catalog, {required bool fresh}) {
    if (fresh) {
      _balance = double.tryParse('${catalog['balance'] ?? 0}') ?? 0;
      _catalogFresh = true;
    }
    _applyCatalogMeta(catalog);
    _replaceProducts([
      ...(catalog['avatars'] as List? ?? const []).whereType<Map>().map(
            Map<String, dynamic>.from,
          ),
      ...(catalog['ownedAvatars'] as List? ?? const []).whereType<Map>().map(
            Map<String, dynamic>.from,
          ),
    ]);
    _entryEffects
      ..clear()
      ..addAll(
        (catalog['entryEffects'] as List? ?? const []).whereType<Map>().map(
              Map<String, dynamic>.from,
            ),
      );
    _productId = _productIdForConfig(_config);
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    final query = ++_catalogQueryId;
    final cache = PageSnapshotCache('avatar_studio_catalog');
    setState(() {
      _loading = true;
      _loadingMore = false;
      _catalogFresh = false;
    });
    // Profile and catalog update separately: neither delays the visible gallery.
    Future<void> loadProfile() async {
      final profile = await _loadData('/api/virtual/profile');
      if (!mounted || !_scope.current || profile == null) return;
      setState(() {
        if (!_saving && !_previewChanged && profile['config'] is Map) {
          _config = VirtualAvatarSpec.normalize(
            profile['config'] as Map,
            gender: widget.initialGender,
          );
          _productId = _productIdForConfig(_config);
        }
        _equippedEntryEffectId = (profile['entryEffectId'] as num?)?.toInt();
      });
    }

    Future<void> loadCatalog() async {
      final snapshot = await cache.read();
      if (!mounted || !_scope.current || query != _catalogQueryId) return;
      if (snapshot != null) {
        setState(() => _applyCatalog(snapshot, fresh: false));
      }
      final catalog = await _loadData(
        '/api/virtual/catalog',
        queryParameters: const {'avatarPage': 1, 'avatarPageSize': 48},
      );
      if (!mounted || !_scope.current || query != _catalogQueryId) return;
      setState(() {
        if (catalog != null) _applyCatalog(catalog, fresh: true);
        _loading = false;
      });
      if (catalog != null) {
        final display = Map<String, dynamic>.from(catalog)..remove('balance');
        await cache.write(display);
      }
    }

    await Future.wait([loadProfile(), loadCatalog()]);
  }

  void _replaceProducts(Iterable<Map<String, dynamic>> serverProducts) {
    final byAsset = <String, Map<String, dynamic>>{};
    for (final item in VirtualAvatarCatalog.builtInFreeProducts) {
      final asset = (item['config'] as Map?)?['assetCode']?.toString();
      if (asset != null) byAsset[asset] = item;
    }
    for (final item in serverProducts) {
      if (item['productType'] != 'finished') continue;
      final config = item['config'];
      final asset = config is Map ? config['assetCode']?.toString() : null;
      if (asset == null ||
          config is! Map ||
          !VirtualAvatarCatalog.hasArtwork(config)) {
        continue;
      }
      byAsset[asset] = item;
    }
    _presets
      ..clear()
      ..addAll(byAsset.values);
  }

  void _appendProducts(Iterable<Map<String, dynamic>> serverProducts) {
    final existing = <String, Map<String, dynamic>>{
      for (final item in _presets)
        if ((item['config'] as Map?)?['assetCode'] != null)
          (item['config'] as Map)['assetCode'].toString(): item,
    };
    for (final item in serverProducts) {
      final config = item['config'];
      if (item['productType'] != 'finished' ||
          config is! Map ||
          !VirtualAvatarCatalog.hasArtwork(config)) {
        continue;
      }
      final code = config['assetCode']?.toString();
      if (code != null && code.isNotEmpty) existing[code] = item;
    }
    _presets
      ..clear()
      ..addAll(existing.values);
  }

  void _applyCatalogMeta(Map<dynamic, dynamic> catalog) {
    final pageInfo = catalog['avatarPageInfo'];
    if (pageInfo is Map) {
      _avatarPage = (pageInfo['page'] as num?)?.toInt() ?? 1;
      _avatarHasMore = pageInfo['hasMore'] == true;
    }
    final spec = catalog['avatarRenderSpec'];
    final categories = spec is Map ? spec['styleCategories'] : null;
    if (categories is List) {
      for (final raw in categories.whereType<Map>()) {
        final code = raw['code']?.toString() ?? '';
        final name = raw['name']?.toString() ?? '';
        if (code.isNotEmpty && name.isNotEmpty) _styleCategories[code] = name;
      }
    }
  }

  void _handleGalleryScroll() {
    if (!_galleryScrollController.hasClients ||
        _loadingMore ||
        !_avatarHasMore ||
        _galleryScrollController.position.extentAfter > 360) {
      return;
    }
    _loadMoreAvatars();
  }

  Future<void> _loadMoreAvatars() async {
    if ((!mounted || !_scope.current) ||
        _loading ||
        _loadingMore ||
        !_avatarHasMore) {
      return;
    }
    final queryId = _catalogQueryId;
    final style = _selectedStyle;
    setState(() => _loadingMore = true);
    final catalog = await _loadData(
      '/api/virtual/catalog',
      queryParameters: {
        'avatarPage': _avatarPage + 1,
        'avatarPageSize': 48,
        if (style != 'all') 'avatarCategory': style,
      },
    );
    if ((!mounted || !_scope.current) ||
        queryId != _catalogQueryId ||
        style != _selectedStyle) {
      return;
    }
    setState(() {
      if (catalog != null) {
        _applyCatalogMeta(catalog);
        _appendProducts((catalog['avatars'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from));
      } else {
        _avatarHasMore = false;
      }
      _loadingMore = false;
    });
  }

  Future<void> _changeStyle(String style) async {
    if ((!mounted || !_scope.current) ||
        _loading ||
        _saving ||
        _selectedStyle == style) {
      return;
    }
    final queryId = ++_catalogQueryId;
    setState(() {
      _selectedStyle = style;
      _loadingMore = true;
    });
    if (_galleryScrollController.hasClients) {
      _galleryScrollController.jumpTo(0);
    }
    final catalog = await _loadData(
      '/api/virtual/catalog',
      queryParameters: {
        'avatarPage': 1,
        'avatarPageSize': 48,
        if (style != 'all') 'avatarCategory': style,
      },
    );
    if ((!mounted || !_scope.current) || queryId != _catalogQueryId) return;
    setState(() {
      if (catalog != null) {
        _applyCatalogMeta(catalog);
        _replaceProducts([
          ...(catalog['avatars'] as List? ?? const [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from),
          ...(catalog['ownedAvatars'] as List? ?? const [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from),
        ]);
      } else {
        _avatarHasMore = false;
      }
      _loadingMore = false;
    });
  }

  int? _productIdForConfig(Map<String, dynamic> config) {
    final assetCode = config['assetCode']?.toString();
    for (final preset in _presets) {
      final presetConfig = preset['config'];
      if (presetConfig is! Map || presetConfig['assetCode'] != assetCode) {
        continue;
      }
      final id = (preset['id'] as num?)?.toInt();
      return id != null && id > 0 ? id : null;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedProduct {
    final assetCode = _config['assetCode']?.toString();
    for (final item in _presets) {
      final config = item['config'];
      if (config is Map && config['assetCode'] == assetCode) return item;
    }
    return null;
  }

  void _selectConfig(Map<String, dynamic> next, {int? productId}) {
    if (_saving) return;
    setState(() {
      _previewChanged = true;
      _config = VirtualAvatarSpec.normalize(
        next,
        gender: widget.initialGender,
      );
      _productId = productId != null && productId > 0 ? productId : null;
    });
  }

  Future<void> _selectPreset(Map<String, dynamic> preset) async {
    if (preset['config'] is Map) {
      _selectConfig(
        Map<String, dynamic>.from(preset['config'] as Map),
        productId: (preset['id'] as num?)?.toInt(),
      );
    }
  }

  bool _needsPurchase(Map<String, dynamic>? product) {
    if (product == null || product['owned'] == true) return false;
    return (double.tryParse('${product['price'] ?? 0}') ?? 0) > 0;
  }

  Future<bool> _ensureSelectedOwned() async {
    if ((!mounted || !_scope.current)) return false;
    final preset = _selectedProduct;
    if (!_needsPurchase(preset)) return true;
    final price = double.tryParse('${preset!['price'] ?? 0}') ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('购买并使用「${preset['name']}」'),
        content: Text(
          '作者：${preset['creatorName'] ?? '玄遇设计所'}\n'
          '价格：${price.toStringAsFixed(0)}玄遇币\n\n'
          '试戴完全免费，确认后才会扣币；购买一次即可永久使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续看看'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认购买'),
          ),
        ],
      ),
    );
    if (confirmed != true || (!mounted || !_scope.current)) return false;
    if (_balance + .0001 < price) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RechargePage()),
      );
      final catalog = await _loadData(
        '/api/virtual/catalog',
        queryParameters: const {'avatarPage': 1, 'avatarPageSize': 48},
      );
      if ((mounted && _scope.current) && catalog != null) {
        setState(() {
          _balance = double.tryParse('${catalog['balance'] ?? 0}') ?? _balance;
        });
      }
      return false;
    }
    try {
      final response = await _scope.post(
        '/api/virtual/avatar/purchase',
        data: {'productId': preset['id']},
      );
      if ((!mounted || !_scope.current)) return false;
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      if (body is! Map ||
          body['code'] != 0 ||
          data is! Map ||
          data['owned'] != true) {
        throw FormatException(body is Map
            ? body['message']?.toString() ?? '购买结果尚未确认，请重试'
            : '购买结果尚未确认，请重试');
      }
      setState(() {
        preset['owned'] = true;
        _balance = double.tryParse('${data['balance']}') ??
            (_balance - (double.tryParse('${data['charged']}') ?? 0));
      });
      return true;
    } on ApiSessionChangedException {
      return false;
    } on FormatException catch (error) {
      if (mounted && _scope.current) showAppToast(context, error.message);
      return false;
    } on DioException catch (error) {
      if ((mounted && _scope.current)) {
        showAppToast(context, _errorMessage(error, '购买失败'));
      }
      return false;
    }
  }

  Future<void> _save() async {
    if ((!mounted || !_scope.current) || _saving || !_catalogFresh) return;
    setState(() {
      _saving = true;
      _previewChanged = true;
    });
    File? file;
    try {
      if (!await _ensureSelectedOwned()) return;
      if ((!mounted || !_scope.current)) return;
      if (_productId != null &&
          VirtualAvatarCatalog.assetUrl(_config) != null) {
        // Cloud originals keep their animation; the server resolves the owned product.
        final response = await _scope.patch('/api/virtual/profile', data: {
          'config': VirtualAvatarSpec.normalize(_config),
          'productId': _productId,
        });
        final saved = _savedAvatarData(response.data);
        final url = saved['avatarUrl']?.toString();
        if (url == null || url.isEmpty) throw StateError('missing avatar url');
        if ((!mounted || !_scope.current)) return;
        showAppToast(context, '头像已保存，全站同步生效');
        _finishSaving(url);
        return;
      }
      final data = await VirtualAvatarArtwork.exportLocalPng(_config,
          pixels: VirtualAvatarSpec.outputPixels);
      if ((!mounted || !_scope.current)) return;
      final directory = await getTemporaryDirectory();
      file = File(
        '${directory.path}/xuanyu_avatar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data, flush: true);
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: 'xuanyu_avatar_1024.png',
        ),
        'moderationScope': 'profile',
      });
      final uploaded = await _scope.post('/api/config/upload', data: form);
      final reviewed = await awaitMediaReview(uploaded.data,
          fetchReview: (path) => _scope.get(path));
      final url = reviewed['url']?.toString();
      if (url == null || url.isEmpty) throw StateError('missing url');
      final saved = await _scope.patch('/api/virtual/profile', data: {
        'config': VirtualAvatarSpec.normalize(_config),
        'productId': _productId,
        'avatarUrl': url,
      });
      final savedUrl = _savedAvatarData(saved.data)['avatarUrl']?.toString();
      if (savedUrl == null || savedUrl.isEmpty) {
        throw const FormatException('头像保存结果无效，请重试');
      }
      if ((!mounted || !_scope.current)) return;
      showAppToast(context, '头像已保存，全站同步生效');
      _finishSaving(savedUrl);
    } on MediaReviewException catch (error) {
      if (mounted && _scope.current) showAppToast(context, error.message);
    } on FormatException catch (error) {
      if (mounted && _scope.current) showAppToast(context, error.message);
    } on DioException catch (error) {
      if ((mounted && _scope.current)) {
        showAppToast(context, _errorMessage(error, '保存失败'));
      }
    } catch (_) {
      if ((mounted && _scope.current)) {
        showAppToast(context, '头像保存失败，请重试，已购买头像无需重新购买');
      }
    } finally {
      try {
        await file?.delete();
      } catch (_) {}
      if ((mounted && _scope.current)) setState(() => _saving = false);
    }
  }

  Map<dynamic, dynamic> _savedAvatarData(dynamic body) {
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      throw FormatException(body is Map
          ? body['message']?.toString() ?? '头像保存失败，请重试'
          : '头像保存结果无效，请重试');
    }
    return body['data'] as Map;
  }

  void _finishSaving(String url) {
    widget.onAvatarSaved?.call(url);
    if (!widget.embedded) Navigator.pop(context, url);
  }

  String _errorMessage(DioException error, String fallback) {
    final body = error.response?.data;
    return body is Map ? body['message']?.toString() ?? fallback : fallback;
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      const body = Center(child: Text(apiSessionChangedMessage));
      return widget.embedded
          ? body
          : Scaffold(
              appBar: AppBar(title: const Text('头像馆')),
              body: body,
            );
    }
    final selected = _selectedProduct;
    final body = _loading && _presets.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewSize = math
                    .min(
                      constraints.maxWidth - 92,
                      math.max(
                        176,
                        constraints.maxHeight * (widget.embedded ? .29 : .37),
                      ),
                    )
                    .toDouble();
                return Column(children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  if (!_loading && !_catalogFresh)
                    TextButton(
                        onPressed: _load, child: const Text('商品状态更新失败，点击重试')),
                  if (widget.embedded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
                      child: Row(children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '原创头像 · 圆形安全区校准',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (_entryEffects.isNotEmpty)
                          IconButton(
                            tooltip: '进房特效',
                            visualDensity: VisualDensity.compact,
                            onPressed: _showEntryEffects,
                            icon: const Icon(Icons.auto_awesome_rounded),
                          ),
                        FilledButton(
                          onPressed: _saving || !_catalogFresh ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          child: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_needsPurchase(selected) ? '购买并使用' : '使用'),
                        ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
                    child: Row(children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '平台原创成品 · 五官统一校准 · 全站同步',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        _catalogFresh
                            ? '${_balance.toStringAsFixed(0)}币'
                            : '余额更新中',
                        style: const TextStyle(
                          color: Color(0xFF9A7439),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]),
                  ),
                  SizedBox(
                    height: previewSize + 68,
                    child: Column(children: [
                      Container(
                        width: previewSize,
                        height: previewSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x26174845),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        foregroundDecoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                        child: VirtualAvatarArtwork(
                          config: _config,
                          circular: true,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.visibility_rounded,
                            size: 16,
                            color: AppColors.primaryDark,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '真实圆形预览 · ${selected?['name'] ?? '平台初始款'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (_needsPurchase(selected)) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.embedded
                              ? '预览免费，点击上方按钮后才确认购买'
                              : '预览免费，点击右上角后才确认购买',
                          style: const TextStyle(
                            color: Color(0xFF9A7439),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ]),
                  ),
                  Expanded(child: _buildPanel()),
                ]);
              },
            ),
          );
    if (widget.embedded) {
      return ColoredBox(color: const Color(0xFFF3F7F6), child: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: const Text('头像馆'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF3F7F6),
        actions: [
          if (_entryEffects.isNotEmpty)
            IconButton(
              tooltip: '进房特效',
              onPressed: _showEntryEffects,
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          TextButton(
            onPressed: _saving || !_catalogFresh ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_needsPurchase(selected) ? '购买并使用' : '使用'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: body,
    );
  }

  Widget _buildPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x13000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryDark,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: const Color(0xFFB59255),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '成品头像'),
            Tab(text: '我的头像'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPresetGallery(ownedOnly: false),
              _buildPresetGallery(ownedOnly: true),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildPresetGallery({required bool ownedOnly}) {
    final products = _presets.where((item) {
      if (item['productType'] != 'finished') return false;
      if (ownedOnly) return item['owned'] == true;
      return _selectedStyle == 'all' || item['categoryCode'] == _selectedStyle;
    }).toList();
    return Column(children: [
      if (!ownedOnly)
        SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            scrollDirection: Axis.horizontal,
            itemCount: _styleCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, index) {
              final entry = _styleCategories.entries.elementAt(index);
              final selected = _selectedStyle == entry.key;
              return ChoiceChip(
                selected: selected,
                label: Text(entry.value),
                onSelected: (_) => _changeStyle(entry.key),
                selectedColor: const Color(0xFFB59255),
                backgroundColor: const Color(0xFFF3F5F4),
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontSize: 10.5,
                ),
              );
            },
          ),
        ),
      if (ownedOnly)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 11, 16, 3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '免费与已购买头像会永久保留',
              style: TextStyle(color: AppColors.textHint, fontSize: 10.5),
            ),
          ),
        ),
      Expanded(
        child: products.isEmpty
            ? Center(
                child: Text(
                  ownedOnly ? '还没有已拥有的头像' : '该风格正在补充原创作品',
                  style: const TextStyle(color: AppColors.textHint),
                ),
              )
            : GridView.builder(
                controller: ownedOnly ? null : _galleryScrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: .74,
                ),
                itemCount:
                    products.length + (!ownedOnly && _loadingMore ? 1 : 0),
                itemBuilder: (_, index) {
                  if (index == products.length) {
                    return const Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return _buildPresetCard(products[index]);
                },
              ),
      ),
    ]);
  }

  Widget _buildPresetCard(Map<String, dynamic> preset) {
    final config = VirtualAvatarSpec.normalize(
      preset['config'] is Map ? preset['config'] as Map : null,
    );
    final selected = _config['assetCode'] == config['assetCode'];
    final owned = preset['owned'] == true;
    final price = double.tryParse('${preset['price'] ?? 0}') ?? 0;
    final stateLabel = price == 0
        ? '免费'
        : owned
            ? '已拥有'
            : '${price.toStringAsFixed(0)}币';
    return InkWell(
      onTap: _saving ? null : () => _selectPreset(preset),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE5F3F0) : const Color(0xFFF9FAF9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE4EAE8),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: VirtualAvatarArtwork(
                    config: config,
                    thumbnail: true,
                    circular: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${config['mediaType'] == 'animated' ? '动态 · ' : ''}${preset['name'] ?? '原创头像'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            stateLabel,
            style: TextStyle(
              color: price == 0 || owned
                  ? AppColors.textHint
                  : const Color(0xFF9A7439),
              fontSize: 9.5,
            ),
          ),
        ]),
      ),
    );
  }

  void _showEntryEffects() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: math.min(510, MediaQuery.of(context).size.height * .68),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAF9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(children: [
                Text('我的进房特效', style: AppTextStyles.titleMedium),
                const Spacer(),
                Text(
                  _catalogFresh ? '${_balance.toStringAsFixed(0)}币' : '余额更新中',
                  style: const TextStyle(color: Color(0xFF9A7439)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                itemCount: _entryEffects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final effect = _entryEffects[index];
                  final equipped = _equippedEntryEffectId == effect['id'];
                  return ListTile(
                    tileColor:
                        equipped ? const Color(0xFFE4F3F0) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryDark,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFE4C27C),
                      ),
                    ),
                    title: Text(effect['name']?.toString() ?? '进房特效'),
                    subtitle: Text(effect['description']?.toString() ?? ''),
                    trailing: FilledButton(
                      onPressed: equipped || !_catalogFresh
                          ? null
                          : () => _equipEntryEffect(effect),
                      child: Text(
                        equipped
                            ? '使用中'
                            : effect['owned'] == true
                                ? '装备'
                                : '${effect['price']}币',
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _equipEntryEffect(Map<String, dynamic> effect) async {
    if ((!mounted || !_scope.current) || !_catalogFresh) return;
    final price = double.tryParse('${effect['price'] ?? 0}') ?? 0;
    if (effect['owned'] != true && _balance + .0001 < price) {
      Navigator.pop(context);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RechargePage()),
      );
      await _load();
      return;
    }
    try {
      await _scope.post(
        '/api/virtual/entry-effect/equip',
        data: {'effectId': effect['id']},
      );
      if ((!mounted || !_scope.current)) return;
      setState(() {
        _equippedEntryEffectId = (effect['id'] as num?)?.toInt();
        if (effect['owned'] != true) {
          effect['owned'] = true;
          _balance -= price;
        }
      });
      Navigator.pop(context);
      showAppToast(context, '已装备「${effect['name']}」');
    } on ApiSessionChangedException {
      return;
    } on DioException catch (error) {
      if ((mounted && _scope.current)) {
        showAppToast(context, _errorMessage(error, '装备失败'));
      }
    }
  }
}
