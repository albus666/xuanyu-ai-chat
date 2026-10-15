import 'dart:math' as math;

enum PulseCaptureStage { positioning, stabilizing, measuring, completed }

class PulseMeasurement {
  const PulseMeasurement({
    required this.averageBpm,
    required this.minimumBpm,
    required this.maximumBpm,
    required this.rhythmVariation,
    required this.signalQuality,
    required this.durationSeconds,
  });

  final double averageBpm;
  final double minimumBpm;
  final double maximumBpm;
  final double rhythmVariation;
  final int signalQuality;
  final int durationSeconds;

  String get rateAttribute {
    if (averageBpm < 60) return '脉率偏缓';
    if (averageBpm > 90) return '脉率偏快';
    return '脉率平和';
  }

  String get traditionalRateReference {
    if (averageBpm < 60) return '迟脉';
    if (averageBpm > 90) return '数脉';
    return '平脉';
  }

  String get rhythmAttribute {
    if (rhythmVariation <= 6) return '脉律较齐';
    if (rhythmVariation <= 12) return '脉律有轻度波动';
    return '脉律波动较明显';
  }

  String get qualityGrade {
    if (signalQuality >= 85) return 'A';
    if (signalQuality >= 70) return 'B';
    return 'C';
  }

  Map<String, dynamic> toJson() => {
        'averageBpm': double.parse(averageBpm.toStringAsFixed(1)),
        'minimumBpm': double.parse(minimumBpm.toStringAsFixed(1)),
        'maximumBpm': double.parse(maximumBpm.toStringAsFixed(1)),
        'rhythmVariation': double.parse(rhythmVariation.toStringAsFixed(1)),
        'signalQuality': signalQuality,
        'durationSeconds': durationSeconds,
        'algorithmVersion': 'ppg-v3-tcm-rate-rhythm',
        'rateAttribute': rateAttribute,
        'traditionalRateReference': traditionalRateReference,
        'rhythmAttribute': rhythmAttribute,
        'qualityGrade': qualityGrade,
      };
}

class PulseSignalSnapshot {
  const PulseSignalSnapshot({
    required this.stage,
    required this.progress,
    required this.quality,
    required this.bpm,
    required this.message,
    required this.waveform,
    this.measurement,
  });

  final PulseCaptureStage stage;
  final double progress;
  final int quality;
  final double? bpm;
  final String message;
  final List<double> waveform;
  final PulseMeasurement? measurement;
}

class _TimedSample {
  const _TimedSample(this.timeMs, this.value);
  final int timeMs;
  final double value;
}

/// 指尖 PPG 信号状态机。只有覆盖有效且周期信号稳定时才累计正式进度。
class PulseSignalAnalyzer {
  PulseSignalAnalyzer({this.measurementSeconds = 45});

  final int measurementSeconds;
  final List<_TimedSample> _samples = [];
  final List<double> _bpmHistory = [];
  final List<int> _qualityHistory = [];
  PulseCaptureStage _stage = PulseCaptureStage.positioning;
  int? _coveredSinceMs;
  int? _lastValidMs;
  int? _lastAcceptedMs;
  int _validMeasurementMs = 0;
  int _lastBpmAddedMs = 0;
  PulseMeasurement? _measurement;

  PulseSignalSnapshot add({
    required int timeMs,
    required double value,
    required bool fingerCovered,
  }) {
    if (_stage == PulseCaptureStage.completed) return _snapshot('测量已完成');

    if (!fingerCovered) {
      _coveredSinceMs = null;
      if (_lastValidMs == null || timeMs - _lastValidMs! > 1800) {
        _resetSignal(
            keepMeasurementProgress: _stage == PulseCaptureStage.measuring);
      }
      _stage = PulseCaptureStage.positioning;
      return _snapshot('请轻轻覆盖后置摄像头与闪光灯');
    }

    _coveredSinceMs ??= timeMs;
    _samples.add(_TimedSample(timeMs, value));
    _samples.removeWhere((s) => timeMs - s.timeMs > 12000);

    if (timeMs - _coveredSinceMs! < 2500 || _samples.length < 35) {
      _stage = PulseCaptureStage.stabilizing;
      return _snapshot('正在建立稳定信号，请保持不动');
    }

    final estimate = _estimatePulse();
    if (estimate == null || estimate.quality < 48) {
      _stage = PulseCaptureStage.stabilizing;
      return _snapshot('信号不稳定，请放松手指并保持静止');
    }

    _lastValidMs = timeMs;
    if (_stage != PulseCaptureStage.measuring) {
      _stage = PulseCaptureStage.measuring;
      _lastAcceptedMs = timeMs;
    } else {
      final delta = math.min(250, timeMs - (_lastAcceptedMs ?? timeMs));
      if (delta > 0) _validMeasurementMs += delta;
      _lastAcceptedMs = timeMs;
    }

    if (timeMs - _lastBpmAddedMs >= 900) {
      _bpmHistory.add(estimate.bpm);
      _qualityHistory.add(estimate.quality);
      _lastBpmAddedMs = timeMs;
    }

    if (_validMeasurementMs >= measurementSeconds * 1000 &&
        _bpmHistory.length >= 12) {
      _measurement = _buildMeasurement(estimate.quality);
      _stage = PulseCaptureStage.completed;
      return _snapshot('测量完成');
    }
    return _snapshot('信号稳定，正在测量', estimate: estimate);
  }

