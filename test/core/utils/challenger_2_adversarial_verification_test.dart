import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/core/utils/vietnamese_text_helper.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  Product makeProduct({
    required String name,
    String category = 'Khác',
    String? brand,
    String? category3Levels,
    bool isCombo = false,
  }) {
    return Product(
      id: 'p_${name.hashCode}',
      name: name,
      code: 'TEST_R3',
      price: 150000,
      costPrice: 100000,
      branchStocks: const {'main_branch': 5},
      category: category,
      brand: brand,
      category3Levels: category3Levels,
      isCombo: isCombo,
    );
  }

  group('Challenger 2 Empirical Adversarial Verification Suite (R3)', () {
    const watchUrlFragment = 'photo-1523275335684-37898b6baf30';

    group('1. Furniture Terms Exact & Fuzzy Stress Testing', () {
      final furnitureExpectations = <String, String>{
        'Bàn chữ K': 'furniture_desks_work',
        'Bàn chữ Z gaming': 'furniture_desks_work',
        'Bàn vi tính': 'furniture_desks_work',
        'Bàn học sinh': 'furniture_desks_work',
        'Ghế xoay văn phòng': 'furniture_chairs_ergonomic',
        'Ghế công thái học': 'furniture_chairs_ergonomic',
        'Tủ quần áo': 'furniture_wardrobes_shelves',
        'Kệ sách mini': 'furniture_wardrobes_shelves',
        'Sofa nỉ': 'furniture_sofas_living',
      };

      for (final entry in furnitureExpectations.entries) {
        test('Furniture exact & variation match: "${entry.key}" -> ${entry.value}', () {
          // 1. Exact string
          final pExact = makeProduct(name: entry.key);
          final matchesExact = SampleImageHelper.getSuggestedImages(pExact);
          expect(matchesExact, isNotEmpty, reason: 'Expected matches for "${entry.key}"');
          expect(matchesExact.first.id, equals(entry.value),
              reason: 'Top match for "${entry.key}" must be ${entry.value}');

          // 2. Unaccented variation
          final unaccName = VietnameseTextHelper.normalizeUnaccented(entry.key);
          final pUnacc = makeProduct(name: unaccName);
          final matchesUnacc = SampleImageHelper.getSuggestedImages(pUnacc);
          expect(matchesUnacc, isNotEmpty, reason: 'Expected matches for unaccented "$unaccName"');
          expect(matchesUnacc.first.id, equals(entry.value),
              reason: 'Top match for unaccented "$unaccName" must be ${entry.value}');

          // 3. Extended realistic retail title
          final pExtended = makeProduct(name: 'Sản phẩm ${entry.key} cao cấp giá rẻ 2026 mẫu mới');
          final matchesExtended = SampleImageHelper.getSuggestedImages(pExtended);
          expect(matchesExtended, isNotEmpty);
          expect(matchesExtended.first.id, equals(entry.value));
        });
      }
    });

    group('2. Negative Keyword Trap Isolation', () {
      test('"Bàn phím cơ" must match tech keyboard, NOT desks', () {
        final p = makeProduct(name: 'Bàn phím cơ không dây Bluetooth Logitech K380');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty);
        expect(matches.first.id, equals('tech_keyboard_mouse'));
        expect(matches.any((m) => m.id == 'furniture_desks_work'), isFalse,
            reason: 'Negative keyword must block furniture_desks_work');
        expect(matches.any((m) => m.id == 'furniture_dining_living_tables'), isFalse);
      });

      test('"Bàn ủi hơi nước" must match appliances iron, NOT desks', () {
        final p = makeProduct(name: 'Bàn ủi hơi nước cầm tay Philips GC1740');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty);
        expect(matches.first.id, equals('home_cleaning_appliances'));
        expect(matches.any((m) => m.id == 'furniture_desks_work'), isFalse,
            reason: 'Negative keyword must block furniture_desks_work');
        expect(matches.any((m) => m.id == 'furniture_dining_living_tables'), isFalse);
      });

      test('"Bìa còng A4" must match stationery, NOT beer', () {
        final p = makeProduct(name: 'Bìa còng A4 Plus 7cm lưu trữ hồ sơ');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty);
        expect(matches.first.id, anyOf(equals('stationery_tools_calculators'), equals('stationery_notebooks_paper')));
        expect(matches.any((m) => m.id == 'beverage_beer'), isFalse,
            reason: 'Diacritic "bìa" must NOT trigger beverage_beer');
      });

      test('"Thước nhôm 30cm" must match stationery, NOT medicine', () {
        final p = makeProduct(name: 'Thước nhôm 30cm Deli văn phòng');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty);
        expect(matches.first.id, anyOf(equals('stationery_pens'), equals('stationery_tools_calculators')));
        expect(matches.any((m) => m.id == 'pharma_otc_medicines'), isFalse,
            reason: 'Diacritic "thước" must NOT trigger pharma_otc_medicines ("thuốc")');
      });

      test('"Mì tôm chua cay gói 75g" must match noodles, NOT bedding pillow', () {
        final p = makeProduct(name: 'Mì tôm chua cay gói 75g Hảo Hảo Acecook');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty);
        expect(matches.first.id, equals('food_instant_noodles'));
        expect(matches.any((m) => m.id == 'home_bedding_mattress'), isFalse,
            reason: '"gói" (packet) must NOT trigger home_bedding_mattress ("gối")');
      });
    });

    group('3. Fallback Elimination & Watch Photo Purge', () {
      final unmatchedInputs = [
        'XYZ_9999_TEST',
        'UnknownProduct12345',
        'random_item_gibberish_998877',
        '!!! @@@ ###',
        '',
        '   ',
      ];

      for (final input in unmatchedInputs) {
        test('Unmatched input "$input" returns empty string and NEVER watch URL', () {
          final p = makeProduct(name: input);
          final urlFromProduct = SampleImageHelper.getSampleImageUrl(p);
          final urlFromText = SampleImageHelper.getSampleImageUrlForText(input);

          expect(urlFromProduct, equals(''),
              reason: 'Unmatched product should return empty string for UI placeholder handling');
          expect(urlFromText, equals(''));

          expect(urlFromProduct.contains(watchUrlFragment), isFalse,
              reason: 'Watch URL must be completely purged');
          expect(urlFromText.contains(watchUrlFragment), isFalse);

          final suggestions = SampleImageHelper.getSuggestedImages(p);
          expect(suggestions, isEmpty, reason: 'No suggestion score should be generated for gibberish');
        });
      }

      test('Universal placeholder URL points to neutral package image, NEVER watch', () {
        expect(SampleImageHelper.universalPlaceholderUrl.contains(watchUrlFragment), isFalse);
        expect(SampleImageHelper.universalPlaceholderUrl, contains('photo-1586769852044-692d6e3703f0'));
      });
    });

    group('4. Snake_case & Uppercase Normalization', () {
      test('Uppercase and snake_case strings match expected categories', () {
        final pKDesk = makeProduct(name: 'BAN_CHU_K_120X60');
        final matchesK = SampleImageHelper.getSuggestedImages(pKDesk);
        expect(matchesK, isNotEmpty);
        expect(matchesK.first.id, equals('furniture_desks_work'));

        final pSwivel = makeProduct(name: 'GHE_XOAY_LUOI_VAN_PHONG');
        final matchesSwivel = SampleImageHelper.getSuggestedImages(pSwivel);
        expect(matchesSwivel, isNotEmpty);
        expect(matchesSwivel.first.id, equals('furniture_chairs_ergonomic'));

        final pSofa = makeProduct(name: 'SOFA_NI_PHONG_KHACH_2M');
        final matchesSofa = SampleImageHelper.getSuggestedImages(pSofa);
        expect(matchesSofa, isNotEmpty);
        expect(matchesSofa.first.id, equals('furniture_sofas_living'));

        final pIphone = makeProduct(name: 'IPHONE_15_PRO_MAX_256GB');
        final matchesIphone = SampleImageHelper.getSuggestedImages(pIphone);
        expect(matchesIphone, isNotEmpty);
        expect(matchesIphone.first.id, equals('tech_iphone'));
      });
    });
  });
}
