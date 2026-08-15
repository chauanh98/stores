class VietQRHelper {
  /// Danh sách các ngân hàng phổ biến tại Việt Nam hỗ trợ VietQR
  static const Map<String, String> supportedBanks = {
    'vietinbank': 'VietinBank (ICB)',
    'vietcombank': 'Vietcombank (VCB)',
    'mbbank': 'MBBank (MB)',
    'techcombank': 'Techcombank (TCB)',
    'bidv': 'BIDV',
    'acb': 'ACB',
    'tpbank': 'TPBank',
    'vpbank': 'VPBank',
    'agribank': 'Agribank',
    'sacombank': 'Sacombank',
    'hdbank': 'HDBank',
    'shb': 'SHB',
    'vib': 'VIB',
    'seabank': 'SeABank',
  };

  /// Tạo đường dẫn VietQR Quick Link dạng ảnh PNG
  ///
  /// Param:
  /// - `bankId`: Mã ngân hàng (ví dụ: `vietinbank`, `vcb`, `mbbank`)
  /// - `accountNo`: Số tài khoản nhận
  /// - `accountName`: Tên chủ tài khoản
  /// - `amount`: Số tiền cần chuyển (ví dụ 3080000)
  /// - `addInfo`: Nội dung chuyển khoản (ví dụ `HD012770`)
  static String buildVietQRImageUrl({
    required String bankId,
    required String accountNo,
    required String accountName,
    required double amount,
    required String addInfo,
    String template = 'compact2', // compact, compact2, qr_only, print
  }) {
    final cleanBankId = bankId.trim().toLowerCase();
    final cleanAccountNo = accountNo.trim();
    final cleanAccountName = Uri.encodeComponent(accountName.trim());
    final cleanAddInfo = Uri.encodeComponent(addInfo.trim());
    final amountInt = amount.round();

    return 'https://img.vietqr.io/image/$cleanBankId-$cleanAccountNo-$template.png?amount=$amountInt&addInfo=$cleanAddInfo&accountName=$cleanAccountName';
  }

  /// Format chuỗi hiển thị thông tin chuyển khoản ngân hàng trên hóa đơn
  static String formatBankTransferInfo({
    required String bankName,
    required String accountNo,
    required String accountName,
  }) {
    return '$accountNo - $bankName - ${accountName.toUpperCase()}';
  }
}
