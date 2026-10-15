import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/app/pages/home/home_index/controller.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/index.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/month_calendar_sheet.dart';
import 'package:xuanyu/app/pages/home/home_index/widgets/galaxy_match_portal.dart';
import 'package:xuanyu/features/community/community_search_page.dart';
import 'package:xuanyu/features/community/create_post_page.dart';
import 'package:xuanyu/features/consultation/consultation_home_section.dart';

class HomeIndexPage extends StatelessWidget {
  const HomeIndexPage({super.key});

  // ============ 顶部 ============
  Widget _buildTopBar(BuildContext context, HomeIndexController c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => MonthCalendarSheet.show(context),
            child: Image.asset(
              ImageAssets.iconQiandao,
              width: 22.r,
              height: 22.r,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CommunitySearchPage()),
              ),
              child: Container(
                height: 36.r,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(18.r),
                ),
                child: Row(
                  children: [
                    Image.asset(
                      ImageAssets.navSearch,
                      width: 18.r,
                      height: 18.r,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        '搜索社区内容',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                    Container(
                      height: 26.r,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: AppColors.primaryGradient,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(13)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '搜索',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreatePostPage()),
            ),
            child: Image.asset(
              ImageAssets.iconTianjia,
              width: 22.r,
              height: 22.r,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  // ============ 能量 + 今日功德 + 养生 ============
  Widget _buildFortuneRow(HomeIndexController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左：今日能量大卡
          Expanded(
            flex: 5,
            child: GestureDetector(
              onTap: c.onFortuneTap,
              child: SizedBox(
                height: 150.h,
                child: SectionCard(
                  padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '今日能量',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            '${c.energyScore.overall}',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            size: 16.r,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const Spacer(),
                      FortuneBars(
                        maxBarHeight: 48,
                        compact: true,
                        items: c.energyScore.toBarItems(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          // 右：今日功德 + 今日养生 两小卡
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildSmallCard(
                  title: '敲木鱼',
                  subtitle: '了解更多',
                  asset: ImageAssets.iconMuyu,
                  onTap: c.onMeritTap,
                ),
                SizedBox(height: 10.h),
                _buildSmallCard(
                  title: '今日养生',
                  subtitle: '了解更多',
                  asset: ImageAssets.iconYangsheng,
                  onTap: c.onHealthTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallCard({
    required String title,
    required String subtitle,
    required String asset,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 70.h,
        width: double.infinity,
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              // 右下角铺满的插画
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 150.r,
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
              // 左侧文字
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(width: 2.w),
                        Icon(
                          Icons.chevron_right,
                          size: 12.r,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 首页双页功能卡 ==========
  Widget _buildMatchPortalCard(HomeIndexController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: _HomePortalCarousel(
        galaxyRevolutionSeconds: c.galaxyRevolutionSeconds,
        onDestinyTap: () => c.onGridTap(const GridEntry(
          '缘分匹配',
          ImageAssets.iconYuanfen,
          RouteNames.homeDestinyMatch,
        )),
        onVoiceTap: () => c.onGridTap(const GridEntry(
          '语音匹配',
          ImageAssets.iconShudong,
          RouteNames.voiceMatch,
        )),
        onWishTap: c.onWishPrayerTap,
        onGoodwillTap: c.onGoodwillEchoTap,
      ),
    );
  }

  // ============ 左右翻页功能入口 ============
  Widget _buildGrid(HomeIndexController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: HomeFeatureCarousel(
        entries: c.gridEntries,
        onTap: c.onGridTap,
        iconBuilder: _buildGridIcon,
      ),
    );
  }

  Widget _buildGridIcon(GridEntry entry) {
    if (entry.label == '生肖印记') {
      return Container(
        width: 42.r,
        height: 42.r,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x24767CC8),
              blurRadius: 9,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(entry.iconAsset, fit: BoxFit.cover),
      );
    }
    if (entry.label == '星座星盘') {
      return Container(
        width: 38.r,
        height: 38.r,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF273F6D), Color(0xFF7479C8)],
          ),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x287479C8),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(entry.iconData, size: 25.r, color: Colors.white),
            Positioned(
              right: 5.r,
              top: 5.r,
              child: Icon(
                Icons.circle,
                size: 4.r,
                color: const Color(0xFFFFE4A8),
              ),
            ),
          ],
        ),
      );
    }
    if (entry.label == '七政四余') {
      return Container(
        width: 38.r,
        height: 38.r,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF174C4A), Color(0xFFB99950)],
          ),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x24174C4A),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Icon(entry.iconData, size: 23.r, color: Colors.white),
      );
    }
    if (entry.label == '伴侣画像') {
      return Container(
        width: 38.r,
        height: 38.r,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFB88DF2), Color(0xFF7267E8)],
          ),
          borderRadius: BorderRadius.circular(11.r),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x287267E8),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(entry.iconData, size: 24.r, color: Colors.white),
            Icon(
              Icons.favorite_rounded,
              size: 9.r,
              color: const Color(0xFFFFF0C5),
            ),
          ],
        ),
      );
    }
    if (entry.label == '使用建议') {
      return Container(
        width: 38.r,
        height: 38.r,
        decoration: BoxDecoration(
          color: const Color(0xFF148B89),
          borderRadius: BorderRadius.circular(11.r),
        ),
        child: Icon(entry.iconData, size: 24.r, color: Colors.white),
      );
    }
    if (entry.iconData != null) {
      return Container(
        width: 36.r,
        height: 36.r,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF8FAFC0), Color(0xFFD99262)],
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(entry.iconData, size: 21.r, color: Colors.white),
      );
    }
    return Image.asset(
      entry.iconAsset,
      width: 38.r,
      height: 38.r,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.apps,
        size: 36.r,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildShopEntry(HomeIndexController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Semantics(
        button: true,
        label: '玄遇好物，为此刻的你挑一点合适的',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16.r),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: c.onShopTap,
            child: Ink(
              height: 72.h,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFBFDFD),
                    Color(0xFFF3FAFA),
                    Color(0xFFF9F7F1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: const Color(0xFFE2E9E8)),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: 30.w,
                    top: -24.h,
                    child: Container(
                      width: 82.r,
                      height: 82.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE4F6F4).withValues(alpha: .38),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12.r),
                        child: Image.asset(
                          ImageAssets.iconXuanyuGoods,
                          width: 52.r,
                          height: 52.r,
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '玄遇好物',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF304B54),
                              ),
                            ),
                            SizedBox(height: 3.h),
                            Text(
                              '为此刻的你，挑一点合适的',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: const Color(0xFF74878C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 30.r,
                        height: 30.r,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: .72),
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 21.r,
                          color: const Color(0xFF668588),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<HomeIndexController>(
      init: HomeIndexController(),
      id: 'home_index',
      builder: (c) {
        return GradientScaffold(
          extendBodyBehindAppBar: false,
          useGradient: true,
          gradientColors: AppColors.homeBgGradient,
          gradientStops: AppColors.homeBgGradientStops,
          body: SafeArea(
            child: SingleChildScrollView(
              key: const ValueKey('home-index-scroll'),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: 20.h + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(context, c),
                  _buildFortuneRow(c),
                  SizedBox(height: 12.h),
                  _buildMatchPortalCard(c),
                  SizedBox(height: 14.h),
                  _buildGrid(c),
                  SizedBox(height: 10.h),
                  _buildShopEntry(c),
                  SizedBox(height: 14.h),
                  const ConsultationHomeSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class HomeFeatureCarousel extends StatefulWidget {
  const HomeFeatureCarousel({
    super.key,
    required this.entries,
    required this.onTap,
    required this.iconBuilder,
  });

  final List<GridEntry> entries;
  final Future<void> Function(GridEntry) onTap;
  final Widget Function(GridEntry) iconBuilder;

  @override
  State<HomeFeatureCarousel> createState() => _HomeFeatureCarouselState();
}

class _HomeFeatureCarouselState extends State<HomeFeatureCarousel> {
  late final PageController _pageController;
  int _pageIndex = 0;

  int get _pageCount =>
      (widget.entries.length + HomeIndexController.gridItemsPerPage - 1) ~/
      HomeIndexController.gridItemsPerPage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.fromLTRB(8.w, 12.h, 8.w, 9.h),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 172.h,
            child: PageView.builder(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              allowImplicitScrolling: true,
              itemCount: _pageCount,
              onPageChanged: (index) {
                if (_pageIndex == index) return;
                setState(() => _pageIndex = index);
              },
              itemBuilder: (_, pageIndex) {
                final start = pageIndex * HomeIndexController.gridItemsPerPage;
                final end = math.min(
                  start + HomeIndexController.gridItemsPerPage,
                  widget.entries.length,
                );
                return _buildPage(widget.entries.sublist(start, end));
              },
            ),
          ),
          SizedBox(height: 7.h),
          Semantics(
            label: '功能入口第${_pageIndex + 1}页，共$_pageCount页',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_pageCount, (index) {
                final selected = _pageIndex == index;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goToPage(index),
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: selected ? 14.w : 6.r,
                      height: 6.r,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFFD8DDE1),
                        borderRadius: BorderRadius.circular(3.r),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(List<GridEntry> entries) {
    final firstRow = entries.take(HomeIndexController.gridColumns).toList();
    final secondRow = entries
        .skip(HomeIndexController.gridColumns)
        .take(HomeIndexController.gridColumns)
        .toList();
    return Column(
      children: <Widget>[
        _buildRow(firstRow),
        SizedBox(height: 8.h),
        _buildRow(secondRow),
      ],
    );
  }

  Widget _buildRow(List<GridEntry> entries) {
    return SizedBox(
      height: 82.h,
      child: Row(
        children: <Widget>[
          for (final entry in entries)
            Expanded(
              child: Semantics(
                button: true,
                label: entry.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTap(entry),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      widget.iconBuilder(entry),
                      SizedBox(height: 7.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3.w),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          for (var i = entries.length; i < HomeIndexController.gridColumns; i++)
            const Spacer(),
        ],
      ),
    );
  }
}

class _HomePortalCarousel extends StatefulWidget {
  const _HomePortalCarousel({
    required this.galaxyRevolutionSeconds,
    required this.onDestinyTap,
    required this.onVoiceTap,
    required this.onWishTap,
    required this.onGoodwillTap,
  });

  final double galaxyRevolutionSeconds;
  final VoidCallback onDestinyTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onWishTap;
  final VoidCallback onGoodwillTap;

  @override
  State<_HomePortalCarousel> createState() => _HomePortalCarouselState();
}

class _HomePortalCarouselState extends State<_HomePortalCarousel> {
  late final PageController _pageController;
  int _pageIndex = 0;
  ScrollPosition? _parentScroll;
  bool _inViewport = true;
  bool _visibilityCheckPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_parentScroll != position) {
      _parentScroll?.removeListener(_scheduleVisibilityCheck);
      _parentScroll = position;
      _parentScroll?.addListener(_scheduleVisibilityCheck);
    }
    _scheduleVisibilityCheck();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckPending) return;
    _visibilityCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckPending = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final screen = Offset.zero & MediaQuery.sizeOf(context);
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      final visible = bounds.overlaps(screen);
      if (visible != _inViewport) setState(() => _inViewport = visible);
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _parentScroll?.removeListener(_scheduleVisibilityCheck);
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: 369 / 170,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: PageView(
              controller: _pageController,
              allowImplicitScrolling: true,
              onPageChanged: (index) {
                if (_pageIndex == index) return;
                setState(() => _pageIndex = index);
              },
              children: <Widget>[
                _buildMatchPage(),
                _buildWishEchoPage(),
              ],
            ),
          ),
        ),
        SizedBox(height: 7.h),
        Semantics(
          label: '功能卡第${_pageIndex + 1}页，共2页',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(2, (index) {
              final selected = _pageIndex == index;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goToPage(index),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: selected ? 14.w : 6.r,
                    height: 6.r,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFD8DDE1),
                      borderRadius: BorderRadius.circular(3.r),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchPage() {
    return GalaxyMatchPortal(
      revolutionSeconds: widget.galaxyRevolutionSeconds,
      active: _pageIndex == 0 && _inViewport,
      onDestinyTap: widget.onDestinyTap,
      onVoiceTap: widget.onVoiceTap,
    );
  }

  Widget _buildWishEchoPage() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          ImageAssets.homeWishEchoPortal,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.white.withValues(alpha: .08),
                Colors.white.withValues(alpha: .01),
              ],
            ),
          ),
        ),
        Row(
          children: <Widget>[
            _buildTextPortal(
              title: '心愿寄语',
              subtitle: '安放心里没说完的话',
              semanticsLabel: '心愿寄语，安放心里没说完的话',
              onTap: widget.onWishTap,
            ),
            _buildTextPortal(
              title: '善意回声',
              subtitle: '让陌生善意被听见',
              semanticsLabel: '善意回声，让陌生善意被听见',
              onTap: widget.onGoodwillTap,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextPortal({
    required String title,
    required String subtitle,
    required String semanticsLabel,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(17.w, 21.h, 8.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17.sp,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF263B63),
                    ),
                  ),
                  SizedBox(height: 7.h),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: const Color(0xFF52698D),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
