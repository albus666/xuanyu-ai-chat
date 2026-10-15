import 'package:fluwx/fluwx.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../community/share_post_to_users_page.dart';

String _voiceRoomShareText(Map<String, dynamic> room) {
  final title = room['title']?.toString().trim();
  final roomNo = room['roomNo']?.toString().trim();
  return [
    '邀请你来玄遇语音房${title?.isNotEmpty == true ? '《$title》' : ''}',
    if (roomNo?.isNotEmpty == true) '房间号：$roomNo',
    '打开玄遇，搜索房间号即可加入',
    AppConstants.baseUrl,
  ].join('\n');
}

Future<void> _shareVoiceRoomExternally(
  BuildContext context,
  Map<String, dynamic> room,
  String channel,
) async {
  final text = _voiceRoomShareText(room);
  try {
    if ((channel == '微信' || channel == '朋友圈') &&
        AppConstants.wxAppId?.isNotEmpty == true) {
      final wx = Fluwx();
      if (!await wx.isWeChatInstalled) throw StateError('未安装微信');
      final sent = await wx.share(WeChatShareTextModel(
        text,
        scene: channel == '朋友圈' ? WeChatScene.timeline : WeChatScene.session,
      ));
      if (!sent) throw StateError('分享未启动');
    } else {
      await Share.share(text, subject: '玄遇语音房邀请');
    }
  } catch (_) {
    if (context.mounted) showAppToast(context, '未能打开$channel，请确认应用已安装');
  }
}

Future<void> showVoiceRoomInviteSheet(
  BuildContext context,
  Map<String, dynamic> room,
) async {
  final pageContext = context;
  final channel = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE7EBEB),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 15),
            Text('邀请好友进入房间', style: AppTextStyles.titleMedium),
            const SizedBox(height: 15),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE5F7F5),
                child: Icon(Icons.people_alt_rounded, color: AppColors.primary),
              ),
              title: const Text('玄遇好友与群聊'),
              subtitle: const Text('发送可直接进入房间的邀请卡'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(sheetContext, '玄遇'),
            ),
            const Divider(height: 22),
            SizedBox(
              height: 82,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _RoomShareChannel(
                    label: '微信',
                    icon: const ReferenceShareBrandIcon(
                        brand: ReferenceShareBrand.weChat),
                    onTap: () => Navigator.pop(sheetContext, '微信'),
                  ),
                  _RoomShareChannel(
                    label: '朋友圈',
                    icon: const ReferenceShareBrandIcon(
                        brand: ReferenceShareBrand.moments),
                    onTap: () => Navigator.pop(sheetContext, '朋友圈'),
                  ),
                  _RoomShareChannel(
                    label: 'QQ',
                    icon: const ReferenceShareBrandIcon(
                        brand: ReferenceShareBrand.qq),
                    onTap: () => Navigator.pop(sheetContext, 'QQ'),
                  ),
                  _RoomShareChannel(
                    label: 'QQ空间',
                    icon: const ReferenceShareBrandIcon(
                        brand: ReferenceShareBrand.qzone),
                    onTap: () => Navigator.pop(sheetContext, 'QQ空间'),
                  ),
                  _RoomShareChannel(
                    label: '微博',
                    icon: const ReferenceShareBrandIcon(
                        brand: ReferenceShareBrand.weibo),
                    onTap: () => Navigator.pop(sheetContext, '微博'),
                  ),
                  _RoomShareChannel(
                    label: '更多',
                    icon: const ReferenceShareMoreIcon(),
                    onTap: () => Navigator.pop(sheetContext, '更多'),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    ),
  );
  if (channel == null || !pageContext.mounted) return;
  if (channel == '玄遇') {
    final owner = room['owner'] is Map ? room['owner'] as Map : const {};
    await showModalBottomSheet<bool>(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SharePostToUsersPage.room(
        roomItem: {
          'id': room['id'],
          'roomNo': room['roomNo'],
          'title': room['title'],
          'roomType': room['roomType'],
          'category': room['category'],
          'onlineCount': room['onlineCount'],
          'ownerNickname': owner['nickname'],
        },
      ),
    );
    return;
  }
  await _shareVoiceRoomExternally(pageContext, room, channel);
}

class _RoomShareChannel extends StatelessWidget {
  const _RoomShareChannel({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 70,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                style:
                    const TextStyle(color: Color(0xFF3F4248), fontSize: 11.5)),
          ]),
        ),
      );
}
