import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/date_utils.dart' as app_date;

/// 查找聊天记录：支持关键词、日期范围与图片/视频筛选。
class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({
    super.key,
    required this.conversationId,
    this.title,
    this.onLocate,
  });

  final int conversationId;
  final String? title;
  final ValueChanged<int>? onLocate;

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  final _keywordController = TextEditingController();
  final _list = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _searched = false;
  bool _mediaOnly = false;
  DateTimeRange? _dateRange;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _searchGeneration++;
    _keywordController.dispose();
    super.dispose();
  }

  String _dateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String get _dateLabel {
    final range = _dateRange;
    if (range == null) return '日期';
    String short(DateTime value) =>
        '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
    return range.start == range.end
        ? short(range.start)
        : '${short(range.start)}-${short(range.end)}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      helpText: '选择聊天日期',
      saveText: '确定',
      cancelText: '取消',
      confirmText: '确定',
      fieldStartHintText: '开始日期',
      fieldEndHintText: '结束日期',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _dateRange = selected);
    await _search();
  }

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _mediaOnly = false;
    });
    if (_keywordController.text.trim().isNotEmpty) {
      _search();
    } else {
      setState(() {
        _searched = false;
        _list.clear();
      });
    }
  }

  Future<void> _search() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty && _dateRange == null && !_mediaOnly) {
      showAppToast(context, '请输入关键词或选择筛选条件');
      return;
    }
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _searched = true;
      _list.clear();
    });
    try {
      final res = await apiClient.get(
        '/api/im/conversation/${widget.conversationId}/messages',
        queryParameters: {
          if (keyword.isNotEmpty) 'keyword': keyword,
          if (_dateRange != null) ...{
            'start_date': _dateValue(_dateRange!.start),
            'end_date': _dateValue(_dateRange!.end),
          },
          if (_mediaOnly) 'type': 'media',
          'page_size': 50,
        },
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final items = data?['list'] as List<dynamic>?;
      if (mounted && generation == _searchGeneration) {
        setState(() {
          for (final item in items ?? const []) {
            if (item is Map<String, dynamic>) {
              _list.add(Map<String, dynamic>.from(item));
            }
          }
          _loading = false;
        });
      }
    } on DioException catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loading = false);
        showAppToast(context, '聊天记录查询失败');
      }
    }
  }

  String? _mediaPreviewUrl(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    final content = message['content']?.toString() ?? '';
    String? raw;
    if (type == 'image') {
      raw = content;
    } else if (type == 'video') {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          raw = (decoded['coverUrl'] ?? decoded['url'])?.toString();
        }
      } catch (_) {
        raw = content;
      }
    }
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final base = apiClient.options.baseUrl;
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          FilterChip(
            key: const ValueKey('chat-search-date-filter'),
            selected: _dateRange != null,
            avatar: const Icon(Icons.calendar_month_outlined, size: 17),
            label: Text(_dateLabel),
            onSelected: (_) => _pickDateRange(),
          ),
          const SizedBox(width: 10),
          FilterChip(
            key: const ValueKey('chat-search-media-filter'),
            selected: _mediaOnly,
            avatar: const Icon(Icons.perm_media_outlined, size: 17),
            label: const Text('图片与视频'),
            onSelected: (selected) {
              setState(() => _mediaOnly = selected);
              if (!selected &&
                  _dateRange == null &&
                  _keywordController.text.trim().isEmpty) {
                setState(() {
                  _searched = false;
                  _list.clear();
                });
              } else {
                _search();
              }
            },
          ),
          if (_dateRange != null || _mediaOnly) ...[
            const SizedBox(width: 4),
            TextButton(onPressed: _clearFilters, child: const Text('清除')),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title != null ? '搜索：${widget.title}' : '查找聊天记录'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _keywordController,
              decoration: InputDecoration(
                hintText: '输入关键词搜索',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _search,
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
          ),
          _filterBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? Center(
                        child: Text(
                          '可按关键词、日期或图片与视频查找',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint),
                        ),
                      )
                    : _list.isEmpty
                        ? Center(
                            child: Text(
                              '未找到相关消息',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textHint),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _list.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, indent: 76, endIndent: 16),
                            itemBuilder: (context, index) {
                              final message = _list[index];
                              final content =
                                  message['content'] as String? ?? '';
                              final nickname =
                                  message['nickname'] as String? ?? '用户';
                              final createdAt = message['createdAt'] as String?;
                              final type = message['type'] as String? ?? 'text';
                              final mediaUrl = _mediaPreviewUrl(message);
                              var display = content;
                              if (type == 'image') display = '[图片]';
                              if (type == 'video') display = '[视频]';
                              if (type == 'voice') display = '[语音]';
                              if (type == 'post') display = '[帖子]';
                              if (type == 'profile') display = '[个人主页]';
                              if (type == 'voice_room') display = '[语音房邀请]';
                              return ListTile(
                                onTap: () {
                                  final id = (message['id'] as num?)?.toInt();
                                  if (id != null) {
                                    if (widget.onLocate != null) {
                                      widget.onLocate!(id);
                                    } else {
                                      Navigator.of(context).pop(id);
                                    }
                                  }
                                },
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: mediaUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          mediaUrl,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Icon(
                                                Icons.broken_image_outlined),
                                          ),
                                        ),
                                      )
                                    : CircleAvatar(
                                        backgroundColor: AppColors.primaryLight,
                                        child: Text(
                                          nickname.isNotEmpty
                                              ? nickname[0]
                                              : '?',
                                          style: AppTextStyles.bodySmall,
                                        ),
                                      ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nickname,
                                        style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                    if (createdAt?.isNotEmpty == true)
                                      Text(
                                        app_date.AppDateUtils.formatTime(
                                            createdAt!),
                                        style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textHint),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  display,
                                  style: AppTextStyles.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
