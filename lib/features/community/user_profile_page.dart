import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/community_feedback.dart';
import '../../core/utils/profile_share.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../message/chat_page.dart';
import '../profile/profile_background_artwork.dart';
import '../profile/profile_background_presets.dart';
import 'post_detail_page.dart';
import 'post_card.dart';
import 'profile_post_feed.dart';
import 'community_online_indicator.dart';
import 'team_title_chip.dart';
import 'user_relationship_settings.dart';

/// 用户公开主页：精修国风版（强化作品边框）
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.userId});

  final int userId;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _user;
  late final _postFeed =
      ProfilePostFeed(() => '/api/community/user/${widget.userId}/posts');
  late final _favoriteFeed =
      ProfilePostFeed(() => _isSelf ? '/api/community/favorites' : null);
  List<Map<String, dynamic>> get _posts => _postFeed.items;
  List<Map<String, dynamic>> get _favorites => _favoriteFeed.items;
  bool get _loadingPosts => _postFeed.loading;
  bool get _loadingFavorites => _favoriteFeed.loading;
  bool get _favoritesLoaded => _favoriteFeed.loaded;
  bool _loadingUser = true;
  bool _loadingIdentity = true;
  String? _userError;
  int _userGeneration = 0;
  bool _relationshipBusy = false;
  bool _openingChat = false;
  final _likingPosts = <int>{};
  int? _currentUserId;
  int _profileTabIndex = 0;
  late final AnimationController _backgroundRevealController;
  final ScrollController _profileScrollController = ScrollController();
  double? _revealDragStartY;
  double _revealDragStartValue = 0;
  double _revealDragDelta = 0;
  bool _consumeRevealGesture = false;
  bool _revealDragCanExpand = false;
  double? _revealCollapsedPointerY;
  bool _limitRevealHandoffFling = false;
  final List<double> _tabScrollOffsets = [0, 0];

  static const double _revealCollapseHandoffDistance = 32;

  /// 避免 ip 刷新失败时在同一会话内反复请求
  bool _ipLocationRefreshAttempted = false;

  /// 主页背景点赞
  bool _homepageLiked = false;
  int _homepageLikeCount = 0;
  bool _togglingHomepageLike = false;

  static const _locationStubs = {'未知', '本地', '内网'};

  bool get _isSelf => _currentUserId != null && _currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    _backgroundRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _profileScrollController.addListener(_onProfileScroll);
    _postFeed.addListener(_feedChanged);
    _favoriteFeed.addListener(_feedChanged);
    apiSessionChanges.addListener(_onSessionChanged);
    _loadCurrentUserId();
    _loadUser();
    _loadPosts();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _postFeed.dispose();
    _favoriteFeed.dispose();
    _profileScrollController.removeListener(_onProfileScroll);
    _backgroundRevealController.dispose();
    _profileScrollController.dispose();
    super.dispose();
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UserProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _postFeed.reset();
      _favoriteFeed.reset();
      _onSessionChanged();
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _userGeneration++;
    setState(() {
      _user = null;
      _currentUserId = null;
      _userError = null;
      _loadingUser = true;
      _loadingIdentity = true;
      _profileTabIndex = 0;
      _tabScrollOffsets.fillRange(0, 2, 0);
      _relationshipBusy = false;
      _openingChat = false;
      _togglingHomepageLike = false;
      _likingPosts.clear();
      _homepageLiked = false;
      _homepageLikeCount = 0;
      _ipLocationRefreshAttempted = false;
    });
    _loadCurrentUserId();
    _loadUser();
    _postFeed.refresh();
  }

  Future<void> _refreshProfile() async {
    await Future.wait([
      if (!_relationshipBusy) _loadUser(skipRegionRefresh: true),
      _postFeed.refresh(),
      if (_isSelf && _favoritesLoaded) _favoriteFeed.refresh(),
    ]);
  }

  void _handleRevealPointerDown(PointerDownEvent event) {
    _revealCollapsedPointerY = null;
    _limitRevealHandoffFling = false;
    if (!_profileScrollController.hasClients ||
        _profileScrollController.position.pixels <= 0.5) {
      _revealDragStartY = event.position.dy;
      _revealDragStartValue = _backgroundRevealController.value;
      _revealDragDelta = 0;
      _consumeRevealGesture = _backgroundRevealController.value > 0.001;
      _revealDragCanExpand = !_profileScrollController.hasClients ||
          _profileScrollController.position.pixels <=
              _profileScrollController.position.minScrollExtent + 0.5;
      _backgroundRevealController.stop();
    }
  }

  void _handleRevealPointerMove(PointerMoveEvent event) {
    final startY = _revealDragStartY;
    if (startY == null) return;
    final delta = event.position.dy - startY;
    _revealDragDelta = delta;
    if (_revealDragStartValue == 0 && (delta < 0 || !_revealDragCanExpand)) {
      return;
    }
    if (delta > 0 || _revealDragStartValue > 0) {
      _consumeRevealGesture = true;
    }
    _backgroundRevealController.value =
        (_revealDragStartValue + delta / 300).clamp(0.0, 1.0);
    // 背景完全收起后先在资料卡/标签栏的归位点吸附一小段，
    // 然后再把持续上滑交给作品列表，避免同一次惯性直接冲进作品。
    if (_backgroundRevealController.value <= 0.001 && delta < 0) {
      _revealCollapsedPointerY ??= event.position.dy;
      final handoffDistance = _revealCollapsedPointerY! - event.position.dy;
      if (handoffDistance >= _revealCollapseHandoffDistance) {
        _consumeRevealGesture = false;
        _limitRevealHandoffFling = true;
      }
    } else {
      _revealCollapsedPointerY = null;
    }
  }

  void _finishRevealDrag() {
    if (_revealDragStartY == null) return;
    _revealDragStartY = null;
    final expand = _revealDragDelta.abs() >= 18
        ? _revealDragDelta > 0
        : _backgroundRevealController.value >= 0.5;
    _backgroundRevealController.animateTo(
      expand ? 1 : 0,
      curve: Curves.easeOutCubic,
    );
    _consumeRevealGesture = false;
    _revealCollapsedPointerY = null;
    if (_limitRevealHandoffFling) {
      // Scrollable 在同一帧创建惯性模拟，下一帧再解除限速。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _limitRevealHandoffFling = false;
      });
    }
  }

  void _onProfileScroll() {
    if (!_profileScrollController.hasClients) return;
    final metrics = _profileScrollController.position;
    if (metrics.extentAfter >= 360) return;
    if (_profileTabIndex == 1) {
      _loadFavorites();
    } else {
      _loadPosts();
    }
  }

  void _switchProfileTab(int index) {
    if (index == _profileTabIndex) return;
    if (index == 1 && !_isSelf) {
      showAppToast(context, '对方的收藏仅自己可见');
      return;
    }
    if (_profileScrollController.hasClients) {
      _tabScrollOffsets[_profileTabIndex] = _profileScrollController.offset;
    }
    setState(() => _profileTabIndex = index);
    if (index == 1 && !_favoritesLoaded) _loadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          index != _profileTabIndex ||
          !_profileScrollController.hasClients) {
        return;
      }
      final position = _profileScrollController.position;
      final target = _tabScrollOffsets[index]
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _profileScrollController.jumpTo(target);
    });
  }

  Future<void> _loadCurrentUserId() async {
    final session = apiSessionChanges.value;
    final prefs = await SharedPreferences.getInstance();
    if (mounted && session == apiSessionChanges.value) {
      setState(() {
        _currentUserId = apiClient.options.headers['Authorization'] == null
            ? null
            : prefs.getInt(AppConstants.keyUserId);
        _loadingIdentity = false;
      });
    }
  }

  bool _isStubLocation(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty || _locationStubs.contains(t);
  }

  /// 与 [MainShellPage._updateLocationOnOpen] 一致：本人资料为占位时尝试用当前 IP 归属地写回后端再刷新
  Future<void> _tryRefreshIpLocationIfSelfAndStub() async {
    if (!mounted || _user == null || _ipLocationRefreshAttempted) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final options = _sessionOptions();
    if (_currentUserId == null) await _loadCurrentUserId();
    if (!mounted ||
        !_sameProfile(session, userId) ||
        !_isSelf ||
        _user == null) {
      return;
    }
    final loc = (_user!['locationCode'] as String?)?.trim() ??
        (_user!['location'] as String?)?.trim();
    if (!_isStubLocation(loc)) return;
    _ipLocationRefreshAttempted = true;
    try {
      final res =
          await apiClient.get('/api/config/ipLocation', options: options);
      if (!mounted || !_sameProfile(session, userId)) return;
      final d = _responseData(res.data);
      final newLoc = (d['location'] as String?)?.trim();
      if (newLoc == null || newLoc.isEmpty || _locationStubs.contains(newLoc)) {
        return;
      }
      await apiClient.post('/api/auth/location',
          data: {'locationCode': newLoc}, options: options);
      if (mounted && _sameProfile(session, userId)) {
        await _loadUser(skipRegionRefresh: true);
      }
    } catch (_) {
      // 归属地补全不影响资料展示，也不在失败后循环写入。
    }
  }

  bool _sameProfile(int session, int userId) =>
      mounted && session == apiSessionChanges.value && userId == widget.userId;

  Options _sessionOptions() => Options(
      headers: {'Authorization': apiClient.options.headers['Authorization']});

  Map _responseData(dynamic body) {
    if (body is! Map ||
        (body['code'] != null && body['code'] != 0) ||
        body['data'] is! Map) {
      throw const FormatException('操作结果无效');
    }
    return body['data'] as Map;
  }

  bool _beginRelationshipChange() {
    if (_relationshipBusy || _isSelf || _user == null) return false;
    // 废弃操作前发出的资料请求，防止迟到的 following 覆盖操作结果。
    _userGeneration++;
    setState(() {
      _relationshipBusy = true;
      _loadingUser = false;
    });
    return true;
  }

  Future<void> _loadUser({bool skipRegionRefresh = false}) async {
    final generation = ++_userGeneration;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    bool current() =>
        mounted &&
        session == apiSessionChanges.value &&
        generation == _userGeneration &&
        userId == widget.userId;
    setState(() {
      _loadingUser = true;
      _userError = null;
    });
    var ok = false;
    try {
      final res = await apiClient.get('/api/community/user/$userId/profile',
          options: Options(headers: {
            'Authorization': apiClient.options.headers['Authorization']
          }));
      if (!current()) return;
      final body = res.data;
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          body['data'] is! Map) {
        throw const FormatException('资料返回无效');
      }
      setState(() => _user = Map<String, dynamic>.from(body['data'] as Map));
      _loadHomepageLikeState();
      ok = true;
    } catch (error) {
      if (!current()) return;
      final status = error is DioException ? error.response?.statusCode : null;
      setState(() {
        _userError = status == 404
            ? '用户不存在'
            : status == 403
                ? '暂时无法查看该用户'
                : '资料加载失败，请重试';
        if (status == 403 || status == 404) _user = null;
      });
      if (status == 403 || status == 404) {
        _postFeed.reset();
        _favoriteFeed.reset();
      }
    } finally {
      if (current()) setState(() => _loadingUser = false);
    }
    if (current() && ok && !skipRegionRefresh) {
      await _tryRefreshIpLocationIfSelfAndStub();
    }
  }

  Future<void> _loadPosts() => _postFeed.load();
  Future<void> _loadFavorites() => _favoriteFeed.load();

  Future<void> _openChat() async {
    if (_openingChat || _user == null || _isSelf) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final user = Map<String, dynamic>.from(_user!);
    setState(() => _openingChat = true);
    try {
      final res = await apiClient.post('/api/im/conversation/single',
          data: {'targetUserId': userId}, options: _sessionOptions());
      if (!mounted || !_sameProfile(session, userId)) return;
      final data = _responseData(res.data);
      final convId = (data['conversationId'] as num?)?.toInt();
      if (convId == null || convId <= 0) throw const FormatException('会话无效');
      final remark = (user['remark'] as String?)?.trim() ?? '';
      final title = remark.isNotEmpty
          ? remark
          : (data['title'] as String? ?? user['nickname'] as String? ?? '用户');
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatPage(
            conversationId: convId,
            title: title,
            conversationType: 'single',
            peerUserId: userId),
      ));
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, '无法发起聊天，请重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) {
        setState(() => _openingChat = false);
      }
    }
  }

  Future<void> _openRemarkSettings() async {
    if (_isSelf || _user == null) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            UserRemarkPage(userId: widget.userId, initialData: _user!),
      ),
    );
    if (!mounted ||
        !_sameProfile(session, userId) ||
        _user == null ||
        result == null) {
      return;
    }
    final remark = result['remark']?.toString().trim() ?? '';
    setState(() {
      _user!.addAll(result);
      _user!['displayName'] =
          remark.isNotEmpty ? remark : (_user!['nickname'] as String? ?? '用户');
    });
    showAppToast(context, '备注和描述已保存');
  }

  Future<void> _openStealthSettings() async {
    if (_user == null) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final result = await showUserStealthSettingsSheet(
      context,
      userId: widget.userId,
      initialData: _user!,
    );
    if (!mounted ||
        !_sameProfile(session, userId) ||
        _user == null ||
        result == null) {
      return;
    }
    setState(() => _user!.addAll(result));
    showAppToast(context, '隐身访问设置已保存');
  }

  Future<void> _toggleQuietFollow() async {
    if (_user == null) return;
    final enabled = _user!['quietFollow'] != true;
    await _updateRelationshipPreference(
      'quietFollow',
      enabled,
      enabled ? '已悄悄关注，对方不会收到通知' : '已取消悄悄关注',
    );
  }

  Future<void> _openSpecialCareSettings() async {
    if (_user == null) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SpecialCareSettingsPage(userId: widget.userId, initialData: _user!),
      ),
    );
    if (mounted && _sameProfile(session, userId)) {
      await _loadUser(skipRegionRefresh: true);
    }
  }

  Future<void> _toggleFollow() async {
    if (!_beginRelationshipChange()) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final options = _sessionOptions();
    final wasFollowing = _user!['following'] == true;
    try {
      if (wasFollowing) {
        final confirmed = await confirmUnfollow(context,
            nickname: _user!['nickname']?.toString() ?? 'TA');
        if (!confirmed || !_sameProfile(session, userId)) return;
      }
      final response = await apiClient
          .post('/api/community/user/$userId/follow', options: options);
      if (!mounted || !_sameProfile(session, userId) || _user == null) return;
      final data = _responseData(response.data);
      if (data['following'] is! bool) throw const FormatException('关注状态无效');
      setState(() {
        final following = data['following'] == true;
        _user!['following'] = following;
        _user!['mutual'] = data['mutual'] == true;
        final count = (_user!['followerCount'] as num?)?.toInt() ?? 0;
        _user!['followerCount'] = (count +
                (following == wasFollowing
                    ? 0
                    : following
                        ? 1
                        : -1))
            .clamp(0, 1 << 31);
      });
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, wasFollowing ? '取消关注失败，请重试' : '关注失败，请重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) {
        setState(() => _relationshipBusy = false);
      }
    }
  }

  Future<void> _toggleLike(int postId) async {
    if (!_likingPosts.add(postId)) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    try {
      final res = await apiClient.post('/api/community/post/$postId/like',
          options: _sessionOptions());
      if (!mounted || !_sameProfile(session, userId)) return;
      final data = _responseData(res.data);
      if (data['liked'] is! bool || data['likeCount'] is! num) {
        throw const FormatException('点赞状态无效');
      }
      setState(() {
        for (final list in [_posts, _favorites]) {
          final i =
              list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) {
            list[i]['liked'] = data['liked'];
            list[i]['likeCount'] = data['likeCount'];
          }
        }
      });
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, '点赞失败，请重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) _likingPosts.remove(postId);
    }
  }

  void _showProfileShare() {
    final user = _user;
    if (user == null) return;
    showUserProfileShareSheet(context, user);
  }

  Future<void> _updateRelationshipPreference(
      String field, bool value, String successMessage) async {
    if (!_beginRelationshipChange()) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    try {
      final response = await apiClient.patch(
          '/api/community/user/$userId/relationship-preferences',
          data: {field: value},
          options: _sessionOptions());
      if (!mounted || !_sameProfile(session, userId) || _user == null) return;
      final data = _responseData(response.data);
      if (data[field] is! bool) throw const FormatException('设置返回无效');
      setState(() {
        for (final key in const [
          'specialCare',
          'hideTargetPosts',
          'hideSelfFromTarget',
          'stealthProfile',
          'stealthMoments',
          'stealthChat',
          'quietFollow',
          'specialCareSound',
        ]) {
          if (data.containsKey(key)) _user![key] = data[key];
        }
      });
      showAppToast(context, successMessage);
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, '设置失败，请稍后重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) {
        setState(() => _relationshipBusy = false);
      }
    }
  }

  Future<void> _showProfileActions() async {
    final user = _user;
    if (user == null) return;
    if (!_isSelf) {
      showUserProfileShareSheet(
        context,
        user,
        onRemark: _openRemarkSettings,
        onStealth: _openStealthSettings,
        onQuietFollow: _toggleQuietFollow,
        onSpecialCare: _openSpecialCareSettings,
        onBlock: _confirmBlockUser,
      );
      return;
    }
    const actions = [
      _ProfileMenuAction(
        id: 'share',
        label: '分享主页',
        icon: Icons.ios_share_rounded,
        color: AppColors.primary,
      ),
      _ProfileMenuAction(
        id: 'background',
        label: '查看背景',
        icon: Icons.wallpaper_rounded,
        color: Color(0xFF6877C9),
      ),
    ];

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 15, bottom: 12),
                  child: Text(
                    '主页设置',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisExtent: 92,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: actions.length,
                  itemBuilder: (context, index) {
                    final item = actions[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(sheetContext, item.id),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(item.icon, color: item.color, size: 25),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'share':
        _showProfileShare();
        return;
      case 'background':
        _showBackgroundPreview(user['homeBackgroundUrl']?.toString());
        return;
    }
  }

  Future<void> _loadHomepageLikeState() async {
    if (_user == null) return;
    final liked = _user!['homepageLiked'] == true;
    final count = (_user!['homepageLikeCount'] as num?)?.toInt() ?? 0;
    if (mounted) {
      setState(() {
        _homepageLiked = liked;
        _homepageLikeCount = count;
      });
    }
  }

  Future<void> _toggleHomepageLike() async {
    if (_isSelf || _user == null || _togglingHomepageLike) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    setState(() => _togglingHomepageLike = true);
    try {
      final res = await apiClient.post(
          '/api/community/user/$userId/homepage-like',
          options: _sessionOptions());
      if (!mounted || !_sameProfile(session, userId)) return;
      final data = _responseData(res.data);
      if (data['liked'] is! bool || data['homepageLikeCount'] is! num) {
        throw const FormatException('点赞状态无效');
      }
      setState(() {
        _homepageLiked = data['liked'] == true;
        _homepageLikeCount = (data['homepageLikeCount'] as num).toInt();
      });
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, '点赞失败，请重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) {
        setState(() => _togglingHomepageLike = false);
      }
    }
  }

  void _showBackgroundPreview(String? bgUrl) {
    final previewAllowed = _user?['backgroundPreviewAllowed'] == null ||
        _user?['backgroundPreviewAllowed'] == true ||
        _user?['backgroundPreviewAllowed'] == 1;
    if (!_isSelf && !previewAllowed) return;
    if ((_isSelf || previewAllowed) &&
        ((bgUrl?.trim().isNotEmpty ?? false) ||
            (_user?['homeBackgroundId']?.toString() ?? '').isNotEmpty)) {
      showDialog(
        context: context,
        builder: (ctx) => Stack(
          children: [
            // Full-screen background image
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  color: Colors.black,
                  child: InteractiveViewer(
                    child: Center(
                      child: ProfileBackgroundArtwork(
                        backgroundId: _user?['homeBackgroundId']?.toString(),
                        legacyUrl: bgUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Top close button
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              left: 14,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            // Bottom "点赞" button
            Positioned(
              bottom: MediaQuery.of(ctx).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      _toggleHomepageLike();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _homepageLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: _homepageLiked
                                ? const Color(0xFFFF657F)
                                : Colors.grey.shade600,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _homepageLikeCount > 0
                                ? '$_homepageLikeCount'
                                : '点赞',
                            style: TextStyle(
                              color: _homepageLiked
                                  ? const Color(0xFFFF657F)
                                  : Colors.grey.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildBottomActions(bool following) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        6,
        18,
        5 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _bottomButton(
              label: following ? '已关注' : '关注',
              icon: const ReferenceActionGlyph(
                type: ReferenceActionIconType.follow,
                size: 17,
              ),
              onTap: _relationshipBusy ? null : _toggleFollow,
              filled: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _bottomButton(
              label: _openingChat ? '正在打开' : '私聊',
              icon: const ReferenceActionGlyph(
                type: ReferenceActionIconType.privateChat,
                size: 18,
              ),
              onTap: _openingChat ? null : _openChat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomButton({
    required String label,
    required Widget icon,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          gradient: filled ? AppColors.primaryGradient : null,
          color: filled ? null : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(999),
          border:
              filled ? null : Border.all(color: AppColors.primary, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(
                color: filled ? Colors.white : AppColors.primaryDark,
              ),
              child: icon,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.button.copyWith(
                color: filled ? Colors.white : AppColors.primaryDark,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMomentCard(Map<String, dynamic> item) {
    final postId = (item['id'] as num?)?.toInt();
    return PostCard(
      item: item,
      currentUserId: _currentUserId,
      showHeader: _profileTabIndex == 1,
      showPreciseTimestamp: _profileTabIndex == 0,
      showMoreMenu: false,
      showPrivateAction: true,
      compactLayout: true,
      onTap: postId == null
          ? null
          : () async {
              final session = apiSessionChanges.value;
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      PostDetailPage(postId: postId, initialItem: item)));
              if (mounted && session == apiSessionChanges.value) {
                await _refreshProfile();
              }
            },
      onLike: _toggleLike,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingIdentity || (_loadingUser && _user == null)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_userError ?? '资料加载失败，请重试'),
            TextButton(onPressed: _refreshProfile, child: const Text('重试加载资料')),
          ])));
    }

    final nickname = _user!['nickname'] as String? ?? '用户';
    final displayName =
        (_user!['displayName'] as String?)?.trim().isNotEmpty == true
            ? (_user!['displayName'] as String).trim()
            : nickname;
    final avatarUrl = _user!['avatarUrl'] as String?;
    final intro = _user!['intro'] as String? ?? '暂无介绍';
    final following = _user!['following'] == true;
    final g = (_user!['gender'] as num?)?.toInt();
    final genderLabel = g == 1 ? '男' : (g == 2 ? '女' : null);
    final likeCount = (_user!['likeCount'] as num?)?.toInt() ?? 0;
    final followCount = (_user!['followCount'] as num?)?.toInt() ?? 0;
    final followerCount = (_user!['followerCount'] as num?)?.toInt() ?? 0;
    final teamTitle = (_user!['teamTitle'] as String?)?.trim() ?? '';
    final activeFeed = _profileTabIndex == 1 ? _favoriteFeed : _postFeed;
    final activeList = activeFeed.items;
    final activeLoading =
        _profileTabIndex == 1 ? _loadingFavorites : _loadingPosts;
    final activeEmptyTitle = switch (_profileTabIndex) {
      0 => '暂无作品发布',
      _ => '暂无收藏',
    };
    final activeEmptyIcon = switch (_profileTabIndex) {
      0 => Icons.style_outlined,
      1 => Icons.bookmark_border_rounded,
      _ => Icons.favorite_border_rounded,
    };

    return Scaffold(
      backgroundColor: AppColors.communityScaffold,
      bottomNavigationBar: _isSelf ? null : _buildBottomActions(following),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleRevealPointerDown,
        onPointerMove: _handleRevealPointerMove,
        onPointerUp: (_) => _finishRevealDrag(),
        onPointerCancel: (_) => _finishRevealDrag(),
        child: CustomScrollView(
          controller: _profileScrollController,
          physics: _ProfileRevealScrollPhysics(
            shouldLock: () =>
                _consumeRevealGesture ||
                _backgroundRevealController.value > 0.001,
            shouldLimitFling: () => _limitRevealHandoffFling,
            parent: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(
                displayName,
                nickname,
                avatarUrl,
                intro,
                likeCount,
                followCount,
                followerCount,
                genderLabel,
                _user?['locationCode'] as String? ??
                    _user?['location'] as String?,
                teamTitle,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProfileTabsHeaderDelegate(
                height: 46,
                child: _buildProfileTabs(),
              ),
            ),
            if (_userError != null)
              SliverToBoxAdapter(
                  child: TextButton(
                      onPressed: _refreshProfile,
                      child: const Text('资料刷新失败，点击重试'))),
            if (activeList.isEmpty &&
                !activeLoading &&
                activeFeed.error == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          activeEmptyIcon,
                          size: 48,
                          color: AppColors.textHint.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          activeEmptyTitle,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, _isSelf ? 32 : 92),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= activeList.length) return null;
                    return _buildMomentCard(activeList[index]);
                  }, childCount: activeList.length),
                ),
              ),
            SliverToBoxAdapter(child: ProfileFeedStatus(feed: activeFeed)),
            if (activeLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTabs() {
    const tabs = ['瞬间', '收藏'];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 1, 18, 0),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          ...List.generate(tabs.length, (index) {
            final selected = _profileTabIndex == index;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _switchProfileTab(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            selected ? AppColors.primary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Text(
                    tabs[index],
                    style: AppTextStyles.titleMedium.copyWith(
                      fontSize: 14,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
          IconButton(
              tooltip: '刷新主页',
              onPressed: _refreshProfile,
              icon: const Icon(Icons.refresh_rounded, size: 20)),
        ],
      ),
    );
  }

  Future<void> _confirmBlockUser() async {
    if (!_beginRelationshipChange()) return;
    final session = apiSessionChanges.value;
    final userId = widget.userId;
    final options = _sessionOptions();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 58),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 25, 24, 8),
                child: Text(
                  '确定将对方加入黑名单？',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 22),
                child: Text(
                  '黑名单在“我的-设置-隐私设置”中',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF55575D)),
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 58,
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 18,
                            color: Color(0xFF303238),
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            fontSize: 18,
                            color: Color(0xFF303238),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !_sameProfile(session, userId)) return;
      final res = await apiClient.post('/api/community/user/$userId/block',
          options: options);
      if (!mounted || !_sameProfile(session, userId)) return;
      final data = _responseData(res.data);
      if (data['blocked'] != true) throw const FormatException('拉黑未完成');
      _postFeed.reset();
      _favoriteFeed.reset();
      _userGeneration++;
      setState(() {
        _user = null;
        _userError = '暂时无法查看该用户';
        _loadingUser = false;
      });
      showAppToast(context, '已拉黑');
      Navigator.of(context).maybePop(true);
    } catch (_) {
      if (mounted && _sameProfile(session, userId)) {
        showAppToast(context, '拉黑失败，请重试');
      }
    } finally {
      if (mounted && _sameProfile(session, userId)) {
        setState(() => _relationshipBusy = false);
      }
    }
  }

  Widget _buildHeader(
    String displayName,
    String nickname,
    String? avatarUrl,
    String intro,
    int likes,
    int follow,
    int follower,
    String? genderLabel,
    String? ipLocation,
    String teamTitle,
  ) {
    final headerBgUrl = _user?['homeBackgroundUrl']?.toString().trim();
    final headerInk =
        profileBackgroundById(_user?['homeBackgroundId']?.toString())?.dark ==
                false
            ? const Color(0xFF203E3A)
            : Colors.white;
    final previewAllowed = _user?['backgroundPreviewAllowed'] == null ||
        _user?['backgroundPreviewAllowed'] == true ||
        _user?['backgroundPreviewAllowed'] == 1;
    final province = _provinceOnly(ipLocation);

    return AnimatedBuilder(
      animation: _backgroundRevealController,
      builder: (context, _) {
        final screen = MediaQuery.sizeOf(context);
        final collapsedHeight =
            (screen.height * 0.34).clamp(282.0, 330.0).toDouble();
        final expandedHeight =
            (screen.height * 0.58).clamp(470.0, 580.0).toDouble();
        final reveal = Curves.easeOutCubic.transform(
          _backgroundRevealController.value,
        );
        final height =
            collapsedHeight + (expandedHeight - collapsedHeight) * reveal;
        return Semantics(
          label: '下拉展开主页背景，上滑收起',
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: previewAllowed
                        ? () => _showBackgroundPreview(headerBgUrl)
                        : null,
                    child: ProfileBackgroundArtwork(
                      key: ValueKey(
                        'profile-background-${_user?['homeBackgroundId']}-$headerBgUrl',
                      ),
                      backgroundId: _user?['homeBackgroundId']?.toString(),
                      legacyUrl: headerBgUrl,
                      dim: headerInk == Colors.white ? .12 : 0,
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: MediaQuery.paddingOf(context).top + 2,
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: '返回',
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: headerInk,
                              size: 24,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: headerInk,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: _isSelf ? '主页设置' : '用户设置',
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              color: headerInk,
                              size: 27,
                            ),
                            onPressed: _showProfileActions,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (province.isNotEmpty)
                  Positioned(
                    right: 18,
                    top: MediaQuery.paddingOf(context).top + 50,
                    child: Text(
                      'IP属地：$province',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: headerInk.withValues(alpha: 0.86),
                        fontSize: 12,
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: _buildProfileSummaryCard(
                    nickname: nickname,
                    avatarUrl: avatarUrl,
                    intro: intro,
                    likes: likes,
                    follow: follow,
                    follower: follower,
                    genderLabel: genderLabel,
                    teamTitle: teamTitle,
                    opacity: 0.90 - reveal * 0.07,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileSummaryCard({
    required String nickname,
    required String? avatarUrl,
    required String intro,
    required int likes,
    required int follow,
    required int follower,
    required String? genderLabel,
    required String teamTitle,
    required double opacity,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              CommunityOnlineIndicator(
                online: _user?['isOnline'] == true,
                dotSize: 13,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4DD5CC), Color(0xFFE993AF)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Text(
                            nickname.isNotEmpty ? nickname[0] : '?',
                            style: AppTextStyles.titleLarge,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLarge.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (teamTitle.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          TeamTitleChip(
                            title: teamTitle,
                            userId: widget.userId,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _inlineStat(follow, '关注'),
                        const SizedBox(width: 18),
                        _inlineStat(follower, '被关注'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (intro.isNotEmpty && intro != '暂无介绍') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                intro,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (genderLabel != null)
                _buildTag(
                  Icons.auto_awesome_rounded,
                  genderLabel,
                  const Color(0xFFFFEFF4),
                  const Color(0xFFD8688B),
                ),
              _buildTag(
                Icons.favorite_rounded,
                '$likes 次共鸣',
                const Color(0xFFFFF6E6),
                const Color(0xFFB87A20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _provinceOnly(String? value) {
    var text = value?.trim() ?? '';
    if (_isStubLocation(text)) return '';
    text = text.split(RegExp(r'[\s,/·-]+')).first;
    return text
        .replaceFirst(RegExp(r'特别行政区$'), '')
        .replaceFirst(RegExp(r'自治区$'), '')
        .replaceFirst(RegExp(r'[省市]$'), '');
  }

  Widget _inlineStat(int count, String label) {
    return RichText(
      text: TextSpan(
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textHint,
          fontSize: 14,
        ),
        children: [
          TextSpan(
            text: '$count ',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: label),
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: textColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 0.5 : 0,
      shadowColor: Colors.black.withValues(alpha: .08),
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabsHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

class _ProfileRevealScrollPhysics extends ScrollPhysics {
  const _ProfileRevealScrollPhysics({
    required this.shouldLock,
    required this.shouldLimitFling,
    super.parent,
  });

  final bool Function() shouldLock;
  final bool Function() shouldLimitFling;

  @override
  _ProfileRevealScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ProfileRevealScrollPhysics(
      shouldLock: shouldLock,
      shouldLimitFling: shouldLimitFling,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (shouldLock()) return 0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final effectiveVelocity = shouldLimitFling()
        ? velocity.clamp(-720.0, 720.0).toDouble()
        : velocity;
    return super.createBallisticSimulation(position, effectiveVelocity);
  }
}

class _ProfileMenuAction {
  const _ProfileMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}
