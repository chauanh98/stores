import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// FAB tự ẩn khi scroll xuống, hiện lại khi scroll lên.
/// Dùng slide animation tự nhiên.
class ScrollAwareFab extends StatefulWidget {
  const ScrollAwareFab({
    super.key,
    required this.scrollController,
    required this.child,
  });

  /// ScrollController của danh sách cần theo dõi
  final ScrollController scrollController;

  /// Widget FAB gốc (thường là FloatingActionButton)
  final Widget child;

  @override
  State<ScrollAwareFab> createState() => _ScrollAwareFabState();
}

class _ScrollAwareFabState extends State<ScrollAwareFab>
    with SingleTickerProviderStateMixin {
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ScrollAwareFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final direction = widget.scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _isVisible) {
      setState(() => _isVisible = false);
    } else if (direction == ScrollDirection.forward && !_isVisible) {
      setState(() => _isVisible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: _isVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isVisible ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !_isVisible,
          child: widget.child,
        ),
      ),
    );
  }
}
