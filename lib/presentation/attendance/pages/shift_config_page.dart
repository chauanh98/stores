import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/attendance/attendance_providers.dart';
import '../../../application/attendance/store_gps_config_notifier.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/geo_distance_helper.dart';
import '../../../domain/attendance/shift.dart';
import '../../../domain/attendance/store_gps_config.dart';

class ShiftConfigPage extends ConsumerStatefulWidget {
  const ShiftConfigPage({super.key});

  @override
  ConsumerState<ShiftConfigPage> createState() => _ShiftConfigPageState();
}

class _ShiftConfigPageState extends ConsumerState<ShiftConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _syncConfigToFields(StoreGpsConfig? config) {
    if (config != null) {
      _latController.text = config.latitude.toString();
      _lngController.text = config.longitude.toString();
      _radiusController.text = config.allowedRadiusMeters.toString();
      _addressController.text = config.address ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftsState = ref.watch(shiftListNotifierProvider);
    final gpsState = ref.watch(storeGpsConfigNotifierProvider);
    final user = ref.watch(authProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);
    final storeNames = storeNamesAsync.valueOrNull ?? {};

    // Sync fields if empty
    if (_latController.text.isEmpty && gpsState.config != null) {
      _syncConfigToFields(gpsState.config);
    }

    final canManage = user?.canManageShifts == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Cấu hình Ca làm việc & GPS Chi nhánh',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 13,
          ),
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'DANH SÁCH CA LÀM'),
            Tab(text: 'TỌA ĐỘ GPS CHI NHÁNH'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Ca làm việc
          _buildShiftsTab(shiftsState, canManage),

          // Tab 2: Cấu hình GPS
          _buildGpsConfigTab(gpsState, user, storeNames, canManage),
        ],
      ),
      floatingActionButton: (_tabController.index == 0 && canManage)
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showShiftEditDialog(null),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildShiftsTab(ShiftListState state, bool canManage) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final shifts = state.shifts;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: shifts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final shift = shifts[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.12),
              child: const Icon(Icons.schedule, color: AppColors.primary),
            ),
            title: Text(shift.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${shift.startTime} - ${shift.endTime} • Chuẩn: ${shift.standardWorkHours}h • Ân hạn: ${shift.gracePeriodMinutes}p',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: canManage
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                        onPressed: () => _showShiftEditDialog(shift),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xác nhận xóa'),
                              content: Text('Bạn có chắc muốn xóa ca "${shift.name}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.danger))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            ref.read(shiftListNotifierProvider.notifier).deleteShift(shift.id);
                          }
                        },
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildGpsConfigTab(
    StoreGpsConfigState state,
    dynamic user,
    Map<String, String> storeNames,
    bool canManage,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentStoreId = state.storeId;
    final currentStoreName = storeNames[currentStoreId] ?? currentStoreId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cấu hình Geofence GPS Chi nhánh',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Store Selector for Admin
              if (user?.role.toLowerCase().trim() == 'admin') ...[
                const Text('Chọn Chi nhánh cấu hình:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: storeNames.containsKey(currentStoreId) ? currentStoreId : null,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: storeNames.entries.map((e) {
                    return DropdownMenuItem(value: e.key, child: Text(e.value));
                  }).toList(),
                  onChanged: canManage
                      ? (newStore) {
                          if (newStore != null) {
                            ref.read(storeGpsConfigNotifierProvider.notifier).loadConfig(newStore);
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 14),
              ] else ...[
                Text('Chi nhánh: $currentStoreName', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
              ],

              TextField(
                controller: _latController,
                readOnly: !canManage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Vĩ độ (Latitude) *',
                  hintText: 'Ví dụ: 10.035000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _lngController,
                readOnly: !canManage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Kinh độ (Longitude) *',
                  hintText: 'Ví dụ: 105.788000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _radiusController,
                readOnly: !canManage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Bán kính cho phép chấm công (mét) *',
                  hintText: 'Mặc định: 150 mét',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.my_location),
                label: const Text('Lấy tọa độ vị trí hiện tại'),
                onPressed: canManage
                    ? () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final pos = await ref.read(storeGpsConfigNotifierProvider.notifier).getCurrentGpsCoordinates();
                        if (pos != null) {
                          _latController.text = pos.latitude.toString();
                          _lngController.text = pos.longitude.toString();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Đã lấy tọa độ: ${pos.latitude}, ${pos.longitude}')),
                          );
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: state.isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(state.isSaving ? 'ĐANG LƯU...' : 'LƯU CẤU HÌNH GPS'),
                  onPressed: (state.isSaving || !canManage)
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final lat = double.tryParse(_latController.text) ?? 10.035;
                          final lng = double.tryParse(_lngController.text) ?? 105.788;
                          final rad = double.tryParse(_radiusController.text) ?? GeoDistanceHelper.defaultAllowedRadiusMeters;

                          final newConfig = StoreGpsConfig(
                            storeId: currentStoreId,
                            latitude: lat,
                            longitude: lng,
                            allowedRadiusMeters: rad,
                            storeName: currentStoreName,
                            address: _addressController.text.trim(),
                          );

                          final success = await ref.read(storeGpsConfigNotifierProvider.notifier).saveConfig(newConfig);
                          if (success) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Cập nhật GPS thành công!')),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShiftEditDialog(Shift? shift) {
    final nameCtrl = TextEditingController(text: shift?.name ?? '');
    final startCtrl = TextEditingController(text: shift?.startTime ?? '08:00');
    final endCtrl = TextEditingController(text: shift?.endTime ?? '12:00');
    final graceCtrl = TextEditingController(text: (shift?.gracePeriodMinutes ?? 15).toString());
    final hoursCtrl = TextEditingController(text: (shift?.standardWorkHours ?? 4.0).toString());
    String shiftType = shift?.type ?? 'morning';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(shift == null ? 'Thêm ca làm việc mới' : 'Chỉnh sửa ca làm việc'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên ca *', hintText: 'Ca Sáng', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: shiftType,
                  decoration: const InputDecoration(labelText: 'Loại ca', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Ca Sáng')),
                    DropdownMenuItem(value: 'afternoon', child: Text('Ca Chiều')),
                    DropdownMenuItem(value: 'evening', child: Text('Ca Tối')),
                    DropdownMenuItem(value: 'flexible', child: Text('Ca Linh hoạt')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => shiftType = v);
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startCtrl,
                        decoration: const InputDecoration(labelText: 'Giờ bắt đầu', hintText: '08:00', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: endCtrl,
                        decoration: const InputDecoration(labelText: 'Giờ kết thúc', hintText: '12:00', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: graceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Ân hạn (phút)', hintText: '15', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: hoursCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Chuẩn (giờ)', hintText: '4.0', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                final newShift = Shift(
                  id: shift?.id ?? 'shift_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  startTime: startCtrl.text.trim(),
                  endTime: endCtrl.text.trim(),
                  gracePeriodMinutes: int.tryParse(graceCtrl.text) ?? 15,
                  standardWorkHours: double.tryParse(hoursCtrl.text) ?? 4.0,
                  type: shiftType,
                );

                ref.read(shiftListNotifierProvider.notifier).saveShift(newShift);
                Navigator.pop(ctx);
              },
              child: const Text('Lưu ca'),
            ),
          ],
        ),
      ),
    );
  }
}
