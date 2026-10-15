import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/navigation/app_deep_link.dart';

void main() {
  test('群聊二维码链接只接受正数会话编号', () {
    expect(groupConversationIdFromDeepLink('xuanyu://group/42'), 42);
    expect(groupConversationIdFromDeepLink(' xuanyu://group/7 '), 7);
    expect(groupConversationIdFromDeepLink('xuanyu://group/0'), isNull);
    expect(groupConversationIdFromDeepLink('xuanyu://group/-1'), isNull);
    expect(
      groupConversationIdFromDeepLink('xuanyu://group/not-a-number'),
      isNull,
    );
    expect(groupConversationIdFromDeepLink('xuanyupay://group/42'), isNull);
    expect(groupConversationIdFromDeepLink('xuanyu://profile/42'), isNull);
    expect(groupConversationIdFromDeepLink('xuanyu://group/42/extra'), isNull);
  });

  test('Android 从隐私门禁转交链接且前后台都能送入 Flutter', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final consent = File(
      'android/app/src/main/kotlin/com/xuanyu/android/PrivacyConsentActivity.kt',
    ).readAsStringSync();
    final main = File(
      'android/app/src/main/kotlin/com/xuanyu/android/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:scheme="xuanyu"'));
    expect(manifest, contains('android:host="group"'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(consent, contains('data = incomingLink'));
    expect(main, contains('"xuanyu/deep_links"'));
    expect(main, contains('override fun onNewIntent'));
    expect(main, contains('channel.invokeMethod("onLink", value)'));
  });

  test('iOS 注册群聊协议且保留原支付协议', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(plist, contains('<string>xuanyupay</string>'));
    expect(plist, contains('<string>xuanyu</string>'));
    expect(delegate, contains('name: "xuanyu/deep_links"'));
    expect(delegate, contains('open url: URL'));
    expect(delegate, contains('channel.invokeMethod("onLink"'));
  });
}
