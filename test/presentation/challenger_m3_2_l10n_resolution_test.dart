import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/extensions/context_extensions.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/customers/pages/customer_debt_adjustment_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier([super.state]);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}



void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 3: BuildContext.l10n Empirical Resolution & Key Parity Stress Tests', () {
    testWidgets('1. All 349 keys in AppLocalizations resolve non-empty Strings in Vietnamese (vi)', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = context.l10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(l10n.accountConfirmNewPassword, isNotEmpty, reason: "accountConfirmNewPassword should not be empty in vi");
      expect(l10n.accountDeletedSuccess, isNotEmpty, reason: "accountDeletedSuccess should not be empty in vi");
      expect(l10n.accountManagement, isNotEmpty, reason: "accountManagement should not be empty in vi");
      expect(l10n.add, isNotEmpty, reason: "add should not be empty in vi");
      expect(l10n.addAccount, isNotEmpty, reason: "addAccount should not be empty in vi");
      expect(l10n.addAttributeTitle, isNotEmpty, reason: "addAttributeTitle should not be empty in vi");
      expect(l10n.addCustomerSuccess, isNotEmpty, reason: "addCustomerSuccess should not be empty in vi");
      expect(l10n.addFirstData, isNotEmpty, reason: "addFirstData should not be empty in vi");
      expect(l10n.addNewCustomer, isNotEmpty, reason: "addNewCustomer should not be empty in vi");
      expect(l10n.addProduct, isNotEmpty, reason: "addProduct should not be empty in vi");
      expect(l10n.addUnitTitle, isNotEmpty, reason: "addUnitTitle should not be empty in vi");
      expect(l10n.added, isNotEmpty, reason: "added should not be empty in vi");
      expect(l10n.address, isNotEmpty, reason: "address should not be empty in vi");
      expect(l10n.addressSection, isNotEmpty, reason: "addressSection should not be empty in vi");
      expect(l10n.adjustedDebtValue, isNotEmpty, reason: "adjustedDebtValue should not be empty in vi");
      expect(l10n.adjustment, isNotEmpty, reason: "adjustment should not be empty in vi");
      expect(l10n.adjustmentNoteDefault, isNotEmpty, reason: "adjustmentNoteDefault should not be empty in vi");
      expect(l10n.all, isNotEmpty, reason: "all should not be empty in vi");
      expect(l10n.allBranches, isNotEmpty, reason: "allBranches should not be empty in vi");
      expect(l10n.allBranchesCombined, isNotEmpty, reason: "allBranchesCombined should not be empty in vi");
      expect(l10n.allTime, isNotEmpty, reason: "allTime should not be empty in vi");
      expect(l10n.amount, isNotEmpty, reason: "amount should not be empty in vi");
      expect(l10n.amountPaid, isNotEmpty, reason: "amountPaid should not be empty in vi");
      expect(l10n.amountToPay, isNotEmpty, reason: "amountToPay should not be empty in vi");
      expect(l10n.and, isNotEmpty, reason: "and should not be empty in vi");
      expect(l10n.attendanceDashboard, isNotEmpty, reason: "attendanceDashboard should not be empty in vi");
      expect(l10n.attendanceEarlyLeave, isNotEmpty, reason: "attendanceEarlyLeave should not be empty in vi");
      expect(l10n.attendanceLateToday, isNotEmpty, reason: "attendanceLateToday should not be empty in vi");
      expect(l10n.attendanceNoDataMonth, isNotEmpty, reason: "attendanceNoDataMonth should not be empty in vi");
      expect(l10n.attendanceNoRecordsFilter, isNotEmpty, reason: "attendanceNoRecordsFilter should not be empty in vi");
      expect(l10n.attendanceNotArrived, isNotEmpty, reason: "attendanceNotArrived should not be empty in vi");
      expect(l10n.attendancePersonalTimesheet, isNotEmpty, reason: "attendancePersonalTimesheet should not be empty in vi");
      expect(l10n.attendanceTotalWorkHours, isNotEmpty, reason: "attendanceTotalWorkHours should not be empty in vi");
      expect(l10n.attendanceUpdateGpsSuccess, isNotEmpty, reason: "attendanceUpdateGpsSuccess should not be empty in vi");
      expect(l10n.attendanceWorking, isNotEmpty, reason: "attendanceWorking should not be empty in vi");
      expect(l10n.back, isNotEmpty, reason: "back should not be empty in vi");
      expect(l10n.barcodeScannerStarting, isNotEmpty, reason: "barcodeScannerStarting should not be empty in vi");
      expect(l10n.basicInfo, isNotEmpty, reason: "basicInfo should not be empty in vi");
      expect(l10n.branch, isNotEmpty, reason: "branch should not be empty in vi");
      expect(l10n.brand, isNotEmpty, reason: "brand should not be empty in vi");
      expect(l10n.buyerName, isNotEmpty, reason: "buyerName should not be empty in vi");
      expect(l10n.byQuantity, isNotEmpty, reason: "byQuantity should not be empty in vi");
      expect(l10n.byRevenue, isNotEmpty, reason: "byRevenue should not be empty in vi");
      expect(l10n.cancel, isNotEmpty, reason: "cancel should not be empty in vi");
      expect(l10n.cancelDraftOrder, isNotEmpty, reason: "cancelDraftOrder should not be empty in vi");
      expect(l10n.cash, isNotEmpty, reason: "cash should not be empty in vi");
      expect(l10n.category, isNotEmpty, reason: "category should not be empty in vi");
      expect(l10n.change, isNotEmpty, reason: "change should not be empty in vi");
      expect(l10n.changeDue, isNotEmpty, reason: "changeDue should not be empty in vi");
      expect(l10n.changePrice, isNotEmpty, reason: "changePrice should not be empty in vi");
      expect(l10n.checkProductsAndQuantity, isNotEmpty, reason: "checkProductsAndQuantity should not be empty in vi");
      expect(l10n.checkout, isNotEmpty, reason: "checkout should not be empty in vi");
      expect(l10n.close, isNotEmpty, reason: "close should not be empty in vi");
      expect(l10n.commonCancelled, isNotEmpty, reason: "commonCancelled should not be empty in vi");
      expect(l10n.commonCompleted, isNotEmpty, reason: "commonCompleted should not be empty in vi");
      expect(l10n.commonContinue, isNotEmpty, reason: "commonContinue should not be empty in vi");
      expect(l10n.commonCostPrice, isNotEmpty, reason: "commonCostPrice should not be empty in vi");
      expect(l10n.commonDone, isNotEmpty, reason: "commonDone should not be empty in vi");
      expect(l10n.commonDraftReceipt, isNotEmpty, reason: "commonDraftReceipt should not be empty in vi");
      expect(l10n.commonHasDebt, isNotEmpty, reason: "commonHasDebt should not be empty in vi");
      expect(l10n.commonInStock, isNotEmpty, reason: "commonInStock should not be empty in vi");
      expect(l10n.commonNoDebt, isNotEmpty, reason: "commonNoDebt should not be empty in vi");
      expect(l10n.commonOutOfStock, isNotEmpty, reason: "commonOutOfStock should not be empty in vi");
      expect(l10n.commonResetFilter, isNotEmpty, reason: "commonResetFilter should not be empty in vi");
      expect(l10n.commonSaveDraft, isNotEmpty, reason: "commonSaveDraft should not be empty in vi");
      expect(l10n.commonSupplier, isNotEmpty, reason: "commonSupplier should not be empty in vi");
      expect(l10n.commonTotalPaidAmount, isNotEmpty, reason: "commonTotalPaidAmount should not be empty in vi");
      expect(l10n.commonTotalSalesAmount, isNotEmpty, reason: "commonTotalSalesAmount should not be empty in vi");
      expect(l10n.companyName, isNotEmpty, reason: "companyName should not be empty in vi");
      expect(l10n.confirmCancelDraftOrder, isNotEmpty, reason: "confirmCancelDraftOrder should not be empty in vi");
      expect(l10n.confirmDeleteAccountTitle, isNotEmpty, reason: "confirmDeleteAccountTitle should not be empty in vi");
      expect(l10n.confirmLogout, isNotEmpty, reason: "confirmLogout should not be empty in vi");
      expect(l10n.confirmLogoutApp, isNotEmpty, reason: "confirmLogoutApp should not be empty in vi");
      expect(l10n.contactSection, isNotEmpty, reason: "contactSection should not be empty in vi");
      expect(l10n.continuePayment, isNotEmpty, reason: "continuePayment should not be empty in vi");
      expect(l10n.createOrder, isNotEmpty, reason: "createOrder should not be empty in vi");
      expect(l10n.createQr, isNotEmpty, reason: "createQr should not be empty in vi");
      expect(l10n.createReceipt, isNotEmpty, reason: "createReceipt should not be empty in vi");
      expect(l10n.createReceiptTitle, isNotEmpty, reason: "createReceiptTitle should not be empty in vi");
      expect(l10n.createdAt, isNotEmpty, reason: "createdAt should not be empty in vi");
      expect(l10n.createdBy, isNotEmpty, reason: "createdBy should not be empty in vi");
      expect(l10n.createdTime, isNotEmpty, reason: "createdTime should not be empty in vi");
      expect(l10n.currentDebt, isNotEmpty, reason: "currentDebt should not be empty in vi");
      expect(l10n.currentStock, isNotEmpty, reason: "currentStock should not be empty in vi");
      expect(l10n.customerCode, isNotEmpty, reason: "customerCode should not be empty in vi");
      expect(l10n.customerDebt, isNotEmpty, reason: "customerDebt should not be empty in vi");
      expect(l10n.customerDeleted, isNotEmpty, reason: "customerDeleted should not be empty in vi");
      expect(l10n.customerDetail, isNotEmpty, reason: "customerDetail should not be empty in vi");
      expect(l10n.customerGroupSection, isNotEmpty, reason: "customerGroupSection should not be empty in vi");
      expect(l10n.customerType, isNotEmpty, reason: "customerType should not be empty in vi");
      expect(l10n.customers, isNotEmpty, reason: "customers should not be empty in vi");
      expect(l10n.dailyReport, isNotEmpty, reason: "dailyReport should not be empty in vi");
      expect(l10n.dashboard, isNotEmpty, reason: "dashboard should not be empty in vi");
      expect(l10n.date, isNotEmpty, reason: "date should not be empty in vi");
      expect(l10n.days, isNotEmpty, reason: "days should not be empty in vi");
      expect(l10n.debtAdjustmentHint, isNotEmpty, reason: "debtAdjustmentHint should not be empty in vi");
      expect(l10n.debtAdjustmentNoteHint, isNotEmpty, reason: "debtAdjustmentNoteHint should not be empty in vi");
      expect(l10n.debtAdjustmentTitle, isNotEmpty, reason: "debtAdjustmentTitle should not be empty in vi");
      expect(l10n.debtToCollect, isNotEmpty, reason: "debtToCollect should not be empty in vi");
      expect(l10n.debtUpdateSuccess, isNotEmpty, reason: "debtUpdateSuccess should not be empty in vi");
      expect(l10n.delete, isNotEmpty, reason: "delete should not be empty in vi");
      expect(l10n.deleteCustomerTitle, isNotEmpty, reason: "deleteCustomerTitle should not be empty in vi");
      expect(l10n.displayNameHint, isNotEmpty, reason: "displayNameHint should not be empty in vi");
      expect(l10n.displayNameLabel, isNotEmpty, reason: "displayNameLabel should not be empty in vi");
      expect(l10n.doneBtn, isNotEmpty, reason: "doneBtn should not be empty in vi");
      expect(l10n.draft, isNotEmpty, reason: "draft should not be empty in vi");
      expect(l10n.draftDetail, isNotEmpty, reason: "draftDetail should not be empty in vi");
      expect(l10n.draftOrderCancelled, isNotEmpty, reason: "draftOrderCancelled should not be empty in vi");
      expect(l10n.draftSaved, isNotEmpty, reason: "draftSaved should not be empty in vi");
      expect(l10n.draftUnpaid, isNotEmpty, reason: "draftUnpaid should not be empty in vi");
      expect(l10n.edit, isNotEmpty, reason: "edit should not be empty in vi");
      expect(l10n.editAccount, isNotEmpty, reason: "editAccount should not be empty in vi");
      expect(l10n.editProduct, isNotEmpty, reason: "editProduct should not be empty in vi");
      expect(l10n.email, isNotEmpty, reason: "email should not be empty in vi");
      expect(l10n.enterQuantityHint, isNotEmpty, reason: "enterQuantityHint should not be empty in vi");
      expect(l10n.excelActions, isNotEmpty, reason: "excelActions should not be empty in vi");
      expect(l10n.expense, isNotEmpty, reason: "expense should not be empty in vi");
      expect(l10n.expiresOn, isNotEmpty, reason: "expiresOn should not be empty in vi");
      expect(l10n.export, isNotEmpty, reason: "export should not be empty in vi");
      expect(l10n.exportExcel, isNotEmpty, reason: "exportExcel should not be empty in vi");
      expect(l10n.exportSuccess, isNotEmpty, reason: "exportSuccess should not be empty in vi");
      expect(l10n.exportingStore, isNotEmpty, reason: "exportingStore should not be empty in vi");
      expect(l10n.filePickerError, isNotEmpty, reason: "filePickerError should not be empty in vi");
      expect(l10n.fullNameRequired, isNotEmpty, reason: "fullNameRequired should not be empty in vi");
      expect(l10n.import, isNotEmpty, reason: "import should not be empty in vi");
      expect(l10n.importDescription, isNotEmpty, reason: "importDescription should not be empty in vi");
      expect(l10n.importDetail, isNotEmpty, reason: "importDetail should not be empty in vi");
      expect(l10n.importError, isNotEmpty, reason: "importError should not be empty in vi");
      expect(l10n.importExcel, isNotEmpty, reason: "importExcel should not be empty in vi");
      expect(l10n.importPrice, isNotEmpty, reason: "importPrice should not be empty in vi");
      expect(l10n.importProduct, isNotEmpty, reason: "importProduct should not be empty in vi");
      expect(l10n.importSuccess, isNotEmpty, reason: "importSuccess should not be empty in vi");
      expect(l10n.importSummary, isNotEmpty, reason: "importSummary should not be empty in vi");
      expect(l10n.inStock, isNotEmpty, reason: "inStock should not be empty in vi");
      expect(l10n.individual, isNotEmpty, reason: "individual should not be empty in vi");
      expect(l10n.interest, isNotEmpty, reason: "interest should not be empty in vi");
      expect(l10n.invalidAmount, isNotEmpty, reason: "invalidAmount should not be empty in vi");
      expect(l10n.invalidDebtValue, isNotEmpty, reason: "invalidDebtValue should not be empty in vi");
      expect(l10n.inventoryAmount, isNotEmpty, reason: "inventoryAmount should not be empty in vi");
      expect(l10n.inventoryCancelReasonHint, isNotEmpty, reason: "inventoryCancelReasonHint should not be empty in vi");
      expect(l10n.inventoryCancelSuccess, isNotEmpty, reason: "inventoryCancelSuccess should not be empty in vi");
      expect(l10n.inventoryConfirmCancelTitle, isNotEmpty, reason: "inventoryConfirmCancelTitle should not be empty in vi");
      expect(l10n.inventoryConfirmExitMsg, isNotEmpty, reason: "inventoryConfirmExitMsg should not be empty in vi");
      expect(l10n.inventoryConfirmExitTitle, isNotEmpty, reason: "inventoryConfirmExitTitle should not be empty in vi");
      expect(l10n.inventoryCreateReceipt, isNotEmpty, reason: "inventoryCreateReceipt should not be empty in vi");
      expect(l10n.inventoryDeleteDraftSuccess, isNotEmpty, reason: "inventoryDeleteDraftSuccess should not be empty in vi");
      expect(l10n.inventoryDiscount, isNotEmpty, reason: "inventoryDiscount should not be empty in vi");
      expect(l10n.inventoryImportPrice, isNotEmpty, reason: "inventoryImportPrice should not be empty in vi");
      expect(l10n.inventoryLastImportPrice, isNotEmpty, reason: "inventoryLastImportPrice should not be empty in vi");
      expect(l10n.inventoryLeave, isNotEmpty, reason: "inventoryLeave should not be empty in vi");
      expect(l10n.inventoryReceiptCode, isNotEmpty, reason: "inventoryReceiptCode should not be empty in vi");
      expect(l10n.inventoryReceiptDetail, isNotEmpty, reason: "inventoryReceiptDetail should not be empty in vi");
      expect(l10n.inventoryReceiptHistory, isNotEmpty, reason: "inventoryReceiptHistory should not be empty in vi");
      expect(l10n.inventoryStay, isNotEmpty, reason: "inventoryStay should not be empty in vi");
      expect(l10n.inventoryTransactions, isNotEmpty, reason: "inventoryTransactions should not be empty in vi");
      expect(l10n.inventoryValue, isNotEmpty, reason: "inventoryValue should not be empty in vi");
      expect(l10n.invoice, isNotEmpty, reason: "invoice should not be empty in vi");
      expect(l10n.invoiceDetail, isNotEmpty, reason: "invoiceDetail should not be empty in vi");
      expect(l10n.invoiceId, isNotEmpty, reason: "invoiceId should not be empty in vi");
      expect(l10n.invoiceInfoSection, isNotEmpty, reason: "invoiceInfoSection should not be empty in vi");
      expect(l10n.invoicesTitle, isNotEmpty, reason: "invoicesTitle should not be empty in vi");
      expect(l10n.language, isNotEmpty, reason: "language should not be empty in vi");
      expect(l10n.loadingText, isNotEmpty, reason: "loadingText should not be empty in vi");
      expect(l10n.loans, isNotEmpty, reason: "loans should not be empty in vi");
      expect(l10n.loginTitle, isNotEmpty, reason: "loginTitle should not be empty in vi");
      expect(l10n.logout, isNotEmpty, reason: "logout should not be empty in vi");
      expect(l10n.logoutAccount, isNotEmpty, reason: "logoutAccount should not be empty in vi");
      expect(l10n.lowStock, isNotEmpty, reason: "lowStock should not be empty in vi");
      expect(l10n.model, isNotEmpty, reason: "model should not be empty in vi");
      expect(l10n.months, isNotEmpty, reason: "months should not be empty in vi");
      expect(l10n.more, isNotEmpty, reason: "more should not be empty in vi");
      expect(l10n.moreOptions, isNotEmpty, reason: "moreOptions should not be empty in vi");
      expect(l10n.name, isNotEmpty, reason: "name should not be empty in vi");
      expect(l10n.needRestock, isNotEmpty, reason: "needRestock should not be empty in vi");
      expect(l10n.newBrandTitle, isNotEmpty, reason: "newBrandTitle should not be empty in vi");
      expect(l10n.newCategoryTitle, isNotEmpty, reason: "newCategoryTitle should not be empty in vi");
      expect(l10n.newPrice, isNotEmpty, reason: "newPrice should not be empty in vi");
      expect(l10n.newProductTitle, isNotEmpty, reason: "newProductTitle should not be empty in vi");
      expect(l10n.no, isNotEmpty, reason: "no should not be empty in vi");
      expect(l10n.noAccountsFound, isNotEmpty, reason: "noAccountsFound should not be empty in vi");
      expect(l10n.noBrandFound, isNotEmpty, reason: "noBrandFound should not be empty in vi");
      expect(l10n.noCategoryFound, isNotEmpty, reason: "noCategoryFound should not be empty in vi");
      expect(l10n.noCustomerSelected, isNotEmpty, reason: "noCustomerSelected should not be empty in vi");
      expect(l10n.noCustomersFound, isNotEmpty, reason: "noCustomersFound should not be empty in vi");
      expect(l10n.noData, isNotEmpty, reason: "noData should not be empty in vi");
      expect(l10n.noDataToExport, isNotEmpty, reason: "noDataToExport should not be empty in vi");
      expect(l10n.noDebtData, isNotEmpty, reason: "noDebtData should not be empty in vi");
      expect(l10n.noInvoicesFound, isNotEmpty, reason: "noInvoicesFound should not be empty in vi");
      expect(l10n.noOtherStoreToTransfer, isNotEmpty, reason: "noOtherStoreToTransfer should not be empty in vi");
      expect(l10n.noPhone, isNotEmpty, reason: "noPhone should not be empty in vi");
      expect(l10n.noPhoneAvailable, isNotEmpty, reason: "noPhoneAvailable should not be empty in vi");
      expect(l10n.noProducts, isNotEmpty, reason: "noProducts should not be empty in vi");
      expect(l10n.noProductsFound, isNotEmpty, reason: "noProductsFound should not be empty in vi");
      expect(l10n.noPurchases, isNotEmpty, reason: "noPurchases should not be empty in vi");
      expect(l10n.noSalesData, isNotEmpty, reason: "noSalesData should not be empty in vi");
      expect(l10n.noTransactions, isNotEmpty, reason: "noTransactions should not be empty in vi");
      expect(l10n.noTransactionsYet, isNotEmpty, reason: "noTransactionsYet should not be empty in vi");
      expect(l10n.notCategorized, isNotEmpty, reason: "notCategorized should not be empty in vi");
      expect(l10n.notEnoughStock, isNotEmpty, reason: "notEnoughStock should not be empty in vi");
      expect(l10n.notFound, isNotEmpty, reason: "notFound should not be empty in vi");
      expect(l10n.notUpdated, isNotEmpty, reason: "notUpdated should not be empty in vi");
      expect(l10n.note, isNotEmpty, reason: "note should not be empty in vi");
      expect(l10n.numberOfProducts, isNotEmpty, reason: "numberOfProducts should not be empty in vi");
      expect(l10n.onlySupervisorCanAssignStore, isNotEmpty, reason: "onlySupervisorCanAssignStore should not be empty in vi");
      expect(l10n.onlySupervisorCanEditRole, isNotEmpty, reason: "onlySupervisorCanEditRole should not be empty in vi");
      expect(l10n.orderCreatedBy, isNotEmpty, reason: "orderCreatedBy should not be empty in vi");
      expect(l10n.orderDiscount, isNotEmpty, reason: "orderDiscount should not be empty in vi");
      expect(l10n.orderInfo, isNotEmpty, reason: "orderInfo should not be empty in vi");
      expect(l10n.orders, isNotEmpty, reason: "orders should not be empty in vi");
      expect(l10n.outOfStockAlert, isNotEmpty, reason: "outOfStockAlert should not be empty in vi");
      expect(l10n.outOfStockMsg, isNotEmpty, reason: "outOfStockMsg should not be empty in vi");
      expect(l10n.overview, isNotEmpty, reason: "overview should not be empty in vi");
      expect(l10n.paid, isNotEmpty, reason: "paid should not be empty in vi");
      expect(l10n.parentCategoryLabel, isNotEmpty, reason: "parentCategoryLabel should not be empty in vi");
      expect(l10n.passwordLabel, isNotEmpty, reason: "passwordLabel should not be empty in vi");
      expect(l10n.payment, isNotEmpty, reason: "payment should not be empty in vi");
      expect(l10n.paymentMethod, isNotEmpty, reason: "paymentMethod should not be empty in vi");
      expect(l10n.paymentMethodTransfer, isNotEmpty, reason: "paymentMethodTransfer should not be empty in vi");
      expect(l10n.paymentNoteDefault, isNotEmpty, reason: "paymentNoteDefault should not be empty in vi");
      expect(l10n.paymentSuccess, isNotEmpty, reason: "paymentSuccess should not be empty in vi");
      expect(l10n.performedBy, isNotEmpty, reason: "performedBy should not be empty in vi");
      expect(l10n.phone, isNotEmpty, reason: "phone should not be empty in vi");
      expect(l10n.phoneNumberRequired, isNotEmpty, reason: "phoneNumberRequired should not be empty in vi");
      expect(l10n.pickImageFromGallery, isNotEmpty, reason: "pickImageFromGallery should not be empty in vi");
      expect(l10n.pleaseEnter, isNotEmpty, reason: "pleaseEnter should not be empty in vi");
      expect(l10n.pleaseEnterAdjustedDebt, isNotEmpty, reason: "pleaseEnterAdjustedDebt should not be empty in vi");
      expect(l10n.pleaseEnterCredentials, isNotEmpty, reason: "pleaseEnterCredentials should not be empty in vi");
      expect(l10n.pleaseEnterEmail, isNotEmpty, reason: "pleaseEnterEmail should not be empty in vi");
      expect(l10n.pleaseEnterName, isNotEmpty, reason: "pleaseEnterName should not be empty in vi");
      expect(l10n.pleaseEnterValidEmail, isNotEmpty, reason: "pleaseEnterValidEmail should not be empty in vi");
      expect(l10n.pleaseEnterValidNumber, isNotEmpty, reason: "pleaseEnterValidNumber should not be empty in vi");
      expect(l10n.pleaseFillAllField, isNotEmpty, reason: "pleaseFillAllField should not be empty in vi");
      expect(l10n.pleaseSelectDateRange, isNotEmpty, reason: "pleaseSelectDateRange should not be empty in vi");
      expect(l10n.price, isNotEmpty, reason: "price should not be empty in vi");
      expect(l10n.productAdded, isNotEmpty, reason: "productAdded should not be empty in vi");
      expect(l10n.productCode, isNotEmpty, reason: "productCode should not be empty in vi");
      expect(l10n.productDetail, isNotEmpty, reason: "productDetail should not be empty in vi");
      expect(l10n.productId, isNotEmpty, reason: "productId should not be empty in vi");
      expect(l10n.productList, isNotEmpty, reason: "productList should not be empty in vi");
      expect(l10n.productName, isNotEmpty, reason: "productName should not be empty in vi");
      expect(l10n.productNotFoundInSystem, isNotEmpty, reason: "productNotFoundInSystem should not be empty in vi");
      expect(l10n.products, isNotEmpty, reason: "products should not be empty in vi");
      expect(l10n.profit, isNotEmpty, reason: "profit should not be empty in vi");
      expect(l10n.purchaseHistory, isNotEmpty, reason: "purchaseHistory should not be empty in vi");
      expect(l10n.purchasedOn, isNotEmpty, reason: "purchasedOn should not be empty in vi");
      expect(l10n.purchases, isNotEmpty, reason: "purchases should not be empty in vi");
      expect(l10n.qrTitle, isNotEmpty, reason: "qrTitle should not be empty in vi");
      expect(l10n.quantity, isNotEmpty, reason: "quantity should not be empty in vi");
      expect(l10n.receiptAmount, isNotEmpty, reason: "receiptAmount should not be empty in vi");
      expect(l10n.reports, isNotEmpty, reason: "reports should not be empty in vi");
      expect(l10n.retailCustomer, isNotEmpty, reason: "retailCustomer should not be empty in vi");
      expect(l10n.retry, isNotEmpty, reason: "retry should not be empty in vi");
      expect(l10n.returnsCountLabel, isNotEmpty, reason: "returnsCountLabel should not be empty in vi");
      expect(l10n.revenue, isNotEmpty, reason: "revenue should not be empty in vi");
      expect(l10n.revenueByProduct, isNotEmpty, reason: "revenueByProduct should not be empty in vi");
      expect(l10n.revenueSummary, isNotEmpty, reason: "revenueSummary should not be empty in vi");
      expect(l10n.roleAdmin, isNotEmpty, reason: "roleAdmin should not be empty in vi");
      expect(l10n.roleStaff, isNotEmpty, reason: "roleStaff should not be empty in vi");
      expect(l10n.roleSupervisor, isNotEmpty, reason: "roleSupervisor should not be empty in vi");
      expect(l10n.salesTitle, isNotEmpty, reason: "salesTitle should not be empty in vi");
      expect(l10n.save, isNotEmpty, reason: "save should not be empty in vi");
      expect(l10n.saveDraft, isNotEmpty, reason: "saveDraft should not be empty in vi");
      expect(l10n.saveDraftConfirm, isNotEmpty, reason: "saveDraftConfirm should not be empty in vi");
      expect(l10n.saveDraftTitle, isNotEmpty, reason: "saveDraftTitle should not be empty in vi");
      expect(l10n.saveReceipt, isNotEmpty, reason: "saveReceipt should not be empty in vi");
      expect(l10n.searchCustomersHint, isNotEmpty, reason: "searchCustomersHint should not be empty in vi");
      expect(l10n.searchInvoicesHint, isNotEmpty, reason: "searchInvoicesHint should not be empty in vi");
      expect(l10n.searchPOSHint, isNotEmpty, reason: "searchPOSHint should not be empty in vi");
      expect(l10n.searchProducts, isNotEmpty, reason: "searchProducts should not be empty in vi");
      expect(l10n.searchProductsHint, isNotEmpty, reason: "searchProductsHint should not be empty in vi");
      expect(l10n.selectAll, isNotEmpty, reason: "selectAll should not be empty in vi");
      expect(l10n.selectBranch, isNotEmpty, reason: "selectBranch should not be empty in vi");
      expect(l10n.selectCategoryTitle, isNotEmpty, reason: "selectCategoryTitle should not be empty in vi");
      expect(l10n.selectCustomer, isNotEmpty, reason: "selectCustomer should not be empty in vi");
      expect(l10n.selectDate, isNotEmpty, reason: "selectDate should not be empty in vi");
      expect(l10n.selectDateRange, isNotEmpty, reason: "selectDateRange should not be empty in vi");
      expect(l10n.selectTargetStore, isNotEmpty, reason: "selectTargetStore should not be empty in vi");
      expect(l10n.settingsTitle, isNotEmpty, reason: "settingsTitle should not be empty in vi");
      expect(l10n.shipping, isNotEmpty, reason: "shipping should not be empty in vi");
      expect(l10n.staff, isNotEmpty, reason: "staff should not be empty in vi");
      expect(l10n.status, isNotEmpty, reason: "status should not be empty in vi");
      expect(l10n.stock, isNotEmpty, reason: "stock should not be empty in vi");
      expect(l10n.stockAfterImport, isNotEmpty, reason: "stockAfterImport should not be empty in vi");
      expect(l10n.stockLabel, isNotEmpty, reason: "stockLabel should not be empty in vi");
      expect(l10n.store, isNotEmpty, reason: "store should not be empty in vi");
      expect(l10n.takeNewPhoto, isNotEmpty, reason: "takeNewPhoto should not be empty in vi");
      expect(l10n.targetStore, isNotEmpty, reason: "targetStore should not be empty in vi");
      expect(l10n.taxAndAccounting, isNotEmpty, reason: "taxAndAccounting should not be empty in vi");
      expect(l10n.taxCode, isNotEmpty, reason: "taxCode should not be empty in vi");
      expect(l10n.timeRange, isNotEmpty, reason: "timeRange should not be empty in vi");
      expect(l10n.title, isNotEmpty, reason: "title should not be empty in vi");
      expect(l10n.topSelling, isNotEmpty, reason: "topSelling should not be empty in vi");
      expect(l10n.totalAmount, isNotEmpty, reason: "totalAmount should not be empty in vi");
      expect(l10n.totalExpense, isNotEmpty, reason: "totalExpense should not be empty in vi");
      expect(l10n.totalOrders, isNotEmpty, reason: "totalOrders should not be empty in vi");
      expect(l10n.totalPaymentAmount, isNotEmpty, reason: "totalPaymentAmount should not be empty in vi");
      expect(l10n.totalProductAmount, isNotEmpty, reason: "totalProductAmount should not be empty in vi");
      expect(l10n.totalProfit, isNotEmpty, reason: "totalProfit should not be empty in vi");
      expect(l10n.totalQuantity, isNotEmpty, reason: "totalQuantity should not be empty in vi");
      expect(l10n.totalRevenue, isNotEmpty, reason: "totalRevenue should not be empty in vi");
      expect(l10n.totalSales, isNotEmpty, reason: "totalSales should not be empty in vi");
      expect(l10n.totalSalesAndReturns, isNotEmpty, reason: "totalSalesAndReturns should not be empty in vi");
      expect(l10n.totalValue, isNotEmpty, reason: "totalValue should not be empty in vi");
      expect(l10n.transactionHistory, isNotEmpty, reason: "transactionHistory should not be empty in vi");
      expect(l10n.transactions, isNotEmpty, reason: "transactions should not be empty in vi");
      expect(l10n.transfer, isNotEmpty, reason: "transfer should not be empty in vi");
      expect(l10n.transferCompleted, isNotEmpty, reason: "transferCompleted should not be empty in vi");
      expect(l10n.transferDetails, isNotEmpty, reason: "transferDetails should not be empty in vi");
      expect(l10n.transferProduct, isNotEmpty, reason: "transferProduct should not be empty in vi");
      expect(l10n.transferQuantity, isNotEmpty, reason: "transferQuantity should not be empty in vi");
      expect(l10n.tryAdjustingSearch, isNotEmpty, reason: "tryAdjustingSearch should not be empty in vi");
      expect(l10n.unitPrice, isNotEmpty, reason: "unitPrice should not be empty in vi");
      expect(l10n.unknownStore, isNotEmpty, reason: "unknownStore should not be empty in vi");
      expect(l10n.update, isNotEmpty, reason: "update should not be empty in vi");
      expect(l10n.updated, isNotEmpty, reason: "updated should not be empty in vi");
      expect(l10n.usernameLabel, isNotEmpty, reason: "usernameLabel should not be empty in vi");
      expect(l10n.walkInCustomerDebtNotAllowed, isNotEmpty, reason: "walkInCustomerDebtNotAllowed should not be empty in vi");
      expect(l10n.wantToDelete, isNotEmpty, reason: "wantToDelete should not be empty in vi");
      expect(l10n.warranty, isNotEmpty, reason: "warranty should not be empty in vi");
      expect(l10n.warrantyActive, isNotEmpty, reason: "warrantyActive should not be empty in vi");
      expect(l10n.warrantyExpired, isNotEmpty, reason: "warrantyExpired should not be empty in vi");
      expect(l10n.warrantyExpiresIn, isNotEmpty, reason: "warrantyExpiresIn should not be empty in vi");
      expect(l10n.warrantyPeriod, isNotEmpty, reason: "warrantyPeriod should not be empty in vi");
      expect(l10n.warrantyStatus, isNotEmpty, reason: "warrantyStatus should not be empty in vi");
      expect(l10n.accountDeleteConfirm('TEST_VALUE'), isNotEmpty, reason: "accountDeleteConfirm should not be empty in vi");
      expect(l10n.amountToPayLabel('TEST_VALUE'), isNotEmpty, reason: "amountToPayLabel should not be empty in vi");
      expect(l10n.attendanceDeleteShiftConfirm('TEST_VALUE'), isNotEmpty, reason: "attendanceDeleteShiftConfirm should not be empty in vi");
      expect(l10n.cannotCall('TEST_VALUE'), isNotEmpty, reason: "cannotCall should not be empty in vi");
      expect(l10n.cannotSms('TEST_VALUE'), isNotEmpty, reason: "cannotSms should not be empty in vi");
      expect(l10n.cartSummaryTitle(5), isNotEmpty, reason: "cartSummaryTitle should not be empty in vi");
      expect(l10n.copyCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyCodeSuccess should not be empty in vi");
      expect(l10n.copyCustomerCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyCustomerCodeSuccess should not be empty in vi");
      expect(l10n.copyInvoiceCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyInvoiceCodeSuccess should not be empty in vi");
      expect(l10n.copyPhoneSuccess('TEST_VALUE'), isNotEmpty, reason: "copyPhoneSuccess should not be empty in vi");
      expect(l10n.createdTimeLabel('TEST_VALUE'), isNotEmpty, reason: "createdTimeLabel should not be empty in vi");
      expect(l10n.deleteCustomerConfirm('TEST_VALUE'), isNotEmpty, reason: "deleteCustomerConfirm should not be empty in vi");
      expect(l10n.goodsCount(5), isNotEmpty, reason: "goodsCount should not be empty in vi");
      expect(l10n.inventoryLoadError('TEST_VALUE'), isNotEmpty, reason: "inventoryLoadError should not be empty in vi");
      expect(l10n.invoiceCountLabel(5), isNotEmpty, reason: "invoiceCountLabel should not be empty in vi");
      expect(l10n.orderIdLabel('TEST_VALUE'), isNotEmpty, reason: "orderIdLabel should not be empty in vi");
      expect(l10n.ordersCount(5), isNotEmpty, reason: "ordersCount should not be empty in vi");
      expect(l10n.receiptCreatedSuccess('TEST_VALUE'), isNotEmpty, reason: "receiptCreatedSuccess should not be empty in vi");
      expect(l10n.remainingDebtLabel('TEST_VALUE'), isNotEmpty, reason: "remainingDebtLabel should not be empty in vi");
      expect(l10n.soldQty(5), isNotEmpty, reason: "soldQty should not be empty in vi");
      expect(l10n.stockLimitAlert(5), isNotEmpty, reason: "stockLimitAlert should not be empty in vi");
      expect(l10n.totalCustomers(5), isNotEmpty, reason: "totalCustomers should not be empty in vi");
      expect(l10n.totalInvoices(5), isNotEmpty, reason: "totalInvoices should not be empty in vi");
      expect(l10n.totalProducts(5), isNotEmpty, reason: "totalProducts should not be empty in vi");
      expect(l10n.totalStockCount(5), isNotEmpty, reason: "totalStockCount should not be empty in vi");
    });

    testWidgets('2. All 349 keys in AppLocalizations resolve non-empty Strings in English (en)', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = context.l10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(l10n.accountConfirmNewPassword, isNotEmpty, reason: "accountConfirmNewPassword should not be empty in en");
      expect(l10n.accountDeletedSuccess, isNotEmpty, reason: "accountDeletedSuccess should not be empty in en");
      expect(l10n.accountManagement, isNotEmpty, reason: "accountManagement should not be empty in en");
      expect(l10n.add, isNotEmpty, reason: "add should not be empty in en");
      expect(l10n.addAccount, isNotEmpty, reason: "addAccount should not be empty in en");
      expect(l10n.addAttributeTitle, isNotEmpty, reason: "addAttributeTitle should not be empty in en");
      expect(l10n.addCustomerSuccess, isNotEmpty, reason: "addCustomerSuccess should not be empty in en");
      expect(l10n.addFirstData, isNotEmpty, reason: "addFirstData should not be empty in en");
      expect(l10n.addNewCustomer, isNotEmpty, reason: "addNewCustomer should not be empty in en");
      expect(l10n.addProduct, isNotEmpty, reason: "addProduct should not be empty in en");
      expect(l10n.addUnitTitle, isNotEmpty, reason: "addUnitTitle should not be empty in en");
      expect(l10n.added, isNotEmpty, reason: "added should not be empty in en");
      expect(l10n.address, isNotEmpty, reason: "address should not be empty in en");
      expect(l10n.addressSection, isNotEmpty, reason: "addressSection should not be empty in en");
      expect(l10n.adjustedDebtValue, isNotEmpty, reason: "adjustedDebtValue should not be empty in en");
      expect(l10n.adjustment, isNotEmpty, reason: "adjustment should not be empty in en");
      expect(l10n.adjustmentNoteDefault, isNotEmpty, reason: "adjustmentNoteDefault should not be empty in en");
      expect(l10n.all, isNotEmpty, reason: "all should not be empty in en");
      expect(l10n.allBranches, isNotEmpty, reason: "allBranches should not be empty in en");
      expect(l10n.allBranchesCombined, isNotEmpty, reason: "allBranchesCombined should not be empty in en");
      expect(l10n.allTime, isNotEmpty, reason: "allTime should not be empty in en");
      expect(l10n.amount, isNotEmpty, reason: "amount should not be empty in en");
      expect(l10n.amountPaid, isNotEmpty, reason: "amountPaid should not be empty in en");
      expect(l10n.amountToPay, isNotEmpty, reason: "amountToPay should not be empty in en");
      expect(l10n.and, isNotEmpty, reason: "and should not be empty in en");
      expect(l10n.attendanceDashboard, isNotEmpty, reason: "attendanceDashboard should not be empty in en");
      expect(l10n.attendanceEarlyLeave, isNotEmpty, reason: "attendanceEarlyLeave should not be empty in en");
      expect(l10n.attendanceLateToday, isNotEmpty, reason: "attendanceLateToday should not be empty in en");
      expect(l10n.attendanceNoDataMonth, isNotEmpty, reason: "attendanceNoDataMonth should not be empty in en");
      expect(l10n.attendanceNoRecordsFilter, isNotEmpty, reason: "attendanceNoRecordsFilter should not be empty in en");
      expect(l10n.attendanceNotArrived, isNotEmpty, reason: "attendanceNotArrived should not be empty in en");
      expect(l10n.attendancePersonalTimesheet, isNotEmpty, reason: "attendancePersonalTimesheet should not be empty in en");
      expect(l10n.attendanceTotalWorkHours, isNotEmpty, reason: "attendanceTotalWorkHours should not be empty in en");
      expect(l10n.attendanceUpdateGpsSuccess, isNotEmpty, reason: "attendanceUpdateGpsSuccess should not be empty in en");
      expect(l10n.attendanceWorking, isNotEmpty, reason: "attendanceWorking should not be empty in en");
      expect(l10n.back, isNotEmpty, reason: "back should not be empty in en");
      expect(l10n.barcodeScannerStarting, isNotEmpty, reason: "barcodeScannerStarting should not be empty in en");
      expect(l10n.basicInfo, isNotEmpty, reason: "basicInfo should not be empty in en");
      expect(l10n.branch, isNotEmpty, reason: "branch should not be empty in en");
      expect(l10n.brand, isNotEmpty, reason: "brand should not be empty in en");
      expect(l10n.buyerName, isNotEmpty, reason: "buyerName should not be empty in en");
      expect(l10n.byQuantity, isNotEmpty, reason: "byQuantity should not be empty in en");
      expect(l10n.byRevenue, isNotEmpty, reason: "byRevenue should not be empty in en");
      expect(l10n.cancel, isNotEmpty, reason: "cancel should not be empty in en");
      expect(l10n.cancelDraftOrder, isNotEmpty, reason: "cancelDraftOrder should not be empty in en");
      expect(l10n.cash, isNotEmpty, reason: "cash should not be empty in en");
      expect(l10n.category, isNotEmpty, reason: "category should not be empty in en");
      expect(l10n.change, isNotEmpty, reason: "change should not be empty in en");
      expect(l10n.changeDue, isNotEmpty, reason: "changeDue should not be empty in en");
      expect(l10n.changePrice, isNotEmpty, reason: "changePrice should not be empty in en");
      expect(l10n.checkProductsAndQuantity, isNotEmpty, reason: "checkProductsAndQuantity should not be empty in en");
      expect(l10n.checkout, isNotEmpty, reason: "checkout should not be empty in en");
      expect(l10n.close, isNotEmpty, reason: "close should not be empty in en");
      expect(l10n.commonCancelled, isNotEmpty, reason: "commonCancelled should not be empty in en");
      expect(l10n.commonCompleted, isNotEmpty, reason: "commonCompleted should not be empty in en");
      expect(l10n.commonContinue, isNotEmpty, reason: "commonContinue should not be empty in en");
      expect(l10n.commonCostPrice, isNotEmpty, reason: "commonCostPrice should not be empty in en");
      expect(l10n.commonDone, isNotEmpty, reason: "commonDone should not be empty in en");
      expect(l10n.commonDraftReceipt, isNotEmpty, reason: "commonDraftReceipt should not be empty in en");
      expect(l10n.commonHasDebt, isNotEmpty, reason: "commonHasDebt should not be empty in en");
      expect(l10n.commonInStock, isNotEmpty, reason: "commonInStock should not be empty in en");
      expect(l10n.commonNoDebt, isNotEmpty, reason: "commonNoDebt should not be empty in en");
      expect(l10n.commonOutOfStock, isNotEmpty, reason: "commonOutOfStock should not be empty in en");
      expect(l10n.commonResetFilter, isNotEmpty, reason: "commonResetFilter should not be empty in en");
      expect(l10n.commonSaveDraft, isNotEmpty, reason: "commonSaveDraft should not be empty in en");
      expect(l10n.commonSupplier, isNotEmpty, reason: "commonSupplier should not be empty in en");
      expect(l10n.commonTotalPaidAmount, isNotEmpty, reason: "commonTotalPaidAmount should not be empty in en");
      expect(l10n.commonTotalSalesAmount, isNotEmpty, reason: "commonTotalSalesAmount should not be empty in en");
      expect(l10n.companyName, isNotEmpty, reason: "companyName should not be empty in en");
      expect(l10n.confirmCancelDraftOrder, isNotEmpty, reason: "confirmCancelDraftOrder should not be empty in en");
      expect(l10n.confirmDeleteAccountTitle, isNotEmpty, reason: "confirmDeleteAccountTitle should not be empty in en");
      expect(l10n.confirmLogout, isNotEmpty, reason: "confirmLogout should not be empty in en");
      expect(l10n.confirmLogoutApp, isNotEmpty, reason: "confirmLogoutApp should not be empty in en");
      expect(l10n.contactSection, isNotEmpty, reason: "contactSection should not be empty in en");
      expect(l10n.continuePayment, isNotEmpty, reason: "continuePayment should not be empty in en");
      expect(l10n.createOrder, isNotEmpty, reason: "createOrder should not be empty in en");
      expect(l10n.createQr, isNotEmpty, reason: "createQr should not be empty in en");
      expect(l10n.createReceipt, isNotEmpty, reason: "createReceipt should not be empty in en");
      expect(l10n.createReceiptTitle, isNotEmpty, reason: "createReceiptTitle should not be empty in en");
      expect(l10n.createdAt, isNotEmpty, reason: "createdAt should not be empty in en");
      expect(l10n.createdBy, isNotEmpty, reason: "createdBy should not be empty in en");
      expect(l10n.createdTime, isNotEmpty, reason: "createdTime should not be empty in en");
      expect(l10n.currentDebt, isNotEmpty, reason: "currentDebt should not be empty in en");
      expect(l10n.currentStock, isNotEmpty, reason: "currentStock should not be empty in en");
      expect(l10n.customerCode, isNotEmpty, reason: "customerCode should not be empty in en");
      expect(l10n.customerDebt, isNotEmpty, reason: "customerDebt should not be empty in en");
      expect(l10n.customerDeleted, isNotEmpty, reason: "customerDeleted should not be empty in en");
      expect(l10n.customerDetail, isNotEmpty, reason: "customerDetail should not be empty in en");
      expect(l10n.customerGroupSection, isNotEmpty, reason: "customerGroupSection should not be empty in en");
      expect(l10n.customerType, isNotEmpty, reason: "customerType should not be empty in en");
      expect(l10n.customers, isNotEmpty, reason: "customers should not be empty in en");
      expect(l10n.dailyReport, isNotEmpty, reason: "dailyReport should not be empty in en");
      expect(l10n.dashboard, isNotEmpty, reason: "dashboard should not be empty in en");
      expect(l10n.date, isNotEmpty, reason: "date should not be empty in en");
      expect(l10n.days, isNotEmpty, reason: "days should not be empty in en");
      expect(l10n.debtAdjustmentHint, isNotEmpty, reason: "debtAdjustmentHint should not be empty in en");
      expect(l10n.debtAdjustmentNoteHint, isNotEmpty, reason: "debtAdjustmentNoteHint should not be empty in en");
      expect(l10n.debtAdjustmentTitle, isNotEmpty, reason: "debtAdjustmentTitle should not be empty in en");
      expect(l10n.debtToCollect, isNotEmpty, reason: "debtToCollect should not be empty in en");
      expect(l10n.debtUpdateSuccess, isNotEmpty, reason: "debtUpdateSuccess should not be empty in en");
      expect(l10n.delete, isNotEmpty, reason: "delete should not be empty in en");
      expect(l10n.deleteCustomerTitle, isNotEmpty, reason: "deleteCustomerTitle should not be empty in en");
      expect(l10n.displayNameHint, isNotEmpty, reason: "displayNameHint should not be empty in en");
      expect(l10n.displayNameLabel, isNotEmpty, reason: "displayNameLabel should not be empty in en");
      expect(l10n.doneBtn, isNotEmpty, reason: "doneBtn should not be empty in en");
      expect(l10n.draft, isNotEmpty, reason: "draft should not be empty in en");
      expect(l10n.draftDetail, isNotEmpty, reason: "draftDetail should not be empty in en");
      expect(l10n.draftOrderCancelled, isNotEmpty, reason: "draftOrderCancelled should not be empty in en");
      expect(l10n.draftSaved, isNotEmpty, reason: "draftSaved should not be empty in en");
      expect(l10n.draftUnpaid, isNotEmpty, reason: "draftUnpaid should not be empty in en");
      expect(l10n.edit, isNotEmpty, reason: "edit should not be empty in en");
      expect(l10n.editAccount, isNotEmpty, reason: "editAccount should not be empty in en");
      expect(l10n.editProduct, isNotEmpty, reason: "editProduct should not be empty in en");
      expect(l10n.email, isNotEmpty, reason: "email should not be empty in en");
      expect(l10n.enterQuantityHint, isNotEmpty, reason: "enterQuantityHint should not be empty in en");
      expect(l10n.excelActions, isNotEmpty, reason: "excelActions should not be empty in en");
      expect(l10n.expense, isNotEmpty, reason: "expense should not be empty in en");
      expect(l10n.expiresOn, isNotEmpty, reason: "expiresOn should not be empty in en");
      expect(l10n.export, isNotEmpty, reason: "export should not be empty in en");
      expect(l10n.exportExcel, isNotEmpty, reason: "exportExcel should not be empty in en");
      expect(l10n.exportSuccess, isNotEmpty, reason: "exportSuccess should not be empty in en");
      expect(l10n.exportingStore, isNotEmpty, reason: "exportingStore should not be empty in en");
      expect(l10n.filePickerError, isNotEmpty, reason: "filePickerError should not be empty in en");
      expect(l10n.fullNameRequired, isNotEmpty, reason: "fullNameRequired should not be empty in en");
      expect(l10n.import, isNotEmpty, reason: "import should not be empty in en");
      expect(l10n.importDescription, isNotEmpty, reason: "importDescription should not be empty in en");
      expect(l10n.importDetail, isNotEmpty, reason: "importDetail should not be empty in en");
      expect(l10n.importError, isNotEmpty, reason: "importError should not be empty in en");
      expect(l10n.importExcel, isNotEmpty, reason: "importExcel should not be empty in en");
      expect(l10n.importPrice, isNotEmpty, reason: "importPrice should not be empty in en");
      expect(l10n.importProduct, isNotEmpty, reason: "importProduct should not be empty in en");
      expect(l10n.importSuccess, isNotEmpty, reason: "importSuccess should not be empty in en");
      expect(l10n.importSummary, isNotEmpty, reason: "importSummary should not be empty in en");
      expect(l10n.inStock, isNotEmpty, reason: "inStock should not be empty in en");
      expect(l10n.individual, isNotEmpty, reason: "individual should not be empty in en");
      expect(l10n.interest, isNotEmpty, reason: "interest should not be empty in en");
      expect(l10n.invalidAmount, isNotEmpty, reason: "invalidAmount should not be empty in en");
      expect(l10n.invalidDebtValue, isNotEmpty, reason: "invalidDebtValue should not be empty in en");
      expect(l10n.inventoryAmount, isNotEmpty, reason: "inventoryAmount should not be empty in en");
      expect(l10n.inventoryCancelReasonHint, isNotEmpty, reason: "inventoryCancelReasonHint should not be empty in en");
      expect(l10n.inventoryCancelSuccess, isNotEmpty, reason: "inventoryCancelSuccess should not be empty in en");
      expect(l10n.inventoryConfirmCancelTitle, isNotEmpty, reason: "inventoryConfirmCancelTitle should not be empty in en");
      expect(l10n.inventoryConfirmExitMsg, isNotEmpty, reason: "inventoryConfirmExitMsg should not be empty in en");
      expect(l10n.inventoryConfirmExitTitle, isNotEmpty, reason: "inventoryConfirmExitTitle should not be empty in en");
      expect(l10n.inventoryCreateReceipt, isNotEmpty, reason: "inventoryCreateReceipt should not be empty in en");
      expect(l10n.inventoryDeleteDraftSuccess, isNotEmpty, reason: "inventoryDeleteDraftSuccess should not be empty in en");
      expect(l10n.inventoryDiscount, isNotEmpty, reason: "inventoryDiscount should not be empty in en");
      expect(l10n.inventoryImportPrice, isNotEmpty, reason: "inventoryImportPrice should not be empty in en");
      expect(l10n.inventoryLastImportPrice, isNotEmpty, reason: "inventoryLastImportPrice should not be empty in en");
      expect(l10n.inventoryLeave, isNotEmpty, reason: "inventoryLeave should not be empty in en");
      expect(l10n.inventoryReceiptCode, isNotEmpty, reason: "inventoryReceiptCode should not be empty in en");
      expect(l10n.inventoryReceiptDetail, isNotEmpty, reason: "inventoryReceiptDetail should not be empty in en");
      expect(l10n.inventoryReceiptHistory, isNotEmpty, reason: "inventoryReceiptHistory should not be empty in en");
      expect(l10n.inventoryStay, isNotEmpty, reason: "inventoryStay should not be empty in en");
      expect(l10n.inventoryTransactions, isNotEmpty, reason: "inventoryTransactions should not be empty in en");
      expect(l10n.inventoryValue, isNotEmpty, reason: "inventoryValue should not be empty in en");
      expect(l10n.invoice, isNotEmpty, reason: "invoice should not be empty in en");
      expect(l10n.invoiceDetail, isNotEmpty, reason: "invoiceDetail should not be empty in en");
      expect(l10n.invoiceId, isNotEmpty, reason: "invoiceId should not be empty in en");
      expect(l10n.invoiceInfoSection, isNotEmpty, reason: "invoiceInfoSection should not be empty in en");
      expect(l10n.invoicesTitle, isNotEmpty, reason: "invoicesTitle should not be empty in en");
      expect(l10n.language, isNotEmpty, reason: "language should not be empty in en");
      expect(l10n.loadingText, isNotEmpty, reason: "loadingText should not be empty in en");
      expect(l10n.loans, isNotEmpty, reason: "loans should not be empty in en");
      expect(l10n.loginTitle, isNotEmpty, reason: "loginTitle should not be empty in en");
      expect(l10n.logout, isNotEmpty, reason: "logout should not be empty in en");
      expect(l10n.logoutAccount, isNotEmpty, reason: "logoutAccount should not be empty in en");
      expect(l10n.lowStock, isNotEmpty, reason: "lowStock should not be empty in en");
      expect(l10n.model, isNotEmpty, reason: "model should not be empty in en");
      expect(l10n.months, isNotEmpty, reason: "months should not be empty in en");
      expect(l10n.more, isNotEmpty, reason: "more should not be empty in en");
      expect(l10n.moreOptions, isNotEmpty, reason: "moreOptions should not be empty in en");
      expect(l10n.name, isNotEmpty, reason: "name should not be empty in en");
      expect(l10n.needRestock, isNotEmpty, reason: "needRestock should not be empty in en");
      expect(l10n.newBrandTitle, isNotEmpty, reason: "newBrandTitle should not be empty in en");
      expect(l10n.newCategoryTitle, isNotEmpty, reason: "newCategoryTitle should not be empty in en");
      expect(l10n.newPrice, isNotEmpty, reason: "newPrice should not be empty in en");
      expect(l10n.newProductTitle, isNotEmpty, reason: "newProductTitle should not be empty in en");
      expect(l10n.no, isNotEmpty, reason: "no should not be empty in en");
      expect(l10n.noAccountsFound, isNotEmpty, reason: "noAccountsFound should not be empty in en");
      expect(l10n.noBrandFound, isNotEmpty, reason: "noBrandFound should not be empty in en");
      expect(l10n.noCategoryFound, isNotEmpty, reason: "noCategoryFound should not be empty in en");
      expect(l10n.noCustomerSelected, isNotEmpty, reason: "noCustomerSelected should not be empty in en");
      expect(l10n.noCustomersFound, isNotEmpty, reason: "noCustomersFound should not be empty in en");
      expect(l10n.noData, isNotEmpty, reason: "noData should not be empty in en");
      expect(l10n.noDataToExport, isNotEmpty, reason: "noDataToExport should not be empty in en");
      expect(l10n.noDebtData, isNotEmpty, reason: "noDebtData should not be empty in en");
      expect(l10n.noInvoicesFound, isNotEmpty, reason: "noInvoicesFound should not be empty in en");
      expect(l10n.noOtherStoreToTransfer, isNotEmpty, reason: "noOtherStoreToTransfer should not be empty in en");
      expect(l10n.noPhone, isNotEmpty, reason: "noPhone should not be empty in en");
      expect(l10n.noPhoneAvailable, isNotEmpty, reason: "noPhoneAvailable should not be empty in en");
      expect(l10n.noProducts, isNotEmpty, reason: "noProducts should not be empty in en");
      expect(l10n.noProductsFound, isNotEmpty, reason: "noProductsFound should not be empty in en");
      expect(l10n.noPurchases, isNotEmpty, reason: "noPurchases should not be empty in en");
      expect(l10n.noSalesData, isNotEmpty, reason: "noSalesData should not be empty in en");
      expect(l10n.noTransactions, isNotEmpty, reason: "noTransactions should not be empty in en");
      expect(l10n.noTransactionsYet, isNotEmpty, reason: "noTransactionsYet should not be empty in en");
      expect(l10n.notCategorized, isNotEmpty, reason: "notCategorized should not be empty in en");
      expect(l10n.notEnoughStock, isNotEmpty, reason: "notEnoughStock should not be empty in en");
      expect(l10n.notFound, isNotEmpty, reason: "notFound should not be empty in en");
      expect(l10n.notUpdated, isNotEmpty, reason: "notUpdated should not be empty in en");
      expect(l10n.note, isNotEmpty, reason: "note should not be empty in en");
      expect(l10n.numberOfProducts, isNotEmpty, reason: "numberOfProducts should not be empty in en");
      expect(l10n.onlySupervisorCanAssignStore, isNotEmpty, reason: "onlySupervisorCanAssignStore should not be empty in en");
      expect(l10n.onlySupervisorCanEditRole, isNotEmpty, reason: "onlySupervisorCanEditRole should not be empty in en");
      expect(l10n.orderCreatedBy, isNotEmpty, reason: "orderCreatedBy should not be empty in en");
      expect(l10n.orderDiscount, isNotEmpty, reason: "orderDiscount should not be empty in en");
      expect(l10n.orderInfo, isNotEmpty, reason: "orderInfo should not be empty in en");
      expect(l10n.orders, isNotEmpty, reason: "orders should not be empty in en");
      expect(l10n.outOfStockAlert, isNotEmpty, reason: "outOfStockAlert should not be empty in en");
      expect(l10n.outOfStockMsg, isNotEmpty, reason: "outOfStockMsg should not be empty in en");
      expect(l10n.overview, isNotEmpty, reason: "overview should not be empty in en");
      expect(l10n.paid, isNotEmpty, reason: "paid should not be empty in en");
      expect(l10n.parentCategoryLabel, isNotEmpty, reason: "parentCategoryLabel should not be empty in en");
      expect(l10n.passwordLabel, isNotEmpty, reason: "passwordLabel should not be empty in en");
      expect(l10n.payment, isNotEmpty, reason: "payment should not be empty in en");
      expect(l10n.paymentMethod, isNotEmpty, reason: "paymentMethod should not be empty in en");
      expect(l10n.paymentMethodTransfer, isNotEmpty, reason: "paymentMethodTransfer should not be empty in en");
      expect(l10n.paymentNoteDefault, isNotEmpty, reason: "paymentNoteDefault should not be empty in en");
      expect(l10n.paymentSuccess, isNotEmpty, reason: "paymentSuccess should not be empty in en");
      expect(l10n.performedBy, isNotEmpty, reason: "performedBy should not be empty in en");
      expect(l10n.phone, isNotEmpty, reason: "phone should not be empty in en");
      expect(l10n.phoneNumberRequired, isNotEmpty, reason: "phoneNumberRequired should not be empty in en");
      expect(l10n.pickImageFromGallery, isNotEmpty, reason: "pickImageFromGallery should not be empty in en");
      expect(l10n.pleaseEnter, isNotEmpty, reason: "pleaseEnter should not be empty in en");
      expect(l10n.pleaseEnterAdjustedDebt, isNotEmpty, reason: "pleaseEnterAdjustedDebt should not be empty in en");
      expect(l10n.pleaseEnterCredentials, isNotEmpty, reason: "pleaseEnterCredentials should not be empty in en");
      expect(l10n.pleaseEnterEmail, isNotEmpty, reason: "pleaseEnterEmail should not be empty in en");
      expect(l10n.pleaseEnterName, isNotEmpty, reason: "pleaseEnterName should not be empty in en");
      expect(l10n.pleaseEnterValidEmail, isNotEmpty, reason: "pleaseEnterValidEmail should not be empty in en");
      expect(l10n.pleaseEnterValidNumber, isNotEmpty, reason: "pleaseEnterValidNumber should not be empty in en");
      expect(l10n.pleaseFillAllField, isNotEmpty, reason: "pleaseFillAllField should not be empty in en");
      expect(l10n.pleaseSelectDateRange, isNotEmpty, reason: "pleaseSelectDateRange should not be empty in en");
      expect(l10n.price, isNotEmpty, reason: "price should not be empty in en");
      expect(l10n.productAdded, isNotEmpty, reason: "productAdded should not be empty in en");
      expect(l10n.productCode, isNotEmpty, reason: "productCode should not be empty in en");
      expect(l10n.productDetail, isNotEmpty, reason: "productDetail should not be empty in en");
      expect(l10n.productId, isNotEmpty, reason: "productId should not be empty in en");
      expect(l10n.productList, isNotEmpty, reason: "productList should not be empty in en");
      expect(l10n.productName, isNotEmpty, reason: "productName should not be empty in en");
      expect(l10n.productNotFoundInSystem, isNotEmpty, reason: "productNotFoundInSystem should not be empty in en");
      expect(l10n.products, isNotEmpty, reason: "products should not be empty in en");
      expect(l10n.profit, isNotEmpty, reason: "profit should not be empty in en");
      expect(l10n.purchaseHistory, isNotEmpty, reason: "purchaseHistory should not be empty in en");
      expect(l10n.purchasedOn, isNotEmpty, reason: "purchasedOn should not be empty in en");
      expect(l10n.purchases, isNotEmpty, reason: "purchases should not be empty in en");
      expect(l10n.qrTitle, isNotEmpty, reason: "qrTitle should not be empty in en");
      expect(l10n.quantity, isNotEmpty, reason: "quantity should not be empty in en");
      expect(l10n.receiptAmount, isNotEmpty, reason: "receiptAmount should not be empty in en");
      expect(l10n.reports, isNotEmpty, reason: "reports should not be empty in en");
      expect(l10n.retailCustomer, isNotEmpty, reason: "retailCustomer should not be empty in en");
      expect(l10n.retry, isNotEmpty, reason: "retry should not be empty in en");
      expect(l10n.returnsCountLabel, isNotEmpty, reason: "returnsCountLabel should not be empty in en");
      expect(l10n.revenue, isNotEmpty, reason: "revenue should not be empty in en");
      expect(l10n.revenueByProduct, isNotEmpty, reason: "revenueByProduct should not be empty in en");
      expect(l10n.revenueSummary, isNotEmpty, reason: "revenueSummary should not be empty in en");
      expect(l10n.roleAdmin, isNotEmpty, reason: "roleAdmin should not be empty in en");
      expect(l10n.roleStaff, isNotEmpty, reason: "roleStaff should not be empty in en");
      expect(l10n.roleSupervisor, isNotEmpty, reason: "roleSupervisor should not be empty in en");
      expect(l10n.salesTitle, isNotEmpty, reason: "salesTitle should not be empty in en");
      expect(l10n.save, isNotEmpty, reason: "save should not be empty in en");
      expect(l10n.saveDraft, isNotEmpty, reason: "saveDraft should not be empty in en");
      expect(l10n.saveDraftConfirm, isNotEmpty, reason: "saveDraftConfirm should not be empty in en");
      expect(l10n.saveDraftTitle, isNotEmpty, reason: "saveDraftTitle should not be empty in en");
      expect(l10n.saveReceipt, isNotEmpty, reason: "saveReceipt should not be empty in en");
      expect(l10n.searchCustomersHint, isNotEmpty, reason: "searchCustomersHint should not be empty in en");
      expect(l10n.searchInvoicesHint, isNotEmpty, reason: "searchInvoicesHint should not be empty in en");
      expect(l10n.searchPOSHint, isNotEmpty, reason: "searchPOSHint should not be empty in en");
      expect(l10n.searchProducts, isNotEmpty, reason: "searchProducts should not be empty in en");
      expect(l10n.searchProductsHint, isNotEmpty, reason: "searchProductsHint should not be empty in en");
      expect(l10n.selectAll, isNotEmpty, reason: "selectAll should not be empty in en");
      expect(l10n.selectBranch, isNotEmpty, reason: "selectBranch should not be empty in en");
      expect(l10n.selectCategoryTitle, isNotEmpty, reason: "selectCategoryTitle should not be empty in en");
      expect(l10n.selectCustomer, isNotEmpty, reason: "selectCustomer should not be empty in en");
      expect(l10n.selectDate, isNotEmpty, reason: "selectDate should not be empty in en");
      expect(l10n.selectDateRange, isNotEmpty, reason: "selectDateRange should not be empty in en");
      expect(l10n.selectTargetStore, isNotEmpty, reason: "selectTargetStore should not be empty in en");
      expect(l10n.settingsTitle, isNotEmpty, reason: "settingsTitle should not be empty in en");
      expect(l10n.shipping, isNotEmpty, reason: "shipping should not be empty in en");
      expect(l10n.staff, isNotEmpty, reason: "staff should not be empty in en");
      expect(l10n.status, isNotEmpty, reason: "status should not be empty in en");
      expect(l10n.stock, isNotEmpty, reason: "stock should not be empty in en");
      expect(l10n.stockAfterImport, isNotEmpty, reason: "stockAfterImport should not be empty in en");
      expect(l10n.stockLabel, isNotEmpty, reason: "stockLabel should not be empty in en");
      expect(l10n.store, isNotEmpty, reason: "store should not be empty in en");
      expect(l10n.takeNewPhoto, isNotEmpty, reason: "takeNewPhoto should not be empty in en");
      expect(l10n.targetStore, isNotEmpty, reason: "targetStore should not be empty in en");
      expect(l10n.taxAndAccounting, isNotEmpty, reason: "taxAndAccounting should not be empty in en");
      expect(l10n.taxCode, isNotEmpty, reason: "taxCode should not be empty in en");
      expect(l10n.timeRange, isNotEmpty, reason: "timeRange should not be empty in en");
      expect(l10n.title, isNotEmpty, reason: "title should not be empty in en");
      expect(l10n.topSelling, isNotEmpty, reason: "topSelling should not be empty in en");
      expect(l10n.totalAmount, isNotEmpty, reason: "totalAmount should not be empty in en");
      expect(l10n.totalExpense, isNotEmpty, reason: "totalExpense should not be empty in en");
      expect(l10n.totalOrders, isNotEmpty, reason: "totalOrders should not be empty in en");
      expect(l10n.totalPaymentAmount, isNotEmpty, reason: "totalPaymentAmount should not be empty in en");
      expect(l10n.totalProductAmount, isNotEmpty, reason: "totalProductAmount should not be empty in en");
      expect(l10n.totalProfit, isNotEmpty, reason: "totalProfit should not be empty in en");
      expect(l10n.totalQuantity, isNotEmpty, reason: "totalQuantity should not be empty in en");
      expect(l10n.totalRevenue, isNotEmpty, reason: "totalRevenue should not be empty in en");
      expect(l10n.totalSales, isNotEmpty, reason: "totalSales should not be empty in en");
      expect(l10n.totalSalesAndReturns, isNotEmpty, reason: "totalSalesAndReturns should not be empty in en");
      expect(l10n.totalValue, isNotEmpty, reason: "totalValue should not be empty in en");
      expect(l10n.transactionHistory, isNotEmpty, reason: "transactionHistory should not be empty in en");
      expect(l10n.transactions, isNotEmpty, reason: "transactions should not be empty in en");
      expect(l10n.transfer, isNotEmpty, reason: "transfer should not be empty in en");
      expect(l10n.transferCompleted, isNotEmpty, reason: "transferCompleted should not be empty in en");
      expect(l10n.transferDetails, isNotEmpty, reason: "transferDetails should not be empty in en");
      expect(l10n.transferProduct, isNotEmpty, reason: "transferProduct should not be empty in en");
      expect(l10n.transferQuantity, isNotEmpty, reason: "transferQuantity should not be empty in en");
      expect(l10n.tryAdjustingSearch, isNotEmpty, reason: "tryAdjustingSearch should not be empty in en");
      expect(l10n.unitPrice, isNotEmpty, reason: "unitPrice should not be empty in en");
      expect(l10n.unknownStore, isNotEmpty, reason: "unknownStore should not be empty in en");
      expect(l10n.update, isNotEmpty, reason: "update should not be empty in en");
      expect(l10n.updated, isNotEmpty, reason: "updated should not be empty in en");
      expect(l10n.usernameLabel, isNotEmpty, reason: "usernameLabel should not be empty in en");
      expect(l10n.walkInCustomerDebtNotAllowed, isNotEmpty, reason: "walkInCustomerDebtNotAllowed should not be empty in en");
      expect(l10n.wantToDelete, isNotEmpty, reason: "wantToDelete should not be empty in en");
      expect(l10n.warranty, isNotEmpty, reason: "warranty should not be empty in en");
      expect(l10n.warrantyActive, isNotEmpty, reason: "warrantyActive should not be empty in en");
      expect(l10n.warrantyExpired, isNotEmpty, reason: "warrantyExpired should not be empty in en");
      expect(l10n.warrantyExpiresIn, isNotEmpty, reason: "warrantyExpiresIn should not be empty in en");
      expect(l10n.warrantyPeriod, isNotEmpty, reason: "warrantyPeriod should not be empty in en");
      expect(l10n.warrantyStatus, isNotEmpty, reason: "warrantyStatus should not be empty in en");
      expect(l10n.accountDeleteConfirm('TEST_VALUE'), isNotEmpty, reason: "accountDeleteConfirm should not be empty in en");
      expect(l10n.amountToPayLabel('TEST_VALUE'), isNotEmpty, reason: "amountToPayLabel should not be empty in en");
      expect(l10n.attendanceDeleteShiftConfirm('TEST_VALUE'), isNotEmpty, reason: "attendanceDeleteShiftConfirm should not be empty in en");
      expect(l10n.cannotCall('TEST_VALUE'), isNotEmpty, reason: "cannotCall should not be empty in en");
      expect(l10n.cannotSms('TEST_VALUE'), isNotEmpty, reason: "cannotSms should not be empty in en");
      expect(l10n.cartSummaryTitle(5), isNotEmpty, reason: "cartSummaryTitle should not be empty in en");
      expect(l10n.copyCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyCodeSuccess should not be empty in en");
      expect(l10n.copyCustomerCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyCustomerCodeSuccess should not be empty in en");
      expect(l10n.copyInvoiceCodeSuccess('TEST_VALUE'), isNotEmpty, reason: "copyInvoiceCodeSuccess should not be empty in en");
      expect(l10n.copyPhoneSuccess('TEST_VALUE'), isNotEmpty, reason: "copyPhoneSuccess should not be empty in en");
      expect(l10n.createdTimeLabel('TEST_VALUE'), isNotEmpty, reason: "createdTimeLabel should not be empty in en");
      expect(l10n.deleteCustomerConfirm('TEST_VALUE'), isNotEmpty, reason: "deleteCustomerConfirm should not be empty in en");
      expect(l10n.goodsCount(5), isNotEmpty, reason: "goodsCount should not be empty in en");
      expect(l10n.inventoryLoadError('TEST_VALUE'), isNotEmpty, reason: "inventoryLoadError should not be empty in en");
      expect(l10n.invoiceCountLabel(5), isNotEmpty, reason: "invoiceCountLabel should not be empty in en");
      expect(l10n.orderIdLabel('TEST_VALUE'), isNotEmpty, reason: "orderIdLabel should not be empty in en");
      expect(l10n.ordersCount(5), isNotEmpty, reason: "ordersCount should not be empty in en");
      expect(l10n.receiptCreatedSuccess('TEST_VALUE'), isNotEmpty, reason: "receiptCreatedSuccess should not be empty in en");
      expect(l10n.remainingDebtLabel('TEST_VALUE'), isNotEmpty, reason: "remainingDebtLabel should not be empty in en");
      expect(l10n.soldQty(5), isNotEmpty, reason: "soldQty should not be empty in en");
      expect(l10n.stockLimitAlert(5), isNotEmpty, reason: "stockLimitAlert should not be empty in en");
      expect(l10n.totalCustomers(5), isNotEmpty, reason: "totalCustomers should not be empty in en");
      expect(l10n.totalInvoices(5), isNotEmpty, reason: "totalInvoices should not be empty in en");
      expect(l10n.totalProducts(5), isNotEmpty, reason: "totalProducts should not be empty in en");
      expect(l10n.totalStockCount(5), isNotEmpty, reason: "totalStockCount should not be empty in en");
    });

    testWidgets('3. BuildContext.l10n throws TypeError when pumped without localization delegates', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                () => context.l10n,
                throwsA(isA<TypeError>()),
                reason: 'Calling context.l10n without delegates must fail fast due to non-null assertion',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('4. CustomerListTile resolves context.l10n without phone fallback and renders with 0 errors', (tester) async {
      const customerNoPhone = Customer(
        id: 'cust_01',
        name: 'Trần Văn B',
        phone: '',
        email: '',
        address: '',
        purchases: [],
        currentDebt: 500000,
        totalSales: 2000000,
      );

      final fakeAuth = _FakeAuthNotifier(const UserAccount(
        username: 'admin',
        displayName: 'Admin User',
        role: 'admin',
        storeId: 'store_001',
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => fakeAuth),
          ],
          child: const MaterialApp(
            locale: Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CustomerListTile(customer: customerNoPhone),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Trần Văn B'), findsOneWidget);
      expect(find.text('Chưa có SĐT'), findsOneWidget);
    });

    testWidgets('5. LoginPage resolves context.l10n labels and renders smoothly with 0 errors in both vi and en', (tester) async {
      final fakeAuth = _FakeAuthNotifier();

      // Test Vietnamese
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => fakeAuth),
          ],
          child: const MaterialApp(
            locale: Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đăng Nhập'), findsNWidgets(2)); // Title and Button
      expect(find.text('Tên đăng nhập'), findsOneWidget);
      expect(find.text('Mật khẩu'), findsOneWidget);

      // Re-pump with English
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => fakeAuth),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsNWidgets(2)); // Title and Button
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('6. CustomerDebtAdjustmentPage resolves context.l10n title with 0 errors', (tester) async {
      const customer = Customer(
        id: 'cust_02',
        name: 'Lê Thị C',
        phone: '0901234567',
        email: '',
        address: '',
        purchases: [],
        currentDebt: 1000000,
        totalSales: 5000000,
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CustomerDebtAdjustmentPage(customer: customer),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Điều chỉnh công nợ'), findsOneWidget);
    });

    testWidgets('7. OverviewFilterBar renders with AppLocalizations.of(context) in vi and en without plugin exceptions', (tester) async {
      final fakeAuth = _FakeAuthNotifier(const UserAccount(
        username: 'admin',
        displayName: 'Admin User',
        role: 'admin',
        storeId: 'store_001',
      ));
      final branchesNotifier = SelectedBranchesNotifier(const UserAccount(username: 'admin', displayName: 'Admin User', role: 'admin', storeId: 'store_001'), ['store_001', 'store_002']);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            selectedStoreFilterProvider.overrideWith((ref) => 'all'),
            selectedBranchesProvider.overrideWith((ref) => branchesNotifier),
            overviewTimeRangeTypeProvider.overrideWith((ref) => OverviewTimeRange.today),
            authProvider.overrideWith((ref) => fakeAuth),
          ],
          child: const MaterialApp(
            locale: Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: OverviewFilterBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tất cả chi nhánh (Xem gộp)'), findsOneWidget);
    });

    testWidgets('8. Dynamic locale change (vi -> en -> vi) triggers rebuild cleanly without MissingPluginException', (tester) async {
      final localeNotifier = ValueNotifier<Locale>(const Locale('vi'));

      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, currentLocale, _) {
            return MaterialApp(
              locale: currentLocale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (ctx) {
                  return Scaffold(
                    body: Text(ctx.l10n.commonSaveDraft),
                  );
                },
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lưu tạm'), findsOneWidget);

      // Switch to English
      localeNotifier.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Save Draft'), findsOneWidget);

      // Switch back to Vietnamese
      localeNotifier.value = const Locale('vi');
      await tester.pumpAndSettle();
      expect(find.text('Lưu tạm'), findsOneWidget);
    });

    testWidgets('9. Fallback behavior for unhandled locale (e.g. French) gracefully falls back without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (locale, supported) {
            return supported.first;
          },
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Text(context.l10n.cancel),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
