import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/community_feedback.dart';
import '../../core/utils/post_share.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../message/im_workflow_request.dart';
import 'post_media_cache.dart';
import 'post_card.dart';
import 'post_detail_page.dart';
import 'topic_feed_page.dart';
import 'community_search_page.dart';
import 'team_home_page.dart';
import '../consultation/voice_room_overlay_controller.dart';
import '../fortune/paipan/models/region.dart';
import '../fortune/paipan/widgets/birth_place_picker_sheet.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => CommunityPageState();
}

class CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _followFeed = <Map<String, dynamic>>[];
  final _localFeed = <Map<String, dynamic>>[];
  final _recommendFeed = <Map<String, dynamic>>[];
  final _partyUsers = <Map<String, dynamic>>[];
  int _followPage = 1;
  int _localPage = 1;
  int _recommendPage = 1;
  bool _loadingFollow = false;
  bool _loadingLocal = false;
  bool _loadingRecommend = false;
  String? _followError;
  String? _localError;
  String? _recommendError;
  bool _hasMoreFollow = true;
  bool _hasMoreLocal = true;
  bool _hasMoreRecommend = true;
  final _recommendTeams = <Map<String, dynamic>>[];
  bool _showRecommendTeams = true;
  int? _currentUserId;
  bool _localUseAutoLocation = true;
  String _localManualLocation = '';
  bool _partyLoading = false;
  String _partySnapshot = '';
  Timer? _partyRefreshTimer;
  Timer? _feedWarmupTimer;
  final _feedRevisions = <String, int>{};
  final _feedUpdatedAt = <String, DateTime>{};
  final _pendingImages = <String, ImageProvider>{};
  bool _warmingImages = false;
  int _session = apiSessionChanges.value;

  static const _localUseAutoKey = 'community_local_use_auto_location';
  static const _localManualLocationKey = 'community_local_manual_location';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_onSessionChanged);
    _tabController = TabController(length: 3, initialIndex: 1, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCurrentUserId();
    _loadLocalLocationPreference().then((_) {
      if (!mounted) return;
      // Stagger adjacent tabs instead of starting every request together.
      _feedWarmupTimer = Timer(const Duration(seconds: 3), () async {
        if (!_canWarm) return;
        if (!_feedUpdatedAt.containsKey('following')) await _loadFollow();
        if (!_canWarm) return;
        if (!_feedUpdatedAt.containsKey('local')) await _loadLocal();
      });
    });
    _loadCurrentTab();
    _loadRecommendTeams();
    _partyRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_tabController.index == 0) _loadPartyPresence();
    });
  }

  Future<void> _loadLocalLocationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _localUseAutoLocation = prefs.getBool(_localUseAutoKey) ?? true;
      _localManualLocation = prefs.getString(_localManualLocationKey) ?? '';
      if (_localManualLocation.trim().isEmpty) _localUseAutoLocation = true;
    });
  }

  Future<void> _loadCurrentUserId() async {
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    if (mounted && session == _session) {
      setState(() => _currentUserId = prefs.getInt(AppConstants.keyUserId));
    }
  }

  void _loadCurrentTab() {
    if (_tabController.index == 0 && _followFeed.isEmpty) _loadFollow();
    if (_tabController.index == 1 && _recommendFeed.isEmpty) _loadRecommend();
    if (_tabController.index == 2 && _localFeed.isEmpty) _loadLocal();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadCurrentTab();
      if (_tabController.index == 0) _loadPartyPresence();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _partyRefreshTimer?.cancel();
    _feedWarmupTimer?.cancel();
    apiSessionChanges.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _tabController.index == 0) {
      _loadPartyPresence();
    }
  }

  bool get _canWarm =>
      mounted &&
      _session == apiSessionChanges.value &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  void _onSessionChanged() {
    if (!mounted) return;
    _session = apiSessionChanges.value;
    _feedWarmupTimer?.cancel();
    _pendingImages.clear();
    _feedUpdatedAt.clear();
    setState(() {
      _followFeed.clear();
      _recommendFeed.clear();
      _localFeed.clear();
      _recommendTeams.clear();
      _partyUsers.clear();
      _partySnapshot = '';
      _currentUserId = null;
      _loadingFollow = _loadingLocal = _loadingRecommend = false;
      _followError = _localError = _recommendError = null;
      _followPage = _localPage = _recommendPage = 1;
      _hasMoreFollow = _hasMoreLocal = _hasMoreRecommend = true;
    });
    if (apiClient.options.headers['Authorization'] != null) {
      _loadCurrentUserId();
      _loadCurrentTab();
    }
  }

  Future<void> _warmImages(List<Map<String, dynamic>> items) async {
    if (!_canWarm) return;
    final edge = postPreviewEdge(
      MediaQuery.sizeOf(context).width,
      MediaQuery.devicePixelRatioOf(context),
    );
    final avatars = items
        .map((item) => item['avatarUrl'])
        .whereType<String>()
        .toSet();
    for (final url in postPreviewUrls(items)) {
      _pendingImages[url] = postPreviewImage(
        url,
        avatars.contains(url) ? 160 : edge,
      );
    }
    while (_pendingImages.length > 6) {
      _pendingImages.remove(_pendingImages.keys.last);
    }
    if (_warmingImages) return;
    _warmingImages = true;
    final session = _session;
    try {
      // Sequential and bounded, so taps and visible content keep priority.
      while (_canWarm && session == _session && _pendingImages.isNotEmpty) {
        final url = _pendingImages.keys.first;
        final provider = _pendingImages.remove(url)!;
        await precacheImage(provider, context, onError: (_, __) {});
      }
    } finally {
      _warmingImages = false;
      _pendingImages.clear();
    }
  }

  Future<void> _loadFollow({bool refresh = false}) async {
    if (!refresh && (_loadingFollow || !_hasMoreFollow)) return;
    final revision = (_feedRevisions['following'] ?? 0) + 1;
    _feedRevisions['following'] = revision;
    final session = _session;
    bool current() =>
        mounted &&
        session == _session &&
        revision == _feedRevisions['following'];
    if (refresh) _followPage = 1;
    setState(() {
      _loadingFollow = true;
      _followError = null;
    });
    final result = await _fetchFeed(
      'following',
      _followFeed,
      () => setState(() => _followPage++),
      _followPage,
      current,
    );
    if (current()) {
      setState(() {
        _hasMoreFollow = result.hasMore;
        _followError = result.error;
        _loadingFollow = false;
      });
    }
  }

  Future<void> _loadPartyPresence() async {
    if (_partyLoading) return;
    _partyLoading = true;
    final session = _session;
    try {
      final response = await apiClient.get('/api/im/party-presence');
      final data = (response.data as Map?)?['data'] as Map?;
      final rawList = data?['list'] as List<dynamic>? ?? const [];
      final next = rawList
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) =>
                (item['userId'] as num?)?.toInt() != null &&
                (item['roomId'] as num?)?.toInt() != null,
          )
          .toList();
      final snapshot = next
          .map(
            (item) =>
                '${item['userId']}:${item['roomId']}:${item['nickname']}:${item['avatarUrl']}',
          )
          .join('|');
      if (!mounted || session != _session || snapshot == _partySnapshot) return;
      setState(() {
        _partySnapshot = snapshot;
        _partyUsers
          ..clear()
          ..addAll(next);
      });
    } on DioException catch (_) {
      // 好友派对动态不影响关注信息流加载。
    } finally {
      _partyLoading = false;
    }
  }

  Future<void> _loadLocal({bool refresh = false}) async {
    if (!refresh && (_loadingLocal || !_hasMoreLocal)) return;
    final revision = (_feedRevisions['local'] ?? 0) + 1;
    _feedRevisions['local'] = revision;
    final session = _session;
    bool current() =>
        mounted && session == _session && revision == _feedRevisions['local'];
    if (refresh) _localPage = 1;
    setState(() {
      _loadingLocal = true;
      _localError = null;
    });
    final result = await _fetchFeed(
      'local',
      _localFeed,
      () => setState(() => _localPage++),
      _localPage,
      current,
    );
    if (current()) {
      setState(() {
        _hasMoreLocal = result.hasMore;
        _localError = result.error;
        _loadingLocal = false;
      });
    }
  }

  Future<void> _loadRecommend({bool refresh = false}) async {
    if (!refresh && (_loadingRecommend || !_hasMoreRecommend)) return;
    final revision = (_feedRevisions['recommend'] ?? 0) + 1;
    _feedRevisions['recommend'] = revision;
    final session = _session;
    bool current() =>
        mounted &&
        session == _session &&
        revision == _feedRevisions['recommend'];
    if (refresh) _recommendPage = 1;
    setState(() {
      _loadingRecommend = true;
      _recommendError = null;
    });
    final result = await _fetchFeed(
      'recommend',
      _recommendFeed,
      () => setState(() => _recommendPage++),
      _recommendPage,
      current,
    );
    if (current()) {
      setState(() {
        _hasMoreRecommend = result.hasMore;
        _recommendError = result.error;
        _loadingRecommend = false;
      });
    }
  }

  Future<void> _loadRecommendTeams() async {
    final session = _session;
    try {
      final response = await apiClient.get('/api/im/teams/joinable');
      if (!mounted || session != _session) return;
      final items =
          ((response.data as Map?)?['data'] as Map?)?['list'] as List<dynamic>?;
      setState(() {
        _recommendTeams.clear();
        if (items != null) {
          for (final e in items) {
            if (e is Map<String, dynamic>) {
              _recommendTeams.add(Map<String, dynamic>.from(e));
            }
          }
        }
      });
    } on DioException catch (error) {
      if (mounted &&
          session == _session &&
          {401, 403, 404}.contains(error.response?.statusCode)) {
        setState(() {
          _recommendTeams.clear();
        });
      }
    }
  }

  Future<void> _refreshFollow() async {
    await Future.wait([_loadFollow(refresh: true), _loadPartyPresence()]);
  }

  void _openParty(Map<String, dynamic> user) {
    final roomId = (user['roomId'] as num?)?.toInt();
    if (roomId == null) return;
    final opened = VoiceRoomOverlayController.instance.open(roomId);
    if (!opened && mounted) showAppToast(context, '请先退出当前语音房');
  }

  String _absoluteAvatarUrl(String value) {
    if (value.isEmpty || value.startsWith('http')) return value;
    final baseUrl = apiClient.options.baseUrl;
    return baseUrl + (value.startsWith('/') ? '' : '/') + value;
  }

  Widget _buildPartyPresenceStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.45)),
        ),
      ),
      child: SizedBox(
        height: 91,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _partyUsers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            final user = _partyUsers[index];
            final nickname = user['nickname']?.toString().trim() ?? '';
            final avatarUrl = _absoluteAvatarUrl(
              user['avatarUrl']?.toString().trim() ?? '',
            );
            return Semantics(
              button: true,
              label: '${nickname.isEmpty ? '好友' : nickname}正在派对，点击进入',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openParty(user),
                child: SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF328DF4),
                            ),
                            child: CircleAvatar(
                              backgroundColor: AppColors.primaryLight,
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Text(
                                      nickname.isNotEmpty ? nickname[0] : '?',
                                      style: AppTextStyles.titleMedium.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            left: 3,
                            right: 3,
                            bottom: -6,
                            child: Container(
                              height: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF328DF4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: const Text(
                                '在派对中',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        nickname.isEmpty ? '好友' : nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refreshLocal() async {
    await _loadLocal(refresh: true);
  }

  Future<void> _refreshRecommend() async {
    await Future.wait([_loadRecommend(refresh: true), _loadRecommendTeams()]);
  }

  Future<_FeedFetchResult> _fetchFeed(
    String tab,
    List<Map<String, dynamic>> list,
    VoidCallback onPageInc,
    int page,
    bool Function() isCurrent,
  ) async {
    try {
      final query = <String, dynamic>{
        'tab': tab,
        'page': page,
        'page_size': 20,
      };
      if (tab == 'local' &&
          !_localUseAutoLocation &&
          _localManualLocation.trim().isNotEmpty) {
        query['location'] = _localManualLocation.trim();
      }
      final res = await apiClient.get(
        '/api/community/feed',
        queryParameters: query,
      );
      if (!isCurrent()) return const _FeedFetchResult(hasMore: false);
      final data = imResponseData(res.data);
      final items = imResponseList(data);
      if (items.any((item) => item['id'] is! num)) {
        throw const FormatException('作品数据不完整');
      }
      final previous = {for (final item in list) item['id']: item};
      final nextItems = [
        for (final item in items)
          reuseLoadedPostMedia(previous[item['id']], item),
      ];
      setState(() {
        if (page == 1) list.clear();
        for (final item in nextItems) {
          if (!list.any((existing) => existing['id'] == item['id'])) {
            list.add(item);
          }
        }
      });
      if (items.isNotEmpty) onPageInc();
      _feedUpdatedAt[tab] = DateTime.now();
      unawaited(_warmImages(nextItems));
      final hasMore =
          items.isNotEmpty &&
          (data['hasMore'] is bool
              ? data['hasMore'] == true
              : items.length >= 20);
      return _FeedFetchResult(
        hasMore: hasMore,
        resolvedLocation: data['resolvedLocation']?.toString().trim() ?? '',
      );
    } on DioException catch (error) {
      if (isCurrent() && {401, 403, 404}.contains(error.response?.statusCode)) {
        setState(list.clear);
      }
      return _FeedFetchResult(
        hasMore: false,
        error: error.response?.statusCode == 401
            ? '登录状态已过期，请重新登录'
            : '内容加载失败，请检查网络后重试',
      );
    } catch (error) {
      if (isCurrent() && {401, 403, 404}.contains(imFailureStatus(error))) {
        setState(list.clear);
      }
      return const _FeedFetchResult(hasMore: false, error: '内容加载失败，请稍后重试');
    }
  }

  Future<void> _setLocalAutoLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localUseAutoKey, true);
    if (!mounted) return;
    setState(() {
      _localUseAutoLocation = true;
      _localFeed.clear();
    });
    await _refreshLocal();
  }

  Future<void> _setLocalManualLocation(String location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localUseAutoKey, false);
    await prefs.setString(_localManualLocationKey, location);
    if (!mounted) return;
    setState(() {
      _localUseAutoLocation = false;
      _localManualLocation = location;
      _localFeed.clear();
    });
    await _refreshLocal();
  }

  Future<void> _setLocalManualRegion(Region region) async {
    final location = region.extPath.trim().isNotEmpty
        ? region.extPath.trim()
        : region.name.trim();
    await _setLocalManualLocation(location);
  }

  static const _hotCities = [
    '北京',
    '上海',
    '广州',
    '深圳',
    '成都',
    '重庆',
    '武汉',
    '西安',
    '南京',
    '郑州',
    '长沙',
    '济南',
    '杭州',
    '苏州',
    '天津',
    '青岛',
    '福州',
    '厦门',
    '合肥',
    '南昌',
    '贵阳',
    '南宁',
    '昆明',
    '沈阳',
    '太原',
    '石家庄',
    '哈尔滨',
    '长春',
    '海口',
    '兰州',
  ];

  Future<void> _showLocalLocationOptions() async {
    final location = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '选择同城地区',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(ctx).bottom + 20,
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '选择所在地',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _hotCities.map((c) {
                          final selected =
                              !_localUseAutoLocation &&
                              _localManualLocation == c;
                          return GestureDetector(
                            onTap: () => Navigator.pop(ctx, c),
                            child: Container(
                              width: (MediaQuery.of(ctx).size.width - 72) / 4,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary.withValues(alpha: 0.4)
                                      : AppColors.divider.withValues(
                                          alpha: 0.6,
                                        ),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, '__other__'),
                        icon: const Icon(Icons.map_outlined, size: 19),
                        label: const Text('选择其它所在地（省 / 市 / 区县）'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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
    if (!mounted || location == null) return;
    if (location == '__auto__') {
      await _setLocalAutoLocation();
    } else if (location == '__other__') {
      await BirthPlacePickerSheet.show(
        context,
        title: '选择同城地区',
        initialRegion: _localManualLocation.trim().isEmpty
            ? null
            : Region.placeholder(
                name: _localManualLocation.split(RegExp(r'\s+')).last,
                extPath: _localManualLocation,
              ),
        onConfirm: _setLocalManualRegion,
      );
    } else {
      await _setLocalManualLocation(location);
    }
  }

  Widget _buildLocalFeed() {
    return _FeedList(
      list: _localFeed,
      loading: _loadingLocal,
      error: _localError,
      onRefresh: _refreshLocal,
      onRetry: _refreshLocal,
      onLoadMore: _loadLocal,
      onLike: (id) => _handleLike(_localFeed, id),
      onFollow: _handleFollow,
      onFavorite: (id) => _handleFavorite(_localFeed, id),
      onShare: (id) => _handleShare(_localFeed, id),
      onNotInterested: (id) => _handleNotInterested(_localFeed, id),
      emptyTitle: '暂无同城内容',
      emptySubtitle: '换个地区看看，或下拉刷新',
      currentUserId: _currentUserId,
      onDeleted: (postId) => setState(
        () =>
            _localFeed.removeWhere((e) => (e['id'] as num?)?.toInt() == postId),
      ),
    );
  }

  Future<void> _handleLike(List<Map<String, dynamic>> list, int postId) async {
    final index = list.indexWhere(
      (item) => (item['id'] as num?)?.toInt() == postId,
    );
    if (index < 0) return;
    final wasLiked = list[index]['liked'] == true;
    final previousCount = (list[index]['likeCount'] as num?)?.toInt() ?? 0;
    setState(() {
      list[index]['liked'] = !wasLiked;
      list[index]['likeCount'] = (previousCount + (wasLiked ? -1 : 1)).clamp(
        0,
        1 << 31,
      );
    });
    try {
      final res = await apiClient.post('/api/community/post/$postId/like');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final i = list.indexWhere(
            (e) => (e['id'] as num?)?.toInt() == postId,
          );
          if (i >= 0) {
            list[i]['liked'] = data['liked'] == true;
            list[i]['likeCount'] = data['likeCount'];
          }
        });
      }
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() {
        final currentIndex = list.indexWhere(
          (item) => (item['id'] as num?)?.toInt() == postId,
        );
        if (currentIndex >= 0) {
          list[currentIndex]['liked'] = wasLiked;
          list[currentIndex]['likeCount'] = previousCount;
        }
      });
      showAppToast(context, '点赞失败，请重试');
    }
  }

  Future<void> _handleFollow(int userId) async {
    Map<String, dynamic>? reference;
    for (final feed in [_followFeed, _recommendFeed, _localFeed]) {
      for (final post in feed) {
        if ((post['userId'] as num?)?.toInt() == userId) {
          reference = post;
          break;
        }
      }
      if (reference != null) break;
    }
    final wasFollowing = reference?['following'] == true;
    if (wasFollowing) {
      final confirmed = await confirmUnfollow(
        context,
        nickname: reference?['nickname']?.toString() ?? 'TA',
      );
      if (!confirmed || !mounted) return;
    }

    void syncFollowing(bool value) {
      for (final feed in [_followFeed, _recommendFeed, _localFeed]) {
        for (final post in feed) {
          if ((post['userId'] as num?)?.toInt() == userId) {
            post['following'] = value;
          }
        }
      }
    }

    setState(() => syncFollowing(!wasFollowing));
    try {
      final res = await apiClient.post('/api/community/user/$userId/follow');
      final data = (res.data as Map?)?['data'] as Map?;
      final following = data?['following'] == true;
      if (!mounted) return;
      setState(() => syncFollowing(following));
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() => syncFollowing(wasFollowing));
      showAppToast(context, wasFollowing ? '取消关注失败' : '关注操作失败');
    }
  }

  Future<void> _handleFavorite(
    List<Map<String, dynamic>> list,
    int postId,
  ) async {
    try {
      final res = await apiClient.post('/api/community/post/$postId/favorite');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final i = list.indexWhere(
            (e) => (e['id'] as num?)?.toInt() == postId,
          );
          if (i >= 0) list[i]['favorited'] = data['favorited'] == true;
        });
      }
    } on DioException catch (_) {}
  }

  void _handleShare(List<Map<String, dynamic>> list, int postId) {
    Map<String, dynamic>? item;
    for (final e in list) {
      if ((e['id'] as num?)?.toInt() == postId) {
        item = e;
        break;
      }
    }
    if (item == null) return;
    showSharePostSheet(
      context,
      item,
      onShared: (count) {
        if (count != null && mounted) {
          setState(() {
            final i = list.indexWhere(
              (e) => (e['id'] as num?)?.toInt() == postId,
            );
            if (i >= 0) list[i]['shareCount'] = count;
          });
        }
      },
    );
  }

  Future<void> _handleNotInterested(
    List<Map<String, dynamic>> list,
    int postId,
  ) async {
    final reason = await showNotInterestedReasonSheet(context);
    if (reason == null || !mounted) return;
    final index = list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
    if (index < 0) return;
    final removed = list[index];
    var undone = false;
    var persisted = false;
    setState(() => list.removeAt(index));

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('已减少类似内容 · ${reason.label}'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF303236),
        action: SnackBarAction(
          label: '撤销',
          textColor: AppColors.communityAccent,
          onPressed: () async {
            if (!mounted || undone) return;
            undone = true;
            setState(() => list.insert(index.clamp(0, list.length), removed));
            if (persisted) {
              try {
                await apiClient.delete(
                  '/api/community/post/$postId/not-interested',
                );
              } catch (_) {
                // 列表已经恢复；下次刷新时仍以服务端结果为准。
              }
            }
          },
        ),
      ),
    );
    try {
      await apiClient.post(
        '/api/community/post/$postId/not-interested',
        data: {'reasonCode': reason.code},
      );
      persisted = true;
      if (undone) {
        await apiClient.delete('/api/community/post/$postId/not-interested');
      }
    } catch (_) {
      if (!mounted || undone) return;
      setState(() => list.insert(index.clamp(0, list.length), removed));
      messenger?.hideCurrentSnackBar();
      showAppToast(context, '设置失败，内容已恢复');
    }
  }

  void _onRecommendTeamTap(Map<String, dynamic> t) {
    final id = (t['conversationId'] as num?)?.toInt();
    if (id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamHomePage(
            conversationId: id,
            initialName: t['name'] as String? ?? '部落',
            initialTitle: (t['title'] as String?)?.trim(),
            initialMemberCount: (t['memberCount'] as num?)?.toInt(),
            initialMaxMembers: (t['maxMembers'] as num?)?.toInt(),
          ),
        ),
      );
      return;
    }
    final name = t['name'] as String? ?? '部落';
    final title = (t['title'] as String?)?.trim() ?? '';
    final memberCount = (t['memberCount'] as num?)?.toInt() ?? 0;
    final maxMembers = (t['maxMembers'] as num?)?.toInt() ?? 500;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24 + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.accentGold.withValues(alpha: 0.25),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: AppTextStyles.titleMedium)),
              ],
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '头衔：$title',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '$memberCount / $maxMembers 人',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '申请通过后同时加入部落与部落群，与加入公开群流程相同。',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: id == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        await apiClient.post('/api/im/group/$id/apply');
                        if (!mounted) return;
                        showAppToast(context, '已提交申请');
                        await _loadRecommendTeams();
                      } on DioException catch (e) {
                        if (!mounted) return;
                        final msg =
                            (e.response?.data is Map &&
                                (e.response!.data as Map).containsKey(
                                  'message',
                                ))
                            ? (e.response!.data as Map)['message']?.toString()
                            : null;
                        showAppToast(context, msg ?? '操作失败');
                      }
                    },
              child: const Text('申请加入'),
            ),
          ],
        ),
      ),
    );
  }

  void refreshFeed() {
    _refreshRecommend();
    _refreshFollow();
    _refreshLocal();
  }

  /// Reuse the startup load on tab switches; refresh only the visible stale tab.
  void refreshIfStale() {
    final tab = ['following', 'recommend', 'local'][_tabController.index];
    final updated = _feedUpdatedAt[tab];
    if (updated != null &&
        DateTime.now().difference(updated) < const Duration(minutes: 1)) {
      return;
    }
    switch (_tabController.index) {
      case 0:
        if (!_loadingFollow) _refreshFollow();
      case 1:
        if (!_loadingRecommend) _refreshRecommend();
      case 2:
        if (!_loadingLocal) _refreshLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 54,
        centerTitle: true,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: TabBar(
          controller: _tabController,
          onTap: (index) {
            if (index == 2) _showLocalLocationOptions();
          },
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTextStyles.bodyMedium.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: AppTextStyles.bodySmall.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.communityAccent, width: 3),
            insets: EdgeInsets.symmetric(horizontal: 20),
          ),
          dividerColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          tabs: const [
            Tab(text: '关注'),
            Tab(text: '推荐'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('同城'),
                  SizedBox(width: 1),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: AppColors.textPrimary,
              size: 23,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CommunitySearchPage()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ColoredBox(
        color: Colors.white,
        child: TabBarView(
          controller: _tabController,
          children: [
            _FeedList(
              list: _followFeed,
              header: _partyUsers.isEmpty ? null : _buildPartyPresenceStrip(),
              loading: _loadingFollow,
              error: _followError,
              onRefresh: _refreshFollow,
              onRetry: _refreshFollow,
              onLoadMore: _loadFollow,
              onLike: (id) => _handleLike(_followFeed, id),
              onFollow: _handleFollow,
              onFavorite: (id) => _handleFavorite(_followFeed, id),
              onShare: (id) => _handleShare(_followFeed, id),
              onNotInterested: (id) => _handleNotInterested(_followFeed, id),
              emptyTitle: '暂无关注动态',
              emptySubtitle: '关注更多用户后，这里会更热闹',
              currentUserId: _currentUserId,
              onDeleted: (postId) => setState(
                () => _followFeed.removeWhere(
                  (e) => (e['id'] as num?)?.toInt() == postId,
                ),
              ),
            ),
            _RecommendFeedList(
              list: _recommendFeed,
              teams: _recommendTeams,
              showTeams: _showRecommendTeams,
              loading: _loadingRecommend,
              error: _recommendError,
              onRefresh: _refreshRecommend,
              onRetry: _refreshRecommend,
              onLoadMore: _loadRecommend,
              onLike: (id) => _handleLike(_recommendFeed, id),
              onFollow: _handleFollow,
              onFavorite: (id) => _handleFavorite(_recommendFeed, id),
              onShare: (id) => _handleShare(_recommendFeed, id),
              onNotInterested: (id) => _handleNotInterested(_recommendFeed, id),
              currentUserId: _currentUserId,
              onDeleted: (postId) => setState(
                () => _recommendFeed.removeWhere(
                  (e) => (e['id'] as num?)?.toInt() == postId,
                ),
              ),
              onTeamTap: _onRecommendTeamTap,
              onCloseTeams: () => setState(() => _showRecommendTeams = false),
            ),
            _buildLocalFeed(),
          ],
        ),
      ),
    );
  }
}

