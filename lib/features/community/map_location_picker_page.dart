import 'dart:async';
import 'dart:convert';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:permission_handler/permission_handler.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/amap_platform_support.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/device_location.dart';

/// 地图选点的结构化结果。精确坐标仅用于提交给业务接口做模糊化，页面不公开。
class MapLocationSelection {
  const MapLocationSelection({
    required this.address,
    required this.province,
    required this.city,
    required this.district,
    required this.township,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final String province;
  final String city;
  final String district;
  final String township;
  final double? latitude;
  final double? longitude;

  String get publicLabel => [province, city, district, township]
      .where((part) => part.trim().isNotEmpty)
      .join(' ');
}

/// 地图选点页面：展示高德地图，点击/拖动获取位置并逆地理编码
class MapLocationPickerPage extends StatefulWidget {
  const MapLocationPickerPage({super.key, this.returnDetails = false});

  /// 默认保持原有 String 返回值；情绪地图需要行政区和坐标时返回 MapLocationSelection。
  final bool returnDetails;

  @override
  State<MapLocationPickerPage> createState() => _MapLocationPickerPageState();
}

class _MapLocationPickerPageState extends State<MapLocationPickerPage> {
  final ValueNotifier<String?> _selectedAddress = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _loadingRegeo = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _locatingUser = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _searching = ValueNotifier<bool>(false);

  AMapController? _mapController;
  final MapController _osmController = MapController();
  LatLng? _userLatLng;
  MapLocationSelection? _selectedDetails;
  LatLng? _pendingCameraTarget;
  double? _pendingCameraZoom;
  bool _handledNativeLocation = false;

  /// 程序主动移动镜头时忽略 onCameraMoveEnd，避免抢占用户手势。
  bool _programmaticCameraMove = false;
  int _regeoSeq = 0;
  bool? _mapSupported;
  bool _amapInited = false;
  Timer? _cameraEndDebounce;
  Timer? _programmaticUnlockTimer;

  /// 缓存地图实例，避免 overlay 刷新时反复重建 PlatformView。
  Widget? _mapLayer;

  final TextEditingController _manualCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(39.909187, 116.397451),
    zoom: 12.0,
  );

  static final MyLocationStyleOptions _myLocationStyle = MyLocationStyleOptions(
    true,
    circleFillColor: Colors.transparent,
    circleStrokeColor: Colors.transparent,
    circleStrokeWidth: 0,
  );

  static const AMapApiKey _apiKey = AMapApiKey(
    androidKey: AppConstants.amapAndroidKey,
    iosKey: AppConstants.amapIosKey,
  );

  static const AMapPrivacyStatement _privacyStatement = AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );

  bool _isValidKey(String key) => key.isNotEmpty && !key.startsWith('YOUR_');

  bool get _useNativeIosMap => AmapPlatformSupport.useNativeAmapWidget;

  bool get _hasValidKey {
    if (kIsWeb) return false;
    if (_useNativeIosMap) return _isValidKey(AppConstants.amapIosKey);
    // Android 选点用瓦片 + 高德 Web 逆地理，不再依赖 3D SDK Key。
    return true;
  }

  ll.LatLng _toOsm(LatLng latLng) =>
      ll.LatLng(latLng.latitude, latLng.longitude);

  LatLng _fromOsm(ll.LatLng latLng) => LatLng(latLng.latitude, latLng.longitude);

  @override
  void initState() {
    super.initState();
    _probeMapSupport();
  }

  @override
  void dispose() {
    _cameraEndDebounce?.cancel();
    _programmaticUnlockTimer?.cancel();
    _selectedAddress.dispose();
    _loadingRegeo.dispose();
    _locatingUser.dispose();
    _searching.dispose();
    _manualCtrl.dispose();
    _searchCtrl.dispose();
    _osmController.dispose();
    super.dispose();
  }

