import 'package:dio/dio.dart';
import 'package:fluwx/fluwx.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/community/share_post_to_users_page.dart';
import '../../features/message/im_workflow_request.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../network/api_session_scope.dart';
import '../theme/app_colors.dart';
import '../utils/app_toast.dart';
import '../utils/tool_share_message.dart';

/// Shared entry for in-app recipients and external sharing channels.
class AppShareMoreButton extends StatelessWidget {
  const AppShareMoreButton(
      {super.key,
      required this.title,
      required this.shareText,
      this.iconColor,
      this.toolRoute});
  final String title;
  final String shareText;
  final Color? iconColor;
  final String? toolRoute;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('app-share-more-button'),
        tooltip: '更多',
        onPressed: () => showAppShareSheet(context,
            title: title, shareText: shareText, toolRoute: toolRoute),
        icon: Icon(Icons.more_horiz_rounded, color: iconColor),
      );
}

Future<void> showAppShareSheet(
  BuildContext context, {
  required String title,
  required String shareText,
  String? toolRoute,
  Future<XFile> Function()? imageBuilder,
}) {
  final payload = _SharePayload(
    title: title,
    text: shareText,
    toolRoute: toolRoute,
    imageBuilder: imageBuilder,
  );
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AppShareSheet(pageContext: context, payload: payload),
  );
}

class _SharePayload {
  _SharePayload(
      {required this.title,
      required this.text,
      this.toolRoute,
      this.imageBuilder});
  final String title;
  final String text;
  final String? toolRoute;
  final Future<XFile> Function()? imageBuilder;
  final scope = ApiSessionScope();
  Future<XFile>? _file;
  String? _uploadedUrl;
  String get externalText => '$text\n${AppConstants.appDownloadUrl}';

  Future<XFile> file() async {
    scope.ensureCurrent();
    try {
      final result = await (_file ??= imageBuilder!());
      scope.ensureCurrent();
      return result;
    } catch (_) {
      _file = null;
      rethrow;
    }
  }

  Future<Map<String, String>> message(ApiSessionScope request) async {
    scope.ensureCurrent();
    request.ensureCurrent();
    if (imageBuilder == null) {
      return {
        'type': 'text',
        'content': toolRoute == null
            ? externalText
            : ToolShareMessage(title: title, text: text, route: toolRoute!)
                .encode()
      };
    }
    if (_uploadedUrl == null) {
      final image = await file();
      scope.ensureCurrent();
      request.ensureCurrent();
      final response = await request.post('/api/config/upload',
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(image.path,
                filename: 'xuanyu_share.png'),
          }));
      final data = imResponseData(response.data);
      final raw = data['url']?.toString().trim() ?? '';
      if (raw.isEmpty) throw const ImWorkflowFailure('分享图片上传失败，请重试');
      final url = Uri.parse(apiClient.options.baseUrl).resolve(raw);
      if (!['http', 'https'].contains(url.scheme)) {
        throw const ImWorkflowFailure('分享图片地址异常');
      }
      _uploadedUrl = url.toString();
    }
    scope.ensureCurrent();
    request.ensureCurrent();
    return {'type': 'image', 'content': _uploadedUrl!};
  }
}

class _AppShareSheet extends StatefulWidget {
  const _AppShareSheet({required this.pageContext, required this.payload});
  final BuildContext pageContext;
  final _SharePayload payload;
  @override
  State<_AppShareSheet> createState() => _AppShareSheetState();
}

