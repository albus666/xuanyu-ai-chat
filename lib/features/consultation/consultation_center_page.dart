import 'dart:async';

import 'teacher_profile_updates.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/foreground_refresh.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'consultation_history_page.dart';
import 'create_voice_room_page.dart';
import 'teacher_detail_page.dart';
import 'teacher_workbench_page.dart';
import 'voice_room_overlay_controller.dart';
import 'voice_room_design.dart';

class ConsultationCenterPage extends StatefulWidget {
  const ConsultationCenterPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<ConsultationCenterPage> createState() => _ConsultationCenterPageState();
}

class _ConsultationCenterPageState extends State<ConsultationCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic> _config = const {};
  bool _isTeacher = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    _loadHeader();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHeader() async {
    Map<String, dynamic> config = const {};
    var teacher = false;
    try {
      final response = await apiClient.get('/api/consultation/config');
      final rawConfig = (response.data as Map?)?['data'];
      if (rawConfig is Map) config = Map<String, dynamic>.from(rawConfig);
    } on DioException catch (_) {}
    try {
      final response =
          await apiClient.get('/api/consultation/teacher/workbench');
      teacher = (response.data as Map?)?['code'] == 0;
    } on DioException catch (_) {}
    if (!mounted) return;
    setState(() {
      _config = config;
      _isTeacher = teacher;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFEAF8FA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('在线问道', style: AppTextStyles.titleMedium),
        actions: [
          IconButton(
            tooltip: '咨询记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ConsultationHistoryPage()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          if (_isTeacher)
            IconButton(
              tooltip: '老师工作台',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TeacherWorkbenchPage()),
              ),
              icon: const Icon(Icons.workspace_premium_outlined),
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeaderDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: AppColors.primaryDark,
                unselectedLabelColor: AppColors.textHint,
                labelStyle: AppTextStyles.bodyMedium
                    .copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: '私人专线'),
                  Tab(text: '在线名师'),
                  Tab(text: '免费派对'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _TeacherList(enabled: _config['privateEnabled'] != false),
            _RoomList(
                roomType: 'master',
                enabled: _config['masterPlazaEnabled'] != false),
            _RoomList(
                roomType: 'free',
                enabled: _config['freePlazaEnabled'] != false),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) {
          final index = _tabController.index;
          final masterEnabled = _config['masterPlazaEnabled'] != false;
          final freeEnabled = _config['freePlazaEnabled'] != false;
          final canCreate = (index == 2 && freeEnabled) ||
              (index == 1 && _isTeacher && masterEnabled);
          if (!canCreate) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => CreateVoiceRoomPage(
                      roomType: index == 1 ? 'master' : 'free'),
                ),
              );
              if (created == true && mounted) setState(() {});
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(index == 1 ? '创建名师房' : '创建派对'),
          );
        },
      ),
    );
  }
}

class _TeacherList extends StatefulWidget {
  const _TeacherList({required this.enabled});
  final bool enabled;

  @override
  State<_TeacherList> createState() => _TeacherListState();
}

