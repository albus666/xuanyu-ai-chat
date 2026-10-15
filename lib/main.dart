import 'features/message/special_care_message_sound_host.dart';
import 'features/message/social_call_overlay.dart';
import 'features/fortune/matched_voice_overlay.dart';
import 'features/consultation/consultation_call_overlay.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/app/bootstrap/startup_gate.dart';
import 'package:xuanyu/app/common/routers/names.dart';
import 'package:xuanyu/app/common/routers/pages.dart';
import 'package:xuanyu/app/common/style/theme.dart';
import 'package:xuanyu/app/global.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/removed_pet_data_cleanup.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/navigation/app_deep_link.dart';
import 'package:xuanyu/core/payment/apple_iap_service.dart';
import 'package:xuanyu/core/privacy/consent_services.dart';
import 'package:xuanyu/core/settings/app_settings_store.dart';
import 'package:xuanyu/core/utils/app_toast.dart';
import 'package:xuanyu/core/utils/android_media_picker.dart';
import 'package:xuanyu/core/update/app_update_host.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_host.dart';
import 'package:xuanyu/features/consultation/voice_room_overlay_controller.dart';
import 'package:xuanyu/features/consultation/consultation_incoming_call_host.dart';
import 'package:xuanyu/features/message/social_call_incoming_host.dart';
import 'package:xuanyu/features/merit/widgets/muyu_floating_overlay.dart';
import 'package:xuanyu/shared/widgets/global_edge_back_gesture.dart';

Future<void> main() async {
  await Global.init();
  configureAndroidMediaPicker();
  // Orientation is declared by each platform's native configuration. Keeping
  // iPad unlocked here avoids a launch-time orientation assertion on iPadOS
  // when the app is installed as a universal iPhone/iPad app.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_immersiveOverlay);
  final prefs = await SharedPreferences.getInstance();
  await RemovedPetDataCleanup.run(prefs);
  await AppSettingsStore.instance.initialize(prefs);
  const acceptedVersion =
      '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}';
  final canInitializeConsentServices =
      (prefs.getBool(AppConstants.keyAgreementAccepted) ?? false) &&
          prefs.getString(AppConstants.keyAgreementVersion) == acceptedVersion;
  final token = prefs.getString(AppConstants.keyToken);
  setupApiClientToken(token);
  AppleIapService.instance.initialize();
  Get.put(AuthState(prefs), permanent: true);
  ErrorWidget.builder = (_) => const _AppErrorFallback();

  runApp(const XuanyuApp());
  if (canInitializeConsentServices) {
    unawaited(_initializeConsentServicesAfterStartup());
  }
}

Future<void> _initializeConsentServicesAfterStartup() async {
  await StartupGate.ready;
  await initializeConsentDependentServices();
}

/// 状态栏 / 导航栏透明沉浸，内容色透出统一。
const SystemUiOverlayStyle _immersiveOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

final GlobalKey<ScaffoldMessengerState> _appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final NavigatorObserver _routeUiCleanupObserver =
    _RouteUiCleanupObserver(_appMessengerKey);

class _RouteUiCleanupObserver extends NavigatorObserver {
  _RouteUiCleanupObserver(this.messengerKey);

  final GlobalKey<ScaffoldMessengerState> messengerKey;

  void _cleanup() {
    messengerKey.currentState?.removeCurrentSnackBar();
    dismissAllAppToasts();
    if (Get.isSnackbarOpen) Get.closeAllSnackbars();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _cleanup();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _cleanup();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _cleanup();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _cleanup();
  }
}

class _AppErrorFallback extends StatelessWidget {
  const _AppErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    size: 42,
                    color: Color(0xFF24BFB7),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '页面暂时没有加载好',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      Get.key.currentState?.pushNamedAndRemoveUntil(
                        RouteNames.root,
                        (_) => false,
                      );
                    },
                    child: const Text('返回首页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final socialCallBackNavigatorObserver = SocialCallBackNavigatorObserver();
final consultationBackNavigatorObserver = ConsultationBackNavigatorObserver();
final matchedVoiceBackNavigatorObserver = MatchedVoiceBackNavigatorObserver();

class XuanyuApp extends StatelessWidget {
  const XuanyuApp({super.key});

  Future<void> _handleEdgeBack() async {
    final matchedCall = MatchedVoiceOverlay.instance;
    if (matchedCall.roomId != null && !matchedCall.minimized) {
      await matchedCall.handleBack?.call();
      return;
    }
    final socialCall = SocialCallOverlay.instance;
    if (socialCall.callId != null && !socialCall.minimized) {
      await socialCall.handleBack?.call();
      return;
    }
    final privateCall = ConsultationCallOverlay.instance;
    if (privateCall.sessionId != null && !privateCall.minimized) {
      await privateCall.handleBack?.call();
      return;
    }
    final voiceRoom = VoiceRoomOverlayController.instance;
    if (voiceRoom.hasActiveRoom && !voiceRoom.minimized) {
      await voiceRoom.handleSystemBack();
      return;
    }
    final navigator = Get.key.currentState;
    if (navigator != null && navigator.canPop()) {
      await navigator.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _immersiveOverlay,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return GetMaterialApp(
            title: '玄遇',
            debugShowCheckedModeBanner: false,
            theme: ShellTheme.light(),
            scaffoldMessengerKey: _appMessengerKey,
            navigatorObservers: [
              _routeUiCleanupObserver,
              voiceRoomBackNavigatorObserver,
              matchedVoiceBackNavigatorObserver,
              socialCallBackNavigatorObserver,
              consultationBackNavigatorObserver,
            ],
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: RouteNames.root,
            getPages: RoutePages.list,
            builder: (context, child) => AnimatedBuilder(
              animation: AppSettingsStore.instance,
              builder: (context, _) {
                final media = MediaQuery.of(context);
                final settings = AppSettingsStore.instance;
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(
                        settings.boolValue('largerText') ? 1.12 : 1),
                    disableAnimations: settings.boolValue('reduceMotion'),
                  ),
                  child: AppUpdateHost(
                    navigatorKey: Get.key,
                    child: MuyuFloatingOverlayHost(
                      child: GlobalEdgeBackGesture(
                        onBack: _handleEdgeBack,
                        child: ConsultationIncomingCallHost(
                          child: MatchedVoiceOverlayHost(
                            rootNavigatorKey: Get.key,
                            child: ConsultationCallOverlayHost(
                              child: SocialCallOverlayHost(
                                child: SocialCallIncomingHost(
                                  child: VoiceRoomOverlayHost(
                                      child: AppDeepLinkHost(
                                    child: SpecialCareMessageSoundHost(
                                      child: child ?? const SizedBox.shrink(),
                                    ),
                                  )),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
