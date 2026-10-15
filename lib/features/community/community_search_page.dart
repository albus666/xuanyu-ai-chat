import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'post_card.dart';
import 'community_online_indicator.dart';
import 'post_detail_page.dart';
import 'topic_feed_page.dart';
import 'user_profile_page.dart';

const _kSearchHistoryKey = 'community_search_history_v1';
const _kMaxHistory = 20;

/// 社区搜索：帖子、用户（支持昵称、8位ID、用户数字ID）
class CommunitySearchPage extends StatefulWidget {
  const CommunitySearchPage({super.key});

  @override
  State<CommunitySearchPage> createState() => _CommunitySearchPageState();
}

class _CommunitySearchPageState extends State<CommunitySearchPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _postList = <Map<String, dynamic>>[];
  final _userList = <Map<String, dynamic>>[];
  final _history = <String>[];
  bool _loadingPost = false;
  bool _loadingUser = false;
  bool _hasSearchedPost = false;
  bool _hasSearchedUser = false;
  bool _showResults = false;
  String _submittedKeyword = '';
  int _searchRevision = 0;
  int _lastTabIndex = 0;
  ApiSessionScope _scope = ApiSessionScope();
  String? _historyKey;
  late Future<void> _historyReady;
  Future<void> _historyWrites = Future<void>.value();
  String? _postError;
  String? _userError;
  int _postPage = 0;
  int _userPage = 0;
  bool _postHasMore = false;
  bool _userHasMore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_lastTabIndex == _tabController.index) return;
      _lastTabIndex = _tabController.index;
      if (!_showResults || _submittedKeyword.isEmpty) return;
      if (_tabController.index == 0 && !_hasSearchedPost) {
        _searchPosts();
      } else if (_tabController.index == 1 && !_hasSearchedUser) {
        _searchUsers();
      }
    });
    apiSessionChanges.addListener(_onSessionChanged);
    _historyReady = _loadHistory();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final scope = _scope;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || !scope.current) return;
    final userId = prefs.getInt(AppConstants.keyUserId);
    // 旧公共历史无账号归属，保留原值但不展示给新账号。
    _historyKey = userId != null && userId > 0
        ? '${_kSearchHistoryKey}_user_$userId'
        : null;
    final raw = _historyKey == null
        ? <String>[]
        : prefs.getStringList(_historyKey!) ?? <String>[];
    if (mounted && scope.current) {
      setState(
        () => _history
          ..clear()
          ..addAll(raw),
      );
    }
  }

  Future<void> _saveHistory(String keyword) async {
    final scope = _scope;
    await _historyReady;
    if (!mounted || !scope.current) return;
    final next = [
      keyword,
      ..._history.where((e) => e != keyword),
    ].take(_kMaxHistory).toList();
    if (mounted && scope.current) {
      setState(
        () => _history
          ..clear()
          ..addAll(next),
      );
    }
    await _persistHistory(next, scope);
  }

  Future<void> _clearHistory() async {
    final scope = _scope;
    await _historyReady;
    if (!mounted || !scope.current) return;
    setState(() => _history.clear());
    await _persistHistory(const [], scope);
  }

  Future<void> _persistHistory(List<String> values, ApiSessionScope scope) {
    final key = _historyKey;
    if (key == null) return Future<void>.value();
    _historyWrites = _historyWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!scope.current) return;
      if (values.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, values);
      }
    }).catchError((Object _) {});
    return _historyWrites;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _scope = ApiSessionScope();
    _searchRevision++;
    _searchController.clear();
    setState(() {
      _postList.clear();
      _userList.clear();
      _history.clear();
      _historyKey = null;
      _submittedKeyword = '';
      _showResults = false;
      _loadingPost = false;
      _loadingUser = false;
      _hasSearchedPost = false;
      _hasSearchedUser = false;
      _postError = null;
      _userError = null;
      _postPage = 0;
      _userPage = 0;
      _postHasMore = false;
      _userHasMore = false;
    });
    _historyReady = _loadHistory();
  }

  Future<void> _searchPosts({bool more = false}) =>
      _searchResults(users: false, more: more);

  Future<void> _searchUsers({bool more = false}) =>
      _searchResults(users: true, more: more);

  Future<void> _searchResults({required bool users, required bool more}) async {
    final keyword = _submittedKeyword;
    if (keyword.isEmpty || (users ? _loadingUser : _loadingPost)) return;
    if (more && !(users ? _userHasMore : _postHasMore)) return;
    final revision = _searchRevision;
    final scope = _scope;
    final page = more ? (users ? _userPage : _postPage) + 1 : 1;
    setState(() {
      if (users) {
        _loadingUser = true;
        _userError = null;
      } else {
        _loadingPost = true;
        _postError = null;
      }
    });
    try {
      final res = await scope.get(
        users ? '/api/community/user/search' : '/api/community/post/search',
        queryParameters: {'keyword': keyword, 'page': page, 'page_size': 30},
      );
      final body = res.data;
      if (body is! Map || body['code'] != 0) {
        throw FormatException(
          body is Map
              ? body['message']?.toString() ?? '搜索失败，请重试'
              : '搜索结果异常，请重试',
        );
      }
      final data = body['data'];
      if (data is! Map || data['list'] is! List) {
        throw const FormatException('搜索结果异常，请重试');
      }
      final idKey = users ? 'userId' : 'id';
      final items = <Map<String, dynamic>>[];
      for (final item in data['list'] as List) {
        if (item is! Map || item[idKey] is! num) {
          throw const FormatException('搜索结果异常，请重试');
        }
        items.add(Map<String, dynamic>.from(item));
      }
      if (!mounted || revision != _searchRevision || !scope.current) return;
      setState(() {
        final list = users ? _userList : _postList;
        if (!more) list.clear();
        final ids = list.map((item) => item[idKey]).toSet();
        list.addAll(items.where((item) => ids.add(item[idKey])));
        final hasMore = data['hasMore'] == true ||
            (data['hasMore'] == null && items.length == 30);
        if (users) {
          _hasSearchedUser = true;
          _userPage = page;
          _userHasMore = hasMore;
        } else {
          _hasSearchedPost = true;
          _postPage = page;
          _postHasMore = hasMore;
        }
      });
    } catch (error) {
      if (!mounted || revision != _searchRevision || !scope.current) return;
      final message = error is FormatException
          ? error.message
          : apiSessionFailureMessage(error, '搜索失败，请重试');
      setState(() {
        if (users) {
          _userError = message;
        } else {
          _postError = message;
        }
      });
    } finally {
      if (mounted && revision == _searchRevision && scope.current) {
        setState(() {
          if (users) {
            _loadingUser = false;
          } else {
            _loadingPost = false;
          }
        });
      }
    }
  }

  void _onSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      showAppToast(context, '请输入搜索关键词');
      return;
    }
    _focusNode.unfocus();
    _saveHistory(keyword);
    setState(() {
      _submittedKeyword = keyword;
      _searchRevision++;
      _loadingPost = false;
      _loadingUser = false;
      _postList.clear();
      _userList.clear();
      _showResults = true;
      _hasSearchedPost = false;
      _hasSearchedUser = false;
      _postError = null;
      _userError = null;
      _postPage = 0;
      _userPage = 0;
      _postHasMore = false;
      _userHasMore = false;
    });
    if (_tabController.index == 0) {
      _searchPosts();
    } else {
      _searchUsers();
    }
  }

  void _applyHistoryKeyword(String keyword) {
    _searchController.text = keyword;
    _onSearch();
  }

  Future<void> _openImageSearch() async {
    final scope = _scope;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted || !scope.current) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted || !scope.current) return;
      final keywordController = TextEditingController(
        text: _searchController.text.trim(),
      );
      final keyword = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(image.path),
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keywordController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: '补充图片关键词',
                  hintText: '例如：风景、汉服、手作',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.pop(sheetContext, value),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(sheetContext, keywordController.text),
                  child: const Text('搜索相关作品'),
                ),
              ),
            ],
          ),
        ),
      );
      keywordController.dispose();
      if (!mounted || !scope.current || keyword == null) return;
      final value = keyword.trim();
      if (value.isEmpty) {
        showAppToast(context, '请补充一个图片关键词');
        return;
      }
      _searchController.text = value;
      _onSearch();
    } catch (_) {
      if (mounted && scope.current) showAppToast(context, '暂时无法读取图片');
    }
  }

  Widget _buildSearchHeader() {
    const barHeight = 40.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearch(),
                      cursorColor: const Color(0xFFE53935),
                      textAlignVertical: TextAlignVertical.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜索帖子、昵称或ID',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textHint,
                          fontSize: 15,
                          height: 1.2,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openImageSearch,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: barHeight,
                      child: Center(
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 22,
                          color: AppColors.textSecondary.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    color: const Color(0xFFE0E0E0),
                  ),
                  GestureDetector(
                    onTap: _onSearch,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: barHeight,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            '搜索',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '历史记录',
                style: AppTextStyles.titleSmall.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_history.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 22,
                    color: AppColors.textSecondary.withValues(alpha: 0.75),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: _clearHistory,
                ),
            ],
          ),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '暂无历史记录',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _history.map((keyword) {
                return GestureDetector(
                  onTap: () => _applyHistoryKeyword(keyword),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEBEBEB)),
                    ),
                    child: Text(
                      keyword,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textHint,
        labelStyle: AppTextStyles.titleSmall.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: AppTextStyles.bodyMedium.copyWith(fontSize: 15),
        indicatorColor: AppColors.textPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: '帖子'),
          Tab(text: '用户'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchHeader(),
            if (!_showResults) _buildHistorySection(),
            if (_showResults) ...[
              _buildResultTabs(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _PostSearchResult(
                      list: _postList,
                      loading: _loadingPost,
                      hasSearched: _hasSearchedPost,
                      error: _postError,
                      hasMore: _postHasMore,
                      onRetry: () => _searchPosts(more: _postList.isNotEmpty),
                      onMore: () => _searchPosts(more: true),
                    ),
                    _UserSearchResult(
                      list: _userList,
                      loading: _loadingUser,
                      hasSearched: _hasSearchedUser,
                      error: _userError,
                      hasMore: _userHasMore,
                      onRetry: () => _searchUsers(more: _userList.isNotEmpty),
                      onMore: () => _searchUsers(more: true),
                    ),
                  ],
                ),
              ),
            ] else
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({
    required this.error,
    required this.loading,
    required this.hasMore,
    required this.onRetry,
    required this.onMore,
  });
  final String? error;
  final bool loading;
  final bool hasMore;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null) ...[
                      Text(error!, textAlign: TextAlign.center),
                      TextButton(onPressed: onRetry, child: const Text('重试搜索')),
                    ] else if (hasMore)
                      TextButton(onPressed: onMore, child: const Text('加载更多')),
                  ],
                ),
        ),
      );
}

