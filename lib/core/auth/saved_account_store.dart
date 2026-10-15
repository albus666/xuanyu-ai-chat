import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

class SavedAccountSession {
  const SavedAccountSession({
    required this.userId,
    required this.token,
    required this.account,
    required this.nickname,
    required this.avatarUrl,
    required this.minorMode,
    required this.updatedAt,
  });

  final int userId;
  final String token;
  final String account;
  final String nickname;
  final String avatarUrl;
  final bool minorMode;
  final DateTime updatedAt;

  String get displayName =>
      nickname.trim().isNotEmpty ? nickname.trim() : '用户$userId';

  String get maskedAccount {
    final value = account.trim();
    if (RegExp(r'^\d{11}$').hasMatch(value)) {
      return '${value.substring(0, 3)}****${value.substring(7)}';
    }
    return value.isNotEmpty ? value : '玄遇号 $userId';
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'token': token,
        'account': account,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'minorMode': minorMode,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static SavedAccountSession? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final userId = (raw['userId'] as num?)?.toInt();
    final token = raw['token']?.toString() ?? '';
    if (userId == null || userId <= 0 || token.isEmpty) return null;
    return SavedAccountSession(
      userId: userId,
      token: token,
      account: raw['account']?.toString() ?? '',
      nickname: raw['nickname']?.toString() ?? '',
      avatarUrl: raw['avatarUrl']?.toString() ?? '',
      minorMode: raw['minorMode'] == true || raw['minorMode'] == 1,
      updatedAt: DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SavedAccountStore {
  SavedAccountStore._();

  static Future<List<SavedAccountSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(AppConstants.keySavedAccountSessions);
    if (encoded == null || encoded.isEmpty) return [];
    try {
      final raw = jsonDecode(encoded);
      if (raw is! List) return [];
      final accounts = raw
          .map(SavedAccountSession.fromJson)
          .whereType<SavedAccountSession>()
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return accounts;
    } catch (_) {
      return [];
    }
  }

  static Future<void> rememberLogin({
    required String token,
    required int userId,
    String account = '',
    String nickname = '',
    String avatarUrl = '',
    bool minorMode = false,
  }) async {
    if (token.isEmpty || userId <= 0) return;
    final accounts = await load();
    final previous =
        accounts.where((item) => item.userId == userId).firstOrNull;
    accounts.removeWhere((item) => item.userId == userId);
    accounts.insert(
      0,
      SavedAccountSession(
        userId: userId,
        token: token,
        account: account.trim().isNotEmpty
            ? account.trim()
            : previous?.account ?? '',
        nickname: nickname.trim().isNotEmpty
            ? nickname.trim()
            : previous?.nickname ?? '',
        avatarUrl: avatarUrl.trim().isNotEmpty
            ? avatarUrl.trim()
            : previous?.avatarUrl ?? '',
        minorMode: minorMode,
        updatedAt: DateTime.now(),
      ),
    );
    await _save(accounts.take(5).toList());
  }

  static Future<void> updateCurrentProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyToken) ?? '';
    final userId = prefs.getInt(AppConstants.keyUserId) ??
        (profile['userId'] as num?)?.toInt() ??
        0;
    await rememberLogin(
      token: token,
      userId: userId,
      account: profile['mobile']?.toString() ?? '',
      nickname: profile['nickname']?.toString() ?? '',
      avatarUrl: profile['avatarUrl']?.toString() ?? '',
      minorMode: profile['minorMode'] == true || profile['minorMode'] == 1,
    );
  }

  static Future<void> remove(int userId) async {
    final accounts = await load();
    accounts.removeWhere((item) => item.userId == userId);
    await _save(accounts);
  }

  static Future<bool> validate(SavedAccountSession account) async {
    final client = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrlOverride ?? AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Authorization': 'Bearer ${account.token}'},
    ));
    try {
      final response = await client.get('/api/auth/me');
      final body = response.data;
      return body is Map && (body['code'] == 0 || body['code'] == null);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _save(List<SavedAccountSession> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.keySavedAccountSessions,
      jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }
}
