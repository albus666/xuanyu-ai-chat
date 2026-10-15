import 'dart:async';
import '../message/conversation_preview.dart';

import '../../core/utils/ai_content.dart';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/post_share.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/reference_action_icons.dart';
import 'post_detail_page.dart';
import 'post_media_cache.dart';
import 'community_online_indicator.dart';
import 'post_entity_text.dart';
import 'post_publish_settings_page.dart';
import 'post_text_cover_preview.dart';
import 'topic_feed_page.dart';
import 'user_profile_page.dart';
import 'team_title_chip.dart';
import 'video_player_page.dart';
import '../message/chat_page.dart';
import '../message/joinable_groups_page.dart';
import '../fortune/voice_match_page.dart';
import '../consultation/consultation_center_page.dart';
import '../virtual_goods/virtual_avatar_studio_page.dart';
import '../shop/shop_page.dart';

String? postDisplayLocation(Map<String, dynamic> item) {
  if (item['locationSource'] != 'user') return null;
  final value = item['locationCode'] ?? item['locationName'];
  final location = value?.toString().trim() ?? '';
  return location.isEmpty ? null : location;
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.item,
    this.onTap,
    this.onTopicTap,
    this.onMentionTap,
    this.onLike,
    this.onFavorite,
    this.onShare,
    this.onFollow,
    this.onNotInterested,
    this.showActionRow = true,
    this.heroTagSuffix,
    this.currentUserId,
    this.onDeleted,

    /// 无图大字封面下是否再展示完整正文（动态详情页为 true，列表仅封面不重复）
    this.showBodyBelowTextCover = false,

    /// 详情页已有统一的右上角菜单时可关闭卡片自身菜单
    this.showMoreMenu = true,

    /// 一体式信息流：去掉外层卡片背景/圆角/阴影/边框
    this.integrated = false,

    /// 作品详情：保留一体式外观，但正文和媒体不再跟随信息流头像缩进。
    this.detailLayout = false,

    /// 一体式信息流下是否展示底部分割线
    this.showBottomDivider = false,

    /// 详情页可将作者信息提升到顶部导航栏，避免正文内重复展示。
    this.showHeader = true,

    /// 某些页面已有固定私聊入口时，可隐藏卡片内的私聊按钮。
    this.showPrivateAction = true,

    /// 个人主页瞬间在不重复作者栏时，单独显示精确到分钟的发布时间。
    this.showPreciseTimestamp = false,

    /// 个人主页中的作品卡使用更紧凑的字号、留白和操作图标。
    this.compactLayout = false,
    this.openMediaAsPost = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final void Function(int topicId, String topicName)? onTopicTap;
  final void Function(int userId, String nickname)? onMentionTap;
  final void Function(int postId)? onLike;
  final void Function(int postId)? onFavorite;
  final void Function(int postId)? onShare;
  final void Function(int userId)? onFollow;
  final void Function(int postId)? onNotInterested;
  final bool showActionRow;

  /// 用于避免同一帖子在列表与详情页同时存在时的 Hero 标签冲突
  final String? heroTagSuffix;

  /// 当前登录用户 ID，与帖子作者一致时显示「删除」
  final int? currentUserId;

  /// 删除成功后回调（从列表移除等）
  final void Function(int postId)? onDeleted;
  final bool showBodyBelowTextCover;
  final bool showMoreMenu;
  final bool integrated;
  final bool detailLayout;
  final bool showBottomDivider;
  final bool showHeader;
  final bool showPrivateAction;
  final bool showPreciseTimestamp;
  final bool compactLayout;
  final bool openMediaAsPost;

  static const double _integratedContentIndent = 60; // 头像直径+间距：正文、媒体、操作共用一条基线
  static const double _integratedContentRightInset = 20;
  static const double _feedSingleImageSize = 200;

  static String? _firstMediaUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      return s.isEmpty ? null : s;
    }
    if (raw is Map) {
      for (final k in const ['url', 'path', 'src', 'uri']) {
        final v = raw[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }

  static List<String> _extractMediaUrls(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final e in raw) {
      final u = _firstMediaUrl(e);
      if (u != null) out.add(u);
    }
    return out;
  }

  static bool _isVideoPost(Map<String, dynamic> item) {
    final t = item['mediaType'];
    return t != null && t.toString().toLowerCase() == 'video';
  }

  static bool _isAudioPost(Map<String, dynamic> item) {
    final t = item['mediaType'];
    return t != null && t.toString().toLowerCase() == 'audio';
  }

  Future<void> _openPrivateChat(BuildContext context, int userId) async {
    try {
      final res = await apiClient.post(
        '/api/im/conversation/single',
        data: {'targetUserId': userId},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final conversationId = (data?['conversationId'] as num?)?.toInt();
      if (conversationId == null || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            title: data?['title'] as String? ??
                item['nickname'] as String? ??
                '用户',
            conversationType: 'single',
            peerUserId: userId,
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) showAppToast(context, '无法发起私聊');
    }
  }

  void _showLargeImage(BuildContext context, String url, String heroTag) {
    if (openMediaAsPost && onTap != null) {
      onTap!();
      return;
    }
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.black.withValues(alpha: 0.95),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Hero(
                  tag: heroTag,
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              if (AiContent.label(item).isNotEmpty)
                Positioned(
                  left: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                  child: Text(
                    AiContent.label(item),
                    style: const TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.black87,
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPostMoreMenu(BuildContext context) {
    final postId = (item['id'] as num?)?.toInt();
    final postUserId = (item['userId'] as num?)?.toInt();
    final isOwner = currentUserId != null && postUserId == currentUserId;

    if (postId == null) return;

    Future<void> deletePost() async {
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
      if (confirmed != true || !context.mounted) return;
      try {
        await apiClient.post('/api/community/post/$postId/delete');
        if (context.mounted) {
          showAppToast(context, '已删除');
          onDeleted?.call(postId);
        }
      } catch (_) {
        if (context.mounted) showAppToast(context, '删除失败，请重试');
      }
    }

    Future<void> changeVisibility() async {
      final value = await editPublishedPostVisibility(context, postId);
      if (value == null) return;
      item['visibility'] = value.visibility;
      item['excludedUserIds'] = value.excludedUserIds.toList();
    }

    showPostMoreActionSheet(
      context,
      item,
      following: item['following'] == true,
      onPrivateChat: !isOwner && postUserId != null && currentUserId != null
          ? () => _openPrivateChat(context, postUserId)
          : null,
      onToggleFollow: !isOwner && postUserId != null && onFollow != null
          ? () => onFollow!(postUserId)
          : null,
      onNotInterested: !isOwner && onNotInterested != null
          ? () => onNotInterested!(postId)
          : null,
      onReport: !isOwner && currentUserId != null
          ? () => showReportSheet(
                context,
                targetType: 'post',
                targetId: postId,
                title: '举报帖子',
              )
          : null,
      onChangeVisibility: isOwner ? changeVisibility : null,
      onDelete: isOwner ? deletePost : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nickname = item['nickname'] as String? ?? '用户';
    final avatarUrl = item['avatarUrl'] as String?;
    final rawContent = item['content'] as String? ?? '';
    final content =
        rawContent.startsWith('【语音通话】') || rawContent.startsWith('【视频通话】')
            ? callMessageLabel(rawContent)
            : rawContent;
    final likeCount = (item['likeCount'] as num?)?.toInt() ?? 0;
    final commentCount = (item['commentCount'] as num?)?.toInt() ?? 0;
    final createdAt = item['createdAt'] as String? ?? '';
    final mediaUrls = _extractMediaUrls(item['mediaUrls']);
    final hasMedia = mediaUrls.isNotEmpty;
    final topics = item['topics'] as List<dynamic>?;
    final mentions = item['mentions'] as List<dynamic>?;
    final component = item['component'];
    final helpRequest = item['helpRequest'];
    final supplementalTopics = (topics ?? const <dynamic>[]).where((topic) {
      final name = topic is Map ? topic['name']?.toString().trim() ?? '' : '';
      return name.isNotEmpty && !content.contains('#$name');
    }).toList();
    final liked = item['liked'] == true;
    final postId = (item['id'] as num?)?.toInt();
    final postUserId = (item['userId'] as num?)?.toInt();
    final isOwner = currentUserId != null && postUserId == currentUserId;
    final indentContent = integrated && !detailLayout;

    Widget indented(Widget child) {
      if (!indentContent) return child;
      return Padding(
        padding: const EdgeInsets.only(
          left: _integratedContentIndent,
          right: _integratedContentRightInset,
        ),
        child: child,
      );
    }

    final tapHandler = onTap ??
        (postId != null
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PostDetailPage(postId: postId, initialItem: item),
                  ),
                )
            : null);

    final aiLabel = AiContent.label(item);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          _buildHeader(context, nickname, avatarUrl, createdAt),
          SizedBox(height: compactLayout ? 8 : 12),
        ],
        if (!showHeader && showPreciseTimestamp && createdAt.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: compactLayout ? 12 : 14,
                color: AppColors.communityAccent,
              ),
              SizedBox(width: compactLayout ? 4 : 5),
              Text(
                AppDateUtils.formatPostDateTime(createdAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textHint,
                  fontSize: compactLayout ? 11 : 12,
                ),
              ),
            ],
          ),
          SizedBox(height: compactLayout ? 7 : 10),
        ],
        if (aiLabel.isNotEmpty)
          indented(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                aiLabel,
                style: const TextStyle(
                  color: Color(0xFF986000),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (helpRequest is Map && helpRequest['requested'] == true)
          indented(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: .18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      helpRequest['status'] == 'resolved'
                          ? '${helpRequest['teamName'] ?? '部落'}已协助解决'
                          : '请求${helpRequest['teamName'] ?? '部落'}协助',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (helpRequest['status'] == 'resolved')
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
          ),
        if (detailLayout && hasMedia && _isAudioPost(item))
          indented(
            _PostAudioPlayer(
              url: mediaUrls.first,
              durationSeconds:
                  (item['audioDurationSeconds'] as num?)?.toInt() ?? 0,
            ),
          ),
        if (detailLayout && hasMedia && !_isAudioPost(item))
          indented(
            _buildMediaGallery(
              context,
              mediaUrls,
              _isVideoPost(item),
              postId: postId,
              heroSuffix: heroTagSuffix,
              videoCoverUrl: _firstMediaCoverUrl(item),
            ),
          ),
        if (hasMedia && content.isNotEmpty)
          indented(
            Padding(
              padding: EdgeInsets.only(top: detailLayout ? 14 : 0, right: 4),
              child: ExpandablePostEntityText(
                content: content,
                topics: topics,
                mentions: mentions,
                onTopicTap: (id, name) => _openTopic(context, id, name),
                onMentionTap: (id, name) => _openMention(context, id, name),
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: detailLayout ? 15 : (compactLayout ? 14 : 17),
                  height: detailLayout ? 1.52 : (compactLayout ? 1.5 : 1.62),
                  letterSpacing: detailLayout || compactLayout ? 0.05 : 0.15,
                  color: AppColors.communityText,
                ),
                maxLines: 4,
              ),
            ),
          ),
        if (!hasMedia && content.isNotEmpty) ...[
          if (showHeader && !integrated)
            indented(
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: PostTextCoverPreview(
                    content: content,
                    maxLines: 8,
                    topics: topics,
                    mentions: mentions,
                    onTopicTap: (id, name) => _openTopic(context, id, name),
                    onMentionTap: (id, name) => _openMention(context, id, name),
                  ),
                ),
              ),
            )
          else
            indented(
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: integrated
                    ? ExpandablePostEntityText(
                        content: content,
                        topics: topics,
                        mentions: mentions,
                        onTopicTap: (id, name) => _openTopic(context, id, name),
                        onMentionTap: (id, name) =>
                            _openMention(context, id, name),
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: detailLayout ? 15 : 17,
                          height: detailLayout ? 1.52 : 1.62,
                          letterSpacing: detailLayout ? 0.05 : 0.15,
                          color: AppColors.communityText,
                        ),
                        maxLines: 4,
                      )
                    : PostEntityText(
                        content: content,
                        topics: topics,
                        mentions: mentions,
                        onTopicTap: (id, name) => _openTopic(context, id, name),
                        onMentionTap: (id, name) =>
                            _openMention(context, id, name),
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: compactLayout ? 14 : 16,
                          height: compactLayout ? 1.5 : 1.65,
                          letterSpacing: compactLayout ? 0.05 : 0.25,
                          color: AppColors.communityText,
                        ),
                      ),
              ),
            ),
          if (showHeader && !integrated && showBodyBelowTextCover) ...[
            const SizedBox(height: 14),
            indented(
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: PostEntityText(
                  content: content,
                  topics: topics,
                  mentions: mentions,
                  onTopicTap: (id, name) => _openTopic(context, id, name),
                  onMentionTap: (id, name) => _openMention(context, id, name),
                  style: AppTextStyles.bodyLarge.copyWith(
                    height: 1.65,
                    letterSpacing: 0.25,
                    color: AppColors.textPrimary.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
          ],
        ],
        if (hasMedia && !detailLayout && _isAudioPost(item)) ...[
          SizedBox(height: compactLayout ? 6 : 8),
          indented(
            _PostAudioPlayer(
              url: mediaUrls.first,
              durationSeconds:
                  (item['audioDurationSeconds'] as num?)?.toInt() ?? 0,
            ),
          ),
        ],
        if (hasMedia && !detailLayout && !_isAudioPost(item)) ...[
          SizedBox(height: compactLayout ? 6 : 8),
          indented(
            _buildMediaGallery(
              context,
              mediaUrls,
              _isVideoPost(item),
              postId: postId,
              heroSuffix: heroTagSuffix,
              videoCoverUrl: _firstMediaCoverUrl(item),
            ),
          ),
        ],
        if (supplementalTopics.isNotEmpty) ...[
          SizedBox(height: compactLayout ? 6 : 8),
          indented(_buildTopicList(context, supplementalTopics)),
        ],
        if (component is Map && component['title'] != null) ...[
          SizedBox(height: compactLayout ? 8 : 12),
          indented(_buildAttachedComponent(context, component)),
        ],
        if (showActionRow) ...[
          SizedBox(height: compactLayout ? 8 : 12),
          indented(
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (showPrivateAction && !isOwner && postUserId != null)
                  _buildPlainAction(
                    ReferenceActionGlyph(
                      type: ReferenceActionIconType.privateChat,
                      size: compactLayout ? 19 : 22,
                      color: AppColors.communityMeta,
                    ),
                    '私聊',
                    AppColors.communityMeta,
                    onTap: () => _openPrivateChat(context, postUserId),
                  ),
                _buildPlainAction(
                  Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: compactLayout ? 19 : 22,
                    color: liked
                        ? const Color(0xFFE25568)
                        : AppColors.communityMeta,
                  ),
                  likeCount.toString(),
                  liked ? const Color(0xFFE25568) : AppColors.communityMeta,
                  onTap: postId != null && onLike != null
                      ? () => onLike!(postId)
                      : null,
                ),
                _buildPlainAction(
                  Icon(
                    Icons.mode_comment_outlined,
                    size: compactLayout ? 19 : 22,
                    color: AppColors.communityMeta,
                  ),
                  commentCount.toString(),
                  AppColors.communityMeta,
                  onTap: tapHandler,
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!integrated) {
      return GestureDetector(
        onTap: tapHandler,
        child: Container(
          margin: EdgeInsets.only(bottom: compactLayout ? 10 : 16),
          padding: compactLayout
              ? const EdgeInsets.fromLTRB(13, 12, 13, 10)
              : const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(compactLayout ? 16 : 20),
            border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: compactLayout ? 8 : 12,
                offset: Offset(0, compactLayout ? 2 : 4),
              ),
            ],
          ),
          child: body,
        ),
      );
    }

    return GestureDetector(
      onTap: tapHandler,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: body,
          ),
          if (showBottomDivider)
            Divider(
              height: 1,
              thickness: 0.8,
              color: AppColors.divider.withValues(alpha: 0.35),
              indent: _integratedContentIndent + 16,
              endIndent: _integratedContentRightInset,
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String nickname,
    String? avatarUrl,
    String createdAt,
  ) {
    final locationCode = postDisplayLocation(item);
    final postId = (item['id'] as num?)?.toInt();
    final showMore = showMoreMenu &&
        postId != null &&
        (currentUserId != null || onShare != null);
    final userId = (item['userId'] as num?)?.toInt();
    final isOwner = currentUserId != null && currentUserId == userId;
    final following = item['following'] == true;
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            final userId = (item['userId'] as num?)?.toInt();
            if (userId != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(userId: userId),
                ),
              );
            }
          },
          child: CommunityOnlineIndicator(
            online: item['isOnline'] == true,
            dotSize: compactLayout ? 10 : 12,
            child: CircleAvatar(
              radius: compactLayout ? 18 : 22,
              backgroundColor: AppColors.communityInsetSurface,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? postPreviewImage(avatarUrl, 160)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      nickname.isNotEmpty ? nickname[0] : '?',
                      style: AppTextStyles.titleSmall,
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(width: compactLayout ? 9 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      nickname,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: compactLayout ? 13.5 : 15,
                        color: AppColors.communityName,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TeamTitleChip(
                    title: item['teamTitle'] as String?,
                    userId: (item['userId'] as num?)?.toInt(),
                  ),
                ],
              ),
              SizedBox(height: compactLayout ? 1 : 2),
              Row(
                children: [
                  Text(
                    AppDateUtils.formatRelativeMD(createdAt),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.communityMeta,
                      fontSize: compactLayout ? 11 : 12,
                    ),
                  ),
                  if (locationCode != null &&
                      locationCode.toString().trim().isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compactLayout ? 4 : 6,
                      ),
                      child: const Text(
                        '·',
                        style: TextStyle(color: AppColors.communityMeta),
                      ),
                    ),
                    Icon(
                      Icons.location_on_rounded,
                      size: compactLayout ? 9 : 10,
                      color: AppColors.communityMeta,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        locationCode.toString().trim(),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.communityMeta,
                          fontSize: compactLayout ? 11 : 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (!isOwner && userId != null && onFollow != null)
          GestureDetector(
            onTap: () => onFollow!(userId),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compactLayout ? 11 : 14,
                vertical: compactLayout ? 5 : 7,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.communityAccent,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    following ? '已关注' : '关注',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.communityAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (showMore)
          IconButton(
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 20,
              color: AppColors.textHint.withValues(alpha: 0.6),
            ),
            onPressed: () => _showPostMoreMenu(context),
          ),
      ],
    );
  }

  static String? _firstMediaCoverUrl(Map<String, dynamic> item) {
    final covers = item['mediaCoverUrls'];
    if (covers is List) {
      for (final e in covers) {
        final s = _firstMediaUrl(e);
        if (s != null) return s;
      }
    }
    return null;
  }

  Widget _buildMediaGallery(
    BuildContext context,
    List<String> urls,
    bool isVideo, {
    int? postId,
    String? heroSuffix,
    String? videoCoverUrl,
  }) {
    if (isVideo && urls.isNotEmpty) {
      final videoUrl = urls[0].toString();
      return GestureDetector(
        onTap: () {
          if (openMediaAsPost && onTap != null) {
            onTap!();
            return;
          }
          if (videoUrl.trim().isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                videoUrl: videoUrl,
                aiLabel: AiContent.label(item),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (videoCoverUrl != null && videoCoverUrl.isNotEmpty)
                  Image(
                    image: detailLayout
                        ? NetworkImage(videoCoverUrl)
                        : postPreviewImage(
                            videoCoverUrl,
                            postPreviewEdge(
                              MediaQuery.sizeOf(context).width,
                              MediaQuery.devicePixelRatioOf(context),
                            ),
                          ),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF1a1a1a)),
                  )
                else
                  Container(color: const Color(0xFF1a1a1a)),
                Container(color: Colors.black.withValues(alpha: 0.2)),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (detailLayout && urls.isNotEmpty) {
      return _DetailImageCarousel(
        urls: urls,
        postId: postId,
        heroSuffix: heroSuffix,
        onOpen: (index, tag) => _showLargeImage(context, urls[index], tag),
      );
    }

    if (urls.length == 1) {
      final url = urls[0].toString();
      final tag =
          'hero_img_${postId ?? 0}_0${heroSuffix != null ? '_$heroSuffix' : ''}';
      return LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = integrated &&
                  !detailLayout &&
                  constraints.maxWidth > _feedSingleImageSize
              ? _feedSingleImageSize
              : constraints.maxWidth;
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: previewSize,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: GestureDetector(
                  onTap: () => _showLargeImage(context, url, tag),
                  child: Hero(
                    tag: tag,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        width: previewSize,
                        errorBuilder: (_, __, ___) => Container(
                            height: previewSize,
                            color: AppColors.cardBackground),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: urls.length == 2 ? 2 : 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: urls.length > 9 ? 9 : urls.length,
      itemBuilder: (context, index) {
        final url = urls[index].toString();
        final tag =
            'hero_img_${postId ?? 0}_$index${heroSuffix != null ? '_$heroSuffix' : ''}';
        return GestureDetector(
          onTap: () => _showLargeImage(context, url, tag),
          child: Hero(
            tag: tag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(
                image: postPreviewImage(
                  url,
                  postPreviewEdge(
                    MediaQuery.sizeOf(context).width,
                    MediaQuery.devicePixelRatioOf(context),
                  ),
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.cardBackground),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openTopic(BuildContext context, int topicId, String topicName) {
    if (onTopicTap != null) {
      onTopicTap!(topicId, topicName);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicFeedPage(topicId: topicId, topicName: topicName),
      ),
    );
  }

  void _openMention(BuildContext context, int userId, String nickname) {
    if (onMentionTap != null) {
      onMentionTap!(userId, nickname);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserProfilePage(userId: userId)));
  }

  Widget _buildTopicList(BuildContext context, List<dynamic> topics) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: topics.map((t) {
        final name = t is Map ? t['name']?.toString() ?? '' : t.toString();
        final id = t is Map ? (t['id'] as num?)?.toInt() : null;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: id == null ? null : () => _openTopic(context, id, name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '# $name',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAttachedComponent(BuildContext context, Map component) {
    final key = component['key']?.toString() ?? '';
    final title = component['title']?.toString() ?? '互动组件';
    final subtitle = component['subtitle']?.toString() ?? '';
    final icon = switch (key) {
      'voice_match' => Icons.graphic_eq_rounded,
      'voice_party' => Icons.spatial_audio_off_rounded,
      'interest_group' || 'group_party' => Icons.groups_rounded,
      'avatar_studio' => Icons.face_retouching_natural_rounded,
      'xuanyu_store' => Icons.storefront_rounded,
      'poll' => Icons.poll_rounded,
      _ => Icons.widgets_rounded,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.5,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAttachedComponent(context, component),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE7EFEF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 21,
                    height: 21,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF66DCD5), Color(0xFF6D86EC)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF303338),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF999DA3),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (key != 'poll')
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFB2B7BC),
                      size: 14,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAttachedComponent(BuildContext context, Map component) {
    final key = component['key']?.toString() ?? '';
    final reference = component['referenceId'];
    final referenceId =
        reference is num ? reference.toInt() : int.tryParse('$reference');
    Widget? page;
    switch (key) {
      case 'voice_match':
        page = const VoiceMatchPage();
      case 'voice_party':
        page = const ConsultationCenterPage(initialTab: 2);
      case 'interest_group':
        page = const JoinableGroupsPage();
      case 'avatar_studio':
        page = const VirtualAvatarStudioPage();
      case 'xuanyu_store':
        page = const ShopPage();
      case 'group_party':
        if (referenceId != null) {
          page = ChatPage(
            conversationId: referenceId,
            title: component['title']?.toString() ?? '群聊派对',
            conversationType: 'group',
          );
        }
    }
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
    }
  }

  Widget _buildPlainAction(
    Widget icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 3,
          vertical: compactLayout ? 6 : 9,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(size: compactLayout ? 19 : 22, color: color),
              child: icon,
            ),
            SizedBox(width: compactLayout ? 4 : 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: compactLayout ? 11 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostAudioPlayer extends StatefulWidget {
  const _PostAudioPlayer({required this.url, required this.durationSeconds});

  final String url;
  final int durationSeconds;

  @override
  State<_PostAudioPlayer> createState() => _PostAudioPlayerState();
}

class _PostAudioPlayerState extends State<_PostAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.durationSeconds > 0 ? widget.durationSeconds : 1;
    final progress = (_position.inSeconds / total).clamp(0.0, 1.0);
    final label = widget.durationSeconds <= 0
        ? '声音作品'
        : '${widget.durationSeconds ~/ 60}:${(widget.durationSeconds % 60).toString().padLeft(2, '0')}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE9FAF8), Color(0xFFF8F0F5)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary,
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: AppColors.primary,
                    backgroundColor: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Text(
                label,
                style: const TextStyle(color: Color(0xFF777C82), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailImageCarousel extends StatefulWidget {
  const _DetailImageCarousel({
    required this.urls,
    required this.postId,
    required this.heroSuffix,
    required this.onOpen,
  });

  final List<String> urls;
  final int? postId;
  final String? heroSuffix;
  final void Function(int index, String heroTag) onOpen;

  @override
  State<_DetailImageCarousel> createState() => _DetailImageCarouselState();
}

class _DetailImageCarouselState extends State<_DetailImageCarousel> {
  int _index = 0;

  String _heroTag(int index) =>
      'hero_img_${widget.postId ?? 0}_$index${widget.heroSuffix != null ? '_${widget.heroSuffix}' : ''}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.45,
          child: PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              final tag = _heroTag(index);
              return GestureDetector(
                onTap: () => widget.onOpen(index, tag),
                child: Hero(
                  tag: tag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Image.network(
                        widget.urls[index],
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: AppColors.cardBackground),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.urls.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.urls.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _index
                      ? AppColors.communityAccent
                      : AppColors.communityDivider,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
