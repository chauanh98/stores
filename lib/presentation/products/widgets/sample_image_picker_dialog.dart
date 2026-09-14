import 'package:flutter/material.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/core/utils/vietnamese_text_helper.dart';

/// Modal dialog for browsing and selecting sample images with smart suggestions.
class SampleImagePickerDialog extends StatefulWidget {
  final String productName;
  final String? category;
  final String? brand;
  final String? category3Levels;
  final bool isCombo;

  const SampleImagePickerDialog({
    super.key,
    required this.productName,
    this.category,
    this.brand,
    this.category3Levels,
    this.isCombo = false,
  });

  /// Static helper to show the dialog and return selected image URL
  static Future<String?> show(
    BuildContext context, {
    required String productName,
    String? category,
    String? brand,
    String? category3Levels,
    bool isCombo = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SampleImagePickerDialog(
        productName: productName,
        category: category,
        brand: brand,
        category3Levels: category3Levels,
        isCombo: isCombo,
      ),
    );
  }

  @override
  State<SampleImagePickerDialog> createState() => _SampleImagePickerDialogState();
}

class _SampleImagePickerDialogState extends State<SampleImagePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedIndustry;

  List<SampleImageMatch> _suggestedMatches = [];
  List<SampleImageCategory> _allCategories = [];

  @override
  void initState() {
    super.initState();
    _allCategories = SampleImageHelper.getAllCategories();
    _loadSuggestions();
  }

  void _loadSuggestions() {
    _suggestedMatches = SampleImageHelper.getSuggestedImagesForText(
      widget.productName,
      category: widget.category,
      brand: widget.brand,
      category3Levels: widget.category3Levels,
      isCombo: widget.isCombo,
      limit: 8,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SampleImageCategory> _getFilteredCategories() {
    final query = VietnameseTextHelper.normalizeUnaccented(_searchQuery);
    return _allCategories.where((cat) {
      if (_selectedIndustry != null && cat.industry != _selectedIndustry) {
        return false;
      }
      if (query.isEmpty) return true;

      final nameUnacc = VietnameseTextHelper.normalizeUnaccented(cat.name);
      final industryUnacc = VietnameseTextHelper.normalizeUnaccented(cat.industry);
      final kwMatch = cat.keywords.any((kw) =>
          VietnameseTextHelper.normalizeUnaccented(kw).contains(query));

      return nameUnacc.contains(query) || industryUnacc.contains(query) || kwMatch;
    }).toList();
  }

  Set<String> _getIndustries() {
    return _allCategories.map((c) => c.industry).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final industries = _getIndustries().toList();
    final filteredCategories = _getFilteredCategories();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Gợi ý & Chọn Ảnh Mẫu Thông Minh',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm ảnh theo tên, ngành hàng, từ khóa...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Quick Filter Chips by Industry
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: industries.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) {
                if (idx == 0) {
                  final isSelected = _selectedIndustry == null;
                  return ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedIndustry = null),
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: isSelected ? AppColors.primary : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }
                final ind = industries[idx - 1];
                final isSelected = _selectedIndustry == ind;
                return ChoiceChip(
                  label: Text(ind),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedIndustry = isSelected ? null : ind),
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? AppColors.primary : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1, color: AppColors.borderLight),

          // Content List / Grid
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top Smart Suggestions Section (if not searching with text)
                if (_searchQuery.isEmpty && _selectedIndustry == null && _suggestedMatches.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.amber, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ảnh gợi ý phù hợp nhất cho "${widget.productName.isNotEmpty ? widget.productName : "sản phẩm"}"',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: _suggestedMatches.length,
                    itemBuilder: (ctx, index) {
                      final match = _suggestedMatches[index];
                      return _buildImageCard(
                        category: match.category,
                        isBestMatch: index == 0,
                        score: match.score,
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.borderLight),
                  const SizedBox(height: 10),
                ],

                // All Categories Section
                Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'Kết quả tìm kiếm (${filteredCategories.length})'
                          : 'Tất cả danh mục ảnh mẫu (${filteredCategories.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (filteredCategories.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'Không tìm thấy ảnh mẫu phù hợp',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: filteredCategories.length,
                    itemBuilder: (ctx, index) {
                      final cat = filteredCategories[index];
                      return _buildImageCard(category: cat);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard({
    required SampleImageCategory category,
    bool isBestMatch = false,
    int? score,
  }) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(category.imageUrl),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isBestMatch ? AppColors.primary : AppColors.borderLight,
            width: isBestMatch ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      child: Image.network(
                        category.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade100,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  if (isBestMatch)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, color: Colors.white, size: 10),
                            SizedBox(width: 2),
                            Text(
                              'Khuyên dùng',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Caption
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.industry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