class _PostSearchResult extends StatelessWidget {
  const _PostSearchResult({
    required this.list,
    required this.loading,
    required this.hasSearched,
    required this.error,
    required this.hasMore,
    required this.onRetry,
    required this.onMore,
  });

  final List<Map<String, dynamic>> list;
  final bool loading;
  final bool hasSearched;
  final String? error;
  final bool hasMore;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (loading && list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在搜索…',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      );
    }
    if (error != null && list.isEmpty) {
      return _SearchFooter(
        error: error,
        loading: false,
        hasMore: false,
        onRetry: onRetry,
        onMore: onMore,
      );
    }
    if (list.isEmpty) {
      return _buildEmptyState(
        hasSearched ? '未找到相关帖子' : '探索有趣的灵魂和故事',
        hasSearched ? Icons.search_off_rounded : Icons.auto_awesome_rounded,
        hasSearched ? '试试其他关键词' : '输入关键词开始搜索',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
      itemCount: list.length + 1,
      itemBuilder: (context, index) {
        if (index == list.length) {
          return _SearchFooter(
            error: error,
            loading: loading,
            hasMore: hasMore,
            onRetry: onRetry,
            onMore: onMore,
          );
        }
        final item = list[index];
        return PostCard(
          item: item,
          heroTagSuffix: 'search_$index',
          integrated: true,
          showBottomDivider: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PostDetailPage(postId: item['id'] as int, initialItem: item),
            ),
          ),
          onTopicTap: (id, name) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TopicFeedPage(topicId: id, topicName: name),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, IconData icon, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSearchResult extends StatelessWidget {
  const _UserSearchResult({
    required this.list,
    required this.loading,
    required this.hasSearched,
    required this.error,
    required this.hasMore,
    required this.onRetry,
    required this.onMore,
  });

  final List<Map<String, dynamic>> list;
  final bool loading;
  final bool hasSearched;
  final String? error;
  final bool hasMore;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (loading && list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在搜索…',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      );
    }
    if (error != null && list.isEmpty) {
      return _SearchFooter(
        error: error,
        loading: false,
        hasMore: false,
        onRetry: onRetry,
        onMore: onMore,
      );
    }
    if (list.isEmpty) {
      return _buildEmptyState(
        hasSearched ? '未找到相关用户' : '通过昵称或ID寻找故友',
        hasSearched ? Icons.person_off_rounded : Icons.person_search_rounded,
        hasSearched ? '试试其他关键词或ID' : '输入昵称或用户ID开始搜索',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: list.length + 1,
      itemBuilder: (_, i) {
        if (i == list.length) {
          return _SearchFooter(
            error: error,
            loading: loading,
            hasMore: hasMore,
            onRetry: onRetry,
            onMore: onMore,
          );
        }
        final u = list[i];
        final userId = (u['userId'] as num?)?.toInt();
        final nickname = u['nickname'] as String? ?? '用户';
        final avatarUrl = u['avatarUrl'] as String?;
        if (userId == null) return const SizedBox.shrink();
        final userCode = u['userCode'] as String?;
        final gender = u['gender'];
        final bio = u['bio'] as String?;
        final online = u['isOnline'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(userId: userId),
                ),
              ),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CommunityOnlineIndicator(
                          online: online,
                          dotSize: 12,
                          child: Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.cardBackground,
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? NetworkImage(avatarUrl)
                                      : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(
                                      nickname.isNotEmpty ? nickname[0] : '?',
                                      style: AppTextStyles.titleMedium.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        if (gender != null)
                          Positioned(
                            left: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                gender == 1
                                    ? Icons.male_rounded
                                    : Icons.female_rounded,
                                size: 14,
                                color: gender == 1 ? Colors.blue : Colors.pink,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (userCode != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ID: $userCode',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textHint,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (bio != null && bio.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              bio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, IconData icon, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
