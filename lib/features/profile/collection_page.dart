import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/post_share.dart';
import '../../core/theme/app_text_styles.dart';
import '../community/post_card.dart';
import '../community/profile_post_feed.dart';
import '../community/post_detail_page.dart';
import '../community/topic_feed_page.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late final _feed = ProfilePostFeed(
      () => apiClient.options.headers['Authorization'] == null
          ? null
          : '/api/community/favorites',
      pageSize: 20);
  List<Map<String, dynamic>> get _list => _feed.items;
  bool get _loading => _feed.loading;
  bool get _loadingMore => _feed.loading;
  bool get _hasMore => _feed.hasMore;
  final _busyActions = <String>{};
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_feedChanged);
    apiSessionChanges.addListener(_onSessionChanged);
    _loadCurrentUserId();
    _load();
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _currentUserId = null;
      _busyActions.clear();
    });
    _loadCurrentUserId();
    if (apiClient.options.headers['Authorization'] != null) _feed.refresh();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _feed.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    final session = apiSessionChanges.value;
    final prefs = await SharedPreferences.getInstance();
    if (mounted && session == apiSessionChanges.value) {
      setState(() => _currentUserId =
          apiClient.options.headers['Authorization'] == null
              ? null
              : prefs.getInt(AppConstants.keyUserId));
    }
  }

  Future<void> _load() => _feed.load();
  Future<void> _reload() async {
    if (mounted) await _feed.refresh();
  }

  Future<void> _handleLike(int postId) => _updatePost(postId, 'like');
  Future<void> _handleFavorite(int postId) => _updatePost(postId, 'favorite');

  Future<void> _updatePost(int postId, String action) async {
    final key = '$postId:$action';
    if (!_busyActions.add(key)) return;
    final session = apiSessionChanges.value;
    try {
      final res = await apiClient.post('/api/community/post/$postId/$action',
          options: Options(headers: {
            'Authorization': apiClient.options.headers['Authorization']
          }));
      if (!mounted || session != apiSessionChanges.value) return;
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final field = action == 'like' ? 'liked' : 'favorited';
      if (body is! Map ||
          (body['code'] != null && body['code'] != 0) ||
          data is! Map ||
          data[field] is! bool ||
          (action == 'like' && data['likeCount'] is! num)) {
        throw const FormatException('操作结果无效');
      }
      setState(() {
        final i = _list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
        if (i >= 0) {
          _list[i][field] = data[field];
          if (action == 'like') _list[i]['likeCount'] = data['likeCount'];
          if (action == 'favorite' && data['favorited'] == false) {
            _list.removeAt(i);
          }
        }
      });
      if (action == 'favorite' && data['favorited'] == false) {
        await _feed.refresh();
      }
    } catch (_) {
      if (mounted && session == apiSessionChanges.value) {
        showAppToast(context, '操作失败，请重试');
      }
    } finally {
      if (session == apiSessionChanges.value) _busyActions.remove(key);
    }
  }

  void _handleShare(int postId) {
    Map<String, dynamic>? item;
    for (final e in _list) {
      if ((e['id'] as num?)?.toInt() == postId) {
        item = e;
        break;
      }
    }
    if (item == null) return;
    final session = apiSessionChanges.value;
    showSharePostSheet(context, item, onShared: (count) {
      if (count != null && mounted && session == apiSessionChanges.value) {
        setState(() {
          final i =
              _list.indexWhere((e) => (e['id'] as num?)?.toInt() == postId);
          if (i >= 0) _list[i]['shareCount'] = count;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: _loading && _list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _list.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                            child: _feed.error != null
                                ? ProfileFeedStatus(feed: _feed)
                                : Text('暂无收藏',
                                    style: AppTextStyles.bodyMedium)),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _list.length +
                          (_loadingMore ? 1 : 0) +
                          ((_hasMore || _feed.error != null) &&
                                  _list.isNotEmpty &&
                                  !_loadingMore
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          if (_loadingMore) {
                            return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)));
                          }
                          return Center(child: ProfileFeedStatus(feed: _feed));
                        }
                        final item = _list[index];
                        return PostCard(
                          item: item,
                          heroTagSuffix: 'fav_$index',
                          showActionRow: false,
                          showHeader: false,
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => PostDetailPage(
                                      postId: item['id'] as int,
                                      initialItem: item),
                                ),
                              )
                              .then((_) => _reload()),
                          onTopicTap: (id, name) => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => TopicFeedPage(
                                    topicId: id, topicName: name)),
                          ),
                          onLike: _handleLike,
                          onFavorite: _handleFavorite,
                          onShare: _handleShare,
                          currentUserId: _currentUserId,
                          onDeleted: (postId) {
                            if (!mounted) return;
                            setState(() => _list.removeWhere(
                                (e) => (e['id'] as num?)?.toInt() == postId));
                            _reload();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
