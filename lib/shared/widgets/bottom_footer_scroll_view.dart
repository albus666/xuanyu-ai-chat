import 'package:flutter/material.dart';

/// The footer ends the scroll content and fills the viewport for short pages.
class BottomFooterScrollView extends StatelessWidget {
  const BottomFooterScrollView(
      {super.key,
      this.child,
      this.children,
      required this.footer,
      this.padding = EdgeInsets.zero,
      this.physics});
  final Widget? child;
  final List<Widget>? children;
  final Widget footer;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: physics,
        slivers: [
          SliverPadding(
              padding: padding,
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    child ??
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children ?? const []),
                    SafeArea(top: false, child: footer)
                  ],
                ),
              ))
        ],
      );
}
