import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';

const _accent = AppColors.primary;
const _ink = Color(0xFF25272B);
const _muted = Color(0xFFB5B8BE);
const _section = Color(0xFFFAFAFA);

/// 发布时需要随作品保存的完整权限设置。
class PostPublishSettings {
  const PostPublishSettings({
    this.visibility = 1,
    this.disableDownloadCopy = false,
    this.disableForward = false,
    this.commentPermission = 'everyone',
    this.originalDeclaration = false,
    this.repostDeclaration = false,
    this.aiGenerated = false,
    this.excludedUserIds = const <int>{},
  });

  /// 1 广场；2 仅自己；3 仅主页；4 仅陌生人；5 仅话题广场。
  final int visibility;
  final bool disableDownloadCopy;
  final bool disableForward;
  final String commentPermission;
  final bool originalDeclaration;
  final bool repostDeclaration;
  final bool aiGenerated;
  final Set<int> excludedUserIds;

  bool get allowComment => commentPermission != 'none';

  String get visibilityLabel => switch (visibility) {
        2 => '仅自己可见',
        3 => '仅主页可见',
        4 => '仅陌生人可见',
        5 => '仅话题广场可见',
        _ => excludedUserIds.isEmpty ? '广场可见' : '广场可见 · 有排除',
      };

  String get commentPermissionLabel => switch (commentPermission) {
        'following' => '我关注的人可评',
        'followers' => '关注我的人可评',
        'none' => '所有人都不可评论',
        _ => '所有人可评',
      };

  PostPublishSettings copyWith({
    int? visibility,
    bool? disableDownloadCopy,
    bool? disableForward,
    String? commentPermission,
    bool? originalDeclaration,
    bool? repostDeclaration,
    bool? aiGenerated,
    Set<int>? excludedUserIds,
  }) {
    return PostPublishSettings(
      visibility: visibility ?? this.visibility,
      disableDownloadCopy: disableDownloadCopy ?? this.disableDownloadCopy,
      disableForward: disableForward ?? this.disableForward,
      commentPermission: commentPermission ?? this.commentPermission,
      originalDeclaration: originalDeclaration ?? this.originalDeclaration,
      repostDeclaration: repostDeclaration ?? this.repostDeclaration,
      aiGenerated: aiGenerated ?? this.aiGenerated,
      excludedUserIds: excludedUserIds ?? this.excludedUserIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'visibility': visibility,
        'disableDownloadCopy': disableDownloadCopy,
        'disableForward': disableForward,
        'commentPermission': commentPermission,
        'originalDeclaration': originalDeclaration,
        'repostDeclaration': repostDeclaration,
        'aiGenerated': aiGenerated,
        'excludedUserIds': excludedUserIds.toList(),
      };

  static PostPublishSettings fromJson(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const PostPublishSettings();
      }
    }
    if (raw is! Map) return const PostPublishSettings();
    final ids = <int>{};
    final rawIds = raw['excludedUserIds'];
    if (rawIds is List) {
      for (final value in rawIds) {
        final id = value is num ? value.toInt() : int.tryParse('$value');
        if (id != null && id > 0) ids.add(id);
      }
    }
    final rawVisibility = (raw['visibility'] as num?)?.toInt() ?? 1;
    final visibility =
        rawVisibility >= 1 && rawVisibility <= 5 ? rawVisibility : 1;
    return PostPublishSettings(
      visibility: visibility,
      disableDownloadCopy: raw['disableDownloadCopy'] == true,
      disableForward: raw['disableForward'] == true,
      commentPermission: (raw['commentPermission'] ?? 'everyone').toString(),
      originalDeclaration: raw['originalDeclaration'] == true,
      repostDeclaration: raw['repostDeclaration'] == true,
      aiGenerated: raw['aiGenerated'] == true,
      excludedUserIds: ids,
    );
  }
}

