import '../../domain/entities/product.dart';

class SampleImageHelper {
  /// Map product to a high-quality relevant online image URL based on its name and category
  static String getSampleImageUrl(Product product) {
    final nameLower = product.name.toLowerCase();
    final catLower = product.category.toLowerCase();
    final brandLower = (product.brand ?? '').toLowerCase();
    final combined = '$nameLower $catLower $brandLower ${product.category3Levels ?? ''}';

    // 1. Combo / Gift Packages
    if (product.isCombo || combined.contains('combo') || combined.contains('gói')) {
      return 'https://images.unsplash.com/photo-1512756290469-ec264b7fbf87?w=600&auto=format&fit=crop&q=80';
    }

    // 2. Apple iPhone
    if (combined.contains('iphone') || (combined.contains('apple') && combined.contains('phone'))) {
      return 'https://images.unsplash.com/photo-1592750475338-74b7b21085ab?w=600&auto=format&fit=crop&q=80';
    }

    // 3. Samsung Galaxy / Android Smartphones
    if (combined.contains('samsung') || combined.contains('galaxy') || combined.contains('xiaomi') || combined.contains('oppo') || combined.contains('vivo') || combined.contains('realme')) {
      return 'https://images.unsplash.com/photo-1610945265064-0e34e5519bbf?w=600&auto=format&fit=crop&q=80';
    }

    // 4. General Smartphones / Phones
    if (combined.contains('điện thoại') || combined.contains('smartphone') || combined.contains('phone')) {
      return 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=600&auto=format&fit=crop&q=80';
    }

    // 5. MacBook / Apple Laptops
    if (combined.contains('macbook') || (combined.contains('apple') && combined.contains('laptop'))) {
      return 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=600&auto=format&fit=crop&q=80';
    }

    // 6. Windows / Gaming Laptops / Laptop
    if (combined.contains('laptop') || combined.contains('notebook') || combined.contains('máy tính xách tay') || combined.contains('asus') || combined.contains('dell') || combined.contains('lenovo') || combined.contains('acer') || combined.contains('hp')) {
      return 'https://images.unsplash.com/photo-1603302576837-37561b2e2302?w=600&auto=format&fit=crop&q=80';
    }

    // 7. iPad / Tablets
    if (combined.contains('ipad') || combined.contains('tablet') || combined.contains('máy tính bảng') || combined.contains('tab')) {
      return 'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?w=600&auto=format&fit=crop&q=80';
    }

    // 8. Desktop PC / Case / Máy tính để bàn
    if (combined.contains('pc') || combined.contains('desktop') || combined.contains('máy bàn') || combined.contains('case') || combined.contains('máy tính để bàn')) {
      return 'https://images.unsplash.com/photo-1587202372775-e229f172b9d7?w=600&auto=format&fit=crop&q=80';
    }

    // 9. Monitors / Màn hình
    if (combined.contains('màn hình') || combined.contains('monitor') || combined.contains('display')) {
      return 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=600&auto=format&fit=crop&q=80';
    }

    // 10. AirPods / Wireless Earbuds
    if (combined.contains('airpod') || combined.contains('tws') || combined.contains('true wireless') || combined.contains('tai nghe không dây') || combined.contains('earbuds')) {
      return 'https://images.unsplash.com/photo-1600294037681-c80b4cb5b434?w=600&auto=format&fit=crop&q=80';
    }

    // 11. Over-Ear Headphones / Tai nghe chụp tai
    if (combined.contains('tai nghe') || combined.contains('headphone') || combined.contains('headset') || combined.contains('chụp tai')) {
      return 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600&auto=format&fit=crop&q=80';
    }

    // 12. Bluetooth Speakers / Loa
    if (combined.contains('loa') || combined.contains('speaker') || combined.contains('soundbar') || combined.contains('jbl') || combined.contains('marshall')) {
      return 'https://images.unsplash.com/photo-1545454675-3531b543be5d?w=600&auto=format&fit=crop&q=80';
    }

    // 13. Smartwatch / Apple Watch / Đồng hồ
    if (combined.contains('đồng hồ') || combined.contains('watch') || combined.contains('smartwatch') || combined.contains('garmin')) {
      return 'https://images.unsplash.com/photo-1508685096489-7aacd43bd3b1?w=600&auto=format&fit=crop&q=80';
    }

    // 14. Keyboards / Bàn phím
    if (combined.contains('bàn phím') || combined.contains('keyboard') || combined.contains('phím cơ')) {
      return 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=600&auto=format&fit=crop&q=80';
    }

    // 15. Mice / Chuột máy tính
    if (combined.contains('chuột') || combined.contains('mouse') || combined.contains('logitech')) {
      return 'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=600&auto=format&fit=crop&q=80';
    }

    // 16. Chargers / Củ sạc / Cáp sạc
    if (combined.contains('sạc') || combined.contains('cáp') || combined.contains('củ sạc') || combined.contains('dây sạc') || combined.contains('charger') || combined.contains('cable') || combined.contains('adapter') || combined.contains('type-c') || combined.contains('lightning')) {
      return 'https://images.unsplash.com/photo-1583863788434-e58a36330cf0?w=600&auto=format&fit=crop&q=80';
    }

    // 17. Powerbank / Pin dự phòng
    if (combined.contains('dự phòng') || combined.contains('powerbank') || combined.contains('pin sạc') || combined.contains('pin')) {
      return 'https://images.unsplash.com/photo-1609091839311-d5365f9ff1c5?w=600&auto=format&fit=crop&q=80';
    }

    // 18. Case / Screen Protector / Ốp lưng / Kính cường lực
    if (combined.contains('ốp') || combined.contains('cường lực') || combined.contains('kính') || combined.contains('dán') || combined.contains('case') || combined.contains('bao da')) {
      return 'https://images.unsplash.com/photo-1586953208448-b95a79798f07?w=600&auto=format&fit=crop&q=80';
    }

    // 19. Camera / Máy ảnh / Webcam
    if (combined.contains('camera') || combined.contains('máy ảnh') || combined.contains('webcam') || combined.contains('flycam')) {
      return 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=600&auto=format&fit=crop&q=80';
    }

    // 20. Fashion / Clothing / Quần áo / Giày
    if (combined.contains('thời trang') || combined.contains('quần') || combined.contains('áo') || combined.contains('giày') || combined.contains('dép') || combined.contains('túi') || combined.contains('balo')) {
      return 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?w=600&auto=format&fit=crop&q=80';
    }

    // 21. Drinks / Beverage / Cafe / Trà
    if (combined.contains('uống') || combined.contains('cafe') || combined.contains('trà') || combined.contains('nước') || combined.contains('sữa') || combined.contains('bia')) {
      return 'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?w=600&auto=format&fit=crop&q=80';
    }

    // 22. Food / Bánh kẹo / Thực phẩm
    if (combined.contains('ăn') || combined.contains('thực phẩm') || combined.contains('bánh') || combined.contains('kẹo') || combined.contains('món')) {
      return 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=600&auto=format&fit=crop&q=80';
    }

    // Default High-Quality Product Placeholder
    return 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=600&auto=format&fit=crop&q=80';
  }
}
