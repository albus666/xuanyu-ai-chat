import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/report_utils.dart';
import '../../core/widgets/app_share_more_button.dart';
import '../message/chat_page.dart';
import '../message/chat_info_page.dart';
import '../message/group_members_page.dart';
import '../message/im_workflow_request.dart';
import 'post_card.dart';

class TeamHomePage extends StatefulWidget {
  const TeamHomePage({
    super.key,
    required this.conversationId,
    required this.initialName,
    this.initialTitle,
    this.initialMemberCount,
    this.initialMaxMembers,
  });

  final int conversationId;
  final String initialName;
  final String? initialTitle;
  final int? initialMemberCount;
  final int? initialMaxMembers;

  @override
  State<TeamHomePage> createState() => _TeamHomePageState();
}

class _TeamHomePageState extends State<TeamHomePage> {
  final _scope = ImWorkflowRequest();
  int _generation = 0;
  int _resourceGeneration = 0;
  int _postGeneration = 0;
  String? _loadError;
  String? _postError;
  String? _caseError;
  String? _memberError;
  bool _following = false;
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _team;
  final _posts = <Map<String, dynamic>>[];
  final _members = <Map<String, dynamic>>[];
  final _cases = <Map<String, dynamic>>[];
  final _resources = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingPosts = false;
  bool _loadingResources = false;
  bool _savingResource = false;
  bool _submittingResource = false;
  bool _showAllResources = false;
  bool _applying = false;
  String? _resourceError;
  String _resourceQuery = '';

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
    _load();
  }

  bool get _active => mounted && _scope.current;
  bool get _ready =>
      _active && !_loading && _loadError == null && _team != null;
  bool get _canManage =>
      _ready &&
      (_info != null
          ? _info!['canManage'] == true
          : _team?['canManage'] == true);

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _clearData() {
    _info = null;
    _team = null;
    _posts.clear();
    _members.clear();
    _cases.clear();
    _resources.clear();
  }

  void _invalidate(String message) {
    _generation++;
    _resourceGeneration++;
    _postGeneration++;
    _clearData();
    _loading = false;
    _loadingPosts = false;
    _loadingResources = false;
    _loadError = message;
  }

  void _sessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() => _invalidate(imSessionChangedMessage));
  }

  void _operationFailed(Object error, String fallback,
      {bool requireReloadOnUncertain = false}) {
    if (!_active) return;
    final message = imFailureMessage(error, fallback);
    final status = imFailureStatus(error);
    if ({401, 403, 404}.contains(status) ||
        (requireReloadOnUncertain && status == null)) {
      setState(() => _invalidate(message));
    }
    showAppToast(context, message);
  }

  Widget _sessionDialog(BuildContext dialogContext, Widget child) =>
      ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (_, value, __) => _scope.current
            ? child
            : AlertDialog(
                title: const Text('账号已切换'),
                content: const Text(imSessionChangedMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  )
                ],
              ),
      );

  Future<void> _load() async {
    if (!_active || _applying || _following || _savingResource) return;
    final generation = ++_generation;
    _resourceGeneration++;
    _postGeneration++;
    setState(() {
      _loading = true;
      _loadError = null;
      _clearData();
    });
    try {
      final team = await _scope.get(
        '/api/im/team/conversation/${widget.conversationId}',
      );
      final teamId = (team['teamId'] as num?)?.toInt();
      if (teamId == null || teamId <= 0) {
        throw const ImWorkflowFailure('部落不存在或暂时无法加载，请重试');
      }
      // 非成员也可查看基础主页，不能调用只允许成员访问的群详情接口。
      Map<String, dynamic>? info;
      if (team['isMember'] == true) {
        info = await _scope
            .get('/api/im/conversation/${widget.conversationId}/info');
        if (info['isMember'] != true) {
          throw const ImWorkflowFailure('成员身份已变化，请重试加载');
        }
      }
      if (!_active || generation != _generation) return;
      setState(() {
        _info = info;
        _team = team;
        _caseError = null;
        _memberError = null;
        _loadingResources = false;
        _loadingPosts = false;
        _loading = false;
      });
      await Future.wait([
        _loadCases(teamId, generation),
        if (team['isMember'] == true) _loadMembers(generation),
        _reloadResources(),
        _refreshPostsOnly(),
      ]);
    } catch (error) {
      if (!_active || generation != _generation) return;
      setState(() => _invalidate(imFailureMessage(error, '部落主页加载失败，请重试')));
    }
  }

  Future<void> _loadCases(int teamId, int generation) async {
    try {
      final cases =
          imResponseList(await _scope.get('/api/im/team/$teamId/cases'));
      if (!_active || generation != _generation) return;
      setState(() => _cases.addAll(cases));
    } catch (error) {
      if (!_active || generation != _generation) return;
      setState(() => _caseError = imFailureMessage(error, '案例加载失败'));
    }
  }

  Future<void> _loadMembers(int generation) async {
    try {
      final members = imResponseList(await _scope
          .get('/api/im/conversation/${widget.conversationId}/members'));
      if (!_active || generation != _generation) return;
      setState(() => _members.addAll(members));
    } catch (error) {
      if (!_active || generation != _generation) return;
      setState(() => _memberError = imFailureMessage(error, '成员加载失败'));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllResources(int teamId) async {
    final result = <Map<String, dynamic>>[];
    final seen = <int>{};
    var page = 1;
    while (true) {
      final data = await _scope.get(
        '/api/im/team/$teamId/resources',
        query: {'page': page, 'page_size': 50},
      );
      final list = imResponseList(data);
      var added = 0;
      for (final item in list) {
        final id = (item['id'] as num?)?.toInt();
        if (id == null || id <= 0) throw const ImWorkflowFailure('资料数据异常，请重试');
        if (seen.add(id)) {
          result.add(item);
          added++;
        }
      }
      if (data['hasMore'] != true) break;
      if (added == 0) throw const ImWorkflowFailure('资料分页异常，请重试');
      page += 1;
    }
    return result;
  }

  Future<void> _reloadResources() async {
    final teamId = (_team?['teamId'] as num?)?.toInt();
    if (!_ready || teamId == null || _loadingResources) return;
    final generation = ++_resourceGeneration;
    setState(() {
      _loadingResources = true;
      _resourceError = null;
    });
    try {
      final resources = await _fetchAllResources(teamId);
      if (!_active || generation != _resourceGeneration) return;
      setState(() {
        _resources
          ..clear()
          ..addAll(resources);
      });
    } catch (error) {
      if (_active && generation == _resourceGeneration) {
        setState(() {
          _resources.clear();
          _resourceError = imFailureMessage(error, '资料库加载失败');
        });
      }
    } finally {
      if (_active && generation == _resourceGeneration) {
        setState(() => _loadingResources = false);
      }
    }
  }

  Future<void> _refreshPostsOnly() async {
    if (!_ready || _loadingPosts) return;
    final generation = ++_postGeneration;
    setState(() {
      _loadingPosts = true;
      _postError = null;
    });
    try {
      final data = await _scope.get(
        '/api/community/team/conversation/${widget.conversationId}/posts',
        query: {'page': 1, 'page_size': 20},
      );
      final posts = imResponseList(data);
      if (_active && generation == _postGeneration) {
        setState(() {
          _posts
            ..clear()
            ..addAll(posts);
        });
      }
    } catch (error) {
      if (_active && generation == _postGeneration) {
        setState(() {
          _posts.clear();
          _postError = imFailureMessage(error, '求助加载失败');
        });
      }
    } finally {
      if (_active && generation == _postGeneration) {
        setState(() => _loadingPosts = false);
      }
    }
  }

  Future<void> _applyJoin() async {
    if (!_ready ||
        _applying ||
        _team?['isMember'] == true ||
        _team?['isPublic'] != true) {
      return;
    }
    setState(() => _applying = true);
    var note = '';
    final questions = (_team?['applicationQuestions'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _sessionDialog(
            ctx,
            AlertDialog(
              title: const Text('申请加入部落'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (questions.isNotEmpty) ...[
                    const Text('请在下方按顺序回答：',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...questions.asMap().entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${entry.key + 1}. ${entry.value}',
                              style: const TextStyle(fontSize: 13)),
                        )),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    onChanged: (value) => note = value,
                    maxLength: 200,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          questions.isEmpty ? '简单介绍自己或填写加入理由（选填）' : '填写你的回答',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('提交申请'),
                ),
              ],
            )),
      );
      if (confirmed != true || !_ready) return;
      await _scope.post(
        '/api/im/group/${widget.conversationId}/apply',
        data: {'note': note.trim()},
      );
      if (mounted && _scope.current) {
        showAppToast(context, '已提交申请');
        setState(() => _team = {...?_team, 'applyStatus': 'pending'});
      }
    } catch (error) {
      _operationFailed(error, '申请结果待确认，请刷新后查看', requireReloadOnUncertain: true);
    } finally {
      if (_active) setState(() => _applying = false);
    }
  }

  Future<void> _withdrawJoin() async {
    if (!_ready || _applying || _team?['applyStatus'] != 'pending') return;
    setState(() => _applying = true);
    try {
      await _scope.post(
        '/api/im/group/${widget.conversationId}/apply/withdraw',
      );
      if (mounted && _scope.current) {
        showAppToast(context, '申请已撤回');
        setState(() => _team = {...?_team, 'applyStatus': 'withdrawn'});
      }
    } catch (error) {
      _operationFailed(error, '撤回结果待确认，请刷新后查看', requireReloadOnUncertain: true);
    } finally {
      if (_active) setState(() => _applying = false);
    }
  }

  Future<void> _toggleFollow() async {
    final teamId = (_team?['teamId'] as num?)?.toInt();
    if (!_ready || teamId == null || _following) return;
    setState(() => _following = true);
    try {
      final data = await _scope.post('/api/im/team/$teamId/follow');
      final following = data['following'];
      if (following is! bool) throw const ImWorkflowFailure('关注结果待确认，请刷新后查看');
      if (_active) {
        setState(() => _team = {...?_team, 'following': following});
      }
    } catch (error) {
      _operationFailed(error, '关注结果待确认，请刷新后查看', requireReloadOnUncertain: true);
    } finally {
      if (_active) setState(() => _following = false);
    }
  }

  Future<_ResourceAttachment?> _pickAndUploadResourceFile() async {
    if (!_canManage) {
      throw const _ResourceEditorException(imSessionChangedMessage);
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'txt',
        'csv',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
      ],
      withData: false,
    );
    if (!_canManage) {
      throw const _ResourceEditorException(imSessionChangedMessage);
    }
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > 30 * 1024 * 1024) {
      throw const _ResourceEditorException('附件不能超过30MB');
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const _ResourceEditorException('暂时无法读取这个文件，请重新选择');
    }
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: file.name),
    });
    try {
      if (!_canManage) {
        throw const _ResourceEditorException(imSessionChangedMessage);
      }
      final data = await _scope.post('/api/config/upload', data: formData);
      if (!_canManage) {
        throw const _ResourceEditorException(imSessionChangedMessage);
      }
      final url = data['url']?.toString().trim() ?? '';
      if (url.isEmpty) throw const _ResourceEditorException('附件上传失败');
      final extension = (file.extension ?? '').toLowerCase();
      final type =
          const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension)
              ? 'image'
              : 'file';
      return _ResourceAttachment(name: file.name, url: url, type: type);
    } catch (error) {
      throw _ResourceEditorException(imFailureMessage(error, '附件上传失败'));
    }
  }

  Future<void> _createResource() => _editResource();

  Future<void> _editResource([Map<String, dynamic>? existing]) async {
    final teamId = (_team?['teamId'] as num?)?.toInt();
    if (!_canManage || teamId == null || _savingResource) return;
    setState(() => _savingResource = true);
    try {
      final draft = await showDialog<_ResourceDraft>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _sessionDialog(
            ctx,
            _ResourceEditorDialog(
              existing: existing,
              onPickAttachment: _pickAndUploadResourceFile,
            )),
      );
      if (draft == null || !_canManage) return;
      setState(() => _submittingResource = true);
      final resourceId = (existing?['id'] as num?)?.toInt();
      final data = {
        'title': draft.title,
        'content': draft.content,
        'type': draft.type,
        'url': draft.url,
        'visibility': draft.visibility,
      };
      if (resourceId == null) {
        await _scope.post('/api/im/team/$teamId/resources', data: data);
      } else {
        await _scope.patch(
          '/api/im/team/$teamId/resource/$resourceId',
          data: data,
        );
      }
      if (mounted && _scope.current) {
        showAppToast(context, resourceId == null ? '资料已发布' : '资料已更新');
        _resourceGeneration++;
        _loadingResources = false;
        await _reloadResources();
      }
    } catch (error) {
      _operationFailed(error, '保存结果待确认，请刷新资料库后查看',
          requireReloadOnUncertain: true);
    } finally {
      if (_active) {
        setState(() {
          _savingResource = false;
          _submittingResource = false;
        });
      }
    }
  }

  Future<void> _deleteResource(Map<String, dynamic> item) async {
    final teamId = (_team?['teamId'] as num?)?.toInt();
    final resourceId = (item['id'] as num?)?.toInt();
    if (!_canManage ||
        teamId == null ||
        resourceId == null ||
        _savingResource) {
      return;
    }
    setState(() => _savingResource = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _sessionDialog(
            dialogContext,
            AlertDialog(
              title: const Text('删除资料'),
              content: Text('确定删除「${item['title'] ?? '这条资料'}」吗？删除后用户将无法查看。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('删除'),
                ),
              ],
            )),
      );
      if (confirmed != true || !_canManage) return;
      setState(() => _submittingResource = true);
      await _scope.delete('/api/im/team/$teamId/resource/$resourceId');
      if (!mounted || !_scope.current) return;
      _resourceGeneration++;
      _loadingResources = false;
      setState(() => _resources.removeWhere(
            (resource) => (resource['id'] as num?)?.toInt() == resourceId,
          ));
      showAppToast(context, '资料已删除');
    } catch (error) {
      _operationFailed(error, '删除失败');
    } finally {
      if (_active) {
        setState(() {
          _savingResource = false;
          _submittingResource = false;
        });
      }
    }
  }

  Future<void> _openResourceAttachment(String rawUrl) async {
    if (!_ready) return;
    final uri = Uri.tryParse(rawUrl.trim());
    try {
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted && _scope.current) showAppToast(context, '暂时无法打开附件');
      }
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '暂时无法打开附件');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_team?['name'] ??
            _info?['name'] ??
            (_scope.current ? widget.initialName : '部落'))
        .toString()
        .trim();
    final title =
        (_team?['title'] ?? widget.initialTitle ?? '').toString().trim();
    final announcement =
        (_info?['announcement'] ?? _team?['announcement'] ?? '')
            .toString()
            .trim();
    final memberCount = (_info?['memberCount'] as num?)?.toInt() ??
        (_team?['memberCount'] as num?)?.toInt() ??
        widget.initialMemberCount ??
        0;
    final maxMembers = (_info?['maxMembers'] as num?)?.toInt() ??
        (_team?['maxMembers'] as num?)?.toInt() ??
        widget.initialMaxMembers ??
        500;
    final isMember = _info?['isMember'] == true || _team?['isMember'] == true;
    final isPublic = _team?['isPublic'] == true;
    final canManage = _canManage;
    final applyPending = _team?['applyStatus'] == 'pending';
    final description = _team?['description']?.toString().trim() ?? '';
    final canHelp = _team?['canHelp']?.toString().trim() ?? '';
    final cannotHelp = _team?['cannotHelp']?.toString().trim() ?? '';
    final charter = _team?['charter']?.toString().trim() ?? '';
    final skills =
        (_team?['skillTags'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final onlineModes =
        (_team?['onlineModes'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final membershipStatus = _team?['membershipStatus']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.communityScaffold,
      appBar: AppBar(
        title: Text('部落主页', style: AppTextStyles.titleMedium),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.communityScaffold,
        actions: [
          if (_ready)
            AppShareMoreButton(
              title: name,
              shareText: '我在玄遇发现了「$name」部落，来看看这里的专业答疑与公开案例。',
            ),
          IconButton(
            tooltip: _team?['following'] == true ? '取消关注' : '关注部落',
            onPressed: _ready && !_following ? _toggleFollow : null,
            icon: Icon(
              _team?['following'] == true
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
            ),
          ),
          IconButton(
            tooltip: '举报部落',
            onPressed: (_team?['teamId'] as num?)?.toInt() == null
                ? null
                : () => showReportSheet(
                      context,
                      targetType: 'team',
                      targetId: (_team!['teamId'] as num).toInt(),
                      title: '举报部落',
                    ),
            icon: const Icon(Icons.report_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null
              ? Center(
                  child: ImWorkflowRetry(
                      message: _loadError!,
                      onRetry: _scope.current ? _load : null))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _buildHero(name, title, memberCount, maxMembers),
                      if (membershipStatus == 'probation') ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF6DF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.workspace_premium_outlined,
                                size: 17,
                                color: Color(0xFFAA7620),
                              ),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '你目前是实习成员，社区答疑仍会显示部落标识。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF815A18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _buildActionRow(
                          name, isMember, isPublic, canManage, applyPending),
                      const SizedBox(height: 14),
                      _buildTrustSection(
                        description,
                        skills,
                        canHelp,
                        cannotHelp,
                        charter,
                        onlineModes,
                      ),
                      if (isMember) ...[
                        const SizedBox(height: 14),
                        _buildMembersSection(name),
                      ],
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: '部落公告',
                        icon: Icons.campaign_outlined,
                        child: Text(
                          announcement.isNotEmpty ? announcement : '暂无公告',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: announcement.isNotEmpty
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: '部落求助',
                        icon: Icons.support_agent_rounded,
                        child: _buildPostSection(),
                      ),
                      const SizedBox(height: 14),
                      _buildCasesSection(),
                      const SizedBox(height: 14),
                      _buildResourcesSection(canManage),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 18),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTrustSection(
    String description,
    List<String> skills,
    String canHelp,
    String cannotHelp,
    String charter,
    List<String> onlineModes,
  ) {
    return _sectionCard(
      title: '能力与边界',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty)
            Text(
              description,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.55),
            ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: skills
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (canHelp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '能帮助',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              canHelp,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
            ),
          ],
          if (cannotHelp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '不提供',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              cannotHelp,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
            ),
          ],
          if (onlineModes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '线上方式',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: onlineModes
                  .map(
                    (mode) => Chip(
                      label: Text(mode),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (charter.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '部落公约',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              charter,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '仅开展线上交流 · 付费服务须走平台咨询或私人专线',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildCasesSection() => _sectionCard(
        title: '公开案例',
        icon: Icons.task_alt_rounded,
        child: _caseError != null
            ? ImWorkflowRetry(message: _caseError!, onRetry: _load)
            : _cases.isEmpty
                ? Text(
                    '暂无经求助者同意公开的案例',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textHint),
                  )
                : Column(
                    children: _cases
                        .take(5)
                        .map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(
                              Icons.check_circle_outline,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              item['title']?.toString() ?? '已解决案例',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item['summary']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
      );

  Widget _buildResourcesSection(bool canManage) {
    final query = _resourceQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _resources
        : _resources.where((item) {
            final title = item['title']?.toString().toLowerCase() ?? '';
            final content = item['content']?.toString().toLowerCase() ?? '';
            return title.contains(query) || content.contains(query);
          }).toList();
    final visible = _showAllResources ? filtered : filtered.take(3).toList();
    return _sectionCard(
      title: '资料库',
      icon: Icons.menu_book_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showAllResources && _resources.isNotEmpty) ...[
            TextField(
              onChanged: (value) => setState(() => _resourceQuery = value),
              decoration: const InputDecoration(
                hintText: '搜索资料标题或正文',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_loadingResources)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_resourceError != null)
            _buildResourceError()
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                query.isEmpty ? '暂无可查看的资料' : '没有找到相关资料',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            )
          else
            ...visible.map((item) => _buildResourceItem(item, canManage)),
          if (!_loadingResources && _resourceError == null) ...[
            if (_resources.length > 3 || _showAllResources)
              TextButton.icon(
                onPressed: () => setState(() {
                  _showAllResources = !_showAllResources;
                  if (!_showAllResources) _resourceQuery = '';
                }),
                icon: Icon(
                  _showAllResources
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.format_list_bulleted_rounded,
                ),
                label: Text(
                  _showAllResources ? '收起资料库' : '查看全部（${_resources.length}）',
                ),
              ),
          ],
          if (canManage) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _savingResource ? null : _createResource,
              icon: _submittingResource
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('发布资料'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResourceError() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(_resourceError ?? '资料库加载失败')),
            TextButton(onPressed: _reloadResources, child: const Text('重试')),
          ],
        ),
      );

  Widget _buildResourceItem(Map<String, dynamic> item, bool canManage) {
    final type = item['type']?.toString() ?? 'text';
    final visibility = item['visibility']?.toString() ?? 'public';
    final content = item['content']?.toString().trim() ?? '';
    final url = item['url']?.toString().trim() ?? '';
    final creator = item['creatorName']?.toString().trim() ?? '';
    final updatedAt = _formatResourceTime(
      item['updatedAt']?.toString() ?? item['createdAt']?.toString() ?? '',
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 12, right: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(_resourceTypeIcon(type), color: AppColors.primary),
          title: Text(
            item['title']?.toString() ?? '部落资料',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              _resourceVisibilityLabel(visibility),
              if (creator.isNotEmpty) creator,
              if (updatedAt.isNotEmpty) updatedAt,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
          trailing: canManage
              ? PopupMenuButton<String>(
                  enabled: !_savingResource,
                  onSelected: (value) {
                    if (value == 'edit') _editResource(item);
                    if (value == 'delete') _deleteResource(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                )
              : const Icon(Icons.keyboard_arrow_down_rounded),
          children: [
            if (content.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(content,
                    style: AppTextStyles.bodyMedium.copyWith(height: 1.55)),
              ),
            if (url.isNotEmpty) ...[
              if (content.isNotEmpty) const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _openResourceAttachment(url),
                  icon: Icon(type == 'link'
                      ? Icons.link_rounded
                      : Icons.attach_file_rounded),
                  label: Text(type == 'link' ? '打开资料链接' : '查看附件'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _resourceTypeIcon(String type) => switch (type) {
        'image' => Icons.image_outlined,
        'file' => Icons.attach_file_rounded,
        'link' => Icons.link_rounded,
        _ => Icons.article_outlined,
      };

  String _resourceVisibilityLabel(String visibility) => switch (visibility) {
        'members' => '部落成员可见',
        'admins' => '仅管理者可见',
        _ => '所有人可见',
      };

  String _formatResourceTime(String raw) {
    if (raw.isEmpty) return '';
    final normalized = raw.replaceFirst('T', ' ');
    return normalized.length >= 16 ? normalized.substring(0, 16) : normalized;
  }

  Widget _buildHero(
    String name,
    String title,
    int memberCount,
    int maxMembers,
  ) {
    final caseCount = (_team?['caseCount'] as num?)?.toInt() ?? 0;
    final openHelpCount = (_team?['openHelpCount'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Color(0xFF24272D),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : '部落',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '$memberCount / $maxMembers 人',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$caseCount 个已解决案例 · $openHelpCount 个待响应求助',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    String name,
    bool isMember,
    bool isPublic,
    bool canManage,
    bool applyPending,
  ) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: !_ready || _applying
                ? null
                : isMember
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              conversationId: widget.conversationId,
                              title: name,
                              conversationType: 'group',
                            ),
                          ),
                        )
                    : !isPublic
                        ? null
                        : applyPending
                            ? _withdrawJoin
                            : _applyJoin,
            child: Text(
              isMember
                  ? '进入部落群聊'
                  : !isPublic
                      ? '暂不开放申请'
                      : applyPending
                          ? '撤回申请'
                          : '申请加入',
            ),
          ),
        ),
        if (isMember) ...[
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ChatInfoPage(
                    conversationId: widget.conversationId,
                    title: name,
                    onUpdated: _load,
                  ),
                ),
              );
              if (!mounted || !_scope.current) return;
              if (changed == true) {
                Navigator.of(context).pop(true);
              } else {
                _load();
              }
            },
            child: Text(canManage ? '管理' : '详情'),
          ),
        ],
      ],
    );
  }

  Widget _buildMembersSection(String name) {
    final preview = _members.take(6).toList();
    return _sectionCard(
      title: '部落成员',
      icon: Icons.people_outline_rounded,
      child: _memberError != null
          ? ImWorkflowRetry(message: _memberError!, onRetry: _load)
          : InkWell(
              onTap: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => GroupMembersPage(
                        conversationId: widget.conversationId,
                        title: name,
                        isTribe: true,
                        onKicked: _load,
                      ),
                    ),
                  )
                  .then((_) => _load()),
              child: Row(
                children: [
                  ...preview.map((member) {
                    final nickname = member['nickname']?.toString() ?? '用户';
                    final avatar = member['avatarUrl']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: const Color(0xFFF1F2F4),
                        backgroundImage:
                            avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty
                            ? Text(
                                nickname.isNotEmpty ? nickname[0] : '?',
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                      ),
                    );
                  }),
                  const Spacer(),
                  const Text(
                    '查看全部',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFFB9BDC4),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: AppColors.divider.withValues(alpha: 0.35))),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          )),
    );
  }

  Widget _buildPostSection() {
    if (_postError != null) {
      return ImWorkflowRetry(message: _postError!, onRetry: _refreshPostsOnly);
    }
    if (_loadingPosts || (_loading && _posts.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Icon(
              Icons.dynamic_feed_outlined,
              size: 44,
              color: AppColors.textHint.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              '暂无面向该部落的求助',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _refreshPostsOnly,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        ..._posts.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return PostCard(
            item: item,
            heroTagSuffix: 'team_${widget.conversationId}_$index',
            integrated: true,
            showBottomDivider: index != _posts.length - 1,
            onDeleted: (postId) {
              if (!_ready) return;
              setState(() {
                _postGeneration++;
                _loadingPosts = false;
                _posts.removeWhere((e) => (e['id'] as num?)?.toInt() == postId);
              });
            },
          );
        }),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: _refreshPostsOnly,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('刷新求助'),
          ),
        ),
      ],
    );
  }
}

