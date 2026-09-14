import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/firebase/attendance_remote_data_source.dart';
import '../../../domain/attendance/store_gps_config.dart';

class GpsStatusCard extends StatelessWidget {
  final double distanceMeters;
  final bool isWithinRadius;
  final StoreGpsConfig? storeConfig;
  final TextEditingController? explanationController;
  final VoidCallback onRefreshLocation;
  final Function(GeoPoint) onSelectSimulatedLocation;

  const GpsStatusCard({
    super.key,
    required this.distanceMeters,
    required this.isWithinRadius,
    this.storeConfig,
    this.explanationController,
    required this.onRefreshLocation,
    required this.onSelectSimulatedLocation,
  });

  @override
  Widget build(BuildContext context) {
    final maxRadius = storeConfig?.allowedRadiusMeters ?? 150.0;
    final storeName = storeConfig?.storeName ?? 'Chi nhánh';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isWithinRadius
              ? AppColors.success.withOpacity(0.4)
              : AppColors.warning.withOpacity(0.6),
          width: 1.5,
        ),
      ),
      color: isWithinRadius ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isWithinRadius
                      ? AppColors.successLight
                      : AppColors.warningLight,
                  child: Icon(
                    isWithinRadius ? Icons.my_location : Icons.location_searching,
                    color: isWithinRadius ? AppColors.success : AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vị trí GPS & Chi nhánh',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        storeName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.primary),
                  tooltip: 'Cập nhật lại vị trí',
                  onPressed: onRefreshLocation,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Khoảng cách đến cửa hàng:',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${distanceMeters.toStringAsFixed(1)} mét',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isWithinRadius ? AppColors.success : const Color(0xFFB45309),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isWithinRadius ? AppColors.successLight : AppColors.warningLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isWithinRadius ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 16,
                        color: isWithinRadius ? AppColors.success : const Color(0xFFB45309),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isWithinRadius ? 'Hợp lệ (<= ${maxRadius.toInt()}m)' : 'Cảnh báo (> ${maxRadius.toInt()}m)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isWithinRadius ? AppColors.success : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // If outside radius, display mandatory explanation field
            if (!isWithinRadius && explanationController != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.edit_note, size: 18, color: AppColors.warning),
                        SizedBox(width: 6),
                        Text(
                          'Lý do giải trình (Bắt buộc khi ngoài bán kính):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: explanationController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Nhập lý do (ví dụ: Đi giao hàng, lỗi GPS, hỗ trợ chi nhánh khác...)',
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Quick Demo / Test GPS simulation toggle
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<GeoPoint>(
                  tooltip: 'Giả lập vị trí GPS (Hỗ trợ Test/Demo)',
                  onSelected: onSelectSimulatedLocation,
                  itemBuilder: (ctx) {
                    final baseLat = storeConfig?.latitude ?? 10.035000;
                    final baseLng = storeConfig?.longitude ?? 105.788000;
                    return [
                      PopupMenuItem(
                        value: GeoPoint(baseLat, baseLng, 'Tại cửa hàng (0m)'),
                        child: const Text('Tại cửa hàng (0m - Hợp lệ)'),
                      ),
                      PopupMenuItem(
                        value: GeoPoint(baseLat + 0.0006, baseLng, 'Gần cửa hàng (~65m)'),
                        child: const Text('Gần cửa hàng (~65m - Hợp lệ)'),
                      ),
                      PopupMenuItem(
                        value: GeoPoint(baseLat + 0.003, baseLng, 'Ngoài cửa hàng (~330m)'),
                        child: const Text('Ngoài cửa hàng (~330m - Cảnh báo)'),
                      ),
                      PopupMenuItem(
                        value: GeoPoint(baseLat + 0.010, baseLng, 'Xa cửa hàng (~1.1km)'),
                        child: const Text('Xa cửa hàng (~1.1km - Cảnh báo)'),
                      ),
                    ];
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'Chế độ test tọa độ',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
