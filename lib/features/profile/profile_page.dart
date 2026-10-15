import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/payment/apple_iap_service.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/user_cache_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../community/create_post_page.dart';
import '../community/community_search_page.dart';
import '../community/post_detail_page.dart';
import '../community/profile_post_feed.dart';
import '../community/post_text_cover_preview.dart';
import '../community/user_list_page.dart';
import '../fortune/paipan_record_archive_page.dart';
import '../consultation/consultation_history_page.dart';
import '../consultation/teacher_workbench_page.dart';
import 'balance_page.dart';
import 'collection_page.dart';
import 'help_support_page.dart';
import 'private_posts_page.dart';
import 'edit_profile_page.dart';
import 'profile_background_artwork.dart';
import 'profile_background_presets.dart';
import '../virtual_goods/decoration_center_page.dart';
import 'orders_page.dart';
import 'recharge_page.dart';
import 'settings_page.dart';
import 'teacher_apply_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.isMinorMode = false,
    this.onMinorModeChanged,
    this.onLogout,
    this.onConstitutionChanged,
  });

  final bool isMinorMode;
  final ValueChanged<bool>? onMinorModeChanged;
  final VoidCallback? onLogout;
  final VoidCallback? onConstitutionChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

abstract class ProfilePageState extends State<ProfilePage> {
  void refreshUser();
}

class _ProfilePageState extends ProfilePageState {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _postsScrollController = ScrollController();
  Map<String, dynamic>? _user;
  String _balance = '0.00';
  bool _updatingHomeBackground = false;

  Color get _profileForeground =>
      profileBackgroundById(_user?['homeBackgroundId']?.toString())?.dark ==
              false
          ? const Color(0xFF203E3A)
          : Colors.white;

  late final _postFeed = ProfilePostFeed(() {
    final uid = (_user?['userId'] as num?)?.toInt();
    return uid == null ? null : '/api/community/user/$uid/posts';
  });
  late final _favoriteFeed = ProfilePostFeed(() =>
      apiClient.options.headers['Authorization'] == null
          ? null
          : '/api/community/favorites');
  late final _likedFeed = ProfilePostFeed(() =>
      apiClient.options.headers['Authorization'] == null
          ? null
          : '/api/community/likes');
  List<Map<String, dynamic>> get _posts => _postFeed.items;
  List<Map<String, dynamic>> get _favoritePosts => _favoriteFeed.items;
  List<Map<String, dynamic>> get _likedPosts => _likedFeed.items;
  int _profileContentIndex = 0;
  int _userGeneration = 0;
  int _balanceGeneration = 0;
  String? _userError;
  final _likingPosts = <int>{};
  ProfilePostFeed get _visibleFeed => switch (_profileContentIndex) {
        1 => _favoriteFeed,
        2 => _likedFeed,
        _ => _postFeed,
      };
  List<Map<String, dynamic>> get _visiblePosts => _visibleFeed.items;
  bool get _visiblePostsLoading => _visibleFeed.loading;

  void _onPostsScroll() {
    if (!_postsScrollController.hasClients) return;
    final m = _postsScrollController.position;
    if (m.pixels >= m.maxScrollExtent - 320) _loadVisiblePosts();
  }

  /// 刷新钱包、个人资料与瞬间列表。触发：底栏切入「我的」、设置/编辑资料返回、发文成功等。无定时刷新；整页下拉见 [_onPullRefreshFullProfile]。
  @override
  void refreshUser() {
    if (!mounted) return;
    final session = apiSessionChanges.value;
    _loadBalance();
    _loadUser().then((_) {
      if (!mounted || session != apiSessionChanges.value) return;
      _reloadVisiblePosts();
    });
  }

  static String _formatBalance(String raw) {
    final v = double.tryParse(raw) ?? 0;
    return v.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    for (final feed in [_postFeed, _favoriteFeed, _likedFeed]) {
      feed.addListener(_feedChanged);
    }
    apiSessionChanges.addListener(_onSessionChanged);
    _postsScrollController.addListener(_onPostsScroll);
    AppleIapService.instance.changes.addListener(_loadBalance);
    refreshUser();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    for (final feed in [_postFeed, _favoriteFeed, _likedFeed]) {
      feed.dispose();
    }
    AppleIapService.instance.changes.removeListener(_loadBalance);
    _postsScrollController.removeListener(_onPostsScroll);
    _postsScrollController.dispose();
    super.dispose();
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _userGeneration++;
    _balanceGeneration++;
    setState(() {
      _user = null;
      _balance = '0.00';
      _profileContentIndex = 0;
      _likingPosts.clear();
      _userError =
          apiClient.options.headers['Authorization'] == null ? '请重新登录' : null;
    });
    if (apiClient.options.headers['Authorization'] != null) refreshUser();
  }