  Future<void> _probeMapSupport() async {
    final supported = await AmapPlatformSupport.isMapSupported();
    if (!mounted) return;
    setState(() => _mapSupported = supported);
    if (supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToUserLocation(showError: false);
      });
    }
  }

  Future<void> _moveToUserLocation({bool showError = true}) async {
    if (_locatingUser.value) return;
    if (kIsWeb) {
      if (showError && mounted) showAppToast(context, 'Web 平台暂不支持定位');
      return;
    }
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted && !status.isLimited) {
      if (showError && mounted) showAppToast(context, '请授予定位权限以使用当前位置');
      return;
    }
    _locatingUser.value = true;
    try {
      final position = await DeviceLocation.current();
      if (mounted && position != null) {
        await _applyUserLocation(
          LatLng(position.latitude, position.longitude),
          selectLocation: true,
          zoom: 15.0,
        );
      } else if (showError && mounted) {
        showAppToast(context, '定位失败，请检查定位权限与网络');
      }
    } on Object catch (_) {
      if (showError && mounted) showAppToast(context, '定位失败，请稍后重试');
    } finally {
      if (mounted) _locatingUser.value = false;
    }
  }

  Future<void> _applyUserLocation(
    LatLng loc, {
    bool selectLocation = false,
    bool moveMap = true,
    double? zoom,
  }) async {
    if (!mounted) return;
    _userLatLng = loc;

    if (moveMap) {
      await _moveMapToLatLng(loc, zoom: zoom, retry: 2);
    }
    if (!selectLocation || !mounted) return;
    await _selectLatLng(loc);
  }

  /// 原生定位回调会持续上报；仅首次自动移到当前位置，之后不再抢镜头。
  void _handleNativeLocation(AMapLocation loc) {
    if (!isLocationValid(loc)) return;
    final latLng = loc.latLng;
    if (_handledNativeLocation) {
      _userLatLng = latLng;
      return;
    }
    _handledNativeLocation = true;
    _applyUserLocation(
      latLng,
      selectLocation: _selectedAddress.value == null,
      moveMap: true,
      zoom: 15.0,
    );
  }

  Future<void> _moveMapToLatLng(
    LatLng latLng, {
    double? zoom,
    bool animated = true,
    int retry = 0,
  }) async {
    if (!_useNativeIosMap) {
      _programmaticCameraMove = true;
      _programmaticUnlockTimer?.cancel();
      try {
        final currentZoom = zoom ?? _osmController.camera.zoom;
        _osmController.move(_toOsm(latLng), currentZoom);
        _pendingCameraTarget = null;
        _pendingCameraZoom = null;
      } on Object catch (_) {
        _pendingCameraTarget = latLng;
        _pendingCameraZoom = zoom;
      }
      _programmaticUnlockTimer = Timer(
        Duration(milliseconds: animated ? 420 : 50),
        () {
          if (mounted) _programmaticCameraMove = false;
        },
      );
      return;
    }

    final controller = _mapController;
    if (controller == null) {
      _pendingCameraTarget = latLng;
      _pendingCameraZoom = zoom;
      return;
    }

    _programmaticCameraMove = true;
    _programmaticUnlockTimer?.cancel();
    var succeeded = false;
    try {
      final update = zoom != null
          ? CameraUpdate.newLatLngZoom(latLng, zoom)
          : CameraUpdate.newLatLng(latLng);
      await controller
          .moveCamera(
            update,
            animated: animated,
            duration: animated ? 350 : 0,
          )
          .timeout(const Duration(milliseconds: 800));
      _pendingCameraTarget = null;
      _pendingCameraZoom = null;
      succeeded = true;
    } on Object catch (_) {
      _pendingCameraTarget = latLng;
      _pendingCameraZoom = zoom;
    }

    _programmaticUnlockTimer = Timer(
      Duration(milliseconds: animated ? 420 : 50),
      () {
        if (mounted) _programmaticCameraMove = false;
      },
    );

    if (succeeded || retry <= 0 || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _moveMapToLatLng(
      latLng,
      zoom: zoom,
      animated: animated,
      retry: retry - 1,
    );
  }

  Future<void> _moveMapToUserLocation() async {
    final latLng = _userLatLng;
    if (latLng == null) {
      await _moveToUserLocation(showError: true);
      return;
    }
    final selectFuture = _selectLatLng(latLng);
    unawaited(_moveMapToLatLng(latLng, animated: true));
    await selectFuture;
  }

  String? _amapWebKey() {
    final key = (AppConstants.amapWebKey.isNotEmpty &&
            !AppConstants.amapWebKey.startsWith('YOUR_'))
        ? AppConstants.amapWebKey
        : (AppConstants.amapAndroidKey.isNotEmpty &&
                !AppConstants.amapAndroidKey.startsWith('YOUR_')
            ? AppConstants.amapAndroidKey
            : null);
    return key == null || key.isEmpty ? null : key;
  }

  Future<void> _searchLocation() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      showAppToast(context, '请输入地点或区域名称');
      return;
    }
    final key = _amapWebKey();
    if (key == null) {
      showAppToast(context, '暂时无法搜索地点，请直接在地图上选点');
      return;
    }
    _searching.value = true;
    try {
      final url = 'https://restapi.amap.com/v3/geocode/geo'
          '?key=${Uri.encodeQueryComponent(key)}'
          '&address=${Uri.encodeQueryComponent(query)}';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) throw const FormatException();
      final payload = jsonDecode(response.body) as Map<String, dynamic>?;
      final geocodes = payload?['geocodes'];
      final first = geocodes is List && geocodes.isNotEmpty
          ? geocodes.first
          : null;
      final location = first is Map ? first['location']?.toString() : null;
      final parts = location?.split(',') ?? const <String>[];
      final longitude = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
      final latitude = parts.length > 1 ? double.tryParse(parts[1]) : null;
      if (latitude == null || longitude == null) {
        if (mounted) showAppToast(context, '没有找到匹配地点，请换个关键词');
        return;
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      await _applyUserLocation(
        LatLng(latitude, longitude),
        selectLocation: true,
        zoom: 16.0,
      );
    } on Object catch (_) {
      if (mounted) showAppToast(context, '地点搜索失败，请稍后重试');
    } finally {
      if (mounted) _searching.value = false;
    }
  }

  Future<void> _selectLatLng(LatLng latLng) async {
    final seq = ++_regeoSeq;
    if (!mounted) return;
    final fallback =
        '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
    _loadingRegeo.value = true;
    _selectedAddress.value = fallback;
    _selectedDetails = MapLocationSelection(
      address: fallback,
      province: '',
      city: '',
      district: '',
      township: '',
      latitude: latLng.latitude,
      longitude: latLng.longitude,
    );

    final details = await _reverseGeocode(latLng.latitude, latLng.longitude);
    if (!mounted || seq != _regeoSeq) return;
    _loadingRegeo.value = false;
    if (details != null) _selectedDetails = details;
    _selectedAddress.value = details?.address ?? fallback;
  }

  void _onCameraMoveEnd(CameraPosition position) {
    if (_programmaticCameraMove) return;
    _cameraEndDebounce?.cancel();
    // 拖动松手后短防抖，避免连续 finish 触发多次逆地理。
    _cameraEndDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || _programmaticCameraMove) return;
      _selectLatLng(position.target);
    });
  }

  Future<MapLocationSelection?> _reverseGeocode(double lat, double lng) async {
    final key = _amapWebKey();
    if (key == null || key.isEmpty) return null;
    final url =
        'https://restapi.amap.com/v3/geocode/regeo?key=$key&location=$lng,$lat';
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>?;
      final status = json?['status']?.toString();
      if (status != '1') return null;
      final regeocode = json?['regeocode'] as Map<String, dynamic>?;
      final addressComponent =
          regeocode?['addressComponent'] as Map<String, dynamic>?;
      if (addressComponent == null) return null;
      final province = addressComponent['province']?.toString() ?? '';
      final cityRaw = addressComponent['city'];
      final city = cityRaw is String
          ? cityRaw
          : (cityRaw is List && cityRaw.isNotEmpty
              ? cityRaw.first.toString()
              : '');
      final district = addressComponent['district']?.toString() ?? '';
      final township = addressComponent['township']?.toString() ?? '';
      final sn = addressComponent['streetNumber'];
      final street = sn is Map ? (sn['street']?.toString() ?? '') : '';
      final number = sn is Map ? (sn['number']?.toString() ?? '') : '';
      final merged = '$province$city$district$township$street$number'
          .replaceAll(RegExp(r'\s+|\[\]'), '');
      final formatted = regeocode?['formatted_address']?.toString() ?? '';
      final address = formatted.isNotEmpty ? formatted : merged;
      if (address.isEmpty) return null;
      return MapLocationSelection(
        address: address,
        province: province,
        city: city,
        district: district,
        township: township.isNotEmpty ? township : street,
        latitude: lat,
        longitude: lng,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _onMapTap(LatLng latLng) async {
    if (!_hasValidKey) return;
    _cameraEndDebounce?.cancel();
    final selectFuture = _selectLatLng(latLng);
    unawaited(_moveMapToLatLng(latLng, animated: true));
    await selectFuture;
  }

  void _confirm() {
    final address = _selectedAddress.value;
    if (address != null) {
      Navigator.of(context)
          .pop(widget.returnDetails ? _selectedDetails : address);
    } else {
      showAppToast(context, '请在地图上点击选择位置');
    }
  }

  void _confirmManual() {
    final text = _manualCtrl.text.trim();
    if (text.isEmpty) {
      showAppToast(context, '请输入位置名称');
      return;
    }
    if (widget.returnDetails) {
      Navigator.of(context).pop(MapLocationSelection(
        address: text,
        province: '',
        city: '',
        district: '',
        township: text,
        latitude: null,
        longitude: null,
      ));
    } else {
      Navigator.of(context).pop(text);
    }
  }

  Widget _ensureMapLayer() {
    if (!_useNativeIosMap) {
      return _mapLayer ??= FlutterMap(
        key: const ValueKey('map_location_picker_osm'),
        mapController: _osmController,
        options: MapOptions(
          initialCenter: _toOsm(_initialPosition.target),
          initialZoom: _initialPosition.zoom,
          onTap: (tapPosition, point) => _onMapTap(_fromOsm(point)),
          onMapReady: () {
            final latLng = _pendingCameraTarget ?? _userLatLng;
            if (latLng != null) {
              final zoom = _pendingCameraZoom ?? 15.0;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _moveMapToLatLng(latLng, zoom: zoom, retry: 3);
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _moveToUserLocation(showError: false);
              });
            }
          },
          onMapEvent: (event) {
            if (_programmaticCameraMove) return;
            if (event is MapEventMoveEnd) {
              _onCameraMoveEnd(
                CameraPosition(
                  target: _fromOsm(event.camera.center),
                  zoom: event.camera.zoom,
                ),
              );
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=7',
            fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['1', '2', '3', '4'],
            userAgentPackageName: 'com.xuanyu.android',
          ),
        ],
      );
    }

    return _mapLayer ??= AMapWidget(
      key: const ValueKey('map_location_picker'),
      initialCameraPosition: _initialPosition,
      myLocationStyleOptions: _myLocationStyle,
      // 关掉比例尺；Logo 官方不可关，用负边距移出可视区
      scaleEnabled: false,
      logoBottomMargin: -200,
      logoLeftMargin: -200,
      onLocationChanged: _handleNativeLocation,
      onMapCreated: (AMapController c) {
        _mapController = c;
        final latLng = _pendingCameraTarget ?? _userLatLng;
        if (latLng != null) {
          final zoom = _pendingCameraZoom ?? 15.0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _moveMapToLatLng(latLng, zoom: zoom, retry: 3);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _moveToUserLocation(showError: false);
          });
        }
      },
      onTap: _onMapTap,
      onCameraMoveEnd: _onCameraMoveEnd,
    );
  }

  Widget _buildUnsupportedFallback() {
    return Scaffold(
      appBar: AppBar(title: const Text('选择位置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              '当前设备不支持高德地图预览',
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '当前环境无法加载高德三维地图（常见于 x86 模拟器），请手动输入位置。',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _manualCtrl,
              decoration: const InputDecoration(
                labelText: '位置名称',
                hintText: '例如：北京市朝阳区',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirmManual(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _confirmManual,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mapSupported == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_mapSupported == false) {
      return _buildUnsupportedFallback();
    }

    if (_useNativeIosMap && !_amapInited) {
      AMapInitializer.init(context, apiKey: _apiKey);
      AMapInitializer.updatePrivacyAgree(_privacyStatement);
      _amapInited = true;
    }
    if (!_hasValidKey) {
      return Scaffold(
        appBar: AppBar(title: const Text('地图选点')),
        body: Center(
          child: Text(
            '请先在 AppConstants 中配置高德地图 API Key',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      appBar: AppBar(
        title: const Text('地图选点'),
        actions: [
          TextButton(onPressed: _confirm, child: const Text('确定')),
        ],
      ),
      body: Stack(
        children: [
          // 地图层：同一 Widget 实例，地址刷新不再触发 PlatformView 同步。
          _ensureMapLayer(),
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  size: 44,
                  color: AppColors.primary.withValues(alpha: 0.95),
                  shadows: const [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: topPad + 8,
            child: Material(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              elevation: 2,
              child: ValueListenableBuilder<bool>(
                valueListenable: _searching,
                builder: (context, searching, _) => TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchLocation(),
                  decoration: InputDecoration(
                    hintText: '搜索地点或区域',
                    hintStyle: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.primary),
                    suffixIcon: searching
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: '搜索',
                            onPressed: _searchLocation,
                            icon: const Icon(Icons.arrow_forward_rounded,
                                color: AppColors.primary),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _selectedAddress,
            builder: (context, address, _) {
              return Positioned(
                right: 16,
                bottom: address != null ? bottomPad + 150 : bottomPad + 24,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _locatingUser,
                  builder: (context, locating, __) {
                    return FloatingActionButton.small(
                      heroTag: 'map_picker_my_location',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      onPressed: locating ? null : _moveMapToUserLocation,
                      child: locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    );
                  },
                ),
              );
            },
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _selectedAddress,
            builder: (context, address, _) {
              if (address == null) return const SizedBox.shrink();
              return Positioned(
                left: 16,
                right: 16,
                bottom: bottomPad + 24,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 6,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.place_rounded,
                                color: AppColors.primary, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: _loadingRegeo,
                                builder: (context, loading, __) {
                                  if (loading) {
                                    return Row(
                                      children: [
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '正在解析地址...',
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return Text(
                                    address,
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w600),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _confirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('确定选择此位置'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
