import 'conversation_preview.dart';
import 'chat_search_page.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/network/api_session_scope.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/tool_share_message.dart';
import '../../shared/widgets/tool_share_preview.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/image_utils.dart';

import '../community/post_detail_page.dart';
import '../community/post_text_cover_preview.dart';
import '../community/user_profile_page.dart';
import '../community/video_player_page.dart';
import '../consultation/voice_room_overlay_controller.dart';
import '../profile/profile_background_artwork.dart';
import '../virtual_goods/virtual_gift_sheet.dart';
import '../virtual_goods/virtual_gift_playback_queue.dart';
import '../virtual_goods/virtual_avatar_artwork.dart';
import '../virtual_goods/virtual_avatar_catalog.dart';
import '../virtual_goods/virtual_style_order_sheet.dart';
import 'chat_info_page.dart';
import 'chat_appearance.dart';
import 'chat_message_sync.dart';
import 'chat_recall.dart';
import 'im_workflow_request.dart';
import 'single_chat_settings_page.dart';
import 'social_call_overlay.dart';

int compareChatMessages(Map<String, dynamic> left, Map<String, dynamic> right) {
  final a = (left['id'] as num?)?.toInt() ?? 0;
  final b = (right['id'] as num?)?.toInt() ?? 0;
  if (a > 0 && b > 0) return a.compareTo(b);
  if (a > 0) return -1;
  if (b > 0) return 1;
  final at = DateTime.tryParse(left['createdAt']?.toString() ?? '');
  final bt = DateTime.tryParse(right['createdAt']?.toString() ?? '');
  return (at ?? DateTime.fromMillisecondsSinceEpoch(0))
      .compareTo(bt ?? DateTime.fromMillisecondsSinceEpoch(0));
}

