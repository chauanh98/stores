import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/smart_cash_helper.dart';

void main() {
  group('SmartCashHelper Unit Tests', () {
    test('generateSmartCashSuggestions returns empty list for netPay <= 0', () {
      expect(SmartCashHelper.generateSmartCashSuggestions(0), isEmpty);
      expect(SmartCashHelper.generateSmartCashSuggestions(-50000), isEmpty);
    });

    test('generateSmartCashSuggestions for netPay = 340,000đ matches expected suggestions', () {
      final suggestions = SmartCashHelper.generateSmartCashSuggestions(340000);
      // Expected: [340,000 (Trả đủ), 350,000, 400,000, 500,000, 1,000,000]
      expect(suggestions.first, 340000.0);
      expect(suggestions, contains(340000.0));
      expect(suggestions, contains(350000.0));
      expect(suggestions, contains(400000.0));
      expect(suggestions, contains(500000.0));
      expect(suggestions, contains(1000000.0));
      expect(suggestions.length, lessThanOrEqualTo(5));

      // Sorted ascending
      for (int i = 0; i < suggestions.length - 1; i++) {
        expect(suggestions[i], lessThan(suggestions[i + 1]));
      }
    });

    test('generateSmartCashSuggestions for netPay = 12,500đ', () {
      final suggestions = SmartCashHelper.generateSmartCashSuggestions(12500);
      expect(suggestions.first, 12500.0);
      expect(suggestions, contains(20000.0));
      expect(suggestions, contains(50000.0));
      expect(suggestions, contains(100000.0));
      expect(suggestions.length, lessThanOrEqualTo(5));
    });

    test('generateSmartCashSuggestions for netPay = 500,000đ (round base)', () {
      final suggestions = SmartCashHelper.generateSmartCashSuggestions(500000);
      expect(suggestions.first, 500000.0);
      expect(suggestions, contains(1000000.0));
      expect(suggestions.length, greaterThanOrEqualTo(2));
      for (final s in suggestions) {
        expect(s, greaterThanOrEqualTo(500000.0));
      }
    });

    test('generateSmartCashSuggestions for netPay = 1,250,000đ (large amount)', () {
      final suggestions = SmartCashHelper.generateSmartCashSuggestions(1250000);
      expect(suggestions.first, 1250000.0);
      for (final s in suggestions) {
        expect(s, greaterThanOrEqualTo(1250000.0));
      }
      expect(suggestions.length, lessThanOrEqualTo(5));
      for (int i = 0; i < suggestions.length - 1; i++) {
        expect(suggestions[i], lessThan(suggestions[i + 1]));
      }
    });

    test('generateSmartCashSuggestions respects maxSuggestions parameter', () {
      final suggestions = SmartCashHelper.generateSmartCashSuggestions(123456, maxSuggestions: 3);
      expect(suggestions.length, 3);
      expect(suggestions.first, 123456.0);
    });
  });
}
