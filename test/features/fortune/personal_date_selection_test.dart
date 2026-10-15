import 'package:flutter_test/flutter_test.dart';
import 'package:lunar/lunar.dart';
import 'package:xuanyu/features/fortune/almanac/personal_date_selection.dart';

void main() {
  const engine = PersonalDateSelectionEngine();
  const profile = PersonalAlmanacProfile(
    name: '测试档案',
    gans: ['甲', '丙', '戊', '壬'],
    zhis: ['辰', '寅', '午', '子'],
    supportiveElements: {'火', '土'},
  );

  test('未来30天推荐完整且按内部排序降序排列', () {
    final from = DateTime(2026, 8, 20);
    final results = engine.recommend(
      from: from,
      days: 30,
      purpose: PersonalDatePurpose.contract,
      profile: profile,
    );

    expect(results, hasLength(30));
    expect(
      results.every(
        (item) =>
            !item.date.isBefore(from) &&
            item.date.isBefore(from.add(const Duration(days: 30))),
      ),
      isTrue,
    );
    for (var i = 1; i < results.length; i++) {
      expect(results[i - 1].score, greaterThanOrEqualTo(results[i].score));
    }
  });

  test('与原局日支相冲时明确说明，不把冲突隐藏成总分', () {
    final date = _findDayBranch('子', DateTime(2026, 1, 1));
    final result = engine.evaluate(
      date: date,
      purpose: PersonalDatePurpose.meeting,
      profile: profile,
    );

    expect(result.reasons.any((reason) => reason.contains('原局日支相冲')), isTrue);
    expect(result.recommendedTimes.every((time) => !time.startsWith('子时')),
        isTrue);
  });

  test('喜用结果只作为可解释的助力项', () {
    final date = _findDayStemElement('火', DateTime(2026, 1, 1));
    final result = engine.evaluate(
      date: date,
      purpose: PersonalDatePurpose.communication,
      profile: profile,
    );

    expect(result.reasons.any((reason) => reason.contains('命盘助力方向')), isTrue);
    expect(result.reasons.any((reason) => reason.contains('解析')), isFalse);
    expect(result.score, inInclusiveRange(10, 95));
    expect(result.recommendedTimes.length, lessThanOrEqualTo(3));
  });

  test('双方事项采用较谨慎一方，不以平均分掩盖冲突', () {
    const second = PersonalAlmanacProfile(
      name: '对方档案',
      gans: ['乙', '丁', '辛', '癸'],
      zhis: ['巳', '卯', '未', '亥'],
      supportiveElements: {'水', '木'},
    );
    final date = _findDayBranch('子', DateTime(2026, 1, 1));
    final firstOnly = engine.evaluate(
      date: date,
      purpose: PersonalDatePurpose.wedding,
      profile: profile,
    );
    final secondOnly = engine.evaluate(
      date: date,
      purpose: PersonalDatePurpose.wedding,
      profile: second,
    );
    final pair = engine.evaluateForPair(
      date: date,
      purpose: PersonalDatePurpose.wedding,
      first: profile,
      second: second,
    );

    expect(
        pair.score,
        firstOnly.score < secondOnly.score
            ? firstOnly.score
            : secondOnly.score);
    expect(pair.reasons.any((reason) => reason.startsWith('测试档案：')), isTrue);
    expect(pair.reasons.any((reason) => reason.startsWith('对方档案：')), isTrue);
  });
}

DateTime _findDayBranch(String branch, DateTime from) {
  for (var offset = 0; offset < 60; offset++) {
    final date = from.add(Duration(days: offset));
    final ganZhi = Lunar.fromDate(DateTime(date.year, date.month, date.day, 12))
        .getDayInGanZhi();
    if (ganZhi.endsWith(branch)) return date;
  }
  throw StateError('60天内未找到日支$branch');
}

DateTime _findDayStemElement(String element, DateTime from) {
  const elements = {
    '甲': '木',
    '乙': '木',
    '丙': '火',
    '丁': '火',
    '戊': '土',
    '己': '土',
    '庚': '金',
    '辛': '金',
    '壬': '水',
    '癸': '水',
  };
  for (var offset = 0; offset < 10; offset++) {
    final date = from.add(Duration(days: offset));
    final ganZhi = Lunar.fromDate(DateTime(date.year, date.month, date.day, 12))
        .getDayInGanZhi();
    if (ganZhi.isNotEmpty && elements[ganZhi[0]] == element) return date;
  }
  throw StateError('10天内未找到$element日干');
}
