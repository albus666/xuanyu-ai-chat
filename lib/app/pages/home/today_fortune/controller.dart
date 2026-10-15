import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/core/network/account_profile_requests.dart';
import 'package:xuanyu/core/network/api_session_scope.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/core/utils/daily_energy_score.dart';

class FortuneSection {
  final String title;
  final String content;
  const FortuneSection(this.title, this.content);
}

class TodayFortuneController extends GetxController {
  TodayFortuneController();

  List<String> dates = <String>['今日', '明日', '后日'];
  int selectedDate = 0;
  List<DailyEnergyDay> _days = const <DailyEnergyDay>[];

  List<FortuneSection> sections = <FortuneSection>[
    const FortuneSection('今日分析', '加载中…'),
  ];

  DailyEnergyScore energyScore = DailyEnergyScore.compute();
  List<String> scoreBasis = const <String>[];
  String? birthDate;
  String? birthTime;

  bool _readyFromCache = false;
  final _scope = ApiSessionScope();

  @override
  void onClose() {
    apiSessionChanges.removeListener(_accountChanged);
    super.onClose();
  }

  void _accountChanged() {
    _days = [];
    birthDate = birthTime = null;
    energyScore = DailyEnergyScore.compute();
    scoreBasis = [];
    dates = ['今日'];
    selectedDate = 0;
    sections = [const FortuneSection('提示', apiSessionChangedMessage)];
    update(['fortune']);
  }

  @override
  void onInit() {
    super.onInit();
    apiSessionChanges.addListener(_accountChanged);
    // 会话内或首页已加载过：同步命中，避免再次进入仍显示「加载中」
    final session = DailyEnergyLoader.sessionCacheForToday();
    if (session != null) {
      _applyResult(session);
      _readyFromCache = true;
    }
  }

  @override
  Future<void> onReady() async {
    super.onReady();
    if (_readyFromCache) return;
    await _load();
  }

  Future<void> _load() async {
    if (!_scope.current || isClosed) return;
    final cached = await DailyEnergyLoader.refreshFromLocalCache();
    if (!_scope.current || isClosed) return;
    if (cached != null) {
      _applyResult(cached);
      _readyFromCache = true;
      return;
    }

    sections = <FortuneSection>[const FortuneSection('今日分析', '加载中…')];
    update(['fortune']);

    unawaited(_loadProfileBirth());
    final result = await DailyEnergyLoader.load(
      birthDate: birthDate,
      birthTime: birthTime,
    );
    if (!_scope.current || isClosed) return;
    if (result.hasError) {
      _applyResult(result, errorText: result.errorMessage);
      return;
    }
    _applyResult(result);
    _readyFromCache = true;
  }

  Future<void> _loadProfileBirth() async {
    try {
      final res = await AccountProfileRequests.fetch(_scope);
      if (isClosed || !_scope.current) return;
      final data = (res.data as Map?)?['data'] as Map?;
      birthDate = (data?['birthDate'] as String?)?.trim();
      birthTime = (data?['birthTime'] as String?)?.trim();
    } on DioException catch (_) {
    } on ApiSessionChangedException catch (_) {}
  }

  void _applyResult(DailyEnergyResult result, {String? errorText}) {
    _days = result.days.isNotEmpty
        ? result.days.take(7).toList(growable: false)
        : <DailyEnergyDay>[
            DailyEnergyDay(
              score: result.score,
              content: result.content,
              date: result.date,
            ),
          ];
    dates = List<String>.generate(
      _days.length,
      (index) => _dayLabel(index, _days[index].date),
    );
    selectedDate = 0;
    _showSelectedDay(errorText: errorText);
  }

  void _showSelectedDay({String? errorText}) {
    if (_days.isEmpty) return;
    final day = _days[selectedDate];
    final content = day.content.trim();
    sections = <FortuneSection>[
      FortuneSection(
        '今日分析',
        errorText?.isNotEmpty == true
            ? errorText!
            : content.isEmpty
                ? '暂无能量解读，请稍后再试。'
                : content,
      ),
    ];
    energyScore = day.score;
    scoreBasis = day.scoreBasis;
    update(['fortune']);
  }

  void selectDate(int idx) {
    if (idx == selectedDate || idx < 0 || idx >= dates.length) return;
    selectedDate = idx;
    _showSelectedDay();
  }

  String get selectedDateText => _days.isEmpty
      ? DailyEnergyLoader.todayString()
      : _days[selectedDate].date;

  String dateTextAt(int index) {
    if (index < 0 || index >= _days.length) return '';
    final parts = _days[index].date.split('-');
    return parts.length == 3 ? '${parts[1]}.${parts[2]}' : _days[index].date;
  }

  String _dayLabel(int index, String rawDate) {
    if (index == 0) return '今日';
    if (index == 1) return '明日';
    if (index == 2) return '后日';
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return '第${index + 1}日';
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '周${weekdays[parsed.weekday - 1]}';
  }
}
