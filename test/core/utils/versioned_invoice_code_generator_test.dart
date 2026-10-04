import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/code_generator_helper.dart';

void main() {
  group('Versioned Invoice Code Generator Tests (Phương án 1)', () {
    test('Standard invoice generates initial version code with underscore (_01)', () {
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259'), 'HD013259_01');
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD001234'), 'HD001234_01');
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD000001'), 'HD000001_01');
    });

    test('Incrementing already versioned invoice codes (_01 -> _02 -> _03)', () {
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259_01'), 'HD013259_02');
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259_02'), 'HD013259_03');
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259_09'), 'HD013259_10');
    });

    test('Never contains invalid Firebase Realtime Database characters (replaces . with _)', () {
      final code1 = CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259');
      final code2 = CodeGeneratorHelper.generateVersionedInvoiceCode('HD013259.01');
      final code3 = CodeGeneratorHelper.generateVersionedInvoiceCode('HD1234#01');

      expect(code2, 'HD013259_02');
      expect(code3, 'HD1234_02');

      for (final code in [code1, code2, code3]) {
        expect(code.contains('.'), isFalse, reason: 'Firebase keys must not contain dot');
        expect(code.contains('#'), isFalse);
        expect(code.contains(r'$'), isFalse);
        expect(code.contains('['), isFalse);
        expect(code.contains(']'), isFalse);
      }
    });

    test('Version increments work accurately with existing codes', () {
      expect(
        CodeGeneratorHelper.generateVersionedInvoiceCode(
          'HD013259',
          existingCodes: ['HD013259', 'HD013259_01'],
        ),
        'HD013259_02',
      );

      expect(
        CodeGeneratorHelper.generateVersionedInvoiceCode(
          'HD013259',
          existingCodes: ['HD013259_01', 'HD013259_02'],
        ),
        'HD013259_03',
      );
    });

    test('Handles empty and whitespace inputs gracefully', () {
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode(''), 'HD000001_01');
      expect(CodeGeneratorHelper.generateVersionedInvoiceCode('   '), 'HD000001_01');
    });
  });
}
