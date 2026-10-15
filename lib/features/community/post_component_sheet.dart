import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';

const _accent = AppColors.primary;
const _ink = Color(0xFF292B30);
const _muted = Color(0xFFB6B9BE);

class PostComponentSelection {
  const PostComponentSelection({
    required this.key,
    required this.title,
    required this.subtitle,
    this.referenceId,
  });

  final String key;
  final String title;
  final String subtitle;
  final int? referenceId;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'subtitle': subtitle,
    if (referenceId != null) 'referenceId': referenceId,
  };
}

Future<PostComponentSelection?> showPostComponentSheet(BuildContext context) {
  return showModalBottomSheet<PostComponentSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(27)),
    ),
    builder: (_) => const _PostComponentSheet(),
  );
}

class _PostComponentSheet extends StatefulWidget {
  const _PostComponentSheet();

  @override
  State<_PostComponentSheet> createState() => _PostComponentSheetState();
}

class _PostComponentSheetState extends State<_PostComponentSheet> {
  final _searchController = TextEditingController();
  final _parties = <Map<String, dynamic>>[];
  final _followedParties = <Map<String, dynamic>>[];
  bool _loading = true;
  int _tab = 0;

  static const _features = <_FeatureSpec>[
    _FeatureSpec(
      key: 'voice_match',
      title: '语音匹配',
      subtitle: '等待Ta的语音邀请',
      icon: Icons.graphic_eq_rounded,
      colors: [Color(0xFFCE7BFF), Color(0xFF7056EE)],
    ),
    _FeatureSpec(
      key: 'voice_party',
      title: '心声回响',
      subtitle: '听听大家在聊什么',
      icon: Icons.spatial_audio_off_rounded,
      colors: [Color(0xFF4066D8), Color(0xFF1C274D)],
    ),
    _FeatureSpec(
      key: 'interest_group',
      title: '兴趣群组',
      subtitle: '总有一群人懂你',
      icon: Icons.forum_rounded,
      colors: [Color(0xFF70DDD4), Color(0xFF35A9B5)],
    ),
    _FeatureSpec(
      key: 'avatar_studio',
      title: '个性形象馆',
      subtitle: '和我搭同款',
      icon: Icons.face_retouching_natural_rounded,
      colors: [Color(0xFFFFC95C), Color(0xFFFF7D7F)],
    ),
    _FeatureSpec(
      key: 'xuanyu_store',
      title: '玄遇好物',
      subtitle: '发现有温度的生活灵感',
      icon: Icons.storefront_rounded,
      colors: [Color(0xFFE886E5), Color(0xFF8552E7)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    _loadParties();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadParties() async {
    try {
      final response = await apiClient.get('/api/im/conversations');
      final data = (response.data as Map?)?['data'];
      final raw = data is Map ? data['list'] : null;
      if (raw is List && mounted) {
        setState(() {
          for (final item in raw.whereType<Map>()) {
            final map = Map<String, dynamic>.from(item);
            if (map['type'] == 'single') continue;
            _parties.add(map);
            if (map['followed'] == true || map['joined'] == true) {
              _followedParties.add(map);
            }
          }
        });
      }
    } on DioException {
      // 空状态本身就是合法状态，不用打断发布。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _partyName(Map<String, dynamic> item) =>
      (item['title'] ?? item['name'] ?? '群聊派对').toString();

  int? _partyId(Map<String, dynamic> item) {
    final raw = item['conversationId'] ?? item['id'];
    return raw is num ? raw.toInt() : int.tryParse('$raw');
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> source) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where(
          (item) =>
              _partyName(item).toLowerCase().contains(query) ||
              '${_partyId(item) ?? ''}'.contains(query),
        )
        .toList();
  }

  void _selectParty(Map<String, dynamic> item) {
    Navigator.of(context).pop(
      PostComponentSelection(
        key: 'group_party',
        title: _partyName(item),
        subtitle: '群聊派对',
        referenceId: _partyId(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.91,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD8DADD),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 52),
            child: Row(
              children: [
                _tabButton(0, '群聊派对'),
                const Spacer(),
                _tabButton(1, '更多功能'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 190),
              child: _tab == 0 ? _buildParties() : _buildFeatures(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int value, String label) {
    final selected = _tab == value;
    return InkWell(
      onTap: () => setState(() => _tab = value),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? _ink : const Color(0xFF9EA1A7),
              fontSize: 18,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 7),
          AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            width: selected ? 28 : 0,
            height: 3.5,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParties() {
    return ListView(
      key: const ValueKey('parties'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索派对ID/派对群主/派对名称',
            hintStyle: const TextStyle(color: _muted, fontSize: 16),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _muted,
              size: 28,
            ),
            filled: true,
            fillColor: const Color(0xFFF7F7F8),
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _partySection('我的派对', _filtered(_parties), '暂无群聊派对'),
        const SizedBox(height: 32),
        _partySection('我的关注', _filtered(_followedParties), '暂无关注的群聊派对'),
      ],
    );
  }

  Widget _partySection(
    String title,
    List<Map<String, dynamic>> items,
    String emptyText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (items.isEmpty)
          Container(
            height: 170,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              emptyText,
              style: const TextStyle(color: _muted, fontSize: 16),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                for (final item in items)
                  ListTile(
                    onTap: () => _selectParty(item),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF65DDD6), Color(0xFF6C82F2)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      _partyName(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 16),
                    ),
                    subtitle: Text(
                      '派对ID ${_partyId(item) ?? '--'}',
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    trailing: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: _accent,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFeatures() {
    return ListView.separated(
      key: const ValueKey('features'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: _features.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final feature = _features[index];
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).pop(
            PostComponentSelection(
              key: feature.key,
              title: feature.title,
              subtitle: feature.subtitle,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: feature.colors,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: feature.colors.last.withValues(alpha: 0.22),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(feature.icon, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature.title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        feature.subtitle,
                        style: const TextStyle(color: _muted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFFD2D4D7),
                  size: 24,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureSpec {
  const _FeatureSpec({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
}
