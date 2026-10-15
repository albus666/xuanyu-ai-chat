import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import 'im_workflow_request.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import '../community/user_profile_page.dart';
import '../community/user_relationship_settings.dart';
import 'chat_appearance.dart';

class SingleChatSettingsPage extends StatefulWidget {
  const SingleChatSettingsPage({
    super.key,
    required this.conversationId,
    required this.peerUserId,
    required this.initialTitle,
  });

  final int conversationId;
  final int peerUserId;
  final String initialTitle;

  @override
  State<SingleChatSettingsPage> createState() => _SingleChatSettingsPageState();
}

class _SingleChatSettingsPageState extends State<SingleChatSettingsPage> {
  Map<String, dynamic>? _info;
  ChatAppearance _appearance = const ChatAppearance();
  bool _loading = true;
  bool _saving = false;
  final _scope = ImWorkflowRequest();
  int _loadGeneration = 0;
  String? _error;
  bool get _ready => mounted && _scope.current && !_loading && _info != null;

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    _loadGeneration++;
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _info = null;
      _appearance = const ChatAppearance();
      _loading = false;
      _saving = false;
      _error = imSessionChangedMessage;
    });
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _scope
          .get('/api/im/conversation/${widget.conversationId}/info');
      if (info['type'] != 'single') {
        throw const ImWorkflowFailure('聊天设置数据异常，请重试');
      }
      final appearance = await loadChatAppearance(widget.conversationId);
      if (!mounted || !_scope.current || generation != _loadGeneration) return;
      setState(() {
        _info = info;
        _appearance = appearance;
      });
    } catch (error) {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() {
          _info = null;
          _error = imFailureMessage(error, '聊天设置加载失败，请重试');
        });
      }
    } finally {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!_ready || _saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (error) {
      if (mounted && _scope.current) {
        if (imFailureStatus(error) == 404 ||
            (imFailureStatus(error) == null && error is! ImWorkflowFailure)) {
          _loadGeneration++;
          setState(() {
            _info = null;
            _loading = false;
            _error = '操作结果待确认，请重新加载';
          });
        }
        showAppToast(context, imFailureMessage(error, '操作失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm(String title, String content, String action) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(action)),
              ],
            ));
    return confirmed == true && _ready;
  }

  Future<void> _setConversationFlag(String key, bool value) =>
      _runAction(() async {
        await _scope.patch('/api/im/conversation/${widget.conversationId}',
            data: {key: value});
        if (!mounted || !_scope.current) return;
        _loadGeneration++;
        setState(() => _info = {...?_info, key: value});
      });

  Future<void> _openRemark() => _runAction(() async {
        final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
                builder: (_) => UserRemarkPage(
                    userId: widget.peerUserId, initialData: _info!)));
        if (!mounted || !_scope.current || result == null) return;
        await _load();
        if (mounted && _scope.current && _info != null) {
          showAppToast(context, '备注和描述已保存');
        }
      });

  Future<void> _openSpecialCare() => _runAction(() async {
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => SpecialCareSettingsPage(
                userId: widget.peerUserId, initialData: _info!)));
        if (mounted && _scope.current) await _load();
      });

  Future<void> _openStealth() => _runAction(() async {
        final result = await showUserStealthSettingsSheet(context,
            userId: widget.peerUserId, initialData: _info!);
        if (mounted && _scope.current && result != null) await _load();
      });

  Future<void> _chooseAppearance(ChatAppearancePickerType type) =>
      _runAction(() async {
        final background = type == ChatAppearancePickerType.background;
        final selected = await showChatAppearancePicker(context,
            title: background ? '聊天背景' : '消息气泡',
            current: background ? _appearance.background : _appearance.bubble,
            type: type);
        if (selected == null || !mounted || !_scope.current) return;
        if (background) {
          await saveChatBackground(widget.conversationId, selected);
        } else {
          await saveChatBubble(widget.conversationId, selected);
        }
        if (!mounted || !_scope.current) return;
        setState(() => _appearance = ChatAppearance(
            background: background ? selected : _appearance.background,
            bubble: background ? _appearance.bubble : selected));
      });
  Future<void> _chooseBackground() =>
      _chooseAppearance(ChatAppearancePickerType.background);
  Future<void> _chooseBubble() =>
      _chooseAppearance(ChatAppearancePickerType.bubble);

  Future<void> _toggleFollow() => _runAction(() async {
        if (_info?['following'] == true &&
            !await _confirm('取消关注', '取消后将不再是互关好友，语音和视频通话会同时关闭。', '取消关注')) {
          return;
        }
        if (!_ready) return;
        final data = await _scope
            .post('/api/community/user/${widget.peerUserId}/follow');
        if (!mounted || !_scope.current) return;
        if (data['following'] is! bool || data['mutual'] is! bool) {
          await _load();
          throw const ImWorkflowFailure('关注结果待确认，请查看最新状态');
        }
        _loadGeneration++;
        setState(() => _info = {
              ...?_info,
              'following': data['following'],
              'mutualFollow': data['mutual']
            });
      });

  Future<void> _toggleBlock() => _runAction(() async {
        final blocked = _info?['blocked'] == true;
        if (!await _confirm(
            blocked ? '解除拉黑' : '拉黑用户',
            blocked ? '解除后可以重新关注和聊天。' : '拉黑后双方无法私聊，并会解除互相关注。',
            blocked ? '解除' : '拉黑')) {
          return;
        }
        await _scope.post(
            '/api/community/user/${widget.peerUserId}/${blocked ? 'unblock' : 'block'}');
        if (!mounted || !_scope.current) return;
        _loadGeneration++;
        setState(() => _info = {
              ...?_info,
              'blocked': !blocked,
              if (!blocked) 'following': false,
              if (!blocked) 'mutualFollow': false
            });
      });

  Future<void> _deleteConversation() => _runAction(() async {
        if (!await _confirm('删除会话', '会话将从消息列表移除，新消息到达后仍可重新出现。', '删除')) return;
        await _scope
            .post('/api/im/conversation/${widget.conversationId}/delete');
        if (mounted && _scope.current) Navigator.of(context).pop('deleted');
      });

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final nickname = info?['displayName']?.toString() ?? widget.initialTitle;
    final avatar = info?['avatarUrl']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8F9),
        surfaceTintColor: Colors.transparent,
        title: const Text('聊天设置'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : info == null
              ? Center(
                  child: ImWorkflowRetry(
                      message: _error ?? '聊天设置加载失败，请重试',
                      onRetry: _scope.current ? _load : null))
              : AbsorbPointer(
                  absorbing: _saving,
                  child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 42),
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    UserProfilePage(userId: widget.peerUserId),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: AppColors.primaryLight,
                                    backgroundImage: avatar.isNotEmpty
                                        ? NetworkImage(avatar)
                                        : null,
                                    child: avatar.isEmpty
                                        ? Text(nickname.isEmpty
                                            ? '?'
                                            : nickname[0])
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(nickname,
                                            style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 5),
                                        Text(
                                            info['mutualFollow'] == true
                                                ? '互关好友 · 可语音和视频通话'
                                                : '查看对方主页',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _card([
                            _tile(Icons.search_rounded, '查找聊天内容',
                                onTap: () async {
                              Navigator.of(this.context).pop('search');
                            }),
                            _tile(Icons.edit_note_rounded, '设置备注、描述和图片',
                                value: info['remark']?.toString(),
                                onTap: _openRemark),
                          ]),
                          const SizedBox(height: 12),
                          _card([
                            _switch(
                                Icons.push_pin_outlined,
                                '置顶聊天',
                                info['pinned'] == true,
                                (value) =>
                                    _setConversationFlag('pinned', value)),
                            _switch(
                                Icons.notifications_off_outlined,
                                '消息免打扰',
                                info['mute'] == true,
                                (value) => _setConversationFlag('mute', value)),
                            _tile(Icons.favorite_outline_rounded, '特别关心及专属提示音',
                                value:
                                    info['specialCare'] == true ? '已开启' : '未开启',
                                onTap: _openSpecialCare),
                            _tile(Icons.wallpaper_rounded, '聊天背景',
                                value: chatBackgroundChoices[
                                    _appearance.background],
                                onTap: _chooseBackground),
                            _tile(Icons.chat_bubble_outline_rounded, '消息气泡',
                                value: chatBubbleChoices[_appearance.bubble],
                                onTap: _chooseBubble),
                            _tile(Icons.visibility_off_outlined, '对 Ta 隐身访问设置',
                                onTap: _openStealth),
                          ]),
                          const SizedBox(height: 12),
                          _card([
                            _tile(Icons.person_add_alt_1_rounded,
                                info['following'] == true ? '取消关注' : '关注',
                                onTap: _toggleFollow),
                            _tile(Icons.block_rounded,
                                info['blocked'] == true ? '解除拉黑' : '拉黑用户',
                                danger: info['blocked'] != true,
                                onTap: _toggleBlock),
                            _tile(Icons.report_outlined, '举报用户',
                                onTap: () => showReportSheet(context,
                                    targetType: 'user',
                                    targetId: widget.peerUserId,
                                    title: '举报用户')),
                          ]),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: _deleteConversation,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side:
                                    const BorderSide(color: Color(0x33FF0000)),
                                backgroundColor: Colors.white,
                              ),
                              child: const Text('删除会话'),
                            ),
                          ),
                        ],
                      ))),
    );
  }

  Widget _card(List<Widget> children) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _tile(IconData icon, String title,
      {String? value, VoidCallback? onTap, bool danger = false}) {
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.red : const Color(0xFF4B555B)),
      title: Text(title,
          style:
              TextStyle(color: danger ? Colors.red : const Color(0xFF25272B))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value?.isNotEmpty == true)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(value!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _switch(
      IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon, color: const Color(0xFF4B555B)),
      title: Text(title),
      value: value,
      activeTrackColor: AppColors.primary,
      onChanged: _saving ? null : onChanged,
    );
  }
}
