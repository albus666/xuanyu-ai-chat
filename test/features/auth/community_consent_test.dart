import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/app/bootstrap/auth_state.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/features/auth/agreement_dialog.dart';

void main() {
  test('旧协议同意记录不能跳过新版社区规则确认', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyAgreementAccepted: true,
      AppConstants.keyAgreementVersion: '2026-09-22|2026-09-16',
    });
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthState(prefs);
    expect(auth.agreementAccepted, isFalse);
    await prefs.setString(AppConstants.keyAgreementVersion,
        '${AppConstants.userAgreementVersion}|${AppConstants.privacyPolicyVersion}');
    expect(auth.agreementAccepted, isTrue);
  });

  testWidgets('小屏可阅读零容忍规则并主动同意', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var accepted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AgreementDialog(onAccept: () => accepted = true)),
    ));
    expect(accepted, isFalse);
    final copy = tester.widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText()).join();
    expect(copy, contains('零容忍'));
    await tester.ensureVisible(find.text('同意并继续'));
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    expect(accepted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
