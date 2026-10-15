import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'user_profile_page.dart';

/// 用户搜索：按昵称搜索，进入用户主页
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _controller = TextEditingController();
  final _list = <Map<String, dynamic>>[];
  final _scope = ApiSessionScope();
  bool _loading = false;
  bool _hasSearched = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _keyword = '';
  String? _error;
  int _generation = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    _generation++;
    setState(() {
      _list.clear();
      _loading = _loadingMore = _hasMore = false;
      _error = apiSessionChangedMessage;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (!_scope.current || (_loading && keyword == _keyword)) return;
    final generation = ++_generation;
    setState(() {
      _list.clear();
      _keyword = keyword;
      _page = 0;
      _error = null;
      _hasMore = _loadingMore = false;
      _loading = keyword.isNotEmpty;
      _hasSearched = false;
    });
    if (keyword.isEmpty) return;
    await _requestPage(1, generation);
  }

  Future<void> _loadMore() async {
    if (!_scope.current || _loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    await _requestPage(_page + 1, _generation);
  }

  Future<void> _requestPage(int page, int generation) async {
    bool current() => mounted && _scope.current && generation == _generation;
    try {
      final res = await _scope.get('/api/community/user/search',
          queryParameters: {
            'keyword': _keyword,
            'page': page,
            'page_size': 30
          });
      if (!current()) return;
      final body = res.data;
      if (body is! Map) throw const FormatException();
      if (body['code'] != 0) {
        throw _UserSearchFailure(body['message']?.toString() ?? '搜索失败，请重试');
      }
      final data = body['data'];
      if (data is! Map || data['list'] is! List || data['hasMore'] is! bool) {
        throw const FormatException();
      }
      final items = <Map<String, dynamic>>[];
      for (final item in data['list'] as List) {
        if (item is! Map ||
            item['userId'] is! num ||
            (item['userId'] as num) <= 0) {
          throw const FormatException();
        }
        items.add(Map<String, dynamic>.from(item));
      }
      setState(() {
        final seen = _list.map((u) => u['userId']).toSet();
        _list.addAll(items.where((u) => seen.add(u['userId'])));
        _page = page;
        _hasMore = data['hasMore'] == true && items.isNotEmpty;
        _hasSearched = true;
      });
    } catch (error) {
      if (!current()) return;
      setState(() => _error = error is _UserSearchFailure
          ? error.message
          : apiSessionFailureMessage(error, '搜索失败，请重试'));
    } finally {
      if (current()) setState(() => _loading = _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            enabled: _scope.current,
            onChanged: (value) {
              if (value.trim().isEmpty) _search();
            },
            decoration: InputDecoration(
              hintText: '搜索昵称或ID',
              hintStyle: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textHint, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textHint, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 8),
            ),
            style: AppTextStyles.bodyMedium,
          ),
        ),
        titleSpacing: 0,
        actions: [
          TextButton(
            onPressed: _scope.current ? _search : null,
            child: const Text('搜索',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _list.isEmpty
              ? _buildEmptyState()
              : _buildUserList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _hasSearched
                ? Icons.person_off_rounded
                : Icons.person_search_rounded,
            size: 64,
            color: AppColors.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? (_hasSearched ? '未找到相关用户' : '输入昵称或ID寻找好友'),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          ),
          if (_error != null && _scope.current)
            TextButton(onPressed: _search, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _list.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _list.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _loadingMore
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    if (_error != null) Text(_error!),
                    TextButton(
                        onPressed: _loadMore,
                        child: Text(_error == null ? '加载更多' : '重试')),
                  ]),
          );
        }
        final u = _list[i];
        final userId = (u['userId'] as num?)?.toInt();
        final nickname = u['nickname']?.toString() ?? '用户';
        final avatarUrl = u['avatarUrl']?.toString();
        if (userId == null) return const SizedBox.shrink();
        final userCode = u['userCode']?.toString();
        final gender = u['gender']; // 1男 2女
        final bio = u['bio']?.toString();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.cardBackground,
                      backgroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl)
                              : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? Text(nickname.isNotEmpty ? nickname[0] : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary))
                          : null,
                    ),
                  ),
                  if (gender != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: Icon(
                          gender == 1
                              ? Icons.male_rounded
                              : Icons.female_rounded,
                          size: 14,
                          color: gender == 1 ? Colors.blue : Colors.pinkAccent,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(nickname,
                  style: AppTextStyles.titleSmall.copyWith(fontSize: 15)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (userCode != null)
                    Text('ID: $userCode',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textHint, fontSize: 11)),
                  if (bio != null && bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.divider, size: 14),
              onTap: () => _scope.current
                  ? Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => UserProfilePage(userId: userId)),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _UserSearchFailure implements Exception {
  const _UserSearchFailure(this.message);
  final String message;
}
