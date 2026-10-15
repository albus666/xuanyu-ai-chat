import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/rtc_audio_activity.dart';

/// 木鱼敲击短音效（本地 WAV，播放池）。
class MuyuKnockSound {
  MuyuKnockSound._();

  static const _bundlePaths = [
    'assets/merit/muyu_knock_soft_1.wav',
    'assets/merit/muyu_knock_soft_2.wav',
    'assets/merit/muyu_knock_soft_3.wav',
    'assets/merit/muyu_knock_soft_4.wav',
  ];
  static const _assetPaths = [
    'merit/muyu_knock_soft_1.wav',
    'merit/muyu_knock_soft_2.wav',
    'merit/muyu_knock_soft_3.wav',
    'merit/muyu_knock_soft_4.wav',
  ];
  static const _poolSize = 3;

  static final List<AudioPlayer> _players = [];
  static final List<Uint8List> _samples = [];
  static final Random _random = Random();
  static int _playerCursor = 0;
  static int _lastSampleIndex = -1;
  static int? _lastHitAtMs;
  static bool _ready = false;
  static Future<void>? _initFuture;
  static final Set<Future<void>> _playbacks = {};
  static bool _registered = false;

  static Future<void> ensureReady() {
    if (!_registered) {
      _registered = true;
      RtcAudioActivity.registerSound(_stopForCall);
    }
    if (RtcAudioActivity.active) return Future<void>.value();
    return _initFuture ??= _doInit().whenComplete(() {
      if (!_ready) _initFuture = null;
    });
  }

  static Future<void> _stopForCall() async {
    await _initFuture;
    await Future.wait(List.of(_playbacks));
    for (final player in _players) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  static Future<void> _doInit() async {
    try {
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

      _samples.clear();
      for (final path in _bundlePaths) {
        final data = await rootBundle.load(path);
        _samples.add(data.buffer.asUint8List());
      }

      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer();
        // Scope sound settings to this player; never replace the app-wide
        // context, which also resets Android's communication mode and route.
        try {
          await p.setAudioContext(ctx);
        } catch (e) {
          debugPrint('MuyuKnockSound: audioContext skip: ${e.runtimeType}');
        }
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(0.52);
        _players.add(p);
      }
      _ready = _samples.length == _bundlePaths.length &&
          _samples.every((sample) => sample.isNotEmpty) &&
          _players.isNotEmpty;
      final totalBytes =
          _samples.fold<int>(0, (sum, sample) => sum + sample.length);
      debugPrint(
          'MuyuKnockSound: ready=$_ready samples=${_samples.length} bytes=$totalBytes');
    } catch (e, st) {
      debugPrint('MuyuKnockSound: init failed: $e\n$st');
      _ready = false;
      _initFuture = null;
    }
  }

  /// 动画击中帧调用。
  static void playHit({double volume = 0.52}) {
    if (RtcAudioActivity.active) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final gapMs = _lastHitAtMs == null ? null : now - _lastHitAtMs!;
    _lastHitAtMs = now;
    final playback = _playHitAsync(volumeForGap(volume, gapMs: gapMs));
    _playbacks.add(playback);
    unawaited(playback.whenComplete(() => _playbacks.remove(playback)));
  }

  /// 连续敲得越快，单次声音越轻，避免短尾音堆叠后产生听觉疲劳。
  @visibleForTesting
  static double volumeForGap(double requested, {int? gapMs}) {
    final repeatFactor = gapMs == null
        ? 1.0
        : switch (gapMs) {
            < 85 => 0.52,
            < 135 => 0.68,
            < 220 => 0.84,
            _ => 1.0,
          };
    return (requested.clamp(0.1, 1.0) * 0.86 * repeatFactor)
        .clamp(0.06, 0.86)
        .toDouble();
  }

  static Future<void> _playHitAsync(double volume) async {
    if (RtcAudioActivity.active) return;
    await ensureReady();
    if (RtcAudioActivity.active) return;
    if (!_ready || _players.isEmpty || _samples.isEmpty) {
      debugPrint('MuyuKnockSound: play skipped ready=$_ready');
      return;
    }
    var sampleIndex = _random.nextInt(_samples.length);
    if (_samples.length > 1 && sampleIndex == _lastSampleIndex) {
      sampleIndex = (sampleIndex + 1) % _samples.length;
    }
    _lastSampleIndex = sampleIndex;
    final p = _players[_playerCursor % _players.length];
    _playerCursor++;
    final bytes = _samples[sampleIndex];
    final assetPath = _assetPaths[sampleIndex];
    try {
      await p.stop();
      await p.setVolume(volume);
      if (RtcAudioActivity.active) return;
      await p.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (e) {
      debugPrint('MuyuKnockSound: bytes play fail: $e');
      try {
        if (RtcAudioActivity.active) return;
        await p.play(AssetSource(assetPath));
      } catch (e2) {
        debugPrint('MuyuKnockSound: asset play fail: $e2');
      }
    }
  }
}