  void reset() {
    _samples.clear();
    _bpmHistory.clear();
    _qualityHistory.clear();
    _stage = PulseCaptureStage.positioning;
    _coveredSinceMs = null;
    _lastValidMs = null;
    _lastAcceptedMs = null;
    _validMeasurementMs = 0;
    _lastBpmAddedMs = 0;
    _measurement = null;
  }

  void _resetSignal({required bool keepMeasurementProgress}) {
    _samples.clear();
    _lastAcceptedMs = null;
    if (!keepMeasurementProgress) {
      _bpmHistory.clear();
      _qualityHistory.clear();
      _validMeasurementMs = 0;
    }
  }

  _PulseEstimate? _estimatePulse() {
    if (_samples.length < 35) return null;
    final duration = (_samples.last.timeMs - _samples.first.timeMs) / 1000;
    if (duration < 3.5) return null;
    final rate = (_samples.length - 1) / duration;
    if (rate < 6) return null;

    final raw = _samples.map((e) => e.value).toList();
    final mean = raw.reduce((a, b) => a + b) / raw.length;
    final centered = raw.map((v) => v - mean).toList();
    final energy = centered.fold<double>(0, (s, v) => s + v * v);
    if (energy < 1) return null;

    var bestCorrelation = -1.0;
    var bestLag = 0;
    final minLag = math.max(2, (rate * 60 / 180).round());
    final maxLag = math.min(centered.length ~/ 2, (rate * 60 / 42).round());
    for (var lag = minLag; lag <= maxLag; lag++) {
      var numerator = 0.0;
      var left = 0.0;
      var right = 0.0;
      for (var i = lag; i < centered.length; i++) {
        final a = centered[i];
        final b = centered[i - lag];
        numerator += a * b;
        left += a * a;
        right += b * b;
      }
      final denominator = math.sqrt(left * right);
      if (denominator <= 0) continue;
      final correlation = numerator / denominator;
      if (correlation > bestCorrelation) {
        bestCorrelation = correlation;
        bestLag = lag;
      }
    }
    if (bestLag == 0) return null;
    final bpm = 60 * rate / bestLag;
    if (bpm < 42 || bpm > 180) return null;
    final quality = (35 + bestCorrelation.clamp(0.0, 1.0) * 65).round();
    return _PulseEstimate(bpm, quality.clamp(0, 100));
  }

  PulseMeasurement _buildMeasurement(int lastQuality) {
    final sorted = [..._bpmHistory]..sort();
    final lowCut = math.max(0, (sorted.length * .1).floor());
    final highCut = math.min(sorted.length, (sorted.length * .9).ceil());
    final trimmed = sorted.sublist(lowCut, math.max(lowCut + 1, highCut));
    final average = trimmed.reduce((a, b) => a + b) / trimmed.length;
    final variance =
        trimmed.fold<double>(0, (s, v) => s + math.pow(v - average, 2)) /
            trimmed.length;
    final quality = _qualityHistory.isEmpty
        ? lastQuality
        : (_qualityHistory.reduce((a, b) => a + b) / _qualityHistory.length)
            .round();
    return PulseMeasurement(
      averageBpm: average,
      minimumBpm: trimmed.first,
      maximumBpm: trimmed.last,
      rhythmVariation: math.sqrt(variance),
      signalQuality: quality.clamp(0, 100),
      durationSeconds: measurementSeconds,
    );
  }

  PulseSignalSnapshot _snapshot(String message, {_PulseEstimate? estimate}) {
    final normalized = <double>[];
    if (_samples.isNotEmpty) {
      final visible = _samples.length > 80
          ? _samples.sublist(_samples.length - 80)
          : _samples;
      final values = visible.map((e) => e.value).toList();
      final minValue = values.reduce(math.min);
      final maxValue = values.reduce(math.max);
      final span = math.max(.001, maxValue - minValue);
      for (final value in values) {
        normalized.add(((value - minValue) / span) * 2 - 1);
      }
    }
    return PulseSignalSnapshot(
      stage: _stage,
      progress: _stage == PulseCaptureStage.measuring
          ? (_validMeasurementMs / (measurementSeconds * 1000)).clamp(0.0, 1.0)
          : (_stage == PulseCaptureStage.completed ? 1 : 0),
      quality: estimate?.quality ?? 0,
      bpm: estimate?.bpm,
      message: message,
      waveform: normalized,
      measurement: _measurement,
    );
  }
}

class _PulseEstimate {
  const _PulseEstimate(this.bpm, this.quality);
  final double bpm;
  final int quality;
}
