import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ProductImageThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String? productName;
  final String? categoryName;
  final double size;
  final double borderRadius;
  final BoxFit fit;

  const ProductImageThumbnail({
    super.key,
    this.imageUrl,
    this.productName,
    this.categoryName,
    this.size = 48,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final hasValidUrl = imageUrl != null &&
        imageUrl!.trim().isNotEmpty &&
        (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://'));

    if (hasValidUrl) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: size,
          height: size,
          color: Colors.grey.shade100,
          child: Image.network(
            imageUrl!,
            width: size,
            height: size,
            fit: fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: size,
                height: size,
                color: Colors.grey.shade100,
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

    return _buildCategoryPlaceholder();
  }

  Widget _buildCategoryPlaceholder() {
    final catLower = (categoryName ?? '').toLowerCase();
    final nameLower = (productName ?? '').toLowerCase();

    final IconData icon = _getCategoryIcon(catLower, nameLower);
    final Color bgColor = _getPastelColor(categoryName ?? productName ?? '');
    final Color iconColor = _getDarkerTone(bgColor);

    final String initialLetter = (productName != null && productName!.trim().isNotEmpty)
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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
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
    final combined = '$cat $name';
    if (combined.contains('điện thoại') ||
        combined.contains('phone') ||
        combined.contains('iphone') ||
        combined.contains('samsung') ||
        combined.contains('xiaomi') ||
        combined.contains('oppo')) {
      return Icons.smartphone_rounded;
    }
    if (combined.contains('laptop') ||
        combined.contains('máy tính') ||
        combined.contains('macbook') ||
        combined.contains('pc')) {
      return Icons.laptop_mac_rounded;
    }
    if (combined.contains('tai nghe') ||
        combined.contains('headphone') ||
        combined.contains('airpod') ||
        combined.contains('loa') ||
        combined.contains('âm thanh')) {
      return Icons.headphones_rounded;
    }
    if (combined.contains('sạc') ||
        combined.contains('cáp') ||
        combined.contains('pin') ||
        combined.contains('dây') ||
        combined.contains('củ sạc') ||
        combined.contains('adapter')) {
      return Icons.cable_rounded;
    }
    if (combined.contains('đồng hồ') || combined.contains('watch')) {
      return Icons.watch_rounded;
    }
    if (combined.contains('ốp') ||
        combined.contains('kính') ||
        combined.contains('dán') ||
        combined.contains('cường lực') ||
        combined.contains('bao da')) {
      return Icons.shield_rounded;
    }
    if (combined.contains('thời trang') ||
        combined.contains('quần') ||
        combined.contains('áo') ||
        combined.contains('giày') ||
        combined.contains('dép') ||
        combined.contains('túi')) {
      return Icons.checkroom_rounded;
    }
    if (combined.contains('ăn') ||
        combined.contains('uống') ||
        combined.contains('thực phẩm') ||
        combined.contains('nước') ||
        combined.contains('bánh') ||
        combined.contains('kẹo')) {
      return Icons.restaurant_rounded;
    }
    if (combined.contains('combo') || combined.contains('gói')) {
      return Icons.auto_awesome_motion_rounded;
    }
    if (combined.contains('dịch vụ') || combined.contains('sửa')) {
      return Icons.build_circle_outlined;
    }
    return Icons.inventory_2_rounded;
  }

  Color _getPastelColor(String text) {
    if (text.isEmpty) return const Color(0xFFEDF2F7);

    final palette = [
      const Color(0xFFEBF8FF), // Light Blue
      const Color(0xFFFAF5FF), // Light Purple
      const Color(0xFFE6FFFA), // Light Teal
      const Color(0xFFFEFCBF), // Light Amber
      const Color(0xFFFFF5F5), // Light Red/Pink
      const Color(0xFFF0FFF4), // Light Green
      const Color(0xFFFFF0F5), // Light Rose
      const Color(0xFFF7FAFC), // Light Slate
    ];

    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final index = hash.abs() % palette.length;
    return palette[index];
  }

  Color _getDarkerTone(Color pastel) {
    if (pastel == const Color(0xFFEBF8FF)) return const Color(0xFF2B6CB0);
    if (pastel == const Color(0xFFFAF5FF)) return const Color(0xFF6B46C1);
    if (pastel == const Color(0xFFE6FFFA)) return const Color(0xFF2C7A7B);
    if (pastel == const Color(0xFFFEFCBF)) return const Color(0xFF975A16);
    if (pastel == const Color(0xFFFFF5F5)) return const Color(0xFFC53030);
    if (pastel == const Color(0xFFF0FFF4)) return const Color(0xFF276749);
    if (pastel == const Color(0xFFFFF0F5)) return const Color(0xFFB83280);
    return const Color(0xFF4A5568);
  }
}