/// 复用发布时的可见范围选择页，保存作者已发布作品的新范围。
Future<PostPublishSettings?> editPublishedPostVisibility(
  BuildContext context,
  int postId,
) async {
  try {
    final response =
        await apiClient.get('/api/community/post/$postId/visibility');
    final initial = PostPublishSettings.fromJson(
      (response.data as Map?)?['data'],
    );
    if (!context.mounted) return null;
    final selected = await Navigator.of(context).push<PostPublishSettings>(
      MaterialPageRoute(
        builder: (_) => PostPublishSettingsPage(
          initial: initial,
          visibilityOnly: true,
        ),
      ),
    );
    if (selected == null || !context.mounted) return null;
    final saved = await apiClient.patch(
      '/api/community/post/$postId/visibility',
      data: {
        'visibility': selected.visibility,
        'excludedUserIds': selected.excludedUserIds.toList(),
      },
    );
    final value = PostPublishSettings.fromJson(
      (saved.data as Map?)?['data'],
    );
    if (context.mounted) showAppToast(context, '可见范围已更新');
    return value;
  } on DioException catch (error) {
    final message = error.response?.data is Map
        ? (error.response?.data as Map)['message']?.toString()
        : null;
    if (context.mounted) showAppToast(context, message ?? '修改失败，请重试');
    return null;
  }
}

class PostPublishSettingsPage extends StatefulWidget {
  const PostPublishSettingsPage({
    super.key,
    required this.initial,
    this.visibilityOnly = false,
  });

  final PostPublishSettings initial;
  final bool visibilityOnly;

  @override
  State<PostPublishSettingsPage> createState() =>
      _PostPublishSettingsPageState();
}

class _PostPublishSettingsPageState extends State<PostPublishSettingsPage> {
  late PostPublishSettings _value = widget.initial;

