import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/fortune/pulse_signal_analyzer.dart';

void main() {
  test('手指未正确放置时不显示测量进度', () {
    final analyzer = PulseSignalAnalyzer(measurementSeconds: 30);
    final snapshot =
        analyzer.add(timeMs: 1000, value: 100, fingerCovered: false);
    expect(snapshot.stage, PulseCaptureStage.positioning);
    expect(snapshot.progress, 0);
  });

  test('稳定周期信号通过质量门控后才进入测量', () {
    final analyzer = PulseSignalAnalyzer(measurementSeconds: 30);
    PulseSignalSnapshot? snapshot;
    for (var i = 0; i < 140; i++) {
      final seconds = i / 10;
      final value = 110 + 9 * math.sin(2 * math.pi * 1.2 * seconds);
      snapshot =
          analyzer.add(timeMs: i * 100, value: value, fingerCovered: true);
    }
    expect(snapshot, isNotNull);
    expect(snapshot!.stage, PulseCaptureStage.measuring);
    expect(snapshot.progress, greaterThan(0));
    expect(snapshot.bpm, inInclusiveRange(65, 80));
  });

  test('完整测量转为频率脉象参考并明确质量分级', () {
    const measurement = PulseMeasurement(
      averageBpm: 72,
      minimumBpm: 68,
      maximumBpm: 76,
      rhythmVariation: 4,
      signalQuality: 88,
      durationSeconds: 45,
    );

    expect(measurement.rateAttribute, '脉率平和');
    expect(measurement.traditionalRateReference, '平脉');
    expect(measurement.rhythmAttribute, '脉律较齐');
    expect(measurement.qualityGrade, 'A');
    expect(measurement.toJson()['algorithmVersion'], 'ppg-v3-tcm-rate-rhythm');
  });
}
