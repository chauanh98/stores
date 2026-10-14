import 'package:flutter/material.dart';

/// Caps [child] (typically a fixed footer / summary bar that sits below an
/// `Expanded` list in a `Column`) to [maxFraction] of the screen height and
/// lets it scroll when it would be taller. On normal screens it is a
/// transparent wrapper; on tiny screens / 2x text scale it prevents the footer
/// from squeezing the list to nothing or overflowing the Column.
class CappedScroll extends StatelessWidget {
  const CappedScroll({super.key, required this.child, this.maxFraction = 0.45});

  final Widget child;
  final double maxFraction;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * maxFraction),
      child: SingleChildScrollView(
        child: child,
      ),
    );
  }
}
