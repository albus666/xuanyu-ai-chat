import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/local/paipan_record_store.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/ai_generated_mark.dart';
import '../../core/widgets/ai_generated_image.dart';
import '../../core/widgets/app_gpt_markdown.dart';
import '../fortune/archive_relationship.dart';
import '../fortune/bazi_input_page.dart';
import '../fortune/paipan/models/paipan_record.dart';
import '../fortune/paipan_record_archive_page.dart';

/// 只解码末尾完整的 UTF-8 序列，避免 TCP 分包把一个汉字拆开后 JSON 解析失败。
int _completeUtf8Length(List<int> bytes) {
  if (bytes.isEmpty) return 0;
  var index = bytes.length;
  var continuation = 0;
  while (index > 0 &&
      continuation < 3 &&
      (bytes[index - 1] & 0xC0) == 0x80) {
    index--;
    continuation++;
  }
  if (index == 0) return bytes.length;
  final lead = bytes[index - 1];
  final need = lead < 0x80
      ? 1
      : (lead & 0xE0) == 0xC0
          ? 2
          : (lead & 0xF0) == 0xE0
              ? 3
              : (lead & 0xF8) == 0xF0
                  ? 4
                  : 1;
  if (1 + continuation < need) return index - 1;
  return bytes.length;
}

Future<String> _drainResponseBodyIfAny(dynamic data) async {
  if (data is! ResponseBody) return '';
  final sb = StringBuffer();
  try {
    await for (final chunk in data.stream) {
      sb.write(utf8.decode(chunk, allowMalformed: true));
    }
  } catch (_) {
    return sb.toString();
  }
  return sb.toString();
}

String? _tryParseApiMessage(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('{')) {
    try {
      final j = jsonDecode(s);
      if (j is Map && j['message'] != null) {
        final m = j['message'].toString().trim();
        if (m.isNotEmpty) return m;
      }
    } catch (_) {}
  }
  if (s.length < 800 && !s.startsWith('<!DOCTYPE') && !s.startsWith('<html')) {
    return s;
  }
  return null;
}

Future<String> _messageFromDioException(DioException e) async {
  final data = e.response?.data;
  if (data is Map && data['message'] != null) {
    final m = data['message'].toString().trim();
    if (m.isNotEmpty) return m;
  }
  if (data is String) {
    final parsed = _tryParseApiMessage(data);
    if (parsed != null) return parsed;
  }
  if (data is ResponseBody) {
    final drained = await _drainResponseBodyIfAny(data);
    final parsed = _tryParseApiMessage(drained);
    if (parsed != null) return parsed;
  }
  if (e.response?.statusCode == 401) return '请先登录';
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，请稍后重试';
    case DioExceptionType.connectionError:
      return '无法连接服务器，请检查网络';
    case DioExceptionType.badResponse:
      return '服务暂时繁忙，请稍后重试';
    default:
      break;
  }
  return '网络异常，请稍后重试';
}

/// AI 名师对话页：流式输出 + 可展开思考过程；tool-use 场景会显示工具调用进度
/// 接口 `/api/fortune/ai-master-chat/stream`
class AiMasterChatPage extends StatefulWidget {
  const AiMasterChatPage({
    super.key,
    this.title = 'AI 名师',
    this.scene = 'master',
    this.enableArchive = true,
  });

  final String title;
  final String scene;
  final bool enableArchive;

  @override
  State<AiMasterChatPage> createState() => _AiMasterChatPageState();
}

class _AiMasterChatPageState extends State<AiMasterChatPage> {
  final _messages = <Map<String, dynamic>>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  int? _sessionId;
  bool _loadingHistory = true;

  /// 本轮及后续发送可继续附带，直至用户清除或重选
  PaipanRecord? _attachedArchive;

  /// 流式阶段只驱动本条气泡，避免整页 setState + 键盘抬升时反复重布局 ListView。
  final _streamLiveContent = ValueNotifier<String>('');
  final _streamLiveReasoning = ValueNotifier<String>('');
  VoidCallback? _streamScrollListener;
  DateTime? _lastStreamScrollAt;

