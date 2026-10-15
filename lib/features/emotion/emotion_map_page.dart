import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/core/utils/report_utils.dart';
import 'package:xuanyu/features/emotion/data/province_names.dart';
import 'package:xuanyu/features/emotion/models/emotion_type.dart';
import 'package:xuanyu/features/emotion/models/identity_type.dart';
import 'package:xuanyu/features/emotion/services/emotion_map_service.dart';
import 'package:xuanyu/features/emotion/widgets/china_emotion_map_widget.dart';
import 'package:xuanyu/features/fortune/paipan/models/region.dart';
import 'package:xuanyu/features/fortune/paipan/widgets/birth_place_picker_sheet.dart';
import 'package:xuanyu/features/message/chat_page.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

/// 独立情绪地图：Flutter 矢量底图 + 模糊位置状态点。
class EmotionMapPage extends StatefulWidget {
  const EmotionMapPage({super.key});

  @override
  State<EmotionMapPage> createState() => _EmotionMapPageState();
}

class _EmotionPublishLocation {
  const _EmotionPublishLocation({
    required this.province,
    required this.city,
    required this.district,
    required this.township,
    required this.latitude,
    required this.longitude,
  });

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

class _EmotionMapPageState extends State<EmotionMapPage> {
  EmotionMapOverview _overview =
      const EmotionMapOverview(total: 0, regions: []);
  List<EmotionCheckin> _items = [];
  Region? _region;
  _EmotionPublishLocation? _publishLocation;
  IdentityType _identity = IdentityType.worker;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  final _sheetCtrl = DraggableScrollableController();
  bool _showingNearbyPoints = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sheetCtrl.dispose();
    super.dispose();
  }

  ({String province, String city, String district, String township})
      get _regionParts {
    final publish = _publishLocation;
    if (publish != null) {
      return (
        province: publish.province,
        city: publish.city,
        district: publish.district,
        township: publish.township,
      );
    }
    final parts = (_region?.extPath ?? '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return (
      province: parts.isNotEmpty ? parts[0] : '',
      city: parts.length > 1 ? parts[1] : '',
      district: parts.length > 2 ? parts[2] : '',
      township: parts.length > 3 ? parts[3] : '',
    );
  }

  Map<String, EmotionType> get _provinceEmotions {
    final map = <String, EmotionType>{};
    for (final r in _overview.regions) {
      if (r.province.isEmpty) continue;
      final short = ProvinceNames.toShort(r.province);
      map[short] = r.emotion;
      map[r.province] = r.emotion;
    }
    return map;
  }

  Map<String, int> get _provinceCounts {
    final map = <String, int>{};
    for (final r in _overview.regions) {
      if (r.province.isEmpty) continue;
      final short = ProvinceNames.toShort(r.province);
      map[short] = r.count;
      map[r.province] = r.count;
    }
    return map;
  }

  String? get _selectedShort {
    final p = _regionParts.province;
    if (p.isEmpty) return null;
    return ProvinceNames.toShort(p);
  }

