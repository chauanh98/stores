import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 4-column touch numpad widget designed for rapid mobile touch input in POS and stock-in workflows.
/// Matches video DATA_IMPORT/video_2026-09-27_07-41-44.mp4 (00:15 - 00:33) and KiotViet accounting aesthetics.
class AccountingNumpad extends StatelessWidget {
  /// Invoked when a numeric digit or decimal dot is pressed ('0'-'9', '00', '000', '.').
  final ValueChanged<String>? onDigit;

  /// Invoked when the backspace key is pressed.
  final VoidCallback? onDelete;

  /// Invoked when the clear ('C') key is pressed.
  final VoidCallback? onClear;

  /// Invoked when the action/done ('Nhập') key is pressed.
  final VoidCallback? onDone;

  /// Generic keypress callback compatible with test harnesses.
  final ValueChanged<String>? onKeyPress;

  /// Generic enter callback compatible with test harnesses.
  final VoidCallback? onEnter;

  /// Optional background color for the numpad container.
  final Color? backgroundColor;

  /// Optional height for each key row.
  final double rowHeight;

  const AccountingNumpad({
    super.key,
    this.onDigit,
    this.onDelete,
    this.onClear,
    this.onDone,
    this.onKeyPress,
    this.onEnter,
    this.backgroundColor,
    this.rowHeight = 46.0,
  });

  static const List<List<String>> _keyRows = [
    ['1', '2', '3', 'backspace'],
    ['4', '5', '6', 'clear'],
    ['7', '8', '9', '000'],
    ['.', '0', '00', 'enter'],
  ];

  void _handleKeyTap(String key) {
    if (key == 'backspace') {
      onDelete?.call();
      onKeyPress?.call('backspace');
    } else if (key == 'clear') {
      onClear?.call();
      onKeyPress?.call('clear');
    } else if (key == 'enter') {
      onDone?.call();
      onEnter?.call();
      onKeyPress?.call('enter');
    } else {
      onDigit?.call(key);
      onKeyPress?.call(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? AppColors.surface;

    return Container(
      key: const Key('accounting_numpad'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: const Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _keyRows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              children: row.map((k) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: _buildKeyButton(context, k, theme),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyButton(BuildContext context, String k, ThemeData theme) {
    Widget content;
    Key buttonKey;
    Color buttonBgColor = AppColors.white;
    Color textColor = AppColors.textTitle;
    Border? border;

    if (k == 'backspace') {
      buttonKey = const Key('numpad_backspace');
      content = const Icon(Icons.backspace_outlined,
          size: 20, color: AppColors.textSlate600);
      buttonBgColor = AppColors.surfaceLight;
    } else if (k == 'clear') {
      buttonKey = const Key('numpad_clear');
      content = const Text(
        'C',
        style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.dangerMedium),
      );
      buttonBgColor = AppColors.dangerSubtle;
      border = Border.all(color: AppColors.dangerBorder, width: 1);
    } else if (k == 'enter') {
      buttonKey = const Key('numpad_enter');
      content = const Text(
        'Nhập',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryAction,
          letterSpacing: 0.2,
        ),
      );
      buttonBgColor = AppColors.infoSubtle;
      border = Border.all(color: AppColors.infoBorder, width: 1);
    } else {
      buttonKey = Key('numpad_$k');
      final isAccent = k == '000' || k == '00';
      content = Text(
        k,
        style: TextStyle(
          fontSize: isAccent ? 16 : 19,
          fontWeight: isAccent ? FontWeight.w700 : FontWeight.w600,
          color: textColor,
        ),
      );
    }

    return Material(
      color: buttonBgColor,
      borderRadius: BorderRadius.circular(8),
      elevation: 0.8,
      shadowColor: AppColors.black.withOpacity(0.06),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleKeyTap(k),
        splashColor: theme.colorScheme.primary.withOpacity(0.12),
        highlightColor: theme.colorScheme.primary.withOpacity(0.06),
        child: Container(
          height: rowHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border:
                border ?? Border.all(color: AppColors.borderLight, width: 0.8),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Backward compatibility alias for test suites and alternate references.
typedef AccountingNumpadWidget = AccountingNumpad;
