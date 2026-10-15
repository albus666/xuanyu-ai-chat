import '../../core/utils/ai_content.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'user_profile_page.dart';

Map<String, dynamic> _sharePickerData(dynamic body) {
  if (body is! Map ||
      (body['code'] != null && body['code'] != 0) ||
      (body['data'] != null && body['data'] is! Map)) {
    throw const FormatException('分享返回异常');
  }
  final data = body['data'];
  return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

/// 分享帖子给关注的用户：选择好友后发送帖子预览卡片到私聊
class SharePostToUsersPage extends StatefulWidget {
  const SharePostToUsersPage({
    super.key,
    required this.postItem,
    this.onShared,
  })  : profileItem = null,
        roomItem = null,
        messageBuilder = null;

  const SharePostToUsersPage.profile({
    super.key,
    required this.profileItem,
  })  : postItem = null,
        roomItem = null,
        onShared = null,
        messageBuilder = null;

  const SharePostToUsersPage.room({
    super.key,
    required this.roomItem,
  })  : postItem = null,
        profileItem = null,
        onShared = null,
        messageBuilder = null;

  const SharePostToUsersPage.message({super.key, required this.messageBuilder})
      : postItem = null,
        profileItem = null,
        roomItem = null,
        onShared = null;

  final Future<Map<String, String>> Function(ApiSessionScope scope)?
      messageBuilder;

  /// 帖子完整数据，用于构造预览
  final Map<String, dynamic>? postItem;

  /// 复用好友/群聊选择器分享个人主页卡片。
  final Map<String, dynamic>? profileItem;

  /// 复用好友/群聊选择器发送可直接进入的语音房邀请卡。
  final Map<String, dynamic>? roomItem;

  /// 分享成功回调，参数为新的 shareCount
  final void Function(int? newShareCount)? onShared;

  @override
  State<SharePostToUsersPage> createState() => _SharePostToUsersPageState();
}

class _SharePostToUsersPageState extends State<SharePostToUsersPage> {
  final _scope = ApiSessionScope();
  final _following = <Map<String, dynamic>>[];
  final _groups = <Map<String, dynamic>>[];
  final _selectedIds = <int>{};
  final _selectedConversationIds = <int>{};
  bool _loading = true;
  bool _sharing = false;
  bool _showGroups = false;
  bool _sessionInvalid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _loadFollowing();
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() {
      _following.clear();
      _groups.clear();
      _selectedIds.clear();
      _selectedConversationIds.clear();
      _loading = false;
      _sharing = false;
      _sessionInvalid = true;
      _error = apiSessionChangedMessage;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    if (_sessionInvalid || !_scope.current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _scope.get('/api/community/user/me/following-list'),
        _scope.get('/api/im/conversations'),
      ]);
      final data = _sharePickerData(results[0].data);
      final list = data['list'];
      final conversationData = _sharePickerData(results[1].data);
      final conversations = conversationData['list'];
      if (list is! List || conversations is! List) {
        throw const FormatException('分享对象列表返回异常');
      }
      if (mounted && _scope.current) {
        setState(() {
          _following.clear();
          _groups.clear();
          for (final e in list) {
            if (e is Map) {
              _following.add(Map<String, dynamic>.from(e));
            }
          }
          for (final e in conversations) {
            if (e is Map && e['type'] != 'single') {
              _groups.add(Map<String, dynamic>.from(e));
            }
          }
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && _scope.current) {
        setState(() {
          _loading = false;
          _error = apiSessionFailureMessage(error, '分享对象加载失败，请重试');
        });
      }
    }
  }

  String _buildPostContentJson() {
    final item = widget.postItem!;
    final raw = AiContent.markedText(
        item['content']?.toString() ?? '', AiContent.label(item));
    final payload = {
      'aiLabel': AiContent.label(item),
      'aiGenerated': item['aiGenerated'] == true,
      'AIGC': item['AIGC'],
      'postId': (item['id'] as num?)?.toInt(),
      'nickname': item['nickname'] ?? '用户',
      'content': raw.length > 100 ? '${raw.substring(0, 100)}...' : raw,
      'mediaUrls': item['mediaUrls'] ?? [],
      'mediaCoverUrls': item['mediaCoverUrls'] ?? [],
      'mediaType': item['mediaType'] ?? 'image',
      'likeCount': (item['likeCount'] as num?)?.toInt() ?? 0,
      'createdAt': item['createdAt'] ?? '',
    };
    return jsonEncode(payload);
  }

  String _buildProfileContentJson() {
    final item = widget.profileItem!;
    final rawUserId = item['userId'] ?? item['id'];
    final userId = rawUserId is num
        ? rawUserId.toInt()
        : int.tryParse(rawUserId?.toString() ?? '');
    return jsonEncode({
      'userId': userId,
      'nickname': item['nickname'] ?? '玄遇用户',
      'avatarUrl': item['avatarUrl'] ?? '',
      'intro': item['intro'] ?? '',
      'teamTitle': item['teamTitle'] ?? '',
      'followerCount': (item['followerCount'] as num?)?.toInt() ?? 0,
    });
  }

  String _buildRoomContentJson() {
    final item = widget.roomItem!;
    return jsonEncode({
      'roomId': (item['id'] as num?)?.toInt(),
      'roomNo': item['roomNo'] ?? '',
      'title': item['title'] ?? '语音房',
      'roomType': item['roomType'] ?? 'free',
      'category': item['category'] ?? '交流',
      'onlineCount': (item['onlineCount'] as num?)?.toInt() ?? 0,
      'ownerNickname': item['ownerNickname'] ?? '房主',
    });
  }

  Future<void> _share() async {
    if (_sessionInvalid || !_scope.current || _sharing) {
      if (mounted && _sessionInvalid) {
        showAppToast(context, apiSessionChangedMessage);
      }
      return;
    }
    if (_selectedIds.isEmpty && _selectedConversationIds.isEmpty) {
      showAppToast(context, '请选择好友或群聊');
      return;
    }
    setState(() => _sharing = true);
    final isProfile = widget.profileItem != null;
    final isRoom = widget.roomItem != null;
    final postId = (widget.postItem?['id'] as num?)?.toInt();
    var contentJson = widget.messageBuilder != null
        ? ''
        : isRoom
            ? _buildRoomContentJson()
            : isProfile
                ? _buildProfileContentJson()
                : _buildPostContentJson();
    var messageType = isRoom
        ? 'voice_room'
        : isProfile
            ? 'profile'
            : 'post';
    final selectedUsers = _selectedIds.toList();
    final selectedConversations = _selectedConversationIds.toList();
    int successCount = 0;
    final sentUsers = <int>{};
    final sentConversations = <int>{};
    try {
      if (widget.messageBuilder != null) {
        final message = await widget.messageBuilder!(_scope);
        _scope.ensureCurrent();
        contentJson = message['content']!;
        messageType = message['type']!;
      }
      for (final userId in selectedUsers) {
        try {
          final convRes = await _scope.post(
            '/api/im/conversation/single',
            data: {'targetUserId': userId},
          );
          final convData = _sharePickerData(convRes.data);
          final convId = (convData['conversationId'] as num?)?.toInt();
          if (convId == null) continue;
          final sent = await _scope.post(
            '/api/im/conversation/$convId/message',
            data: {'type': messageType, 'content': contentJson},
          );
          _sharePickerData(sent.data);
          successCount++;
          sentUsers.add(userId);
        } catch (_) {
          if (!_scope.current) rethrow;
        }
      }
      for (final conversationId in selectedConversations) {
        try {
          final sent = await _scope.post(
            '/api/im/conversation/$conversationId/message',
            data: {'type': messageType, 'content': contentJson},
          );
          _sharePickerData(sent.data);
          successCount++;
          sentConversations.add(conversationId);
        } catch (_) {
          if (!_scope.current) rethrow;
        }
      }
      int? newShareCount;
      if (postId != null) {
        try {
          final shareRes =
              await _scope.post('/api/community/post/$postId/share');
          final shareData = _sharePickerData(shareRes.data);
          newShareCount = (shareData['shareCount'] as num?)?.toInt();
        } catch (_) {
          if (!_scope.current) rethrow;
          // 分享消息已经成功，计数失败不重复发送消息。
        }
      }
      if (mounted && _scope.current) {
        widget.onShared?.call(newShareCount);
        showAppToast(
          context,
          successCount > 0
              ? isRoom
                  ? '已邀请 $successCount 个好友或群聊'
                  : '已分享至 $successCount 个会话'
              : isRoom
                  ? '邀请失败'
                  : '分享失败',
        );
        final total = selectedUsers.length + selectedConversations.length;
        if (successCount == total) {
          Navigator.of(context).pop(true);
        } else if (successCount > 0) {
          setState(() {
            _selectedIds.removeAll(sentUsers);
            _selectedConversationIds.removeAll(sentConversations);
          });
          showAppToast(context, '部分发送失败，可重试剩余对象');
        }
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '分享失败，请稍后重试'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(widget.roomItem != null ? '邀请好友' : '分享给好友',
                    style: AppTextStyles.titleMedium),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _targetTab('好友', !_showGroups),
                  _targetTab('群聊', _showGroups),
                ],
              ),
            ),
          ),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(32), child: CircularProgressIndicator())
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (!_sessionInvalid) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('share-target-retry'),
                      onPressed: _loadFollowing,
                      child: const Text('重新加载'),
                    ),
                  ],
                ],
              ),
            )
          else if ((_showGroups ? _groups : _following).isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _showGroups ? '暂无已加入的群聊' : '暂无关注的人，先关注喜欢的用户吧',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textHint),
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _showGroups ? _groups.length : _following.length,
                itemBuilder: (context, index) {
                  if (_showGroups) {
                    final group = _groups[index];
                    final conversationId =
                        (group['conversationId'] as num?)?.toInt();
                    if (conversationId == null) return const SizedBox.shrink();
                    final title = group['title']?.toString().trim();
                    final selected =
                        _selectedConversationIds.contains(conversationId);
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(Icons.groups_rounded,
                              color: AppColors.primary),
                        ),
                        title: Text(title?.isNotEmpty == true ? title! : '群聊'),
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) => _toggleConversation(conversationId),
                        ),
                        onTap: () => _toggleConversation(conversationId),
                      ),
                    );
                  }
                  final u = _following[index];
                  final userId = (u['userId'] as num?)?.toInt();
                  final nickname = u['nickname'] as String? ?? '用户';
                  final avatarUrl = u['avatarUrl'] as String?;
                  if (userId == null) return const SizedBox.shrink();
                  final selected = _selectedIds.contains(userId);
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(userId: userId),
                          ),
                        ),
                        child: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          backgroundImage:
                              avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? Text(nickname.isNotEmpty ? nickname[0] : '?')
                              : null,
                        ),
                      ),
                      title: Text(nickname),
                      trailing: Checkbox(
                        value: selected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(userId);
                            } else {
                              _selectedIds.remove(userId);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selectedIds.remove(userId);
                          } else {
                            _selectedIds.add(userId);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_sharing ||
                          _sessionInvalid ||
                          (_selectedIds.isEmpty &&
                              _selectedConversationIds.isEmpty))
                      ? null
                      : _share,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _sharing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          '${widget.roomItem != null ? '邀请' : '分享'}(${_selectedIds.length + _selectedConversationIds.length})'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetTab(String label, bool selected) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _showGroups = label == '群聊'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(label,
              style: AppTextStyles.bodyMedium.copyWith(
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ),
    );
  }

  void _toggleConversation(int conversationId) {
    setState(() {
      if (!_selectedConversationIds.remove(conversationId)) {
        _selectedConversationIds.add(conversationId);
      }
    });
  }
}
