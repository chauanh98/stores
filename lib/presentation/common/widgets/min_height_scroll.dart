import 'package:flutter/material.dart';

/// Gives [child] at least [minHeight] logical pixels. When the available
/// height is smaller (tiny screens, landscape with keyboard, 2x text scale)
/// the child is laid out at [minHeight] inside a vertical scroll view instead
/// of overflowing. When there is enough room it is a transparent pass-through.
class MinHeightScroll extends StatelessWidget {
  const MinHeightScroll({
    super.key,
    required this.minHeight,
    required this.child,
  });

  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight ||
            constraints.maxHeight >= minHeight) {
          return child;
        }
        return SingleChildScrollView(
          child: SizedBox(height: minHeight, child: child),
        );
      },
    );
  }
}
