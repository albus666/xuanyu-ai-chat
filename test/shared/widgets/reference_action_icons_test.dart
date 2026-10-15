import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/shared/widgets/reference_action_icons.dart';

void main() {
  testWidgets('私聊字形使用双点微笑气泡绘制', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReferenceActionGlyph(
            type: ReferenceActionIconType.privateChat,
            size: 20,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ReferenceActionGlyph),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('私聊操作面板沿用圆底但使用新的紧凑字形', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReferenceActionCircleIcon(
            type: ReferenceActionIconType.privateChat,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ReferenceActionCircleIcon),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });
}
