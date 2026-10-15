import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/bootstrap/startup_gate.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/settings/app_settings_store.dart';
import 'message_tone_preview.dart';

/// Tracks message IDs, including messages already marked read by an open chat.
class SpecialCareMessageTracker {
  final Map<int, int> _seen = {};
  bool _initialized = false;

  List<String> observe(Iterable<Map> conversations, {bool quiet = false}) {
    final tones = <String>[];
    for (final item in conversations) {
      final id = (item['conversationId'] as num?)?.toInt();
      final message = (item['lastMessageId'] as num?)?.toInt();
      if (id == null || message == null) continue;
      final previous = _seen[id];
      if (_initialized &&
          message > (previous ?? 0) &&
          item['lastMessageIncoming'] == true &&
          item['specialCare'] == true &&
          item['mute'] != true &&
          !quiet) {
        final tone = item['specialCareSound'] as String? ?? 'default';
        if (tone != 'silent') tones.add(tone);
      }
      if (message > (previous ?? 0)) _seen[id] = message;
    }
    _initialized = true;
    return tones;
  }
}

bool messageQuietHours(DateTime now, String start, String end) {
  int? minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  final first = minutes(start), last = minutes(end);
  if (first == null || last == null || first == last) return false;
  final current = now.hour * 60 + now.minute;
  return first < last
      ? current >= first && current < last
      : current >= first || current < last;
}

class SpecialCareMessageSoundHost extends StatefulWidget {
  const SpecialCareMessageSoundHost({super.key, required this.child});
  final Widget child;

  @override
  State<SpecialCareMessageSoundHost> createState() => _SoundHostState();
}

class _SoundHostState extends State<SpecialCareMessageSoundHost>
    with WidgetsBindingObserver {
  ApiSessionScope _scope = ApiSessionScope();
  SpecialCareMessageTracker _tracker = SpecialCareMessageTracker();
  MessageTonePreview _sound = MessageTonePreview();
  Timer? _timer;
  bool _polling = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apiSessionChanges.addListener(_accountChanged);
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!StartupGate.isReady) await StartupGate.ready;
    if (!mounted) return;
    _timer =
        Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_poll()));
    await _poll();
  }

  void _accountChanged() {
    _scope = ApiSessionScope();
    _tracker = SpecialCareMessageTracker();
    unawaited(_sound.dispose());
    _sound = MessageTonePreview();
    _polling = false;
    if (StartupGate.isReady) unawaited(_poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && StartupGate.isReady) unawaited(_poll());
  }

  Future<void> _poll() async {
    final scope = _scope;
    if (!mounted || !_foreground || _polling || !scope.authenticated) return;
    _polling = true;
    try {
      final response = await scope.get('/api/im/conversations');
      if (!mounted || !scope.current) return;
      final data = (response.data as Map?)?['data'];
      final list = data is Map ? data['list'] : null;
      if (list is! List) return;
      final settings = AppSettingsStore.instance;
      final quiet = settings.boolValue('quietHoursEnabled') &&
          messageQuietHours(
              DateTime.now(),
              settings.stringValue('quietHoursStart'),
              settings.stringValue('quietHoursEnd'));
      final tones = _tracker.observe(list.whereType<Map>(), quiet: quiet);
      if (_foreground && tones.isNotEmpty) await _sound.play(tones.first);
    } catch (_) {
      // A failed poll must not interrupt chat or replay previous notifications.
    } finally {
      if (scope.current) _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    apiSessionChanges.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sound.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