@visibleForTesting
String chatAvatarCacheIdentity(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return '';
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return raw;
  return uri.replace(
    queryParameters: const <String, String>{},
    fragment: '',
  ).toString();
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.conversationId,
    required this.title,
    this.conversationType = 'single',
    this.peerUserId,
    this.isPeerMaster = false,
    this.initialMessageId,
  });

  final int conversationId;
  final String title;
  final String conversationType;
  final int? peerUserId;
  final bool isPeerMaster;
  final int? initialMessageId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const _audioRecorder = MethodChannel('xuanyu/audio_recorder');
  final _scope = ImWorkflowRequest();
  final _recalledMessageIds = <int>{};
  final _messages = <Map<String, dynamic>>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _refreshPending = false;
  bool _reconcileAllLoaded = true;
  bool _loadingOlder = false;
  bool _hasMoreHistory = false;
  bool _stickToLatest = true;
  bool _showNewMessages = false;
  String? _historyError;
  late final ChatMessageSync _messageSync;
  final _messageLocationKeys = <String, GlobalKey>{};
  bool _locatingMessage = false;
  int? _highlightMessageId;
  Timer? _highlightTimer;
  bool _startingCall = false;
  bool _sending = false;
  int _activeSends = 0;
  bool _showEmoji = false;
  bool _showMorePanel = false;
  bool _voiceMode = false;
  bool _recording = false;
  bool _recordStarting = false;
  bool _recordReleased = false;
  int? _recordPointerId;
  DateTime? _recordStartedAt;
  Timer? _recordLimitTimer;
  ChatAppearance _appearance = const ChatAppearance();
  late String _displayTitle;
  int? _myUserId;
  Map<String, dynamic>? _chatPermission;
  Map<String, dynamic>? _quotedMessage;
  final _virtualEffects = VirtualGiftPlaybackQueue();
  WebSocket? _conversationEventsSocket;
  Timer? _conversationEventsReconnectTimer;
  Timer? _conversationEventsRefreshTimer;
  bool _conversationEventsConnecting = false;
  int _conversationEventsReconnectAttempt = 0;
  bool _messagesLoadedOnce = false;
  bool _multiSelecting = false;
  bool _messageActionBusy = false;
  final Set<int> _selectedMessageIds = <int>{};
  final Map<String, GlobalKey> _messageActionKeys = <String, GlobalKey>{};

  bool get _chatSendBlocked =>
      _chatPermission?['limited'] == true &&
      _chatPermission?['canSend'] == false;

  int? get _chatRemaining => (_chatPermission?['remaining'] as num?)?.toInt();

  bool get _chatTextOnly => _chatPermission?['limited'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_onSessionChanged);
    _messageSync = ChatMessageSync(apiClient, widget.conversationId);
    _scrollController.addListener(_trackScrollPosition);
    _displayTitle = widget.title;
    _loadMyUserId();
    _loadInitialMessages();
    _loadAppearance();
    _markRead();
    unawaited(_connectConversationEvents());
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmoji) {
        setState(() => _showEmoji = false);
      }
    });
  }

  Future<void> _loadInitialMessages() async {
    await _loadMessages();
    if (mounted && widget.initialMessageId != null) {
      await _jumpToMessage(widget.initialMessageId!);
    }
  }

  Future<void> _openChatSearch() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatSearchPage(
            conversationId: widget.conversationId,
            title: _displayTitle,
            onLocate: (id) {
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                      conversationId: widget.conversationId,
                      title: _displayTitle,
                      conversationType: widget.conversationType,
                      peerUserId: widget.peerUserId,
                      isPeerMaster: widget.isPeerMaster,
                      initialMessageId: id)));
            })));
  }

  Future<void> _loadSingleDisplayInfo() async {
    if (!_scope.current || widget.conversationType != 'single') return;
    try {
      final data = await _scope.get(
        '/api/im/conversation/${widget.conversationId}/info',
      );
      final value = data['displayName']?.toString().trim() ?? '';
      if (mounted &&
          _scope.current &&
          value.isNotEmpty &&
          value != _displayTitle) {
        setState(() => _displayTitle = value);
      }
    } catch (_) {}
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    _conversationEventsReconnectTimer?.cancel();
    _conversationEventsRefreshTimer?.cancel();
    final socket = _conversationEventsSocket;
    _conversationEventsSocket = null;
    if (socket != null) unawaited(socket.close(WebSocketStatus.normalClosure));
    _controller.clear();
    setState(() {
      _virtualEffects.clear();
      _messages.clear();
      _quotedMessage = null;
      _myUserId = null;
      _selectedMessageIds.clear();
      _recalledMessageIds.clear();
    });
  }

  Future<void> _markRead() async {
    if (!mounted || !_scope.current) return;
    try {
      await _scope.post(
        '/api/im/conversation/${widget.conversationId}/read',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiSessionChanges.removeListener(_onSessionChanged);
    _virtualEffects.clear();
    _highlightTimer?.cancel();
    _recordLimitTimer?.cancel();
    _conversationEventsReconnectTimer?.cancel();
    _conversationEventsRefreshTimer?.cancel();
    final eventsSocket = _conversationEventsSocket;
    _conversationEventsSocket = null;
    if (eventsSocket != null) {
      unawaited(eventsSocket.close(WebSocketStatus.normalClosure));
    }
    if (_recording) unawaited(_audioRecorder.invokeMethod('cancelRecording'));
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileAllLoaded = true;
      unawaited(_loadMessages());
      unawaited(_connectConversationEvents());
    }
  }

  void _trackScrollPosition() {
    if (!_scrollController.hasClients || _loadingOlder || _locatingMessage) {
      return;
    }
    _stickToLatest = _scrollController.position.extentAfter <= 72;
    if (_stickToLatest && _showNewMessages && mounted) {
      setState(() => _showNewMessages = false);
    }
  }

  Future<void> _loadAppearance() async {
    final value = await loadChatAppearance(widget.conversationId);
    if (mounted && _scope.current) setState(() => _appearance = value);
  }

  Uri _conversationEventsUri() {
    final base = Uri.parse(apiClient.options.baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/ws/im/conversations/${widget.conversationId}',
      query: null,
      fragment: null,
    );
  }

  Future<void> _connectConversationEvents() async {
    if (!mounted ||
        !_scope.current ||
        _conversationEventsConnecting ||
        _conversationEventsSocket != null) {
      return;
    }
    final authorization =
        apiClient.options.headers['Authorization']?.toString() ?? '';
    if (!authorization.startsWith('Bearer ')) return;
    _conversationEventsConnecting = true;
    try {
      final socket = await WebSocket.connect(
        _conversationEventsUri().toString(),
        headers: {'Authorization': authorization},
      );
      if (!mounted || !_scope.current) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      socket.pingInterval = const Duration(seconds: 25);
      _conversationEventsReconnectTimer?.cancel();
      _conversationEventsReconnectAttempt = 0;
      _conversationEventsSocket = socket;
      socket.listen(
        _handleConversationEvent,
        onDone: () => _handleConversationEventsDisconnected(socket),
        onError: (_) => _handleConversationEventsDisconnected(socket),
        cancelOnError: true,
      );
      // ready 不会重放离线期间的通知，连接成功后主动补齐消息。
      _reconcileAllLoaded = true;
      await _loadMessages();
    } catch (_) {
      _scheduleConversationEventsReconnect();
    } finally {
      _conversationEventsConnecting = false;
    }
  }

  void _handleConversationEvent(dynamic raw) {
    if (!mounted || !_scope.current) return;
    try {
      final decoded = jsonDecode(raw?.toString() ?? '');
      if (decoded is! Map ||
          decoded['type'] != 'conversation.changed' ||
          (decoded['conversationId'] as num?)?.toInt() !=
              widget.conversationId) {
        return;
      }
      final reason = decoded['reason']?.toString() ?? 'message';
      if (reason == 'recall') _reconcileAllLoaded = true;
      // 连续消息合并为一次权威 REST 刷新，避免重复请求和本地状态漂移。
      _conversationEventsRefreshTimer?.cancel();
      _conversationEventsRefreshTimer = Timer(
        const Duration(milliseconds: 100),
        () async {
          await _loadMessages();
          if (reason != 'read') await _markRead();
        },
      );
    } catch (_) {}
  }

  void _handleConversationEventsDisconnected(WebSocket socket) {
    if (!identical(_conversationEventsSocket, socket)) return;
    _conversationEventsSocket = null;
    _scheduleConversationEventsReconnect();
  }

  void _scheduleConversationEventsReconnect() {
    if (!mounted ||
        !_scope.current ||
        _conversationEventsReconnectTimer?.isActive == true) {
      return;
    }
    const delays = <int>[1, 2, 4, 8, 15];
    final delay = delays[_conversationEventsReconnectAttempt
        .clamp(0, delays.length - 1)
        .toInt()];
    _conversationEventsReconnectAttempt++;
    _conversationEventsReconnectTimer = Timer(
      Duration(seconds: delay),
      () => unawaited(_connectConversationEvents()),
    );
  }

  Future<void> _openGiftSheet() async {
    if (!mounted || !_scope.current) return;
    final peerId = widget.peerUserId;
    if (_chatTextOnly) {
      showAppToast(context, '对方回复或与你互相关注后才可以赠送礼物');
      return;
    }
    final targets = <VirtualGiftTarget>[];
    if (widget.conversationType == 'single' && peerId != null) {
      targets.add(
        VirtualGiftTarget(
          userId: peerId,
          nickname: _displayTitle,
          conversationId: widget.conversationId,
        ),
      );
    } else {
      try {
        final data = await _scope.get(
          '/api/im/conversation/${widget.conversationId}/members',
        );
        final list = data['list'] as List? ?? const [];
        for (final raw in list) {
          if (raw is! Map) continue;
          final userId = (raw['userId'] as num?)?.toInt();
          if (userId == null || userId == _myUserId) continue;
          targets.add(
            VirtualGiftTarget(
              userId: userId,
              nickname: raw['nickname']?.toString() ?? '群成员',
              conversationId: widget.conversationId,
            ),
          );
        }
      } catch (_) {
        if (mounted && _scope.current) showAppToast(context, '群成员加载失败');
        return;
      }
    }
    if (targets.isEmpty) {
      if (mounted) showAppToast(context, '暂无可赠送的成员');
      return;
    }
    if (!mounted || !_scope.current) return;
    final result = await showVirtualGiftSheet(context, targets: targets);
    if (result == null || !mounted || !_scope.current) return;
    setState(() => _virtualEffects.enqueue(result));
    await _loadMessages();
  }

  void _completeVirtualEffect(Map<String, dynamic> effect) {
    if (!mounted || !_scope.current) return;
    setState(() => _virtualEffects.complete(effect));
  }

  Future<void> _openStyleOrderSheet() async {
    final peerId = widget.peerUserId;
    if (widget.conversationType != 'single' || peerId == null) {
      showAppToast(context, '装扮赠送目前支持私聊对象');
      return;
    }
    if (_chatTextOnly) {
      showAppToast(context, '对方回复或与你互相关注后才可以赠送装扮');
      return;
    }
    final result = await showVirtualStyleOrderSheet(
      context,
      target: VirtualStyleTarget(
        userId: peerId,
        nickname: _displayTitle,
        conversationId: widget.conversationId,
      ),
    );
    if (result != null && mounted) await _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (!mounted || !_scope.current) return;
    if (_loading) {
      _refreshPending = true;
      return;
    }
    _loading = true;
    try {
      final knownIds =
          _messages.map((m) => (m['id'] as num?)?.toInt()).whereType<int>();
      final latestKnownId =
          knownIds.isEmpty ? null : knownIds.reduce((a, b) => a > b ? a : b);
      final requestKnownIds = knownIds.toSet();
      final reconcileIds = _reconcileAllLoaded
          ? chatReconciliationIds(_messages)
          : const <int>{};
      _reconcileAllLoaded = false;
      final data = await _messageSync.refresh(
          latestKnownId: latestKnownId, knownIds: reconcileIds);
      final list = data['list'] as List<dynamic>?;
      if (mounted && _scope.current) {
        final followLatest = !_messagesLoadedOnce || _stickToLatest;
        final previousIds = _messages
            .map((item) => (item['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
        final incomingNudge = _messagesLoadedOnce &&
            (list ?? const <dynamic>[])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .any((item) {
              final id = (item['id'] as num?)?.toInt();
              return item['type'] == 'nudge' &&
                  id != null &&
                  !previousIds.contains(id) &&
                  _myUserId != null &&
                  item['senderId'] != _myUserId;
            });
        setState(() {
          _virtualEffects.observeMessages((list ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row)));
          if (!_messagesLoadedOnce) _hasMoreHistory = data['hasMore'] == true;
          _historyError = null;
          final permission = data['chatPermission'];
          _chatPermission =
              permission is Map ? Map<String, dynamic>.from(permission) : null;
          final existingById = <int, Map<String, dynamic>>{
            for (final item in _messages)
              if ((item['id'] as num?)?.toInt() case final int id) id: item,
          };
          final pending = _messages
              .where((item) => item['localId'] != null)
              .toList(growable: false);
          final incomingIds = (list ?? const [])
              .whereType<Map>()
              .map((item) => (item['id'] as num?)?.toInt())
              .whereType<int>()
              .toSet();
          final oldestIncoming = incomingIds.isEmpty
              ? null
              : incomingIds.reduce((a, b) => a < b ? a : b);
          final next = <Map<String, dynamic>>[
            // 刷新最新消息不能抹掉用户已经翻出的历史记录。
            for (final item in _messages)
              if (item['id'] is num &&
                  ((oldestIncoming != null &&
                          (item['id'] as num).toInt() < oldestIncoming) ||
                      (!requestKnownIds.contains(item['id']) &&
                          !incomingIds.contains(item['id']))))
                item,
          ];
          if (!followLatest && incomingIds.difference(previousIds).isNotEmpty) {
            _showNewMessages = true;
          }
          for (final e in list ?? const <dynamic>[]) {
            if (e is Map<String, dynamic>) {
              final incoming = Map<String, dynamic>.from(e);
              final id = (incoming['id'] as num?)?.toInt();
              final existing = id == null ? null : existingById[id];
              if (existing != null) {
                final previousAvatar = existing['avatarUrl']?.toString();
                final incomingAvatar = incoming['avatarUrl']?.toString();
                if (previousAvatar != null &&
                    previousAvatar.isNotEmpty &&
                    chatAvatarCacheIdentity(previousAvatar) ==
                        chatAvatarCacheIdentity(incomingAvatar)) {
                  incoming['avatarUrl'] = previousAvatar;
                }
                existing
                  ..clear()
                  ..addAll(incoming);
                next.add(existing);
              } else {
                next.add(incoming);
              }
            }
          }
          next.addAll(pending);
          _messages
            ..clear()
            ..addAll(next);
          _messages.sort(compareChatMessages);
          _applyRecalledIds((data['recalledIds'] as List? ?? const [])
              .whereType<num>()
              .map((id) => id.toInt()));
          _messagesLoadedOnce = true;
        });
        if (incomingNudge && ModalRoute.of(context)?.isCurrent == true) {
          unawaited(AppHaptics.nudge());
        }
        if (followLatest) _scrollToBottom();
      }
    } catch (_) {
      // 保留现有消息；实时刷新失败不打断聊天页。
      _reconcileAllLoaded = true;
      if (mounted && _scope.current && !_messagesLoadedOnce) {
        setState(() => _historyError = '消息加载失败，点击重试');
      }
    } finally {
      _loading = false;
      if (_refreshPending && mounted && _scope.current) {
        _refreshPending = false;
        unawaited(_loadMessages());
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (!mounted || !_scope.current || _loadingOlder || !_hasMoreHistory) {
      return;
    }
    final ids =
        _messages.map((m) => (m['id'] as num?)?.toInt()).whereType<int>();
    if (ids.isEmpty) return;
    final oldest = ids.reduce((a, b) => a < b ? a : b);
    setState(() {
      _loadingOlder = true;
      _historyError = null;
    });
    try {
      final data = await _messageSync.page(beforeId: oldest);
      if (!mounted || !_scope.current) return;
      final position =
          _scrollController.hasClients ? _scrollController.position : null;
      final oldExtent = position?.maxScrollExtent ?? 0;
      final oldOffset = position?.pixels ?? 0;
      setState(() {
        final existingIds = _messages.map((m) => m['id']).toSet();
        final older = (data['list'] as List? ?? const [])
            .whereType<Map>()
            .where((m) => !existingIds.contains(m['id']))
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _messages.insertAll(0, older);
        _applyRecalledIds((data['recalledIds'] as List? ?? const [])
            .whereType<num>()
            .map((id) => id.toInt()));
        _hasMoreHistory = data['hasMore'] == true && older.isNotEmpty;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final current = _scrollController.position;
        _scrollController.jumpTo(
            (oldOffset + current.maxScrollExtent - oldExtent)
                .clamp(current.minScrollExtent, current.maxScrollExtent));
      });
    } catch (_) {
      if (mounted) setState(() => _historyError = '历史消息加载失败，点击重试');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _jumpToMessage(int id) async {
    if (_locatingMessage || !mounted || !_scope.current) return;
    _stickToLatest = false;
    setState(() => _locatingMessage = true);
    try {
      while (!_messages.any((message) => _messageId(message) == id) &&
          _hasMoreHistory &&
          mounted &&
          _scope.current) {
        final count = _messages.length;
        await _loadOlderMessages();
        if (_messages.length == count) break;
      }
      if (!mounted || !_scope.current) return;
      if (!_messages.any((message) => _messageId(message) == id)) {
        showAppToast(context, '该消息已删除或暂时无法加载');
        return;
      }
      setState(() => _highlightMessageId = id);
      await WidgetsBinding.instance.endOfFrame;
      final targetIndex =
          _messages.indexWhere((message) => _messageId(message) == id);
      var lower = 0.0;
      var upper = _scrollController.position.maxScrollExtent;
      for (var attempt = 0;
          attempt < 32 && mounted && _scope.current;
          attempt++) {
        final anchor = _messageLocationKeys[id.toString()]?.currentContext;
        if (anchor != null && anchor.mounted) {
          await Scrollable.ensureVisible(anchor,
              alignment: .35, duration: const Duration(milliseconds: 250));
          break;
        }
        final laidOut = <int>[];
        for (var index = 0; index < _messages.length; index++) {
          final key = _messages[index]['id']?.toString();
          if (_messageLocationKeys[key]?.currentContext != null) {
            laidOut.add(index);
          }
        }
        final offset = _scrollController.offset;
        if (laidOut.isNotEmpty && targetIndex < laidOut.first) upper = offset;
        if (laidOut.isNotEmpty && targetIndex > laidOut.last) lower = offset;
        final position = _scrollController.position;
        _scrollController.jumpTo(((lower + upper) / 2)
            .clamp(position.minScrollExtent, position.maxScrollExtent));
        await WidgetsBinding.instance.endOfFrame;
      }
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightMessageId = null);
      });
    } finally {
      if (mounted) setState(() => _locatingMessage = false);
    }
  }

  void _scrollToBottom() {
    if (_locatingMessage) return;
    if (mounted && _showNewMessages) setState(() => _showNewMessages = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<bool> _send({String? type, String? contentOverride}) async {
    if (!mounted || !_scope.current) return false;
    final draftAtSend = _controller.text;
    final quoteAtSend = _quotedMessage;
    final content = contentOverride ?? _controller.text.trim();
    if (!mounted || content.isEmpty || (_sending && contentOverride == null)) {
      return false;
    }
    if (content.runes.length > 2000) {
      showAppToast(context, '消息最多2000个字符，请分条发送');
      return false;
    }
    if (_chatSendBlocked) {
      showAppToast(context, '对方回复或与你互相关注后，才可以继续发送');
      return false;
    }
    if (_chatTextOnly && (type ?? 'text') != 'text') {
      showAppToast(context, '对方回复前只能发送文字消息');
      return false;
    }
    if (_chatTextOnly && content.characters.length > 80) {
      showAppToast(context, '对方回复前每条最多80个字');
      return false;
    }
    setState(() {
      _activeSends++;
      _sending = true;
    });
    try {
      final msgType = type ?? 'text';
      final requestData = <String, dynamic>{
        'type': msgType,
        'content': content,
        if (contentOverride == null && _quotedMessage?['id'] != null)
          'quoteMessageId': _quotedMessage!['id'],
      };
      final data = await _scope.post(
        '/api/im/conversation/${widget.conversationId}/message',
        data: requestData,
      );
      if (data['id'] is! num) {
        throw StateError('发送结果无效');
      }
      if (mounted && _scope.current) {
        setState(() {
          final item = Map<String, dynamic>.from(data);
          final permission = item.remove('chatPermission');
          if (permission is Map) {
            _chatPermission = Map<String, dynamic>.from(permission);
          }
          final messageId = item['id'];
          if (messageId != null) {
            _messages.removeWhere((message) => message['id'] == messageId);
          }
          _messages.add(item);
          _applyRecalledIds(const <int>[]);
          _messages.sort(compareChatMessages);
        });
        if (contentOverride == null && _controller.text == draftAtSend) {
          _controller.clear();
          if (identical(_quotedMessage, quoteAtSend)) {
            setState(() => _quotedMessage = null);
          }
        }
        _scrollToBottom();
      }
      return true;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['data'] is Map && mounted) {
        setState(
          () =>
              _chatPermission = Map<String, dynamic>.from(body['data'] as Map),
        );
      }
      final message = body is Map ? body['message']?.toString() : null;
      if (mounted) showAppToast(context, message ?? '发送失败');
      return false;
    } catch (_) {
      if (mounted) showAppToast(context, '发送失败，请重试');
      return false;
    } finally {
      _activeSends--;
      if (mounted) setState(() => _sending = _activeSends > 0);
    }
  }

  void _quoteMessage(Map<String, dynamic> message) {
    if (!_scope.current || isChatMessageRecalled(message)) return;
    final content = message['content']?.toString().trim() ?? '';
    if (content.isEmpty) return;
    setState(() => _quotedMessage = message);
    _focusNode.requestFocus();
  }

  Future<void> _showMessageActions(
    Map<String, dynamic> message,
    bool isMe,
    BuildContext anchorContext,
  ) async {
    if (!_scope.current ||
        _multiSelecting ||
        _messageActionBusy ||
        message['id'] == null ||
        isChatMessageRecalled(message)) {
      return;
    }
    final renderBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null || !renderBox.hasSize) return;
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭消息操作',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 130),
      pageBuilder: (_, __, ___) => _MessageActionOverlay(
        anchor: topLeft & renderBox.size,
        alignRight: isMe,
        canRecall: canRecallChatMessage(message, _myUserId),
      ),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(animation),
          alignment: isMe ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        ),
      ),
    );
    if (!mounted || !_scope.current || isChatMessageRecalled(message)) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messageCopyText(message)));
      if (mounted) showAppToast(context, '已复制');
    } else if (action == 'quote') {
      _quoteMessage(message);
    } else if (action == 'forward') {
      await _forwardMessages({_messageId(message)!});
    } else if (action == 'favorite') {
      await _favoriteMessages({_messageId(message)!});
    } else if (action == 'delete') {
      await _deleteMessages({_messageId(message)!});
    } else if (action == 'recall') {
      await _recallMessage(message);
    } else if (action == 'multi') {
      _enterMultiSelect(message);
    }
  }

  int? _messageId(Map<String, dynamic> message) =>
      (message['id'] as num?)?.toInt();

  void _applyRecalledIds(Iterable<int> ids) {
    _recalledMessageIds.addAll(ids);
    for (final message in _messages) {
      if (isChatMessageRecalled(message) && _messageId(message) != null) {
        _recalledMessageIds.add(_messageId(message)!);
      }
    }
    redactRecalledChatMessages(_messages, _recalledMessageIds);
    _selectedMessageIds.removeAll(_recalledMessageIds);
    if (_quotedMessage != null &&
        (_recalledMessageIds.contains(_messageId(_quotedMessage!)) ||
            isChatMessageRecalled(_quotedMessage!))) {
      _quotedMessage = null;
    }
  }

  Future<void> _recallMessage(Map<String, dynamic> message) async {
    if (!mounted || !_scope.current || _messageActionBusy) return;
    if (!canRecallChatMessage(message, _myUserId)) {
      showAppToast(context, '仅可撤回自己两分钟内发送的消息');
      return;
    }
    final id = _messageId(message)!;
    setState(() => _messageActionBusy = true);
    try {
      final data = await _scope.post(
          '/api/im/conversation/${widget.conversationId}/message/$id/recall');
      if (!mounted || !_scope.current) return;
      if (data['messageId'] != id || data['recalled'] != true) {
        throw const ImWorkflowFailure('撤回结果待确认，请刷新聊天记录');
      }
      setState(() => _applyRecalledIds({id}));
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, imFailureMessage(error, '撤回未确认，请刷新后重试'));
        unawaited(_loadMessages());
      }
    } finally {
      if (mounted && _scope.current) setState(() => _messageActionBusy = false);
    }
  }

  String _messageCopyText(Map<String, dynamic> message) {
    final content = message['content']?.toString() ?? '';
    if (message['type'] == 'text' || message['type'] == 'image') return content;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        return decoded['url']?.toString() ??
            decoded['content']?.toString() ??
            content;
      }
    } catch (_) {}
    return content;
  }

  String _actionError(Object error, String fallback) {
    return imFailureMessage(error, fallback);
  }

  void _enterMultiSelect(Map<String, dynamic> message) {
    final id = _messageId(message);
    if (id == null) return;
    setState(() {
      _multiSelecting = true;
      _selectedMessageIds
        ..clear()
        ..add(id);
      _showEmoji = false;
      _showMorePanel = false;
    });
    _focusNode.unfocus();
  }

  void _leaveMultiSelect() {
    if (!mounted) return;
    setState(() {
      _multiSelecting = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(Map<String, dynamic> message) {
    if (isChatMessageRecalled(message)) return;
    final id = _messageId(message);
    if (id == null) return;
    setState(() {
      if (!_selectedMessageIds.add(id)) _selectedMessageIds.remove(id);
    });
  }

  Future<int?> _pickForwardConversation() async {
    try {
      final data = await _scope.get('/api/im/conversations');
      final conversations = imResponseList(data);
      if (!mounted || !_scope.current) return null;
      if (conversations.isEmpty) {
        showAppToast(context, '暂无可转发的会话');
        return null;
      }
      return await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('转发到'),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          content: SizedBox(
            width: 320,
            height: MediaQuery.sizeOf(context).height * .48,
            child: ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = conversations[index];
                final id = (item['conversationId'] as num?)?.toInt();
                final title = item['title']?.toString() ?? '会话';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      item['type'] == 'group'
                          ? Icons.groups_rounded
                          : Icons.person_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  title:
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    item['lastMessage']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: id == null
                      ? null
                      : () => Navigator.pop(dialogContext, id),
                );
              },
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, _actionError(error, '会话加载失败'));
      }
      return null;
    }
  }

  Future<void> _forwardMessages(Set<int> messageIds) async {
    if (!_scope.current || messageIds.isEmpty || _messageActionBusy) return;
    setState(() => _messageActionBusy = true);
    try {
      final targetId = await _pickForwardConversation();
      if (targetId == null || !mounted || !_scope.current) return;
      if (messageIds.any(_recalledMessageIds.contains)) {
        throw const ImWorkflowFailure('所选消息已撤回，请重新选择');
      }
      await _scope.post(
        '/api/im/conversation/$targetId/messages/forward',
        data: {'messageIds': messageIds.toList()},
      );
      if (!mounted || !_scope.current) return;
      showAppToast(context, '已转发');
      if (_multiSelecting) _leaveMultiSelect();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, _actionError(error, '转发失败'));
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy = false);
    }
  }

  Future<void> _favoriteMessages(Set<int> messageIds) async {
    if (!_scope.current || messageIds.isEmpty || _messageActionBusy) return;
    setState(() => _messageActionBusy = true);
    try {
      await _scope.post(
        '/api/im/conversation/${widget.conversationId}/messages/favorite',
        data: {'messageIds': messageIds.toList()},
      );
      if (!mounted || !_scope.current) return;
      showAppToast(context, messageIds.length == 1 ? '已收藏' : '已收藏所选消息');
      if (_multiSelecting) _leaveMultiSelect();
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, _actionError(error, '收藏失败'));
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy = false);
    }
  }

  Future<void> _deleteMessages(Set<int> messageIds) async {
    if (!_scope.current || messageIds.isEmpty || _messageActionBusy) return;
    setState(() => _messageActionBusy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除消息'),
          content: Text(messageIds.length == 1
              ? '仅从你的聊天记录中删除这条消息？'
              : '仅从你的聊天记录中删除所选 ${messageIds.length} 条消息？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_scope.current) return;
      await _scope.post(
        '/api/im/conversation/${widget.conversationId}/messages/delete',
        data: {'messageIds': messageIds.toList()},
      );
      if (!mounted || !_scope.current) return;
      setState(() {
        _messages.removeWhere(
          (message) => messageIds.contains(_messageId(message)),
        );
        _multiSelecting = false;
        _selectedMessageIds.clear();
      });
      showAppToast(context, '已删除');
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, _actionError(error, '删除失败'));
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy = false);
    }
  }

  Future<void> _loadMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted && _scope.current) {
      setState(() => _myUserId = prefs.getInt(AppConstants.keyUserId));
    }
  }

  Future<Map<String, dynamic>?> _uploadMedia(File file, String filename) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: filename),
    });
    final response = await apiClient.post('/api/config/upload', data: formData);
    final raw = (response.data as Map?)?['data'];
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (data['url']?.toString().isEmpty ?? true) {
      throw Exception(
          (response.data as Map?)?['message']?.toString() ?? '媒体上传失败');
    }
    for (final key in const ['url', 'coverUrl']) {
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty && !value.startsWith('http')) {
        data[key] =
            '${apiClient.options.baseUrl}${value.startsWith('/') ? '' : '/'}$value';
      }
    }
    return data;
  }

  Future<void> _pickAndSendMedia() async {
    if (_sending) return;
    if (_chatTextOnly) {
      showAppToast(context, '对方回复前只能发送文字消息');
      return;
    }
    final pendingId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final xfile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (!mounted) return;
      if (xfile == null) return;
      setState(() {
        _messages.add({
          'localId': pendingId,
          'type': 'image',
          'content': xfile.path,
          'localPath': xfile.path,
          'sending': false,
          'senderId': _myUserId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      });
      _scrollToBottom();
      showAppToast(context, '正在发送图片');
      await _sendPendingMedia(pendingId);
    } catch (e) {
      _removePendingMessage(pendingId);
      if (mounted) showAppToast(context, _mediaUploadError(e, '选择图片失败，请重试'));
    }
  }

  Future<void> _sendPendingMedia(String pendingId) async {
    final index = _messages.indexWhere((item) => item['localId'] == pendingId);
    if (!mounted || index < 0 || _messages[index]['sending'] == true) return;
    final pending = _messages[index];
    setState(() {
      pending['sending'] = true;
      pending['failed'] = false;
    });
    var sent = false;
    try {
      var url = pending['uploadedUrl']?.toString();
      if (url == null || url.isEmpty) {
        final uploadFile =
            await _fileForUpload(XFile(pending['localPath'] as String));
        final uploaded = await _uploadMedia(uploadFile, 'chat_image.jpg');
        url = uploaded?['url']?.toString();
        if (url == null || url.isEmpty) throw StateError('上传失败');
        pending['uploadedUrl'] = url;
      }
      if (!mounted) return;
      sent = await _send(type: 'image', contentOverride: url);
      if (sent) _removePendingMessage(pendingId);
    } catch (error) {
      if (mounted) {
        showAppToast(context, _mediaUploadError(error, '图片发送失败，请重试'));
      }
    } finally {
      if (mounted && !sent) {
        final followLatest = _stickToLatest;
        setState(() {
          pending['sending'] = false;
          pending['failed'] = true;
        });
        if (followLatest) _scrollToBottom();
      }
    }
  }

  Future<File> _fileForUpload(XFile xfile) async {
    final original = File(xfile.path);
    if (await original.exists()) {
      return ImageUtils.compressPostImage(original);
    }
    final bytes = await xfile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('无法读取所选图片');
    }
    final fallback = File(
      '${Directory.systemTemp.path}/chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await fallback.writeAsBytes(bytes, flush: true);
    return ImageUtils.compressPostImage(fallback);
  }

  void _removePendingMessage(String pendingId) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((item) => item['localId'] == pendingId);
    });
  }

  Future<void> _startVoiceRecording() async {
    if (_recording || _recordStarting || _sending || _chatTextOnly) return;
    setState(() {
      _recordStarting = true;
      _recordReleased = false;
    });
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) setState(() => _recordStarting = false);
      if (mounted) showAppToast(context, '需要麦克风权限才能发送语音');
      return;
    }
    if (!mounted || _recordReleased) {
      if (mounted) setState(() => _recordStarting = false);
      return;
    }
    try {
      await _audioRecorder.invokeMethod<void>('startRecording');
      if (!mounted) {
        await _audioRecorder.invokeMethod<void>('cancelRecording');
        return;
      }
      setState(() {
        _recordStarting = false;
        _recording = true;
        _recordStartedAt = DateTime.now();
      });
      if (_recordReleased) {
        await _stopVoiceRecording();
        return;
      }
      unawaited(HapticFeedback.mediumImpact());
      _recordLimitTimer?.cancel();
      _recordLimitTimer = Timer(
        const Duration(seconds: 60),
        () => _stopVoiceRecording(),
      );
    } on PlatformException catch (_) {
      if (mounted) setState(() => _recordStarting = false);
      if (mounted) showAppToast(context, '录音启动失败，请重试');
    }
  }

  Future<void> _stopVoiceRecording() async {
    _recordReleased = true;
    if (_recordStarting) return;
    if (!_recording) return;
    _recordLimitTimer?.cancel();
    final started = _recordStartedAt;
    setState(() => _recording = false);
    try {
      final path = await _audioRecorder.invokeMethod<String>('stopRecording');
      final elapsed = started == null
          ? 0
          : DateTime.now().difference(started).inMilliseconds;
      final duration = (elapsed / 1000).ceil().clamp(1, 60);
      if (path == null || elapsed < 650) {
        if (path != null) {
          await File(path).delete().catchError((_) => File(path));
        }
        if (mounted) showAppToast(context, '说话时间太短');
        return;
      }
      final uploaded = await _uploadMedia(
        File(path),
        'voice.m4a',
      );
      await File(path).delete().catchError((_) => File(path));
      final url = uploaded?['url']?.toString();
      if (url == null || url.isEmpty) throw const FormatException();
      await _send(
        type: 'voice',
        contentOverride: jsonEncode({'url': url, 'duration': duration}),
      );
    } catch (e) {
      if (mounted) showAppToast(context, _mediaUploadError(e, '语音发送失败，请重试'));
    } finally {
      _recordStartedAt = null;
    }
  }

  void _onRecordPointerDown(PointerDownEvent event) {
    if (_recordPointerId != null) return;
    _recordPointerId = event.pointer;
    _startVoiceRecording();
  }

  String _mediaUploadError(Object error, String fallback) {
    if (error is DioException && error.response?.data is Map) {
      final message = (error.response!.data as Map)['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    }
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty || message.startsWith('DioException')
        ? fallback
        : message;
  }

  void _onRecordPointerUp(PointerEvent event) {
    if (_recordPointerId != event.pointer) return;
    _recordPointerId = null;
    _stopVoiceRecording();
  }

  Future<void> _showCallOptions() async {
    final peerId = widget.peerUserId;
    if (peerId == null || widget.conversationType != 'single') {
      if (mounted) showAppToast(context, '群聊暂不支持一对一通话');
      return;
    }
    try {
      final response = await apiClient.get(
        '/api/im/conversation/${widget.conversationId}/info',
      );
      final data = (response.data as Map?)?['data'] as Map?;
      if (data?['mutualFollow'] != true) {
        if (mounted) showAppToast(context, '语音和视频通话仅限互相关注的好友');
        return;
      }
    } on DioException catch (_) {
      if (mounted) showAppToast(context, '暂时无法确认好友关系');
      return;
    }
    if (!mounted) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('视频通话'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('语音通话'),
              onTap: () => Navigator.pop(context, 'voice'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (mode != null && mounted) await _startCall(mode);
  }

  Future<void> _startCall(String mode) async {
    if (!_scope.current || _startingCall) return;
    final peerId = widget.peerUserId;
    if (peerId == null) return;
    _startingCall = true;
    try {
      final response = await _scope.post(
        '/api/im/social-call',
        data: {
          'conversationId': widget.conversationId,
          'targetUserId': peerId,
          'mode': mode,
        },
      );
      if (!mounted || !_scope.current) return;
      final call = response;
      final id = (call['id'] as num?)?.toInt();
      if (id == null) return;
      await SocialCallOverlay.instance.open(id, call: call);
      if (mounted && _scope.current) await _loadMessages();
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? (error.response?.data as Map)['message']?.toString()
          : null;
      if (mounted && _scope.current) {
        showAppToast(context, message ?? '暂时无法发起通话');
      }
    } on ImWorkflowFailure catch (error) {
      if (mounted && _scope.current) showAppToast(context, error.message);
    } finally {
      _startingCall = false;
    }
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() {
      _showEmoji = !_showEmoji;
      _showMorePanel = false;
      _voiceMode = false;
    });
  }

  void _showMoreActions() {
    if (_chatTextOnly) {
      showAppToast(context, '对方回复前只能发送文字消息');
      return;
    }
    _focusNode.unfocus();
    setState(() {
      _showEmoji = false;
      _showMorePanel = !_showMorePanel;
    });
  }

  Future<void> _openSingleChatSettings() async {
    final peerUserId = widget.peerUserId;
    if (peerUserId == null) return;
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => SingleChatSettingsPage(
          conversationId: widget.conversationId,
          peerUserId: peerUserId,
          initialTitle: _displayTitle,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'search') {
      await _openChatSearch();
      return;
    }
    if (result == 'deleted') {
      Navigator.of(context).pop(true);
      return;
    }
    if (result is int) {
      await _jumpToMessage(result);
      return;
    }
    await _loadAppearance();
    await _loadSingleDisplayInfo();
    await _loadMessages();
  }

  Future<void> _openGroupChatSettings() async {
    final leftOrDissolved = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => ChatInfoPage(
          conversationId: widget.conversationId,
          title: widget.title,
          onUpdated: _loadMessages,
        ),
      ),
    );
    if (!mounted) return;
    if (leftOrDissolved == 'search') {
      await _openChatSearch();
      return;
    }
    if (leftOrDissolved is int) {
      await _jumpToMessage(leftOrDissolved);
      return;
    }
    if (leftOrDissolved == true) {
      Navigator.of(context).pop(true);
      return;
    }
    await _loadAppearance();
    await _loadMessages();
  }

  Widget _buildMorePanel() {
    return Container(
      height: 138,
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
        22,
        18,
        22,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _morePanelItem(
              Icons.photo_library_outlined,
              '图片',
              _pickAndSendMedia,
            ),
          ),
          Expanded(
            child: _morePanelItem(
              Icons.phone_in_talk_outlined,
              '通话',
              _showCallOptions,
            ),
          ),
          Expanded(
            child: _morePanelItem(
              Icons.card_giftcard_rounded,
              '礼物',
              _openGiftSheet,
            ),
          ),
          Expanded(
            child: _morePanelItem(
              Icons.auto_awesome_rounded,
              '装扮',
              _openStyleOrderSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _morePanelItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        setState(() => _showMorePanel = false);
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 27),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
          appBar: AppBar(title: const Text('聊天')),
          body: const Center(child: Text(imSessionChangedMessage)));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: widget.peerUserId != null
            ? GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: widget.peerUserId!),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_displayTitle, style: AppTextStyles.titleMedium),
                    if (widget.isPeerMaster) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          '名师',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : Text(_displayTitle, style: AppTextStyles.titleMedium),
        actions: [
          if (widget.conversationType == 'group')
            IconButton(
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textPrimary,
              ),
              onPressed: _openGroupChatSettings,
            )
          else
            IconButton(
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textPrimary,
              ),
              onPressed: _openSingleChatSettings,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _focusNode.unfocus();
                      if (_showEmoji || _showMorePanel) {
                        setState(() {
                          _showEmoji = false;
                          _showMorePanel = false;
                        });
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: _appearance.backgroundDecoration,
                          ),
                        ),
                        NotificationListener<ScrollUpdateNotification>(
                          onNotification: (notification) {
                            if (notification.dragDetails != null &&
                                notification.metrics.pixels < 80) {
                              unawaited(_loadOlderMessages());
                            }
                            return false;
                          },
                          child: ListView.builder(
                            key: const ValueKey('chat-message-list'),
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: _messages.length + 1,
                            itemBuilder: (context, rowIndex) {
                              if (rowIndex == 0) {
                                return SizedBox(
                                  height: 44,
                                  child: _loadingOlder
                                      ? const Center(
                                          child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2)))
                                      : TextButton(
                                          key: const ValueKey(
                                              'chat-load-history'),
                                          onPressed: _hasMoreHistory
                                              ? _loadOlderMessages
                                              : _historyError != null
                                                  ? _loadMessages
                                                  : null,
                                          child: Text(_historyError ??
                                              (_hasMoreHistory
                                                  ? '加载更早消息'
                                                  : '没有更多消息了')),
                                        ),
                                );
                              }
                              final index = rowIndex - 1;
                              final msg = _messages[index];
                              final isMe = _myUserId != null &&
                                  msg['senderId'] == _myUserId;

                              // 只有时间间隔超过5分钟才显示时间
                              bool showTime = true;
                              if (index > 0) {
                                final prevMsg = _messages[index - 1];
                                final currTime =
                                    DateTime.parse(msg['createdAt']);
                                final prevTime = DateTime.parse(
                                  prevMsg['createdAt'],
                                );
                                if (currTime.difference(prevTime).inMinutes <
                                    5) {
                                  showTime = false;
                                }
                              }

                              final messageKey =
                                  (msg['id'] ?? msg['localId'] ?? index)
                                      .toString();
                              return KeyedSubtree(
                                key: ValueKey('chat-message-$messageKey'),
                                child: ColoredBox(
                                  key: _messageLocationKeys.putIfAbsent(
                                      messageKey, GlobalKey.new),
                                  color: _messageId(msg) == _highlightMessageId
                                      ? AppColors.primary.withValues(alpha: .12)
                                      : Colors.transparent,
                                  child: _buildMessageItem(msg, isMe, showTime),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showNewMessages)
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: FilledButton.tonalIcon(
                              onPressed: _scrollToBottom,
                              icon: const Icon(Icons.arrow_downward_rounded,
                                  size: 18),
                              label: const Text('有新消息'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_multiSelecting)
                  _buildMultiSelectBar()
                else
                  _buildInputArea(),
                if (!_multiSelecting && _showEmoji) _buildEmojiPanel(),
                if (!_multiSelecting && _showMorePanel) _buildMorePanel(),
              ],
            ),
          ),
          if (_virtualEffects.active case final effect?)
            Positioned.fill(
              child: VirtualGiftEffect(
                key: ObjectKey(effect),
                payload: effect,
                onCompleted: () => _completeVirtualEffect(effect),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmojiPanel() {
    const emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👋',
      '🤚',
      '🙏',
      '💪',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
    ];
    return Container(
      height: 250,
      color: AppColors.surface,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () {
            _controller.text += emojis[index];
            _controller.selection = TextSelection.collapsed(
              offset: _controller.text.length,
            );
          },
          child: Center(
            child: Text(emojis[index], style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg, bool isMe, bool showTime) {
    final createdAt = msg['createdAt'] as String? ?? '';
    final messageId = _messageId(msg);
    final actionKeyName =
        (msg['id'] ?? msg['localId'] ?? 'message-${identityHashCode(msg)}')
            .toString();
    final actionKey = _messageActionKeys.putIfAbsent(
      actionKeyName,
      GlobalKey.new,
    );
    void showActions() {
      final anchorContext = actionKey.currentContext;
      if (anchorContext != null) {
        unawaited(_showMessageActions(msg, isMe, anchorContext));
      }
    }

    Widget messageContent;
    if (isChatMessageRecalled(msg)) {
      messageContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
            isMe
                ? '你撤回了一条消息'
                : widget.conversationType == 'single'
                    ? '对方撤回了一条消息'
                    : '${msg['nickname'] ?? '成员'}撤回了一条消息',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
      );
    } else if (msg['type'] == 'nudge') {
      messageContent = Container(
        key: actionKey,
        child: GestureDetector(
          onTap: showActions,
          onLongPress: showActions,
          child: _NudgeMessage(content: msg['content'] as String? ?? ''),
        ),
      );
    } else {
      messageContent = Column(
        children: [
          Container(
            key: actionKey,
            child: _Bubble(
              isMe: isMe,
              content: msg['content'] as String? ?? '',
              msgType: msg['type'] as String? ?? 'text',
              avatarUrl: msg['avatarUrl'] as String?,
              nickname: msg['nickname'] as String?,
              senderId: (msg['senderId'] as num?)?.toInt(),
              messageId: messageId,
              localMediaPath: msg['localPath'] as String?,
              sending: msg['sending'] == true,
              quote: msg['quote'] is Map
                  ? Map<String, dynamic>.from(msg['quote'] as Map)
                  : null,
              myBubbleColor: _appearance.myBubbleColor,
              peerBubbleColor: _appearance.peerBubbleColor,
              onLongPress: showActions,
              onCallTap: widget.conversationType == 'single'
                  ? (mode) => _startCall(mode)
                  : null,
              onAvatarTap: !isMe
                  ? () {
                      unawaited(AppHaptics.nudge());
                      unawaited(
                        _send(
                          type: 'nudge',
                          contentOverride:
                              '拍了拍${msg['nickname']?.toString() ?? '对方'}的头',
                        ),
                      );
                    }
                  : null,
            ),
          ),
          if (msg['failed'] == true && msg['localId'] is String)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _sendPendingMedia(msg['localId'] as String),
                icon: const Icon(Icons.error_outline, size: 18),
                label: const Text('发送失败，点击重试'),
              ),
            ),
          if (isMe && msg['read'] == true)
            const SizedBox(
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 44, top: 2),
                  child: _ReadReceipt(),
                ),
              ),
            ),
        ],
      );
    }

    if (_multiSelecting && !isChatMessageRecalled(msg)) {
      final selected =
          messageId != null && _selectedMessageIds.contains(messageId);
      messageContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: messageId == null ? null : () => _toggleMessageSelection(msg),
        child: ColoredBox(
          color: selected
              ? AppColors.primaryLight.withValues(alpha: .72)
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: IgnorePointer(
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) {},
                    activeColor: AppColors.primaryDark,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              Expanded(child: AbsorbPointer(child: messageContent)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              AppDateUtils.formatChatSection(createdAt),
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: AppColors.textHint,
                letterSpacing: 0.5,
              ),
            ),
          ),
        messageContent,
      ],
    );
  }

  Widget _buildMultiSelectBar() {
    final count = _selectedMessageIds.length;
    Widget action(IconData icon, String label, VoidCallback? onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: onTap == null
                      ? AppColors.textHint
                      : AppColors.primaryDark,
                ),
                const SizedBox(height: 3),
                Text(label, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            action(Icons.close_rounded, '取消', _leaveMultiSelect),
            action(
              Icons.forward_rounded,
              '转发',
              count == 0 || _messageActionBusy
                  ? null
                  : () => _forwardMessages(Set<int>.from(_selectedMessageIds)),
            ),
            action(
              Icons.bookmark_border_rounded,
              '收藏',
              count == 0 || _messageActionBusy
                  ? null
                  : () => _favoriteMessages(Set<int>.from(_selectedMessageIds)),
            ),
            action(
              Icons.delete_outline_rounded,
              '删除',
              count == 0 || _messageActionBusy
                  ? null
                  : () => _deleteMessages(Set<int>.from(_selectedMessageIds)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: !_showEmoji && !_showMorePanel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_quotedMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '引用 ${_quotedMessage!['nickname'] ?? '用户'}：${_quotedMessage!['content'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消引用',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _quotedMessage = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            if (_chatPermission?['limited'] == true) ...[
              Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: _chatSendBlocked
                        ? AppColors.textHint
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _chatSendBlocked
                          ? '已发送 3 条，等待对方回复或互相关注后可继续'
                          : '对方回复前还可发送 ${_chatRemaining ?? 0} 条文字，每条最多80字',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _chatSendBlocked
                            ? AppColors.textHint
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildInputIconBtn(
                  icon: _voiceMode
                      ? Icons.keyboard_alt_outlined
                      : Icons.record_voice_over_outlined,
                  onPressed: _chatTextOnly
                      ? null
                      : () {
                          _focusNode.unfocus();
                          setState(() {
                            _voiceMode = !_voiceMode;
                            _showEmoji = false;
                            _showMorePanel = false;
                          });
                        },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _voiceMode
                      ? Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _onRecordPointerDown,
                          onPointerUp: _onRecordPointerUp,
                          onPointerCancel: _onRecordPointerUp,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _recording || _recordStarting
                                  ? AppColors.primary.withValues(alpha: .13)
                                  : AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _recording || _recordStarting
                                    ? AppColors.primary
                                    : AppColors.divider.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              _recordStarting
                                  ? '准备录音…'
                                  : _recording
                                      ? '松开发送'
                                      : '按住说话',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: _recording || _recordStarting
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          constraints: const BoxConstraints(
                            minHeight: 42,
                            maxHeight: 120,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.divider.withValues(alpha: 0.55),
                            ),
                          ),
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            readOnly: _chatSendBlocked,
                            maxLength: _chatTextOnly ? 80 : null,
                            maxLines: 4,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            onTap: () {
                              if (_showEmoji || _showMorePanel) {
                                setState(() {
                                  _showEmoji = false;
                                  _showMorePanel = false;
                                });
                              }
                            },
                            style: AppTextStyles.bodyMedium,
                            decoration: InputDecoration(
                              hintText:
                                  _chatSendBlocked ? '等待对方回复…' : '写下想说的话...',
                              hintStyle: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textHint,
                              ),
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 2),
                _buildInputIconBtn(
                  icon: _showEmoji
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined,
                  onPressed: _toggleEmoji,
                ),
                const SizedBox(width: 2),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (_, value, __) {
                    final hasText = !_voiceMode && value.text.trim().isNotEmpty;
                    if (!hasText) {
                      return _buildInputIconBtn(
                        icon: Icons.add_circle_outline_rounded,
                        onPressed: _chatTextOnly ? null : _showMoreActions,
                      );
                    }
                    if (_sending) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }
                    return IconButton(
                      tooltip: '发送',
                      onPressed: _chatSendBlocked ? null : () => _send(),
                      icon: Icon(
                        Icons.send_rounded,
                        color: _chatSendBlocked
                            ? AppColors.textHint
                            : AppColors.primary,
                        size: 27,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputIconBtn({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: onPressed == null
                ? AppColors.textHint.withValues(alpha: 0.45)
                : AppColors.textSecondary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.anchor,
    required this.alignRight,
    required this.canRecall,
  });

  final Rect anchor;
  final bool alignRight;
  final bool canRecall;

  static const _actions = <(String, String, IconData)>[
    ('copy', '复制', Icons.copy_rounded),
    ('forward', '转发', Icons.forward_rounded),
    ('favorite', '收藏', Icons.bookmark_border_rounded),
    ('delete', '删除', Icons.delete_outline_rounded),
    ('multi', '多选', Icons.playlist_add_check_rounded),
    ('quote', '引用', Icons.format_quote_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final actions = [
      ..._actions,
      if (canRecall) ('recall', '撤回', Icons.undo_rounded)
    ];
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 24).clamp(0, 246).toDouble();
          final height = canRecall ? 194.0 : 136.0;
          final preferredLeft = alignRight ? anchor.right - width : anchor.left;
          final left = preferredLeft
              .clamp(12.0, constraints.maxWidth - width - 12.0)
              .toDouble();
          final safeTop = media.padding.top + 8;
          final top = (anchor.top - height - 8)
              .clamp(safeTop, constraints.maxHeight - height - 8)
              .toDouble();
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: Material(
                  color: const Color(0xFF16545D),
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: GridView.count(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: 1.45,
                    children: actions
                        .map(
                          (action) => InkWell(
                            onTap: () => Navigator.of(context).pop(action.$1),
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(action.$3, color: Colors.white, size: 23),
                                const SizedBox(height: 3),
                                Text(
                                  action.$2,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.isMe,
    required this.content,
    required this.myBubbleColor,
    required this.peerBubbleColor,
    this.msgType = 'text',
    this.avatarUrl,
    this.nickname,
    this.senderId,
    this.messageId,
    this.quote,
    this.localMediaPath,
    this.sending = false,
    this.onAvatarTap,
    this.onLongPress,
    this.onCallTap,
  });
  final bool isMe;
  final String content;
  final String msgType;
  final String? avatarUrl;
  final String? nickname;
  final int? senderId;
  final int? messageId;
  final Map<String, dynamic>? quote;
  final String? localMediaPath;
  final bool sending;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onLongPress;
  final void Function(String)? onCallTap;
  final Color myBubbleColor;
  final Color peerBubbleColor;

  Map<String, dynamic> _mediaPayload() {
    try {
      final decoded = jsonDecode(content);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Widget _brokenImagePlaceholder() {
    return Container(
      width: 100,
      height: 100,
      color: AppColors.cardBackground,
      child: const Icon(
        Icons.broken_image,
        color: AppColors.textHint,
      ),
    );
  }

  Widget _buildGiftPreview(BuildContext context, String contentJson) {
    Map<String, dynamic> gift = {};
    try {
      final decoded = jsonDecode(contentJson);
      if (decoded is Map) gift = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final imageUrl = virtualGiftMediaUrl(gift, thumbnail: true);
    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          barrierColor: Colors.black54,
          builder: (dialogContext) => VirtualGiftEffect(
              payload: gift,
              preview: true,
              onCompleted: () {
                if (dialogContext.mounted &&
                    ModalRoute.of(dialogContext)?.isCurrent == true) {
                  Navigator.of(dialogContext).pop();
                }
              }),
        );
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFCF6), Color(0xFFF0F8F8)],
          ),
          borderRadius: const BorderRadius.all(Radius.circular(17)),
          border: Border.all(color: const Color(0xFFE3D4AA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x160E4C47),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: imageUrl.isEmpty
                  ? Center(
                      child: Text(
                        gift['iconText']?.toString() ?? '礼',
                        style: const TextStyle(
                          color: Color(0xFFB4934E),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFFC3A562),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gift['giftName']?.toString() ?? '一份心意',
                    style: const TextStyle(
                      color: Color(0xFF244542),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '心意礼物  ×${gift['quantity'] ?? 1}',
                    style: const TextStyle(
                      color: Color(0xFF8C9895),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostPreview(BuildContext context, String contentJson) {
    Map<String, dynamic> item;
    try {
      item = jsonDecode(contentJson) as Map<String, dynamic>? ?? {};
    } catch (_) {
      return Text(
        contentJson,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }
    final mediaUrls = item['mediaUrls'] as List<dynamic>?;
    final mediaCoverUrls = item['mediaCoverUrls'] as List<dynamic>?;
    final isVideo = item['mediaType'] == 'video';
    final thumbUrl = isVideo
        ? (mediaCoverUrls != null && mediaCoverUrls.isNotEmpty
            ? mediaCoverUrls[0].toString()
            : null)
        : (mediaUrls != null && mediaUrls.isNotEmpty
            ? mediaUrls[0].toString()
            : null);
    final postId = (item['postId'] as num?)?.toInt();
    final likeCount = (item['likeCount'] as num?)?.toInt() ?? 0;
    final postContent = item['content'] as String? ?? '';
    return GestureDetector(
      onTap: () {
        if (postId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PostDetailPage(postId: postId, initialItem: item),
            ),
          );
        }
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thumbUrl != null && thumbUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported),
                    ),
                    if (isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$likeCount',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              AspectRatio(
                aspectRatio: 1,
                child: PostTextCoverPreview(
                  content: postContent,
                  maxLines: 5,
                  compact: true,
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 14),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(
                    Icons.article_outlined,
                    size: 14,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '查看帖子',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePreview(BuildContext context, String contentJson) {
    Map<String, dynamic> item;
    try {
      item = jsonDecode(contentJson) as Map<String, dynamic>? ?? {};
    } catch (_) {
      return const Text('个人主页');
    }
    final rawUserId = item['userId'] ?? item['id'] ?? item['targetUserId'];
    final userId = rawUserId is num
        ? rawUserId.toInt()
        : int.tryParse(rawUserId?.toString() ?? '');
    final nickname = item['nickname']?.toString() ?? '玄遇用户';
    final avatarUrl = item['avatarUrl']?.toString();
    final intro = item['intro']?.toString().trim() ?? '';
    final teamTitle = item['teamTitle']?.toString().trim() ?? '';
    return InkWell(
      onTap: userId == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(userId: userId),
                ),
              ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0FCFA), Color(0xFFFFF1F6)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Text(nickname.isNotEmpty ? nickname[0] : '?')
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                      if (teamTitle.isNotEmpty)
                        Text(
                          teamTitle,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (intro.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                intro,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.favorite_outline_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '查看 TA 的玄遇主页',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRoomPreview(BuildContext context, String contentJson) {
    Map<String, dynamic> item;
    try {
      item = jsonDecode(contentJson) as Map<String, dynamic>? ?? {};
    } catch (_) {
      return const Text('语音房邀请');
    }
    final roomId = (item['roomId'] as num?)?.toInt();
    final title = item['title']?.toString().trim() ?? '';
    final category = item['category']?.toString().trim() ?? '';
    final ownerNickname = item['ownerNickname']?.toString().trim() ?? '';
    final onlineCount = (item['onlineCount'] as num?)?.toInt() ?? 0;
    final isMaster = item['roomType'] == 'master';
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: roomId == null
          ? null
          : () async {
              final scope = ApiSessionScope();
              try {
                final response =
                    await scope.get('/api/consultation/rooms/$roomId');
                if (!context.mounted || !scope.current) return;
                final room = response.data['data'];
                if (room is! Map ||
                    !['live', 'paused'].contains(room['status'])) {
                  showAppToast(context, '派对已经结束');
                  return;
                }
                final opened = VoiceRoomOverlayController.instance.open(roomId);
                if (!opened) showAppToast(context, '请先退出当前语音房');
              } on DioException catch (error) {
                if (!context.mounted || !scope.current) return;
                showAppToast(
                    context,
                    [404, 410].contains(error.response?.statusCode)
                        ? '派对已经结束'
                        : '暂时无法进入派对，请重试');
              } catch (_) {
                if (context.mounted && scope.current) {
                  showAppToast(context, '暂时无法进入派对，请重试');
                }
              }
            },
      child: Container(
        width: MediaQuery.of(context).size.width * .64,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17292D), Color(0xFF22323A)],
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0x3349D4CB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFF071011),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFF38D6CF),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  isMaster ? '在线名师' : '免费派对',
                  style: const TextStyle(
                    color: Color(0xFF6FE3DC),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Text(
                  '邀请你加入',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              title.isEmpty ? '一起来语音房聊聊吧' : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      ownerNickname,
                      category,
                    ].where((value) => value.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                ),
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: Color(0xFFFFB06B),
                ),
                Text(
                  '$onlineCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                const Text(
                  '进入',
                  style: TextStyle(
                    color: Color(0xFF6FE3DC),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: Color(0xFF6FE3DC),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLargeImage(BuildContext context, String heroTag) {
    final local = localMediaPath;
    final image = (local != null && local.isNotEmpty)
        ? Image.file(File(local), fit: BoxFit.contain)
        : Image.network(content, fit: BoxFit.contain);
    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.black.withValues(alpha: 0.95),
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: heroTag,
                  child: image,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
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

  @override
  Widget build(BuildContext context) {
    final avatar = GestureDetector(
      onDoubleTap: onAvatarTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1.5),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryLight,
          backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
              ? NetworkImage(avatarUrl!)
              : null,
          child: avatarUrl == null || avatarUrl!.isEmpty
              ? Text(
                  (nickname ?? '?')[0],
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
      ),
    );

    final toolShare =
        msgType == 'text' ? ToolShareMessage.tryParse(content) : null;
    Widget messageContent;
    final callMode = content.startsWith('【视频通话】')
        ? 'video'
        : content.startsWith('【语音通话】')
            ? 'voice'
            : null;
    if (msgType == 'text' && callMode != null && onCallTap != null) {
      messageContent = GestureDetector(
        onTap: () => onCallTap!(callMode),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              callMode == 'video'
                  ? Icons.videocam_outlined
                  : Icons.phone_outlined,
              size: 20),
          const SizedBox(width: 8),
          Flexible(
              child: Text(callMessageLabel(content),
                  style: AppTextStyles.bodyMedium)),
        ]),
      );
    } else if (toolShare != null) {
      messageContent = ToolSharePreview(message: toolShare);
    } else if (msgType == 'image') {
      final heroTag = 'chat_img_${messageId ?? Object.hash(content, senderId)}';
      final width = MediaQuery.of(context).size.width * 0.5;
      const height = 180.0;
      final local = localMediaPath;
      Widget image;
      if (local != null && local.isNotEmpty) {
        image = Image.file(
          File(local),
          fit: BoxFit.cover,
          width: width,
          height: height,
          errorBuilder: (_, __, ___) => _brokenImagePlaceholder(),
        );
      } else {
        image = Image.network(
          content,
          fit: BoxFit.cover,
          width: width,
          height: height,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _brokenImagePlaceholder(),
        );
      }
      if (sending) {
        image = Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: 0.72, child: image),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          ],
        );
      }
      messageContent = GestureDetector(
        onTap: () => _showLargeImage(context, heroTag),
        child: Hero(
          tag: heroTag,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: 240,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: image,
            ),
          ),
        ),
      );
    } else if (msgType == 'video') {
      final media = _mediaPayload();
      final url = media['url']?.toString() ?? '';
      final coverUrl = media['coverUrl']?.toString() ?? '';
      messageContent = GestureDetector(
        onTap: url.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VideoPlayerPage(videoUrl: url),
                  ),
                ),
        child: Container(
          width: MediaQuery.sizeOf(context).width * .48,
          height: 190,
          decoration: BoxDecoration(
            color: const Color(0xFF20262A),
            borderRadius: BorderRadius.circular(12),
            image: coverUrl.isEmpty
                ? null
                : DecorationImage(
                    image: NetworkImage(coverUrl),
                    fit: BoxFit.cover,
                  ),
          ),
          child: const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      );
    } else if (msgType == 'voice') {
      final media = _mediaPayload();
      messageContent = _ChatVoiceMessage(
        url: media['url']?.toString() ?? '',
        duration: (media['duration'] as num?)?.toInt() ?? 1,
        isMe: isMe,
      );
    } else if (msgType == 'post') {
      messageContent = _buildPostPreview(context, content);
    } else if (msgType == 'profile') {
      messageContent = _buildProfilePreview(context, content);
    } else if (msgType == 'voice_room') {
      messageContent = _buildVoiceRoomPreview(context, content);
    } else if (msgType == 'gift') {
      messageContent = _buildGiftPreview(context, content);
    } else if (msgType == 'style_order') {
      messageContent = _StyleOrderMessageCard(contentJson: content, isMe: isMe);
    } else {
      messageContent = Text(
        callMode == null ? content : callMessageLabel(content),
        style: AppTextStyles.bodyMedium.copyWith(
          color: isMe ? AppColors.textPrimary : AppColors.textPrimary,
          height: 1.4,
        ),
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: (msgType == 'image' ||
              msgType == 'video' ||
              msgType == 'post' ||
              msgType == 'profile' ||
              msgType == 'voice_room' ||
              msgType == 'gift' ||
              msgType == 'style_order')
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: msgType == 'image' || msgType == 'video'
            ? Colors.transparent
            : isMe
                ? myBubbleColor
                : peerBubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // 松约束让短文字气泡按内容收缩，长消息仍受 maxWidth 限制。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote != null)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '引用 ${quote!['nickname'] ?? '用户'}：${quote!['content'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          Padding(
            padding:
                quote == null ? EdgeInsets.zero : const EdgeInsets.only(top: 5),
            child: messageContent,
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start, // 顶部对齐
        children: [
          if (!isMe) ...[avatar, const SizedBox(width: 8)],
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe && nickname != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    nickname!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: msgType == 'text' ? onLongPress : null,
                onLongPress: onLongPress,
                child: bubble,
              ),
            ],
          ),
          if (isMe) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt();

  @override
  Widget build(BuildContext context) {
    return Text(
      '已读',
      style: AppTextStyles.bodySmall.copyWith(
        fontSize: 10,
        color: AppColors.textHint,
        height: 1,
      ),
    );
  }
}

class _NudgeMessage extends StatelessWidget {
  const _NudgeMessage({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.touch_app_rounded,
            size: 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 5),
          Text(
            content,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textHint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatVoiceMessage extends StatefulWidget {
  const _ChatVoiceMessage({
    required this.url,
    required this.duration,
    required this.isMe,
  });

  final String url;
  final int duration;
  final bool isMe;

  @override
  State<_ChatVoiceMessage> createState() => _ChatVoiceMessageState();
}

class _ChatVoiceMessageState extends State<_ChatVoiceMessage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.isEmpty) return;
    if (_playing) {
      await _player.stop();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration.clamp(1, 60);
    final width = 78.0 + duration * 2.0;
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width.clamp(90, 198),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!widget.isMe)
              Icon(
                _playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: AppColors.textPrimary,
                size: 23,
              ),
            if (!widget.isMe) const SizedBox(width: 8),
            Text(
              '$duration″',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.isMe) const SizedBox(width: 8),
            if (widget.isMe)
              Icon(
                _playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: AppColors.textPrimary,
                size: 23,
              ),
          ],
        ),
      ),
    );
  }
}

class _StyleOrderMessageCard extends StatefulWidget {
  const _StyleOrderMessageCard({required this.contentJson, required this.isMe});

  final String contentJson;
  final bool isMe;

  @override
  State<_StyleOrderMessageCard> createState() => _StyleOrderMessageCardState();
}

class _StyleOrderMessageCardState extends State<_StyleOrderMessageCard> {
  late Map<String, dynamic> _order;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    try {
      final decoded = jsonDecode(widget.contentJson);
      _order = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      _order = {};
    }
  }

  Future<void> _pay() async {
    final orderNo = _order['orderNo']?.toString() ?? '';
    if (_paying || orderNo.isEmpty) return;
    setState(() => _paying = true);
    try {
      final response = await apiClient.post(
        '/api/virtual/style-orders/$orderNo/pay',
      );
      final body = response.data;
      if (body is! Map || body['code'] != 0) {
        throw StateError(body is Map ? '${body['message'] ?? '付款失败'}' : '付款失败');
      }
      if (!mounted) return;
      setState(() => _order['status'] = 'completed');
      showAppToast(context, '装扮已到账，可在装扮中心使用');
    } on DioException catch (error) {
      final body = error.response?.data;
      if (mounted) {
        showAppToast(
          context,
          body is Map ? '${body['message'] ?? '付款失败，请稍后重试'}' : '付款失败，请稍后重试',
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Map<String, dynamic> _avatarArtworkConfig(String productCode) {
    final local = VirtualAvatarCatalog.productAssetCodes.containsKey(
      productCode,
    );
    if (local) return VirtualAvatarCatalog.configForProductCode(productCode);

    // 新头像馆商品使用云端成品素材。旧消息只有商品编号，没有保存短时
    // OSS 地址，因此通过稳定代理地址取图，避免全部回落到同一张默认头像。
    final base = apiClient.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final url = productCode.isEmpty
        ? ''
        : '$base/api/virtual/avatar-products/${Uri.encodeComponent(productCode)}/asset?kind=thumbnail';
    return {
      ...VirtualAvatarCatalog.initialConfig(),
      'assetCode': 'remote_$productCode',
      'categoryCode': 'remote',
      'assetUrl': url,
      'thumbnailUrl': url,
      'safeCircleApproved': true,
      'safeCircleInsetPercent': 13,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pending = _order['status']?.toString() == 'pending';
    final request = _order['mode']?.toString() == 'request';
    final name = _order['productName']?.toString().trim();
    final productType = _order['productType']?.toString() ?? 'background';
    final productCode = _order['productCode']?.toString() ?? '';
    final price = double.tryParse('${_order['price']}') ?? 0;
    return Container(
      width: 248,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE9F8F4), Color(0xFFF8FCFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFB9E2D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 112,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: productType == 'avatar'
                  ? VirtualAvatarArtwork(
                      config: _avatarArtworkConfig(productCode),
                      thumbnail: true,
                      fit: BoxFit.contain,
                    )
                  : ProfileBackgroundArtwork(
                      backgroundId: productCode,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFCCEEE6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _order['productType']?.toString() == 'avatar'
                      ? Icons.face_retouching_natural
                      : Icons.wallpaper_rounded,
                  color: AppColors.primaryDark,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name?.isNotEmpty == true ? name! : '一份装扮',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2),
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pending
                ? (request && !widget.isMe
                    ? '请为 TA 代付款，装扮将直接到账给 TA'
                    : '代付款请求已发出，等待对方处理')
                : (request ? '已代 TA 付款，装扮已到账' : '装扮已送达，可前往装扮中心使用'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (pending && request && !widget.isMe) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: FilledButton(
                onPressed: _paying ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  padding: EdgeInsets.zero,
                ),
                child: _paying
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('代付款', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
