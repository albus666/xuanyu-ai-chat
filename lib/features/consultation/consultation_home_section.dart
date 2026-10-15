import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/foreground_refresh.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'create_voice_room_page.dart';
import 'teacher_detail_page.dart';
import 'voice_room_overlay_controller.dart';
import 'voice_room_design.dart';

class ConsultationHomeSection extends StatefulWidget {
  const ConsultationHomeSection({super.key});

  @override
  State<ConsultationHomeSection> createState() =>
      _ConsultationHomeSectionState();
}

class _ConsultationHomeSectionState extends State<ConsultationHomeSection> {
  static const _tabs = ['私人专线', '在线名师', '免费派对'];

  late final ForegroundRefresh _presenceRefresh;
  bool _fetching = false;
  int _selected = 0;
  bool _loading = true;
  bool _isTeacher = false;
  String? _error;
  String _filter = '';
  String _sort = '综合排序';
  Map<String, dynamic> _config = const {};
  List<Map<String, dynamic>> _items = const [];
  int _loadGeneration = 0;
  final _voiceRoomController = VoiceRoomOverlayController.instance;
  int? _lastActiveRoomId;

  @override
  void initState() {
    super.initState();
    _presenceRefresh = ForegroundRefresh(
      refresh: () => _load(silent: true),
      isVisible: () =>
          mounted &&
          !_fetching &&
          _selected == 0 &&
          TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    )..attach();
    _lastActiveRoomId = _voiceRoomController.roomId;
    _voiceRoomController.addListener(_handleVoiceRoomChanged);
    _loadHeader();
    _load();
  }

  void _handleVoiceRoomChanged() {
    final currentRoomId = _voiceRoomController.roomId;
    final roomClosed = _lastActiveRoomId != null && currentRoomId == null;
    _lastActiveRoomId = currentRoomId;
    if (roomClosed && mounted && _selected != 0) unawaited(_load());
  }

  @override
  void dispose() {
    _presenceRefresh.dispose();
    _voiceRoomController.removeListener(_handleVoiceRoomChanged);
    super.dispose();
  }

