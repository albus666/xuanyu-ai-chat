import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/shared/widgets/draggable_call_bubble.dart';

void main() {
  testWidgets('连续拖动累积位移，底部松手只请求确认', (tester) async {
    var confirmations = 0;
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DraggableCallBubble(
      onTap: () => taps++,
      onDismiss: () async {
        confirmations++;
      },
      child: const SizedBox(width: 60, height: 60, child: Icon(Icons.phone)),
    ))));
    final start = tester.getCenter(find.byIcon(Icons.phone));
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(-20, 20));
    await drag.moveBy(const Offset(-20, 20));
    await drag.moveBy(const Offset(-20, 20));
    await tester.pump();
    expect(
        tester.getCenter(find.byIcon(Icons.phone)).dx, lessThan(start.dx - 30));
    await drag.moveTo(const Offset(400, 570));
    await tester.pump();
    expect(find.text('松手结束通话'), findsOneWidget);
    expect(tester.getCenter(find.byIcon(Icons.phone)).dy, greaterThan(510));
    await drag.up();
    await tester.pump();
    expect(confirmations, 1);
    expect(taps, 0);
    expect(tester.getCenter(find.byIcon(Icons.phone)).dy, start.dy);
  });
}
