import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/widgets/lazy_indexed_stack.dart';

void main() {
  testWidgets('未访问栏目不初始化，切回保留状态，消息预热延后', (tester) async {
    final starts = <int>[];
    var index = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return LazyIndexedStack(
              index: index,
              warmupIndices: const {2},
              children: [
                for (var i = 0; i < 3; i++) _Probe(id: i, starts: starts),
              ],
            );
          },
        ),
      ),
    );
    expect(starts, [0]);
    update(() => index = 1);
    await tester.pump();
    expect(starts, [0, 1]);
    update(() => index = 0);
    await tester.pump();
    expect(starts, [0, 1]);
    await tester.pump(const Duration(milliseconds: 900));
    expect(starts, [0, 1, 2]);
    expect(find.text('页0'), findsOneWidget);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.id, required this.starts});
  final int id;
  final List<int> starts;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.starts.add(widget.id);
  }

  @override
  Widget build(BuildContext context) => Text('页${widget.id}');
}
