import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/daily_energy_loader.dart';
import 'package:xuanyu/core/utils/daily_energy_score.dart';

void main() {
  test('daily emotion requires every field and formats four distinct blocks',
      () {
    final insight = DailyEmotionInsight.fromMap(<String, dynamic>{
      'tone': '心里容易无缘由地绷紧，但外在仍会维持正常节奏。',
      'pressureLevel': '偏高',
      'pressureSource': '对时限和失控的预判，会让压力先于明确事件出现。',
      'expression': '语速可能变快，耐心下降，也更想尽快把事情处理完。',
      'regulation': '先确认真正有时限的一件事，再用走动和慢呼吸降低警觉。',
    });

    expect(insight, isNotNull);
    expect(insight!.displayText, contains('情绪底色'));
    expect(insight.displayText, contains('压力感受 · 偏高'));
    expect(insight.displayText, contains('可能表现'));
    expect(insight.displayText, contains('调节方式'));
    expect(insight.displayText.split('\n\n'), hasLength(4));
  });

  test('daily emotion rejects incomplete API content', () {
    expect(
      DailyEmotionInsight.fromMap(<String, dynamic>{
        'tone': '只有一句情绪描述',
      }),
      isNull,
    );
  });

  test('offline score is neutral instead of date hash fluctuation', () {
    final first = DailyEnergyScore.compute(
      birthDate: '1990-01-01',
      birthTime: '12:00',
      forDate: DateTime(2026, 9, 16),
    );
    final second = DailyEnergyScore.compute(
      birthDate: '1990-01-01',
      birthTime: '12:00',
      forDate: DateTime(2026, 9, 17),
    );

    // The existing calibrated placeholder is 74; it must stay independent of date.
    expect(first.overall, 74);
    expect(first.toBarItems().map((item) => item.value), everyElement(74));
    expect(second.overall, first.overall);
  });
}
