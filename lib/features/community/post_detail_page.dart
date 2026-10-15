import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/community_feedback.dart';
import '../../core/utils/post_share.dart';
import '../../core/utils/report_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/reference_action_icons.dart';
import 'post_card.dart';
import 'post_media_cache.dart';
import 'community_online_indicator.dart';
import 'post_entity_text.dart';
import 'post_publish_settings_page.dart';
import 'user_profile_page.dart';
import 'team_title_chip.dart';
import '../message/chat_page.dart';
import '../message/im_workflow_request.dart';

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.postId, this.initialItem});

  final int postId;
  final Map<String, dynamic>? initialItem;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _scope = ImWorkflowRequest();
  int _postLoadRevision = 0;
  String? _postLoadError;
  bool _accessRevoked = false;
  bool _acceptingAnswer = false;
  final _commentActions = <int>{};
  Map<String, dynamic>? _post;
  bool _loading = true;
  final _comments = <Map<String, dynamic>>[];
  int _commentPage = 1;
  bool _loadingMoreComments = false;
  bool _hasMoreComments = true;
  int _commentLoadRevision = 0;
  String? _commentLoadError;
  bool _failedCommentsReset = false;
  final _commentController = TextEditingController();
  final _focusNode = FocusNode();
  final _sendButtonKey = GlobalKey();
  int? _replyToCommentId;
  String? _replyToNickname;
  bool _sendingComment = false;
  int? _currentUserId;
  bool _commentSortHot = true;
  final Map<int, String> _selectedMentions = <int, String>{};
  final Set<int> _expandedReplyCommentIds = {};

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _focusNode.addListener(_onComposerFocusChanged);
    _commentController.addListener(_onComposerFocusChanged);
    if (widget.initialItem != null) {
      _post = Map<String, dynamic>.from(widget.initialItem!);
      _loading = false;
    }
    _loadCurrentUserId();
    _loadPost();
    _loadComments();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (_active) {
      setState(() => _currentUserId = prefs.getInt(AppConstants.keyUserId));
    }
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _focusNode.removeListener(_onComposerFocusChanged);
    _commentController.removeListener(_onComposerFocusChanged);
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _active => mounted && _scope.current;
  bool get _available => _active && !_accessRevoked && _post != null;

  void _invalidatePost(String message) {
    _postLoadRevision++;
    _commentLoadRevision++;
    _post = null;
    _comments.clear();
    _expandedReplyCommentIds.clear();
    _selectedMentions.clear();
    _replyToCommentId = null;
    _replyToNickname = null;
    _accessRevoked = true;
    _postLoadError = message;
    _loading = false;
    _loadingMoreComments = false;
    _sendingComment = false;
    _commentController.clear();
    _focusNode.unfocus();
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() {
      _currentUserId = null;
      _invalidatePost(imSessionChangedMessage);
    });
  }

  Future<void> _commentFailure(Object error, String fallback) async {
    if (!_active) return;
    final message = imFailureMessage(error, fallback);
    showAppToast(context, message);
    if ({401, 403, 404}.contains(imFailureStatus(error))) {
      // 动作被拒绝不等于整帖不可见（例如关闭评论、回复对象被删）。
      // 保留草稿，再由详情读取确认权限；只在读取明确拒绝时清缓存。
      await _loadPost();
    }
  }

  Future<void> _reloadDetail() async {
    await _loadPost();
    if (_available) await _refreshComments();
  }

  void _onComposerFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _insertCommentText(String text, {bool requestKeyboard = true}) {
    final value = _commentController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    _commentController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    if (requestKeyboard) _focusNode.requestFocus();
  }

  void _dismissCommentComposer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
  }

  void _onCommentTapOutside(PointerDownEvent event) {
    final box = _sendButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      if ((origin & box.size).inflate(12).contains(event.position)) {
        return;
      }
    }
    _dismissCommentComposer();
  }

  // 保留旧草稿中的提及解析兼容代码；界面已不再暴露 @ 入口。
  // ignore: unused_element
  Future<void> _showMentionPicker() async {
    final candidates = <int, Map<String, dynamic>>{};
    void addCandidate(Map<String, dynamic> raw) {
      final userId = (raw['userId'] as num?)?.toInt();
      if (userId == null || userId == _currentUserId) return;
      final nickname = raw['nickname']?.toString().trim() ?? '';
      if (nickname.isEmpty) return;
      candidates[userId] = <String, dynamic>{
        'userId': userId,
        'nickname': nickname,
        'avatarUrl': (raw['avatarUrl'] ?? raw['avatar'] ?? '').toString(),
        'userCode': raw['userCode']?.toString() ?? '',
      };
    }

    for (final comment in _comments) {
      addCandidate(Map<String, dynamic>.from(comment));
    }
    try {
      final response = await apiClient.get(
        '/api/community/mention-suggestions',
      );
      final data = (response.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>? ?? const <dynamic>[];
      for (final raw in list) {
        if (raw is Map) addCandidate(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    try {
      final response = await apiClient.get(
        '/api/community/user/me/following-list',
      );
      final data = (response.data as Map?)?['data'] as Map?;
      final list = data?['list'] as List<dynamic>? ?? const <dynamic>[];
      for (final raw in list) {
        if (raw is Map) addCandidate(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    if (!mounted) return;

    String query = '';
    bool searching = false;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final normalizedQuery = query.trim().toLowerCase();
          final visible = candidates.values.where((item) {
            if (normalizedQuery.isEmpty) return true;
            final nickname = item['nickname']?.toString().toLowerCase() ?? '';
            final userCode = item['userCode']?.toString().toLowerCase() ?? '';
            return nickname.contains(normalizedQuery) ||
                userCode.contains(normalizedQuery);
          }).toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Row(
                      children: [
                        Text(
                          '提到谁',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '对方会收到提醒',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) {
                        query = value;
                        setSheetState(() {});
                      },
                      onSubmitted: (value) async {
                        final keyword = value.trim();
                        if (keyword.isEmpty || searching) return;
                        setSheetState(() => searching = true);
                        try {
                          final response = await apiClient.get(
                            '/api/community/user/search',
                            queryParameters: {
                              'keyword': keyword,
                              'page_size': 30,
                            },
                          );
                          final data = (response.data as Map?)?['data'] as Map?;
                          final list = data?['list'] as List<dynamic>? ??
                              const <dynamic>[];
                          for (final raw in list) {
                            if (raw is Map) {
                              addCandidate(Map<String, dynamic>.from(raw));
                            }
                          }
                          setSheetState(() {});
                        } catch (_) {
                          if (sheetContext.mounted) {
                            showAppToast(sheetContext, '搜索用户失败，请稍后重试');
                          }
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => searching = false);
                          }
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '搜索昵称或玄遇号',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF6F6F7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: visible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              '输入昵称或玄遇号后按回车搜索',
                              style: TextStyle(color: AppColors.textHint),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              final nickname =
                                  item['nickname']?.toString() ?? '用户';
                              final avatarUrl =
                                  item['avatarUrl']?.toString() ?? '';
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primaryLight,
                                  backgroundImage: avatarUrl.isEmpty
                                      ? null
                                      : NetworkImage(avatarUrl),
                                  child: avatarUrl.isEmpty
                                      ? Text(nickname.characters.first)
                                      : null,
                                ),
                                title: Text(
                                  nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle:
                                    (item['userCode']?.toString() ?? '').isEmpty
                                        ? null
                                        : Text('玄遇号：${item['userCode']}'),
                                trailing: const Icon(
                                  Icons.alternate_email_rounded,
                                  color: AppColors.primary,
                                ),
                                onTap: () => Navigator.pop(sheetContext, item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    final userId = (selected['userId'] as num?)?.toInt();
    final nickname = selected['nickname']?.toString().trim() ?? '';
    if (userId == null || nickname.isEmpty) return;
    _selectedMentions[userId] = nickname;
    _insertCommentText('@$nickname ');
  }

  Future<void> _loadPost() async {
    if (!_active) return;
    final revision = ++_postLoadRevision;
    setState(() {
      _postLoadError = null;
      if (_post == null) _loading = true;
    });
    try {
      final data = await _scope.get('/api/community/post/${widget.postId}');
      if (data['id'] != widget.postId) {
        throw const ImWorkflowFailure('内容返回异常，请重试');
      }
      if (!_active || revision != _postLoadRevision) return;
      setState(() {
        _post = reuseLoadedPostMedia(_post, data);
        _accessRevoked = false;
      });
    } catch (error) {
      if (!_active || revision != _postLoadRevision) return;
      final message = imFailureMessage(error, '内容加载失败，请重试');
      setState(() {
        if ({401, 403, 404}.contains(imFailureStatus(error))) {
          _invalidatePost(message);
        } else {
          _postLoadError = message;
        }
      });
    } finally {
      if (_active && revision == _postLoadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadComments({bool reset = false}) async {
    if (!_active ||
        _accessRevoked ||
        (!reset && (_loadingMoreComments || !_hasMoreComments))) {
      return;
    }
    final revision = ++_commentLoadRevision;
    final session = apiSessionChanges.value;
    final page = reset ? 1 : _commentPage;
    bool isCurrent() =>
        _active &&
        !_accessRevoked &&
        revision == _commentLoadRevision &&
        session == apiSessionChanges.value;
    setState(() {
      _loadingMoreComments = true;
      _commentLoadError = null;
      _failedCommentsReset = reset;
    });
    try {
      final data = await _scope.get(
        '/api/community/post/${widget.postId}/comments',
        query: {'page': page, 'page_size': 20},
      );
      final list = imResponseList(data);
      if (isCurrent()) {
        setState(() {
          if (reset) _comments.clear();
          final ids = _comments.map((item) => item['id']).toSet();
          for (final e in list) {
            if (ids.add(e['id'])) _comments.add(e);
          }
          _commentPage = page + 1;
          _hasMoreComments = (data['hasMore'] == true);
        });
      }
    } catch (error) {
      if (isCurrent()) {
        setState(() {
          if ({401, 403, 404}.contains(imFailureStatus(error))) {
            _invalidatePost(imFailureMessage(error, '评论已不可访问'));
          } else {
            _commentLoadError = imFailureMessage(error, '评论加载失败');
          }
        });
      }
    } finally {
      if (isCurrent()) setState(() => _loadingMoreComments = false);
    }
  }

  Future<void> _deletePost() async {
    if (!_available) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条瞬间？'),
        content: const Text('删除后无法恢复，相关评论也将不再展示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_available) return;
    final postId = widget.postId;
    try {
      await _scope.post('/api/community/post/$postId/delete');
      if (!mounted || !_available) return;
      showAppToast(context, '已删除');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '删除失败，请重试');
    }
  }

  Future<void> _toggleFollow() async {
    if (!_available) return;
    final post = _post;
    final authorId = (post?['userId'] as num?)?.toInt();
    if (post == null || authorId == null || _isOwner) return;
    final wasFollowing = post['following'] == true;
    if (wasFollowing) {
      final confirmed = await confirmUnfollow(
        context,
        nickname: post['nickname']?.toString() ?? 'TA',
      );
      if (!confirmed || !mounted || !_available) return;
    }
    setState(() => post['following'] = !wasFollowing);
    try {
      final data = await _scope.post('/api/community/user/$authorId/follow');
      if (_available) {
        setState(() => post['following'] = data['following'] == true);
      }
    } catch (_) {
      if (!mounted || !_available) return;
      setState(() => post['following'] = wasFollowing);
      showAppToast(context, '关注失败，请稍后重试');
    }
  }

  Future<void> _openPrivateChat() async {
    if (!_available) return;
    final post = _post;
    final authorId = (post?['userId'] as num?)?.toInt();
    if (post == null || authorId == null || _isOwner) return;
    try {
      final data = await _scope.post(
        '/api/im/conversation/single',
        data: {'targetUserId': authorId},
      );
      final conversationId = (data['conversationId'] as num?)?.toInt();
      if (conversationId == null || !mounted || !_available) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            title:
                data['title'] as String? ?? post['nickname'] as String? ?? '用户',
            conversationType: 'single',
            peerUserId: authorId,
          ),
        ),
      );
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '暂时无法发起私聊');
    }
  }

  void _showDetailMoreMenu() {
    if (!_available) return;
    final post = _post;
    if (post == null) return;
    final postId = (post['id'] as num?)?.toInt();
    if (postId == null) return;
    final isOwner = _isOwner;
    final authorId = (post['userId'] as num?)?.toInt();
    Future<void> changeVisibility() async {
      if (!_available) return;
      final value = await editPublishedPostVisibility(context, postId);
      if (value != null && _available) {
        setState(() {
          post['visibility'] = value.visibility;
          post['excludedUserIds'] = value.excludedUserIds.toList();
        });
      }
    }

    showPostMoreActionSheet(
      context,
      post,
      following: post['following'] == true,
      onShared: (count) {
        if (count != null && _available) {
          setState(() => post['shareCount'] = count);
        }
      },
      onPrivateChat: !isOwner && authorId != null ? _openPrivateChat : null,
      onToggleFollow: !isOwner && authorId != null ? _toggleFollow : null,
      onNotInterested: !isOwner ? _markNotInterested : null,
      onReport: !isOwner
          ? () {
              if (!_available) return;
              showReportSheet(
                context,
                targetType: 'post',
                targetId: postId,
                title: '举报帖子',
              );
            }
          : null,
      onChangeVisibility: isOwner ? changeVisibility : null,
      onDelete: isOwner ? _deletePost : null,
    );
  }

  Future<void> _markNotInterested() async {
    if (!_available) return;
    final reason = await showNotInterestedReasonSheet(context);
    if (reason == null || !mounted || !_available) return;
    try {
      await _scope.post(
        '/api/community/post/${widget.postId}/not-interested',
        data: {'reasonCode': reason.code},
      );
      if (!mounted || !_available) return;
      showAppToast(context, '已减少类似内容 · ${reason.label}');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '操作失败，请稍后重试');
    }
  }

  Future<void> _toggleLike() async {
    if (!_available) return;
    final liked = _post!['liked'] == true;
    setState(() {
      _post!['liked'] = !liked;
      _post!['likeCount'] =
          ((_post!['likeCount'] as num?)?.toInt() ?? 0) + (liked ? -1 : 1);
    });
    try {
      final data = await _scope.post(
        '/api/community/post/${widget.postId}/like',
      );
      if (_available) {
        setState(() {
          _post!['liked'] = data['liked'] == true;
          _post!['likeCount'] =
              (data['likeCount'] as num?)?.toInt() ?? _post!['likeCount'];
        });
      }
    } catch (_) {
      if (_available) {
        setState(() {
          _post!['liked'] = liked;
          _post!['likeCount'] =
              ((_post!['likeCount'] as num?)?.toInt() ?? 0) + (liked ? 1 : -1);
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_available) return;
    final post = _post;
    if (post == null) return;
    final wasFavorited = post['favorited'] == true;
    final oldCount = (post['favoriteCount'] as num?)?.toInt() ?? 0;
    setState(() {
      post['favorited'] = !wasFavorited;
      post['favoriteCount'] = (oldCount + (wasFavorited ? -1 : 1)).clamp(
        0,
        999999,
      );
    });
    try {
      final data = await _scope.post(
        '/api/community/post/${widget.postId}/favorite',
      );
      if (_available) {
        setState(() {
          post['favorited'] = data['favorited'] == true;
          post['favoriteCount'] =
              (data['favoriteCount'] as num?)?.toInt() ?? post['favoriteCount'];
        });
      }
    } catch (_) {
      if (!mounted || !_available) return;
      setState(() {
        post['favorited'] = wasFavorited;
        post['favoriteCount'] = oldCount;
      });
      showAppToast(context, '收藏失败，请稍后重试');
    }
  }

  Future<void> _sendComment() async {
    if (!_available) return;
    final draft = _commentController.text;
    final content = draft.trim();
    if (content.isEmpty || _sendingComment) return;
    final session = apiSessionChanges.value;
    final replyId = _replyToCommentId;
    final replyNickname = _replyToNickname;
    final replyName = _replyToNickname?.trim();
    final submittedContent =
        _replyToCommentId != null && replyName != null && replyName.isNotEmpty
            ? '回复 @$replyName：$content'
            : content;
    final mentionedUserIds = _selectedMentions.entries
        .where((entry) => submittedContent.contains('@${entry.value}'))
        .map((entry) => entry.key)
        .take(10)
        .toList(growable: false);
    setState(() => _sendingComment = true);
    try {
      await _scope.post(
        '/api/community/post/${widget.postId}/comment',
        data: {
          'content': submittedContent,
          if (_replyToCommentId != null) 'parentId': _replyToCommentId,
          if (mentionedUserIds.isNotEmpty) 'mentionedUserIds': mentionedUserIds,
        },
      );
      if (!_available || session != apiSessionChanges.value) return;
      _postLoadRevision++;
      _loading = false;
      final unchanged = _commentController.text == draft &&
          _replyToCommentId == replyId &&
          _replyToNickname == replyNickname;
      if (unchanged) {
        _commentController.clear();
        _selectedMentions.clear();
        _focusNode.unfocus();
      }
      setState(() {
        if (unchanged) {
          _replyToCommentId = null;
          _replyToNickname = null;
        }
        if (_post != null) {
          _post!['commentCount'] =
              ((_post!['commentCount'] as num?)?.toInt() ?? 0) + 1;
        }
      });
      _refreshComments();
    } catch (error) {
      await _commentFailure(error, '评论发送失败');
    } finally {
      if (_active) setState(() => _sendingComment = false);
    }
  }

  Future<void> _acceptTeamAnswer(Map<String, dynamic> comment) async {
    final commentId = (comment['id'] as num?)?.toInt();
    if (!_available ||
        !_isOwner ||
        commentId == null ||
        _acceptingAnswer ||
        !_commentActions.add(commentId)) {
      return;
    }
    _acceptingAnswer = true;
    try {
      await _scope.post(
        '/api/community/post/${widget.postId}/comment/$commentId/accept',
      );
      if (!mounted || !_available) return;
      _commentLoadRevision++;
      _loadingMoreComments = false;
      _postLoadRevision++;
      setState(() {
        final help = _post?['helpRequest'];
        if (help is Map) {
          _post!['helpRequest'] = {
            ...help,
            'status': 'resolved',
            'acceptedCommentId': commentId,
          };
        }
        for (final item in _comments) {
          item['isAcceptedAnswer'] = (item['id'] as num?)?.toInt() == commentId;
        }
      });
      showAppToast(context, '已采纳，问题标记为已解决');
    } catch (error) {
      await _commentFailure(error, '采纳失败');
    } finally {
      _acceptingAnswer = false;
      _commentActions.remove(commentId);
    }
  }

  void _startReply(int? commentId, {String? nickname}) {
    if (!_available || commentId == null) return;
    setState(() {
      _replyToCommentId = commentId;
      _replyToNickname = nickname;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToNickname = null;
    });
    _focusNode.unfocus();
  }

  Future<void> _refreshComments() async {
    await _loadComments(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _post == null) {
      return const Scaffold(
        backgroundColor: AppColors.communityScaffold,
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.communityBodyGradient),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }
    if (_post == null) {
      return Scaffold(
        backgroundColor: AppColors.communityScaffold,
        appBar: AppBar(title: const Text('作品详情')),
        body: DecoratedBox(
          decoration:
              const BoxDecoration(gradient: AppColors.communityBodyGradient),
          child: Center(
              child: ImWorkflowRetry(
            message: _postLoadError ?? '内容不存在',
            onRetry: _scope.current ? _reloadDetail : null,
          )),
        ),
      );
    }

    final topComments = _comments.where((c) => c['parentId'] == null).toList();
    topComments.sort(_compareComments);
    final replyMap = <int, List<Map<String, dynamic>>>{};
    for (final c in _comments) {
      final pid = c['parentId'] as int?;
      if (pid != null) replyMap.putIfAbsent(pid, () => []).add(c);
    }
    for (final list in replyMap.values) {
      list.sort(_compareComments);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 62,
        titleSpacing: 0,
        title: _buildAuthorTitle(),
        actions: [
          if (!_isOwner) _buildTopFollowButton(),
          IconButton(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, size: 26),
            onPressed: _showDetailMoreMenu,
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _dismissCommentComposer(),
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (_) {
                    _dismissCommentComposer();
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _reloadDetail,
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.zero,
                      children: [
                        if (_postLoadError != null)
                          ImWorkflowRetry(
                              message: _postLoadError!, onRetry: _reloadDetail),
                        // 帖子主体
                        PostCard(
                          key: ValueKey('post-detail-${widget.postId}'),
                          item: _post!,
                          showActionRow: false,
                          showMoreMenu: false,
                          showHeader: false,
                          integrated: true,
                          detailLayout: true,
                          onTap: () {},
                        ),
                        _buildPostMetaRow(),
                        const Divider(
                          height: 1,
                          color: AppColors.communityDivider,
                        ),

                        // 评论区头部
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
                          child: Row(
                            children: [
                              Text(
                                '共 ${_post!['commentCount'] ?? 0} 条评论',
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: const Color(0xFF242529),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildCommentSortButton(),
                            ],
                          ),
                        ),

                        if (_commentLoadError != null)
                          Center(
                              child: Column(children: [
                            Text(_commentLoadError!),
                            TextButton(
                              onPressed: () => _loadComments(
                                  reset: _failedCommentsReset ||
                                      _comments.isEmpty),
                              child: const Text('重试加载评论'),
                            ),
                          ])),
                        if (topComments.isEmpty && _loadingMoreComments)
                          const Center(
                              child: CircularProgressIndicator(strokeWidth: 2))
                        else if (topComments.isEmpty &&
                            _commentLoadError == null)
                          _buildEmptyComments()
                        else
                          ...topComments.map(
                            (c) => _buildCommentItem(
                              c,
                              replyMap[c['id'] as int] ?? [],
                            ),
                          ),

                        if (_hasMoreComments &&
                            _comments.isNotEmpty &&
                            _commentLoadError == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: _loadingMoreComments
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    )
                                  : TextButton(
                                      onPressed: _loadComments,
                                      child: const Text('加载更多评论'),
                                    ),
                            ),
                          ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  bool get _isOwner =>
      _post?['isOwner'] == true ||
      (_currentUserId != null &&
          (_post?['userId'] as num?)?.toInt() == _currentUserId);

  Widget _buildAuthorTitle() {
    final post = _post!;
    final nickname = post['nickname']?.toString().trim();
    final name = nickname == null || nickname.isEmpty ? '用户' : nickname;
    final avatarUrl = post['avatarUrl']?.toString();
    final authorId = (post['userId'] as num?)?.toInt();
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: authorId == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(userId: authorId),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CommunityOnlineIndicator(
              online: post['isOnline'] == true,
              dotSize: 10,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Text(name[0], style: AppTextStyles.bodySmall)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopFollowButton() {
    final following = _post?['following'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _toggleFollow,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 68),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: following
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.primary, width: 1.2),
          ),
          alignment: Alignment.center,
          child: Text(
            following ? '已关注' : '关注',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  String _shortRegionLabel(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty || const {'未知', '本地', '内网'}.contains(value)) return '';
    value = value.replaceFirst(RegExp(r'^中国(?:大陆)?\s*'), '');
    const regions = <String>[
      '黑龙江',
      '内蒙古',
      '北京',
      '天津',
      '上海',
      '重庆',
      '河北',
      '山西',
      '辽宁',
      '吉林',
      '江苏',
      '浙江',
      '安徽',
      '福建',
      '江西',
      '山东',
      '河南',
      '湖北',
      '湖南',
      '广东',
      '广西',
      '海南',
      '四川',
      '贵州',
      '云南',
      '西藏',
      '陕西',
      '甘肃',
      '青海',
      '宁夏',
      '新疆',
      '台湾',
      '香港',
      '澳门',
    ];
    final compact = value.replaceAll(RegExp(r'[\s,/·-]+'), '');
    for (final region in regions) {
      if (compact.startsWith(region)) return region;
    }
    final first = value.split(RegExp(r'[\s,/·-]+')).first;
    return first.replaceFirst(
      RegExp(r'(?:特别行政区|壮族自治区|回族自治区|维吾尔自治区|自治区|省|市)$'),
      '',
    );
  }

  Widget _buildPostMetaRow() {
    final post = _post!;
    final createdAt = post['createdAt']?.toString() ?? '';
    final timeText = createdAt.trim().isEmpty
        ? ''
        : AppDateUtils.formatCommentTime(createdAt);
    final location = _shortRegionLabel(
      post['locationCode']?.toString() ?? post['locationName']?.toString(),
    );
    final metaText = [
      timeText,
      location,
    ].where((value) => value.isNotEmpty).join('  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 14),
      child: Row(
        children: [
          if (metaText.isNotEmpty)
            Text(
              metaText,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.communityMeta,
                fontSize: 12,
              ),
            ),
          const Spacer(),
          if (!_isOwner)
            InkWell(
              key: const ValueKey('post-detail-dislike'),
              onTap: _markNotInterested,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.communityDivider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ReferenceActionGlyph(
                      type: ReferenceActionIconType.dislike,
                      size: 16,
                      color: AppColors.communityMeta,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '不喜欢',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.communityMeta,
                        fontSize: 12,
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

  int _compareComments(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (_commentSortHot) {
      final likeCompare = ((b['likeCount'] as num?)?.toInt() ?? 0).compareTo(
        (a['likeCount'] as num?)?.toInt() ?? 0,
      );
      if (likeCompare != 0) return likeCompare;
    }
    final at = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bt = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  }

  Widget _buildCommentSortButton() {
    return InkWell(
      key: const ValueKey('comment-sort-button'),
      onTap: () async {
        final selected = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.white,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('推荐排序'),
                  trailing: _commentSortHot
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.communityAccent,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, true),
                ),
                ListTile(
                  title: const Text('最新排序'),
                  trailing: !_commentSortHot
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.communityAccent,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, false),
                ),
              ],
            ),
          ),
        );
        if (selected != null && mounted) {
          setState(() => _commentSortHot = selected);
        }
      },
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Icon(
          Icons.sort_rounded,
          size: 21,
          color: _commentSortHot
              ? AppColors.communityText
              : AppColors.communityMeta,
        ),
      ),
    );
  }

  Widget _buildEmptyComments() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.forum_outlined,
            size: 48,
            color: AppColors.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无评论，快来抢沙发吧',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(int commentId) async {
    if (!_available ||
        !_comments.any((item) => item['id'] == commentId) ||
        !_commentActions.add(commentId)) {
      return;
    }
    try {
      await _scope.post(
        '/api/community/post/${widget.postId}/comment/$commentId/delete',
      );
      if (!mounted || !_available) return;
      _postLoadRevision++;
      _loading = false;
      showAppToast(context, '已删除');
      setState(() {
        final hadComment = _comments.any((item) => item['id'] == commentId);
        _comments.removeWhere((item) => item['id'] == commentId);
        if (hadComment) {
          _post!['commentCount'] =
              (((_post!['commentCount'] as num?)?.toInt() ?? 1) - 1)
                  .clamp(0, 999999);
        }
      });
      await _refreshComments();
    } catch (error) {
      await _commentFailure(error, '删除失败');
    } finally {
      _commentActions.remove(commentId);
    }
  }

  Future<void> _toggleCommentLike(Map<String, dynamic> item) async {
    final commentId = (item['id'] as num?)?.toInt();
    if (!_available || commentId == null || !_commentActions.add(commentId)) {
      return;
    }
    final liked = item['liked'] == true;
    final disliked = item['disliked'] == true;
    final oldCount = (item['likeCount'] as num?)?.toInt() ?? 0;
    final oldDislikeCount = (item['dislikeCount'] as num?)?.toInt() ?? 0;
    setState(() {
      item['liked'] = !liked;
      item['likeCount'] = (oldCount + (liked ? -1 : 1)).clamp(0, 999999);
      if (!liked && disliked) {
        item['disliked'] = false;
        item['dislikeCount'] = (oldDislikeCount - 1).clamp(0, 999999);
      }
    });
    try {
      final data = await _scope.post(
        '/api/community/comment/$commentId/like',
      );
      if (data['liked'] is! bool || data['disliked'] is! bool) {
        throw const ImWorkflowFailure('操作结果待确认，请刷新评论');
      }
      if (_available) {
        _commentLoadRevision++;
        _loadingMoreComments = false;
        setState(() {
          for (final current in _comments.where((e) => e['id'] == commentId)) {
            current['liked'] = data['liked'];
            current['disliked'] = data['disliked'];
            current['likeCount'] =
                (data['likeCount'] as num?)?.toInt() ?? oldCount;
            current['dislikeCount'] =
                (data['dislikeCount'] as num?)?.toInt() ?? oldDislikeCount;
          }
        });
      }
    } catch (error) {
      if (!_available) return;
      setState(() {
        item['liked'] = liked;
        item['likeCount'] = oldCount;
        item['disliked'] = disliked;
        item['dislikeCount'] = oldDislikeCount;
      });
      await _commentFailure(error, '操作失败');
    } finally {
      _commentActions.remove(commentId);
    }
  }

  Future<void> _toggleCommentDislike(Map<String, dynamic> item) async {
    final commentId = (item['id'] as num?)?.toInt();
    if (!_available || commentId == null || !_commentActions.add(commentId)) {
      return;
    }
    final disliked = item['disliked'] == true;
    final liked = item['liked'] == true;
    final oldCount = (item['dislikeCount'] as num?)?.toInt() ?? 0;
    final oldLikeCount = (item['likeCount'] as num?)?.toInt() ?? 0;
    setState(() {
      item['disliked'] = !disliked;
      item['dislikeCount'] = (oldCount + (disliked ? -1 : 1)).clamp(0, 999999);
      if (!disliked && liked) {
        item['liked'] = false;
        item['likeCount'] = (oldLikeCount - 1).clamp(0, 999999);
      }
    });
    try {
      final data = await _scope.post(
        '/api/community/comment/$commentId/dislike',
      );
      if (data['liked'] is! bool || data['disliked'] is! bool) {
        throw const ImWorkflowFailure('操作结果待确认，请刷新评论');
      }
      if (_available) {
        _commentLoadRevision++;
        _loadingMoreComments = false;
        setState(() {
          for (final current in _comments.where((e) => e['id'] == commentId)) {
            current['liked'] = data['liked'];
            current['disliked'] = data['disliked'];
            current['likeCount'] =
                (data['likeCount'] as num?)?.toInt() ?? oldLikeCount;
            current['dislikeCount'] =
                (data['dislikeCount'] as num?)?.toInt() ?? oldCount;
          }
        });
      }
    } catch (error) {
      if (!_available) return;
      setState(() {
        item['disliked'] = disliked;
        item['dislikeCount'] = oldCount;
        item['liked'] = liked;
        item['likeCount'] = oldLikeCount;
      });
      await _commentFailure(error, '操作失败');
    } finally {
      _commentActions.remove(commentId);
    }
  }

  String _commentLocation(Map<String, dynamic> item) {
    for (final key in const [
      'locationCode',
      'locationName',
      'location',
      'ipLocation',
      'ipRegion',
    ]) {
      final value = item[key]?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          value != '未知' &&
          value != '本地' &&
          value != '内网') {
        return _shortRegionLabel(value);
      }
    }
    return '';
  }

  Widget _buildCommentMeta(Map<String, dynamic> item, {bool dense = false}) {
    final createdAt = item['createdAt'] as String? ?? '';
    final timeText = createdAt.trim().isEmpty
        ? ''
        : AppDateUtils.formatCommentTime(createdAt);
    final location = _commentLocation(item);
    if (timeText.isEmpty && location.isEmpty) return const SizedBox.shrink();

    final style = AppTextStyles.bodySmall.copyWith(
      color: AppColors.communityMeta,
      fontSize: dense ? 11 : 12,
      height: 1.2,
    );

    return Wrap(
      spacing: dense ? 6 : 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (timeText.isNotEmpty) Text(timeText, style: style),
        if (location.isNotEmpty) Text(location, style: style),
      ],
    );
  }

  Widget _buildCommentItem(
    Map<String, dynamic> c,
    List<Map<String, dynamic>> replies,
  ) {
    final nickname = c['nickname'] as String? ?? '用户';
    final avatarText = nickname.trim().isNotEmpty ? nickname.trim()[0] : '?';
    final avatarUrl = c['avatarUrl'] as String?;
    final content = c['content'] as String? ?? '';
    final teamTitle = (c['teamTitle'] as String?)?.trim();
    final userId = (c['userId'] as num?)?.toInt();
    final commentId = (c['id'] as num?)?.toInt();
    final postAuthorId =
        (_post != null ? (_post!['userId'] as num?)?.toInt() : null);
    final canDelete = commentId != null &&
        _currentUserId != null &&
        (_currentUserId == userId || _currentUserId == postAuthorId);

    return GestureDetector(
      key: ValueKey('comment-$commentId'),
      behavior: HitTestBehavior.opaque,
      onLongPress: commentId == null
          ? null
          : () => _showCommentActions(commentId, canDelete: canDelete),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (userId != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserProfilePage(userId: userId),
                        ),
                      );
                    }
                  },
                  child: CommunityOnlineIndicator(
                    online: c['isOnline'] == true,
                    dotSize: 9,
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.communityInsetSurface,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Text(
                              avatarText,
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nickname,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.communityName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (c['isFirst'] == true) ...[
                            const SizedBox(width: 6),
                            _buildFirstCommentBadge(),
                          ],
                          if (userId == postAuthorId) ...[
                            const SizedBox(width: 6),
                            _buildAuthorBadge(),
                          ],
                          if (teamTitle != null && teamTitle.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            TeamTitleChip(title: teamTitle, userId: userId),
                          ],
                          if (c['isAcceptedAnswer'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '已采纳',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      _buildCollapsibleText(content, commentId),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(child: _buildCommentMeta(c)),
                          const SizedBox(width: 10),
                          _commentPlainAction(
                            '回复',
                            onTap: () =>
                                _startReply(commentId, nickname: nickname),
                          ),
                          if (_isOwner &&
                              _post?['helpRequest'] is Map &&
                              (_post!['helpRequest'] as Map)['status'] !=
                                  'resolved' &&
                              c['teamIdentity'] is Map &&
                              ((c['teamIdentity'] as Map)['teamId'] as num?)
                                      ?.toInt() ==
                                  (((_post!['helpRequest'] as Map)['teamId']
                                          as num?)
                                      ?.toInt())) ...[
                            const SizedBox(width: 10),
                            _commentPlainAction(
                              '采纳',
                              onTap: () => _acceptTeamAnswer(c),
                            ),
                          ],
                          const Spacer(),
                          _commentTextAction(
                            label: '${(c['likeCount'] as num?)?.toInt() ?? 0}',
                            icon: Icon(
                              c['liked'] == true
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                            ),
                            color: c['liked'] == true
                                ? const Color(0xFFE05264)
                                : AppColors.textHint,
                            onTap: () => _toggleCommentLike(c),
                          ),
                          const SizedBox(width: 5),
                          _commentTextAction(
                            label:
                                '${(c['dislikeCount'] as num?)?.toInt() ?? 0}',
                            icon: const ReferenceActionGlyph(
                              type: ReferenceActionIconType.dislike,
                              size: 18,
                            ),
                            color: c['disliked'] == true
                                ? AppColors.communityName
                                : AppColors.textHint,
                            onTap: () => _toggleCommentDislike(c),
                          ),
                        ],
                      ),
                      if (replies.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildRepliesBlock(replies, commentId, postAuthorId),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(
              height: 1,
              color: AppColors.communityDivider,
              indent: 49,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepliesBlock(
    List<Map<String, dynamic>> replies,
    int? commentId,
    int? postAuthorId,
  ) {
    final expanded =
        commentId != null && _expandedReplyCommentIds.contains(commentId);
    final visibleReplies = expanded ? replies : replies.take(2).toList();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...visibleReplies.map((r) {
            final rid = (r['id'] as num?)?.toInt();
            final rootId = (r['parentId'] as num?)?.toInt() ?? commentId;
            final replyUserId = (r['userId'] as num?)?.toInt();
            final rCanDelete = rid != null &&
                _currentUserId != null &&
                (_currentUserId == replyUserId ||
                    _currentUserId == postAuthorId);
            final rTitle = (r['teamTitle'] as String?)?.trim();
            final replyName =
                r['nickname']?.toString().trim().isNotEmpty == true
                    ? r['nickname'].toString().trim()
                    : '用户';
            final replyAvatar = r['avatarUrl']?.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: rid == null
                    ? null
                    : () => _showCommentActions(
                          rid,
                          canDelete: rCanDelete,
                          isReply: true,
                        ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: replyUserId == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfilePage(userId: replyUserId),
                                ),
                              ),
                      child: CommunityOnlineIndicator(
                        online: r['isOnline'] == true,
                        dotSize: 8,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.communityInsetSurface,
                          backgroundImage:
                              replyAvatar != null && replyAvatar.isNotEmpty
                                  ? NetworkImage(replyAvatar)
                                  : null,
                          child: replyAvatar == null || replyAvatar.isEmpty
                              ? Text(
                                  replyName[0],
                                  style: const TextStyle(fontSize: 10),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  replyName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.communityName,
                                  ),
                                ),
                              ),
                              if (replyUserId == postAuthorId) ...[
                                const SizedBox(width: 5),
                                _buildAuthorBadge(dense: true),
                              ],
                              if (rTitle != null && rTitle.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                TeamTitleChip(
                                  title: rTitle,
                                  userId: replyUserId,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          _buildInlineCollapsibleText(
                            r['content']?.toString() ?? '',
                            rid,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: _buildCommentMeta(r, dense: true),
                              ),
                              const SizedBox(width: 9),
                              _commentPlainAction(
                                '回复',
                                dense: true,
                                onTap: () =>
                                    _startReply(rootId, nickname: replyName),
                              ),
                              const Spacer(),
                              _commentTextAction(
                                label:
                                    '${(r['likeCount'] as num?)?.toInt() ?? 0}',
                                icon: Icon(
                                  r['liked'] == true
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                                color: r['liked'] == true
                                    ? const Color(0xFFE05264)
                                    : AppColors.textHint,
                                onTap: () => _toggleCommentLike(r),
                              ),
                              const SizedBox(width: 4),
                              _commentTextAction(
                                label:
                                    '${(r['dislikeCount'] as num?)?.toInt() ?? 0}',
                                icon: const ReferenceActionGlyph(
                                  type: ReferenceActionIconType.dislike,
                                  size: 18,
                                ),
                                color: r['disliked'] == true
                                    ? AppColors.communityName
                                    : AppColors.textHint,
                                onTap: () => _toggleCommentDislike(r),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (replies.length > 2 && commentId != null)
            GestureDetector(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedReplyCommentIds.remove(commentId);
                } else {
                  _expandedReplyCommentIds.add(commentId);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  expanded ? '收起回复' : '展开 ${replies.length - 2} 条回复',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFirstCommentBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '首评',
        style: AppTextStyles.bodySmall.copyWith(
          color: const Color(0xFFD78328),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }

  void _confirmDeleteComment(int? commentId, {bool isReply = false}) {
    if (!_available ||
        commentId == null ||
        _commentActions.contains(commentId)) {
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: Text(isReply ? '确定删除这条回复？' : '确定删除这条评论？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteComment(commentId);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleText(String content, int? commentId) {
    return ExpandablePostEntityText(
      key: ValueKey('comment-body-$commentId'),
      content: content,
      maxLines: 3,
      style: AppTextStyles.bodyLarge.copyWith(
        fontSize: 14,
        height: 1.45,
        letterSpacing: .1,
        color: AppColors.communityText,
      ),
      mentionColor: AppColors.communityText,
    );
  }

  Widget _buildInlineCollapsibleText(String content, int? commentId) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: ExpandablePostEntityText(
        key: ValueKey('reply-body-$commentId'),
        content: content,
        maxLines: 2,
        style: AppTextStyles.bodyMedium.copyWith(
          fontSize: 13,
          height: 1.45,
          color: AppColors.communityText,
        ),
        mentionColor: AppColors.communityText,
      ),
    );
  }

  void _showCommentActions(
    int commentId, {
    required bool canDelete,
    bool isReply = false,
  }) {
    if (!_available) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.communityDivider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: canDelete
                      ? const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        )
                      : const ReferenceActionGlyph(
                          type: ReferenceActionIconType.report,
                          size: 24,
                          color: AppColors.textSecondary,
                        ),
                  title: Text(canDelete ? '删除' : '举报'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (!_available) return;
                    if (canDelete) {
                      _confirmDeleteComment(commentId, isReply: isReply);
                    } else {
                      showReportSheet(
                        context,
                        targetType: 'comment',
                        targetId: commentId,
                        title: isReply ? '举报回复' : '举报评论',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commentTextAction({
    required String label,
    required Widget icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(size: 18, color: color),
              child: icon,
            ),
            if (label != '0' && label.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _commentPlainAction(
    String label, {
    required VoidCallback onTap,
    bool dense = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 3 : 4),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: dense ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textHint,
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorBadge({bool dense = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 6,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '作者',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primaryDark,
          fontSize: dense ? 9 : 10,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final replyName = _replyToNickname?.trim().isNotEmpty == true
        ? _replyToNickname!.trim()
        : null;
    final liked = _post?['liked'] == true;
    final likeCount = (_post?['likeCount'] as num?)?.toInt() ?? 0;
    final favorited = _post?['favorited'] == true;
    final favoriteCount = (_post?['favoriteCount'] as num?)?.toInt() ?? 0;
    final commentCount = (_post?['commentCount'] as num?)?.toInt() ?? 0;
    final editing = _focusNode.hasFocus;
    final hasDraft = _commentController.text.trim().isNotEmpty;
    final showSend = editing || hasDraft || _sendingComment;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        10,
        6,
        8,
        2 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              key: const ValueKey<String>('comment-input'),
              height: 40,
              padding: const EdgeInsets.only(left: 12, right: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('comment-text-field'),
                      controller: _commentController,
                      focusNode: _focusNode,
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
                      minLines: 1,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      onTapOutside: _onCommentTapOutside,
                      decoration: InputDecoration(
                        hintText:
                            replyName != null ? '回复 @$replyName' : '说点什么...',
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  if (replyName != null && editing)
                    IconButton(
                      tooltip: '取消回复',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 36,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textHint,
                      onPressed: _cancelReply,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (showSend)
            SizedBox(
              key: _sendButtonKey,
              height: 40,
              child: FilledButton(
                key: const ValueKey<String>('send-comment'),
                onPressed: _sendingComment ? null : _sendComment,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: .35,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(58, 40),
                  shape: const StadiumBorder(),
                ),
                child: _sendingComment
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '发送',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            )
          else ...[
            if (!_isOwner)
              _bottomEmotionAction(
                icon: const ReferenceActionGlyph(
                  type: ReferenceActionIconType.privateChat,
                  size: 23,
                ),
                label: '私聊',
                color: const Color(0xFF3F4248),
                onTap: _openPrivateChat,
              ),
            _bottomEmotionAction(
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              ),
              label: '$likeCount',
              color: liked ? const Color(0xFFE05264) : const Color(0xFF3F4248),
              active: liked,
              onTap: _toggleLike,
            ),
            _bottomEmotionAction(
              icon: Icon(
                favorited ? Icons.star_rounded : Icons.star_border_rounded,
              ),
              label: '$favoriteCount',
              color:
                  favorited ? const Color(0xFFFFB524) : const Color(0xFF3F4248),
              active: favorited,
              onTap: _toggleFavorite,
            ),
            _bottomEmotionAction(
              icon: const Icon(Icons.mode_comment_outlined),
              label: '$commentCount',
              color: const Color(0xFF3F4248),
              onTap: _focusNode.requestFocus,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomEmotionAction({
    required Widget icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return SizedBox(
      width: 48,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(size: 23, color: color),
                child: icon,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppTextStyles.bodySmall.copyWith(
                  color: active ? color : const Color(0xFF3F4248),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
