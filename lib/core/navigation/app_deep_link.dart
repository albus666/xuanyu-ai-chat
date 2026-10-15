import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../app/bootstrap/auth_state.dart';
import '../../app/bootstrap/startup_gate.dart';
import '../../features/message/joinable_groups_page.dart';
import '../network/api_client.dart';
import '../utils/app_toast.dart';

@visibleForTesting
int? groupConversationIdFromDeepLink(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'xuanyu' ||
      uri.host.toLowerCase() != 'group' ||
      uri.pathSegments.length != 1) {
    return null;
  }
  final id = int.tryParse(uri.pathSegments.single);
  return id != null && id > 0 ? id : null;
}

/// 接收 Android/iOS 原生层转交的二维码链接，并在隐私门禁、启动页和登录完成后落地。
class AppDeepLinkHost extends StatefulWidget {
  const AppDeepLinkHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppDeepLinkHost> createState() => _AppDeepLinkHostState();
}

class _AppDeepLinkHostState extends State<AppDeepLinkHost> {
  static const _channel = MethodChannel('xuanyu/deep_links');

  late final AuthState _auth;
  late final VoidCallback _removeAuthListener;
  int? _pendingConversationId;
  int? _activeConversationId;
  bool _routing = false;
  bool _loginTipShown = false;

  @override
  void initState() {
    super.initState();
    _auth = Get.find<AuthState>();
    _removeAuthListener = _auth.addListener(_onAuthChanged);
    apiSessionChanges.addListener(_onSessionChanged);
    _channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readInitialLink());
  }

  @override
  void dispose() {
    _removeAuthListener();
    apiSessionChanges.removeListener(_onSessionChanged);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onLink') {
      await _queueLink(call.arguments?.toString());
    }
  }

  Future<void> _readInitialLink() async {
    try {
      final value = await _channel.invokeMethod<String>('getInitialLink');
      await _queueLink(value);
    } on MissingPluginException {
      // Web/桌面测试环境没有原生通道，不影响正常启动。
    } on PlatformException {
      // 原生链接读取失败不能阻断应用主流程。
    }
  }

  Future<void> _queueLink(String? raw) async {
    final id = groupConversationIdFromDeepLink(raw);
    if (id == null || id == _activeConversationId) return;
    _pendingConversationId = id;
    _loginTipShown = false;
    await _openPendingLink();
  }

  void _onSessionChanged() {
    if (_pendingConversationId == null) return;
    unawaited(_openPendingLink());
  }

  void _onAuthChanged() {
    if (_pendingConversationId == null) return;
    unawaited(_openPendingLink());
  }

  Future<void> _openPendingLink() async {
    if (!mounted || _routing || _pendingConversationId == null) return;
    await StartupGate.ready;
    if (!mounted || _routing || _pendingConversationId == null) return;

    if (!_auth.agreementAccepted) return;
    if (!_auth.hasToken || apiClient.options.headers['Authorization'] == null) {
      if (!_loginTipShown) {
        _loginTipShown = true;
        showGlobalAppToast('请先登录，登录后将继续打开群聊或部落');
      }
      return;
    }

    final navigator = Get.key.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLink());
      return;
    }
    final id = _pendingConversationId!;
    _pendingConversationId = null;
    _activeConversationId = id;
    _routing = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => JoinableGroupsPage(initialConversationId: id),
        ),
      );
    } finally {
      _routing = false;
      _activeConversationId = null;
      if (_pendingConversationId != null) unawaited(_openPendingLink());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
