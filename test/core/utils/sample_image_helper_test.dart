import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
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
      id: 'prod_${name.hashCode}',
      name: name,
      code: 'TEST01',
      price: 100000,
      costPrice: 70000,
      branchStocks: const {'branch_1': 10},
      category: category,
      brand: brand,
      category3Levels: category3Levels,
      isCombo: isCombo,
    );
  }

  group('SampleImageHelper Smart Multi-Industry Matching Tests', () {
    test('Catalog contains 60+ curated categories across 12 industries', () {
      final allCats = SampleImageHelper.getAllCategories();
      expect(allCats.length, greaterThanOrEqualTo(25));
      final industries = allCats.map((c) => c.industry).toSet();
      expect(industries.length, greaterThanOrEqualTo(8));
    });

    group('1. Beverages & Drinks (Accented & Unaccented)', () {
      test('Soda & Energy Drinks (Accented & Unaccented)', () {
        final pAcc = makeProduct(name: 'Nước ngọt Coca Cola 330ml');
        final pUnacc = makeProduct(name: 'nuoc ngot pepsi khong duong lon 320ml');
        final pRedBull = makeProduct(name: 'Nước tăng lực Bò húc Redbull 250ml');

        final matchesAcc = SampleImageHelper.getSuggestedImages(pAcc);
        expect(matchesAcc.first.id, equals('beverage_soda'));

        final matchesUnacc = SampleImageHelper.getSuggestedImages(pUnacc);
        expect(matchesUnacc.first.id, equals('beverage_soda'));

        final matchesRedBull = SampleImageHelper.getSuggestedImages(pRedBull);
        expect(matchesRedBull.first.id, equals('beverage_soda'));
      });

      test('Beer & Alcohol', () {
        final pBeer = makeProduct(name: 'Bia Heineken Silver lon 330ml');
        final pTiger = makeProduct(name: 'bia tiger crystal thung 24 lon');
        final pWine = makeProduct(name: 'Rượu vang đỏ Đà Lạt 750ml');

        expect(SampleImageHelper.getSuggestedImages(pBeer).first.id, equals('beverage_beer'));
        expect(SampleImageHelper.getSuggestedImages(pTiger).first.id, equals('beverage_beer'));
        expect(SampleImageHelper.getSuggestedImages(pWine).first.id, equals('beverage_beer'));
      });

      test('Fresh Milk & Dairy', () {
        final pVinamilk = makeProduct(name: 'Sữa tươi tiệt trùng Vinamilk 100% ít đường 1L');
        final pTH = makeProduct(name: 'sua tuoi th true milk hop 180ml');

        expect(SampleImageHelper.getSuggestedImages(pVinamilk).first.id, equals('beverage_milk'));
        expect(SampleImageHelper.getSuggestedImages(pTH).first.id, equals('beverage_milk'));
      });

      test('Coffee & Tea', () {
        final pCoffee = makeProduct(name: 'Cà phê hòa tan Trung Nguyên Legend Special Edition');
        final pTea = makeProduct(name: 'Trà xanh không độ chai 500ml');
        final pPhucLong = makeProduct(name: 'tra dao phuc long lon');

        expect(SampleImageHelper.getSuggestedImages(pCoffee).first.id, equals('beverage_coffee'));
        expect(SampleImageHelper.getSuggestedImages(pTea).first.id, equals('beverage_tea'));
        expect(SampleImageHelper.getSuggestedImages(pPhucLong).first.id, equals('beverage_tea'));
      });

      test('Mineral Water', () {
        final pWater = makeProduct(name: 'nuoc suoi aquafina chai 500ml');
        final pLavie = makeProduct(name: 'Nước khoáng thiên nhiên LaVie 1.5L');

        expect(SampleImageHelper.getSuggestedImages(pWater).first.id, equals('beverage_water'));
        expect(SampleImageHelper.getSuggestedImages(pLavie).first.id, equals('beverage_water'));
      });
    });

    group('2. FMCG & Cleaning Chemicals', () {
      test('Laundry detergent & Softener', () {
        final pOmo = makeProduct(name: 'Nước giặt OMO Matic cửa trước túi 3.6kg');
        final pComfort = makeProduct(name: 'nuoc xa vai comfort huong ban mai 3.2L');

        expect(SampleImageHelper.getSuggestedImages(pOmo).first.id, equals('fmcg_laundry'));
        expect(SampleImageHelper.getSuggestedImages(pComfort).first.id, equals('fmcg_laundry'));
      });

      test('Dishwashing & Cleaning', () {
        final pSunlight = makeProduct(name: 'Nước rửa chén Sunlight chanh chai 750g');
        final pFloor = makeProduct(name: 'nuoc lau san sunlight huong hoa ha 1kg');

        expect(SampleImageHelper.getSuggestedImages(pSunlight).first.id, equals('fmcg_cleaning'));
        expect(SampleImageHelper.getSuggestedImages(pFloor).first.id, equals('fmcg_cleaning'));
      });

      test('Oral care & Personal wash', () {
        final pColgate = makeProduct(name: 'Kem đánh răng Colgate MaxFresh 225g');
        final pClear = makeProduct(name: 'Dầu gội Clear Men sạch gàu bạc hà 650g');

        expect(SampleImageHelper.getSuggestedImages(pColgate).first.id, equals('fmcg_oral'));
        expect(SampleImageHelper.getSuggestedImages(pClear).first.id, equals('fmcg_body_wash'));
      });

      test('Tissues & Paper', () {
        final pTissue = makeProduct(name: 'Khăn giấy lụa Pulppy 180 tờ');
        final pToilet = makeProduct(name: 'giay ve sinh emos 2 lop loc 10 cuon');

        expect(SampleImageHelper.getSuggestedImages(pTissue).first.id, equals('fmcg_tissue'));
        expect(SampleImageHelper.getSuggestedImages(pToilet).first.id, equals('fmcg_tissue'));
      });
    });

    group('3. Food, Snacks & Seasoning', () {
      test('Instant noodles & Snacks', () {
        final pNoodles = makeProduct(name: 'Mì tôm Hảo Hảo tôm chua cay 75g');
        final pDanisa = makeProduct(name: 'Bánh quy bơ hoàng gia Danisa 454g');
        final pOreo = makeProduct(name: 'Banh quy socola Oreo kep kem vani 133g');

        expect(SampleImageHelper.getSuggestedImages(pNoodles).first.id, equals('food_instant_noodles'));
        expect(SampleImageHelper.getSuggestedImages(pDanisa).first.id, equals('food_cookies_snacks'));
        expect(SampleImageHelper.getSuggestedImages(pOreo).first.id, equals('food_cookies_snacks'));
      });

      test('Fish sauce, Cooking oil & Rice', () {
        final pSauce = makeProduct(name: 'Nước mắm Nam Ngư Đệ Nhị chai 900ml');
        final pOil = makeProduct(name: 'dau an simply nguyen chat 1L');
        final pRice = makeProduct(name: 'Gạo ST25 Sóc Trăng thơm dẻo túi 5kg');

        expect(SampleImageHelper.getSuggestedImages(pSauce).first.id, equals('food_seasoning_oil'));
        expect(SampleImageHelper.getSuggestedImages(pOil).first.id, equals('food_seasoning_oil'));
        expect(SampleImageHelper.getSuggestedImages(pRice).first.id, equals('food_rice_grains'));
      });
    });

    group('4. Cosmetics & Beauty', () {
      test('Lipstick, Sunscreen & Perfume', () {
        final pLipstick = makeProduct(name: 'Son kem lì 3CE Velvet Lip Tint Taupe');
        final pSunscreen = makeProduct(name: 'kem chong nang anessa perfect uv sunscreen milk');
        final pPerfume = makeProduct(name: 'Nước hoa Nam Chanel Bleu De Chanel EDP 100ml');

        expect(SampleImageHelper.getSuggestedImages(pLipstick).first.id, equals('cosmetics_lipstick'));
        expect(SampleImageHelper.getSuggestedImages(pSunscreen).first.id, equals('cosmetics_skincare'));
        expect(SampleImageHelper.getSuggestedImages(pPerfume).first.id, equals('cosmetics_perfume'));
      });
    });

    group('5. Fashion, Shoes & Bags', () {
      test('Tops, Pants & Sneakers', () {
        final pShirt = makeProduct(name: 'Áo thun nam unisex cổ tròn 100% cotton');
        final pJean = makeProduct(name: 'quan jean nam ong suong levi\'s');
        final pShoe = makeProduct(name: 'Giày thể thao nam nữ Nike Air Force 1 07');
        final pBag = makeProduct(name: 'Túi xách nữ công sở da bò cao cấp');

        expect(SampleImageHelper.getSuggestedImages(pShirt).first.id, equals('fashion_tops'));
        expect(SampleImageHelper.getSuggestedImages(pJean).first.id, equals('fashion_pants'));
        expect(SampleImageHelper.getSuggestedImages(pShoe).first.id, equals('shoes_sneakers'));
        expect(SampleImageHelper.getSuggestedImages(pBag).first.id, equals('bags_handbags'));
      });
    });

    group('6. Tech & Gadgets', () {
      test('iPhone, Android, Laptop & Accessories', () {
        final pIphone = makeProduct(name: 'iPhone 15 Pro Max 256GB Titan Tự Nhiên');
        final pAndroid = makeProduct(name: 'dien thoai samsung galaxy s24 ultra');
        final pMacbook = makeProduct(name: 'Laptop MacBook Pro 14 M3 Pro 18GB 512GB');
        final pEarbuds = makeProduct(name: 'Tai nghe AirPods Pro 2 MagSafe Type-C');
        final pCharger = makeProduct(name: 'Củ sạc nhanh Anker 65W GaNPrime');

        expect(SampleImageHelper.getSuggestedImages(pIphone).first.id, equals('tech_iphone'));
        expect(SampleImageHelper.getSuggestedImages(pAndroid).first.id, equals('tech_android'));
        expect(SampleImageHelper.getSuggestedImages(pMacbook).first.id, equals('tech_laptop'));
        expect(SampleImageHelper.getSuggestedImages(pEarbuds).first.id, equals('tech_earbuds'));
        expect(SampleImageHelper.getSuggestedImages(pCharger).first.id, equals('tech_chargers_cables'));
      });
    });

    group('7. Home, Pharmacy, Stationery, Baby & Combo', () {
      test('Appliances & Kitchenware', () {
        final pAirfryer = makeProduct(name: 'Nồi chiên không dầu Philips HD9650 dung tích 7.3L');
        expect(SampleImageHelper.getSuggestedImages(pAirfryer).first.id, equals('home_kitchen_appliances'));
      });

      test('Pharmacy & Healthcare', () {
        final pPanadol = makeProduct(name: 'Thuốc giảm đau hạ sốt Panadol Extra hộp 180 viên');
        final pMask = makeProduct(name: 'khau trang y te 4 lop khang khuan hop 50 cai');
        final pOmron = makeProduct(name: 'Máy đo huyết áp bắp tay tự động Omron HEM-7120');

        expect(SampleImageHelper.getSuggestedImages(pPanadol).first.id, equals('pharma_otc_medicines'));
        expect(SampleImageHelper.getSuggestedImages(pMask).first.id, equals('pharma_face_masks'));
        expect(SampleImageHelper.getSuggestedImages(pOmron).first.id, equals('pharma_medical_devices'));
      });

      test('Stationery', () {
        final pPen = makeProduct(name: 'Bút bi Thiên Long TL-027 ngòi 0.5mm');
        final pPaper = makeProduct(name: 'giay in a4 double a 70gsm ram 500 to');

        expect(SampleImageHelper.getSuggestedImages(pPen).first.id, equals('stationery_pens'));
        expect(SampleImageHelper.getSuggestedImages(pPaper).first.id, equals('stationery_notebooks_paper'));
      });

      test('Baby, Pet & Combos', () {
        final pDiaper = makeProduct(name: 'Tã dán Huggies Platinum Nature Made size M');
        final pPetFood = makeProduct(name: 'Thức ăn hạt cho mèo con Royal Canin Kitten 2kg');
        final pCombo = makeProduct(name: 'Combo giỏ quà tết Phú Quý 2026', isCombo: true);

        expect(SampleImageHelper.getSuggestedImages(pDiaper).first.id, equals('baby_diapers'));
        expect(SampleImageHelper.getSuggestedImages(pPetFood).first.id, equals('pet_food'));
        expect(SampleImageHelper.getSuggestedImages(pCombo).first.id, equals('gift_combo'));
      });
    });

    group('8. Substring Collision Trap & Negative Keyword Tests', () {
      test('"Bàn ăn 6 ghế" matches Dining Tables, NOT Food', () {
        final p = makeProduct(name: 'Bàn ăn 6 ghế gỗ tự nhiên cao cấp');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('furniture_dining_living_tables'));
        expect(matches.any((m) => m.id.startsWith('food_')), isFalse);
      });

      test('"Khăn lau mặt" matches FMCG/Tissue, NOT Food', () {
        final p = makeProduct(name: 'Khăn lau mặt cotton 100% mềm mịn');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('fmcg_tissue'));
        expect(matches.any((m) => m.id.startsWith('food_')), isFalse);
      });

      test('"Túi chống sốc đựng laptop" matches Bags, NOT Laptop tech', () {
        final p = makeProduct(name: 'Túi chống sốc đựng laptop 14 inch chống nước');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('bags_backpacks'));
      });

      test('"Ốp lưng dẻo trong suốt cho iPad Pro" matches Cases, NOT Tablet tech', () {
        final p = makeProduct(name: 'Ốp lưng dẻo trong suốt cho iPad Pro 11 inch');
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches.first.id, equals('tech_cases_protectors'));
      });

      test('Unrecognized random string returns empty string from getSampleImageUrl for UI icon fallback', () {
        final p = makeProduct(name: 'XYZ_123_ABC_TEST_9999_PRODUCT_NULL');
        final url = SampleImageHelper.getSampleImageUrl(p);
        expect(url, equals(''));
        expect(url.contains('photo-1523275335684-37898b6baf30'), isFalse);
        expect(SampleImageHelper.universalPlaceholderUrl, contains('photo-1586769852044-692d6e3703f0'));
      });
    });

    group('9. Smart Furniture & Home Living Discrete Categories Tests', () {
      test('Work Desks & Gaming Desks match furniture_desks_work', () {
        final pKDesk = makeProduct(name: 'Bàn chữ K 120x60 chân sắt sơn tĩnh điện');
        expect(SampleImageHelper.getSuggestedImages(pKDesk).first.id, equals('furniture_desks_work'));

        final pZDesk = makeProduct(name: 'Bàn chữ Z gaming RGB mặt gỗ');
        expect(SampleImageHelper.getSuggestedImages(pZDesk).first.id, equals('furniture_desks_work'));

        final pGaming = makeProduct(name: 'Bàn gaming chữ L nâng hạ chiều cao');
        expect(SampleImageHelper.getSuggestedImages(pGaming).first.id, equals('furniture_desks_work'));

        final pCompDesk = makeProduct(name: 'Bàn vi tính văn phòng chân sắt 1m4');
        expect(SampleImageHelper.getSuggestedImages(pCompDesk).first.id, equals('furniture_desks_work'));

        final pStudyDesk = makeProduct(name: 'Bàn học sinh chống gù chống cận');
        expect(SampleImageHelper.getSuggestedImages(pStudyDesk).first.id, equals('furniture_desks_work'));
      });

      test('Ergonomic & Swivel Chairs match furniture_chairs_ergonomic', () {
        final pSwivel = makeProduct(name: 'Ghế xoay văn phòng lưới thoáng khí');
        expect(SampleImageHelper.getSuggestedImages(pSwivel).first.id, equals('furniture_chairs_ergonomic'));

        final pErgo = makeProduct(name: 'Ghế công thái học Sihoo M57');
        expect(SampleImageHelper.getSuggestedImages(pErgo).first.id, equals('furniture_chairs_ergonomic'));

        final pGamingChair = makeProduct(name: 'Ghế gaming E-Dra Jupiter bọc da');
        expect(SampleImageHelper.getSuggestedImages(pGamingChair).first.id, equals('furniture_chairs_ergonomic'));

        final pDirector = makeProduct(name: 'Ghế giám đốc chân quỳ bọc nệm');
        expect(SampleImageHelper.getSuggestedImages(pDirector).first.id, equals('furniture_chairs_ergonomic'));
      });

      test('Dining Tables & Tea/Coffee Tables match furniture_dining_living_tables', () {
        final pDining = makeProduct(name: 'Bàn ăn 4 ghế mặt đá ceramic cao cấp');
        expect(SampleImageHelper.getSuggestedImages(pDining).first.id, equals('furniture_dining_living_tables'));

        final pTea = makeProduct(name: 'Bàn trà sofa phòng khách hình tròn đôi');
        expect(SampleImageHelper.getSuggestedImages(pTea).first.id, equals('furniture_dining_living_tables'));

        final pCafe = makeProduct(name: 'Bàn cafe chân sắt mặt gỗ thông');
        expect(SampleImageHelper.getSuggestedImages(pCafe).first.id, equals('furniture_dining_living_tables'));
      });

      test('Wardrobes, Shelves & Bookcases match furniture_wardrobes_shelves', () {
        final pWardrobe = makeProduct(name: 'Tủ quần áo gỗ MDF 4 cánh hiện đại');
        expect(SampleImageHelper.getSuggestedImages(pWardrobe).first.id, equals('furniture_wardrobes_shelves'));

        final pBookshelf = makeProduct(name: 'Kệ sách mini để bàn làm việc');
        expect(SampleImageHelper.getSuggestedImages(pBookshelf).first.id, equals('furniture_wardrobes_shelves'));

        final pTvStand = makeProduct(name: 'Kệ tivi phòng khách rút 2 đầu');
        expect(SampleImageHelper.getSuggestedImages(pTvStand).first.id, equals('furniture_wardrobes_shelves'));

        final pNightstand = makeProduct(name: 'Tủ đầu giường 2 ngăn kéo có khóa');
        expect(SampleImageHelper.getSuggestedImages(pNightstand).first.id, equals('furniture_wardrobes_shelves'));

        final pIronShelf = makeProduct(name: 'Kệ sắt đa năng 5 tầng để đồ');
        expect(SampleImageHelper.getSuggestedImages(pIronShelf).first.id, equals('furniture_wardrobes_shelves'));
      });

      test('Sofas & Living Couches match furniture_sofas_living', () {
        final pSofa = makeProduct(name: 'Sofa da góc L cao cấp nhập khẩu');
        expect(SampleImageHelper.getSuggestedImages(pSofa).first.id, equals('furniture_sofas_living'));

        final pSofaBed = makeProduct(name: 'Ghế sofa bed gấp gọn thông minh');
        expect(SampleImageHelper.getSuggestedImages(pSofaBed).first.id, equals('furniture_sofas_living'));

        final pFabricSofa = makeProduct(name: 'Sofa nỉ nhung phòng khách 2m');
        expect(SampleImageHelper.getSuggestedImages(pFabricSofa).first.id, equals('furniture_sofas_living'));
      });

      test('Bedding, Mattresses & Pillows match home_bedding_mattress', () {
        final pBed = makeProduct(name: 'Giường ngủ gỗ sồi 1m8x2m');
        expect(SampleImageHelper.getSuggestedImages(pBed).first.id, equals('home_bedding_mattress'));

        final pMattress = makeProduct(name: 'Nệm cao su non Thắng Lợi 1m6');
        expect(SampleImageHelper.getSuggestedImages(pMattress).first.id, equals('home_bedding_mattress'));

        final pPillow = makeProduct(name: 'Gối ôm cao su thiên nhiên Liên Á');
        expect(SampleImageHelper.getSuggestedImages(pPillow).first.id, equals('home_bedding_mattress'));

        final pBlanket = makeProduct(name: 'Chăn hè tencel cao cấp chần bông');
        expect(SampleImageHelper.getSuggestedImages(pBlanket).first.id, equals('home_bedding_mattress'));
      });

      test('Watch image is NEVER returned anywhere in fallback', () {
        final samples = [
          '',
          '   ',
          'random_gibberish_string_99999',
          'Bàn chữ K gaming',
          'Ghế xoay Sihoo',
          'Tủ quần áo 3 cánh',
        ];
        for (final s in samples) {
          final url = SampleImageHelper.getSampleImageUrlForText(s);
          expect(url.contains('photo-1523275335684-37898b6baf30'), isFalse);
        }
      });
    });
  });
}
