import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/constants/app_constants.dart';

void main() {
  test('Android 原生隐私门禁与 Dart 共用同一套协议 Key 和版本串', () {
    expect(AppConstants.keyAgreementAccepted, 'agreement_accepted');
    expect(AppConstants.keyAgreementAcceptedAt, 'agreement_accepted_at');
    expect(AppConstants.keyAgreementVersion, 'agreement_version');
    expect(
      '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}',
      '2026-10-02|2026-10-14',
    );

    final iosGate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(iosGate, contains('acceptedVersion = "${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}"'));

    final nativeStore = File(
      'android/app/src/main/kotlin/com/xuanyu/android/PrivacyConsentStore.kt',
    ).readAsStringSync();
    expect(
      nativeStore,
      contains('const val USER_AGREEMENT_VERSION = "2026-10-02"'),
    );
    expect(
      nativeStore,
      contains('const val PRIVACY_POLICY_VERSION = "2026-10-14"'),
    );
  });
}
