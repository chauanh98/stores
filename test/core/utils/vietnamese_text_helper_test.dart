import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/vietnamese_text_helper.dart';

void main() {
  group('VietnameseTextHelper Unit Tests', () {
    test('removeDiacritics strips all Vietnamese lowercase vowels and consonants', () {
      expect(
        VietnameseTextHelper.removeDiacritics('aàáảãạăằắẳẵặâầấẩẫậ'),
        equals('aaaaaaaaaaaaaaaaaa'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('dđ'),
        equals('dd'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('eèéẻẽẹêềếểễệ'),
        equals('eeeeeeeeeeee'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('iìíỉĩị'),
        equals('iiiiii'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('oòóỏõọôồốổỗộơờớởỡợ'),
        equals('oooooooooooooooooo'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('uùúủũụưừứửữự'),
        equals('uuuuuuuuuuuu'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('yỳýỷỹỵ'),
        equals('yyyyyy'),
      );
    });

    test('removeDiacritics strips all Vietnamese uppercase vowels and consonants', () {
      expect(
        VietnameseTextHelper.removeDiacritics('AÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ'),
        equals('AAAAAAAAAAAAAAAAAA'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('DĐ'),
        equals('DD'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('EÈÉẺẼẸÊỀẾỂỄỆ'),
        equals('EEEEEEEEEEEE'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('IÌÍỈĨỊ'),
        equals('IIIIII'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('OÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ'),
        equals('OOOOOOOOOOOOOOOOOO'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('UÙÚỦŨỤƯỪỨỬỮỰ'),
        equals('UUUUUUUUUUUU'),
      );
      expect(
        VietnameseTextHelper.removeDiacritics('YỲÝỶỸỴ'),
        equals('YYYYYY'),
      );
    });

    test('normalize collapses extra whitespaces, trims, and lowercases', () {
      expect(
        VietnameseTextHelper.normalize('   NƯỚC   NGỌT   COCA   COLA   '),
        equals('nước ngọt coca cola'),
      );
      expect(
        VietnameseTextHelper.normalize(''),
        equals(''),
      );
    });

    test('normalizeUnaccented removes diacritics and lowercases', () {
      expect(
        VietnameseTextHelper.normalizeUnaccented('Điện Thoại iPhone 15 Pro Max'),
        equals('dien thoai iphone 15 pro max'),
      );
      expect(
        VietnameseTextHelper.normalizeUnaccented('Sữa Tươi Tiệt Trùng Vinamilk 100%'),
        equals('sua tuoi tiet trung vinamilk 100%'),
      );
    });

    test('tokenize splits text into normalized word list', () {
      final tokens = VietnameseTextHelper.tokenize('Nước ngọt Coca-Cola 330ml');
      expect(tokens, containsAll(['nước', 'ngọt', 'coca', 'cola', '330ml']));

      final unaccTokens = VietnameseTextHelper.tokenize(
        'Nước ngọt Coca-Cola 330ml',
        stripDiacritics: true,
      );
      expect(unaccTokens, containsAll(['nuoc', 'ngot', 'coca', 'cola', '330ml']));
    });

    group('Word Boundary Match Precision & Substring Traps Prevention', () {
      test('containsWord matches whole words and avoids substring traps', () {
        // "ăn" in "bàn ăn" should match
        expect(VietnameseTextHelper.containsWord('bàn ăn gia đình', 'ăn'), isTrue);
        expect(VietnameseTextHelper.containsWord('quán ăn', 'ăn'), isTrue);

        // "ăn" in "khăn" MUST NOT match
        expect(VietnameseTextHelper.containsWord('khăn lau mặt cotton', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('khăn ướt em bé', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('băng keo', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('bình xăng', 'ăn'), isFalse);

        // "áo" in "áo thun" matches
        expect(VietnameseTextHelper.containsWord('áo thun nam cotton', 'áo'), isTrue);
        expect(VietnameseTextHelper.containsWord('áo khoác gió', 'áo'), isTrue);

        // "áo" in "báo cáo", "quảng cáo", "thông báo" MUST NOT match
        expect(VietnameseTextHelper.containsWord('báo cáo doanh thu', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('biển quảng cáo', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('thông báo nội bộ', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('pháo hoa tết', 'áo'), isFalse);

        // "pin" in "pin sạc dự phòng" matches
        expect(VietnameseTextHelper.containsWord('pin sạc dự phòng anker', 'pin'), isTrue);

        // "pin" in "shopping", "spin" MUST NOT match
        expect(VietnameseTextHelper.containsWord('túi shopping bag', 'pin'), isFalse);
        expect(VietnameseTextHelper.containsWord('spinner toy', 'pin'), isFalse);
      });

      test('containsWordUnaccented works on unaccented text with boundary protection', () {
        expect(VietnameseTextHelper.containsWordUnaccented('ban an go soi', 'an'), isTrue);
        expect(VietnameseTextHelper.containsWordUnaccented('khan lau mat', 'an'), isFalse);
        expect(VietnameseTextHelper.containsWordUnaccented('ao thun nam', 'ao'), isTrue);
        expect(VietnameseTextHelper.containsWordUnaccented('bao cao tai chinh', 'ao'), isFalse);
      });

      test('containsPhrase matches multi-word phrases', () {
        expect(
          VietnameseTextHelper.containsPhrase(
            'Nồi chiên không dầu Philips HD9650',
            'nồi chiên không dầu',
          ),
          isTrue,
        );
        expect(
          VietnameseTextHelper.containsPhrase(
            'noi chien khong dau philips',
            'nồi chiên không dầu',
            unaccented: true,
          ),
          isTrue,
        );
        expect(
          VietnameseTextHelper.containsPhrase(
            'Bàn ghế phòng khách',
            'nồi chiên không dầu',
          ),
          isFalse,
        );
      });

      test('treats underscore "_" as delimiter in snake_case strings for words and phrases', () {
        expect(VietnameseTextHelper.containsWord('_BAN_CHU_K_', 'ban'), isTrue);
        expect(VietnameseTextHelper.containsWord('BIA_HEINEKEN_SILVER_LON_330ML', 'heineken'), isTrue);
        expect(VietnameseTextHelper.containsWordUnaccented('BAN_CHU_K_GAMING', 'k'), isTrue);
        expect(VietnameseTextHelper.containsPhrase('_BAN_CHU_K_', 'ban chu k', unaccented: true), isTrue);
        expect(VietnameseTextHelper.containsPhrase('BÀN_CHỮ_K_GAMING', 'bàn chữ k'), isTrue);
        expect(VietnameseTextHelper.containsPhrase('BIA_HEINEKEN_SILVER_LON_330ML', 'bia heineken', unaccented: true), isTrue);

        final tokens = VietnameseTextHelper.tokenize('BAN_CHU_K_120X60');
        expect(tokens, containsAll(['ban', 'chu', 'k', '120x60']));
      });
    });
  });
}
