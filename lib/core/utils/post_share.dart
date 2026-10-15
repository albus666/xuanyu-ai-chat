import 'ai_content.dart';
import 'share_card_capture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fluwx/fluwx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/community/share_image_dialog.dart';
import '../../features/community/share_post_to_users_page.dart';
import '../../features/message/im_workflow_request.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_toast.dart';

String communityPostShareLink(Map<String, dynamic> postItem) {
  final id = (postItem['id'] as num?)?.toInt();
  return '${AppConstants.baseUrl}/api/community/share/post/${id ?? 0}';
}

String _communityPostShareText(Map<String, dynamic> postItem) {
  final nickname = postItem['nickname']?.toString().trim() ?? '玄遇用户';
  final raw = AiContent.markedText(
    postItem['content']?.toString().trim() ?? '',
    AiContent.label(postItem),
  );
  final content = raw.length > 72 ? '${raw.substring(0, 72)}…' : raw;
  return '来自玄遇 · $nickname\n${content.isEmpty ? '这里有一条想与你分享的心情' : content}\n${communityPostShareLink(postItem)}';
}

Future<void> _recordExternalShare(
  Map<String, dynamic> postItem,
  void Function(int? newShareCount)? onShared,
  ImWorkflowRequest scope,
) async {
  final postId = (postItem['id'] as num?)?.toInt();
  if (postId == null || !scope.current) return;
  try {
    final data = await scope.post('/api/community/post/$postId/share');
    if (scope.current) {
      onShared?.call((data['shareCount'] as num?)?.toInt());
    }
  } catch (_) {}
}

Future<void> _shareToChannel(
  BuildContext context,
  Map<String, dynamic> postItem,
  String channel, {
  void Function(int? newShareCount)? onShared,
  required ImWorkflowRequest scope,
}) async {
  if (postItem['disableForward'] == true) {
    if (context.mounted) showAppToast(context, '作者已禁止转发');
    return;
  }
  final text = _communityPostShareText(postItem);
  try {
    if ((channel == '微信' || channel == '朋友圈') &&
        AppConstants.wxAppId?.isNotEmpty == true) {
      final wx = Fluwx();
      if (await wx.isWeChatInstalled) {
        final sent = await wx.share(
          WeChatShareTextModel(
            text,
            scene: channel == '朋友圈'
                ? WeChatScene.timeline
                : WeChatScene.session,
          ),
        );
        if (!sent) throw StateError('微信分享未启动');
      } else {
        throw StateError('未安装微信');
      }
    } else {
      await Share.share(text, subject: '分享到$channel');
    }
    await _recordExternalShare(postItem, onShared, scope);
  } catch (_) {
    if (context.mounted) showAppToast(context, '未能打开$channel，请确认应用已安装');
  }
}

Future<void> copyCommunityPostLink(
  BuildContext context,
  Map<String, dynamic> postItem,
) async {
  if (postItem['disableForward'] == true) {
    if (context.mounted) showAppToast(context, '作者已禁止转发');
    return;
  }
  await Clipboard.setData(
    ClipboardData(text: communityPostShareLink(postItem)),
  );
  if (context.mounted) showAppToast(context, '链接已复制');
}

Future<void> copyCommunityPostContent(
  BuildContext context,
  Map<String, dynamic> postItem,
) async {
  if (postItem['disableDownloadCopy'] == true) {
    if (context.mounted) showAppToast(context, '作者已禁止下载和复制');
    return;
  }
  final content = postItem['content']?.toString().trim() ?? '';
  if (content.isEmpty) {
    if (context.mounted) showAppToast(context, '这条作品没有可复制的文字');
    return;
  }
  await Clipboard.setData(
    ClipboardData(
      text: AiContent.markedText(content, AiContent.label(postItem)),
    ),
  );
  if (context.mounted) showAppToast(context, '文字已复制');
}

