import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../network/api_client.dart';

/// 设置中心的跨设备偏好。先本地生效，再同步服务端；失败时恢复原值。
class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._();

  static final AppSettingsStore instance = AppSettingsStore._();

  static const defaults = <String, dynamic>{
    'showOnlineStatus': true,
    'showPartyStatus': true,
    'allowDirectMessages': 'everyone',
    'allowCalls': 'mutual',
    'allowGroupInvites': 'everyone',
    'allowRoomInvites': 'everyone',
    'notifySocialCalls': true,
    'quietHoursEnabled': false,
    'quietHoursStart': '22:00',
    'quietHoursEnd': '08:00',
    'giftConfirmation': true,
    'reduceMotion': false,
    'largerText': false,
  };

  late SharedPreferences _prefs;
  final Map<String, dynamic> _values = Map<String, dynamic>.from(defaults);
  final Map<String, dynamic> _confirmed = {};
  final Map<String, int> _fieldRevisions = {};
  static const _deviceSettings = {'reduceMotion', 'largerText'};
  int? _userId;
  int _generation = 0;
  int _revision = 0;
  int _syncSerial = 0;
  int _pending = 0;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    apiSessionChanges.removeListener(_onSessionChanged);
    apiSessionChanges.addListener(_onSessionChanged);
    _restore(prefs.getInt(AppConstants.keyUserId));
  }

  String _localKey(String key, int? userId) => _deviceSettings.contains(key)
      ? 'app_setting_$key'
      : 'app_setting_user_${userId}_$key';

  void _restore(int? userId) {
    _userId = userId;
    _generation++;
    _revision = 0;
    _pending = 0;
    _fieldRevisions.clear();
    _writeQueue = Future<void>.value();
    for (final entry in defaults.entries) {
      // 无账号归属的旧隐私缓存不能迁移给当前登录人；以服务端为准。
      final cached = userId != null || _deviceSettings.contains(entry.key)
          ? _prefs.get(_localKey(entry.key, userId))
          : null;
      _values[entry.key] =
          _validValue(entry.key, cached) ? cached : entry.value;
    }
    _confirmed
      ..clear()
      ..addAll(_values);
  }

  void _onSessionChanged() {
    _restore(apiClient.options.headers['Authorization'] == null
        ? null
        : _prefs.getInt(AppConstants.keyUserId));
    notifyListeners();
  }

  bool _validValue(String key, dynamic value) => defaults[key] is bool
      ? value is bool
      : defaults[key] is String && value is String;

  bool boolValue(String key) => _values[key] == true;
  String stringValue(String key) => '${_values[key] ?? defaults[key] ?? ''}';
  Map<String, dynamic> get values => Map<String, dynamic>.unmodifiable(_values);

  Future<void> syncFromServer() async {
    final generation = _generation;
    final revision = _revision;
    final serial = ++_syncSerial;
    final hadPendingWrites = _pending > 0;
    final response = await apiClient.get('/api/auth/settings');
    if (generation != _generation ||
        revision != _revision ||
        serial != _syncSerial ||
        hadPendingWrites ||
        _pending > 0) {
      return;
    }
    final raw = (response.data as Map?)?['data'];
    if (raw is! Map) throw StateError('设置响应无效');
    for (final key in defaults.keys) {
      if (_validValue(key, raw[key])) {
        _values[key] = raw[key];
        _confirmed[key] = raw[key];
      }
    }
    await _saveLocal(_confirmed, _userId);
    if (generation != _generation) return;
    notifyListeners();
  }

  Future<void> update(Map<String, dynamic> changes) {
    final patch = Map<String, dynamic>.fromEntries(changes.entries.where(
        (entry) =>
            defaults.containsKey(entry.key) &&
            _validValue(entry.key, entry.value)));
    if (patch.isEmpty) return Future<void>.value();
    final generation = _generation;
    final revision = ++_revision;
    for (final key in patch.keys) {
      _fieldRevisions[key] = revision;
    }
    _pending++;
    _values.addAll(patch);
    notifyListeners();
    // 保证同一个开关连续操作按顺序送达，失败只回滚该次仍有效的字段。
    final result = _writeQueue.then((_) => _write(patch, generation, revision));
    _writeQueue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _write(
      Map<String, dynamic> patch, int generation, int revision) async {
    if (generation != _generation) throw StateError('账号已切换，请重新设置');
    try {
      final response = await apiClient.patch('/api/auth/settings', data: patch);
      if (generation != _generation) throw StateError('账号已切换，请重新设置');
      final raw = (response.data as Map?)?['data'];
      if (raw is! Map || patch.keys.any((key) => !_validValue(key, raw[key]))) {
        throw StateError('设置响应无效');
      }
      for (final key in patch.keys) {
        _confirmed[key] = raw[key];
        if (_fieldRevisions[key] == revision) _values[key] = raw[key];
      }
      await _saveLocal(
          {for (final key in patch.keys) key: _confirmed[key]}, _userId);
    } catch (_) {
      if (generation == _generation) {
        for (final key in patch.keys) {
          if (_fieldRevisions[key] == revision) _values[key] = _confirmed[key];
        }
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        _pending--;
        notifyListeners();
      }
    }
  }

  Future<void> _saveLocal(Map<String, dynamic> values, int? userId) async {
    final writes = <Future<bool>>[];
    for (final entry in values.entries) {
      if (!defaults.containsKey(entry.key)) continue;
      if (userId == null && !_deviceSettings.contains(entry.key)) continue;
      final key = _localKey(entry.key, userId);
      if (entry.value is bool) {
        writes.add(_prefs.setBool(key, entry.value as bool));
      } else {
        writes.add(_prefs.setString(key, '${entry.value}'));
      }
    }
    await Future.wait(writes);
  }
}
