import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import 'im_workflow_request.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../shared/widgets/app_text_field.dart';
import '../community/user_profile_page.dart';

/// 创建线上技能部落；普通交流继续使用群聊。
class CreateTeamPage extends StatefulWidget {
  const CreateTeamPage({super.key});

  @override
  State<CreateTeamPage> createState() => _CreateTeamPageState();
}

class _CreateTeamPageState extends State<CreateTeamPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _skills = TextEditingController();
  final _canHelp = TextEditingController();
  final _cannotHelp = TextEditingController();
  final _charter = TextEditingController();
  final _questions = TextEditingController();
  final _following = <Map<String, dynamic>>[];
  final _selectedIds = <int>{};
  final _onlineModes = <String>{'文字答疑'};
  String _recruitmentMode = 'application';
  bool _loading = true;
  bool _submitting = false;
  final _scope = ImWorkflowRequest();
  String? _error;
  bool _uncertain = false;
  int _loadGeneration = 0;

  void _sessionChanged() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _following.clear();
      _selectedIds.clear();
      _loading = false;
      _submitting = false;
      _error = imSessionChangedMessage;
    });
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    for (final controller in [
      _name,
      _description,
      _skills,
      _canHelp,
      _cannotHelp,
      _charter,
      _questions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_scope.current) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = imResponseList(
          await _scope.get('/api/community/user/me/following-list'));
      final unique = <int, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = (row['userId'] as num?)?.toInt();
        if (id != null) unique[id] = row;
      }
      if (!mounted || !_scope.current || generation != _loadGeneration) return;
      setState(() {
        _following
          ..clear()
          ..addAll(unique.values);
        _selectedIds.removeWhere((id) => !unique.containsKey(id));
      });
    } catch (error) {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _error = imFailureMessage(error, '可邀请成员加载失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> _split(TextEditingController controller, {int limit = 6}) =>
      controller.text
          .split(RegExp(r'[,，、\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(limit)
          .toList();

  String? _validate() {
    if (_name.text.trim().isEmpty) return '请输入部落名称';
    if (_description.text.trim().isEmpty) return '请填写部落介绍';
    if (_split(_skills, limit: 5).isEmpty) return '请填写至少一个真实技能标签';
    if (_canHelp.text.trim().isEmpty) return '请说明能帮助大家解决什么';
    if (_cannotHelp.text.trim().isEmpty) return '请说明不提供哪些帮助';
    if (_charter.text.trim().isEmpty) return '请填写部落公约';
    if (_onlineModes.isEmpty) return '请至少选择一种线上答疑方式';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_scope.current || _uncertain) return;
    final error = _validate();
    if (error != null) {
      showAppToast(context, error);
      return;
    }
    final name = _name.text.trim();
    setState(() => _submitting = true);
    try {
      final data = await _scope.post(
        '/api/im/team/create',
        data: {
          'name': name,
          'description': _description.text.trim(),
          'skillTags': _split(_skills, limit: 5),
          'canHelp': _canHelp.text.trim(),
          'cannotHelp': _cannotHelp.text.trim(),
          'charter': _charter.text.trim(),
          'onlineModes': _onlineModes.toList(),
          'recruitmentMode': _recruitmentMode,
          'applicationQuestions': _split(_questions),
          'memberIds': _selectedIds.toList(),
        },
      );
      if (!mounted || !_scope.current) return;
      final conversationId = (data['conversationId'] as num?)?.toInt();
      if (conversationId == null || conversationId <= 0) {
        _uncertain = true;
        throw const ImWorkflowFailure('创建结果待确认，请返回群聊与部落查看，避免重复创建');
      }
      final invited = (data['invited'] as num?)?.toInt() ?? 0;
      final skipped = <Object?>{
        ...?data['blockedUserIds'] as List?,
        ...?data['busyUserIds'] as List?,
        ...?data['invalidUserIds'] as List?,
      }.length;
      showAppToast(
          context,
          data['invitationUnavailable'] == true
              ? '部落已创建，邀请暂未发出，请稍后在部落管理中重试'
              : skipped > 0
                  ? '部落已创建，已发送$invited个邀请，$skipped人暂不可邀请'
                  : invited > 0
                      ? '部落已创建，已发送$invited个成员邀请'
                      : '部落创建成功');
      Navigator.of(context).pop({
        'conversationId': conversationId,
        'title': data['title']?.toString() ?? name,
      });
    } catch (error) {
      if (mounted && _scope.current) {
        if (error is! ImWorkflowFailure && imFailureStatus(error) == null) {
          _uncertain = true;
        }
        showAppToast(
            context,
            _uncertain
                ? '创建结果待确认，请返回群聊与部落查看，避免重复创建'
                : imFailureMessage(error, '提交失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建部落'),
        actions: [
          TextButton(
            onPressed:
                _submitting || !_scope.current || _uncertain ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('创建'),
          ),
        ],
      ),
      body: !_scope.current
          ? const Center(child: Text(imSessionChangedMessage))
          : AbsorbPointer(
              absorbing: _submitting,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    ImWorkflowRetry(message: _error!, onRetry: _load),
                  if (_uncertain)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('创建结果待确认，请返回群聊与部落查看，避免重复创建')),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '部落是带公开技能身份的线上协作组织，不是普通群聊。技能不设固定分类，但必须真实、合法，并写清能力边界。创建后会同时生成内部群聊。',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    controller: _name,
                    label: '部落名称',
                    hint: '清楚表达部落擅长什么',
                    maxLength: 32,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _description,
                    label: '部落介绍',
                    hint: '介绍成员背景、线上答疑方向与服务方式',
                    maxLines: 3,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _skills,
                    label: '技能标签（1—5个）',
                    hint: '技能不限类别，用逗号分隔，例如：宠物寻回、资料检索',
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _canHelp,
                    label: '能帮助什么',
                    hint: '把可以解决的问题说具体',
                    maxLines: 3,
                    maxLength: 1000,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _cannotHelp,
                    label: '不提供什么',
                    hint: '明确能力边界，不承诺结果、不替代专业意见等',
                    maxLines: 3,
                    maxLength: 1000,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _charter,
                    label: '部落公约',
                    hint: '答疑规范、成员协作、违规处理、退出规则',
                    maxLines: 4,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: 18),
                  Text('线上答疑方式', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['文字答疑', '语音答疑', '视频答疑', '线上直播']
                        .map(
                          (mode) => FilterChip(
                            label: Text(mode),
                            selected: _onlineModes.contains(mode),
                            onSelected: (selected) => setState(
                              () => selected
                                  ? _onlineModes.add(mode)
                                  : _onlineModes.remove(mode),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _recruitmentMode,
                    decoration: const InputDecoration(labelText: '成员加入方式'),
                    items: const [
                      DropdownMenuItem(
                          value: 'application', child: Text('申请加入')),
                      DropdownMenuItem(value: 'invite', child: Text('仅邀请加入')),
                      DropdownMenuItem(value: 'closed', child: Text('暂停招募')),
                    ],
                    onChanged: (value) => setState(
                        () => _recruitmentMode = value ?? 'application'),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _questions,
                    label: '入部落问题（选填）',
                    hint: '每行一个问题，用于成员申请',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 14),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('意向初始成员（选填）', style: AppTextStyles.titleSmall),
                    subtitle: const Text('创建后发送邀请，不会直接把对方加入'),
                    children: _following.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('暂无已关注用户'),
                            ),
                          ]
                        : _following.map((user) {
                            final userId = (user['userId'] as num?)?.toInt();
                            if (userId == null) return const SizedBox.shrink();
                            final nickname =
                                user['nickname']?.toString() ?? '用户';
                            final avatar = user['avatarUrl']?.toString() ?? '';
                            return CheckboxListTile(
                              value: _selectedIds.contains(userId),
                              onChanged: (selected) => setState(
                                () => selected == true
                                    ? _selectedIds.add(userId)
                                    : _selectedIds.remove(userId),
                              ),
                              secondary: GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        UserProfilePage(userId: userId),
                                  ),
                                ),
                                child: CircleAvatar(
                                  backgroundImage: avatar.isNotEmpty
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty
                                      ? Text(
                                          nickname.isEmpty ? '?' : nickname[0])
                                      : null,
                                ),
                              ),
                              title: Text(nickname),
                            );
                          }).toList(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting || !_scope.current || _uncertain
                        ? null
                        : _submit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13),
                      child: Text('立即创建部落'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '部落只开展线上交流与服务，不提供线下活动入口。付费服务必须使用平台现有的咨询、私人专线或订单能力。',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textHint,
                      height: 1.5,
                    ),
                  ),
                ],
              )),
    );
  }
}
