import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xuanyu/app/common/index.dart';
import 'package:xuanyu/core/config/app_content_config.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/account_profile_requests.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/profile/destiny_archive_repository.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/core/utils/daily_energy_score.dart';
import 'package:xuanyu/features/fortune/constitution_test_page.dart';
import 'package:xuanyu/features/fortune/fengshui_page.dart' show FengshuiPage;

class GridEntry {
  final String label;
  final String iconAsset;
  final String? routeName;
  final IconData? iconData;
  const GridEntry(this.label, this.iconAsset, [this.routeName, this.iconData]);
}

class HomeIndexController extends GetxController {
  HomeIndexController();

  static const GridEntry partnerPortraitEntry = GridEntry(
    '伴侣画像',
    '',
    RouteNames.partnerPortrait,
    Icons.blur_circular_rounded,
  );

  DailyEnergyScore energyScore = DailyEnergyScore.compute();
  bool loadingEnergy = true;
  String? energyPreview;
  String? birthDate;
  String? birthTime;
  String? homeBackgroundUrl;
  double galaxyRevolutionSeconds = 420;

  static const int gridColumns = 5;
  static const int gridRows = 2;
  static const int gridItemsPerPage = gridColumns * gridRows;

  // 首页快捷入口：每页固定两行、每行五个，多出的入口横向翻页。
  final List<GridEntry> gridEntries = const [
    GridEntry('八字排盘', ImageAssets.iconBazi, RouteNames.homeBazi),
    GridEntry('紫微斗数', ImageAssets.iconQiandao, RouteNames.homeZiwei),
    GridEntry(
      '星座星盘',
      '',
      RouteNames.homeAstrology,
      Icons.blur_circular_rounded,
    ),
    GridEntry('七政四余', '', RouteNames.homeQizheng, Icons.brightness_7_outlined),
    GridEntry('生肖印记', 'assets/zodiac/dragon.webp', RouteNames.zodiac),
    GridEntry('住宅分析', ImageAssets.iconFengshui),
    GridEntry('体质测试', ImageAssets.iconTizhi),
    partnerPortraitEntry,
    GridEntry('使用建议', '', RouteNames.suggestions, Icons.feedback_outlined),
  ];
  bool _openingGridEntry = false;
  int _loadVersion = 0;

  @override
  void onInit() {
    super.onInit();
    apiSessionChanges.addListener(_accountChanged);
    AppContentConfig.changes.addListener(_applyGalaxyConfig);
    _applyGalaxyConfig();
  }

  @override
  void onClose() {
    apiSessionChanges.removeListener(_accountChanged);
    AppContentConfig.changes.removeListener(_applyGalaxyConfig);
    _loadVersion++;
    super.onClose();
  }

  void _accountChanged() {
    _loadVersion++;
    birthDate = birthTime = energyPreview = homeBackgroundUrl = null;
    energyScore = DailyEnergyScore.compute();
    loadingEnergy = false;
    update(['home_index']);
  }

  @override
  void onReady() {
    super.onReady();
    if (isClosed) return;
    _loadGalaxyConfig();
    loadDailyEnergy();
    unawaited(Future<void>.delayed(
      const Duration(milliseconds: 900),
      _warmArchiveCard,
    ));
  }

  Future<void> _warmArchiveCard() async {
    if (isClosed) return;
    final scope = ApiSessionScope();
    try {
      final snapshot = await DestinyArchiveRepository.load();
      final context = Get.context;
      if (isClosed || !scope.current || context == null || !context.mounted) {
        return;
      }
      final asset = snapshot.assetPath;
      if (asset != null) {
        await precacheImage(AssetImage(asset), context, onError: (_, __) {});
      }
    } catch (_) {
      // 后台预热失败由匹配页重试，不影响首页。
    }
  }

