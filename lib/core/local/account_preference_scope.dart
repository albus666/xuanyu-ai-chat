import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../network/api_session_scope.dart';

/// 固定一次本地读取/保存的账号，不认领无法证明归属的旧公共存档。
class AccountPreferenceScope {
  AccountPreferenceScope._(this.session, this.prefs, this.userId);

  final ApiSessionScope session;
  final SharedPreferences prefs;
  final int? userId;

  static Future<AccountPreferenceScope> capture(
      {ApiSessionScope? session}) async {
    final bound = session ?? ApiSessionScope();
    bound.ensureCurrent();
    final prefs = await SharedPreferences.getInstance();
    bound.ensureCurrent();
    return AccountPreferenceScope._(
      bound,
      prefs,
      prefs.getInt(AppConstants.keyUserId),
    );
  }

  bool get current =>
      session.current && prefs.getInt(AppConstants.keyUserId) == userId;

  String key(String base) => '${base}_user_${userId ?? 'guest'}';

  void ensureCurrent() {
    if (!current) throw const ApiSessionChangedException();
  }
}