  /// OSS 签名每次刷新 query 都会变；去掉 query 后比较，避免头像/背景被当成新图闪一下。
  static String _mediaIdentity(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}${uri.path}';
    } catch (_) {
      return url.split('?').first;
    }
  }

  static String? _preferStableMediaUrl(dynamic previous, dynamic next) {
    final prev = previous?.toString();
    final neu = next?.toString();
    if (neu == null || neu.isEmpty) return neu;
    if (prev == null || prev.isEmpty) return neu;
    if (_mediaIdentity(prev) == _mediaIdentity(neu)) return prev;
    return neu;
  }

  Future<void> _loadUser() async {
    if (!mounted) return;
    final generation = ++_userGeneration;
    final session = apiSessionChanges.value;
    bool current() =>
        mounted &&
        generation == _userGeneration &&
        session == apiSessionChanges.value;
    setState(() => _userError = null);
    try {
      final res = await apiClient.get('/api/auth/me',
          options: Options(headers: {
            'Authorization': apiClient.options.headers['Authorization']
          }));
      if (!current()) return;
      final body = res.data;
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          body['data'] is! Map ||
          body['data']['userId'] is! num) {
        throw const FormatException('资料返回无效');
      }
      final next = Map<String, dynamic>.from(body['data'] as Map);
      final prev = _user;
      if (prev != null && prev['userId'] == next['userId']) {
        next['avatarUrl'] =
            _preferStableMediaUrl(prev['avatarUrl'], next['avatarUrl']);
        next['homeBackgroundUrl'] = _preferStableMediaUrl(
            prev['homeBackgroundUrl'], next['homeBackgroundUrl']);
      }
      setState(() => _user = next);
    } catch (_) {
      if (current()) {
        setState(() => _userError = '资料加载失败，请重试');
        if (mounted && _user != null) showAppToast(context, '资料刷新失败，请重试');
      }
    }
  }

  Future<void> _loadBalance() async {
    final generation = ++_balanceGeneration;
    final session = apiSessionChanges.value;
    try {
      final res = await apiClient.get('/api/auth/wallet/balance',
          options: Options(headers: {
            'Authorization': apiClient.options.headers['Authorization']
          }));
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null &&
          mounted &&
          generation == _balanceGeneration &&
          session == apiSessionChanges.value) {
        setState(() =>
            _balance = _formatBalance((data['balance'] ?? '0').toString()));
      }
    } catch (_) {}
  }

  void _showBackgroundPreview(String? bgUrl) {
    if ((bgUrl == null || bgUrl.trim().isEmpty) &&
        (_user?['homeBackgroundId']?.toString() ?? '').isEmpty) {
      // no custom bg — just show the settings directly
      _showHomeBackgroundSettings();
      return;
    }
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
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          // Bottom "更换背景" button
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
                    Navigator.pop(ctx);
                    _showHomeBackgroundSettings();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined,
                            color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text('装扮中心',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
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

  Future<void> _showHomeBackgroundSettings() async {
    if (_updatingHomeBackground || _user == null) return;
    setState(() => _updatingHomeBackground = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DecorationCenterPage(user: _user!),
      ));
      if (!mounted) return;
      await Future.wait([_loadUser(), _loadBalance()]);
    } finally {
      if (mounted) setState(() => _updatingHomeBackground = false);
    }
  }

  void _reloadPosts() {
    if (mounted) _postFeed.refresh();
  }

  void _loadVisiblePosts() {
    _visibleFeed.load();
  }

  Future<void> _reloadVisiblePosts() async {
    if (!mounted) return;
    // 详情页中可能取消收藏/点赞，非当前标签不能继续沿用旧缓存。
    for (final feed in [_postFeed, _favoriteFeed, _likedFeed]) {
      if (feed != _visibleFeed) feed.reset();
    }
    await _visibleFeed.refresh();
  }

  void _switchProfileContent(int index) {
    if (_profileContentIndex == index) return;
    setState(() => _profileContentIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _postsScrollController.hasClients) {
        _postsScrollController.jumpTo(0);
      }
    });
    if (!_visibleFeed.loaded) _visibleFeed.load();
  }

  /// 整页下拉：钱包、个人资料与瞬间第一页；无定时轮询。顶部侧栏按钮不参与此滚动。
  Future<void> _onPullRefreshFullProfile() async {
    final session = apiSessionChanges.value;
    await Future.wait([_loadBalance(), _loadUser()]);
    if (!mounted || session != apiSessionChanges.value) return;
    final uid = (_user?['userId'] as num?)?.toInt();
    if (uid == null) return;
    await _reloadVisiblePosts();
  }

  Future<void> _toggleLike(int postId) async {
    if (!_likingPosts.add(postId)) return;
    final session = apiSessionChanges.value;
    try {
      final res = await apiClient.post('/api/community/post/$postId/like',
          options: Options(headers: {
            'Authorization': apiClient.options.headers['Authorization']
          }));
      if (!mounted || session != apiSessionChanges.value) return;
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          data is! Map ||
          data['liked'] is! bool ||
          data['likeCount'] is! num) {
        throw const FormatException('点赞返回无效');
      }
      setState(() {
        final liked = data['liked'] == true;
        for (final list in [_posts, _favoritePosts, _likedPosts]) {
          final i =
              list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i < 0) continue;
          if (identical(list, _likedPosts) && !liked) {
            list.removeAt(i);
          } else {
            list[i]['liked'] = liked;
            list[i]['likeCount'] = data['likeCount'];
          }
        }
      });
      // 收藏/赞过来自同一条作品，取消点赞后重查避免偏移分页漏项。
      if (_profileContentIndex == 2 && data['liked'] == false) {
        await _likedFeed.refresh();
      }
    } catch (_) {
      if (mounted && session == apiSessionChanges.value) {
        showAppToast(context, '点赞失败，请重试');
      }
    } finally {
      if (session == apiSessionChanges.value) _likingPosts.remove(postId);
    }
  }

  /// 资料行右侧「编辑资料 + 设置」统一高度，避免一长一方视觉不齐
  static const double _profileActionBtnHeight = 36;

  /// 默认背景：清晰、柔和的青绿渐变，不叠加雾纹或装饰曲线。
  static const LinearGradient _profileHeaderGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF55AEB7),
      Color(0xFF72C6BD),
      Color(0xFFB6D8C5),
    ],
    stops: [0.0, 0.52, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topPad = MediaQuery.paddingOf(context).top;
    final profileBgUrl = _user?['homeBackgroundUrl']?.toString().trim();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      drawer: _buildDrawer(context),
      body: _user == null
          ? Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(gradient: _profileHeaderGradient),
              child: Center(
                  child: _userError == null
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_userError!),
                          TextButton(
                              onPressed: refreshUser,
                              child: const Text('重试加载资料')),
                        ])),
            )
          : Container(
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                      child: ProfileBackgroundArtwork(
                    backgroundId: _user?['homeBackgroundId']?.toString(),
                    legacyUrl: profileBgUrl,
                    dim: _profileForeground == Colors.white ? .12 : 0,
                  )),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxProfileH = constraints.maxHeight * 0.5;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _showBackgroundPreview(profileBgUrl),
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxHeight: maxProfileH),
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(
                                      20, topPad + kToolbarHeight + 4, 20, 40),
                                  child: _buildProfileLayerOnRed(),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                clipBehavior: Clip.none,
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    top: -14,
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Material(
                                      color: AppColors.surface,
                                      surfaceTintColor: Colors.transparent,
                                      elevation: 10,
                                      shadowColor:
                                          Colors.black.withOpacity(0.08),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(22)),
                                        side: BorderSide(
                                            color: AppColors.divider,
                                            width: 0.5),
                                      ),
                                      clipBehavior: Clip.none,
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(22)),
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _buildNotesTitleRow(),
                                            _buildNotesFilterRow(),
                                            Expanded(
                                              child: RefreshIndicator(
                                                color: AppColors.primary,
                                                backgroundColor: Colors.white
                                                    .withOpacity(0.92),
                                                displacement: 32,
                                                onRefresh:
                                                    _onPullRefreshFullProfile,
                                                child:
                                                    _buildNotesInnerScrollView(
                                                        bottomInset),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.menu_rounded,
                                  color: _profileForeground),
                              onPressed: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                            ),
                            const Spacer(),
                            _buildChangeBackgroundButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildChangeBackgroundButton() {
    return Semantics(
      button: true,
      label: _updatingHomeBackground ? '正在同步装扮' : '装扮中心',
      child: Material(
        color: _profileForeground.withValues(alpha: 0.16),
        shape: StadiumBorder(
          side: BorderSide(color: _profileForeground.withValues(alpha: 0.78)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _updatingHomeBackground ? null : _showHomeBackgroundSettings,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updatingHomeBackground)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _profileForeground,
                    ),
                  )
                else
                  Icon(
                    Icons.image_outlined,
                    size: 17,
                    color: _profileForeground,
                  ),
                const SizedBox(width: 6),
                Text(
                  _updatingHomeBackground ? '同步中' : '装扮中心',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _profileForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 与「瞬间」标题行的左右 padding 一致，网格左缘与选中线左缘对齐。
  static const double _notesSectionHPadding = 20;

  Widget _buildNotesTitleRow() {
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            _notesSectionHPadding, 8, _notesSectionHPadding, 0),
        child: Row(
          children: [
            _profileContentTab('瞬间',
                selected: _profileContentIndex == 0,
                onTap: () => _switchProfileContent(0)),
            const SizedBox(width: 28),
            _profileContentTab(
              '收藏',
              selected: _profileContentIndex == 1,
              onTap: () => _switchProfileContent(1),
            ),
            const SizedBox(width: 28),
            _profileContentTab(
              '赞过',
              selected: _profileContentIndex == 2,
              onTap: () => _switchProfileContent(2),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search_rounded,
                  color: AppColors.textSecondary, size: 26),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CommunitySearchPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileContentTab(String label,
      {bool selected = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label,
                style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary)),
            const SizedBox(height: 8),
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesFilterRow() {
    if (_profileContentIndex != 0) return const SizedBox.shrink();
    final publicCount = _postFeed.total ?? _posts.length;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
          _notesSectionHPadding, 8, _notesSectionHPadding, 12),
      child: Row(
        children: [
          Text('公开 $publicCount',
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 28),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivatePostsPage()),
            ),
            child: Text('私密',
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  /// 仅瞬间白区内滚动（网格 / 空态 / 加载）；标题行固定在 [Column] 上层。
  Widget _buildNotesInnerScrollView(double bottomInset) {
    final uid = (_user?['userId'] as num?)?.toInt();
    if (uid == null) return const SizedBox.shrink();
    final visiblePosts = _visiblePosts;
    final loading = _visiblePostsLoading;

    const physics =
        AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());

    if (loading && visiblePosts.isEmpty) {
      return CustomScrollView(
        controller: _postsScrollController,
        physics: physics,
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)),
          ),
        ],
      );
    }
    if (_visibleFeed.error != null && visiblePosts.isEmpty) {
      return CustomScrollView(
          controller: _postsScrollController,
          physics: physics,
          slivers: [
            SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: ProfileFeedStatus(feed: _visibleFeed))),
          ]);
    }
    if (visiblePosts.isEmpty && !loading) {
      final emptyText = switch (_profileContentIndex) {
        1 => '还没有收藏任何瞬间',
        2 => '还没有赞过任何瞬间',
        _ => '你还没有发布瞬间哦',
      };
      return CustomScrollView(
        controller: _postsScrollController,
        physics: physics,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(_notesSectionHPadding, 16,
                  _notesSectionHPadding, 24 + bottomInset),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _profileContentIndex == 1
                          ? Icons.bookmark_border_rounded
                          : _profileContentIndex == 2
                              ? Icons.favorite_border_rounded
                              : Icons.article_outlined,
                      size: 56,
                      color: AppColors.textHint.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text(emptyText,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint)),
                  if (_profileContentIndex == 0) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: AppButton(
                        label: '去发布',
                        width: 148,
                        height: 42,
                        isFullWidth: false,
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (_) => const CreatePostPage()))
                            .then((r) {
                          if (r == true && mounted) refreshUser();
                        }),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _postsScrollController,
      physics: physics,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              _notesSectionHPadding, 0, _notesSectionHPadding, 8 + bottomInset),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildPostThumbnail(visiblePosts[index]),
              childCount: visiblePosts.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: ProfileFeedStatus(feed: _visibleFeed)),
        if (loading && visiblePosts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12 + bottomInset),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 红色渐变上的个人信息（浅色字）
  Widget _buildProfileLayerOnRed() {
    final u = _user!;
    final nickname = u['nickname'] as String? ?? '用户';
    final avatarUrl = u['avatarUrl'] as String?;
    final intro = (u['intro'] as String?)?.trim() ?? '';
    final followCount = (u['followCount'] as num?)?.toInt() ?? 0;
    final followerCount = (u['followerCount'] as num?)?.toInt() ?? 0;
    final likeCount = (u['likeCount'] as num?)?.toInt() ?? 0;
    final userId = (u['userId'] as num?)?.toInt();
    final userCode = (u['userCode'] ?? userId ?? '').toString();
    final constitution = u['constitution'] as String?;
    final g = (u['gender'] as num?)?.toInt();

    final hasGender = g == 1 || g == 2;
    final hasConstitution = constitution != null && constitution.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _toEditProfile,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _profileForeground.withOpacity(0.55), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.surface,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Text(nickname.isNotEmpty ? nickname[0] : '?',
                          style: AppTextStyles.titleLarge
                              .copyWith(color: AppColors.primary))
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    style: AppTextStyles.titleLarge.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _profileForeground),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: userCode));
                      showAppToast(context, '玄遇号已复制',
                          duration: const Duration(seconds: 1));
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '玄遇号: $userCode',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: _profileForeground.withOpacity(0.88),
                              fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.copy_rounded,
                            size: 14,
                            color: _profileForeground.withOpacity(0.75)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (intro.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(intro,
              style: AppTextStyles.bodyMedium.copyWith(
                  color: _profileForeground.withOpacity(0.9), height: 1.5)),
        ] else ...[
          const SizedBox(height: 14),
          Text('点击编辑资料，填写个人简介',
              style: AppTextStyles.bodySmall
                  .copyWith(color: _profileForeground.withOpacity(0.65))),
        ],
        if (hasGender || hasConstitution) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasGender)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    g == 1 ? Icons.male_rounded : Icons.female_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              if (hasConstitution)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '体质 $constitution',
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 13,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _profileStatOnRed('获赞', likeCount, null, compact: true),
                  const SizedBox(width: 12),
                  _profileStatOnRed(
                      '关注',
                      followCount,
                      () => _toUserList(
                          '我的关注', '/api/community/user/me/following-list'),
                      compact: true),
                  const SizedBox(width: 12),
                  _profileStatOnRed(
                      '粉丝',
                      followerCount,
                      () => _toUserList(
                          '我的粉丝', '/api/community/user/me/followers'),
                      compact: true),
                ],
              ),
            ),
            Expanded(
              flex: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: _profileActionBtnHeight,
                    child: OutlinedButton(
                      onPressed: _toEditProfile,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _profileForeground,
                        backgroundColor: _profileForeground.withOpacity(0.12),
                        side: BorderSide(
                            color: _profileForeground.withOpacity(0.85)),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        minimumSize: const Size(0, _profileActionBtnHeight),
                        maximumSize: const Size(
                            double.infinity, _profileActionBtnHeight),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('编辑资料',
                          style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _profileForeground,
                              fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: _profileActionBtnHeight,
                    height: _profileActionBtnHeight,
                    child: Material(
                      color: _profileForeground.withOpacity(0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: _profileForeground.withOpacity(0.85)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _openSettings,
                        child: Center(
                            child: Icon(Icons.settings_outlined,
                                color: _profileForeground, size: 20)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => SettingsPage(
            isMinorMode: widget.isMinorMode,
            onMinorModeChanged: widget.onMinorModeChanged,
          ),
        ))
        .then((_) => refreshUser());
  }

  Widget _profileStatOnRed(String label, int count, VoidCallback? onTap,
      {bool compact = false}) {
    final countStyle = compact
        ? AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: _profileForeground)
        : AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: _profileForeground);
    final labelStyle = compact
        ? AppTextStyles.bodySmall.copyWith(
            color: _profileForeground.withOpacity(0.78),
            fontSize: 12,
            fontWeight: FontWeight.w500)
        : AppTextStyles.bodySmall.copyWith(
            color: _profileForeground.withOpacity(0.82), fontSize: 12);
    final gap = compact ? 2.0 : 4.0;

    const hCompact = EdgeInsets.symmetric(vertical: 2, horizontal: 4);
    const hNormal = EdgeInsets.symmetric(vertical: 4, horizontal: 8);

    final child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('$count', style: countStyle, textAlign: TextAlign.center),
        SizedBox(height: gap),
        Text(label, style: labelStyle, textAlign: TextAlign.center),
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: compact ? hCompact : hNormal,
        child: child,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: _profileForeground.withValues(alpha: .24),
        highlightColor: _profileForeground.withValues(alpha: .10),
        child: Padding(
          padding: compact ? hCompact : hNormal,
          child: child,
        ),
      ),
    );
  }

  /// 左上角侧栏：小红书式分组白卡片 + 底部圆形入口
  Widget _buildDrawer(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final drawerW = (sw * 0.82).clamp(300.0, 360.0);

    return Drawer(
      width: drawerW,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
              child: Row(
                children: [
                  Text('菜单',
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textHint.withOpacity(0.85), size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                children: [
                  _drawerCard(
                    children: [
                      _drawerMenuRow(
                        context,
                        icon: Icons.calendar_month_rounded,
                        title: '命理档案',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const PaipanRecordArchivePage()));
                        },
                      ),
                    ],
                  ),
                  _drawerCard(
                    children: [
                      _drawerMenuRow(
                        context,
                        icon: Icons.receipt_long_rounded,
                        title: '我的订单',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const OrdersPage()));
                        },
                      ),
                      _drawerMenuRow(
                        context,
                        icon: Icons.support_agent_rounded,
                        title: '我的咨询与预约',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const ConsultationHistoryPage()));
                        },
                      ),
                      _drawerMenuRow(
                        context,
                        icon: Icons.bookmark_outline_rounded,
                        title: '我的收藏',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const CollectionPage()));
                        },
                      ),
                      _drawerMenuRow(
                        context,
                        icon: _user?['isMaster'] == true
                            ? Icons.workspace_premium_outlined
                            : Icons.school_outlined,
                        title: _user?['isMaster'] == true ? '老师工作台' : '名师入驻',
                        showChevron: true,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => _user?['isMaster'] == true
                                  ? const TeacherWorkbenchPage()
                                  : TeacherApplyPage(onSuccess: _loadUser)));
                        },
                      ),
                    ],
                  ),
                  _drawerCard(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const BalancePage()));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            child: Row(
                              children: [
                                _drawerIconBubble(
                                    Icons.account_balance_wallet_outlined),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('钱包',
                                          style: AppTextStyles.bodyLarge
                                              .copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '玄遇币 ${double.tryParse(_balance)?.toStringAsFixed(2) ?? _balance}',
                                        style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textHint,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    color: AppColors.textHint.withOpacity(0.45),
                                    size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => const RechargePage()));
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text('充值玄遇币',
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => const BalancePage()));
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text('明细与规则',
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w500)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _drawerFooterBar(context),
            if (widget.onLogout != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmLogout(context);
                  },
                  child: Text('退出登录',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _drawerCard({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _drawerInjectDividers(children),
          ),
        ),
      ),
    );
  }

  static List<Widget> _drawerInjectDividers(List<Widget> tiles) {
    final out = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        out.add(
          Divider(
              height: 1,
              thickness: 1,
              indent: 66,
              endIndent: 14,
              color: AppColors.divider.withOpacity(0.9)),
        );
      }
      out.add(tiles[i]);
    }
    return out;
  }

  static Widget _drawerIconBubble(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 22, color: AppColors.textSecondary),
    );
  }

  Widget _drawerMenuRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool showChevron = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _drawerIconBubble(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.textPrimary),
                ),
              ),
              if (showChevron)
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint.withOpacity(0.45), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerFooterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _drawerFooterAction(
            context,
            icon: Icons.headset_mic_outlined,
            label: '帮助与客服',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpSupportPage()));
            },
          ),
          _drawerFooterAction(
            context,
            icon: Icons.settings_outlined,
            label: '设置',
            onTap: () {
              Navigator.pop(context);
              _openSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _drawerFooterAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(icon, size: 24, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary, fontSize: 11, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostThumbnail(Map<String, dynamic> item) {
    final mediaUrls = item['mediaUrls'] as List<dynamic>?;
    final mediaCoverUrls = item['mediaCoverUrls'] as List<dynamic>?;
    final isVideo = item['mediaType'] == 'video';
    final thumbUrl = isVideo
        ? (mediaCoverUrls != null && mediaCoverUrls.isNotEmpty
            ? mediaCoverUrls[0].toString()
            : null)
        : (mediaUrls != null && mediaUrls.isNotEmpty
            ? mediaUrls[0].toString()
            : null);
    final postId = (item['id'] as num?)?.toInt();
    final liked = item['liked'] == true;
    final likeCount = (item['likeCount'] as num?)?.toInt() ?? 0;
    final viewCount = (item['viewCount'] as num?)?.toInt() ?? 0;
    final textOnlyCover = !isVideo && (thumbUrl == null || thumbUrl.isEmpty);

    return GestureDetector(
      onTap: () async {
        if (postId == null) return;
        final session = apiSessionChanges.value;
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) =>
                  PostDetailPage(postId: postId, initialItem: item)),
        );
        if (mounted && session == apiSessionChanges.value) {
          await _reloadVisiblePosts();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppColors.divider.withOpacity(0.9), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo && (thumbUrl == null || thumbUrl.isEmpty))
              Container(
                color: const Color(0xFF1a1a1a),
                child: Center(
                    child: Icon(Icons.videocam_rounded,
                        size: 40, color: Colors.white.withOpacity(0.8))),
              ),
            if (thumbUrl != null && thumbUrl.isNotEmpty)
              Image.network(
                thumbUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF1a1a1a),
                  child: const Center(
                      child: Icon(Icons.videocam_rounded,
                          size: 40, color: Colors.white54)),
                ),
              ),
            if (textOnlyCover)
              PostTextCoverPreview(
                content: item['content'] as String? ?? '',
                maxLines: 6,
                compact: true,
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 36),
              ),
            if (!textOnlyCover)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.3)
                      ],
                      stops: const [0.7, 1.0],
                    ),
                  ),
                ),
              ),
            if (isVideo)
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white70, size: 36)),
            Positioned(
              left: 8,
              bottom: 8,
              child: GestureDetector(
                onTap: postId != null ? () => _toggleLike(postId) : null,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: liked
                          ? const Color(0xFFE53935)
                          : (textOnlyCover
                              ? AppColors.textSecondary
                              : Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$likeCount',
                      style: TextStyle(
                        color: textOnlyCover
                            ? AppColors.textSecondary
                            : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_outlined,
                      size: 16,
                      color: textOnlyCover
                          ? AppColors.textSecondary
                          : Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    '$viewCount',
                    style: TextStyle(
                      color: textOnlyCover
                          ? AppColors.textSecondary
                          : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toUserList(String title, String apiPath) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserListPage(title: title, apiPath: apiPath),
    ));
  }

  void _toEditProfile() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          initialNickname: _user?['nickname'] ?? '',
          initialAvatarUrl: _user?['avatarUrl'],
          initialIntro: _user?['intro'] ?? '',
          initialBirthDate: _user?['birthDate'],
          initialBirthTime: _user?['birthTime'],
          initialBirthPlace: _user?['birthPlace'] as String?,
          initialBirthLongitude: (_user?['birthLongitude'] as num?)?.toDouble(),
          initialBirthLatitude: (_user?['birthLatitude'] as num?)?.toDouble(),
          initialBirthEditRemaining:
              (_user?['birthEditRemaining'] as num?)?.toInt() ?? 2,
          initialGender: (_user?['gender'] as num?)?.toInt(),
          initialConstitution: _user?['constitution'] as String?,
        ),
      ),
    )
        .then((_) {
      _loadUser().then((_) {
        if (mounted) _reloadPosts();
      });
      widget.onConstitutionChanged?.call();
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyToken);
    await prefs.remove(AppConstants.keyUserId);
    await clearUserDependentCache();
    setupApiClientToken(null);
    widget.onLogout?.call();
  }
}
