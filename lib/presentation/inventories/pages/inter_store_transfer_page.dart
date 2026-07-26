import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventory/inter_store_transfer_service.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/product.dart';

class InterStoreTransferPage extends ConsumerStatefulWidget {
  const InterStoreTransferPage({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<InterStoreTransferPage> createState() =>
      _InterStoreTransferPageState();
}

class _InterStoreTransferPageState
    extends ConsumerState<InterStoreTransferPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  String? _selectedTargetStoreId;
  bool _isLoading = false;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final availableStoresAsync = ref.watch(availableStoresProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.transferProduct,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      body: availableStoresAsync.when(
        data: (storesMap) {
          final availableTargets = storesMap.entries
              .where((entry) => entry.key != currentStoreId)
              .toList();

          if (availableTargets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.store_outlined,
                      size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noOtherStoreToTransfer,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          final sourceStoreName = storesMap[currentStoreId] ?? currentStoreId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Product Info Hero Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.secondaryContainer,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.product.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${l10n.currentStock}: ${widget.product.stock}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Transfer Details Section
                  Text(
                    l10n.transferDetails,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Source Store (Read-only)
                          _buildModernField(
                            label: l10n.exportingStore,
                            child: TextFormField(
                              initialValue: sourceStoreName,
                              readOnly: true,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.storefront,
                                    color: colorScheme.primary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withOpacity(0.3),
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Icon(
                              Icons.arrow_downward_rounded,
                              color: colorScheme.primary,
                              size: 28,
                            ),
                          ),

                          // Target Store Dropdown
                          _buildModernField(
                            label: l10n.targetStore,
                            child: DropdownButtonFormField<String>(
                              value: _selectedTargetStoreId,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.store,
                                    color: colorScheme.secondary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                              ),
                              icon:
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                              items: availableTargets.map((entry) {
                                return DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(
                                    entry.value,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                );
                              }).toList(),
                              validator: (value) =>
                                  value == null ? l10n.selectTargetStore : null,
                              onChanged: (value) {
                                setState(() => _selectedTargetStoreId = value);
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Quantity Field
                          _buildModernField(
                            label: l10n.transferQuantity,
                            child: TextFormField(
                              controller: _quantityController,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(
                                    Icons.production_quantity_limits),
                                hintText: l10n.enterQuantityHint,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '${l10n.pleaseEnter} ${l10n.quantity}';
                                }
                                final quantity = int.tryParse(value);
                                if (quantity == null || quantity <= 0) {
                                  return l10n.pleaseEnterValidNumber;
                                }
                                if (quantity > widget.product.stock) {
                                  return l10n.notEnoughStock;
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Submit Button
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _transferProduct,
                    icon: _isLoading
                        ? Container(
                            width: 24,
                            height: 24,
                            padding: const EdgeInsets.all(2.0),
                            child: CircularProgressIndicator(
                              color: colorScheme.onPrimary,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      l10n.transfer,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildModernField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Future<void> _transferProduct() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTargetStoreId == null) return;

    setState(() => _isLoading = true);

    try {
      final quantity = int.parse(_quantityController.text.trim());
      final currentStoreId = ref.read(currentStoreIdProvider);
      final transferService = ref.read(interStoreTransferServiceProvider);
      final storesMap = ref.read(availableStoresProvider).value ?? {};
      final sourceStoreName = storesMap[currentStoreId] ?? currentStoreId;
      final targetStoreName =
          storesMap[_selectedTargetStoreId!] ?? _selectedTargetStoreId!;

      final currentUser = ref.read(authProvider);

      final error = await transferService.transferProduct(
        sourceStoreId: currentStoreId,
        targetStoreId: _selectedTargetStoreId!,
        product: widget.product,
        quantity: quantity,
        sourceStoreName: sourceStoreName,
        targetStoreName: targetStoreName,
        createdBy: currentUser?.username,
        createdByName: currentUser?.name,
      );

      if (mounted) {
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        } else {
          ref.invalidate(productListProvider);
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(l10n.transferCompleted,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
