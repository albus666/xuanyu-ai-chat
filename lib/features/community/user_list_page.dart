import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'user_profile_page.dart';
import '../message/im_workflow_request.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key, required this.title, required this.apiPath});

  final String title;
  final String apiPath;

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final _users = <Map<String, dynamic>>[];
  bool _loading = true;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    _generation++;
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _users.clear();
      _error = null;
      _loading = false;
    });
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    final request = ImWorkflowRequest();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = imResponseList(await request.get(widget.apiPath));
      if (!mounted || !request.current || generation != _generation) return;
      final unique = <int, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = ((row['userId'] ?? row['id']) as num?)?.toInt();
        if (id != null) unique[id] = row;
      }
      setState(() {
        _users
          ..clear()
          ..addAll(unique.values);
      });
    } catch (error) {
      if (mounted && request.current && generation == _generation) {
        setState(() => _error = imFailureMessage(error, '用户列表加载失败，请重试'));
      }
    } finally {
      if (mounted && request.current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.title, style: AppTextStyles.titleMedium),
      ),
      body: _loading && _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _users.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index > 0) return _buildUserTile(_users[index - 1]);
                  if (_error != null) {
                    return ImWorkflowRetry(
                        message: _error!,
                        onRetry: _loading ? null : _loadUsers);
                  }
                  return _users.isEmpty
                      ? SizedBox(height: 300, child: _buildEmptyState())
                      : const SizedBox.shrink();
                },
              )),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded,
              size: 64, color: AppColors.textHint.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无用户',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final nickname = user['nickname'] as String? ?? '用户';
    final avatarUrl = user['avatarUrl'] as String?;
    final intro = user['intro'] as String? ?? '暂无介绍';
    final userId =
        (user['userId'] as num?)?.toInt() ?? (user['id'] as num?)?.toInt();

    return InkWell(
      onTap: () {
        if (userId != null) {
          final request = ImWorkflowRequest();
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => UserProfilePage(userId: userId)))
              .then((_) {
            if (mounted && request.current) _loadUsers();
          });
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(nickname.isNotEmpty ? nickname[0] : '?',
                      style: AppTextStyles.titleSmall)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nickname, style: AppTextStyles.titleSmall),
                  const SizedBox(height: 4),
                  Text(intro,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