  /// 打开 App / 进入首页：当天有本地缓存则用缓存，否则请求 AI 一次并写入本地。
  Future<void> loadDailyEnergy({bool forceRefresh = false}) async {
    if (isClosed) return;
    final scope = ApiSessionScope();
    final version = ++_loadVersion;
    bool current() => !isClosed && scope.current && version == _loadVersion;
    // Reading today's local energy must not wait for a profile round trip.
    loadingEnergy = energyPreview == null;
    update(['home_index']);
    unawaited(_loadProfileBirth(scope));
    final result = await DailyEnergyLoader.load(
      forceRefresh: forceRefresh,
      birthDate: birthDate,
      birthTime: birthTime,
    );
    if (!current()) return;
    energyScore = result.score;
    energyPreview = _previewContent(result.content);
    loadingEnergy = false;
    if (!result.hasError) {
      DailyEnergyLoader.remember(result);
    }
    update(['home_index']);
  }

  Future<void> _loadGalaxyConfig() async {
    await AppContentConfig.load(force: true);
    if (!isClosed) _applyGalaxyConfig();
  }

  void _applyGalaxyConfig() {
    if (isClosed) return;
    final raw = AppContentConfig.section('home')['galaxyRevolutionSeconds'];
    final value = double.tryParse(raw?.toString() ?? '');
    galaxyRevolutionSeconds =
        value != null && value.isFinite && value >= 10 && value <= 3600
            ? value
            : 420;
    update(['home_index']);
  }

  Future<void> _loadProfileBirth(ApiSessionScope scope) async {
    try {
      final res = await AccountProfileRequests.fetch(scope);
      if (isClosed || !scope.current) return;
      final data = (res.data as Map?)?['data'] as Map?;
      birthDate = (data?['birthDate'] as String?)?.trim();
      birthTime = (data?['birthTime'] as String?)?.trim();
      final backgroundUrl = data?['homeBackgroundUrl']?.toString().trim();
      homeBackgroundUrl =
          backgroundUrl?.isNotEmpty == true ? backgroundUrl : null;
      update(['home_index']);
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
  }

  Future<void> refreshHomeBackground() async {
    AccountProfileRequests.invalidate();
    _loadGalaxyConfig();
    final scope = ApiSessionScope();
    try {
      final res = await AccountProfileRequests.fetch(scope);
      if (isClosed || !scope.current) return;
      final data = (res.data as Map?)?['data'] as Map?;
      final backgroundUrl = data?['homeBackgroundUrl']?.toString().trim();
      homeBackgroundUrl =
          backgroundUrl?.isNotEmpty == true ? backgroundUrl : null;
      update(['home_index']);
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
  }

  static String? _previewContent(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final oneLine = t.replaceAll(RegExp(r'\s+'), ' ');
    if (oneLine.length <= 36) return oneLine;
    return '${oneLine.substring(0, 36)}…';
  }

  Future<void> onGridTap(GridEntry e) async {
    if (_openingGridEntry) return;
    _openingGridEntry = true;
    try {
      if (e.routeName != null) {
        await Get.toNamed<dynamic>(e.routeName!);
        return;
      }
      if (e.label.contains('住宅') ||
          e.label.contains('环境') ||
          e.label.contains('风水')) {
        await Get.to<dynamic>(() => const FengshuiPage());
        return;
      }
      if (e.label.contains('体质') || e.label.contains('体制')) {
        await Get.to<dynamic>(() => const ConstitutionTestPage());
        return;
      }
      Get.snackbar('提示', '该功能暂不可用', snackPosition: SnackPosition.BOTTOM);
    } finally {
      _openingGridEntry = false;
    }
  }

  void onFortuneTap() => Get.toNamed(RouteNames.homeTodayFortune);

  void onHealthTap() => Get.toNamed(RouteNames.homeTodayHealth);

  void onMeritTap() => Get.toNamed(RouteNames.homeTodayMerit);

  void onWishPrayerTap() => Get.toNamed(RouteNames.homeWishPrayer);

  void onGoodwillEchoTap() => Get.toNamed(RouteNames.goodwillEcho);

  void onShopTap() => Get.toNamed(RouteNames.shop);
}