Future<void> saveOrShareCommunityPostMedia(
  BuildContext context,
  Map<String, dynamic> postItem,
) async {
  if (postItem['disableDownloadCopy'] == true) {
    if (context.mounted) showAppToast(context, '作者已禁止下载和复制');
    return;
  }
  final aiLabel = AiContent.label(postItem);
  if (aiLabel.isNotEmpty &&
      ['video', 'audio'].contains(postItem['mediaType'])) {
    if (context.mounted) showAppToast(context, '含AI标识的音视频请通过作品链接分享，以保留提示');
    return;
  }
  final rawUrls = postItem['mediaUrls'];
  final urls = rawUrls is List
      ? rawUrls
            .map((value) => value?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .take(9)
            .toList()
      : <String>[];
  if (urls.isEmpty) {
    if (context.mounted) showAppToast(context, '这条作品没有可保存的图片或视频');
    return;
  }
  try {
    final directory = await getTemporaryDirectory();
    final mediaType =
        postItem['mediaType']?.toString().toLowerCase() ?? 'image';
    final files = <XFile>[];
    for (var index = 0; index < urls.length; index++) {
      final response = await Dio().get<List<int>>(
        urls[index],
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) continue;
      final extension = aiLabel.isNotEmpty
          ? 'png'
          : (mediaType == 'video'
                ? 'mp4'
                : (mediaType == 'audio' ? 'm4a' : 'jpg'));
      final file = File(
        '${directory.path}/xuanyu_post_${postItem['id'] ?? 0}_$index.$extension',
      );
      final output = aiLabel.isEmpty
          ? bytes
          : await ShareCardCapture.labelImage(
              bytes,
              label: aiLabel,
              source: postItem['AIGC'] is Map ? postItem['AIGC'] as Map : null,
              propagated: true,
            );
      await file.writeAsBytes(output, flush: true);
      files.add(XFile(file.path));
    }
    if (files.isEmpty) throw StateError('empty media');
    await Share.shareXFiles(
      files,
      text: _communityPostShareText(postItem),
      subject: '玄遇作品',
    );
  } catch (_) {
    if (context.mounted) showAppToast(context, '保存/分享失败，请稍后重试');
  }
}

void _openXuanyuShare(
  BuildContext context,
  Map<String, dynamic> postItem,
  void Function(int? newShareCount)? onShared,
) {
  if (postItem['disableForward'] == true) {
    showAppToast(context, '作者已禁止转发');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        SharePostToUsersPage(postItem: postItem, onShared: onShared),
  );
}

const _shareActionColor = Color(0xFF3F4248);

Widget _shareChannelButton({
  required String label,
  required ReferenceShareBrand brand,
  required VoidCallback onTap,
}) {
  return Expanded(
    child: InkWell(
      key: ValueKey('share-channel-$label'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReferenceShareBrandIcon(
              key: ValueKey('share-channel-icon-$label'),
              brand: brand,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _shareActionColor,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _shareMoreButton({required VoidCallback onTap}) {
  return Expanded(
    child: InkWell(
      key: const ValueKey('share-channel-更多'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ReferenceShareMoreIcon(
              key: ValueKey('share-channel-icon-更多'),
            ),
            const SizedBox(height: 6),
            Text(
              '更多',
              style: AppTextStyles.bodyMedium.copyWith(
                color: _shareActionColor,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _actionButton({
  required String label,
  required Widget icon,
  required VoidCallback onTap,
}) {
  return Expanded(
    child: InkWell(
      key: ValueKey('post-action-$label'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('post-action-icon-$label'),
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F6),
                shape: BoxShape.circle,
              ),
              child: IconTheme(
                data: const IconThemeData(color: _shareActionColor, size: 26),
                child: icon,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _shareActionColor,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<Widget> _shareChannels(
  BuildContext sheetContext,
  BuildContext pageContext,
  Map<String, dynamic> postItem,
  void Function(int? newShareCount)? onShared,
  ImWorkflowRequest scope,
) {
  void external(String channel) {
    Navigator.pop(sheetContext);
    _shareToChannel(
      pageContext,
      postItem,
      channel,
      onShared: onShared,
      scope: scope,
    );
  }

  return [
    _shareChannelButton(
      label: '微信',
      brand: ReferenceShareBrand.weChat,
      onTap: () => external('微信'),
    ),
    _shareChannelButton(
      label: '朋友圈',
      brand: ReferenceShareBrand.moments,
      onTap: () => external('朋友圈'),
    ),
    _shareChannelButton(
      label: 'QQ',
      brand: ReferenceShareBrand.qq,
      onTap: () => external('QQ'),
    ),
    _shareChannelButton(
      label: 'QQ空间',
      brand: ReferenceShareBrand.qzone,
      onTap: () => external('QQ空间'),
    ),
    _shareChannelButton(
      label: '微博',
      brand: ReferenceShareBrand.weibo,
      onTap: () => external('微博'),
    ),
    _shareMoreButton(onTap: () => external('更多')),
  ];
}

String _buildPostMessageJson(Map<String, dynamic> item) {
  final raw = AiContent.markedText(
    item['content']?.toString() ?? '',
    AiContent.label(item),
  );
  return jsonEncode({
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
  });
}

void showSharePostSheet(
  BuildContext context,
  Map<String, dynamic> postItem, {
  void Function(int? newShareCount)? onShared,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PostShareSheet(
      pageContext: context,
      postItem: postItem,
      onShared: onShared,
    ),
  );
}

void showPostMoreActionSheet(
  BuildContext context,
  Map<String, dynamic> postItem, {
  void Function(int? newShareCount)? onShared,
  VoidCallback? onPrivateChat,
  VoidCallback? onToggleFollow,
  VoidCallback? onNotInterested,
  VoidCallback? onReport,
  VoidCallback? onChangeVisibility,
  VoidCallback? onDelete,
  bool following = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PostShareSheet(
      pageContext: context,
      postItem: postItem,
      onShared: onShared,
      onPrivateChat: onPrivateChat,
      onToggleFollow: onToggleFollow,
      onNotInterested: onNotInterested,
      onReport: onReport,
      onChangeVisibility: onChangeVisibility,
      onDelete: onDelete,
      following: following,
    ),
  );
}

class _PostShareSheet extends StatefulWidget {
  const _PostShareSheet({
    required this.pageContext,
    required this.postItem,
    this.onShared,
    this.onPrivateChat,
    this.onToggleFollow,
    this.onNotInterested,
    this.onReport,
    this.onChangeVisibility,
    this.onDelete,
    this.following = false,
  });

  final BuildContext pageContext;
  final Map<String, dynamic> postItem;
  final void Function(int? newShareCount)? onShared;
  final VoidCallback? onPrivateChat;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onNotInterested;
  final VoidCallback? onReport;
  final VoidCallback? onChangeVisibility;
  final VoidCallback? onDelete;
  final bool following;

  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  final _scope = ImWorkflowRequest();
  final _recent = <Map<String, dynamic>>[];
  bool _loadingRecent = true;
  int? _sharingConversationId;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    if (widget.postItem['disableForward'] == true) {
      _loadingRecent = false;
    } else {
      _loadRecent();
    }
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final data = await _scope.get('/api/im/conversations');
      final raw = imResponseList(data);
      if (!mounted || !_scope.current) return;
      setState(() {
        _recent.clear();
        for (final item in raw) {
          if (item['conversationId'] is num) {
            _recent.add(item);
            if (_recent.length == 5) break;
          }
        }
        _loadingRecent = false;
      });
    } catch (_) {
      if (mounted && _scope.current) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _shareDirectly(Map<String, dynamic> target) async {
    if (widget.postItem['disableForward'] == true) {
      showAppToast(context, '作者已禁止转发');
      return;
    }
    final conversationId = (target['conversationId'] as num?)?.toInt();
    if (conversationId == null || _sharingConversationId != null) return;
    setState(() => _sharingConversationId = conversationId);
    try {
      await _scope.post(
        '/api/im/conversation/$conversationId/message',
        data: {
          'type': 'post',
          'content': _buildPostMessageJson(widget.postItem),
        },
      );
      int? newShareCount;
      final postId = (widget.postItem['id'] as num?)?.toInt();
      if (postId != null) {
        try {
          final data = await _scope.post('/api/community/post/$postId/share');
          newShareCount = (data['shareCount'] as num?)?.toInt();
        } catch (_) {
          if (!_scope.current) rethrow;
          // 消息已经成功发送，计数失败不能误报整次分享失败。
        }
      }
      if (!mounted || !_scope.current) return;
      widget.onShared?.call(newShareCount);
      Navigator.pop(context);
      if (widget.pageContext.mounted) {
        showAppToast(widget.pageContext, '已分享给${_targetName(target)}');
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, imFailureMessage(error, '分享失败，请稍后重试'));
      }
    } finally {
      if (mounted && _scope.current) {
        setState(() => _sharingConversationId = null);
      }
    }
  }

  String _targetName(Map<String, dynamic> target) {
    final title = target['title']?.toString().trim();
    return title?.isNotEmpty == true ? title! : '该会话';
  }

  void _runAfterClose(VoidCallback action) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.pageContext.mounted) action();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sharingDisabled = widget.postItem['disableForward'] == true;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .68,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.communityDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 11, 20, 6),
                child: Text(
                  sharingDisabled ? '更多操作' : '分享至好友',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: const Color(0xFF242529),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!sharingDisabled) ...[
                SizedBox(
                  height: 82,
                  child: _loadingRecent
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _recent.isEmpty
                      ? Center(
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openXuanyuShare(
                                widget.pageContext,
                                widget.postItem,
                                widget.onShared,
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('选择好友'),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _recent
                                .take(5)
                                .map(_recentTarget)
                                .toList(),
                          ),
                        ),
                ),
                const Divider(height: 1, color: AppColors.communityDivider),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: _shareChannels(
                      context,
                      widget.pageContext,
                      widget.postItem,
                      widget.onShared,
                      _scope,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, color: AppColors.communityDivider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (widget.onPrivateChat != null)
                      _actionButton(
                        label: '私聊',
                        icon: const ReferenceActionCircleIcon(
                          type: ReferenceActionIconType.privateChat,
                        ),
                        onTap: () => _runAfterClose(widget.onPrivateChat!),
                      ),
                    if (!sharingDisabled)
                      _actionButton(
                        label: '生成分享图',
                        icon: const ReferenceActionCircleIcon(
                          type: ReferenceActionIconType.shareImage,
                        ),
                        onTap: () => _runAfterClose(
                          () => showShareImageDialog(
                            widget.pageContext,
                            widget.postItem,
                          ),
                        ),
                      ),
                    if (widget.onToggleFollow != null)
                      _actionButton(
                        label: widget.following ? '取消关注' : '关注',
                        icon: const ReferenceActionCircleIcon(
                          type: ReferenceActionIconType.follow,
                        ),
                        onTap: () => _runAfterClose(widget.onToggleFollow!),
                      ),
                    if (widget.onNotInterested != null)
                      _actionButton(
                        label: '不喜欢',
                        icon: const ReferenceActionCircleIcon(
                          type: ReferenceActionIconType.dislike,
                        ),
                        onTap: () => _runAfterClose(widget.onNotInterested!),
                      ),
                    if (widget.onReport != null)
                      _actionButton(
                        label: '举报',
                        icon: const ReferenceActionCircleIcon(
                          type: ReferenceActionIconType.report,
                        ),
                        onTap: () => _runAfterClose(widget.onReport!),
                      ),
                    if (widget.onChangeVisibility != null)
                      _actionButton(
                        label: '修改可见范围',
                        icon: const Icon(Icons.visibility_outlined),
                        onTap: () => _runAfterClose(widget.onChangeVisibility!),
                      ),
                    if (widget.onPrivateChat == null &&
                        widget.onToggleFollow == null &&
                        widget.onNotInterested == null &&
                        widget.onReport == null)
                      _actionButton(
                        label: '复制链接',
                        icon: const Icon(Icons.link_rounded),
                        onTap: () => _runAfterClose(
                          () => copyCommunityPostLink(
                            widget.pageContext,
                            widget.postItem,
                          ),
                        ),
                      ),
                    if (widget.onDelete != null)
                      _actionButton(
                        label: '删除',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onTap: () => _runAfterClose(widget.onDelete!),
                      ),
                  ],
                ),
              ),
              if (!sharingDisabled &&
                  widget.postItem['disableDownloadCopy'] != true) ...[
                const Divider(height: 1, color: AppColors.communityDivider),
                SizedBox(
                  height: 92,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _fixedActionButton(
                        label: '保存/分享媒体',
                        icon: const Icon(Icons.download_rounded),
                        onTap: () => _runAfterClose(
                          () => saveOrShareCommunityPostMedia(
                            widget.pageContext,
                            widget.postItem,
                          ),
                        ),
                      ),
                      _fixedActionButton(
                        label: '复制文字',
                        icon: const Icon(Icons.content_copy_rounded),
                        onTap: () => _runAfterClose(
                          () => copyCommunityPostContent(
                            widget.pageContext,
                            widget.postItem,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fixedActionButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 92,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F6),
                  shape: BoxShape.circle,
                ),
                child: IconTheme(
                  data: const IconThemeData(color: _shareActionColor, size: 26),
                  child: icon,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _shareActionColor,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentTarget(Map<String, dynamic> target) {
    final conversationId = (target['conversationId'] as num?)?.toInt();
    final avatarUrl = target['avatarUrl']?.toString().trim();
    final group = target['type'] != 'single';
    final sharing = conversationId == _sharingConversationId;
    return Expanded(
      child: InkWell(
        onTap: sharing ? null : () => _shareDirectly(target),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Column(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.communityInsetSurface,
                backgroundImage: avatarUrl?.isNotEmpty == true
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : avatarUrl?.isNotEmpty == true
                    ? null
                    : Icon(
                        group ? Icons.groups_rounded : Icons.person_rounded,
                        color: AppColors.communityName,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                _targetName(target),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.communityName,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
