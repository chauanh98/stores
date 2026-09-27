/// Hằng số chuỗi hệ thống, mã lỗi, định danh chi nhánh, loại giao dịch và format key (Non-UI context)
class AppStrings {
  AppStrings._();

  // ── Tên Ứng Dụng & Doanh Nghiệp ──
  static const String appName = 'KĐ Store';
  static const String companyName = 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG';

  // ── Ký Hiệu Tiền Tệ & Đơn Vị Tính ──
  static const String currencySymbol = 'đ';
  static const String currencyCode = 'VND';
  static const String defaultUnit = 'Cái';
  static const String unitPiece = 'Cái';
  static const String unitSet = 'Bộ';
  static const String unitBox = 'Hộp';
  static const String unitKg = 'Kg';
  static const String unitMeter = 'Mét';

  // ── Chi Nhánh Cửa Hàng ──
  static const String storeDongThangId = 'store_001';
  static const String storeDongThangName = 'Chi nhánh Đông Thắng';
  static const String storeDongThangShort = 'Đông Thắng';

  static const String storeThoiBinhId = 'store_002';
  static const String storeThoiBinhName = 'Chi nhánh Thới Bình';
  static const String storeThoiBinhShort = 'Thới Bình';

  static const String allStoresId = 'all';
  static const String allStoresName = 'Tất cả chi nhánh';
  static const String allStoresCombined = 'Toàn bộ chi nhánh (Toàn hệ thống)';

  // ── Phương Thức Thanh Toán ──
  static const String paymentMethodCash = 'cash';
  static const String paymentMethodTransfer = 'transfer';
  static const String paymentMethodCard = 'card';
  static const String paymentMethodDebt = 'debt';

  static const String paymentLabelCash = 'Tiền mặt';
  static const String paymentLabelTransfer = 'Chuyển khoản';
  static const String paymentLabelCard = 'Thẻ';
  static const String paymentLabelDebt = 'Tính vào công nợ';

  // ── Trạng Thái Giao Dịch & Phiếu ──
  static const String statusDraft = 'draft';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';
  static const String statusPending = 'pending';
  static const String statusProcessing = 'processing';

  static const String statusDraftLabel = 'Phiếu tạm';
  static const String statusCompletedLabel = 'Đã hoàn thành';
  static const String statusCancelledLabel = 'Đã hủy';

  // ── Loại Giao Dịch Kho (Inventory Transaction Types) ──
  static const String transactionTypeImport = 'import';
  static const String transactionTypeExport = 'export';
  static const String transactionTypeTransfer = 'transfer';
  static const String transactionTypeAdjustment = 'adjustment';
  static const String transactionTypeReturn = 'return';

  // ── Ngoại Lệ & Thông Báo Lỗi Nghiệp Vụ (UseCases & Repositories) ──
  static const String errorGeneric = 'Đã có lỗi xảy ra. Vui lòng thử lại sau.';
  static const String errorNetwork =
      'Lỗi kết nối mạng. Vui lòng kiểm tra lại đường truyền.';
  static const String errorDatabase = 'Lỗi truy vấn cơ sở dữ liệu.';
  static const String errorUnauthorized =
      'Bạn không có quyền thực hiện thao tác này.';
  static const String errorInsufficientStock =
      'Không đủ số lượng hàng trong kho.';
  static const String errorInvalidQuantity = 'Số lượng phải lớn hơn 0.';
  static const String errorInvalidBranch = 'Chi nhánh không hợp lệ.';
  static const String errorSameBranchTransfer =
      'Không thể chuyển hàng trong cùng một kho.';
  static const String errorOrderAlreadyCancelled =
      'Hóa đơn này đã được hủy trước đó.';
  static const String errorCancelReasonRequired =
      'Lý do hủy đơn không được để trống.';
  static const String errorCannotDeleteCompletedReceipt =
      'Không thể xóa phiếu nhập đã hoàn thành. Vui lòng hủy phiếu để hoàn trả tồn kho và công nợ trước khi xóa.';
  static const String errorDebtExceeded =
      'Số tiền thu nợ vượt quá công nợ còn lại của hóa đơn.';
  static const String errorProductNotFound =
      'Không tìm thấy thông tin sản phẩm.';
  static const String errorSupplierNotFound =
      'Không tìm thấy thông tin nhà cung cấp.';
  static const String errorCustomerNotFound =
      'Không tìm thấy thông tin khách hàng.';
  static const String errorInvalidBarcode = 'Mã vạch không hợp lệ.';

  // ── Mẫu Ghi Chú & Tiền Tố Giao Dịch (Ledger Notes & Note Prefixes) ──
  static const String noteSupplierPayment = 'Thanh toán nợ nhà cung cấp';
  static const String noteSupplierAdjustment =
      'Điều chỉnh công nợ nhà cung cấp';
  static const String noteStockInDebt = 'Nhập hàng phát sinh công nợ';
  static const String noteCustomerDebtAdjustment =
      'Điều chỉnh công nợ khách hàng';
  static const String noteReturnOrder = 'Trả hàng đơn';
  static const String noteCancelStockIn = 'Hủy phiếu nhập kho';
  static const String noteTransferSource = 'Chuyển hàng sang kho';
  static const String noteTransferDestination = 'Nhận hàng chuyển từ kho';

  // ── Định Dạng Thời Gian & Nhãn Bộ Lọc Thời Gian Chuẩn ──
  static const String dateFormatPattern = 'dd/MM/yyyy';
  static const String dateTimeFormatPattern = 'dd/MM/yyyy HH:mm';
  static const String timeFormatPattern = 'HH:mm';
  static const String monthYearFormatPattern = 'MM/yyyy';

  static const String filterToday = 'Hôm nay';
  static const String filterYesterday = 'Hôm qua';
  static const String filterLast7Days = '7 ngày qua';
  static const String filterThisMonth = 'Tháng này';
  static const String filterLastMonth = 'Tháng trước';
  static const String filterCustom = 'Tùy chỉnh';
}
