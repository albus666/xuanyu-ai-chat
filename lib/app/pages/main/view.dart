import 'package:flutter/material.dart';
import 'package:xuanyu/core/widgets/lazy_indexed_stack.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/community/index.dart';
import 'package:xuanyu/app/pages/home/home_index/index.dart';
import 'package:xuanyu/app/pages/main/controller.dart';
import 'package:xuanyu/app/pages/message/index.dart';
import 'package:xuanyu/app/pages/mine/index.dart';

class ShellMainPage extends StatefulWidget {
  const ShellMainPage({super.key});

  @override
  State<ShellMainPage> createState() => _ShellMainPageState();
}

class _ShellMainPageState extends State<ShellMainPage> {
  final GlobalKey<CommunityPageState> _communityKey =
      GlobalKey<CommunityPageState>();
  final GlobalKey<ProfilePageState> _profileKey = GlobalKey<ProfilePageState>();
  int _messageBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<MainController>()) {
      Get.put(MainController());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AuthState>(
      builder: (auth) {
        final isMinor = auth.isMinorMode;
        return GetBuilder<MainController>(
          id: 'main',
          builder: (c) {
            return Scaffold(
              backgroundColor: Colors.white,
              body: LazyIndexedStack(
                // Unread badges warm up after the home first frame.
                warmupIndices: const {3},
                index: c.currentIndex,
                children: <Widget>[
                  TickerMode(
                    enabled: c.currentIndex == 0,
                    child: const HomeIndexPage(),
                  ),
                  CommunityPage(key: _communityKey),
                  const SizedBox.shrink(),
                  MessagePage(
                    onBadgeChanged: (count) =>
                        setState(() => _messageBadgeCount = count),
                  ),
                  ProfilePage(
                    key: _profileKey,
                    isMinorMode: auth.isMinorMode,
                    onMinorModeChanged: auth.setMinorMode,
                    onLogout: () async {
                      await auth.logout();
                    },
                    onConstitutionChanged: () {},
                  ),
                ],
              ),
              bottomNavigationBar: _ShellBottomBar(
                currentIndex: c.currentIndex,
                messageBadgeCount: _messageBadgeCount,
                isMinorMode: isMinor,
                onTap: (i) {
                  if (i == 0 && Get.isRegistered<HomeIndexController>()) {
                    Get.find<HomeIndexController>().refreshHomeBackground();
                  }
                  if (i == 1) {
                    _communityKey.currentState?.refreshFeed();
                  }
                  if (i == 4) {
                    _profileKey.currentState?.refreshUser();
                  }
                  c.onTap(i);
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.currentIndex,
    required this.messageBadgeCount,
    required this.isMinorMode,
    required this.onTap,
  });

  final int currentIndex;
  final int messageBadgeCount;
  final bool isMinorMode;
  final ValueChanged<int> onTap;

  Widget _tabItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTapItem,
    int? logicalIndex,
  }) {
    Widget iconWidget = Icon(
      icon,
      size: 22.r,
      color: selected ? AppColors.primary : AppColors.textSecondary,
    );
    if (logicalIndex == 3 && messageBadgeCount > 0) {
      iconWidget = Badge(
        label: Text(messageBadgeCount > 99 ? '99+' : '$messageBadgeCount'),
        backgroundColor: AppColors.primary,
        child: iconWidget,
      );
    }
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTapItem,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _center(VoidCallback onCenter) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCenter,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40.r,
              height: 40.r,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppColors.primaryGradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2922D4C5),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.add_rounded, color: Colors.white, size: 25.r),
            ),
            SizedBox(height: 1.h),
            Text(
              '发布',
              style: TextStyle(
                fontSize: 10.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    if (isMinorMode) {
      return Container(
        height: 64.h + bottom,
        padding: EdgeInsets.only(bottom: bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            _tabItem(
              icon: Icons.home_outlined,
              label: '首页',
              selected: currentIndex == 0,
              logicalIndex: 0,
              onTapItem: () => onTap(0),
            ),
            _tabItem(
              icon: Icons.explore_outlined,
              label: '社区',
              selected: currentIndex == 1,
              logicalIndex: 1,
              onTapItem: () => onTap(1),
            ),
            _tabItem(
              icon: Icons.sentiment_satisfied_outlined,
              label: '我的',
              selected: currentIndex == 4,
              logicalIndex: 4,
              onTapItem: () => onTap(4),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 64.h + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          _tabItem(
            icon: Icons.home_outlined,
            label: '首页',
            selected: currentIndex == 0,
            logicalIndex: 0,
            onTapItem: () => onTap(0),
          ),
          _tabItem(
            icon: Icons.explore_outlined,
            label: '社区',
            selected: currentIndex == 1,
            logicalIndex: 1,
            onTapItem: () => onTap(1),
          ),
          _center(() => onTap(2)),
          _tabItem(
            icon: Icons.chat_bubble_outline,
            label: '消息',
            selected: currentIndex == 3,
            logicalIndex: 3,
            onTapItem: () => onTap(3),
          ),
          _tabItem(
            icon: Icons.sentiment_satisfied_outlined,
            label: '我的',
            selected: currentIndex == 4,
            logicalIndex: 4,
            onTapItem: () => onTap(4),
          ),
        ],
      ),
    );
  }
}
