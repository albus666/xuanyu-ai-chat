import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/profile/legal_document_page.dart';
import 'package:xuanyu/features/profile/legal_document_parser.dart';

void main() {
  test('隐私政策硬换行会拼回完整段落，并抽出标题与版本', () {
    const raw = '''
玄遇隐私政策
版本号：2026-09-16
生效日期：2026 年 9 月 16 日
本隐私政策适用于河南省问灵科技有限公司（以下简称“我们”）开
发运营的玄遇 App（以下简称“本应用”）。
个人信息处理者：河南省问灵科技有限公司
个人信息保护负责人邮箱：2254741308@qq.com
重要提示
本应用提供的历法查询仅供参考。
1.   我们收集的信息与使用场景
1.1   注册登录
个人信息种类：手机号、验证码、Token、用户 ID、登录状态、设
备和网络信息
收集目的：创建账号
SDK名称：地图SDK
开发者:北京高德图强科技有限公司
SDK名称：定位SDK
开发者:北京高德图强科技有限公司
''';
    final parsed = parseLegalDocument(raw, fallbackTitle: '隐私政策');
    expect(parsed.title, '玄遇隐私政策');
    expect(parsed.version, '2026-09-16');
    expect(parsed.effectiveDate, '2026 年 9 月 16 日');
    expect(parsed.blocks.first.kind, LegalBlockKind.body);
    expect(parsed.blocks.first.text, contains('开发运营的玄遇 App'));
    expect(parsed.blocks.first.text, isNot(contains('\n')));
    expect(
      parsed.blocks.where((block) => block.kind == LegalBlockKind.heading),
      hasLength(1),
    );
    expect(
      parsed.blocks.where((block) => block.kind == LegalBlockKind.subheading),
      hasLength(1),
    );
    final kindField = parsed.blocks.firstWhere(
      (block) => block.fieldLabel == '个人信息种类',
    );
    expect(kindField.fieldValue, contains('设备和网络信息'));
    final sdkCards = groupFieldCards(
      parsed.blocks
          .where((block) => block.kind == LegalBlockKind.field)
          .toList(),
    );
    expect(
      sdkCards.where((card) => card.first.fieldLabel == 'SDK名称'),
      hasLength(2),
    );
  });

  testWidgets('隐私政策页按章节、目录和字段卡片展示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentPage(type: LegalDocumentType.privacyPolicy),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('玄遇隐私政策'), findsWidgets);
    expect(find.textContaining('版本 2026-10-14'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.textContaining('开发运营的玄遇 App'), findsOneWidget);
    expect(find.textContaining('1. 我们收集的信息与使用场景'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('个人信息处理者'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('河南省问灵科技有限公司'), findsWidgets);

    await tester.scrollUntilVisible(
      find.textContaining('剪切板可能包含个人信息'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    final notice = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.textSpan?.toPlainText() ?? '').contains('剪切板可能包含个人信息'),
    );
    expect(notice, findsOneWidget);
    expect(
      tester.widget<SelectableText>(notice).textSpan?.style?.fontWeight,
      FontWeight.bold,
    );
    expect(find.textContaining('主动粘贴到输入框的文本内容'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('APP支付客户端SDK'),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('APP支付客户端SDK'), findsOneWidget);
  });
}