class _ResourceDraft {
  const _ResourceDraft({
    required this.title,
    required this.content,
    required this.type,
    required this.url,
    required this.visibility,
  });

  final String title;
  final String content;
  final String type;
  final String url;
  final String visibility;
}

class _ResourceAttachment {
  const _ResourceAttachment({
    required this.name,
    required this.url,
    required this.type,
  });

  final String name;
  final String url;
  final String type;
}

class _ResourceEditorException implements Exception {
  const _ResourceEditorException(this.message);

  final String message;
}

class _ResourceEditorDialog extends StatefulWidget {
  const _ResourceEditorDialog({
    required this.existing,
    required this.onPickAttachment,
  });

  final Map<String, dynamic>? existing;
  final Future<_ResourceAttachment?> Function() onPickAttachment;

  @override
  State<_ResourceEditorDialog> createState() => _ResourceEditorDialogState();
}

class _ResourceEditorDialogState extends State<_ResourceEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _urlController;
  late String _visibility;
  late String _type;
  String _attachmentName = '';
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    _contentController = TextEditingController(
      text: existing?['content']?.toString() ?? '',
    );
    _urlController = TextEditingController(
      text: existing?['url']?.toString() ?? '',
    );
    _visibility = existing?['visibility']?.toString() ?? 'public';
    _type = existing?['type']?.toString() ?? 'text';
    if (_urlController.text.isNotEmpty && _type != 'link') {
      _attachmentName = '已上传附件';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final attachment = await widget.onPickAttachment();
      if (!mounted || attachment == null) return;
      setState(() {
        _attachmentName = attachment.name;
        _urlController.text = attachment.url;
        _type = attachment.type;
      });
    } on _ResourceEditorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '附件上传失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachmentName = '';
      _urlController.clear();
      _type = 'text';
      _error = null;
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final url = _urlController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写资料标题');
      return;
    }
    if (content.isEmpty && url.isEmpty) {
      setState(() => _error = '正文和附件至少填写一项');
      return;
    }
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null || (uri.scheme != 'https' && uri.scheme != 'http'))) {
      setState(() => _error = '资料链接需要以 http:// 或 https:// 开头');
      return;
    }
    var type = _type;
    if (url.isEmpty) type = 'text';
    if (url.isNotEmpty && _attachmentName.isEmpty) type = 'link';
    Navigator.of(context).pop(
      _ResourceDraft(
        title: title,
        content: content,
        type: type,
        url: url,
        visibility: _visibility,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '编辑部落资料' : '发布部落资料'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '例如：新手排盘资料',
                ),
              ),
              TextField(
                controller: _contentController,
                maxLength: 10000,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: '正文（选填）',
                  hintText: '填写资料说明或正文内容',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _visibility,
                decoration: const InputDecoration(labelText: '查看范围'),
                items: const [
                  DropdownMenuItem(value: 'public', child: Text('所有人可见')),
                  DropdownMenuItem(value: 'members', child: Text('部落成员可见')),
                  DropdownMenuItem(value: 'admins', child: Text('仅管理者可见')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _visibility = value);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickAttachment,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(_uploading ? '正在上传…' : '选择并上传附件（选填）'),
              ),
              const SizedBox(height: 4),
              Text(
                '支持图片、PDF、Word、Excel、PPT、TXT、CSV，最大30MB',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
              if (_attachmentName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 18),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _attachmentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '移除附件',
                      onPressed: _uploading ? null : _removeAttachment,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ],
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: const InputDecoration(
                  labelText: '或填写资料链接（选填）',
                  hintText: 'https://',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _uploading ? null : _submit,
          child: Text(editing ? '保存' : '发布'),
        ),
      ],
    );
  }
}
