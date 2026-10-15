import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xuanyu/core/update/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('today suppression expires at local midnight, not after 24 hours', () {
    final evening = DateTime(2026, 10, 7, 23, 59);
    final snoozed = AppUpdateService.localDateKey(evening);
    expect(
      AppUpdateService.shouldSuppressPrompt(snoozedDate: snoozed, now: evening),
      isTrue,
    );
    expect(
      AppUpdateService.shouldSuppressPrompt(
        snoozedDate: snoozed,
        now: DateTime(2026, 10, 8),
      ),
      isFalse,
    );
    expect(
      AppUpdateService.shouldSuppressPrompt(
        snoozedDate: snoozed,
        now: evening,
        manual: true,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.shouldSuppressPrompt(
        snoozedDate: snoozed,
        now: evening,
        requiredUpdate: true,
      ),
      isFalse,
    );
  });

  test('today preference is persisted and manual checks bypass it', () async {
    SharedPreferences.setMockInitialValues({});
    final policy = AppUpdatePolicy.fromJson({'updateAvailable': true});
    final service = AppUpdateService.instance;
    expect(await service.shouldPrompt(policy), isTrue);
    await service.snoozeToday();
    expect(await service.shouldPrompt(policy), isFalse);
    expect(await service.shouldPrompt(policy, manual: true), isTrue);
    expect(
      await service.shouldPrompt(
        AppUpdatePolicy.fromJson({'updateAvailable': true, 'required': true}),
      ),
      isTrue,
    );
  });

  test('parses a forced update policy and release notes', () {
    final policy = AppUpdatePolicy.fromJson({
      'updateAvailable': true,
      'required': true,
      'latestVersion': '1.2.0',
      'latestBuild': 12,
      'title': '需要更新',
      'message': '请更新后继续使用',
      'releaseNotes': ['修复消息问题', '', '优化启动速度'],
      'updateUrl': 'https://example.com/app.apk',
      'delivery': 'external',
      'checkIntervalHours': 6,
    });

    expect(policy.available, isTrue);
    expect(policy.required, isTrue);
    expect(policy.latestBuild, 12);
    expect(policy.releaseNotes, ['修复消息问题', '优化启动速度']);
    expect(policy.checkIntervalHours, 6);
  });

  test('uses safe defaults when optional fields are absent', () {
    final policy = AppUpdatePolicy.fromJson(const {});

    expect(policy.available, isFalse);
    expect(policy.required, isFalse);
    expect(policy.title, '发现新版本');
    expect(policy.delivery, 'external');
    expect(policy.checkIntervalHours, 24);
  });

  test('detects Google Play and sideload distribution channels', () {
    final play = PackageInfo(
      appName: '玄遇',
      packageName: 'com.xuanyu.android',
      version: '1.0.6',
      buildNumber: '7',
      installerStore: 'com.android.vending',
    );
    final sideload = PackageInfo(
      appName: '玄遇',
      packageName: 'com.xuanyu.android',
      version: '1.0.6',
      buildNumber: '7',
      installerStore: 'com.android.packageinstaller',
    );

    expect(AppUpdateService.distributionChannelFor(play), 'google_play');
    expect(AppUpdateService.distributionChannelFor(sideload), 'official_apk');
  });
}
