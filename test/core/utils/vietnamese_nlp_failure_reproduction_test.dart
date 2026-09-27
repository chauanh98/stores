import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  Product makeProduct(String name) {
    return Product(
      id: 'adv_${name.hashCode}',
      name: name,
      code: 'ADV_TEST',
      category: 'Khác',
      price: 50000,
      costPrice: 35000,
      branchStocks: const {'branch_1': 10},
    );
  }

  group('Adversarial Failure Mode Regression Guardrail Suite', () {
    test('TRAP 1 RESOLVED: Unaccented "gói" (packet) matches food_instant_noodles, NOT bedding', () {
      final p1 = makeProduct('mi omachi xot bo ham goi 80g');
      final matches1 = SampleImageHelper.getSuggestedImages(p1);
      
      expect(matches1.first.id, equals('food_instant_noodles'));
      expect(matches1.any((m) => m.id == 'home_bedding_mattress'), isFalse);
    });

    test('TRAP 2 RESOLVED: Underscore "_" in snake_case strings is correctly parsed for keyword matching', () {
      final pUnderscore = makeProduct('#123_IPHONE_15_PRO_MAX_512GB_TITAN_BLUE#');
      final matchesUnderscore = SampleImageHelper.getSuggestedImages(pUnderscore);
      expect(matchesUnderscore, isNotEmpty);
      expect(matchesUnderscore.first.id, equals('tech_iphone'));

      final pUnderscoreBeer = makeProduct('BIA_HEINEKEN_SILVER_LON_330ML');
      expect(SampleImageHelper.getSuggestedImages(pUnderscoreBeer), isNotEmpty);
      expect(SampleImageHelper.getSuggestedImages(pUnderscoreBeer).first.id, equals('beverage_beer'));
    });

    test('TRAP 3 RESOLVED: "Bìa" (folder) in "Bìa nhựa đựng tài liệu" matches stationery, NOT beer', () {
      final pFolder = makeProduct('Bìa nhựa đựng tài liệu A4');
      final matchesFolder = SampleImageHelper.getSuggestedImages(pFolder);
      
      expect(matchesFolder.first.id, equals('stationery_tools_calculators'));
      expect(matchesFolder.any((m) => m.id == 'beverage_beer'), isFalse);
    });

    test('TRAP 4 RESOLVED: "Mực in" (printer ink) matches stationery_pens, NOT seafood', () {
      final pInk = makeProduct('Mực in Laser Canon 2900 hộp mực đen');
      final matchesInk = SampleImageHelper.getSuggestedImages(pInk);
      
      expect(matchesInk.first.id, equals('stationery_pens'));
      expect(matchesInk.any((m) => m.id == 'fresh_meat_seafood'), isFalse);
    });

    test('TRAP 5 RESOLVED: "Thước" (ruler) matches stationery, NOT pharma medicines', () {
      final pRuler = makeProduct('Thước nhôm 30cm văn phòng');
      final matchesRuler = SampleImageHelper.getSuggestedImages(pRuler);
      
      expect(matchesRuler.first.id, equals('stationery_tools_calculators'));
      expect(matchesRuler.any((m) => m.id == 'pharma_otc_medicines'), isFalse);
    });

    test('TRAP 6 RESOLVED: "Sổ" (notebook) matches stationery_notebooks_paper, NOT seafood', () {
      final pNotebook = makeProduct('Sổ còng đa năng cao cấp A5');
      final matchesNotebook = SampleImageHelper.getSuggestedImages(pNotebook);
      
      expect(matchesNotebook.first.id, equals('stationery_notebooks_paper'));
      expect(matchesNotebook.any((m) => m.id == 'fresh_meat_seafood'), isFalse);
    });

    test('TRAP 7 RESOLVED: Keyword score deduplication prevents double scoring for accented/unaccented pairs', () {
      final pAcc = makeProduct('rượu');
      final pUnacc = makeProduct('ruou');
      
      final scoreAcc = SampleImageHelper.getSuggestedImages(pAcc).first.score;
      final scoreUnacc = SampleImageHelper.getSuggestedImages(pUnacc).first.score;
      
      expect(scoreUnacc, equals(30));
      expect(scoreAcc, equals(30));
    });
  });
}
