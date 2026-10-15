import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 首次启动协议在原生门禁内阅读且不打开浏览器', () {
    final activity = File(
      'android/app/src/main/kotlin/com/xuanyu/android/PrivacyConsentActivity.kt',
    ).readAsStringSync();
    final store = File(
      'android/app/src/main/kotlin/com/xuanyu/android/PrivacyConsentStore.kt',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final documentLayout = File(
      'android/app/src/main/res/layout/activity_privacy_document.xml',
    );

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gateStart =
        manifest.indexOf('android:name=".PrivacyConsentActivity"');
    final gateEnd = manifest.indexOf('</activity>', gateStart);
    expect(manifest.substring(gateStart, gateEnd),
        contains('android.intent.action.MAIN'));
    final mainStart = manifest.indexOf('android:name=".MainActivity"');
    final mainEnd = manifest.indexOf('</activity>', mainStart);
    expect(manifest.substring(mainStart, mainEnd),
        contains('android:exported="false"'));
    expect(manifest.substring(mainStart, mainEnd),
        isNot(contains('android.intent.action.MAIN')));
    expect(activity, isNot(contains('import io.flutter')));
    expect(
        activity, contains('if (PrivacyConsentStore.hasValidConsent(this))'));
    expect(
        activity.indexOf('PrivacyConsentStore.persistConsent(this)'),
        lessThan(activity.indexOf('showStartupThenLaunchFlutter()',
            activity.indexOf('privacy_consent_agree'))));
    expect(activity, contains('showDocument(document)'));
    expect(activity, contains('assets.open(document.assetPath)'));
    expect(activity, contains('if (showingDocument)'));
    expect(activity, isNot(contains('Intent.ACTION_VIEW')));
    expect(activity, isNot(contains('Uri.parse')));
    expect(activity, isNot(contains('finishAndRemoveTask')));
    expect(store, isNot(contains('USER_AGREEMENT_URL')));
    expect(store, isNot(contains('PRIVACY_POLICY_URL')));
    expect(gradle, contains('generateNativeLegalDocuments'));
    expect(
        gradle, contains('../lib/features/profile/legal_document_page.dart'));
    expect(documentLayout.existsSync(), isTrue);
  });

  test('iOS 同意前不创建 Flutter 引擎且协议在 App 内阅读', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final storyboard = File(
      'ios/Runner/Base.lproj/Main.storyboard',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(storyboard, contains('PrivacyConsentViewController'));
    expect(delegate, contains('guard engine.run() else { return }'));
    expect(delegate, contains('PrivacyConsentStore.persistConsent()'));
    expect(delegate, contains('LegalDocumentViewController'));
    expect(delegate, isNot(contains('UIApplication.shared.open')));
    expect(project, contains('Generate Native Legal Documents'));
  });
}
