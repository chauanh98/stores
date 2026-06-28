import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';

import '../../../application/orders/orders_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/customer.dart';
import 'pos_checkout_page.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // 'all', 'completed', 'draft'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeRange = ref.watch(activeDateRangeProvider);
    final timeRangeType = ref.watch(selectedTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);

    // Watch all orders for the active date range (including multi-branch support)
    final ordersAsync = ref.watch(allBranchesOrdersByDateRangeProvider(activeRange));
    final customersAsync = ref.watch(customerListNotifierProvider);

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    // Nhãn hiển thị thời gian
    final String dateLabel;
    if (timeRangeType == OverviewTimeRange.custom) {
      dateLabel = '${DateFormat('dd/MM').format(activeRange.start)} - ${DateFormat('dd/MM').format(activeRange.end)}';
    } else {
      dateLabel = timeRangeType.label;
    }

    final currentStoreId = ref.watch(currentStoreIdProvider);
    final mockBranches = getMockBranches(currentStoreId);

    // Nhãn hiển thị chi nhánh
    String branchLabel;
    if (selectedBranchIds.length == mockBranches.length) {
      branchLabel = 'Tất cả chi nhánh';
    } else if (selectedBranchIds.length == 1) {
      branchLabel = mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Hoá đơn', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          // 1. Thanh tìm kiếm hoá đơn
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo mã hoá đơn, tên khách hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                fillColor: Colors.white,
                filled: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE1E2E4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF0067AC)),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE1E2E4)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // 2. Thanh bộ lọc (Thời gian & Chi nhánh)
          _buildFiltersBar(context, dateLabel, branchLabel),

          // Bộ lọc trạng thái hoá đơn (Tất cả, Đã thanh toán, Lưu tạm)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                _buildStatusFilterChip('all', 'Tất cả'),
                const SizedBox(width: 8),
                _buildStatusFilterChip('completed', 'Đã thanh toán'),
                const SizedBox(width: 8),
                _buildStatusFilterChip('draft', 'Lưu tạm'),
              ],
            ),
          ),

          // 3. Nội dung hoá đơn
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                return customersAsync.when(
                  data: (customers) {
                    final branchFilteredOrders = orders;

                    // Áp dụng bộ lọc trạng thái
                    final statusFilteredOrders = branchFilteredOrders.where((order) {
                      if (_selectedStatusFilter == 'all') return true;
                      return order.status == _selectedStatusFilter;
                    }).toList();

                    // Tìm kiếm
                    final searchFilteredOrders = statusFilteredOrders.where((order) {
                      final query = _searchQuery.toLowerCase().trim();
                      if (query.isEmpty) return true;

                      final cName = _getCustomerName(customers, order.customerId).toLowerCase();
                      return order.id.toLowerCase().contains(query) || cName.contains(query);
                    }).toList();

                    // Sắp xếp đơn mới nhất lên đầu
                    searchFilteredOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final totalInvoices = searchFilteredOrders.length;
                    final totalRevenue = searchFilteredOrders.fold(0.0, (sum, o) => sum + o.total);

                    return Column(
                      children: [
                        // Thẻ thống kê tổng tiền hoá đơn đang lọc
                        _buildTotalSummaryCard(totalInvoices, totalRevenue, currencyFormat),
                        
                        // Danh sách
                        Expanded(
                          child: searchFilteredOrders.isEmpty
                              ? const Center(child: Text('Không tìm thấy hoá đơn nào'))
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  itemCount: searchFilteredOrders.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final order = searchFilteredOrders[index];
                                    final customerName = _getCustomerName(customers, order.customerId);
                                    
                                    // Mô phỏng phương thức thanh toán dựa trên mã đơn
                                    final isCash = order.id.hashCode % 3 != 0;
                                    final paymentMethodStr = isCash ? 'Tiền mặt' : 'Chuyển khoản';

                                    return InkWell(
                                      onTap: () => _showInvoiceDetailsBottomSheet(context, ref, order, customerName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE1E2E4)),
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  customerName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                                ),
                                                Text(
                                                  '${currencyFormat.format(order.total)} đ',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0067AC), fontSize: 14),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Mã đơn: ${order.id}',
                                                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt),
                                                      style: const TextStyle(color: Colors.black38, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: order.status == 'draft'
                                                            ? Colors.orange.withOpacity(0.06)
                                                            : Colors.green.withOpacity(0.06),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        order.status == 'draft' ? 'Lưu tạm' : 'Đã thanh toán',
                                                        style: TextStyle(
                                                          color: order.status == 'draft' ? Colors.orange : Colors.green,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0067AC).withOpacity(0.06),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        paymentMethodStr,
                                                        style: const TextStyle(color: Color(0xFF0067AC), fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: LoadingIndicator()),
                  error: (e, _) => Center(child: ErrorView(e)),
                );
              },
              loading: () => const Center(child: LoadingIndicator()),
              error: (e, _) => Center(child: ErrorView(e)),
            ),
          ),
        ],
      ),
    );
  }

  // Thanh bộ lọc (Thời gian & Chi nhánh)
  Widget _buildFiltersBar(BuildContext context, String dateText, String branchText) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          // Bộ lọc Thời gian
          Expanded(
            child: InkWell(
              onTap: () => _showDateRangeFilterBottomSheet(context),
              child: Row(
                children: [
                  Text(
                    dateText,
                    style: const TextStyle(
                      color: Color(0xFF0067AC),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF0067AC), size: 18),
                ],
              ),
            ),
          ),
          // Bộ lọc Chi nhánh
          InkWell(
            onTap: () => _showBranchFilterBottomSheet(context),
            child: Row(
              children: [
                Text(
                  branchText,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.black54, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Thẻ tổng kết trên cùng danh sách hoá đơn
  Widget _buildTotalSummaryCard(int count, double totalRevenue, NumberFormat format) {
    return Container(
      color: const Color(0xFFE3F2FD),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Tổng cộng ($count hoá đơn)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
          ),
          Text(
            '${format.format(totalRevenue)} đ',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0067AC)),
          )
        ],
      ),
    );
  }

  // Tra cứu tên khách hàng dựa trên ID
  String _getCustomerName(List<Customer> customers, String id) {
    if (id == 'khach_le' || id.isEmpty) return 'Khách lẻ';
    final match = customers.firstWhere((c) => c.id == id, orElse: () => const Customer(id: '', name: 'Khách lẻ', phone: '', email: '', address: '', purchases: []));
    return match.name;
  }

  // Hộp thoại Bottom Sheet lọc Thời gian
  void _showDateRangeFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (consumerContext, sheetRef, child) {
            final activeType = sheetRef.watch(selectedTimeRangeTypeProvider);
            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Thời gian',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  ...OverviewTimeRange.values.map((type) {
                    final isSelected = activeType == type;
                    return ListTile(
                      title: Text(
                        type.label,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF0067AC) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0067AC)) : null,
                      onTap: () async {
                        Navigator.pop(consumerContext);
                        if (type == OverviewTimeRange.custom) {
                          final initialRange = ref.read(customDateRangeProvider);
                          final now = DateTime.now();
                          // Chuẩn hóa initialRange về start of day để tránh lỗi của Flutter date picker
                          final normalizedInitialRange = DateTimeRange(
                            start: DateTime(initialRange.start.year, initialRange.start.month, initialRange.start.day),
                            end: DateTime(initialRange.end.year, initialRange.end.month, initialRange.end.day),
                          );
                          final pickedRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(now.year, now.month, now.day),
                            initialDateRange: normalizedInitialRange,
                          );
                          if (pickedRange != null) {
                            ref.read(customDateRangeProvider.notifier).state = pickedRange;
                            ref.read(selectedTimeRangeTypeProvider.notifier).state = OverviewTimeRange.custom;
                          }
                        } else {
                          ref.read(selectedTimeRangeTypeProvider.notifier).state = type;
                        }
                      },
                    );
                  }).toList(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Hộp thoại Bottom Sheet lọc Chi nhánh
  void _showBranchFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final selectedBranchIds = ref.watch(selectedBranchesProvider);
            final notifier = ref.read(selectedBranchesProvider.notifier);
            final currentStoreId = ref.watch(currentStoreIdProvider);
            final mockBranches = getMockBranches(currentStoreId);

            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chọn chi nhánh',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        InkWell(
                          onTap: () {
                            notifier.selectAll();
                          },
                          child: const Text(
                            'Chọn tất cả',
                            style: TextStyle(color: Color(0xFF0067AC), fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        )
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  ...mockBranches.map((branch) {
                    final isChecked = selectedBranchIds.contains(branch.id);
                    return CheckboxListTile(
                      title: Text(branch.name),
                      value: isChecked,
                      activeColor: const Color(0xFF0067AC),
                      onChanged: (_) {
                        notifier.toggleBranch(branch.id);
                      },
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0067AC),
                        ),
                        child: const Text('Xong'),
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusFilterChip(String value, String label) {
    final isSelected = _selectedStatusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedStatusFilter = value;
          });
        }
      },
      selectedColor: const Color(0xFF0067AC).withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF0067AC) : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  void _showInvoiceDetailsBottomSheet(
    BuildContext context,
    WidgetRef ref,
    Order order,
    String customerName,
  ) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.status == 'draft' ? 'Chi tiết đơn tạm' : 'Chi tiết hoá đơn',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(color: Color(0xFFEEEEEE)),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Mã hoá đơn', order.id),
                      _buildDetailRow('Khách hàng', customerName),
                      _buildDetailRow('Thời gian tạo', DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)),
                      _buildDetailRow(
                        'Trạng thái',
                        order.status == 'draft' ? 'Lưu tạm (Chưa thanh toán)' : 'Đã thanh toán',
                        textColor: order.status == 'draft' ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Danh sách sản phẩm',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      ...order.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      '${item.quantity} x ${currencyFormat.format(item.price)} đ',
                                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                                    )
                                  ],
                                ),
                              ),
                              Text(
                                '${currencyFormat.format(item.price * item.quantity)} đ',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                        );
                      }).toList(),
                      const Divider(height: 24, color: Color(0xFFEEEEEE)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tổng tiền thanh toán',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            '${currencyFormat.format(order.total)} đ',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0067AC)),
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (order.status == 'draft') ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context); // Đóng Bottom Sheet
                      
                      // Nạp lại đơn hàng nháp vào giỏ hàng
                      final products = ref.read(productListProvider).value ?? [];
                      ref.read(cartProvider.notifier).populateCart(order.items, products);
                      
                      // Set mã đơn tạm đang hoạt động
                      ref.read(activeOrderIdProvider.notifier).state = order.id;

                      // Tìm khách hàng
                      final customers = ref.read(customerListNotifierProvider).value ?? [];
                      Customer? customer;
                      for (final c in customers) {
                        if (c.id == order.customerId) {
                          customer = c;
                          break;
                        }
                      }

                      // Điều hướng trực tiếp sang màn hình thanh toán
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => POSCheckoutPage(
                            initialCustomer: customer,
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0067AC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Tiếp tục thanh toán / Lên đơn',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                )
              ]
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor ?? Colors.black87,
            ),
          )
        ],
      ),
    );
  }
}