class _TeacherListState extends State<_TeacherList>
    with AutomaticKeepAliveClientMixin {
  late final ForegroundRefresh _presenceRefresh;
  int _loadGeneration = 0;
  bool _fetching = false;
  final _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String _filter = '';
  String _sort = '综合排序';

  @override
  bool get wantKeepAlive => true;

  void _profileChanged() {
    final update = teacherProfileUpdates.value;
    if (!mounted || update == null || !update.current) return;
    final index = _items.indexWhere(
        (item) => item['userId'] == update.profile['userId']);
    if (index < 0) return;
    ++_loadGeneration;
    _fetching = false;
    setState(() {
      _items[index] = {..._items[index], ...update.profile};
      _sortItems();
    });
  }

  @override
  void initState() {
    super.initState();
    teacherProfileUpdates.addListener(_profileChanged);
    _presenceRefresh = ForegroundRefresh(
      refresh: () => _load(silent: true),
      isVisible: () =>
          mounted &&
          widget.enabled &&
          !_fetching &&
          TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    )..attach();
    _load();
  }

  @override
  void dispose() {
    teacherProfileUpdates.removeListener(_profileChanged);
    _presenceRefresh.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!widget.enabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final generation = ++_loadGeneration;
    _fetching = true;
    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await apiClient.get(
        '/api/consultation/teachers',
        queryParameters: {if (_filter.isNotEmpty) 'service_type': _filter},
      );
      final raw = ((response.data as Map?)?['data'] as Map?)?['list'];
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = null;
        _items
          ..clear()
          ..addAll(
            raw is List
                ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
                : const [],
          );
        _sortItems();
      });
    } on DioException catch (e) {
      if (mounted && generation == _loadGeneration && !silent) {
        setState(
          () => _error =
              (e.response?.data as Map?)?['message']?.toString() ?? '老师列表加载失败',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        _fetching = false;
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.enabled) {
      return const _EmptyState(
          icon: Icons.lock_clock_rounded,
          title: '私人专线暂未开放',
          subtitle: '开放时间请留意平台公告');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _LoadFailed(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey('private-line-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                  child: Row(children: [
                    PopupMenuButton<String>(
                      initialValue: _sort,
                      onSelected: (value) {
                        setState(() {
                          _sort = value;
                          _sortItems();
                        });
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: '综合排序', child: Text('综合排序')),
                        PopupMenuItem(value: '评分优先', child: Text('评分优先')),
                        PopupMenuItem(value: '接听优先', child: Text('接听优先')),
                        PopupMenuItem(value: '价格从低', child: Text('价格从低')),
                      ],
                      child: _FilterButton(text: _sort),
                    ),
                    const SizedBox(width: 7),
                    const _FilterButton(text: '资质已核验'),
                    const SizedBox(width: 7),
                    const _FilterButton(text: '语音服务'),
                  ]),
                ),
                SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                    children: [
                      _filterChip('全部', ''),
                      _filterChip('传统文化', 'traditional'),
                      _filterChip('情感倾听', 'listening'),
                      _filterChip('心理咨询', 'psychology'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                  icon: Icons.support_agent_rounded,
                  title: '暂无可接听老师',
                  subtitle: '老师上线后会显示在这里'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) => _TeacherCard(item: _items[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String text, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: ChoiceChip(
        label: Text(text),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
        selectedColor: const Color(0xFFE6FAF7),
        side: BorderSide(
            color: selected ? AppColors.primary : Colors.transparent),
        labelStyle: TextStyle(
            color: selected ? AppColors.primaryDark : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
        showCheckmark: false,
      ),
    );
  }

  void _sortItems() {
    num number(Map<String, dynamic> item, String key) =>
        item[key] is num ? item[key] as num : num.tryParse('${item[key]}') ?? 0;
    switch (_sort) {
      case '评分优先':
        _items
            .sort((a, b) => number(b, 'rating').compareTo(number(a, 'rating')));
        break;
      case '接听优先':
        _items.sort((a, b) {
          final aOnline = a['serviceStatus'] == 'online' ? 0 : 1;
          final bOnline = b['serviceStatus'] == 'online' ? 0 : 1;
          return aOnline.compareTo(bOnline);
        });
        break;
      case '价格从低':
        _items.sort((a, b) => number(a, 'privatePricePerMin')
            .compareTo(number(b, 'privatePricePerMin')));
        break;
    }
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: 3),
          const Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: AppColors.textHint),
        ]),
      );
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['nickname']?.toString() ?? '认证老师';
    final avatar = item['avatarUrl']?.toString() ?? '';
    final online = item['online'] == true;
    final specialties = item['specialties'] is List
        ? (item['specialties'] as List)
            .map((e) => e.toString())
            .take(3)
            .toList()
        : <String>[];
    final price =
        (item['privatePricePerMin'] as num?)?.toStringAsFixed(0) ?? '0';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              TeacherDetailPage(teacherId: (item['userId'] as num).toInt()),
        )),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider.withValues(alpha: .75)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 31,
                    backgroundColor: const Color(0xFFE6FAF7),
                    backgroundImage:
                        avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty
                        ? Text(name.characters.first,
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.primaryDark))
                        : null,
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color:
                                online ? AppColors.success : AppColors.textHint,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2))),
                  ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                          child: Text(name,
                              style: AppTextStyles.titleSmall,
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 7),
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFFFFB572), size: 17),
                    ]),
                    const SizedBox(height: 4),
                    Text(item['displayTitle']?.toString() ?? '平台认证老师',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint)),
                    if (specialties.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children:
                              specialties.map((e) => _MiniTag(e)).toList()),
                    ],
                    const SizedBox(height: 9),
                    Text(
                      '评分 ${(item['rating'] as num?)?.toStringAsFixed(1) ?? '5.0'}  ·  已服务 ${item['completedSessions'] ?? 0} 次',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$price币/分钟',
                      style: const TextStyle(
                          color: Color(0xFFD97706),
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 13),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(item['serviceStatus'] == 'busy' ? '咨询中' : '去咨询',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomList extends StatefulWidget {
  const _RoomList({required this.roomType, required this.enabled});
  final String roomType;
  final bool enabled;

  @override
  State<_RoomList> createState() => _RoomListState();
}

class _RoomListState extends State<_RoomList>
    with AutomaticKeepAliveClientMixin {
  final _items = <Map<String, dynamic>>[];
  final _voiceRoomController = VoiceRoomOverlayController.instance;
  bool _loading = true;
  String? _error;
  int? _lastActiveRoomId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lastActiveRoomId = _voiceRoomController.roomId;
    _voiceRoomController.addListener(_handleVoiceRoomChanged);
    _load();
  }

  void _handleVoiceRoomChanged() {
    final currentRoomId = _voiceRoomController.roomId;
    final roomClosed = _lastActiveRoomId != null && currentRoomId == null;
    _lastActiveRoomId = currentRoomId;
    if (roomClosed && mounted && widget.enabled) unawaited(_load());
  }

  @override
  void dispose() {
    _voiceRoomController.removeListener(_handleVoiceRoomChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.enabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await apiClient.get('/api/consultation/rooms',
          queryParameters: {'type': widget.roomType});
      final raw = ((response.data as Map?)?['data'] as Map?)?['list'];
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(raw is List
              ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
              : const []);
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _error =
            (e.response?.data as Map?)?['message']?.toString() ?? '房间加载失败');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    final roomId = (room['id'] as num?)?.toInt();
    if (roomId == null) return;
    final opened = VoiceRoomOverlayController.instance.open(roomId);
    if (!opened && mounted) showAppToast(context, '请先退出当前语音房');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.enabled) {
      return const _EmptyState(
          icon: Icons.lock_clock_rounded,
          title: '该广场暂未开放',
          subtitle: '开放时间请留意平台公告');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _LoadFailed(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .18),
          _EmptyState(
            icon: widget.roomType == 'master'
                ? Icons.mic_external_on_rounded
                : Icons.forum_outlined,
            title: widget.roomType == 'master' ? '暂时没有老师在线' : '还没有免费派对',
            subtitle:
                widget.roomType == 'master' ? '可以先去私人专线看看在线老师' : '点击右下角创建第一个房间',
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        key: PageStorageKey('room-${widget.roomType}'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => VoiceRoomDiscoveryCard(
          room: _items[i],
          onTap: () => _openRoom(_items[i]),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: const Color(0xFFE6FAF7),
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style:
                const TextStyle(fontSize: 10.5, color: AppColors.primaryDark)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 56, color: AppColors.textHint.withValues(alpha: .35)),
            const SizedBox(height: 14),
            Text(title, style: AppTextStyles.titleSmall),
            const SizedBox(height: 7),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
          ]),
        ),
      );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded,
            size: 48, color: AppColors.textHint),
        const SizedBox(height: 12),
        Text(message,
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
      ]));
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabHeaderDelegate(this.tabBar);
  final TabBar tabBar;
  @override
  double get minExtent => 50;
  @override
  double get maxExtent => 50;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox.expand(
        child: Material(
          color: const Color(0xFFEAF8FA),
          elevation: overlapsContent ? 1 : 0,
          child: tabBar,
        ),
      );
  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
