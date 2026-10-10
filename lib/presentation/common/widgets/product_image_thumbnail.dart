import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/product_image_ref.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../../../application/products/product_image_resolver.dart';

class ProductImageThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String? productName;
  final String? categoryName;
  final double size;
  final double borderRadius;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;

  const ProductImageThumbnail({
    super.key,
    this.imageUrl,
    this.productName,
    this.categoryName,
    this.size = 48,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
    this.cacheWidth = 150,
    this.cacheHeight = 150,
  });

  /// Trích xuất URL ảnh chính từ chuỗi (hỗ trợ cả Network URL và Base64 Data URL, đa ảnh phân cách bằng dấu phẩy)
  static String? resolvePrimaryUrl(String? rawUrl) {
    return ImageCompressionHelper.resolvePrimaryUrl(rawUrl);
  }

  /// Trích xuất tất cả các URL ảnh hợp lệ từ chuỗi (hỗ trợ cả Network URL và Base64 Data URL)
  static List<String> resolveAllUrls(String? rawUrl) {
    return ImageCompressionHelper.parseImageUrls(rawUrl);
  }

  /// Cache bytes đã giải mã của ảnh Base64.
  /// `Image.memory` so sánh bytes theo identity, nên giải mã lại mỗi lần build
  /// sẽ khiến Flutter decode lại ảnh liên tục khi cuộn danh sách.
  static final Map<String, Uint8List> _decodedCache = <String, Uint8List>{};
  static const int _decodedCacheLimit = 300;

  static Uint8List? _decodeCached(String dataUrl) {
    final hit = _decodedCache[dataUrl];
    if (hit != null) return hit;
    final bytes = ImageCompressionHelper.decodeBase64DataUrl(dataUrl);
    if (bytes == null || bytes.isEmpty) return null;
    if (_decodedCache.length >= _decodedCacheLimit) {
      _decodedCache.remove(_decodedCache.keys.first);
    }
    _decodedCache[dataUrl] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = resolvePrimaryUrl(imageUrl);
    if (cleanUrl != null && cleanUrl.isNotEmpty) {
      // Ảnh lưu tách ở node product_images: tải lười khi widget hiển thị.
      if (ProductImageRef.isRef(cleanUrl)) {
        return _ExternalProductImage(
          key: ValueKey(cleanUrl),
          refValue: cleanUrl,
          size: size,
          borderRadius: borderRadius,
          builder: (resolvedUrl) =>
              (resolvedUrl == null ? null : _buildFromUrl(resolvedUrl)) ??
              _buildCategoryPlaceholder(),
        );
      }
      final widget = _buildFromUrl(cleanUrl);
      if (widget != null) return widget;
    }
    return _buildCategoryPlaceholder();
  }

  Widget? _buildFromUrl(String cleanUrl) {
    final effectiveCacheWidth = cacheWidth;
    final effectiveCacheHeight = cacheHeight;

    // 1. Xử lý Base64 Data URL
    if (ImageCompressionHelper.isBase64DataUrl(cleanUrl)) {
      final bytes = _decodeCached(cleanUrl);
      if (bytes == null) return null;
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: size,
          height: size,
          color: AppColors.grey100,
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: fit,
            gaplessPlayback: true,
            cacheWidth: effectiveCacheWidth,
            cacheHeight: effectiveCacheHeight,
            errorBuilder: (context, error, stackTrace) {
              return _buildCategoryPlaceholder();
            },
          ),
        ),
      );
    }

    // 2. Xử lý URL mạng (HTTP / HTTPS)
    if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: size,
          height: size,
          color: AppColors.grey100,
          child: Image.network(
            cleanUrl,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: effectiveCacheWidth,
            cacheHeight: effectiveCacheHeight,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: size,
                height: size,
                color: AppColors.grey100,
                child: Center(
                  child: SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildCategoryPlaceholder();
            },
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildCategoryPlaceholder() {
    final catLower = (categoryName ?? '').toLowerCase();
    final nameLower = (productName ?? '').toLowerCase();

    final IconData icon = _getCategoryIcon(catLower, nameLower);
    final Color bgColor = _getPastelColor(categoryName ?? productName ?? '');
    final Color iconColor = _getDarkerTone(bgColor);

    final String initialLetter =
        (productName != null && productName!.trim().isNotEmpty)
            ? productName!.trim().substring(0, 1).toUpperCase()
            : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
      ),
      child: Center(
        child: size <= 32
            ? Icon(icon, size: size * 0.55, color: iconColor)
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: size * 0.52, color: iconColor),
                  if (initialLetter.isNotEmpty && size >= 54)
                    Positioned(
                      right: 4,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withOpacity(0.06),
                              blurRadius: 2,
                            )
                          ],
                        ),
                        child: Text(
                          initialLetter,
                          style: TextStyle(
                            fontSize: size * 0.18,
                            fontWeight: FontWeight.bold,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  IconData _getCategoryIcon(String cat, String name) {
    final combined = '$cat $name'.toLowerCase();

    // 1. Combo
    if (combined.contains('combo') ||
        combined.contains('gói quà') ||
        combined.contains('gio qua') ||
        combined.contains('set quà')) {
      return Icons.auto_awesome_motion_rounded;
    }

    // 2. Baby & Pet
    if (combined.contains('thú cưng') ||
        combined.contains('thu cung') ||
        combined.contains('cho meo') ||
        combined.contains('chó mèo') ||
        combined.contains('royal canin')) {
      return Icons.pets_rounded;
    }
    if (combined.contains('mẹ & bé') ||
        combined.contains('me & be') ||
        combined.contains('tã') ||
        combined.contains('ta') ||
        combined.contains('bỉm') ||
        combined.contains('bim') ||
        combined.contains('bình sữa') ||
        combined.contains('binh sua')) {
      return Icons.child_friendly_rounded;
    }

    // 3. Pharmacy & Healthcare
    if (combined.contains('thuốc') ||
        combined.contains('thuoc') ||
        combined.contains('dược') ||
        combined.contains('duoc') ||
        combined.contains('y tế') ||
        combined.contains('y te') ||
        combined.contains('khẩu trang') ||
        combined.contains('khau trang') ||
        combined.contains('panadol') ||
        combined.contains('vitamin') ||
        combined.contains('huyết áp') ||
        combined.contains('huyet ap')) {
      return Icons.medical_services_rounded;
    }

    // 4. Stationery
    if (combined.contains('bút') ||
        combined.contains('but') ||
        combined.contains('văn phòng phẩm') ||
        combined.contains('van phong pham') ||
        combined.contains('sổ tay') ||
        combined.contains('so tay') ||
        combined.contains('vở') ||
        combined.contains('vo') ||
        combined.contains('giấy in') ||
        combined.contains('giay in') ||
        combined.contains('thiên long') ||
        combined.contains('thien long')) {
      return Icons.edit_note_rounded;
    }

    // 5. FMCG & Cleaning
    if (combined.contains('nước giặt') ||
        combined.contains('nuoc giat') ||
        combined.contains('bột giặt') ||
        combined.contains('bot giat') ||
        combined.contains('xả vải') ||
        combined.contains('xa vai') ||
        combined.contains('omo') ||
        combined.contains('tide') ||
        combined.contains('comfort') ||
        combined.contains('downy') ||
        combined.contains('nước rửa chén') ||
        combined.contains('nuoc rua chen') ||
        combined.contains('lau sàn') ||
        combined.contains('lau san') ||
        combined.contains('sunlight') ||
        combined.contains('tẩy rửa') ||
        combined.contains('tay rua')) {
      return Icons.local_laundry_service_rounded;
    }
    if (combined.contains('khăn giấy') ||
        combined.contains('khan giay') ||
        combined.contains('giấy vệ sinh') ||
        combined.contains('giay ve sinh') ||
        combined.contains('kem đánh răng') ||
        combined.contains('kem danh rang') ||
        combined.contains('dầu gội') ||
        combined.contains('dau goi') ||
        combined.contains('sữa tắm') ||
        combined.contains('sua tam')) {
      return Icons.soap_rounded;
    }

    // 6. Cosmetics & Beauty
    if (combined.contains('mỹ phẩm') ||
        combined.contains('my pham') ||
        combined.contains('son môi') ||
        combined.contains('son moi') ||
        combined.contains('trang điểm') ||
        combined.contains('trang diem') ||
        combined.contains('skincare') ||
        combined.contains('dưỡng da') ||
        combined.contains('duong da') ||
        combined.contains('nước hoa') ||
        combined.contains('nuoc hoa') ||
        combined.contains('chống nắng') ||
        combined.contains('chong nang')) {
      return Icons.face_retouching_natural_rounded;
    }

    // 7. Beverages
    if (combined.contains('nước ngọt') ||
        combined.contains('nuoc ngot') ||
        combined.contains('coca') ||
        combined.contains('pepsi') ||
        combined.contains('bia') ||
        combined.contains('sữa') ||
        combined.contains('sua') ||
        combined.contains('cà phê') ||
        combined.contains('ca phe') ||
        combined.contains('cafe') ||
        combined.contains('trà') ||
        combined.contains('tra') ||
        combined.contains('nước suối') ||
        combined.contains('nuoc suoi') ||
        combined.contains('aquafina') ||
        combined.contains('lavie')) {
      return Icons.local_drink_rounded;
    }

    // 8. Food & Grocery
    if (combined.contains('mì tôm') ||
        combined.contains('mi tom') ||
        combined.contains('mì gói') ||
        combined.contains('mi goi') ||
        combined.contains('bánh') ||
        combined.contains('banh') ||
        combined.contains('kẹo') ||
        combined.contains('keo') ||
        combined.contains('snack') ||
        combined.contains('gia vị') ||
        combined.contains('gia vi') ||
        combined.contains('dầu ăn') ||
        combined.contains('dau an') ||
        combined.contains('nước mắm') ||
        combined.contains('nuoc mam') ||
        combined.contains('thực phẩm') ||
        combined.contains('thuc pham') ||
        combined.contains('gạo') ||
        combined.contains('gao') ||
        combined.contains('thịt') ||
        combined.contains('thit') ||
        combined.contains('trái cây') ||
        combined.contains('trai cay')) {
      return Icons.restaurant_rounded;
    }

    // 9. Furniture & Home Living
    if (combined.contains('bàn làm việc') ||
        combined.contains('ban lam viec') ||
        combined.contains('bàn học') ||
        combined.contains('ban hoc') ||
        combined.contains('bàn gaming') ||
        combined.contains('ban gaming') ||
        combined.contains('bàn chữ') ||
        combined.contains('ban chu') ||
        combined.contains('bàn vi tính') ||
        combined.contains('ban vi tinh') ||
        combined.contains('bàn máy tính') ||
        combined.contains('ban may tinh') ||
        combined.contains('bàn nâng hạ') ||
        combined.contains('ban nang ha') ||
        combined.contains('bàn chân sắt') ||
        combined.contains('ban chan sat')) {
      return Icons.desk_rounded;
    }
    if (combined.contains('bàn ăn') ||
        combined.contains('ban an') ||
        combined.contains('bàn trà') ||
        combined.contains('ban tra') ||
        combined.contains('bàn sofa') ||
        combined.contains('ban sofa') ||
        combined.contains('bàn cafe') ||
        combined.contains('ban cafe') ||
        combined.contains('bàn tròn') ||
        combined.contains('ban tron')) {
      return Icons.table_restaurant_rounded;
    }
    if (combined.contains('ghế') ||
        combined.contains('ghe') ||
        combined.contains('sofa')) {
      return Icons.chair_rounded;
    }
    if (combined.contains('chăn ga') ||
        combined.contains('chan ga') ||
        combined.contains('nệm') ||
        combined.contains('nem') ||
        combined.contains('đệm') ||
        combined.contains('dem') ||
        combined.contains('gối') ||
        combined.contains('goi') ||
        combined.contains('giường') ||
        combined.contains('giuong') ||
        combined.contains('mền') ||
        combined.contains('men')) {
      return Icons.bed_rounded;
    }
    if (combined.contains('tủ quần áo') ||
        combined.contains('tu quan ao') ||
        combined.contains('kệ sách') ||
        combined.contains('ke sach') ||
        combined.contains('tủ giày') ||
        combined.contains('tu giay') ||
        combined.contains('kệ tivi') ||
        combined.contains('ke tivi') ||
        combined.contains('kệ sắt') ||
        combined.contains('ke sat') ||
        combined.contains('tủ đầu giường') ||
        combined.contains('tu dau giuong')) {
      return Icons.chair_rounded;
    }

    // 10. Home & Kitchen Appliances
    if (combined.contains('nồi chiên') ||
        combined.contains('noi chien') ||
        combined.contains('nồi cơm') ||
        combined.contains('noi com') ||
        combined.contains('ấm siêu tốc') ||
        combined.contains('am sieu toc') ||
        combined.contains('quạt') ||
        combined.contains('quat') ||
        combined.contains('máy hút bụi') ||
        combined.contains('may hut bui') ||
        combined.contains('bếp') ||
        combined.contains('bep') ||
        combined.contains('lò vi sóng') ||
        combined.contains('lo vi song') ||
        combined.contains('nồi') ||
        combined.contains('noi') ||
        combined.contains('chảo') ||
        combined.contains('chao')) {
      return Icons.kitchen_rounded;
    }

    // 10. Shoes & Bags
    if (combined.contains('giày') ||
        combined.contains('giay') ||
        combined.contains('dép') ||
        combined.contains('dep') ||
        combined.contains('sandal') ||
        combined.contains('sneaker') ||
        combined.contains('túi xách') ||
        combined.contains('tui xach') ||
        combined.contains('balo') ||
        combined.contains('ba lo') ||
        combined.contains('ví') ||
        combined.contains('vi')) {
      return Icons.shopping_bag_rounded;
    }

    // 11. Fashion
    if (combined.contains('thời trang') ||
        combined.contains('thoi trang') ||
        combined.contains('quần') ||
        combined.contains('quan') ||
        combined.contains('áo') ||
        combined.contains('ao') ||
        combined.contains('đầm') ||
        combined.contains('dam') ||
        combined.contains('váy') ||
        combined.contains('vay')) {
      return Icons.checkroom_rounded;
    }

    // 12. Tech & Electronics
    if (combined.contains('điện thoại') ||
        combined.contains('dien thoai') ||
        combined.contains('phone') ||
        combined.contains('iphone') ||
        combined.contains('samsung') ||
        combined.contains('xiaomi') ||
        combined.contains('oppo')) {
      return Icons.smartphone_rounded;
    }
    if (combined.contains('laptop') ||
        combined.contains('máy tính') ||
        combined.contains('may tinh') ||
        combined.contains('macbook') ||
        combined.contains('pc')) {
      return Icons.laptop_mac_rounded;
    }
    if (combined.contains('ipad') ||
        combined.contains('tablet') ||
        combined.contains('máy tính bảng') ||
        combined.contains('may tinh bang')) {
      return Icons.tablet_mac_rounded;
    }
    if (combined.contains('tai nghe') ||
        combined.contains('tai nghe') ||
        combined.contains('headphone') ||
        combined.contains('airpod') ||
        combined.contains('loa') ||
        combined.contains('âm thanh')) {
      return Icons.headphones_rounded;
    }
    if (combined.contains('sạc') ||
        combined.contains('sac') ||
        combined.contains('cáp') ||
        combined.contains('cap') ||
        combined.contains('pin') ||
        combined.contains('dây') ||
        combined.contains('củ sạc') ||
        combined.contains('adapter')) {
      return Icons.cable_rounded;
    }
    if (combined.contains('đồng hồ') ||
        combined.contains('dong ho') ||
        combined.contains('watch')) {
      return Icons.watch_rounded;
    }
    if (combined.contains('ốp') ||
        combined.contains('op') ||
        combined.contains('kính') ||
        combined.contains('kinh') ||
        combined.contains('dán') ||
        combined.contains('cường lực') ||
        combined.contains('bao da')) {
      return Icons.shield_rounded;
    }
    if (combined.contains('dịch vụ') ||
        combined.contains('dich vu') ||
        combined.contains('sửa') ||
        combined.contains('sua')) {
      return Icons.build_circle_outlined;
    }

    return Icons.inventory_2_rounded;
  }

  Color _getPastelColor(String text) {
    if (text.isEmpty) return AppColors.thumbnailDefaultBg;

    final palette = [
      AppColors.thumbnailBlueBg, // Light Blue
      AppColors.thumbnailPurpleBg, // Light Purple
      AppColors.thumbnailTealBg, // Light Teal
      AppColors.thumbnailAmberBg, // Light Amber
      AppColors.thumbnailRedBg, // Light Red/Pink
      AppColors.thumbnailGreenBg, // Light Green
      AppColors.thumbnailRoseBg, // Light Rose
      AppColors.thumbnailSlateBg, // Light Slate
    ];

    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final index = hash.abs() % palette.length;
    return palette[index];
  }

  Color _getDarkerTone(Color pastel) {
    if (pastel == AppColors.thumbnailBlueBg) {
      return AppColors.thumbnailBlueFg;
    }
    if (pastel == AppColors.thumbnailPurpleBg) {
      return AppColors.thumbnailPurpleFg;
    }
    if (pastel == AppColors.thumbnailTealBg) {
      return AppColors.thumbnailTealFg;
    }
    if (pastel == AppColors.thumbnailAmberBg) {
      return AppColors.thumbnailAmberFg;
    }
    if (pastel == AppColors.thumbnailRedBg) {
      return AppColors.thumbnailRedFg;
    }
    if (pastel == AppColors.thumbnailGreenBg) {
      return AppColors.thumbnailGreenFg;
    }
    if (pastel == AppColors.thumbnailRoseBg) {
      return AppColors.thumbnailRoseFg;
    }
    return AppColors.thumbnailDefaultFg;
  }
}


/// Hiển thị ảnh sản phẩm lưu tách (`rtdb-img://…`): tải một lần qua
/// [ProductImageResolver] (bộ nhớ → file cache → RTDB), có hiệu ứng mờ dần.
class _ExternalProductImage extends StatefulWidget {
  final String refValue;
  final double size;
  final double borderRadius;
  final Widget Function(String? resolvedUrl) builder;

  const _ExternalProductImage({
    super.key,
    required this.refValue,
    required this.size,
    required this.borderRadius,
    required this.builder,
  });

  @override
  State<_ExternalProductImage> createState() => _ExternalProductImageState();
}

class _ExternalProductImageState extends State<_ExternalProductImage> {
  String? _resolved;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = ProductImageResolver.peek(widget.refValue);
    if (cached != null) {
      _resolved = cached.isNotEmpty ? cached.first : null;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final images = await ProductImageResolver.resolve(widget.refValue);
      if (!mounted) return;
      setState(() {
        _resolved = images.isNotEmpty ? images.first : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ProductImageThumbnail] load ${widget.refValue} failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Container(
          width: widget.size,
          height: widget.size,
          color: AppColors.grey100,
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(
        key: ValueKey(_resolved),
        child: widget.builder(_resolved),
      ),
    );
  }
}
