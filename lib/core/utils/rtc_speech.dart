import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'rtc_audio_activity.dart';

final _speechConfigurations = Expando<Future<void>>();
Future<void> configureRtcSpeech(RtcEngine engine) =>
    _speechConfigurations[engine] ??= _configureRtcSpeech(engine);

Future<void> _configureRtcSpeech(RtcEngine engine) async {
  await RtcAudioActivity.acquire(engine);
  await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioMeeting);
  await engine.enableInEarMonitoring(
      enabled: false,
      includeAudioFilters: EarMonitoringFilterType.earMonitoringFilterNone);
  await restoreRtcSpeechProcessing(engine);
  try {
    // Suppress transient non-speech noise without aggressive voice filtering.
    await engine.setAINSMode(
        enabled: true, mode: AudioAinsMode.ainsModeBalanced);
  } catch (error) {
    // Unsupported devices keep the SDK's standard 3A processing.
    _reportAudioConfigurationFailure('AI noise suppression', error);
  }
}

/// Route changes must not reset the audio profile while capture is running.
Future<void> restoreRtcSpeechProcessing(RtcEngine engine) async {
  try {
    // Restore the SDK's default 3A chain, including loud-input gain control.
    // Disabling AGC removes level regulation for sudden high-level sounds.
    await engine.setParameters(
        '{"che.audio.aec.enable":true,"che.audio.ans.enable":true,"che.audio.agc.enable":true}');
  } catch (error) {
    _reportAudioConfigurationFailure('speech processing', error);
  }
}

void _reportAudioConfigurationFailure(String step, Object error) {
  final code = error is AgoraRtcException ? ' (${error.code})' : '';
  debugPrint('RTC $step failed: ${error.runtimeType}$code');
}

/// Keep native shutdown from blocking navigation indefinitely.
Future<void> releaseRtcEngine(RtcEngine? engine) async {
  if (engine == null) return;
  Future<void> step(Future<void> Function() action, Duration limit) async {
    try {
      await action().timeout(limit);
    } catch (error) {
      debugPrint('RTC cleanup incomplete: ${error.runtimeType}');
    }
  }

  await step(() => engine.muteLocalAudioStream(true),
      const Duration(milliseconds: 500));
  await step(() => engine.muteAllRemoteAudioStreams(true),
      const Duration(milliseconds: 500));
  await step(() => engine.leaveChannel(), const Duration(seconds: 1));
  await step(() => engine.release(), const Duration(seconds: 1));
  _speechConfigurations[engine] = null;
  RtcAudioActivity.release(engine);
}
