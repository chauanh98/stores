import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/products/products_providers.dart';

class SelectBrandPage extends ConsumerStatefulWidget {
  final String? initialBrand;

  const SelectBrandPage({super.key, this.initialBrand});

  @override
  ConsumerState<SelectBrandPage> createState() => _SelectBrandPageState();
}

class _SelectBrandPageState extends ConsumerState<SelectBrandPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<String> _defaultBrands = [
    'Duy Tân',
    'Lợi Phát (Quỳnh Anh)',
    'Mỹ',
    'Nhơn Hòa',
    'Nhật Phi',
    'Phi Hùng',
    'Phương Tiên',
    'Qui Phúc',
    'Thắng Lợi',
    'Việt Việt Phát',
    'Vạn Thành',
    'Đại Đồng Tiến'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Thương hiệu',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF0067AC), size: 28),
            tooltip: 'Thêm thương hiệu mới',
            onPressed: _showAddBrandDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm thương hiệu...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                fillColor: Colors.white,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF0067AC)),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          // List of Brands
          Expanded(
            child: productsAsync.when(
              data: (products) {
                // Collect unique brands from existing products
                final productBrands = products
                    .map((p) => p.brand?.trim())
                    .where((b) => b != null && b.isNotEmpty)
                    .cast<String>()
                    .toSet();

                // Combine product brands and default list
                final allBrands = {...productBrands, ..._defaultBrands}.toList()
                  ..sort();

                // Filter brands based on query
                final filtered = allBrands.where((brand) {
                  return brand
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase());
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('Không tìm thấy thương hiệu nào'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, idx) {
                    final brand = filtered[idx];
                    final isSelected =
                        widget.initialBrand?.trim() == brand.trim();

                    return ListTile(
                      tileColor:
                          isSelected ? const Color(0xFFE0F2FE) : Colors.white,
                      title: Text(
                        brand,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? const Color(0xFF0369A1)
                              : Colors.black87,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF0067AC))
                          : null,
                      onTap: () {
                        Navigator.pop(context, brand);
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Lỗi: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddBrandDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thương hiệu mới'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Tên thương hiệu',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(this.context, name); // Return value to caller
                } else {
                  Navigator.pop(context);
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0067AC)),
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    );
  }
}
