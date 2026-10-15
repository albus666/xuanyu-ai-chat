import 'dart:convert';

import 'package:fluwx/fluwx.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/community/share_post_to_users_page.dart';
import '../../features/message/im_workflow_request.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_toast.dart';

String communityUserShareLink(Map<String, dynamic> user) {
  final userId = (user['userId'] as num?)?.toInt() ?? 0;
  return '${AppConstants.baseUrl}/api/community/share/user/$userId';
}

String _shareText(Map<String, dynamic> user) {
  final nickname = user['nickname']?.toString().trim() ?? '玄遇用户';
  final intro = user['intro']?.toString().trim() ?? '';
  return '在玄遇遇见 $nickname\n${intro.isEmpty ? '来看看 TA 的瞬间与故事' : intro}\n${communityUserShareLink(user)}';
}

String _profileMessageJson(Map<String, dynamic> user) {
  return jsonEncode({
    'userId': (user['userId'] as num?)?.toInt(),
    'nickname': user['nickname'] ?? '玄遇用户',
    'avatarUrl': user['avatarUrl'] ?? '',
    'intro': user['intro'] ?? '',
    'teamTitle': user['teamTitle'] ?? '',
    'followerCount': (user['followerCount'] as num?)?.toInt() ?? 0,
  });
}

Future<void> _shareToChannel(
  BuildContext context,
  Map<String, dynamic> user,
  String channel,
) async {
  final text = _shareText(user);
  try {
    if ((channel == '微信' || channel == '朋友圈') &&
        AppConstants.wxAppId?.isNotEmpty == true) {
      final wx = Fluwx();
      if (!await wx.isWeChatInstalled) throw StateError('未安装微信');
      final sent = await wx.share(
        WeChatShareTextModel(
          text,
          scene: channel == '朋友圈' ? WeChatScene.timeline : WeChatScene.session,
        ),
      );
      if (!sent) throw StateError('微信分享未启动');
    } else {
      await Share.share(text, subject: '分享到$channel');
    }
  } catch (_) {
    if (context.mounted) showAppToast(context, '未能打开$channel，请确认应用已安装');
  }
}

const _actionInk = Color(0xFF3F4248);

