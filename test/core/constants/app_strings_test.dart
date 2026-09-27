import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/constants/app_strings.dart';

void main() {
  group('AppStrings System Constants Verification', () {
    test('App and company identity constants', () {
      expect(AppStrings.appName, 'KĐ Store');
      expect(AppStrings.companyName, 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG');
    });

    test('Store identifiers and branch names', () {
      expect(AppStrings.storeDongThangId, 'store_001');
      expect(AppStrings.storeDongThangName, 'Chi nhánh Đông Thắng');
      expect(AppStrings.storeDongThangShort, 'Đông Thắng');

      expect(AppStrings.storeThoiBinhId, 'store_002');
      expect(AppStrings.storeThoiBinhName, 'Chi nhánh Thới Bình');
      expect(AppStrings.storeThoiBinhShort, 'Thới Bình');

      expect(AppStrings.allStoresId, 'all');
      expect(AppStrings.allStoresName, 'Tất cả chi nhánh');
      expect(AppStrings.allStoresCombined, 'Toàn bộ chi nhánh (Toàn hệ thống)');
    });

    test('Currency and standard units', () {
      expect(AppStrings.currencySymbol, 'đ');
      expect(AppStrings.currencyCode, 'VND');
      expect(AppStrings.defaultUnit, 'Cái');
      expect(AppStrings.unitPiece, 'Cái');
      expect(AppStrings.unitSet, 'Bộ');
      expect(AppStrings.unitBox, 'Hộp');
      expect(AppStrings.unitKg, 'Kg');
      expect(AppStrings.unitMeter, 'Mét');
    });

    test('Payment methods and labels', () {
      expect(AppStrings.paymentMethodCash, 'cash');
      expect(AppStrings.paymentMethodTransfer, 'transfer');
      expect(AppStrings.paymentMethodCard, 'card');
      expect(AppStrings.paymentMethodDebt, 'debt');

      expect(AppStrings.paymentLabelCash, 'Tiền mặt');
      expect(AppStrings.paymentLabelTransfer, 'Chuyển khoản');
      expect(AppStrings.paymentLabelCard, 'Thẻ');
      expect(AppStrings.paymentLabelDebt, 'Tính vào công nợ');
    });

    test('Status codes and labels', () {
      expect(AppStrings.statusDraft, 'draft');
      expect(AppStrings.statusCompleted, 'completed');
      expect(AppStrings.statusCancelled, 'cancelled');
      expect(AppStrings.statusPending, 'pending');

      expect(AppStrings.statusDraftLabel, 'Phiếu tạm');
      expect(AppStrings.statusCompletedLabel, 'Đã hoàn thành');
      expect(AppStrings.statusCancelledLabel, 'Đã hủy');
    });

    test('Inventory transaction types', () {
      expect(AppStrings.transactionTypeImport, 'import');
      expect(AppStrings.transactionTypeExport, 'export');
      expect(AppStrings.transactionTypeTransfer, 'transfer');
      expect(AppStrings.transactionTypeAdjustment, 'adjustment');
      expect(AppStrings.transactionTypeReturn, 'return');
    });

    test('System and repository error messages', () {
      expect(AppStrings.errorGeneric, isNotEmpty);
      expect(AppStrings.errorNetwork, isNotEmpty);
      expect(AppStrings.errorDatabase, isNotEmpty);
      expect(AppStrings.errorUnauthorized, isNotEmpty);
      expect(AppStrings.errorInsufficientStock, isNotEmpty);
      expect(AppStrings.errorCannotDeleteCompletedReceipt, contains('hoàn trả tồn kho và công nợ'));
    });

    test('Ledger notes and note prefixes', () {
      expect(AppStrings.noteSupplierPayment, 'Thanh toán nợ nhà cung cấp');
      expect(AppStrings.noteSupplierAdjustment, 'Điều chỉnh công nợ nhà cung cấp');
      expect(AppStrings.noteStockInDebt, 'Nhập hàng phát sinh công nợ');
      expect(AppStrings.noteCustomerDebtAdjustment, 'Điều chỉnh công nợ khách hàng');
      expect(AppStrings.noteReturnOrder, 'Trả hàng đơn');
      expect(AppStrings.noteCancelStockIn, 'Hủy phiếu nhập kho');
    });

    test('Date format patterns and filter labels', () {
      expect(AppStrings.dateFormatPattern, 'dd/MM/yyyy');
      expect(AppStrings.dateTimeFormatPattern, 'dd/MM/yyyy HH:mm');
      expect(AppStrings.filterToday, 'Hôm nay');
      expect(AppStrings.filterThisMonth, 'Tháng này');
      expect(AppStrings.filterCustom, 'Tùy chỉnh');
    });
  });
}
