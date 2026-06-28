import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import '../widgets/customer_list_tile.dart';
import 'add_customer_page.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final customersAsync = ref.watch(customerListNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customers),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Customers list
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                final filteredCustomers =
                    _filterCustomers(customers, _searchQuery);

                if (filteredCustomers.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          l10n.notFound,
                          style:
                              const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        Text(
                          l10n.tryAdjustingSearch,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref
                        .read(customerListNotifierProvider.notifier)
                        .refresh();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      return CustomerListTile(customer: customer);
                    },
                  ),
                );
              },
              loading: () => const LoadingIndicator(),
              error: (error, stack) => ErrorView(error),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addCustomerFab',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddCustomerPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Customer> _filterCustomers(List<Customer> customers, String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return customers;

    final lowercaseQuery = trimmedQuery.toLowerCase();
    return customers.where((customer) {
      return customer.name.toLowerCase().contains(lowercaseQuery) ||
          customer.phone.toLowerCase().contains(lowercaseQuery) ||
          customer.email.toLowerCase().contains(lowercaseQuery) ||
          customer.address.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }
}
