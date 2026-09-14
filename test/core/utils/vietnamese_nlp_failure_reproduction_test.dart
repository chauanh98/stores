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

  group('Adversarial Failure Mode Reproduction Suite', () {
    test('TRAP 1: Unaccented "gói" (packet) falsely matches "gối" (pillow in bedding) due to double scoring and non-diacritic distinction', () {
      final p1 = makeProduct('mi omachi xot bo ham goi 80g');
      final matches1 = SampleImageHelper.getSuggestedImages(p1);
      
      // EMPIRICAL OBSERVATION: home_furniture_bedding wins over food_instant_noodles
      expect(matches1.first.id, equals('home_furniture_bedding'));
      expect(matches1.first.score, equals(44)); // priority 14 + 15 ('goi') + 15 ('gối' unaccented)
      
      final noodleMatch = matches1.firstWhere((m) => m.id == 'food_instant_noodles');
      expect(noodleMatch.score, equals(30)); // priority 15 + 15 ('omachi')
    });

    test('TRAP 2: Underscore "_" in snake_case strings prevents word boundary recognition', () {
      final pUnderscore = makeProduct('#123_IPHONE_15_PRO_MAX_512GB_TITAN_BLUE#');
      final matchesUnderscore = SampleImageHelper.getSuggestedImages(pUnderscore);
      expect(matchesUnderscore, isEmpty);
      expect(SampleImageHelper.getSampleImageUrl(pUnderscore), equals(SampleImageHelper.universalPlaceholderUrl));

      final pUnderscoreBeer = makeProduct('BIA_HEINEKEN_SILVER_LON_330ML');
      expect(SampleImageHelper.getSuggestedImages(pUnderscoreBeer), isEmpty);
    });

    test('TRAP 3: Unaccented "Bìa" (folder) in "Bìa nhựa đựng tài liệu" falsely matches "bia" (beer)', () {
      final pFolder = makeProduct('Bìa nhựa đựng tài liệu A4');
      final matchesFolder = SampleImageHelper.getSuggestedImages(pFolder);
      
      // beverage_beer scores 30+ while stationery scores 0
      expect(matchesFolder.first.id, equals('beverage_beer'));
    });

    test('TRAP 4: Unaccented "Mực in" (printer ink) matches "mực" (squid in fresh_meat_seafood)', () {
      final pInk = makeProduct('Mực in Laser Canon 2900 hộp mực đen');
      final matchesInk = SampleImageHelper.getSuggestedImages(pInk);
      
      expect(matchesInk.first.id, equals('fresh_meat_seafood'));
    });

    test('TRAP 5: Unaccented "Thước" (ruler) matches "thuốc" (medicine in pharma_otc_medicines)', () {
      final pRuler = makeProduct('Thước nhôm 30cm văn phòng');
      final matchesRuler = SampleImageHelper.getSuggestedImages(pRuler);
      
      expect(matchesRuler.first.id, equals('pharma_otc_medicines'));
    });

    test('TRAP 6: Unaccented "Sổ" (notebook) in non-compound names matches "sò" (clam in fresh_meat_seafood)', () {
      final pNotebook = makeProduct('Sổ còng đa năng cao cấp A5');
      final matchesNotebook = SampleImageHelper.getSuggestedImages(pNotebook);
      
      expect(matchesNotebook.first.id, equals('fresh_meat_seafood'));
    });

    test('TRAP 7: Double scoring anomaly: keywords having both accented and unaccented entries receive 2x points for unaccented queries', () {
      // In SampleImageHelper, beverage_beer has both 'bia' and 'bia chai' / 'bia lon', and 'ruou' and 'rượu'.
      // For input 'ruou vang da lat', 'ruou' matches kw 'ruou' (+15) AND kw 'rượu' (+15) -> +30 points from single word
      final pAcc = makeProduct('rượu');
      final pUnacc = makeProduct('ruou');
      
      final scoreAcc = SampleImageHelper.getSuggestedImages(pAcc).first.score;
      final scoreUnacc = SampleImageHelper.getSuggestedImages(pUnacc).first.score;
      
      // Both match twice because kw list contains both accented and unaccented tokens
      expect(scoreUnacc, equals(45)); // priority 15 + 15 ('ruou') + 15 ('rượu')
      expect(scoreAcc, equals(45));
    });
  });
}
