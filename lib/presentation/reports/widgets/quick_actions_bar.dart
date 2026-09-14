import 'package:flutter/material.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';

/// Thanh lối tắt thao tác nhanh chuẩn KiotViet (R6).
/// Bao gồm 5 tác vụ cốt lõi: Bán hàng POS, Nhập hàng, Chuyển kho, Sổ nợ khách, Quản lý hàng hóa.
class QuickActionsBar extends StatelessWidget {
  const QuickActionsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Thao tác nhanh',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.point_of_sale_rounded,
                  label: 'Bán hàng',
                  color: AppColors.primary,
                  bgColor: const Color(0xFFE0F2FE),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const POSPage(),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.add_business_rounded,
                  label: 'Nhập hàng',
                  color: AppColors.secondary,
                  bgColor: const Color(0xFFDCFCE7),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ImportInventoryPage(),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.swap_horiz_rounded,
                  label: 'Chuyển kho',
                  color: AppColors.supervisor,
                  bgColor: const Color(0xFFF3E8FF),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductsPage(),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.menu_book_rounded,
                  label: 'Sổ nợ khách',
                  color: AppColors.chartOrange,
                  bgColor: const Color(0xFFFEF3C7),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomersPage(
                          initialDebtFilter: CustomerDebtFilter.inDebt,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.inventory_2_rounded,
                  label: 'Hàng hóa',
                  color: AppColors.chartTeal,
                  bgColor: const Color(0xFFCCFBF1),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