  Future<void> _pickCommentPermission() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8F8F8),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _CommentPermissionSheet(
        selected: _value.commentPermission,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _value = _value.copyWith(commentPermission: selected));
    }
  }

  Future<void> _pickExcludedUsers() async {
    final selected = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        builder: (_) => PostAudienceExclusionPage(
          initialSelection: _value.excludedUserIds,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _value = _value.copyWith(
            visibility: 1,
            excludedUserIds: selected,
          ));
    }
  }

  void _setVisibility(int value) {
    if (value == 1 && _value.visibility == 1) {
      _pickExcludedUsers();
      return;
    }
    setState(() => _value = _value.copyWith(visibility: value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 38, color: _ink),
        ),
        title: Text(
          widget.visibilityOnly ? '修改可见范围' : '发布设置',
          style: const TextStyle(
              fontSize: 20, color: _ink, fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_value),
            child: const Text(
              '完成',
              style: TextStyle(
                color: _accent,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        children: [
          const _SectionLabel('可见范围'),
          _VisibilityTile(
            title: '广场可见',
            subtitle: _value.excludedUserIds.isEmpty
                ? '所有人可见'
                : '已排除 ${_value.excludedUserIds.length} 人',
            selected: _value.visibility == 1,
            onTap: () => _setVisibility(1),
          ),
          _VisibilityTile(
            title: '仅主页可见',
            subtitle: '他人只能在你的主页看见',
            selected: _value.visibility == 3,
            onTap: () => _setVisibility(3),
          ),
          _VisibilityTile(
            title: '不给Ta看',
            subtitle: _value.excludedUserIds.isEmpty
                ? '指定用户不可见'
                : '已选择 ${_value.excludedUserIds.length} 人',
            showArrow: true,
            onTap: _pickExcludedUsers,
          ),
          _VisibilityTile(
            title: '仅陌生人可见',
            subtitle: '你关注的、关注你的人均不可见',
            selected: _value.visibility == 4,
            onTap: () => _setVisibility(4),
          ),
          _VisibilityTile(
            title: '仅话题广场可见',
            subtitle: '只能在标签对应的话题广场中可见',
            selected: _value.visibility == 5,
            onTap: () => _setVisibility(5),
          ),
          _VisibilityTile(
            title: '仅自己可见',
            selected: _value.visibility == 2,
            onTap: () => _setVisibility(2),
          ),
          if (!widget.visibilityOnly) ...[
            const _SectionLabel('权限'),
            _SettingSwitch(
              title: '禁止下载和复制',
              subtitle: '包含作品图片视频下载和正文复制',
              value: _value.disableDownloadCopy,
              onChanged: (value) => setState(
                  () => _value = _value.copyWith(disableDownloadCopy: value)),
            ),
            _SettingSwitch(
              title: '禁止转发',
              value: _value.disableForward,
              onChanged: (value) => setState(
                  () => _value = _value.copyWith(disableForward: value)),
            ),
            _NavigationSetting(
              title: '哪些人可以评论我',
              value: _value.commentPermissionLabel,
              onTap: _pickCommentPermission,
            ),
            const _SectionLabel('用户声明'),
            _SettingSwitch(
              title: '原创声明',
              subtitle: '声明此内容为原创作品，获得“已声明原创”标识。',
              value: _value.originalDeclaration,
              onChanged: (value) => setState(() => _value = _value.copyWith(
                    originalDeclaration: value,
                    repostDeclaration: value ? false : null,
                  )),
            ),
            _SettingSwitch(
              title: '转载声明',
              subtitle: '申明此内容非本人原创内容，可免于侵权被删除',
              value: _value.repostDeclaration,
              onChanged: (value) => setState(() => _value = _value.copyWith(
                    repostDeclaration: value,
                    originalDeclaration: value ? false : null,
                  )),
            ),
            _SettingSwitch(
              title: '作品含AI合成内容',
              subtitle: '使用AI生成或合成的文字、图片、音视频请主动声明，发布后将显示标识',
              value: _value.aiGenerated,
              onChanged: (value) =>
                  setState(() => _value = _value.copyWith(aiGenerated: value)),
            ),
          ],
          const SizedBox(height: 36),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _section,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Text(text,
          style: const TextStyle(color: _muted, fontSize: 15, height: 1.2)),
    );
  }
}

class _VisibilityTile extends StatelessWidget {
  const _VisibilityTile({
    required this.title,
    this.subtitle,
    this.selected = false,
    this.showArrow = false,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool showArrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 20, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _ink, fontSize: 17, height: 1.2)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!,
                        style: const TextStyle(
                            color: _muted, fontSize: 14, height: 1.3)),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _accent, size: 28)
            else if (showArrow)
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 28),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _ink, fontSize: 17)),
                if (subtitle != null) ...[
                  const SizedBox(height: 9),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: _muted, fontSize: 13.5, height: 1.4)),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _accent.withValues(alpha: 0.42),
            activeThumbColor: _accent,
          ),
        ],
      ),
    );
  }
}

class _NavigationSetting extends StatelessWidget {
  const _NavigationSetting({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 17, 20),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(color: _ink, fontSize: 17)),
            ),
            Text(value, style: const TextStyle(color: _muted, fontSize: 15)),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 26),
          ],
        ),
      ),
    );
  }
}

