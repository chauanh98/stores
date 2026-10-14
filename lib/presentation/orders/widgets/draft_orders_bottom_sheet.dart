import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../data/datasources/firebase/order_remote_data_source.dart';
import '../../../data/repositories/order_repository_impl.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../common/widgets/loading_indicator.dart';

class DraftOrdersBottomSheet extends ConsumerWidget {
  const DraftOrdersBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const DraftOrdersBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draftsAsync = ref.watch(posDraftOrdersProvider);
    final availableStores =
        ref.watch(availableStoresProvider).valueOrNull ?? {};
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.pending_actions_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                  draftsAsync.maybeWhen(
                    data: (drafts) =>
                        l10n?.draftOrdersCountTitle(drafts.length) ??
                        'Đơn hàng tạm (${drafts.length})',
                    orElse: () => l10n?.draftOrdersTitle ?? 'Đơn hàng tạm',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                )),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n?.close ?? 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),

          // Content
          Expanded(
            child: draftsAsync.when(
              loading: () => const Center(child: LoadingIndicator()),
              error: (err, _) => Center(
                child: SingleChildScrollView(
                    child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n?.draftOrdersLoadError(err.toString()) ??
                        'Lỗi khi tải đơn tạm: $err',
                  ),
                )),
              ),
              data: (drafts) {
                if (drafts.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.pending_actions_outlined,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.draftOrdersEmpty ??
                                'Không có đơn hàng tạm nào',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n?.draftOrdersEmptyHint ??
                                'Khi bán hàng, bạn có thể bấm "Lưu tạm" để lưu giỏ hàng và mở lại thanh toán bất cứ lúc nào.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )),
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: drafts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = drafts[index];
                    return _buildDraftCard(
                      context,
                      ref,
                      order,
                      availableStores,
                      currencyFormat,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(
    BuildContext context,
    WidgetRef ref,
    Order order,
    Map<String, String> availableStores,
    NumberFormat currencyFormat,
  ) {
    final l10n = AppLocalizations.of(context);
    final customerName =
        (order.customerName != null && order.customerName!.trim().isNotEmpty)
            ? order.customerName!
            : (order.customerId.isNotEmpty &&
                    order.customerId != 'khach_le' &&
                    order.customerId != 'walk_in'
                ? order.customerId
                : (l10n?.retailCustomer ?? 'Khách lẻ'));

    final itemsSummary =
        order.items.map((i) => '${i.productName} (x${i.quantity})').join(', ');

    final branchName = availableStores[
            StoreResolverHelper.normalizeStoreId(order.storeId ?? '')] ??
        (order.storeId ?? '');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Code + Branch Badge + Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          order.id,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (branchName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                            child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.infoLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.info.withOpacity(0.3)),
                          ),
                          child: Text(
                            branchName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.info,
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                    child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    DateFormat('HH:mm · dd/MM/yyyy').format(order.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 8),

            // Row 2: Customer Name
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (order.createdByName != null &&
                    order.createdByName!.isNotEmpty)
                  Flexible(
                    child: Text(
                      '${l10n?.staff ?? 'NV'}: ${order.createdByName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 3: Items summary
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.shopping_bag_outlined,
                      size: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${order.items.length} mặt hàng · $itemsSummary',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Row 4: Order Note (if any)
            if (order.note != null && order.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.notes,
                        size: 15, color: AppColors.warningDeep),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: 18, color: AppColors.divider),

            // Row 5: Total & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.totalAmount ?? 'Tổng tiền',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${currencyFormat.format(order.total)} đ',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                )),
                const SizedBox(width: 8),
                Flexible(
                    child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _confirmDeleteDraft(context, ref, order),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(l10n?.cancel ?? 'Hủy',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    FilledButton.icon(
                      onPressed: () => _resumeDraftOrder(context, ref, order),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                      label: Text(l10n?.draftOrderOpen ?? 'Mở đơn',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteDraft(BuildContext context, WidgetRef ref, Order order) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        scrollable: true,
        title: Text(l10n?.draftOrderCancelTitle ?? 'Hủy đơn hàng tạm'),
        content: Text(
          l10n?.draftOrderCancelConfirm(order.id) ??
              'Bạn có chắc chắn muốn hủy đơn tạm ${order.id} không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n?.draftOrderSkip ?? 'Bỏ qua'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                final storeId =
                    (order.storeId != null && order.storeId!.isNotEmpty)
                        ? order.storeId!
                        : ref.read(currentStoreIdProvider);
                final ds = OrderRemoteDataSource(
                    ref.read(firebaseDatabaseProvider), storeId);
                final repo = OrderRepositoryImpl(ds);
                await repo.delete(order.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n?.draftOrderCancelSuccess(order.id) ??
                            'Đã hủy đơn tạm ${order.id}',
                      ),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n?.draftOrderCancelError(e.toString()) ??
                            'Lỗi khi hủy đơn: $e',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              l10n?.draftOrderCancelActionButton ?? 'Hủy đơn',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resumeDraftOrder(
      BuildContext context, WidgetRef ref, Order order) async {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(); // Close bottom sheet

    // 1. If active cart tab already has items, open in a new tab
    final multiCart = ref.read(multiCartProvider);
    if (multiCart.activeTab.items.isNotEmpty) {
      ref.read(multiCartProvider.notifier).addNewTab(
            title: 'Đơn ${order.id}',
          );
    }

    // 2. Set active draft order ID
    ref.read(activeOrderIdProvider.notifier).state = order.id;

    // 3. Set branch if order has storeId
    if (order.storeId != null && order.storeId!.isNotEmpty) {
      ref.read(selectedPOSBranchProvider.notifier).state = order.storeId!;
    }

    // 4. Resolve customer
    final customers =
        ref.read(customerListNotifierProvider).valueOrNull ?? <Customer>[];
    Customer? customer;
    if (order.customerId.isNotEmpty &&
        order.customerId != 'khach_le' &&
        order.customerId != 'walk_in') {
      customer = customers.cast<Customer?>().firstWhere(
            (c) => c?.id == order.customerId,
            orElse: () => null,
          );
      customer ??= Customer(
        id: order.customerId,
        name: order.customerName ?? order.customerId,
        phone: '',
        email: '',
        address: '',
        purchases: const [],
      );
    }

    // 5. Fetch all products to match metadata
    var products = ref.read(productListProvider).valueOrNull ?? [];
    if (products.isEmpty) {
      try {
        products = await ref.read(productRepositoryProvider).fetchAll();
      } catch (_) {}
    }

    // 6. Populate cart
    ref.read(cartProvider.notifier).populateCart(
          order.items,
          products,
          orderId: order.id,
          customer: customer,
          discount: order.discount,
          isDiscountPercent: false,
          note: order.note,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.draftOrderLoadedToCart(order.id) ??
                'Đã nạp đơn tạm ${order.id} vào giỏ hàng',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