Widget _shareChannel({
  required String label,
  required ReferenceShareBrand brand,
  required VoidCallback onTap,
}) {
  return Expanded(
    child: InkWell(
      key: ValueKey('profile-share-channel-$label'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReferenceShareBrandIcon(
              key: ValueKey('profile-share-channel-icon-$label'),
              brand: brand,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _actionInk,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _moreShareChannel({required VoidCallback onTap}) {
  return Expanded(
    child: InkWell(
      key: const ValueKey('profile-share-channel-更多'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ReferenceShareMoreIcon(
              key: ValueKey('profile-share-channel-icon-更多'),
            ),
            const SizedBox(height: 6),
            Text(
              '更多',
              style: AppTextStyles.bodyMedium.copyWith(
                color: _actionInk,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _relationshipAction({
  required String label,
  required Widget icon,
  required VoidCallback onTap,
  bool selected = false,
}) {
  return Expanded(
    child: InkWell(
      key: ValueKey('profile-action-$label'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: .12)
                    : const Color(0xFFF5F5F6),
                shape: BoxShape.circle,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? AppColors.primaryDark : _actionInk,
                  size: 26,
                ),
                child: icon,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: selected ? AppColors.primaryDark : _actionInk,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _remarkGlyph() {
  return const SizedBox.square(
    dimension: 34,
    child: Stack(
      children: [
        Positioned(left: 3, top: 0, child: Icon(Icons.edit_rounded, size: 28)),
        Positioned(
            left: 1,
            right: 1,
            bottom: 2,
            child: Divider(height: 2, thickness: 2)),
      ],
    ),
  );
}

void showUserProfileShareSheet(
  BuildContext context,
  Map<String, dynamic> user, {
  VoidCallback? onRemark,
  VoidCallback? onStealth,
  VoidCallback? onQuietFollow,
  VoidCallback? onSpecialCare,
  VoidCallback? onBlock,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _UserProfileShareSheet(
      pageContext: context,
      user: user,
      onRemark: onRemark,
      onStealth: onStealth,
      onQuietFollow: onQuietFollow,
      onSpecialCare: onSpecialCare,
      onBlock: onBlock,
    ),
  );
}

class _UserProfileShareSheet extends StatefulWidget {
  const _UserProfileShareSheet({
    required this.pageContext,
    required this.user,
    this.onRemark,
    this.onStealth,
    this.onQuietFollow,
    this.onSpecialCare,
    this.onBlock,
  });

  final BuildContext pageContext;
  final Map<String, dynamic> user;
  final VoidCallback? onRemark;
  final VoidCallback? onStealth;
  final VoidCallback? onQuietFollow;
  final VoidCallback? onSpecialCare;
  final VoidCallback? onBlock;

  @override
  State<_UserProfileShareSheet> createState() => _UserProfileShareSheetState();
}

class _UserProfileShareSheetState extends State<_UserProfileShareSheet> {
  final _scope = ImWorkflowRequest();
  final _recent = <Map<String, dynamic>>[];
  bool _loadingRecent = true;
  int? _sharingConversationId;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_onSessionChanged);
    _loadRecent();
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
    final conversationId = (target['conversationId'] as num?)?.toInt();
    if (conversationId == null || _sharingConversationId != null) return;
    setState(() => _sharingConversationId = conversationId);
    try {
      await _scope.post(
        '/api/im/conversation/$conversationId/message',
        data: {'type': 'profile', 'content': _profileMessageJson(widget.user)},
      );
      if (!mounted || !_scope.current) return;
      Navigator.pop(context);
      if (widget.pageContext.mounted) {
        showAppToast(widget.pageContext, '主页已分享给${_targetName(target)}');
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

  void _afterClose(VoidCallback? action) {
    if (action == null) return;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.pageContext.mounted) action();
    });
  }

  @override
  Widget build(BuildContext context) {
    final quietFollow = widget.user['quietFollow'] == true;
    final specialCare = widget.user['specialCare'] == true;
    final stealth = widget.user['stealthProfile'] == true ||
        widget.user['stealthMoments'] == true ||
        widget.user['stealthChat'] == true;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .70),
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
                  '分享至好友',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: const Color(0xFF242529),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: 82,
                child: _loadingRecent
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _recent.isEmpty
                        ? Center(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                showModalBottomSheet<void>(
                                  context: widget.pageContext,
                                  backgroundColor: Colors.transparent,
                                  isScrollControlled: true,
                                  builder: (_) => SharePostToUsersPage.profile(
                                    profileItem: widget.user,
                                  ),
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
                              children: _recent.map(_recentTarget).toList(),
                            ),
                          ),
              ),
              const Divider(height: 1, color: AppColors.communityDivider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _shareChannel(
                      label: '微信',
                      brand: ReferenceShareBrand.weChat,
                      onTap: () => _external('微信'),
                    ),
                    _shareChannel(
                      label: '朋友圈',
                      brand: ReferenceShareBrand.moments,
                      onTap: () => _external('朋友圈'),
                    ),
                    _shareChannel(
                      label: 'QQ',
                      brand: ReferenceShareBrand.qq,
                      onTap: () => _external('QQ'),
                    ),
                    _shareChannel(
                      label: 'QQ空间',
                      brand: ReferenceShareBrand.qzone,
                      onTap: () => _external('QQ空间'),
                    ),
                    _shareChannel(
                      label: '微博',
                      brand: ReferenceShareBrand.weibo,
                      onTap: () => _external('微博'),
                    ),
                    _moreShareChannel(onTap: () => _external('更多')),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.communityDivider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _relationshipAction(
                      label: '备注',
                      icon: _remarkGlyph(),
                      onTap: () => _afterClose(widget.onRemark),
                    ),
                    _relationshipAction(
                      label: '对Ta隐身',
                      icon: const Icon(Icons.visibility_off_outlined),
                      selected: stealth,
                      onTap: () => _afterClose(widget.onStealth),
                    ),
                    _relationshipAction(
                      label: quietFollow ? '取消悄悄关注' : '悄悄关注',
                      icon: const Icon(Icons.account_box_outlined),
                      selected: quietFollow,
                      onTap: () => _afterClose(widget.onQuietFollow),
                    ),
                    _relationshipAction(
                      label: '特别关心',
                      icon: Icon(
                        specialCare
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                      selected: specialCare,
                      onTap: () => _afterClose(widget.onSpecialCare),
                    ),
                    _relationshipAction(
                      label: '拉黑',
                      icon: const Icon(Icons.person_off_outlined),
                      onTap: () => _afterClose(widget.onBlock),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _external(String channel) {
    Navigator.pop(context);
    _shareToChannel(widget.pageContext, widget.user, channel);
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
                    ? const SizedBox.square(
                        dimension: 18,
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