  List<EmotionMapPoint> get _mapPoints => _items
      .where((item) {
        final lat = item.latitude;
        final lng = item.longitude;
        return lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat >= 18 &&
            lat <= 54 &&
            lng >= 73 &&
            lng <= 135;
      })
      .map(
        (item) => EmotionMapPoint(
          id: item.id,
          latitude: item.latitude!,
          longitude: item.longitude!,
          emotion: item.emotion,
          locationLabel: [
            if (item.township.isNotEmpty) item.township,
            if (item.township.isEmpty && item.district.isNotEmpty)
              item.district,
            if (item.township.isEmpty &&
                item.district.isEmpty &&
                item.city.isNotEmpty)
              item.city,
          ].join(''),
        ),
      )
      .toList(growable: false);

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final parts = _regionParts;
      final values = await Future.wait([
        EmotionMapService.overview(),
        EmotionMapService.feed(
          province: parts.province,
          city: parts.city,
          district: parts.district,
          township: parts.township,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = values[0] as EmotionMapOverview;
        _items = (values[1] as EmotionFeedPage).items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = EmotionMapService.message(e);
      });
    }
  }

  void _expandSheet([double size = 0.5]) {
    if (_sheetCtrl.isAttached) {
      _sheetCtrl.animateTo(
        size,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _pickRegion() => BirthPlacePickerSheet.show(
        context,
        initialRegion: _region,
        onConfirm: (region) async {
          setState(() {
            _region = region;
            _publishLocation = null;
          });
          _load();
          _expandSheet(0.48);
        },
      );

  Future<bool> _pickPublishLocation() async {
    Region? selected;
    await BirthPlacePickerSheet.show(
      context,
      title: '选择公开位置',
      initialRegion: _region,
      onConfirm: (region) => selected = region,
    );
    if (!mounted || selected == null) return false;

    final township = await _askTownship();
    if (!mounted || township == null) return false;
    if (RegExp(r'\d|号|栋|单元|室|楼|小区').hasMatch(township)) {
      showAppToast(context, '为保护隐私，请只填写乡镇或街道，不要填写门牌、小区或楼栋');
      return false;
    }
    final parts = selected!.extPath
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final result = _EmotionPublishLocation(
      province: parts.isNotEmpty ? parts[0] : selected!.name,
      city: parts.length > 1 ? parts[1] : '',
      district: parts.length > 2 ? parts[2] : selected!.name,
      township: township,
      latitude: selected!.lat,
      longitude: selected!.lng,
    );
    setState(() {
      _publishLocation = result;
      _region = Region.placeholder(
        name: result.township.isNotEmpty ? result.township : result.district,
        extPath: result.publicLabel,
        lng: result.longitude,
        lat: result.latitude,
      );
    });
    await _load();
    return true;
  }

  Future<String?> _askTownship() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('补充乡镇或街道'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可填写到乡镇或街道；平台只公开模糊位置，不展示详细住址。'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              decoration: const InputDecoration(
                hintText: '例如：清河街道（可留空）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _onProvinceTap(String province, EmotionType? emotion) {
    final full = ProvinceNames.toFull(province) ?? province;
    setState(() {
      _region = Region.placeholder(name: province, extPath: full);
      _publishLocation = null;
    });
    _load();
    _expandSheet(0.55);
  }

  void _onPointTap(EmotionMapPoint point) {
    for (final item in _items) {
      if (item.id == point.id) {
        _showStatusCard(item);
        return;
      }
    }
  }

  Future<void> _publish() async {
    if (_publishLocation == null) {
      final picked = await _pickPublishLocation();
      if (!picked) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PublishEmotionSheet(
        identity: _identity,
        onIdentityChanged: (value) => setState(() => _identity = value),
        regionLabel: _publishLocation?.publicLabel ?? '',
        onSubmit: (emotion, text, chatAllowed) async {
          final location = _publishLocation!;
          await EmotionMapService.publish(
            identity: _identity,
            emotion: emotion,
            province: location.province,
            city: location.city,
            district: location.district,
            township: location.township,
            latitude: location.latitude,
            longitude: location.longitude,
            chatAllowed: chatAllowed,
            content: text,
          );
          if (!context.mounted) return;
          Navigator.pop(context);
          if (mounted) {
            showAppToast(this.context, '已发布到情绪地图');
            _load();
          }
        },
      ),
    );
  }

  Future<void> _startChat(EmotionCheckin item) async {
    try {
      final target = await EmotionMapService.startChat(item.id);
      if (!mounted || target.conversationId <= 0) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: target.conversationId,
            title: target.title,
            conversationType: 'single',
            peerUserId: target.peerUserId > 0 ? target.peerUserId : null,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showAppToast(context, EmotionMapService.message(error));
    }
  }

  Future<void> _showStatusCard(EmotionCheckin item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _EmotionStatusCard(
        item: item,
        onLike: () => _toggleLike(item),
        onReport: item.isMine
            ? null
            : () => showReportSheet(
                  sheetContext,
                  targetType: 'emotion_checkin',
                  targetId: item.id,
                  title: '举报这条状态',
                ),
        onChat: item.chatAllowed && !item.isMine
            ? () {
                Navigator.pop(sheetContext);
                _startChat(item);
              }
            : null,
      ),
    );
  }

  Future<void> _toggleLike(EmotionCheckin item) async {
    try {
      final result = await EmotionMapService.toggleLike(item.id);
      if (!mounted) return;
      setState(() {
        item.liked = result.liked;
        item.likeCount = result.likeCount;
      });
    } catch (error) {
      if (mounted) {
        showAppToast(context, EmotionMapService.message(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F4FA),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: topInset + 56, bottom: 120),
              child: ChinaEmotionMapWidget(
                expand: true,
                provinceEmotions: _provinceEmotions,
                provinceCounts: _provinceCounts,
                selectedProvince: _selectedShort,
                points: _mapPoints,
                onProvinceTap: _onProvinceTap,
                onPointTap: _onPointTap,
                onScaleChanged: (scale) {
                  final showing = scale >= 2.15;
                  if (showing != _showingNearbyPoints && mounted) {
                    setState(() => _showingNearbyPoints = showing);
                  }
                },
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, size: 18.r),
                      onPressed: () {
                        if (Get.key.currentState?.canPop() == true) {
                          Get.back();
                        } else {
                          NavUtils.goBack();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: _pickRegion,
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.place_rounded,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _region?.extPath.isNotEmpty == true
                                      ? _region!.extPath
                                      : '点地图情绪图标，或手动选择位置',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.expand_more,
                                  color: AppColors.textHint, size: 20.r),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () => _load(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: topInset + 58,
            left: 16,
            right: 68,
            child: Material(
              color: Colors.white.withValues(alpha: 0.94),
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Text('🗺', style: TextStyle(fontSize: 16.sp)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error != null
                            ? _error!
                            : _showingNearbyPoints
                                ? '乡镇附近的匿名状态 · 位置已经模糊处理'
                                : '全国 ${_overview.total} 个此刻状态 · 双指放大可看附近的人',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: _error != null
                              ? Colors.orange.shade800
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetCtrl,
            initialChildSize: 0.36,
            minChildSize: 0.2,
            maxChildSize: 0.88,
            builder: (context, scrollController) {
              return Material(
                color: Colors.white,
                elevation: 10,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _region?.extPath.isNotEmpty == true
                                      ? '${_region!.extPath} · ${_items.length} 条'
                                      : '全国动态 · 点地图情绪图标',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  _showingNearbyPoints
                                      ? '点地图状态查看此刻；位置仅展示模糊范围'
                                      : '继续放大地图，可看到乡镇附近的匿名状态',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _publish,
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('记录此刻'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: EmotionType.values.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: Text(e.emoji),
                              label: Text(e.label,
                                  style: const TextStyle(fontSize: 12)),
                              backgroundColor: e.color.withValues(alpha: 0.12),
                              onPressed: () async {
                                if (_publishLocation == null) {
                                  final picked = await _pickPublishLocation();
                                  if (!picked) return;
                                }
                                if (!mounted) return;
                                await showModalBottomSheet<void>(
                                  context: this.context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (ctx) => _PublishEmotionSheet(
                                    identity: _identity,
                                    initialEmotion: e,
                                    onIdentityChanged: (v) =>
                                        setState(() => _identity = v),
                                    regionLabel:
                                        _publishLocation?.publicLabel ?? '',
                                    onSubmit:
                                        (emotion, text, chatAllowed) async {
                                      final location = _publishLocation!;
                                      await EmotionMapService.publish(
                                        identity: _identity,
                                        emotion: emotion,
                                        province: location.province,
                                        city: location.city,
                                        district: location.district,
                                        township: location.township,
                                        latitude: location.latitude,
                                        longitude: location.longitude,
                                        chatAllowed: chatAllowed,
                                        content: text,
                                      );
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (mounted) {
                                        showAppToast(this.context, '已发布到情绪地图');
                                        _load();
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _items.isEmpty
                              ? ListView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.all(32),
                                  children: [
                                    Icon(Icons.touch_app_outlined,
                                        size: 48,
                                        color: AppColors.textHint
                                            .withValues(alpha: 0.5)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _region == null
                                          ? '点地图上各省的情绪图标，查看当地动态'
                                          : '这里还很安静，成为第一条吧',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, index) {
                                    final item = _items[index];
                                    return _FeedTile(
                                      item: item,
                                      onLike: () => _toggleLike(item),
                                      onTap: () => _showStatusCard(item),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({
    required this.item,
    required this.onLike,
    required this.onTap,
  });
  final EmotionCheckin item;
  final VoidCallback onLike;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final place = [
      item.province,
      if (item.city.isNotEmpty) item.city,
      if (item.district.isNotEmpty) item.district,
      if (item.township.isNotEmpty) item.township,
    ].join(' ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: item.emotion.color.withValues(alpha: 0.22),
              child: Text(item.emotion.emoji),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.nickname} · ${item.identity.label}${item.chatAllowed ? ' · 愿意聊聊' : ''}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.content.isEmpty
                        ? '此刻是 ${item.emotion.label}'
                        : item.content,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (place.isNotEmpty) place,
                      if (item.createdAt != null) item.createdAt!,
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: onLike,
                  icon: Icon(
                    item.liked ? Icons.favorite : Icons.favorite_border,
                    color: item.liked
                        ? const Color(0xFFEF5A67)
                        : AppColors.textHint,
                  ),
                ),
                Text(
                  '${item.likeCount}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmotionStatusCard extends StatelessWidget {
  const _EmotionStatusCard({
    required this.item,
    required this.onLike,
    required this.onChat,
    required this.onReport,
  });

  final EmotionCheckin item;
  final VoidCallback onLike;
  final VoidCallback? onChat;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final place = [
      item.city,
      item.district,
      item.township,
    ].where((part) => part.isNotEmpty).join(' ');
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: item.emotion.color.withValues(alpha: 0.18),
                  child: Text(item.emotion.emoji,
                      style: const TextStyle(fontSize: 23)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('同频旅人',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (place.isNotEmpty) '$place附近',
                          item.identity.label,
                          item.emotion.label,
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '善意回应',
                  onPressed: onLike,
                  icon: Icon(
                    item.liked ? Icons.favorite : Icons.favorite_border,
                    color: item.liked
                        ? const Color(0xFFEF5A67)
                        : AppColors.textHint,
                  ),
                ),
                if (onReport != null)
                  IconButton(
                    tooltip: '举报',
                    onPressed: onReport,
                    icon: const ReferenceActionGlyph(
                      type: ReferenceActionIconType.report,
                      size: 23,
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              item.content.isEmpty
                  ? '此刻${item.identity.label}，感觉${item.emotion.label}。'
                  : item.content,
              style: const TextStyle(fontSize: 16, height: 1.55),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 15, color: AppColors.textHint),
                const SizedBox(width: 5),
                Text('状态仅保留2小时 · 位置已模糊',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 18),
            if (item.isMine)
              const Center(
                child: Text('这是你发布的此刻状态',
                    style: TextStyle(color: AppColors.textSecondary)),
              )
            else if (onChat != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onChat,
                  icon: const ReferenceActionGlyph(
                    type: ReferenceActionIconType.privateChat,
                    size: 20,
                    color: Colors.white,
                  ),
                  label: const Text('和TA聊聊'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              )
            else
              const Center(
                child: Text('TA这次只想记录此刻',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PublishEmotionSheet extends StatefulWidget {
  const _PublishEmotionSheet({
    required this.identity,
    required this.onIdentityChanged,
    required this.regionLabel,
    required this.onSubmit,
    this.initialEmotion,
  });

  final IdentityType identity;
  final ValueChanged<IdentityType> onIdentityChanged;
  final String regionLabel;
  final Future<void> Function(
      EmotionType emotion, String text, bool chatAllowed) onSubmit;
  final EmotionType? initialEmotion;

  @override
  State<_PublishEmotionSheet> createState() => _PublishEmotionSheetState();
}

class _PublishEmotionSheetState extends State<_PublishEmotionSheet> {
  late EmotionType _emotion;
  late IdentityType _identity;
  final _text = TextEditingController();
  bool _submitting = false;
  bool _chatAllowed = false;

  @override
  void initState() {
    super.initState();
    _emotion = widget.initialEmotion ?? EmotionType.zen;
    _identity = widget.identity;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '记录此刻 · ${widget.regionLabel}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text('此刻正在',
                  style: TextStyle(
                      fontSize: 12.sp, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: IdentityType.values
                    .map(
                      (item) => ChoiceChip(
                        label: Text('${item.emoji} ${item.label}'),
                        selected: _identity == item,
                        selectedColor: item.color.withValues(alpha: 0.25),
                        onSelected: (_) {
                          setState(() => _identity = item);
                          widget.onIdentityChanged(item);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              Text('情绪',
                  style: TextStyle(
                      fontSize: 12.sp, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EmotionType.values
                    .map(
                      (item) => ChoiceChip(
                        label: Text('${item.emoji} ${item.label}'),
                        selected: _emotion == item,
                        selectedColor: item.color.withValues(alpha: 0.25),
                        onSelected: (_) => setState(() => _emotion = item),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                maxLength: 280,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '写点自定义的话（可选）',
                  filled: true,
                  fillColor: AppColors.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _chatAllowed,
                activeThumbColor: AppColors.primary,
                title: const Text('愿意和同状态的人聊聊',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  '开启后，别人可进入私信；你回复前，对方最多发送3条文字',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
                onChanged: (value) => setState(() => _chatAllowed = value),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined,
                        size: 17, color: AppColors.primary),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '公开时仅显示乡镇或街道附近，坐标会模糊到约1公里，状态2小时后自动结束。',
                        style: TextStyle(fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting
                      ? null
                      : () async {
                          setState(() => _submitting = true);
                          try {
                            await widget.onSubmit(
                              _emotion,
                              _text.text.trim(),
                              _chatAllowed,
                            );
                          } catch (e) {
                            if (mounted) {
                              showAppToast(
                                  this.context, EmotionMapService.message(e));
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _submitting = false);
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_submitting ? '正在发布…' : '发布到这里'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
