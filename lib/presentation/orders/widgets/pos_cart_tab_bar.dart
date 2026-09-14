import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/orders/cart_providers.dart';
import '../../../core/theme/app_colors.dart';

/// Widget thanh quản lý danh sách Tab hóa đơn tạm đa đơn (Multi-Cart POS Bar)
class PosCartTabBar extends ConsumerStatefulWidget {
  const PosCartTabBar({super.key});

  @override
  ConsumerState<PosCartTabBar> createState() => _PosCartTabBarState();
}

class _PosCartTabBarState extends ConsumerState<PosCartTabBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveTab(int index, int totalTabs) {
    if (!_scrollController.hasClients) return;
    // Calculate approximate offset
    final targetOffset = (index * 130.0) - 20;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleCloseTab(
      BuildContext context, WidgetRef ref, CartTab tab) async {
    if (tab.items.isEmpty) {
      ref.read(multiCartProvider.notifier).closeTab(tab.id);
      return;
    }

    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Đóng hóa đơn tạm?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Hóa đơn "${tab.title}" đang có ${tab.totalItems} sản phẩm (${currencyFormat.format(tab.totalAmount)} đ).\nBạn có chắc chắn muốn đóng và xóa các món trong đơn này không?',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Bỏ qua', style: TextStyle(color: Colors.black54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Đóng hóa đơn'),
          ),
        ],
      ),
    );

    if (shouldClose == true) {
      ref.read(multiCartProvider.notifier).closeTab(tab.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiCartState = ref.watch(multiCartProvider);
    final tabs = multiCartState.tabs;
    final activeTabId = multiCartState.activeTabId;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: tabs.length + 1, // +1 for the "Add Tab" button
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // Nút thêm tab mới ở cuối danh sách
          if (index == tabs.length) {
            return InkWell(
              key: const Key('pos_cart_add_tab_btn'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                ref.read(multiCartProvider.notifier).addNewTab();
                // Cuộn tới tab mới thêm
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Thêm đơn',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final tab = tabs[index];
          final isActive = tab.id == activeTabId;
          final itemCount = tab.totalItems;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('pos_cart_tab_${tab.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                ref.read(multiCartProvider.notifier).switchTab(tab.id);
                _scrollToActiveTab(index, tabs.length);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? AppColors.primary : AppColors.border,
                    width: isActive ? 1.5 : 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_outlined,
                      size: 14,
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tab.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.w500,
                        color:
                            isActive ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    if (itemCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.white
                              : AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$itemCount',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? AppColors.primary
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    // Nút đóng tab
                    InkWell(
                      key: Key('pos_cart_tab_close_${tab.id}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _handleCloseTab(context, ref, tab),
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: isActive
                              ? Colors.white.withOpacity(0.85)
                              : Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
