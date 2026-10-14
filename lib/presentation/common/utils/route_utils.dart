import 'package:flutter/widgets.dart';

/// Pops the route that owns [context] only if it is still the active, topmost
/// route. Returns whether it popped.
///
/// A plain `Navigator.pop(ctx)` in a bottom-sheet / dialog item handler pops
/// *whatever is on top*: on a rapid double tap (the sheet is still tappable
/// during its exit animation) the second tap popped the page underneath the
/// sheet and left the handler working with a dead page / disposed notifier.
bool closeRoute<T extends Object?>(BuildContext context, [T? result]) {
  if (!context.mounted) return false;
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive || !route.isCurrent) return false;
  Navigator.of(context).pop<T>(result);
  return true;
}