  Future<void> _loadHeader() async {
    Map<String, dynamic> config = const {};
    var teacher = false;
    try {
      final response = await apiClient.get('/api/consultation/config');
      final raw = (response.data as Map?)?['data'];
      if (raw is Map) config = Map<String, dynamic>.from(raw);
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

  Future<void> _load({bool silent = false}) async {
    _fetching = true;
    final generation = ++_loadGeneration;
    final selectedTab = _selected;
    setState(() {
      if (!silent) {
        _loading = true;
        _error = null;
      }
    });
    try {
      final response = selectedTab == 0
          ? await apiClient.get(
              '/api/consultation/teachers',
              queryParameters: {
                if (_filter.isNotEmpty) 'service_type': _filter,
              },
            )
          : await apiClient.get(
              '/api/consultation/rooms',
              queryParameters: {'type': selectedTab == 1 ? 'master' : 'free'},
            );
      final raw = ((response.data as Map?)?['data'] as Map?)?['list'];
      if (!mounted || generation != _loadGeneration) return;
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      if (selectedTab == 0) _sortTeachers(items);
      setState(() {
        _items = items;
        _error = null;
      });
    } on DioException catch (e) {
      if (mounted && generation == _loadGeneration && !silent) {
        setState(
          () => _error =
              (e.response?.data as Map?)?['message']?.toString() ?? '服务加载失败',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        _fetching = false;
        setState(() => _loading = false);
      }
    }
  }

  void _sortTeachers(List<Map<String, dynamic>> items) {
    num number(Map<String, dynamic> item, String key) =>
        item[key] is num ? item[key] as num : num.tryParse('${item[key]}') ?? 0;
    switch (_sort) {
      case '评分优先':
        items
            .sort((a, b) => number(b, 'rating').compareTo(number(a, 'rating')));
      case '接听优先':
        items.sort((a, b) {
          final aOnline =
              a['serviceStatus'] == 'online' || a['online'] == true ? 0 : 1;
          final bOnline =
              b['serviceStatus'] == 'online' || b['online'] == true ? 0 : 1;
          return aOnline.compareTo(bOnline);
        });
      case '价格从低':
        items.sort((a, b) => number(a, 'privatePricePerMin')
            .compareTo(number(b, 'privatePricePerMin')));
    }
  }

  bool get _canCreateRoom {
    if (_selected == 1) {
      return _isTeacher && _config['masterPlazaEnabled'] != false;
    }
    return _selected == 2 && _config['freePlazaEnabled'] != false;
  }

  Future<void> _createRoom() async {
    if (!_canCreateRoom) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CreateVoiceRoomPage(roomType: _selected == 1 ? 'master' : 'free'),
      ),
    );
    if (created == true && mounted) _load();
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    final roomId = (room['id'] as num?)?.toInt();
    if (roomId == null) return;
    final opened = VoiceRoomOverlayController.instance.open(roomId);
    if (!opened && mounted) showAppToast(context, '请先退出当前语音房');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ServiceTabs(
          selected: _selected,
          tabs: _tabs,
          onChanged: (index) {
            if (index == _selected) return;
            setState(() => _selected = index);
            _load();
          },
        ),
        if (_selected == 0) ...[
          const SizedBox(height: 12),
          _buildTeacherFilters(),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _buildSectionContent(),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSectionContent() {
    if (_loading) {
      return const SizedBox(
        key: ValueKey('loading'),
        height: 150,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_error != null) return _InlineError(message: _error!, onRetry: _load);
    if (_selected == 0) {
      if (_items.isEmpty) return const _EmptyPreview(type: 0);
      return Column(
        key: const ValueKey('teacher-items'),
        children: [
          for (var index = 0; index < _items.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TeacherPreview(
                item: _items[index],
                featured: index == 0,
              ),
            ),
        ],
      );
    }
    return Stack(
      key: ValueKey('room-items-$_selected'),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: _canCreateRoom ? 128 : 68),
          child: _items.isEmpty
              ? _EmptyPreview(type: _selected)
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (_, index) => VoiceRoomDiscoveryCard(
                    room: _items[index],
                    onTap: () => _openRoom(_items[index]),
                  ),
                ),
        ),
        Positioned(
          right: 4,
          bottom: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoomFloatingAction(
                tooltip: '刷新房间',
                label: '刷新',
                icon: Icons.refresh_rounded,
                onTap: _load,
              ),
              if (_canCreateRoom) ...[
                const SizedBox(height: 10),
                _RoomFloatingAction(
                  tooltip: _selected == 1 ? '创建在线名师房' : '创建免费派对',
                  label: '创建房间',
                  icon: Icons.add_home_work_rounded,
                  accent: true,
                  onTap: _createRoom,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherFilters() {
    return Column(children: [
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            PopupMenuButton<String>(
              initialValue: _sort,
              onSelected: (value) {
                setState(() => _sort = value);
                _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: '综合排序', child: Text('综合排序')),
                PopupMenuItem(value: '评分优先', child: Text('评分优先')),
                PopupMenuItem(value: '接听优先', child: Text('接听优先')),
                PopupMenuItem(value: '价格从低', child: Text('价格从低')),
              ],
              child: _InlineFilter(text: _sort, expandable: true),
            ),
            const _FilterDivider(),
            const _InlineFilter(text: '资质已核验'),
            const _FilterDivider(),
            const _InlineFilter(text: '语音服务'),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            _category('全部', ''),
            _category('传统文化', 'traditional'),
            _category('情感倾听', 'listening'),
            _category('心理咨询', 'psychology'),
          ],
        ),
      ),
    ]);
  }

  Widget _category(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          if (selected) return;
          setState(() => _filter = value);
          _load();
        },
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE6FAF7) : Colors.white60,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0x00FFFFFF),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primaryDark : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceTabs extends StatelessWidget {
  const _ServiceTabs({
    required this.selected,
    required this.tabs,
    required this.onChanged,
  });

  final int selected;
  final List<String> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x287A8794))),
        ),
        child: Row(
          children: List.generate(tabs.length, (index) {
            final active = selected == index;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(index),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 13, 3, 0),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      tabs[index],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? AppColors.primaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: active ? 38 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: active ? AppColors.primaryGradient : null,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      );
}

