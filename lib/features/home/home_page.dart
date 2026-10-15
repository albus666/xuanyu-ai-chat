import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/post_share.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/utils/daily_energy_loader.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/post_card.dart';
import '../community/post_detail_page.dart';
import '../community/topic_feed_page.dart';
import '../fortune/bazi_input_page.dart';
import '../fortune/paipan/utils/region_loader.dart';
import '../fortune/fate_match_page.dart';
import '../fortune/voice_match_page.dart';
import '../fortune/fengshui_page.dart';
import '../fortune/constitution_test_page.dart';
import '../message/master_consult_entry_page.dart';
import 'announcements_page.dart';
import 'daily_fortune_detail_page.dart';
import 'daily_health_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _hotPosts = [];
  Map<String, dynamic>? _dailyFortune;
  Map<String, dynamic>? _dailyHealth;
  bool _loadingHot = true;
  bool _loadingFortune = true;
  bool _loadingHealth = true;
  int? _currentUserId;
  int _fortuneRequest = 0;
  int _healthRequest = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_clearPersonalContent);
    _loadCurrentUserId();
    _loadHot();
    _loadDailyFortune();
    _loadDailyHealth();
    Future.delayed(const Duration(milliseconds: 800),
        () => _checkUnreadAnnouncementPopup());
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_clearPersonalContent);
    super.dispose();
  }

  void _clearPersonalContent() {
    _fortuneRequest++;
    _healthRequest++;
    if (mounted) {
      setState(() {
        _dailyFortune = null;
        _dailyHealth = null;
        _loadingFortune = false;
        _loadingHealth = false;
      });
    }
  }

  /// 若有未读的「平台公告」类系统通知，弹窗展示一条并标已读
  Future<void> _checkUnreadAnnouncementPopup() async {
    if (!mounted) return;
    try {
      final res = await apiClient.get(
        '/api/community/system-notifications',
        queryParameters: {'page': 1, 'page_size': 10},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>?;
      if (list == null || list.isEmpty) return;
      Map<String, dynamic>? firstUnread;
      for (final e in list) {
        if (e is Map<String, dynamic> &&
            e['type'] == 'announcement' &&
            e['read'] != true) {
          firstUnread = Map<String, dynamic>.from(e);
          break;
        }
      }
      if (firstUnread == null || !mounted) return;
      final id = (firstUnread['id'] as num?)?.toInt();
      final title = firstUnread['title'] as String? ?? '平台公告';
      final content = firstUnread['content'] as String? ?? '';
      if (id != null)
        apiClient.post('/api/community/system-notifications/read', data: {
          'ids': [id]
        });
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.campaign_rounded,
                  color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(content.isEmpty ? '您有一条新公告，点击下方查看详情。' : content,
                style: AppTextStyles.bodyMedium),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AnnouncementsPage()));
              },
              child: const Text('查看全部'),
            ),
          ],
        ),
      );
    } on DioException catch (_) {}
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _currentUserId = prefs.getInt(AppConstants.keyUserId));
  }

  static String _todayString() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// 重新拉取今日运势（例如用户在个人资料中补填出生日期后切回首页时调用）
  void reloadDailyFortune() {
    if (!mounted) return;
    setState(() => _loadingFortune = true);
    _loadDailyFortune();
  }

  /// 修改体质后调用：直接请求接口更新今日养生，更新完再写入缓存（不读旧缓存）
  void reloadDailyHealth() {
    if (!mounted) return;
    setState(() => _loadingHealth = true);
    _loadDailyHealth(forceRefresh: true);
  }

  /// 仅从本地缓存刷新今日养生（不改体质时切回首页用，无请求、不转圈）
  Future<void> refreshDailyHealthFromCache() async {
    if (!mounted) return;
    final scope = ApiSessionScope();
    final request = ++_healthRequest;
    final prefs = await SharedPreferences.getInstance();
    if (!scope.current || request != _healthRequest) return;
    final today = _todayString();
    final cachedDate = prefs.getString(
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthDate));
    final cached = prefs.getString(
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthCache));
    if (cachedDate != today || cached == null || cached.isEmpty) return;
    try {
      final data = jsonDecode(cached) as Map<String, dynamic>?;
      if (data != null && mounted) setState(() => _dailyHealth = data);
    } catch (_) {}
  }

  Future<void> _loadDailyFortune() async {
    final scope = ApiSessionScope();
    final request = ++_fortuneRequest;
    bool current() => mounted && scope.current && request == _fortuneRequest;
    final prefs = await SharedPreferences.getInstance();
    if (!current()) return;
    final dateKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyFortuneDate);
    final dataKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyFortuneCache);
    final today = _todayString();
    final cachedDate = prefs.getString(dateKey);
    final cached = prefs.getString(dataKey);
    if (cachedDate == today && cached != null && cached.isNotEmpty) {
      try {
        final data = jsonDecode(cached) as Map<String, dynamic>?;
        if (data != null && mounted) {
          setState(() {
            _dailyFortune = data;
            _loadingFortune = false;
          });
          return;
        }
      } catch (_) {}
    }
    try {
      final res = await scope.get('/api/fortune/today-fortune');
      if (!current()) return;
      final data = (res.data as Map?)?['data'];
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        await prefs.setString(dateKey, today);
        if (!current()) return;
        await prefs.setString(dataKey, jsonEncode(map));
        if (current()) setState(() => _dailyFortune = map);
      }
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
    if (current()) setState(() => _loadingFortune = false);
  }

  Future<void> _loadDailyHealth({bool forceRefresh = false}) async {
    final scope = ApiSessionScope();
    final request = ++_healthRequest;
    bool current() => mounted && scope.current && request == _healthRequest;
    final prefs = await SharedPreferences.getInstance();
    if (!current()) return;
    final dateKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthDate);
    final dataKey =
        DailyEnergyLoader.cacheKey(prefs, AppConstants.keyDailyHealthCache);
    final today = _todayString();
    if (!forceRefresh) {
      final cachedDate = prefs.getString(dateKey);
      final cached = prefs.getString(dataKey);
      if (cachedDate == today && cached != null && cached.isNotEmpty) {
        try {
          final data = jsonDecode(cached) as Map<String, dynamic>?;
          if (data != null && mounted) {
            setState(() {
              _dailyHealth = data;
              _loadingHealth = false;
            });
            return;
          }
        } catch (_) {}
      }
    }
    try {
      final res = await scope.get('/api/fortune/daily-health');
      if (!current()) return;
      final data = (res.data as Map?)?['data'];
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        await prefs.setString(dateKey, today);
        if (!current()) return;
        await prefs.setString(dataKey, jsonEncode(map));
        if (current()) setState(() => _dailyHealth = map);
      }
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
    if (current()) setState(() => _loadingHealth = false);
  }

  Future<void> _handleLike(int postId) async {
    try {
      final res = await apiClient.post('/api/community/post/$postId/like');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final i =
              _hotPosts.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) {
            _hotPosts[i]['liked'] = data['liked'] == true;
            _hotPosts[i]['likeCount'] = data['likeCount'];
          }
        });
      }
    } on DioException catch (_) {}
  }

  Future<void> _handleFavorite(int postId) async {
    try {
      final res = await apiClient.post('/api/community/post/$postId/favorite');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final i =
              _hotPosts.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) _hotPosts[i]['favorited'] = data['favorited'] == true;
        });
      }
    } on DioException catch (_) {}
  }

  void _handleShare(int postId) {
    Map<String, dynamic>? item;
    for (final e in _hotPosts) {
      if ((e['id'] as num?)?.toInt() == postId) {
        item = e;
        break;
      }
    }
    if (item == null) return;
    showSharePostSheet(context, item, onShared: (count) {
      if (count != null && mounted) {
        setState(() {
          final i =
              _hotPosts.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) _hotPosts[i]['shareCount'] = count;
        });
      }
    });
  }

  Future<void> _loadHot() async {
    try {
      final res = await apiClient.get('/api/community/feed',
          queryParameters: {'tab': 'recommend', 'page': 1, 'page_size': 5});
      final data = (res.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>?;
      if (list != null && mounted) {
        setState(() {
          _hotPosts = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } on DioException catch (_) {}
    if (mounted) setState(() => _loadingHot = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration:
            const BoxDecoration(gradient: AppColors.scaffoldBodyGradient),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDailyFortuneAndHealthSection(),
                    const SizedBox(height: 26),
                    _buildSectionHeader('服务与匹配', '命理工具与缘分社交'),
                    const SizedBox(height: 8),
                    _buildSectionPanel(child: _buildServiceAndMatchSection()),
                    const SizedBox(height: 26),
                    _buildSectionHeader('热门推荐', '社区精彩动态'),
                    const SizedBox(height: 12),
                    _hotPosts.isEmpty && _loadingHot
                        ? const Center(
                            child: Padding(
                                padding: EdgeInsets.all(40),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : _buildHotSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.98),
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('玄遇',
              style: AppTextStyles.titleMedium
                  .copyWith(letterSpacing: 2.2, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
            ),
            child: IconButton(
              icon: const Icon(Icons.campaign_outlined,
                  color: AppColors.textPrimary, size: 20),
              tooltip: '平台公告',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyFortuneAndHealthSection() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildDailyFortuneSection()),
          const SizedBox(width: 12),
          Expanded(child: _buildDailyHealthSection()),
        ],
      ),
    );
  }

  Widget _buildDailyFortuneSection() {
    if (_loadingFortune) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9F1239), Color(0xFFDC2626)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('今日运势',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const Icon(Icons.wb_sunny_rounded,
                    color: Colors.white70, size: 18),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70)),
            const SizedBox(height: 8),
            Text('正在计算今日运势',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.95), fontSize: 13)),
          ],
        ),
      );
    }

    final fortune = _dailyFortune?['content'] ?? '正在掐指一算您的今日运势...';
    final date = _dailyFortune?['date'] as String?;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DailyFortuneDetailPage(
            content: fortune,
            date: date,
            title: '今日运势',
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9F1239), Color(0xFFDC2626)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('今日运势',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.8), size: 12),
              ],
            ),
            // 今日运势无天气行，把该高度用于多展示一行正文（4 行），与今日养生底部仍对齐
            const SizedBox(height: 12),
            SizedBox(
              height: _fortunePreviewTextHeight,
              child: Text(
                fortune,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Text('点击查看完整运势',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// 今日养生卡片内正文区域固定高度（3 行），今日运势用 87 显示 4 行（多出的 24 为天气位复用）
  static const double _cardPreviewTextHeight = 63;

  /// 今日运势多展示一行正文的高度（与 _cardWeatherSlotHeight 同高，保证两卡片底部对齐）
  static const double _fortunePreviewTextHeight = 87;

  /// 今日养生天气行占位高度
  static const double _cardWeatherSlotHeight = 24;

  /// 今日养生卡片预览：去掉 ``` 代码块包裹后，换行合并与长度截断。
  String _dailyHealthPreviewText(String text) {
    if (text.isEmpty) return '宜清淡饮食、规律作息。';
    final stripped = _dailyHealthStripCodeFence(text);
    final noMarkdown = _stripMarkdownForPreview(stripped);
    final oneLine = noMarkdown.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.isEmpty) return '宜清淡饮食、规律作息。';
    if (oneLine.length <= 100) return oneLine;
    return '${oneLine.substring(0, 100)}…';
  }

  /// 去掉今日养生内容外的 ```markdown ... ``` 包裹
  String _dailyHealthStripCodeFence(String raw) {
    if (raw.isEmpty) return raw;
    String s = raw.trim();
    if (s.startsWith('```')) {
      final firstLineEnd = s.indexOf('\n');
      if (firstLineEnd != -1) {
        s = s.substring(firstLineEnd + 1);
      } else {
        s = s.replaceFirst(RegExp(r'^```\w*\s*'), '');
      }
    }
    if (s.trimRight().endsWith('```')) {
      s = s.trimRight();
      final lastFence = s.lastIndexOf('```');
      if (lastFence != -1) s = s.substring(0, lastFence).trimRight();
    }
    return s.trim();
  }

  /// 从今日养生接口返回的 weather 对象中提取简短文案（如「北京：晴，18℃」），仅用 weather、temperature、city。
  String? _weatherSummaryFromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return null;
    final w = map['weather']?.toString().trim();
    final t = map['temperature'];
    final city = map['city']?.toString().trim();
    final tempStr = t != null ? '$t℃' : '';
    final parts = [
      if (w != null && w.isNotEmpty) w,
      if (tempStr.isNotEmpty) tempStr
    ];
    if (parts.isEmpty) return null;
    final summary = parts.join('，');
    return (city != null && city.isNotEmpty) ? '$city：$summary' : summary;
  }

  /// 去除 Markdown 符号，用于卡片预览展示（如今日运势、今日养生）。
  String _stripMarkdownForPreview(String text) {
    if (text.isEmpty) return text;
    var s = text.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    s = s.replaceAllMapped(
        RegExp(r'\*{1,2}([^*]+)\*{1,2}'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '');
    return s
        .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }

  Widget _buildDailyHealthSection() {
    if (_loadingHealth) {
      return _buildHealthCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('今日养生',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                Icon(Icons.eco_rounded,
                    color: Colors.white.withOpacity(0.7), size: 18),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70)),
            const SizedBox(height: 8),
            Text('正在生成养生建议',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9), fontSize: 13)),
          ],
        ),
      );
    }
    final content = _dailyHealth?['content'] ?? '宜清淡饮食、规律作息。';
    final date = _dailyHealth?['date'] as String?;
    final constitution = _dailyHealth?['constitution'] as String?;
    final solarTerm = _dailyHealth?['solarTerm'] as String?;
    final weather = _dailyHealth?['weather'];
    final weatherMap =
        weather is Map ? Map<String, dynamic>.from(weather) : null;
    // 优先用接口返回的 weatherSummary（后端已拼好），没有再用 map 解析
    final weatherSummary =
        (_dailyHealth?['weatherSummary'] as String?)?.trim() ??
            _weatherSummaryFromMap(weatherMap) ??
            '';
    // 调试：打印用于展示的天气相关变量
    debugPrint(
        '[今日养生卡片] weather=$weather, weatherMap=$weatherMap, weatherSummary="$weatherSummary"');
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DailyHealthDetailPage(
            content: content,
            date: date,
            constitution: constitution,
            solarTerm: solarTerm,
            weather: weatherMap,
          ),
        ),
      ),
      child: _buildHealthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('今日养生',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.8), size: 12),
              ],
            ),
            SizedBox(
              height: _cardWeatherSlotHeight,
              child: weatherSummary.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('天气 $weatherSummary',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12)),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _cardPreviewTextHeight,
              child: Text(
                _dailyHealthPreviewText(content),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Text('点击查看完整建议',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F766E).withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppTextStyles.titleMedium
                    .copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint, fontSize: 11)),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: AppColors.divider.withValues(alpha: 0.45)),
          ),
          child: Text('精选',
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildSectionPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }

  /// 原「核心服务」+「缘分匹配」合并：两行三列，多色渐变 + 独立描边
  Widget _buildServiceAndMatchSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMatchCard(
                  '八字排盘',
                  '探寻命理玄奥',
                  Icons.auto_awesome_mosaic_rounded,
                  gradientColors: const [
                    Color(0xFF7F1D1D),
                    Color(0xFFB91C1C),
                    Color(0xFFEA580C),
                    Color(0xFFF97316),
                  ],
                  borderColor: const Color(0xFFFBBF24),
                  onTap: () {
                    RegionLoader.preload();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BaziInputPage()));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMatchCard(
                  '风水分析',
                  '居住环境调优',
                  Icons.landscape_rounded,
                  gradientColors: const [
                    Color(0xFF064E3B),
                    Color(0xFF047857),
                    Color(0xFF10B981),
                    Color(0xFF5EEAD4),
                  ],
                  borderColor: const Color(0xFF6EE7B7),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FengshuiPage())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMatchCard(
                  '体质测试',
                  'AI 智慧辩证',
                  Icons.health_and_safety_rounded,
                  gradientColors: const [
                    Color(0xFF1E3A8A),
                    Color(0xFF2563EB),
                    Color(0xFF38BDF8),
                    Color(0xFF7DD3FC),
                  ],
                  borderColor: const Color(0xFF93C5FD),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => const ConstitutionTestPage()))
                      .then((_) => reloadDailyHealth()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMatchCard(
                  '名师咨询',
                  '一对一深度解答',
                  Icons.menu_book_rounded,
                  gradientColors: const [
                    Color(0xFF78350F),
                    Color(0xFFD97706),
                    Color(0xFFF59E0B),
                    Color(0xFFFDE68A),
                  ],
                  borderColor: const Color(0xFFFCD34D),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MasterConsultEntryPage())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMatchCard(
                  '缘分匹配',
                  '喜属性·时辰·年龄·性别·生肖·同日生',
                  Icons.favorite_rounded,
                  gradientColors: const [
                    Color(0xFF312E81),
                    Color(0xFF4F46E5),
                    Color(0xFF818CF8),
                    Color(0xFFC4B5FD),
                  ],
                  borderColor: const Color(0xFFA5B4FC),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FateMatchPage())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMatchCard(
                  '语音匹配',
                  '一对一语音聊天',
                  Icons.mic_rounded,
                  gradientColors: const [
                    Color(0xFF831843),
                    Color(0xFFBE185D),
                    Color(0xFFEC4899),
                    Color(0xFFF9A8D4),
                  ],
                  borderColor: const Color(0xFFF472B6),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const VoiceMatchPage())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(
    String title,
    String subtitle,
    IconData icon, {
    required List<Color> gradientColors,
    required Color borderColor,
    VoidCallback? onTap,
  }) {
    assert(gradientColors.length >= 2);
    final n = gradientColors.length;
    final stops = n <= 2 ? null : List<double>.generate(n, (i) => i / (n - 1));
    final shadowTint =
        Color.lerp(gradientColors.first, gradientColors.last, 0.45)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        height: 102,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            stops: stops,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: borderColor.withValues(alpha: 0.92), width: 1.35),
          boxShadow: [
            BoxShadow(
                color: shadowTint.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 5)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
                right: -8,
                bottom: -6,
                child: Icon(icon,
                    size: 48, color: Colors.white.withValues(alpha: 0.14))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: AppTextStyles.titleSmall.copyWith(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        height: 1.15)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 9.5,
                      height: 1.2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotSection() {
    return Column(
      children: _hotPosts
          .asMap()
          .entries
          .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  item: e.value,
                  heroTagSuffix: 'hot_${e.key}',
                  integrated: true,
                  showBottomDivider: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PostDetailPage(
                            postId: e.value['id'] as int,
                            initialItem: e.value)),
                  ),
                  onTopicTap: (id, name) => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            TopicFeedPage(topicId: id, topicName: name)),
                  ),
                  onLike: _handleLike,
                  onFavorite: _handleFavorite,
                  onShare: _handleShare,
                  currentUserId: _currentUserId,
                  onDeleted: (postId) => setState(() => _hotPosts.removeWhere(
                      (p) => (p['id'] as num?)?.toInt() == postId)),
                ),
              ))
          .toList(),
    );
  }
}
