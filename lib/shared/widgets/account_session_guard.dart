import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';

/// 旧账号页面不展示旧内容，也不能在切号后继续写入新账号。
mixin AccountSessionGuard<T extends StatefulWidget> on State<T> {
  final accountSession = ApiSessionScope();

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  Widget get accountChangedPage => Scaffold(
        appBar: AppBar(title: const Text('账号已切换')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
}
