import 'dart:io';
import 'package:stores/core/utils/excel_helper.dart';

void main() async {
  try {
    print("Reading file...");
    final file = File("DanhSachKhachHang_KV05072026-113800-340.xlsx");
    if (!file.existsSync()) {
      print("File does not exist!");
      return;
    }
    final bytes = await file.readAsBytes();
    print("Parsing Excel...");
    final customers = ExcelHelper.parseCustomers(bytes);
    print("Success! Parsed ${customers.length} customers.");
  } catch (e, stack) {
    print("Error encountered: $e");
    print("Stack trace:\n$stack");
  }
}