class _CommentPermissionSheet extends StatelessWidget {
  const _CommentPermissionSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    const values = <(String, String)>[
      ('everyone', '所有人可评'),
      ('following', '我关注的人可评'),
      ('followers', '关注我的人可评'),
      ('none', '所有人都不可评论'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        MediaQuery.paddingOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE7E7E9),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                for (final option in values)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(option.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(option.$2,
                                style:
                                    const TextStyle(color: _ink, fontSize: 17)),
                          ),
                          if (selected == option.$1)
                            const Icon(Icons.check_circle_rounded,
                                color: _accent, size: 25),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PostAudienceExclusionPage extends StatefulWidget {
  const PostAudienceExclusionPage({
    super.key,
    required this.initialSelection,
  });

  final Set<int> initialSelection;

  @override
  State<PostAudienceExclusionPage> createState() =>
      _PostAudienceExclusionPageState();
}

class _PostAudienceExclusionPageState extends State<PostAudienceExclusionPage> {
  final _queryController = TextEditingController();
  final _selected = <int>{};
  final Map<String, List<Map<String, dynamic>>> _lists = {
    '最近聊天': [],
    '我关注的': [],
    '关注我的': [],
  };
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelection);
    _queryController.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<Object?> _safeGet(String path) async {
    try {
      return (await apiClient.get(path)).data;
    } on DioException {
      return null;
    }
  }

  List<Map<String, dynamic>> _extractList(Object? body) {
    if (body is! Map) return [];
    final data = body['data'];
    final raw = data is Map ? data['list'] : data;
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      final peer = map['peer'];
      if (peer is Map) {
        for (final entry in peer.entries) {
          map.putIfAbsent(entry.key.toString(), () => entry.value);
        }
      }
      return map;
    }).toList();
  }

  int? _userId(Map<String, dynamic> item) {
    for (final key in const [
      'userId',
      'targetUserId',
      'peerUserId',
      'otherUserId',
      'id'
    ]) {
      final raw = item[key];
      final id = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (id != null && id > 0) return id;
    }
    return null;
  }

  String _name(Map<String, dynamic> item) =>
      (item['nickname'] ?? item['title'] ?? item['name'] ?? '玄遇用户').toString();

  Future<void> _load() async {
    final results = await Future.wait([
      _safeGet('/api/im/conversations'),
      _safeGet('/api/community/user/me/following-list'),
      _safeGet('/api/community/user/me/followers'),
    ]);
    if (!mounted) return;
    final recent = _extractList(results[0])
        .where((item) => item['type'] == null || item['type'] == 'single')
        .where((item) => _userId(item) != null)
        .toList();
    final following = _extractList(results[1]);
    final followers = _extractList(results[2]);
    setState(() {
      _lists['最近聊天'] = recent;
      _lists['我关注的'] = following;
      _lists['关注我的'] = followers;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _visibleItems {
    final source = _lists[_lists.keys.elementAt(_tab)] ?? const [];
    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where((item) => _name(item).toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _lists.keys.toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 38, color: _ink),
        ),
        title: const Text('不给Ta看',
            style: TextStyle(
                color: _ink, fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(Set<int>.from(_selected)),
            child: const Text('完成',
                style: TextStyle(color: _accent, fontSize: 17)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _tab = i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tabs[i],
                              style: TextStyle(
                                color: _tab == i ? _ink : _muted,
                                fontSize: 15,
                                fontWeight: _tab == i
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              )),
                          const SizedBox(height: 7),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: _tab == i ? 24 : 0,
                            height: 3,
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: '搜索备注、昵称',
                hintStyle: const TextStyle(color: _muted, fontSize: 16),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _muted, size: 27),
                filled: true,
                fillColor: const Color(0xFFF7F7F8),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _visibleItems.isEmpty
                    ? const Center(
                        child: Text('这里暂时还没有人',
                            style: TextStyle(color: _muted, fontSize: 15)))
                    : ListView.separated(
                        itemCount: _visibleItems.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 82, color: Color(0xFFF1F1F2)),
                        itemBuilder: (context, index) {
                          final item = _visibleItems[index];
                          final id = _userId(item);
                          final selected = id != null && _selected.contains(id);
                          final avatar =
                              (item['avatarUrl'] ?? item['avatar'])?.toString();
                          return InkWell(
                            onTap: id == null
                                ? null
                                : () => setState(() {
                                      selected
                                          ? _selected.remove(id)
                                          : _selected.add(id);
                                    }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 27,
                                    backgroundColor: const Color(0xFFF0F7F7),
                                    backgroundImage:
                                        avatar != null && avatar.isNotEmpty
                                            ? NetworkImage(avatar)
                                            : null,
                                    child: avatar == null || avatar.isEmpty
                                        ? Text(_name(item).characters.first,
                                            style: const TextStyle(
                                                color: _accent,
                                                fontWeight: FontWeight.w700))
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(_name(item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _ink, fontSize: 17)),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 27,
                                    height: 27,
                                    decoration: BoxDecoration(
                                      color: selected ? _accent : Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected
                                            ? _accent
                                            : const Color(0xFFCACDD1),
                                        width: 1.4,
                                      ),
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check_rounded,
                                            color: Colors.white, size: 18)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
