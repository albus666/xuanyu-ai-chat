import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/presence_heartbeat.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/main_bottom_nav.dart';
import '../home/home_page.dart';
import '../community/community_page.dart';
import '../publish/publish_page.dart';
import '../message/message_page.dart';
import '../profile/profile_page.dart';
import '../community/create_post_page.dart';

class MainShellPage extends StatefulWidget {
  static final ValueNotifier<int> homeRequests = ValueNotifier(0);
  static void showHome() => homeRequests.value++;
  const MainShellPage({
    super.key,
    this.initialIndex = 0,
    this.isMinorMode = false,
    this.onMinorModeChanged,
    this.onLogout,
  });

  final int initialIndex;
  final bool isMinorMode;
  final ValueChanged<bool>? onMinorModeChanged;
  final VoidCallback? onLogout;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  late int _currentIndex;
  final _presenceHeartbeat = PresenceHeartbeat();
  final _homeKey = GlobalKey<HomePageState>();
  final _communityKey = GlobalKey<CommunityPageState>();
  final _profileKey = GlobalKey<ProfilePageState>();
  int _messageBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    MainShellPage.homeRequests.addListener(_showHome);
    _presenceHeartbeat.attach();
    _updateLocationOnOpen();
  }

  void _showHome() {
    if (mounted) setState(() => _currentIndex = MainBottomNav.tabHome);
  }

  @override
  void didUpdateWidget(MainShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMinorMode && !oldWidget.isMinorMode) {
      if (_currentIndex == MainBottomNav.tabPublish ||
          _currentIndex == MainBottomNav.tabMessage) {
        setState(() => _currentIndex = MainBottomNav.tabHome);
      }
    }
  }

  @override
  void dispose() {
    MainShellPage.homeRequests.removeListener(_showHome);
    _presenceHeartbeat.detach();
    super.dispose();
  }

  /// 每次打开软件重新获取定位并保存到后端
  Future<void> _updateLocationOnOpen() async {
    try {
      final res = await apiClient.get('/api/config/ipLocation');
      final data = (res.data as Map?)?['data'] as Map?;
      final loc = (data?['location'] as String?)?.trim();
      if (loc == null || loc.isEmpty) return;
      // 与后端约定：占位不写入 user_profile，避免把「未知」覆盖掉历史上正确的省市区
      if (loc == '未知' || loc == '本地' || loc == '内网') return;
      await apiClient.post('/api/auth/location', data: {'locationCode': loc});
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[ipLocation] 更新失败: ${e.message} code=${e.response?.statusCode}');
      }
    }
    if (widget.isMinorMode &&
        (MainBottomNav.tabPublish == _currentIndex ||
            MainBottomNav.tabMessage == _currentIndex)) {
      _currentIndex = MainBottomNav.tabHome;
    }
  }

  void _onTabTapped(int index) {
    if (index == MainBottomNav.tabPublish) {
      Navigator.of(context)
          .push(
        MaterialPageRoute(builder: (_) => const CreatePostPage()),
      )
          .then((result) {
        if (result == true) _communityKey.currentState?.refreshFeed();
      });
      return;
    }
    // 切回首页时从本地缓存刷新今日养生（编辑资料/体质测试后已写入缓存，此处只读不请求）
    if (index == MainBottomNav.tabHome) {
      _homeKey.currentState?.refreshDailyHealthFromCache();
    }
    // 复用启动时已加载的社区内容，过期时仅后台更新当前标签。
    if (index == MainBottomNav.tabCommunity) {
      _communityKey.currentState?.refreshIfStale();
    }
    // 切到「我的」：刷新个人资料 + 笔记列表（笔记无定时刷新，仅此处与资料页下拉刷新）
    if (index == MainBottomNav.tabProfile) {
      _profileKey.currentState?.refreshUser();
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isMinor = widget.isMinorMode;
    final pages = [
      HomePage(key: _homeKey),
      CommunityPage(key: _communityKey),
      const PublishPage(),
      MessagePage(
          onBadgeChanged: (count) =>
              setState(() => _messageBadgeCount = count)),
      ProfilePage(
        key: _profileKey,
        isMinorMode: isMinor,
        onMinorModeChanged: widget.onMinorModeChanged,
        onLogout: widget.onLogout,
        onConstitutionChanged: () => _homeKey.currentState?.reloadDailyHealth(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: MainBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        isMinorMode: isMinor,
        messageBadgeCount: _messageBadgeCount,
      ),
    );
  }
}