  String _archiveDisplayName(PaipanRecord r) {
    final n = r.displayName.trim();
    return n.isEmpty ? '未命名' : n;
  }

  String _archiveAttachLabel(PaipanRecord r) =>
      '${_archiveDisplayName(r)} · ${r.summary}';

  static final _assistantSplit = RegExp(
    r'【思考过程】\s*\n([\s\S]*?)\n\n【回复】\s*\n([\s\S]*)',
    multiLine: true,
  );
  static final _markdownImage = RegExp(
    r'!\[[^\]]*\]\(\s*(https?://[^\s)]+)\s*\)',
  );

  /// 历史入库格式：【思考过程】…【回复】…
  static Map<String, String?> _parseStoredAssistant(String? raw) {
    final s = raw ?? '';
    final m = _assistantSplit.firstMatch(s);
    if (m != null) {
      return {
        'reasoning': m.group(1)?.trim(),
        'answer': m.group(2)?.trim() ?? ''
      };
    }
    return {'reasoning': null, 'answer': s};
  }

  static String? _firstMarkdownImageUrl(String? raw) {
    final m = _markdownImage.firstMatch(raw ?? '');
    return m?.group(1);
  }

  @override
  void initState() {
    super.initState();
    if (widget.scene == 'love_wake') {
      _loadingHistory = false;
      _startNewChat();
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadPreferredArchive() async {
    final records = await PaipanRecordStore.loadAll();
    if (!mounted || records.isEmpty || _attachedArchive != null) return;
    final self = records.where((record) => record.isSelf);
    final eligible = records.where(_archiveIdentityReady);
    if (self.isEmpty && eligible.isEmpty) return;
    setState(
        () => _attachedArchive = self.isNotEmpty ? self.first : eligible.first);
  }

  bool _archiveIdentityReady(PaipanRecord record) =>
      record.isSelf ||
      (!record.isLegacySelf &&
          record.displayName.trim().isNotEmpty &&
          !ArchiveRelationship.isReservedSelfName(record.displayName));

  Future<void> _selectArchive(PaipanRecord record) async {
    if (!_archiveIdentityReady(record)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先为这份旧档案补充姓名和关系')),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => const PaipanRecordArchivePage()),
      );
      return;
    }
    if (_attachedArchive?.id == record.id) return;
    if (_messages.isNotEmpty && !await _startNewChat()) return;
    if (mounted) setState(() => _attachedArchive = record);
  }

  Future<void> _loadHistory() async {
    if (widget.scene == 'love_wake') {
      if (mounted) setState(() => _loadingHistory = false);
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      final res = await apiClient.get(
        '/api/fortune/ai-master-chat/history',
        queryParameters: _sessionId != null ? {'session_id': _sessionId} : null,
      );
      final data = (res.data as Map?)?['data'] as Map?;
      if (data != null && mounted) {
        final sid = (data['sessionId'] as num?)?.toInt();
        final list = data['messages'] as List<dynamic>?;
        setState(() {
          _sessionId = sid;
          _messages.clear();
          if (list != null) {
            for (final e in list) {
              if (e is Map<String, dynamic>) {
                final m = Map<String, dynamic>.from(e);
                if (m['role'] == 'assistant') {
                  final c = m['content'] as String?;
                  final p = _parseStoredAssistant(c);
                  final answer = (p['answer'] ?? '').toString();
                  if ((p['reasoning'] ?? '').toString().trim().isNotEmpty) {
                    m['reasoning'] = p['reasoning'];
                  }
                  m['content'] = AiGeneratedMark.ensureTextMark(answer);
                  m['imageUrl'] =
                      _firstMarkdownImageUrl(answer) ?? _firstMarkdownImageUrl(c);
                }
                _messages.add(m);
              }
            }
          }
          _loadingHistory = false;
        });
        if (_messages.isEmpty && widget.enableArchive) {
          await _loadPreferredArchive();
        }
        _scrollToBottom();
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  String _bodyWithoutMark(String text) =>
      text.replaceAll(AiGeneratedMark.textSuffix, '').trim();

  /// 流式正文若被截断，生成结束后用已入库的回复补上，不必退出页面。
  Future<void> _revealStoredAnswerIfRicher(int assistantIndex) async {
    if (!mounted || _sessionId == null) return;
    if (assistantIndex < 0 || assistantIndex >= _messages.length) return;
    try {
      final res = await apiClient.get(
        '/api/fortune/ai-master-chat/history',
        queryParameters: {'session_id': _sessionId},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final list = data?['messages'] as List<dynamic>?;
      if (list == null || !mounted || assistantIndex >= _messages.length) return;
      Map<String, dynamic>? stored;
      for (final item in list.reversed) {
        if (item is Map && item['role'] == 'assistant') {
          stored = Map<String, dynamic>.from(item);
          break;
        }
      }
      if (stored == null || !mounted) return;
      final raw = stored['content'] as String?;
      final parsed = _parseStoredAssistant(raw);
      final answer = (parsed['answer'] ?? '').toString();
      final reasoning = (parsed['reasoning'] ?? '').toString().trim();
      final live = (_messages[assistantIndex]['content'] as String?) ?? '';
      if (_bodyWithoutMark(answer).length <= _bodyWithoutMark(live).length) {
        return;
      }
      final image = _firstMarkdownImageUrl(answer) ?? _firstMarkdownImageUrl(raw);
      setState(() {
        _messages[assistantIndex]['content'] =
            AiGeneratedMark.ensureTextMark(answer);
        if (reasoning.isNotEmpty) {
          _messages[assistantIndex]['reasoning'] = reasoning;
        }
        if (image != null && image.isNotEmpty) {
          _messages[assistantIndex]['imageUrl'] = image;
        }
        _messages[assistantIndex]['streaming'] = false;
      });
      _scrollToBottom();
    } catch (_) {}
  }

  Future<bool> _startNewChat() async {
    try {
      final res = await apiClient.post(
        '/api/fortune/ai-master-chat/new',
        data: {'scene': widget.scene},
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final sid = (data?['sessionId'] as num?)?.toInt();
      if (mounted) {
        setState(() {
          _sessionId = sid;
          _messages.clear();
        });
      }
      if (widget.enableArchive && _attachedArchive == null) {
        await _loadPreferredArchive();
      }
      return true;
    } on DioException catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _unbindStreamNotifiersForScroll();
    _streamLiveContent.dispose();
    _streamLiveReasoning.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _bindStreamNotifiersForScroll() {
    _unbindStreamNotifiersForScroll();
    void tick() {
      if (!mounted || !_sending) return;
      final now = DateTime.now();
      if (_lastStreamScrollAt != null &&
          now.difference(_lastStreamScrollAt!) <
              const Duration(milliseconds: 120)) {
        return;
      }
      _lastStreamScrollAt = now;
      _scrollToBottom(instant: true);
    }

    _streamScrollListener = tick;
    _streamLiveContent.addListener(_streamScrollListener!);
    _streamLiveReasoning.addListener(_streamScrollListener!);
  }

  void _unbindStreamNotifiersForScroll() {
    if (_streamScrollListener != null) {
      _streamLiveContent.removeListener(_streamScrollListener!);
      _streamLiveReasoning.removeListener(_streamScrollListener!);
      _streamScrollListener = null;
    }
    _lastStreamScrollAt = null;
  }

  String _contentWithoutDuplicateImage(String? content, String? imageUrl) {
    final c = content ?? '';
    if (c.isEmpty || imageUrl == null || imageUrl.isEmpty) return c;
    final escapedUrl = RegExp.escape(imageUrl);
    return c
        .replaceAll(
            RegExp(r'!\[[^\]]*\]\s*\(\s*' + escapedUrl + r'\s*\)',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\n{2,}'), '\n\n')
        .trim();
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (instant) {
        _scrollController.jumpTo(max);
      } else {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showArchivePicker() async {
    final initialList = await PaipanRecordStore.loadAll();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) {
        var list = List<PaipanRecord>.from(initialList);
        Future<void> reload(StateSetter setSheetState) async {
          final latest = await PaipanRecordStore.loadAll();
          if (!ctx.mounted) return;
          setSheetState(() => list = latest);
        }

        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Text('选择分析对象', style: AppTextStyles.titleMedium),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () async {
                              await Navigator.of(ctx).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const BaziInputPage(forOther: true)),
                              );
                              await reload(setSheetState);
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('添加'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _attachedArchive = null);
                              Navigator.pop(ctx);
                            },
                            child: const Text('清除附带'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  '暂无命理档案。\n点右上角「添加」可直接进入八字排盘创建。',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textHint, height: 1.5),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final r = list[i];
                                final selected = _attachedArchive?.id == r.id;
                                return Container(
                                    margin:
                                        const EdgeInsets.fromLTRB(14, 5, 14, 5),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                              .withValues(alpha: .08)
                                          : const Color(0xFFF7FAFA),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                          color: selected
                                              ? AppColors.primary
                                              : const Color(0xFFE3ECEC)),
                                    ),
                                    child: ListTile(
                                      leading: Container(
                                        width: 42,
                                        height: 42,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: selected
                                                ? AppColors.primary
                                                : const Color(0xFFE3F1F1),
                                            borderRadius:
                                                BorderRadius.circular(13)),
                                        child: Text(r.isFemale ? '坤' : '乾',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: selected
                                                    ? Colors.white
                                                    : AppColors.primaryDark)),
                                      ),
                                      title: Row(children: [
                                        Flexible(
                                            child: Text(_archiveDisplayName(r),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700))),
                                        const SizedBox(width: 7),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(99)),
                                          child: Text(r.relationshipLabel,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      AppColors.textSecondary)),
                                        ),
                                      ]),
                                      subtitle: Text(
                                        '${r.summary}\n${DateFormat('yyyy-MM-dd HH:mm').format(r.birthDateTime)}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textHint),
                                      ),
                                      trailing: r.isSelf
                                          ? Icon(
                                              selected
                                                  ? Icons.check_circle_rounded
                                                  : Icons.chevron_right_rounded,
                                              color: selected
                                                  ? AppColors.primary
                                                  : AppColors.textHint)
                                          : IconButton(
                                              tooltip: '删除档案',
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: AppColors.error),
                                              onPressed: () async {
                                                final ok =
                                                    await showDialog<bool>(
                                                  context: ctx,
                                                  builder: (dctx) =>
                                                      AlertDialog(
                                                    title: const Text('删除档案'),
                                                    content: Text(
                                                        '确定删除「${_archiveDisplayName(r)}」吗？'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  dctx, false),
                                                          child:
                                                              const Text('取消')),
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  dctx, true),
                                                          child:
                                                              const Text('删除')),
                                                    ],
                                                  ),
                                                );
                                                if (ok == true) {
                                                  await PaipanRecordStore
                                                      .delete(r.id);
                                                  if (_attachedArchive?.id ==
                                                          r.id &&
                                                      mounted) {
                                                    setState(() =>
                                                        _attachedArchive =
                                                            null);
                                                  }
                                                  await reload(setSheetState);
                                                }
                                              },
                                            ),
                                      onTap: () async {
                                        Navigator.pop(ctx);
                                        await _selectArchive(r);
                                      },
                                    ));
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserBubble(Map<String, dynamic> m) {
    final text = m['content'] as String? ?? '';
    final archiveSummary = m['archiveSummary'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (archiveSummary != null && archiveSummary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD97706).withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_special_outlined,
                      size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '已附档案：$archiveSummary',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
          softWrap: true,
        ),
      ],
    );
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    _controller.clear();

    final userMsg = {
      'role': 'user',
      'content': content,
      'createdAt': DateTime.now().toIso8601String(),
      if (_attachedArchive != null)
        'archiveSummary': _archiveAttachLabel(_attachedArchive!),
    };
    setState(() {
      _messages.add(userMsg);
      _messages.add({
        'role': 'assistant',
        'content': '',
        'reasoning': '',
        'streaming': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      _sending = true;
    });
    _streamLiveContent.value = '';
    _streamLiveReasoning.value = '';
    _bindStreamNotifiersForScroll();
    _scrollToBottom();

    final body = <String, dynamic>{'message': content};
    body['scene'] = widget.scene;
    if (_sessionId != null) body['sessionId'] = _sessionId;
    if (widget.enableArchive && _attachedArchive != null) {
      body['archiveContext'] =
          await PaipanRecordStore.loadAiContext(_attachedArchive!);
    }

    final assistantIndex = _messages.length - 1;
    var reasoningAcc = '';
    var contentAcc = '';
    String? imageUrl;

    try {
      final res = await apiClient.post(
        '/api/fortune/ai-master-chat/stream',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          connectTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 6),
          // 须包含 application/json，否则部分 DRF 配置下仅 text/event-stream 会 406
          headers: {
            'Accept': 'text/event-stream, application/json;q=0.9, */*;q=0.8'
          },
        ),
      );

      final rb = res.data;
      if (rb is! ResponseBody) {
        throw FormatException('SSE 响应类型异常：${rb.runtimeType}');
      }
      var carry = '';
      final pending = <int>[];
      await for (final chunk in rb.stream) {
        pending.addAll(chunk);
        final safe = _completeUtf8Length(pending);
        if (safe > 0) {
          carry += utf8.decode(pending.sublist(0, safe), allowMalformed: true);
          pending.removeRange(0, safe);
        }
        carry = _consumeSseCarry(
          carry,
          reasoning: reasoningAcc,
          content: contentAcc,
          apply: (nextReasoning, nextContent) {
            reasoningAcc = nextReasoning;
            contentAcc = nextContent;
            _publishStream(assistantIndex, reasoningAcc, contentAcc);
          },
          onSession: (sid) {
            if (mounted) _sessionId = sid;
          },
          onImage: (url) => imageUrl = url,
          onError: (msg) {
            if (mounted) {
              _unbindStreamNotifiersForScroll();
              setState(() {
                _messages[assistantIndex]['content'] = msg;
                _messages[assistantIndex]['reasoning'] =
                    reasoningAcc.isEmpty ? null : reasoningAcc;
                _messages[assistantIndex]['streaming'] = false;
                _sending = false;
              });
            }
          },
        );
        if (!_sending && mounted && _messages[assistantIndex]['streaming'] != true) {
          return;
        }
      }
      if (pending.isNotEmpty) {
        carry += utf8.decode(pending, allowMalformed: true);
      }
      if (carry.isNotEmpty) {
        _consumeSseCarry(
          '$carry\n',
          reasoning: reasoningAcc,
          content: contentAcc,
          apply: (nextReasoning, nextContent) {
            reasoningAcc = nextReasoning;
            contentAcc = nextContent;
            _publishStream(assistantIndex, reasoningAcc, contentAcc);
          },
          onSession: (sid) {
            if (mounted) _sessionId = sid;
          },
          onImage: (url) => imageUrl = url,
          onError: (msg) {
            if (mounted) {
              _unbindStreamNotifiersForScroll();
              setState(() {
                _messages[assistantIndex]['content'] = msg;
                _messages[assistantIndex]['reasoning'] =
                    reasoningAcc.isEmpty ? null : reasoningAcc;
                _messages[assistantIndex]['streaming'] = false;
                _sending = false;
              });
            }
          },
        );
      }

      if (mounted) {
        _unbindStreamNotifiersForScroll();
        setState(() {
          _messages[assistantIndex]['content'] = AiGeneratedMark.ensureTextMark(
              contentAcc.isEmpty ? '抱歉，暂未生成回复。' : contentAcc);
          _messages[assistantIndex]['reasoning'] =
              reasoningAcc.isEmpty ? null : reasoningAcc;
          if (imageUrl != null && imageUrl!.isNotEmpty) {
            _messages[assistantIndex]['imageUrl'] = imageUrl;
          }
          _messages[assistantIndex]['streaming'] = false;
          _sending = false;
        });
        _scrollToBottom();
      }
      await _revealStoredAnswerIfRicher(assistantIndex);
    } on DioException catch (e) {
      final msg = await _messageFromDioException(e);
      if (mounted) {
        _unbindStreamNotifiersForScroll();
        setState(() {
          _messages[assistantIndex]['content'] = msg;
          _messages[assistantIndex]['streaming'] = false;
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        _unbindStreamNotifiersForScroll();
        setState(() {
          _messages[assistantIndex]['content'] = '请求异常：${e.toString()}';
          _messages[assistantIndex]['streaming'] = false;
          _sending = false;
        });
        _scrollToBottom();
      }
    }
  }

  String _consumeSseCarry(
    String carry, {
    required String reasoning,
    required String content,
    required void Function(String reasoning, String content) apply,
    required void Function(int sid) onSession,
    required void Function(String? url) onImage,
    required void Function(String msg) onError,
  }) {
    while (true) {
      final nl = carry.indexOf('\n');
      if (nl < 0) break;
      var line = carry.substring(0, nl).trimRight();
      carry = carry.substring(nl + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty || !line.startsWith('data:')) continue;
      final payload = line.substring(5).trimLeft();
      if (payload.isEmpty) continue;
      final Map<String, dynamic> ev;
      try {
        final raw = jsonDecode(payload);
        if (raw is! Map) continue;
        ev = Map<String, dynamic>.from(raw);
      } catch (_) {
        continue;
      }
      final type = ev['type'] as String?;
      if (type == 'session') {
        final sid = (ev['sessionId'] as num?)?.toInt();
        if (sid != null) onSession(sid);
      } else if (type == 'status') {
        final t = (ev['text'] as String? ?? '').trim();
        if (t.isEmpty) continue;
        reasoning += '$t\n';
        apply(reasoning, content);
      } else if (type == 'tool_start') {
        final label = (ev['label'] as String?)?.trim().isNotEmpty == true
            ? ev['label'].toString()
            : (ev['name']?.toString() ?? '工具');
        reasoning += '正在调用：$label…\n';
        apply(reasoning, content);
      } else if (type == 'tool_result') {
        final label = (ev['label'] as String?)?.trim().isNotEmpty == true
            ? ev['label'].toString()
            : (ev['name']?.toString() ?? '工具');
        final ok = ev['ok'] == true;
        reasoning += ok ? '$label 完成 ✓\n' : '$label 失败\n';
        apply(reasoning, content);
      } else if (type == 'reasoning_clear') {
        reasoning = '';
        apply(reasoning, content);
      } else if (type == 'reasoning') {
        reasoning += ev['text'] as String? ?? '';
        apply(reasoning, content);
      } else if (type == 'content_clear') {
        content = '';
        apply(reasoning, content);
      } else if (type == 'content') {
        content += ev['text'] as String? ?? '';
        apply(reasoning, content);
      } else if (type == 'content_replace') {
        content = ev['text'] as String? ?? '';
        apply(reasoning, content);
      } else if (type == 'error') {
        onError(ev['message']?.toString() ?? '生成失败');
        break;
      } else if (type == 'done') {
        onImage(ev['imageUrl'] as String?);
        final sid = (ev['sessionId'] as num?)?.toInt();
        if (sid != null) onSession(sid);
      }
    }
    return carry;
  }

  void _publishStream(int assistantIndex, String reasoning, String content) {
    if (!mounted) return;
    _messages[assistantIndex]['reasoning'] = reasoning.isEmpty ? null : reasoning;
    _messages[assistantIndex]['content'] = content;
    _streamLiveReasoning.value = reasoning;
    _streamLiveContent.value = content;
  }

  Widget _buildAssistantBubble(Map<String, dynamic> m, int messageIndex) {
    return _assistantBubbleCore(
      reasoning: m['reasoning'] as String?,
      content: m['content'] as String? ?? '',
      streaming: m['streaming'] == true,
      imageUrl: m['imageUrl'] as String?,
      messageIndex: messageIndex,
      markdownSelectable: true,
    );
  }

  Widget _assistantBubbleCore({
    required String? reasoning,
    required String content,
    required bool streaming,
    required String? imageUrl,
    required int messageIndex,
    required bool markdownSelectable,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reasoning != null && reasoning.isNotEmpty)
          _ThinkingProcessBlock(
            key: ValueKey('think_$messageIndex'),
            reasoning: reasoning,
            streaming: streaming,
          ),
        if (reasoning != null && reasoning.isNotEmpty)
          const SizedBox(height: 8),
        if (imageUrl != null && imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AiGeneratedImage(imageUrl: imageUrl),
          ),
        if (streaming &&
            content.isEmpty &&
            (reasoning == null || reasoning.isEmpty))
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textHint),
                ),
                const SizedBox(width: 8),
                Text('正在生成回复…',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textHint)),
              ],
            ),
          )
        else if (content.isNotEmpty)
          AppGptMarkdown(
            selectionArea: markdownSelectable,
            data: AiGeneratedMark.ensureTextMark(
                _contentWithoutDuplicateImage(content, imageUrl)),
            bodyStyle: AppTextStyles.bodyMedium
                .copyWith(height: 1.62, color: AppColors.textPrimary),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _loadingHistory ? null : _startNewChat,
            icon: const Icon(Icons.add_rounded,
                size: 18, color: AppColors.primary),
            label: const Text('新对话',
                style: TextStyle(color: AppColors.primary, fontSize: 14)),
          ),
        ],
        title: Text(widget.title, style: AppTextStyles.titleMedium),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFEAF7F7),
            child: const Text(
              'AI生成内容 · 仅供传统文化交流与一般参考，不替代医疗、法律、投资等专业意见',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.primaryDark),
            ),
          ),
          if (widget.enableArchive)
            InkWell(
              onTap: _sending ? null : _showArchivePicker,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFDDEAEA)),
                ),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_search_rounded,
                        color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('当前分析对象',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textHint)),
                          const SizedBox(height: 2),
                          Text(
                            _attachedArchive == null
                                ? '请先选择一份八字档案'
                                : '${_archiveDisplayName(_attachedArchive!)} · ${_attachedArchive!.relationshipLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                        ]),
                  ),
                  Text(_attachedArchive == null ? '选择' : '切换',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primary),
                ]),
              ),
            ),
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 64,
                                color:
                                    AppColors.textHint.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('有什么想咨询的吗？',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textHint)),
                            const SizedBox(height: 8),
                            Text(
                              widget.enableArchive
                                  ? '选择一份命理档案，再直接说出你想问的事。'
                                  : '把你的关系问题直接说出来，我会给你清醒、直接、可执行的建议。',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textHint, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                            12, 12, 12, 12 + mq.viewInsets.bottom),
                        cacheExtent: 480.0,
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final isUser = m['role'] == 'user';
                          return RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final w = constraints.maxWidth;
                                  final assistantMax = math.min(560.0, w);

                                  final messageBubble = Container(
                                    clipBehavior: Clip.hardEdge,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? AppColors.primary
                                              .withValues(alpha: 0.1)
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: isUser
                                        ? _buildUserBubble(m)
                                        : (m['streaming'] == true
                                            ? RepaintBoundary(
                                                child: AnimatedBuilder(
                                                  animation: Listenable.merge([
                                                    _streamLiveContent,
                                                    _streamLiveReasoning
                                                  ]),
                                                  builder: (_, __) {
                                                    final r =
                                                        _streamLiveReasoning
                                                            .value;
                                                    final c = _streamLiveContent
                                                        .value;
                                                    return _assistantBubbleCore(
                                                      reasoning:
                                                          r.isEmpty ? null : r,
                                                      content: c.isEmpty
                                                          ? c
                                                          : AiGeneratedMark
                                                              .ensureTextMark(
                                                                  c),
                                                      streaming: true,
                                                      imageUrl: m['imageUrl']
                                                          as String?,
                                                      messageIndex: i,
                                                      markdownSelectable: false,
                                                    );
                                                  },
                                                ),
                                              )
                                            : _buildAssistantBubble(m, i)),
                                  );

                                  if (isUser) {
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Flexible(
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                  maxWidth: w * 0.88),
                                              child: messageBubble,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const CircleAvatar(
                                          radius: 14,
                                          backgroundColor:
                                              AppColors.primaryLight,
                                          child: Icon(Icons.person,
                                              size: 16,
                                              color: AppColors.primary),
                                        ),
                                      ],
                                    );
                                  }

                                  return Align(
                                    alignment: Alignment.center,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: assistantMax),
                                      child: messageBubble,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 10, 12, 10 + mq.padding.bottom + mq.viewInsets.bottom),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.enableArchive && _attachedArchive != null)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.auto_stories_rounded,
                                  size: 23, color: AppColors.primaryDark),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('已附带命理档案',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(_archiveAttachLabel(_attachedArchive!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            )),
                            InkWell(
                              onTap: _sending
                                  ? null
                                  : () =>
                                      setState(() => _attachedArchive = null),
                              borderRadius: BorderRadius.circular(20),
                              child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded,
                                      size: 20, color: AppColors.textHint)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.enableArchive)
                      IconButton(
                        tooltip: '附带命理档案',
                        onPressed: _sending ? null : _showArchivePicker,
                        icon: Icon(
                          Icons.folder_open_outlined,
                          color: _attachedArchive != null
                              ? AppColors.primaryDark
                              : AppColors.textHint,
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: AppTextStyles.bodyMedium,
                        decoration: InputDecoration(
                          hintText: widget.scene == 'love_wake'
                              ? '把让你上头的事说出来…'
                              : '输入您的问题...',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    _sending
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton.filled(
                            onPressed: _send,
                            icon: const Icon(Icons.send_rounded),
                            style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706)),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 深度思考：超过 [_ThinkingProcessBlock.collapseCharThreshold] 字且流式结束后默认折叠，可点「展开全部」查看全文。
class _ThinkingProcessBlock extends StatefulWidget {
  /// 大于该字数则视为长文，结束后默认折叠（流式进行中始终全文展示）。
  static const int collapseCharThreshold = 400;

  final String reasoning;
  final bool streaming;

  const _ThinkingProcessBlock({
    super.key,
    required this.reasoning,
    required this.streaming,
  });

  @override
  State<_ThinkingProcessBlock> createState() => _ThinkingProcessBlockState();
}

class _ThinkingProcessBlockState extends State<_ThinkingProcessBlock> {
  late bool _expanded;

  bool get _long =>
      widget.reasoning.length > _ThinkingProcessBlock.collapseCharThreshold;

  @override
  void initState() {
    super.initState();
    _expanded = widget.streaming || !_long;
  }

  @override
  void didUpdateWidget(covariant _ThinkingProcessBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reasoning.length <=
        _ThinkingProcessBlock.collapseCharThreshold) {
      if (!_expanded) setState(() => _expanded = true);
    } else if (oldWidget.streaming && !widget.streaming) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFull = widget.streaming || !_long || _expanded;
    final bodyStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
      fontSize: 13,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.psychology_outlined,
                size: 18, color: AppColors.textHint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.streaming ? '思考中…' : '思考过程',
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFFD97706),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!widget.streaming && _long)
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? '收起' : '展开全部',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color(0xFFD97706),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFD97706).withValues(alpha: 0.2)),
          ),
          child: showFull
              ? SelectableText(widget.reasoning, style: bodyStyle)
              : Text(
                  widget.reasoning,
                  style: bodyStyle,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}
