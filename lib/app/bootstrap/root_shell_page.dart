import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';
import 'package:xuanyu/app/bootstrap/startup_quote_page.dart';
import 'package:xuanyu/app/bootstrap/startup_quote_service.dart';
import 'package:xuanyu/app/pages/main/view.dart';
import 'package:xuanyu/app/pages/system/login/view.dart';
import 'package:xuanyu/features/auth/agreement_dialog.dart';

/// 应用根：协议 → 登录 → 主框架。个人资料由用户进入后按需完善。
class RootShellPage extends StatefulWidget {
  const RootShellPage({super.key});

  @override
  State<RootShellPage> createState() => _RootShellPageState();
}

class _RootShellPageState extends State<RootShellPage> {
  static bool _shownForCurrentProcess = false;

  Timer? _startupTimer;
  final Stopwatch _startupStopwatch = Stopwatch();
  late final AuthState _auth;
  late bool _showStartup;
  late String _startupQuote;

  @override
  void initState() {
    super.initState();
    _auth = Get.find<AuthState>();
    _showStartup = !_shownForCurrentProcess;
    _shownForCurrentProcess = true;
    _startupQuote = StartupQuoteService.cached(_auth.prefs);
    if (!_showStartup) StartupGate.markReady();
  }

  void _startStartupCountdown() {
    if (!mounted || !_showStartup || _startupTimer != null) return;
    _startupStopwatch.start();
    _startupTimer = Timer(startupDisplayDuration, _finishStartup);
  }

  Future<void> _refreshStartupQuote() async {
    if (!_auth.agreementAccepted) return;
    // 只缓存到下次启动，避免用户正在阅读时文字突然变化。
    await StartupQuoteService.refresh(_auth.prefs);
  }

  void _finishStartup() {
    if (!mounted || !_showStartup) return;
    _startupTimer?.cancel();
    _startupStopwatch.stop();
    StartupGate.markReady();
    if (kDebugMode) {
      debugPrint(
        'Startup overlay finished in '
        '${_startupStopwatch.elapsedMilliseconds}ms',
      );
    }
    setState(() => _showStartup = false);
    unawaited(_refreshStartupQuote());
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildAuthenticatedContent(),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : startupTransitionDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showStartup
                ? StartupQuotePage(
                    key: const ValueKey<String>('startup-quote'),
                    quote: _startupQuote,
                    onContinue: _finishStartup,
                    onReady: _startStartupCountdown,
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('startup-finished'),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthenticatedContent() {
    return GetBuilder<AuthState>(
      key: const ValueKey<String>('authenticated-content'),
      builder: (auth) {
        if (!auth.agreementAccepted) {
          return Scaffold(
            body: Center(
              child: AgreementDialog(
                onAccept: () {
                  auth.markAgreementAccepted();
                },
              ),
            ),
          );
        }
        if (!auth.hasToken) {
          return const ShellLoginPage();
        }
        return ShellMainPage(key: ValueKey<int?>(auth.userId));
      },
    );
  }
}