class _TeacherPreview extends StatelessWidget {
  const _TeacherPreview({required this.item, required this.featured});
  final Map<String, dynamic> item;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final avatar = item['avatarUrl']?.toString() ?? '';
    final name = item['nickname']?.toString() ?? '认证老师';
    final online = item['serviceStatus'] == 'online';
    final tags = item['specialties'] is List
        ? (item['specialties'] as List)
            .map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .take(3)
            .toList()
        : <String>[];
    final teacherId = (item['userId'] as num?)?.toInt();
    void open() {
      if (teacherId == null) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TeacherDetailPage(teacherId: teacherId),
      ));
    }

    final price =
        (item['privatePricePerMin'] as num?)?.toStringAsFixed(0) ?? '0';
    return Material(
      color: featured ? const Color(0xFFF3FBFA) : Colors.transparent,
      borderRadius: BorderRadius.circular(featured ? 20 : 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(featured ? 20 : 14),
        onTap: open,
        child: Ink(
          padding:
              EdgeInsets.fromLTRB(featured ? 16 : 4, 14, featured ? 14 : 4, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(featured ? 20 : 14),
            border: featured
                ? Border.all(color: const Color(0x4D85DDD7))
                : const Border(bottom: BorderSide(color: Color(0x247A8794))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              CircleAvatar(
                radius: featured ? 37 : 29,
                backgroundColor: const Color(0xFFE6FAF7),
                backgroundImage:
                    avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty
                    ? Text(
                        name.characters.first,
                        style: AppTextStyles.titleMedium
                            .copyWith(color: AppColors.primaryDark),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? AppColors.success : AppColors.textHint,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.verified_rounded,
                        size: 17, color: Color(0xFFFFB572)),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    '${online ? '可立即咨询' : item['serviceStatus'] == 'busy' ? '咨询中' : item['isOnline'] == true ? '在线 · 休息中' : '暂时离线'} · ${item['displayTitle']?.toString() ?? '认证名师'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: online
                            ? AppColors.primaryDark
                            : AppColors.textHint),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: tags.map((tag) => _MiniTag(tag)).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '评分 ${(item['rating'] as num?)?.toStringAsFixed(1) ?? '5.0'} · 已服务 ${item['completedSessions'] ?? 0}次',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '$price玄遇币/分钟',
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 13),
              InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    item['serviceStatus'] == 'busy' ? '咨询中' : '去咨询',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _RoomFloatingAction extends StatelessWidget {
  const _RoomFloatingAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          elevation: 8,
          shadowColor: Colors.black26,
          color: accent ? AppColors.primary : const Color(0xFFF9FAFA),
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  icon,
                  color: accent ? Colors.white : const Color(0xFF176762),
                  size: 20,
                ),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: accent ? Colors.white : const Color(0xFF29313A),
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

class _InlineFilter extends StatelessWidget {
  const _InlineFilter({required this.text, this.expandable = false});
  final String text;
  final bool expandable;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            text,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          if (expandable) ...[
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 15, color: AppColors.textHint),
          ],
        ]),
      );
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        color: const Color(0x337A8794),
      );
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE6FAF7),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9.5, color: AppColors.primaryDark),
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 130,
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(message),
          ),
        ),
      );
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.type});
  final int type;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 130,
        child: Center(
          child: Text(
            type == 0 ? '暂无可接听老师' : '暂无正在进行的房间',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          ),
        ),
      );
}
