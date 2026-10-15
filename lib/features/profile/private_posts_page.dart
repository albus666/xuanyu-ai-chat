import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/post_share.dart';
import '../community/post_card.dart';
import '../community/post_detail_page.dart';

class PrivatePostsPage extends StatefulWidget {
  const PrivatePostsPage({super.key});

  @override
  State<PrivatePostsPage> createState() => _PrivatePostsPageState();
}

class _PrivatePostsPageState extends State<PrivatePostsPage> {
  final _list = <Map<String, dynamic>>[];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadFailed = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _load();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _currentUserId = prefs.getInt(AppConstants.keyUserId));
    }
  }

  Future<void> _load() async {
    if (_loadingMore || !_hasMore) return;
    if (_list.isNotEmpty) setState(() => _loadingMore = true);
    if (_list.isEmpty && mounted) setState(() => _loadFailed = false);
    try {
      final response = await apiClient.get(
        '/api/community/my-posts',
        queryParameters: {
          'page': _page,
          'page_size': 20,
          'visibility': 'private',
        },
      );
      final data = (response.data as Map?)?['data'] as Map?;
      final items = data?['list'] as List<dynamic>?;
      if (items != null && mounted) {
        setState(() {
          for (final item in items) {
            if (item is Map<String, dynamic> &&
                !_list.any((existing) => existing['id'] == item['id'])) {
              _list.add(Map<String, dynamic>.from(item));
            }
          }
          _page++;
          _hasMore = data?['hasMore'] == true;
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          // 兼容尚未升级的服务端：没有私密内容时返回 404 也按正常空态处理。
          _loadFailed = error.response?.statusCode != 404;
          _hasMore = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    setState(() {
      _list.clear();
      _page = 1;
      _hasMore = true;
      _loading = true;
      _loadingMore = false;
      _loadFailed = false;
    });
    await _load();
  }

  Future<void> _toggleLike(int postId) async {
    try {
      final response = await apiClient.post('/api/community/post/$postId/like');
      final data = (response.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final index = _list
              .indexWhere((item) => (item['id'] as num?)?.toInt() == postId);
          if (index >= 0) {
            _list[index]['liked'] = data['liked'] == true;
            _list[index]['likeCount'] = data['likeCount'];
          }
        });
      }
    } on DioException catch (_) {
      if (mounted) showAppToast(context, '操作失败，请稍后重试');
    }
  }

  Future<void> _toggleFavorite(int postId) async {
    try {
      final response =
          await apiClient.post('/api/community/post/$postId/favorite');
      final data = (response.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        setState(() {
          final index = _list
              .indexWhere((item) => (item['id'] as num?)?.toInt() == postId);
          if (index >= 0) {
            _list[index]['favorited'] = data['favorited'] == true;
          }
        });
      }
    } on DioException catch (_) {
      if (mounted) showAppToast(context, '收藏操作失败');
    }
  }

  void _share(int postId) {
    final item = _list.cast<Map<String, dynamic>?>().firstWhere(
          (post) => (post?['id'] as num?)?.toInt() == postId,
          orElse: () => null,
        );
    if (item == null) return;
    showSharePostSheet(
      context,
      item,
      onShared: (count) {
        if (count == null || !mounted) return;
        setState(() => item['shareCount'] = count);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.communityScaffold,
      appBar: AppBar(
        title: const Text('我的私密'),
        backgroundColor: AppColors.communityScaffold,
      ),
      body: DecoratedBox(
        decoration:
            const BoxDecoration(gradient: AppColors.communityBodyGradient),
        child: _loading && _list.isEmpty
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : RefreshIndicator(
                onRefresh: _reload,
                color: AppColors.communityAccent,
                child: _list.isEmpty && _loadFailed
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.55,
                            child: Center(
                              child: TextButton.icon(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('暂时无法加载，点此重试'),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.55,
                                child: Center(
                                  child: Text(
                                    '还没有私密瞬间',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : GridView.builder(
                            padding: EdgeInsets.fromLTRB(
                                12, 12, 12, 12 + bottomPadding),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: _list.length +
                                (_loadingMore || _hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _list.length) {
                                if (_loadingMore) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  );
                                }
                                return Center(
                                  child: TextButton(
                                    onPressed: _load,
                                    child: const Text('加载更多'),
                                  ),
                                );
                              }
                              final item = _list[index];
                              final postId = (item['id'] as num?)?.toInt();
                              return PostCard(
                                item: item,
                                heroTagSuffix: 'private_$index',
                                showActionRow: false,
                                openMediaAsPost: true,
                                showHeader: true,
                                currentUserId: _currentUserId,
                                onTap: postId == null
                                    ? null
                                    : () => Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) => PostDetailPage(
                                              postId: postId,
                                              initialItem: item,
                                            ),
                                          ),
                                        )
                                        .then((_) => _reload()),
                                onLike: _toggleLike,
                                onFavorite: _toggleFavorite,
                                onShare: _share,
                                onDeleted: (deletedId) => setState(
                                  () => _list.removeWhere(
                                    (post) =>
                                        (post['id'] as num?)?.toInt() ==
                                        deletedId,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
      ),
    );
  }
}