/// 推荐 Tab：顶部横向推荐部落 + 帖子列表。
class _RecommendFeedList extends StatelessWidget {
  const _RecommendFeedList({
    required this.list,
    required this.teams,
    required this.showTeams,
    required this.loading,
    this.error,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
    required this.onLike,
    required this.onFollow,
    required this.onFavorite,
    required this.onShare,
    required this.onNotInterested,
    required this.onTeamTap,
    required this.onCloseTeams,
    this.currentUserId,
    this.onDeleted,
  });

  final List<Map<String, dynamic>> list;
  final List<Map<String, dynamic>> teams;
  final bool showTeams;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final void Function(int postId) onLike;
  final void Function(int userId) onFollow;
  final void Function(int postId) onFavorite;
  final void Function(int postId) onShare;
  final void Function(int postId) onNotInterested;
  final void Function(Map<String, dynamic> t) onTeamTap;
  final VoidCallback onCloseTeams;
  final int? currentUserId;
  final void Function(int postId)? onDeleted;

  @override
  Widget build(BuildContext context) {
    final hasTeams = showTeams && teams.isNotEmpty;
    final hasStrip = hasTeams;

    if (list.isEmpty && !loading && !hasStrip) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: error == null
                ? const _CommunityEmptyState(
                    icon: Icons.forum_outlined,
                    title: '暂无内容',
                    subtitle: '下拉刷新试试，或稍后再来看看',
                  )
                : _CommunityErrorState(message: error!, onRetry: onRetry),
          ),
        ),
      );
    }

    if (list.isEmpty && loading && !hasStrip) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        color: AppColors.primary,
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _CommunityLoadingState(label: '正在加载推荐内容...'),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 320 && !loading) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        displacement: 20,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (hasTeams)
              SliverToBoxAdapter(
                child: _RecommendCirclesRow(
                  teams: teams,
                  onTeamTap: onTeamTap,
                  onClose: onCloseTeams,
                ),
              ),
            if (list.isEmpty && !loading && hasStrip)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: error == null
                        ? Center(
                            child: Text(
                              '推荐内容已更新，动态暂时为空',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textHint,
                              ),
                            ),
                          )
                        : _CommunityErrorState(
                            message: error!,
                            onRetry: onRetry,
                            compact: true,
                          ),
                  ),
                ),
              ),
            if (list.isEmpty && loading && hasStrip)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return PostCard(
                    key: ValueKey('community-post-${list[index]['id']}'),
                    item: list[index],
                    heroTagSuffix: 'rec_$index',
                    integrated: true,
                    showBottomDivider: true,
                    showPrivateAction: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailPage(
                          postId: list[index]['id'] as int,
                          initialItem: list[index],
                        ),
                      ),
                    ),
                    onTopicTap: (id, name) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TopicFeedPage(topicId: id, topicName: name),
                      ),
                    ),
                    onLike: onLike,
                    onFollow: onFollow,
                    onFavorite: onFavorite,
                    onShare: onShare,
                    onNotInterested: onNotInterested,
                    currentUserId: currentUserId,
                    onDeleted: onDeleted,
                  );
                }, childCount: list.length),
              ),
            ),
            if (loading && list.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (!loading && list.isNotEmpty && error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _CommunityErrorState(
                    message: error!,
                    onRetry: onRetry,
                    compact: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecommendCirclesRow extends StatelessWidget {
  const _RecommendCirclesRow({
    required this.teams,
    required this.onTeamTap,
    required this.onClose,
  });

  final List<Map<String, dynamic>> teams;
  final void Function(Map<String, dynamic> t) onTeamTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGold.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '推荐部落',
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        splashRadius: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '发现感兴趣的主题部落',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 112,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                scrollDirection: Axis.horizontal,
                itemCount: teams.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = teams[index];
                  final name = item['name'] as String? ?? '部落';
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTeamTap(item),
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 92,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.accentGold.withValues(
                                alpha: 0.18,
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                color: AppColors.accentGold,
                                size: 25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '部落',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontSize: 10,
                                color: AppColors.textHint,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.list,
    this.header,
    required this.loading,
    this.error,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
    required this.onLike,
    required this.onFollow,
    required this.onFavorite,
    required this.onShare,
    required this.onNotInterested,
    this.emptyTitle = '暂无动态',
    this.emptySubtitle = '关注更多用户后，这里会更热闹',
    this.currentUserId,
    this.onDeleted,
  });
  final List<Map<String, dynamic>> list;
  final Widget? header;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final void Function(int postId) onLike;
  final void Function(int userId) onFollow;
  final void Function(int postId) onFavorite;
  final void Function(int postId) onShare;
  final void Function(int postId) onNotInterested;
  final String emptyTitle;
  final String emptySubtitle;
  final int? currentUserId;
  final void Function(int postId)? onDeleted;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty && !loading) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              if (header != null) header!,
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: error == null
                    ? _CommunityEmptyState(
                        icon: Icons.dynamic_feed_outlined,
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                      )
                    : _CommunityErrorState(message: error!, onRetry: onRetry),
              ),
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 320 && !loading) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        displacement: 20,
        color: AppColors.primary,
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          itemCount:
              list.length +
              (header == null ? 0 : 1) +
              (loading || error != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (header != null && index == 0) return header!;
            final listIndex = index - (header == null ? 0 : 1);
            if (listIndex == list.length) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: error == null
                    ? const Center(
                        child: _CommunityLoadingState(label: '正在加载更多...'),
                      )
                    : _CommunityErrorState(
                        message: error!,
                        onRetry: onRetry,
                        compact: true,
                      ),
              );
            }
            return PostCard(
              key: ValueKey('community-post-${list[listIndex]['id']}'),
              item: list[listIndex],
              heroTagSuffix: 'list_$listIndex',
              integrated: true,
              showBottomDivider: true,
              showPrivateAction: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostDetailPage(
                    postId: list[listIndex]['id'] as int,
                    initialItem: list[listIndex],
                  ),
                ),
              ),
              onTopicTap: (id, name) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopicFeedPage(topicId: id, topicName: name),
                ),
              ),
              onLike: onLike,
              onFollow: onFollow,
              onFavorite: onFavorite,
              onShare: onShare,
              onNotInterested: onNotInterested,
              currentUserId: currentUserId,
              onDeleted: onDeleted,
            );
          },
        ),
      ),
    );
  }
}

class _FeedFetchResult {
  const _FeedFetchResult({
    required this.hasMore,
    this.error,
    this.resolvedLocation = '',
  });

  final bool hasMore;
  final String? error;
  final String resolvedLocation;
}

class _CommunityErrorState extends StatelessWidget {
  const _CommunityErrorState({
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: compact ? 28 : 52,
              color: AppColors.textHint.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityEmptyState extends StatelessWidget {
  const _CommunityEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 72,
            color: AppColors.textHint.withValues(alpha: 0.32),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

class _CommunityLoadingState extends StatelessWidget {
  const _CommunityLoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
        ),
      ],
    );
  }
}
