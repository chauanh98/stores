import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/products/categories_providers.dart';
import '../../../domain/entities/category.dart';
import 'select_category_page.dart';

class AddCategoryPage extends ConsumerStatefulWidget {
  const AddCategoryPage({super.key});

  @override
  ConsumerState<AddCategoryPage> createState() => _AddCategoryPageState();
}

class _AddCategoryPageState extends ConsumerState<AddCategoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  Category? _parentCategory;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(l10n.newCategoryTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: AppColors.primary),
            onPressed: _isSaving ? null : _saveCategory,
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.borderLight),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.category,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black87),
                            ),
                            const SizedBox(height: 16),
                            // Tên nhóm
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: '${l10n.category} *',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return '${l10n.pleaseEnter} ${l10n.category}';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            // Nhóm cha
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.parentCategoryLabel,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.black54)),
                              subtitle: Text(
                                _parentCategory?.name ?? l10n.notFound,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    fontSize: 15),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _selectParentCategory,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _selectParentCategory() async {
    final selected = await Navigator.push<Category>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SelectCategoryPage(initialCategory: _parentCategory),
      ),
    );
    if (selected != null) {
      setState(() {
        _parentCategory = selected;
      });
    }
  }

  void _saveCategory() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final cleanName =
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      final id = _parentCategory != null
          ? '${_parentCategory!.id}_$cleanName'
          : cleanName;

      final category = Category(
        id: id,
        name: name,
        parentId: _parentCategory?.id,
      );

      await ref.read(categoryRepositoryProvider).upsert(category);
      ref.invalidate(categoryListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.save), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, category);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.importError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
