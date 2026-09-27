import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('UserAccount Entity Permissions', () {
    test('Admin account permissions', () {
      const admin = UserAccount(
        username: 'admin_user',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      expect(admin.isAdmin, isTrue);
      expect(admin.isSupervisor, isFalse);
      expect(admin.isStaff, isFalse);
      expect(admin.isAllStores, isTrue);
      expect(admin.canSwitchStore, isTrue);
      expect(admin.canManageUsers, isTrue);
      expect(admin.canViewDebtSummary, isTrue);
      expect(admin.canViewTotalSales, isTrue);
      expect(admin.canViewCostPrice, isTrue);
      expect(admin.canManageProducts, isTrue);
      expect(admin.canDeleteInvoice, isTrue);
      expect(admin.canDeleteCustomer, isTrue);
      expect(admin.canExportCustomers, isTrue);
      expect(admin.canChangeImportStore, isTrue);
      expect(admin.canChangeTransferSourceStore, isTrue);
      expect(admin.canEditPriceAndDiscount, isTrue);
      expect(admin.canManagePaymentConfig, isTrue);
      expect(admin.canManageShifts, isTrue);
      expect(admin.canAdjustAttendance, isTrue);
      expect(admin.requiresAttendance, isFalse);
      expect(admin.name, equals('Quản trị viên'));
    });

    test('Supervisor account permissions', () {
      const supervisor = UserAccount(
        username: 'supervisor_user',
        displayName: 'Giám sát viên',
        role: 'supervisor',
        storeId: 'store_001',
      );

      expect(supervisor.isAdmin, isFalse);
      expect(supervisor.isSupervisor, isTrue);
      expect(supervisor.isStaff, isFalse);
      expect(supervisor.isAllStores, isFalse);
      expect(supervisor.canSwitchStore, isTrue);
      expect(supervisor.canManageUsers, isFalse);
      expect(supervisor.canViewDebtSummary, isTrue);
      expect(supervisor.canViewTotalSales, isTrue);
      expect(supervisor.canViewCostPrice, isTrue);
      expect(supervisor.canManageProducts, isTrue);
      expect(supervisor.canDeleteInvoice, isFalse);
      expect(supervisor.canDeleteCustomer, isFalse);
      expect(supervisor.canExportCustomers, isTrue);
      expect(supervisor.canChangeImportStore, isTrue);
      expect(supervisor.canChangeTransferSourceStore, isTrue);
      expect(supervisor.canEditPriceAndDiscount, isTrue);
      expect(supervisor.canManagePaymentConfig, isFalse);
      expect(supervisor.canManageShifts, isTrue);
      expect(supervisor.canAdjustAttendance, isTrue);
      expect(supervisor.requiresAttendance, isFalse);
      expect(supervisor.name, equals('Giám sát viên'));
    });

    test('Staff (nhanvien) account permissions', () {
      const staff = UserAccount(
        username: 'staff_user',
        displayName: 'Nhân viên bán hàng',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      expect(staff.isAdmin, isFalse);
      expect(staff.isSupervisor, isFalse);
      expect(staff.isStaff, isTrue);
      expect(staff.canSwitchStore, isFalse);
      expect(staff.canViewDebtSummary, isFalse);
      expect(staff.canViewTotalSales, isFalse);
      expect(staff.canViewCostPrice, isFalse);
      expect(staff.canManageProducts, isFalse);
      expect(staff.canDeleteInvoice, isFalse);
      expect(staff.canDeleteCustomer, isFalse);
      expect(staff.canExportCustomers, isFalse);
      expect(staff.canChangeImportStore, isFalse);
      expect(staff.canChangeTransferSourceStore, isFalse);
      expect(staff.canEditPriceAndDiscount, isFalse);
      expect(staff.canManagePaymentConfig, isFalse);
      expect(staff.canManageShifts, isFalse);
      expect(staff.canAdjustAttendance, isFalse);
      expect(staff.requiresAttendance, isTrue);
      expect(staff.name, equals('Nhân viên bán hàng'));
    });

    test('UserAccount serialization and fallback name', () {
      final map = {
        'role': 'nhanvien',
        'storeId': 'store_002',
      };
      final user = UserAccount.fromMap('user123', map);

      expect(user.username, equals('user123'));
      expect(user.displayName, isNull);
      expect(user.name, equals('user123'));
      expect(user.role, equals('nhanvien'));
      expect(user.storeId, equals('store_002'));
      expect(user.canViewDebtSummary, isFalse);

      final serialized = user.toMap();
      expect(serialized['role'], equals('nhanvien'));
      expect(serialized['storeId'], equals('store_002'));
      expect(serialized.containsKey('displayName'), isFalse);
    });
  });
}
