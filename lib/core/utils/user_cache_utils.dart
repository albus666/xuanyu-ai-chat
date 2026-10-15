import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import 'daily_energy_loader.dart';

/// 清除与当前用户绑定的本地缓存（今日运势、今日养生）。
/// 在登出、401、或新用户登录/注册成功后调用，避免同设备换用户后仍看到上一用户缓存。
Future<void> clearUserDependentCache({bool Function()? shouldClear}) async {
  final prefs = await SharedPreferences.getInstance();
  if (shouldClear != null && !shouldClear()) return;
  DailyEnergyLoader.clearSession();
  await Future.wait([
    prefs.remove(AppConstants.keyDailyFortuneCache),
    prefs.remove(AppConstants.keyDailyFortuneDate),
    prefs.remove(AppConstants.keyDailyHealthCache),
    prefs.remove(AppConstants.keyDailyHealthDate),
    for (final base in [
      AppConstants.keyDailyFortuneCache,
      AppConstants.keyDailyFortuneDate,
      AppConstants.keyDailyHealthCache,
      AppConstants.keyDailyHealthDate
    ])
      prefs.remove(DailyEnergyLoader.cacheKey(prefs, base)),
  ]);
}
