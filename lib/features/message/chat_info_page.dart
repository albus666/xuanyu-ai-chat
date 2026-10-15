import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/constants/app_constants.dart';
import 'im_workflow_request.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../community/team_home_page.dart';
import '../community/user_profile_page.dart';
import 'add_group_members_page.dart';
import 'chat_appearance.dart';
import 'chat_apply_page.dart';
import 'group_members_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage({
    super.key,
    required this.conversationId,
    required this.title,
    this.onUpdated,
  });

  final int conversationId;
  final String title;
  final VoidCallback? onUpdated;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

const String _kRemarkPrefix = 'chat_remark_account_';

class _ChatInfoPageState extends State<ChatInfoPage> {
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _pendingInvites = [];
  Map<String, dynamic>? _team;
  bool _loading = true;
  String _remark = '';
  ChatAppearance _appearance = const ChatAppearance();
  bool _savingConversation = false;
  final _scope = ImWorkflowRequest();
  int _loadGeneration = 0;
  String? _error;
  String? _remarkKey;

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
      _team = null;
      _members.clear();
      _pendingInvites.clear();
      _remark = '';
      _remarkKey = null;
      _appearance = const ChatAppearance();
      _loading = false;
      _savingConversation = false;
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
      final results = await Future.wait([
        _scope.get('/api/im/conversation/${widget.conversationId}/info'),
        _scope.get('/api/im/conversation/${widget.conversationId}/members'),
        _scope.get('/api/im/team/conversation/${widget.conversationId}'),
      ]);
      final info = results[0];
      if (info['isMember'] != true) {
        throw const ImWorkflowFailure('群详情数据异常，请重试');
      }
      final members = imResponseList(results[1]);
      final pending = results[1]['pendingInvites'] == null
          ? <Map<String, dynamic>>[]
          : imResponseList(results[1], key: 'pendingInvites');
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !_scope.current || generation != _loadGeneration) return;
      final userId = prefs.getInt(AppConstants.keyUserId);
      if (userId == null) throw const ImWorkflowFailure('请重新登录后查看');
      final remarkKey = '$_kRemarkPrefix${userId}_${widget.conversationId}';
      final appearance = await loadChatAppearance(widget.conversationId);
      if (!mounted || !_scope.current || generation != _loadGeneration) return;
      setState(() {
        _info = info;
        _members = members;
        _pendingInvites = pending;
        _team = results[2]['teamId'] is num ? results[2] : null;
        _remarkKey = remarkKey;
        _remark = prefs.getString(remarkKey) ?? '';
        _appearance = appearance;
      });
    } catch (error) {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() {
          _info = null;
          _members.clear();
          _pendingInvites.clear();
          _team = null;
          _error = imFailureMessage(error, '群详情加载失败，请重试');
        });
      }
    } finally {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action,
      {bool manager = false, bool owner = false}) async {
    if (!_ready || _savingConversation) return;
    if ((manager && _info?['canManage'] != true) ||
        (owner && _info?['isOwner'] != true)) {
      showAppToast(context, '管理权限不足，请刷新后重试');
      return;
    }
    setState(() => _savingConversation = true);
    try {
      await action();
    } catch (error) {
      if (mounted && _scope.current) {
        if ({401, 403, 404}.contains(imFailureStatus(error))) {
          _loadGeneration++;
          setState(() {
            _info = null;
            _team = null;
            _members.clear();
            _pendingInvites.clear();
            _loading = false;
            _error = '权限或群状态已变化，请刷新';
          });
        }
        showAppToast(context, imFailureMessage(error, '操作失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) {
        setState(() => _savingConversation = false);
      }
    }
  }

  Future<String?> _editText(String title, String current, String hint,
      {int maxLength = 50, int maxLines = 1, String submit = '保存'}) async {
    var value = current;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
            initialValue: current,
            onChanged: (text) => value = text,
            decoration: InputDecoration(hintText: hint),
            maxLength: maxLength,
            maxLines: maxLines),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, value.trim()),
              child: Text(submit)),
        ],
      ),
    );
    return mounted && _scope.current ? result : null;
  }

  Future<void> _patchInfo(Map<String, dynamic> changes) async {
    if (!_ready) return;
    await _scope.patch('/api/im/conversation/${widget.conversationId}',
        data: changes);
    if (!mounted || !_scope.current) return;
    // 服务端部分旧接口可能忽略无权限字段；重新读取，不靠本地乐观值冒充保存成功。
    await _load();
    if (!mounted || !_scope.current) return;
    if (_info == null) {
      showAppToast(context, '已提交，请重试加载确认最新状态');
      return;
    }
    for (final entry in changes.entries) {
      if ((_info![entry.key] ?? '') != (entry.value ?? '')) {
        throw const ImWorkflowFailure('设置未生效，请刷新确认当前权限');
      }
    }
    widget.onUpdated?.call();
  }

  Future<void> _toggleMute(bool value) =>
      _runAction(() => _patchInfo({'mute': value}));
  Future<void> _togglePinned(bool value) =>
      _runAction(() => _patchInfo({'pinned': value}));
  Future<void> _toggleIsPublic(bool value) =>
      _runAction(() => _patchInfo({'isPublic': value}), owner: true);

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

  Future<void> _editName() => _runAction(() async {
        final current = _info?['name']?.toString() ?? widget.title;
        final result = await _editText(
            _team != null ? '部落名称' : '群聊名称', current, '请输入名称',
            maxLength: 32, submit: '确定');
        if (!mounted) return;
        if (result == null || result == current) return;
        if (result.isEmpty) {
          showAppToast(context, '名称不能为空');
          return;
        }
        await _patchInfo({'name': result});
      }, manager: true);

  Future<void> _editAnnouncement() => _runAction(() async {
        final result = await _editText(_team != null ? '部落公告' : '群公告',
            _info?['announcement']?.toString() ?? '', '请输入公告，选填',
            maxLength: 500, maxLines: 4);
        if (result != null) await _patchInfo({'announcement': result});
      }, manager: true);

  void _showGroupQr() {
    if (_info?['isPublic'] != true) {
      showAppToast(context, '当前未开放申请，群主开启“允许他人申请加入”后才能分享二维码');
      return;
    }
    final isTeam = _team != null;
    showDialog<void>(
      context: context,
      builder: (ctx) => ImWorkflowSessionBoundary(
        request: _scope,
        expiredBuilder: (_) => AlertDialog(
          title: const Text('账号已切换'),
          content: const Text(imSessionChangedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
        child: Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isTeam ? '部落二维码' : '群聊二维码',
                      style: AppTextStyles.titleMedium),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: QrImageView(
                      data: 'xuanyu://group/${widget.conversationId}',
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isTeam ? '扫码查看部落并申请加入' : '扫码查看群聊并申请加入',
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '需已安装玄遇 APP',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textHint),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editRemark() => _runAction(() async {
        final key = _remarkKey;
        if (key == null) return;
        final result = await _editText('备注', _remark, '仅自己可见的备注');
        if (result == null) return;
        final prefs = await SharedPreferences.getInstance();
        if (!mounted || !_scope.current) return;
        await prefs.setString(key, result);
        if (mounted && _scope.current) setState(() => _remark = result);
      });

  Future<void> _editTeamTitle() => _runAction(() async {
        if (_team?['isOwner'] != true) return;
        final teamId = (_team?['teamId'] as num?)?.toInt();
        if (teamId == null) return;
        final result = await _editText(
            '部落头衔', _team?['title']?.toString() ?? '', '10 字以内，留空则清除',
            maxLength: 10);
        if (result == null || !_ready) return;
        await _scope
            .patch('/api/im/team/$teamId/title', data: {'title': result});
        if (!mounted || !_scope.current) return;
        await _load();
        if (!mounted || !_scope.current) return;
        if (_team?['title'] == result) {
          showAppToast(context, '已保存');
          widget.onUpdated?.call();
        } else {
          showAppToast(context, '已提交，请重试加载确认最新状态');
        }
      }, owner: true);

  Future<void> _confirmLeaveGroup() => _endMembership(dissolve: false);
  Future<void> _confirmDissolveGroup() => _endMembership(dissolve: true);

  Future<void> _endMembership({required bool dissolve}) => _runAction(() async {
        final name = _info?['name']?.toString() ?? widget.title;
        final label = _team != null ? '部落' : '群聊';
        final action = dissolve ? '解散' : '退出';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$action$label'),
            content: Text(dissolve
                ? '确定解散「$name」？所有成员将被移出，且该操作无法撤销。'
                : '确定退出「$name」？退出后将不能继续接收消息。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(dissolve ? '解散$label' : '退出',
                      style: const TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (ok != true || !_ready) return;
        if (dissolve && _info?['isOwner'] != true) return;
        await _scope.post(
            '/api/im/conversation/${widget.conversationId}/${dissolve ? 'dissolve' : 'leave'}');
        if (!mounted || !_scope.current) return;
        showAppToast(context, dissolve ? '$label已解散' : '已退出$label');
        Navigator.of(context).pop(true);
      }, owner: dissolve);

  @override
  Widget build(BuildContext context) {
    final count = _info?['memberCount'] as int? ?? _members.length;
    final name = _info?['name'] as String? ?? widget.title;
    final mute = _info?['mute'] as bool? ?? false;
    final pinned = _info?['pinned'] as bool? ?? false;
    final isOwner = _info?['isOwner'] as bool? ?? false;
    final isPublic = _info?['isPublic'] as bool? ?? false;
    final announcement = _info?['announcement'] as String?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_team != null ? '部落管理' : '群聊信息($count)',
            style: AppTextStyles.titleMedium),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _info == null
              ? Center(
                  child: ImWorkflowRetry(
                      message: _error ?? '群详情加载失败，请重试',
                      onRetry: _scope.current ? _load : null))
              : AbsorbPointer(
                  absorbing: _savingConversation,
                  child: RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _buildSectionCard([
                              _buildMemberGrid(count),
                              const Divider(
                                  height: 1, indent: 16, endIndent: 16),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 4),
                                title: Center(
                                  child: Text(
                                      _team != null ? '查看全部部落成员' : '查看全部群成员',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                          color: AppColors.textSecondary)),
                                ),
                                onTap: () => Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (_) => GroupMembersPage(
                                          conversationId: widget.conversationId,
                                          title: name,
                                          isTribe: _team != null,
                                          onKicked: _load,
                                        ),
                                      ),
                                    )
                                    .then((_) => _load()),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            if (_team != null) ...[
                              _buildSectionCard([
                                _settingTile(
                                  '部落主页',
                                  _team!['name'] as String? ?? widget.title,
                                  Icons.shield_outlined,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TeamHomePage(
                                        conversationId: widget.conversationId,
                                        initialName:
                                            _team!['name'] as String? ??
                                                widget.title,
                                        initialTitle:
                                            _team!['title'] as String?,
                                        initialMemberCount:
                                            (_info?['memberCount'] as num?)
                                                ?.toInt(),
                                        initialMaxMembers:
                                            (_info?['maxMembers'] as num?)
                                                ?.toInt(),
                                      ),
                                    ),
                                  ),
                                ),
                                _settingTile(
                                  '部落头衔',
                                  (_team!['title'] as String?)?.isNotEmpty ==
                                          true
                                      ? _team!['title'] as String
                                      : '未设置',
                                  Icons.military_tech_outlined,
                                  onTap: (_team!['isOwner'] as bool? ?? false)
                                      ? _editTeamTitle
                                      : null,
                                ),
                              ]),
                              const SizedBox(height: 12),
                            ],
                            _buildSectionCard([
                              _settingTile(_team != null ? '部落名称' : '群聊名称',
                                  name, Icons.group_outlined,
                                  onTap: _editName),
                              _settingTile(_team != null ? '部落二维码' : '群二维码',
                                  null, Icons.qr_code_2_outlined,
                                  onTap: _showGroupQr),
                              _settingTile(
                                  _team != null ? '部落公告' : '群公告',
                                  (announcement != null &&
                                          announcement.isNotEmpty)
                                      ? announcement
                                      : '未设置',
                                  Icons.campaign_outlined,
                                  onTap: _editAnnouncement),
                              _settingTile(
                                  '备注',
                                  _remark.isNotEmpty ? _remark : '未设置',
                                  Icons.edit_note_outlined,
                                  onTap: _editRemark),
                              _settingTile(
                                  _team != null ? '举报部落' : '举报群聊', null, null,
                                  leading: const ReferenceActionGlyph(
                                    type: ReferenceActionIconType.report,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                  onTap: () => showReportSheet(context,
                                      targetType: 'group',
                                      targetId: widget.conversationId,
                                      title: _team != null ? '举报部落' : '举报群聊')),
                            ]),
                            if (_info?['canManage'] == true) ...[
                              const SizedBox(height: 12),
                              _buildSectionCard([
                                _settingTile(
                                  '申请与邀请',
                                  '查看待处理申请、我的申请与处理记录',
                                  Icons.how_to_reg_outlined,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const ChatApplyPage()),
                                  ),
                                ),
                              ]),
                            ],
                            const SizedBox(height: 12),
                            _buildSectionCard([
                              _settingTile('查找聊天记录', null, Icons.search_rounded,
                                  onTap: () async {
                                Navigator.of(this.context).pop('search');
                              }),
                            ]),
                            const SizedBox(height: 12),
                            _buildSectionCard([
                              _switchTile(
                                '置顶聊天',
                                null,
                                Icons.push_pin_outlined,
                                pinned,
                                _savingConversation ? null : _togglePinned,
                              ),
                              if (isOwner)
                                _switchTile(
                                  '允许他人申请加入',
                                  _team != null
                                      ? '开启后将在社区「推荐部落」展示，用户可申请加入部落与部落群'
                                      : '开启后群聊将出现在可加入群聊列表',
                                  Icons.group_add_outlined,
                                  isPublic,
                                  _toggleIsPublic,
                                ),
                              _switchTile(
                                '消息免打扰',
                                null,
                                Icons.notifications_off_outlined,
                                mute,
                                _savingConversation ? null : _toggleMute,
                              ),
                              _settingTile(
                                '聊天背景',
                                chatBackgroundChoices[_appearance.background],
                                Icons.wallpaper_rounded,
                                onTap: _chooseBackground,
                              ),
                              _settingTile(
                                '消息气泡',
                                chatBubbleChoices[_appearance.bubble],
                                Icons.chat_bubble_outline_rounded,
                                onTap: _chooseBubble,
                              ),
                            ]),
                            const SizedBox(height: 32),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: isOwner
                                      ? _confirmDissolveGroup
                                      : _confirmLeaveGroup,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: AppColors.error),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    foregroundColor: AppColors.error,
                                  ),
                                  child: Text(
                                      isOwner
                                          ? '解散${_team != null ? '部落' : '群聊'}'
                                          : '退出${_team != null ? '部落' : '群聊'}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 50),
                          ],
                        ),
                      ))),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Material(
      color: AppColors.surface,
      child: DecoratedBox(
          decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xFFECEEF1), width: .7))),
          child: Column(children: children)),
    );
  }

  Widget _buildMemberGrid(int total) {
    const crossCount = 5;
    final canManage = _info?['canManage'] as bool? ?? false;
    // 最多显示 14 个成员 + 1 个添加按钮
    final displayCount = canManage ? 14 : 15;
    final displayMembers = _members.take(displayCount).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: 20,
          crossAxisSpacing: 10,
          childAspectRatio: 0.75,
        ),
        itemCount: displayMembers.length + (canManage ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < displayMembers.length) {
            final m = displayMembers[index];
            return _memberAvatar(
              userId: (m['userId'] as num?)?.toInt(),
              nickname: m['nickname'] as String? ?? '用户',
              avatarUrl: m['avatarUrl'] as String?,
            );
          } else {
            return _buildAddButton();
          }
        },
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (_) => AddGroupMembersPage(
            conversationId: widget.conversationId,
            isTribe: _team != null,
            existingUserIds: _members
                .map((e) => (e['userId'] as num?)?.toInt())
                .whereType<int>()
                .toSet()
              ..addAll(_pendingInvites
                  .map((e) => (e['userId'] as num?)?.toInt())
                  .whereType<int>()),
          ),
        ),
      )
          .then((added) {
        if (added == true) _load();
      }),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.add_rounded,
                size: 30, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text('邀请', style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _memberAvatar(
      {int? userId, required String nickname, String? avatarUrl}) {
    return GestureDetector(
      onTap: () {
        if (userId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfilePage(userId: userId)),
          );
        }
      },
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              image: avatarUrl != null && avatarUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl), fit: BoxFit.cover)
                  : null,
              color: AppColors.primaryLight,
            ),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Center(
                    child: Text(nickname.isNotEmpty ? nickname[0] : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)))
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            nickname,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _settingTile(String title, String? value, IconData? icon,
      {Widget? leading, VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8)),
        child: leading ?? Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style:
              AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(value,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint),
                  overflow: TextOverflow.ellipsis),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _switchTile(String title, String? subtitle, IconData icon, bool value,
      ValueChanged<bool>? onChanged) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style:
              AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 10))
          : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
        activeThumbColor: AppColors.primary,
      ),
    );
  }
}
