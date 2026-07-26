import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,###', 'vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. If text is empty, return empty
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // 2. Handle backspace on non-digit separator character (e.g. '.')
    String textToParse = newValue.text;
    if (oldValue.text.length - newValue.text.length == 1) {
      final oldCursor = oldValue.selection.baseOffset;
      if (oldCursor > 0 && oldCursor <= oldValue.text.length) {
        final deletedChar = oldValue.text[oldCursor - 1];
        if (deletedChar == '.' || deletedChar == ',') {
          // User pressed backspace on a dot separator; delete the digit before it
          if (oldCursor - 1 > 0) {
            textToParse = oldValue.text.substring(0, oldCursor - 2) +
                oldValue.text.substring(oldCursor);
          }
        }
      }
    }

    final digitsOnly = textToParse.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // 3. Format the number
    final number = int.tryParse(digitsOnly) ?? 0;
    final newText = _formatter.format(number);

    // 4. Preserve full selection or calculate intelligent cursor position
    if (newValue.selection.baseOffset == 0 &&
        newValue.selection.extentOffset == newValue.text.length) {
      return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: 0, extentOffset: newText.length),
      );
    }

    // Calculate cursor position based on number of digits before cursor
    final int digitsBeforeCursor;
    if (newValue.selection.baseOffset <= newValue.text.length) {
      digitsBeforeCursor = newValue.text
          .substring(
              0, newValue.selection.baseOffset.clamp(0, newValue.text.length))
          .replaceAll(RegExp(r'\D'), '')
          .length;
    } else {
      digitsBeforeCursor = digitsOnly.length;
    }

    int selectionIndex = newText.length;
    int currentDigits = 0;
    for (int i = 0; i < newText.length; i++) {
      if (RegExp(r'\d').hasMatch(newText[i])) {
        currentDigits++;
      }
      if (currentDigits == digitsBeforeCursor) {
        selectionIndex = i + 1;
        break;
      }
    }
    if (digitsBeforeCursor == 0) {
      selectionIndex = 0;
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: selectionIndex.clamp(0, newText.length)),
    );
  }
}
