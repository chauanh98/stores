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
      id: 'adv_${name.hashCode}',
      name: name,
      code: 'ADV_TEST',
      price: 50000,
      costPrice: 35000,
      branchStocks: const {'branch_1': 10},
      category: category,
      brand: brand,
      category3Levels: category3Levels,
      isCombo: isCombo,
    );
  }

  group('Adversarial Vietnamese NLP & Image Trap Challenge', () {
    group('Dimension 1: Substring Collision Traps & Boundary Protection', () {
      test('"khăn ướt" / "khăn lau" does NOT collide with "ăn"', () {
        // VietnameseTextHelper boundary verification
        expect(VietnameseTextHelper.containsWord('khăn ướt em bé bobby', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('khăn lau mặt cotton cao cấp', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('khăn giấy lụa tempo', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('khan uot em be', 'an'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('khan lau mat', 'an'), isFalse);

        // SampleImageHelper category matching verification
        final pWetWipes = makeProduct(name: 'Khăn ướt Bobby không mùi 80 miếng gói');
        final matchesWipes = SampleImageHelper.getSuggestedImages(pWetWipes);
        expect(matchesWipes, isNotEmpty);
        expect(matchesWipes.first.id, equals('fmcg_tissue'));
        expect(matchesWipes.any((m) => m.id.startsWith('food_')), isFalse);

        final pBabyWipes = makeProduct(name: 'khan uot huggies cao cap 64 to');
        final matchesBaby = SampleImageHelper.getSuggestedImages(pBabyWipes);
        expect(matchesBaby, isNotEmpty);
        expect(matchesBaby.any((m) => m.id.startsWith('food_')), isFalse);
      });

      test('"báo cáo" / "quảng cáo" / "thông báo" / "phao" does NOT collide with "áo"', () {
        // VietnameseTextHelper boundary verification
        expect(VietnameseTextHelper.containsWord('báo cáo doanh thu tháng 8', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('biển quảng cáo mica led', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('bảng thông báo nội bộ', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('phao cứu sinh', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('bao cao tai chinh', 'ao'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('bien quang cao', 'ao'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('thong bao khan cap', 'ao'), isFalse);

        // SampleImageHelper category matching verification
        final pReport = makeProduct(name: 'Bìa còng lưu báo cáo tài chính A4 KingJim');
        final matchesReport = SampleImageHelper.getSuggestedImages(pReport);
        expect(matchesReport, isNotEmpty);
        expect(matchesReport.first.id, equals('stationery_tools_calculators'));
        expect(matchesReport.any((m) => m.id.startsWith('fashion_')), isFalse);

        final pNotice = makeProduct(name: 'Sổ tay ghi thông báo cuộc họp bìa da');
        final matchesNotice = SampleImageHelper.getSuggestedImages(pNotice);
        expect(matchesNotice, isNotEmpty);
        expect(matchesNotice.first.id, equals('stationery_notebooks_paper'));
        expect(matchesNotice.any((m) => m.id.startsWith('fashion_')), isFalse);
      });

      test('"bàn ăn" matches furniture, NOT food; "bàn chải" matches oral care; "bàn phím" matches tech', () {
        final pDiningTable = makeProduct(name: 'Bàn ăn tròn 6 ghế gỗ sồi tự nhiên Hoàng Anh Gia Lai');
        final matchesDining = SampleImageHelper.getSuggestedImages(pDiningTable);
        expect(matchesDining, isNotEmpty);
        expect(matchesDining.first.id, equals('furniture_dining_living_tables'));
        expect(matchesDining.any((m) => m.id.startsWith('food_')), isFalse);

        final pToothbrush = makeProduct(name: 'Bàn chải đánh răng P/S than tre hoạt tính lông tơ');
        final matchesToothbrush = SampleImageHelper.getSuggestedImages(pToothbrush);
        expect(matchesToothbrush, isNotEmpty);
        expect(matchesToothbrush.first.id, equals('fmcg_oral'));
        expect(matchesToothbrush.any((m) => m.id.startsWith('furniture_')), isFalse);

        final pKeyboard = makeProduct(name: 'Bàn phím cơ không dây Bluetooth Logitech K380');
        final matchesKeyboard = SampleImageHelper.getSuggestedImages(pKeyboard);
        expect(matchesKeyboard, isNotEmpty);
        expect(matchesKeyboard.first.id, equals('tech_keyboard_mouse'));
        expect(matchesKeyboard.any((m) => m.id.startsWith('furniture_')), isFalse);

        final pIron = makeProduct(name: 'Bàn là hơi nước đứng Philips GC518');
        final matchesIron = SampleImageHelper.getSuggestedImages(pIron);
        expect(matchesIron, isNotEmpty);
        expect(matchesIron.first.id, equals('home_cleaning_appliances'));
        expect(matchesIron.any((m) => m.id.startsWith('furniture_')), isFalse);
      });

      test('"nước giặt" vs "nước ngọt" vs "nước suối" vs "nước mắm" vs "nước hoa" distinct isolation', () {
        final pLaundry = makeProduct(name: 'Nước giặt Surf hương hoa cỏ may túi 3.5kg');
        expect(SampleImageHelper.getSuggestedImages(pLaundry).first.id, equals('fmcg_laundry'));
        expect(SampleImageHelper.getSuggestedImages(pLaundry).any((m) => m.id.startsWith('beverage_')), isFalse);

        final pSoda = makeProduct(name: 'Nước ngọt Mirinda hương xá xị lon 320ml');
        expect(SampleImageHelper.getSuggestedImages(pSoda).first.id, equals('beverage_soda'));
        expect(SampleImageHelper.getSuggestedImages(pSoda).any((m) => m.id.startsWith('fmcg_')), isFalse);

        final pWater = makeProduct(name: 'Nước khoáng Vĩnh Hảo có ga 500ml');
        expect(SampleImageHelper.getSuggestedImages(pWater).first.id, equals('beverage_water'));
        expect(SampleImageHelper.getSuggestedImages(pWater).any((m) => m.id.startsWith('fmcg_')), isFalse);

        final pFishSauce = makeProduct(name: 'Nước mắm Chinsu cá hồi thượng hạng 500ml');
        expect(SampleImageHelper.getSuggestedImages(pFishSauce).first.id, equals('food_seasoning_oil'));
        expect(SampleImageHelper.getSuggestedImages(pFishSauce).any((m) => m.id.startsWith('beverage_')), isFalse);

        final pPerfume = makeProduct(name: 'Nước hoa Nữ Chanel Coco Mademoiselle 100ml');
        expect(SampleImageHelper.getSuggestedImages(pPerfume).first.id, equals('cosmetics_perfume'));
        expect(SampleImageHelper.getSuggestedImages(pPerfume).any((m) => m.id.startsWith('beverage_')), isFalse);

        final pEyeDrop = makeProduct(name: 'Nước nhỏ mắt V.Rohto New bảo vệ thị lực 13ml');
        expect(SampleImageHelper.getSuggestedImages(pEyeDrop).first.id, equals('pharma_otc_medicines'));
        expect(SampleImageHelper.getSuggestedImages(pEyeDrop).any((m) => m.id.startsWith('beverage_')), isFalse);
      });
    });

    group('Dimension 2: Unaccented Strings with Slang, Heavy Casing, Numbers & Retail Brands', () {
      test('Handles all unaccented beverage & FMCG retail items correctly', () {
        final cases = <String, String>{
          'nuoc ngot pepsi khong duong lon 320ml': 'beverage_soda',
          'sting dau lon cao 330ml': 'beverage_soda',
          'bo huc thai lan 250ml': 'beverage_soda',
          'bia tiger bac lon 330ml thung 24 lon': 'beverage_beer',
          'bia heineken silver chai 330ml': 'beverage_beer',
          'sua tuoi tiet trung co gai ha lan it duong 1l': 'beverage_milk',
          'sua dac co ong tho hop thiec 380g': 'beverage_milk',
          'ca phe hoa tan g7 3in1 trung nguyen hop 18 goi': 'beverage_coffee',
          'tra o long tea plus chai 455ml': 'beverage_tea',
          'tra sua matcha phuc long lon': 'beverage_tea',
          'nuoc tinh khiet dasani chai 500ml': 'beverage_water',
          'nuoc ep trai cay twister cam 1l': 'beverage_juice',
          'nuoc giat omo matic cua truoc 3.6kg': 'fmcg_laundry',
          'nuoc xa vai downy huyen bi tui 3.5l': 'fmcg_laundry',
          'nuoc lau san sunlight huong hoa ha chai 1kg': 'fmcg_cleaning',
          'nuoc tay bon cau vim diet khuan 880ml': 'fmcg_cleaning',
          'kem danh rang closeup bac ha thom mat 230g': 'fmcg_oral',
          'dau goi head and shoulders sach gau 650ml': 'fmcg_body_wash',
          'sua tam dove duong am sau 900g': 'fmcg_body_wash',
          'giay ve sinh pulppy 2 lop loc 10 cuon': 'fmcg_tissue',
        };

        for (final entry in cases.entries) {
          final p = makeProduct(name: entry.key);
          final matches = SampleImageHelper.getSuggestedImages(p);
          expect(
            matches.isNotEmpty && matches.first.id == entry.value,
            isTrue,
            reason: 'Failed for unaccented item: "${entry.key}", got: ${matches.isEmpty ? "NONE" : matches.first.id}, expected: ${entry.value}',
          );
        }
      });

      test('Handles all unaccented food, fashion, tech & home items correctly', () {
        final cases = <String, String>{
          'mi tom omachi xot bo ham 80g': 'food_instant_noodles',
          'banh chocopie orion hop 12 cai': 'food_cookies_snacks',
          'snack khoai tay oishi vi pho mai': 'food_cookies_snacks',
          'keo m&m socola dau phong goi 45g': 'food_candies_chocolate',
          'dau an neptune light chai 1l': 'food_seasoning_oil',
          'gao thom lai sua st25 tui 5kg': 'food_rice_grains',
          'xuc xich tiet trung vissan goi 5 cay': 'food_canned_sausage',
          'son kem li 3ce taupe mau do dat': 'cosmetics_lipstick',
          'kem chong nang la roche-posay anthelios 50ml': 'cosmetics_skincare',
          'ao khoac gio the north face unisex': 'fashion_outerwear',
          'quan jean nam levis 511 slim fit': 'fashion_pants',
          'giay the thao nike air jordan 1 retro': 'shoes_sneakers',
          'tui deo cheo nu da bo cao cap': 'bags_handbags',
          'balo laptop chong nuoc arctic hunter 15.6 inch': 'bags_backpacks',
          'dien thoai samsung galaxy s24 ultra 512gb': 'tech_android',
          'laptop macbook air m2 8gb 256gb': 'tech_laptop',
          'tai nghe airpods pro 2 type c': 'tech_earbuds',
          'cu sac nhanh anker 65w ganprime': 'tech_chargers_cables',
          'noi chien khong dau lock and lock 5.2l': 'home_kitchen_appliances',
          'may do huyet ap omron hem 7120': 'pharma_medical_devices',
          'but bi thien long tl027 hop 20 cay': 'stationery_pens',
          'ta quan moony man size l 44 mieng': 'baby_diapers',
          'thuc an cho meo royal canin kitten 2kg': 'pet_food',
        };

        for (final entry in cases.entries) {
          final p = makeProduct(name: entry.key);
          final matches = SampleImageHelper.getSuggestedImages(p);
          expect(
            matches.isNotEmpty && matches.first.id == entry.value,
            isTrue,
            reason: 'Failed for unaccented item: "${entry.key}", got: ${matches.isEmpty ? "NONE" : matches.first.id}, expected: ${entry.value}',
          );
        }
      });

      test('Extreme casing, weird symbols, multiple spaces, and discount tags resilience', () {
        final p1 = makeProduct(name: '  [HOT SALE 50%] - nUoC   gIaT   oMo   MaTiC   3.8kG !!!  ');
        expect(SampleImageHelper.getSuggestedImages(p1).first.id, equals('fmcg_laundry'));

        final p2 = makeProduct(name: '*** BIA HEINEKEN SILVER 330ML [LỐC 6 LON] ***');
        expect(SampleImageHelper.getSuggestedImages(p2).first.id, equals('beverage_beer'));

        final p3 = makeProduct(name: '<<< GẠO ST25 ÔNG CUA CHÍNH HÃNG (TÚI 5KG) >>>');
        expect(SampleImageHelper.getSuggestedImages(p3).first.id, equals('food_rice_grains'));

        final p4 = makeProduct(name: '--- Son Kem Lì 3CE #Taupe Edition 2026 ---');
        expect(SampleImageHelper.getSuggestedImages(p4).first.id, equals('cosmetics_lipstick'));

        final p5 = makeProduct(name: '#123-IPHONE-15-PRO-MAX-512GB-TITAN-BLUE#');
        expect(SampleImageHelper.getSuggestedImages(p5).first.id, equals('tech_iphone'));
      });
    });

    group('Dimension 3: Negative Keyword Exclusion Strict Stress Test', () {
      test('"Ốp lưng iPhone 15 Pro Max" matches Cases, NOT iPhone', () {
        final p = makeProduct(name: 'Ốp lưng dẻo trong suốt MagSafe cho iPhone 15 Pro Max');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('tech_cases_protectors'));
        expect(matches.any((m) => m.id == 'tech_iphone'), isFalse);
      });

      test('"Bao da iPad Pro 11 inch" matches Cases, NOT Tablet', () {
        final p = makeProduct(name: 'Bao da nắp gập thông minh cho iPad Pro 11 M2');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('tech_cases_protectors'));
        expect(matches.any((m) => m.id == 'tech_tablet'), isFalse);
      });

      test('"Kính cường lực Samsung Galaxy S24" matches Cases/Protectors, NOT Android phone', () {
        final p = makeProduct(name: 'Kính cường lực KingKong 9D chống nhìn trộm cho Samsung Galaxy S24');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('tech_cases_protectors'));
        expect(matches.any((m) => m.id == 'tech_android'), isFalse);
      });

      test('"Túi chống sốc MacBook Pro 14 inch" matches Bags, NOT Laptop', () {
        final p = makeProduct(name: 'Túi chống sốc lót nhung cao cấp cho MacBook Pro 14 inch M3');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('bags_backpacks'));
        expect(matches.any((m) => m.id == 'tech_laptop'), isFalse);
      });

      test('"Sữa tắm Hazeline matcha lựu đỏ" matches Body Wash, NOT Milk drink', () {
        final p = makeProduct(name: 'Sữa tắm sáng da Hazeline Matcha Lựu Đỏ chai 900g');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('fmcg_body_wash'));
        expect(matches.any((m) => m.id == 'beverage_milk'), isFalse);
      });

      test('"Sữa rửa mặt Simple dịu lành" matches Skincare, NOT Milk drink', () {
        final p = makeProduct(name: 'Sữa rửa mặt Simple Kind to Skin Refreshing Facial Wash 150ml');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('cosmetics_skincare'));
        expect(matches.any((m) => m.id == 'beverage_milk'), isFalse);
      });

      test('"Dầu gió xanh Con Ó 24ml" matches OTC Medicine, NOT Cooking oil', () {
        final p = makeProduct(name: 'Dầu gió xanh Con Ó Eagle Brand Medicated Oil 24ml');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('pharma_otc_medicines'));
        expect(matches.any((m) => m.id == 'food_seasoning_oil'), isFalse);
      });

      test('"Nước cam ép Vfresh 1L" matches Juice, NOT Fresh fruit', () {
        final p = makeProduct(name: 'Nước ép cam nguyên chất Vfresh hộp 1L');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('beverage_juice'));
        expect(matches.any((m) => m.id == 'fresh_fruits'), isFalse);
      });

      test('"Giấy in Double A A4 70gsm" matches Office Paper, NOT Tissues', () {
        final p = makeProduct(name: 'Giấy in A4 Double A 70gsm ream 500 tờ');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('stationery_notebooks_paper'));
        expect(matches.any((m) => m.id == 'fmcg_tissue'), isFalse);
      });
    });

    group('Dimension 4: Metadata Fields (Brand, Category, Category3Levels, Combos)', () {
      test('Resolves image when keyword is in Brand or Category rather than Product Name', () {
        final pBrand = makeProduct(
          name: 'Nước giải khát vị cam 330ml',
          category: 'Đồ uống có ga',
          brand: 'Mirinda',
        );
        expect(SampleImageHelper.getSuggestedImages(pBrand).first.id, equals('beverage_soda'));

        final pSkincare = makeProduct(
          name: 'Kem dưỡng ẩm phục hồi da 50ml',
          category: 'Chăm sóc da',
          brand: 'La Roche-Posay',
        );
        expect(SampleImageHelper.getSuggestedImages(pSkincare).first.id, equals('cosmetics_skincare'));

        final pPet = makeProduct(
          name: 'Hạt dinh dưỡng cao cấp cho mèo lớn 1.5kg',
          category: 'Thú cưng',
          brand: 'Royal Canin',
        );
        expect(SampleImageHelper.getSuggestedImages(pPet).first.id, equals('pet_food'));

        final pCleaning = makeProduct(
          name: 'Chai xịt tẩy rửa đa năng 500ml',
          category: 'Hóa phẩm vệ sinh',
          brand: 'Sunlight',
        );
        expect(SampleImageHelper.getSuggestedImages(pCleaning).first.id, equals('fmcg_cleaning'));
      });

      test('Combos and gift sets always prioritize combo image', () {
        final pCombo = makeProduct(
          name: 'Giỏ quà tết Phú Quý 2026',
          category: 'Quà tặng',
          isCombo: true,
        );
        final matches = SampleImageHelper.getSuggestedImages(pCombo);
        expect(matches.first.id, equals('gift_combo'));
        expect(SampleImageHelper.getSampleImageUrl(pCombo), equals(matches.first.imageUrl));
      });
    });

    group('Dimension 5: Empty, Malformed, Unknown Inputs & Fallback Safety', () {
      test('Empty string returns empty string fallback, never watch photo URL', () {
        final p = makeProduct(name: '');
        final url = SampleImageHelper.getSampleImageUrl(p);
        expect(url, equals(''));
        expect(url.contains('photo-1523275335684-37898b6baf30'), isFalse);
        expect(SampleImageHelper.universalPlaceholderUrl, contains('photo-1586769852044-692d6e3703f0'));
        expect(SampleImageHelper.getSuggestedImages(p), isEmpty);
      });

      test('Whitespace-only string returns empty string fallback without error', () {
        final p = makeProduct(name: '      ');
        final url = SampleImageHelper.getSampleImageUrl(p);
        expect(url, equals(''));
        expect(SampleImageHelper.getSuggestedImages(p), isEmpty);
      });

      test('Gibberish, numbers only, or special characters only returns empty string fallback', () {
        final cases = ['1234567890', '!@#\$%^&*()_+=-', 'qwertyuiopasdfghjklzxcvbnm9999'];
        for (final c in cases) {
          final p = makeProduct(name: c);
          expect(SampleImageHelper.getSampleImageUrl(p), equals(''));
          expect(SampleImageHelper.getSuggestedImages(p), isEmpty);
        }
      });

      test('getSampleImageUrlForText matches direct text inputs and returns empty on empty string', () {
        final urlOmo = SampleImageHelper.getSampleImageUrlForText('Bột giặt Omo 5kg');
        expect(urlOmo, isNotEmpty);
        expect(urlOmo, isNot(equals('')));
        expect(urlOmo.contains('photo-1523275335684-37898b6baf30'), isFalse);

        final urlEmpty = SampleImageHelper.getSampleImageUrlForText('');
        expect(urlEmpty, equals(''));
      });
    });

    group('Dimension 6: Milestone M3 Furniture Precision, Snake Case & Diacritic Disambiguation Suite', () {
      test('Snake case and underscore strings match correctly across categories', () {
        final pKDesk = makeProduct(name: 'BÀN_CHỮ_K_GAMING_120X60');
        expect(SampleImageHelper.getSuggestedImages(pKDesk).first.id, equals('furniture_desks_work'));

        final pIphone = makeProduct(name: '#123_IPHONE_15_PRO_MAX_512GB_TITAN_BLUE#');
        expect(SampleImageHelper.getSuggestedImages(pIphone).first.id, equals('tech_iphone'));

        final pBeer = makeProduct(name: 'BIA_HEINEKEN_SILVER_LON_330ML');
        expect(SampleImageHelper.getSuggestedImages(pBeer).first.id, equals('beverage_beer'));
      });

      test('Diacritic collision prevention: folder (bìa), ruler (thước), ink (mực), notebook (sổ), packet (gói)', () {
        // "Bìa nhựa" must NOT match beverage_beer
        final pFolder = makeProduct(name: 'Bìa nhựa còng A4 lưu hồ sơ KingJim');
        final matchesFolder = SampleImageHelper.getSuggestedImages(pFolder);
        expect(matchesFolder.any((m) => m.id == 'beverage_beer'), isFalse);

        // "Mì gói" must match food_instant_noodles, NOT home_bedding_mattress
        final pNoodles = makeProduct(name: 'Mì tôm xốt bò hầm gói 80g');
        final matchesNoodles = SampleImageHelper.getSuggestedImages(pNoodles);
        expect(matchesNoodles.first.id, equals('food_instant_noodles'));
        expect(matchesNoodles.any((m) => m.id == 'home_bedding_mattress'), isFalse);

        // "Thước nhôm" must NOT match pharma_otc_medicines
        final pRuler = makeProduct(name: 'Thước nhôm 30cm văn phòng Deli');
        final matchesRuler = SampleImageHelper.getSuggestedImages(pRuler);
        expect(matchesRuler.any((m) => m.id == 'pharma_otc_medicines'), isFalse);

        // "Sổ còng" must NOT match fresh_meat_seafood
        final pNotebook = makeProduct(name: 'Sổ còng đa năng cao cấp A5');
        final matchesNotebook = SampleImageHelper.getSuggestedImages(pNotebook);
        expect(matchesNotebook.first.id, equals('stationery_notebooks_paper'));
        expect(matchesNotebook.any((m) => m.id == 'fresh_meat_seafood'), isFalse);

        // "Mực in" must NOT match fresh_meat_seafood
        final pInk = makeProduct(name: 'Mực in Laser Canon 2900');
        final matchesInk = SampleImageHelper.getSuggestedImages(pInk);
        expect(matchesInk.any((m) => m.id == 'fresh_meat_seafood'), isFalse);
      });

      test('Discrete furniture categories precision matching', () {
        // 1. Work Desks & Gaming Desks
        final pDeskK = makeProduct(name: 'Bàn chữ K 120x60 chân sắt sơn tĩnh điện');
        expect(SampleImageHelper.getSuggestedImages(pDeskK).first.id, equals('furniture_desks_work'));

        final pDeskZ = makeProduct(name: 'Bàn chữ Z gaming RGB');
        expect(SampleImageHelper.getSuggestedImages(pDeskZ).first.id, equals('furniture_desks_work'));

        final pDeskGaming = makeProduct(name: 'Bàn gaming chữ L');
        expect(SampleImageHelper.getSuggestedImages(pDeskGaming).first.id, equals('furniture_desks_work'));

        // 2. Ergonomic & Swivel Chairs
        final pChairSwivel = makeProduct(name: 'Ghế xoay văn phòng');
        expect(SampleImageHelper.getSuggestedImages(pChairSwivel).first.id, equals('furniture_chairs_ergonomic'));

        final pChairErgo = makeProduct(name: 'Ghế công thái học Sihoo M57');
        expect(SampleImageHelper.getSuggestedImages(pChairErgo).first.id, equals('furniture_chairs_ergonomic'));

        // 3. Dining & Living Tables
        final pTableDining = makeProduct(name: 'Bàn ăn 6 ghế gỗ sồi');
        expect(SampleImageHelper.getSuggestedImages(pTableDining).first.id, equals('furniture_dining_living_tables'));

        final pTableTea = makeProduct(name: 'Bàn trà sofa tròn');
        expect(SampleImageHelper.getSuggestedImages(pTableTea).first.id, equals('furniture_dining_living_tables'));

        // 4. Wardrobes & Shelves
        final pWardrobe = makeProduct(name: 'Tủ quần áo gỗ 3 cánh');
        expect(SampleImageHelper.getSuggestedImages(pWardrobe).first.id, equals('furniture_wardrobes_shelves'));

        final pBookshelf = makeProduct(name: 'Kệ sách gỗ 5 tầng');
        expect(SampleImageHelper.getSuggestedImages(pBookshelf).first.id, equals('furniture_wardrobes_shelves'));

        // 5. Sofas
        final pSofa = makeProduct(name: 'Sofa da góc L phòng khách');
        expect(SampleImageHelper.getSuggestedImages(pSofa).first.id, equals('furniture_sofas_living'));

        // 6. Bedding & Mattresses
        final pBed = makeProduct(name: 'Giường ngủ hiện đại 1m8');
        expect(SampleImageHelper.getSuggestedImages(pBed).first.id, equals('home_bedding_mattress'));

        final pMattress = makeProduct(name: 'Nệm cao su thiên nhiên 1m6');
        expect(SampleImageHelper.getSuggestedImages(pMattress).first.id, equals('home_bedding_mattress'));
      });

      test('Watch placeholder is NEVER returned anywhere in fallback or suggestions', () {
        final products = [
          makeProduct(name: 'XYZ_123_NON_EXISTENT_PRODUCT'),
          makeProduct(name: '9876543210'),
          makeProduct(name: '   '),
          makeProduct(name: 'Bàn chữ K gaming'),
        ];

        for (final p in products) {
          final url = SampleImageHelper.getSampleImageUrl(p);
          expect(url.contains('photo-1523275335684-37898b6baf30'), isFalse);
          final suggestions = SampleImageHelper.getSuggestedImages(p);
          for (final s in suggestions) {
            expect(s.imageUrl.contains('photo-1523275335684-37898b6baf30'), isFalse);
          }
        }
      });
    });
  });
}
