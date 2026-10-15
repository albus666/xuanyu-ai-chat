import 'dart:async';

import 'package:flutter/material.dart';

/// Keep visited tabs mounted, but leave unopened tabs off the startup path.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.warmupIndices = const {},
    this.warmupDelay = const Duration(milliseconds: 900),
  });

  final int index;
  final List<Widget> children;
  final Set<int> warmupIndices;
  final Duration warmupDelay;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = {};
  Timer? _warmup;

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
    if (widget.warmupIndices.isNotEmpty) {
      _warmup = Timer(widget.warmupDelay, () {
        if (mounted) setState(() => _visited.addAll(widget.warmupIndices));
      });
    }
  }

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  void dispose() {
    _warmup?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: widget.index,
        children: [
          for (var index = 0; index < widget.children.length; index++)
            TickerMode(
              enabled: index == widget.index,
              child: _visited.contains(index)
                  ? widget.children[index]
                  : const SizedBox.shrink(),
            ),
        ],
      );
}
