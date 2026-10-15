import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/post_share.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_share_more_button.dart';
import 'post_card.dart';
import 'post_detail_page.dart';

/// 话题聚合页：某话题下的帖子列表
class TopicFeedPage extends StatefulWidget {
  const TopicFeedPage({super.key, required this.topicId, required this.topicName});

  final int topicId;
  final String topicName;

  @override
  State<TopicFeedPage> createState() => _TopicFeedPageState();
}

class _TopicFeedPageState extends State<TopicFeedPage> {
  final _list = <Map<String, dynamic>>[];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _load();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _currentUserId = prefs.getInt(AppConstants.keyUserId));
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final res = await apiClient.get(
        '/api/community/topic/${widget.topicId}/feed',
        queryParameters: {'page': _page, 'page_size': 20},
      );
      final body = res.data as Map<String, dynamic>?;
      final data = body?['data'] as Map<String, dynamic>?;
      final items = data?['list'] as List<dynamic>?;
      if (items != null && mounted) {
        setState(() {
          for (final e in items) {
            if (e is Map<String, dynamic>) _list.add(Map<String, dynamic>.from(e));
          }
          _page++;
          _hasMore = data?['hasMore'] == true;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleLike(int postId) async {
    try {
      final res = await apiClient.post('/api/community/post/$postId/like');
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final i = _list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) {
            _list[i]['liked'] = data['liked'] == true;
            _list[i]['likeCount'] = data['likeCount'];
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
          final i = _list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) _list[i]['favorited'] = data['favorited'] == true;
        });
      }
    } on DioException catch (_) {}
  }

  void _handleShare(int postId) {
    Map<String, dynamic>? item;
    for (final e in _list) {
      if ((e['id'] as num?)?.toInt() == postId) { item = e; break; }
    }
    if (item == null) return;
    showSharePostSheet(context, item, onShared: (count) {
      if (count != null && mounted) {
        setState(() {
          final i = _list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) _list[i]['shareCount'] = count;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.communityScaffold,
      appBar: AppBar(
        backgroundColor: AppColors.communityScaffold,
        elevation: 0,
        title: Text('#${widget.topicName}', style: AppTextStyles.titleMedium),
        actions: [
          AppShareMoreButton(
            title: '#${widget.topicName}',
            shareText: '我在玄遇发现了话题 #${widget.topicName}，来一起看看大家正在聊什么。',
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.communityBodyGradient),
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _list.clear();
              _page = 1;
              _hasMore = true;
            });
            await _load();
          },
          child: _list.isEmpty && !_loading
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: Center(
                      child: Text('暂无内容', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _list.length + (_loading ? 1 : 0) + (_hasMore && _list.isNotEmpty && !_loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _list.length) {
                      if (_loading) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                        );
                      }
                      return Center(child: TextButton(onPressed: _load, child: const Text('加载更多')));
                    }
                    final item = _list[index];
                    return PostCard(
                      item: item,
                      heroTagSuffix: 'topic_$index',
                      integrated: true,
                      showBottomDivider: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailPage(postId: item['id'] as int, initialItem: item),
                        ),
                      ),
                      onTopicTap: (id, name) => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TopicFeedPage(topicId: id, topicName: name)),
                      ),
                      onLike: _handleLike,
                      onFavorite: _handleFavorite,
                      onShare: _handleShare,
                      currentUserId: _currentUserId,
                      onDeleted: (postId) => setState(() => _list.removeWhere((e) => (e['id'] as num?)?.toInt() == postId)),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