class _AppShareSheetState extends State<_AppShareSheet> {
  final _recent = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  bool _confirming = false;
  ModalRoute<dynamic>? _confirmationRoute;
  ApiSessionScope get _scope => widget.payload.scope;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    if (_scope.current) {
      _loadRecent();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sessionChanged());
    }
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted && !_scope.current) {
      final navigator = Navigator.of(context);
      if (_confirmationRoute?.isActive == true) {
        navigator.removeRoute(_confirmationRoute!);
      }
      navigator.removeRoute(ModalRoute.of(context)!);
    }
  }

  Future<void> _loadRecent() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final response = await _scope.get('/api/im/conversations');
      final items = imResponseList(imResponseData(response.data));
      if (!mounted || !_scope.current) return;
      setState(() {
        _recent.clear();
        _recent.addAll(
            items.where((item) => item['conversationId'] is num).take(10));
        _loading = false;
      });
    } catch (_) {
      if (mounted && _scope.current) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _send(Map<String, dynamic> target) async {
    if (_busy || !_scope.current) return;
    setState(() {
      _busy = true;
      _confirming = true;
    });
    final title = target['title']?.toString().trim();
    final name = title?.isNotEmpty == true ? title! : '该会话';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          _confirmationRoute = ModalRoute.of(context);
          return ValueListenableBuilder<int>(
            valueListenable: apiSessionChanges,
            builder: (context, _, __) => AlertDialog(
              title: Text(_scope.current ? '发送给$name' : '账号已切换'),
              content: Text(_scope.current
                  ? widget.payload.title
                  : apiSessionChangedMessage),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    key: const ValueKey('app-share-confirm-send'),
                    onPressed: !_scope.current
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('发送')),
              ],
            ),
          );
        },
      );
      _confirmationRoute = null;
      if (mounted) setState(() => _confirming = false);
      if (confirmed != true || !mounted || !_scope.current) return;
      final message = await widget.payload.message(_scope);
      _scope.ensureCurrent();
      final response = await _scope.post(
          '/api/im/conversation/${target['conversationId']}/message',
          data: message);
      imResponseData(response.data);
      if (!mounted || !_scope.current) return;
      Navigator.pop(context);
      if (widget.pageContext.mounted) {
        showAppToast(widget.pageContext, '已发送给$name');
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '分享失败，请重试'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  void _chooseFriends() {
    if (_busy || !_scope.current) return;
    final payload = widget.payload;
    Navigator.pop(context);
    showModalBottomSheet<bool>(
        context: widget.pageContext,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) =>
            SharePostToUsersPage.message(messageBuilder: payload.message));
  }

  Future<void> _external(String channel) async {
    if (_busy || !_scope.current) return;
    setState(() => _busy = true);
    try {
      final payload = widget.payload;
      final image = payload.imageBuilder == null ? null : await payload.file();
      _scope.ensureCurrent();
      if (!mounted) return;
      if ((channel == '微信' || channel == '朋友圈') &&
          AppConstants.wxAppId?.isNotEmpty == true) {
        final wx = Fluwx();
        if (!await wx.isWeChatInstalled) throw StateError('未安装微信');
        _scope.ensureCurrent();
        final scene =
            channel == '朋友圈' ? WeChatScene.timeline : WeChatScene.session;
        final success = await wx.share(image == null
            ? WeChatShareTextModel(payload.externalText, scene: scene)
            : WeChatShareImageModel(
                WeChatImageToShare(localImagePath: image.path),
                scene: scene));
        if (!success) throw StateError('分享未启动');
      } else if (image == null) {
        await Share.share(payload.externalText, subject: payload.title);
      } else {
        await Share.shareXFiles([image],
            text: payload.externalText, subject: payload.title);
      }
      if (mounted && _scope.current) Navigator.pop(context);
    } catch (error) {
      if (mounted && _scope.current) showAppToast(context, '未能打开分享，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _recipient(Map<String, dynamic>? target) {
    final group = target != null && target['type'] != 'single';
    final avatar = target?['avatarUrl']?.toString().trim() ?? '';
    final title = target?['title']?.toString().trim() ?? '';
    return SizedBox(
        width: 76,
        child: InkWell(
          key: target == null
              ? const ValueKey('app-share-more-friends')
              : ValueKey('app-share-recipient-${target['conversationId']}'),
          onTap: _busy
              ? null
              : () => target == null ? _chooseFriends() : _send(target),
          borderRadius: BorderRadius.circular(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFF5F5F6),
                foregroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
                onForegroundImageError: avatar.isEmpty ? null : (_, __) {},
                child: Icon(
                    target == null
                        ? Icons.person_add_alt_1_rounded
                        : group
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                    color: const Color(0xFF85898D))),
            const SizedBox(height: 6),
            Text(
                target == null
                    ? '更多好友'
                    : title.isEmpty
                        ? '该会话'
                        : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ));
  }

  Widget _channel(String label, ReferenceShareBrand? brand) => SizedBox(
      width: 60,
      child: InkWell(
        key: ValueKey('app-share-channel-$label'),
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _external(label),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              brand == null
                  ? const ReferenceShareMoreIcon()
                  : ReferenceShareBrandIcon(brand: brand),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF3F4248))),
            ])),
      ));

  @override
  Widget build(BuildContext context) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
            top: false,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(
                      color: AppColors.communityDivider,
                      borderRadius: BorderRadius.circular(2))),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('分享至好友',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              SizedBox(
                  height: 72 + MediaQuery.textScalerOf(context).scale(14),
                  child: _loading
                      ? const Center(
                          child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : _failed
                          ? Center(
                              child: TextButton(
                                  onPressed: _busy ? null : _loadRecent,
                                  child: const Text('好友加载失败，点击重试')))
                          : ListView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              children: [
                                  ..._recent.map(_recipient),
                                  _recipient(null),
                                ])),
              const Divider(height: 1, color: AppColors.communityDivider),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                                width: constraints.maxWidth < 360
                                    ? 360
                                    : constraints.maxWidth,
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _channel(
                                          '微信', ReferenceShareBrand.weChat),
                                      _channel(
                                          '朋友圈', ReferenceShareBrand.moments),
                                      _channel('QQ', ReferenceShareBrand.qq),
                                      _channel(
                                          'QQ空间', ReferenceShareBrand.qzone),
                                      _channel('微博', ReferenceShareBrand.weibo),
                                      _channel('更多', null),
                                    ])),
                          ))),
              if (_busy && !_confirming)
                const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 4),
            ]))),
      );
}
