import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/purchase.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/entities/warranty.dart';

import 'support/excel_e2e_harness.dart';

void main() {
  group('=== EXCEL IMPORT/EXPORT & DEDUPLICATION: MASTER 4-TIER E2E TEST SUITE ===', () {
    // ========================================================================
    // TIER 1: FEATURE COVERAGE (ISOLATION)
    // ========================================================================
    group('TIER 1: Feature Coverage (>=5 tests per feature)', () {
      // ----------------------------------------------------------------------
      // Feature 1: Products Parser & Exporter
      // ----------------------------------------------------------------------
      group('Feature 1: Products Parser & Exporter', () {
        test('T1.1: parseProducts parses standard KiotViet product sheet with code, name, price, and stock', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'SP0001',
              'name': 'Bàn ăn cao cấp',
              'price': 4500000.0,
              'costPrice': 3200000.0,
              'stock': 15.0,
              'unit': 'Bộ',
              'type': 'Hàng hóa',
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.code, 'SP0001');
          expect(products.first.name, 'Bàn ăn cao cấp');
          expect(products.first.price, 4500000.0);
          expect(products.first.costPrice, 3200000.0);
          expect(products.first.stock, 15);
          expect(products.first.unit, 'Bộ');
        });

        test('T1.2: parseProducts parses 3-level hierarchical category and extracts root category', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'SP000771',
              'name': 'Bàn ăn bên nguyên khối',
              'category3Levels': 'Bàn ăn>>Bàn ăn bên',
              'price': 12000000.0,
              'costPrice': 8500000.0,
              'stock': 4.0,
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.category3Levels, 'Bàn ăn>>Bàn ăn bên');
          expect(products.first.category, 'Bàn ăn');
        });

        test('T1.3: parseProducts handles combo products and component metadata', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'COMBO_01',
              'name': 'Bộ phòng khách trọn gói',
              'type': 'Combo - Đóng gói',
              'components': 'SP0001(1), SP0002(4)',
              'price': 15000000.0,
              'costPrice': 10000000.0,
              'stock': 2.0,
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.type, 'Combo - Đóng gói');
          expect(products.first.components, 'SP0001(1), SP0002(4)');
        });

        test('T1.4: ExcelTestWorkbookBuilder produces valid OpenXML bytes matching KiotViet product columns', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {'code': 'TEST_CODE', 'name': 'Test Name', 'price': 1000.0},
          ]);
          expect(bytes, isNotEmpty);
          expect(bytes.length, greaterThan(100));
        });

        test('T1.5: parseProducts handles barcode, description, and note template fields', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'SP99',
              'name': 'Tủ thờ căm xe',
              'barcode': '8936001234567',
              'description': 'Gỗ căm xe 100%, sơn PU bóng',
              'noteTemplate': 'Bảo hành 5 năm tại nhà',
              'imageUrl': 'https://example.com/img.jpg',
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.barcode, '8936001234567');
          expect(products.first.description, 'Gỗ căm xe 100%, sơn PU bóng');
          expect(products.first.noteTemplate, 'Bảo hành 5 năm tại nhà');
          expect(products.first.imageUrl, 'https://example.com/img.jpg');
        });
      });

      // ----------------------------------------------------------------------
      // Feature 2: Customers Parser & Exporter
      // ----------------------------------------------------------------------
      group('Feature 2: Customers Parser & Exporter', () {
        test('T1.6: parseCustomers parses standard KiotViet 24-column customer sheet', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH0001',
              'name': 'Nguyễn Văn An',
              'phone': '0901234567',
              'email': 'an@example.com',
              'address': '123 Lê Lợi, TP.HCM',
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.id, 'KH0001');
          expect(customers.first.name, 'Nguyễn Văn An');
          expect(customers.first.phone, '0901234567');
          expect(customers.first.address, '123 Lê Lợi, TP.HCM');
        });

        test('T1.7: parseCustomers normalizes phone numbers with special characters', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH0002',
              'name': 'Trần Thị Bình',
              'phone': '+84 912-345-678',
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.phone.replaceAll(RegExp(r'\D'), ''), contains('912345678'));
        });

        test('T1.8: parseCustomers parses financial debt and sales totals accurately', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH0003',
              'name': 'Lê Hoàng Cường',
              'phone': '0923456789',
              'currentDebt': 8500000.0,
              'totalSales': 25000000.0,
              'netSales': 23000000.0,
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.currentDebt, 8500000.0);
          expect(customers.first.totalSales, 25000000.0);
          expect(customers.first.netSales, 23000000.0);
        });

        test('T1.9: parseCustomers handles customer metadata and group tags', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH0004',
              'name': 'Công ty TNHH Minh Khang',
              'group': 'Khách sỉ VIP',
              'taxCode': '0312345678',
              'notes': 'Ưu tiên giao buổi sáng',
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.group, 'Khách sỉ VIP');
          expect(customers.first.taxCode, '0312345678');
          expect(customers.first.notes, 'Ưu tiên giao buổi sáng');
        });

        test('T1.10: ExcelTestWorkbookBuilder builds valid customer sheet with 24 columns', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {'id': 'KH_TEST', 'name': 'Khách Hàng Test'},
          ]);
          expect(bytes, isNotEmpty);
          final parsed = ExcelHelper.parseCustomers(bytes);
          expect(parsed.length, 1);
          expect(parsed.first.id, 'KH_TEST');
        });
      });

      // ----------------------------------------------------------------------
      // Feature 3: Suppliers Parser & Exporter
      // ----------------------------------------------------------------------
      group('Feature 3: Suppliers Parser & Exporter', () {
        test('T1.11: SupplierExcelParser.parseSuppliers parses KiotViet 18-column supplier sheet', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC001',
              'name': 'Gỗ Xanh Bình Dương',
              'phone': '0274123456',
              'email': 'goxanh@example.com',
              'address': 'KCN Sóng Thần, Bình Dương',
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.code, 'NCC001');
          expect(suppliers.first.name, 'Gỗ Xanh Bình Dương');
          expect(suppliers.first.phone, '0274123456');
          expect(suppliers.first.email, 'goxanh@example.com');
        });

        test('T1.12: SupplierExcelParser.parseSuppliers parses current debt and total purchases', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC002',
              'name': 'Xưởng Cơ Khí Tiến Phát',
              'totalPurchase': 50000000.0,
              'currentDebt': 15000000.0,
              'taxCode': '3701234567',
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.totalPurchase, 50000000.0);
          expect(suppliers.first.currentDebt, 15000000.0);
          expect(suppliers.first.taxCode, '3701234567');
        });

        test('T1.13: SupplierExcelParser.parseSuppliers embeds group tag in note', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC003',
              'name': 'Đại lý Kim Khí 1',
              'group': 'Nhà cung cấp sắt thép',
              'note': 'Giao hàng tận kho',
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.note, contains('[Nhóm: Nhà cung cấp sắt thép]'));
        });

        test('T1.14: SupplierExcelParser.exportSuppliers exports valid Uint8List bytes', () async {
          const supplier = Supplier(
            id: 'NCC001',
            code: 'NCC001',
            name: 'Gỗ Xanh Bình Dương',
            phone: '0274123456',
            email: 'goxanh@example.com',
            address: 'Bình Dương',
            currentDebt: 15000000.0,
            totalPurchase: 60000000.0,
          );

          final bytes = await SupplierExcelParser.exportSuppliers([supplier]);
          expect(bytes, isNotEmpty);
          final reParsed = SupplierExcelParser.parseSuppliers(bytes);
          expect(reParsed.length, 1);
          expect(reParsed.first.code, 'NCC001');
          expect(reParsed.first.currentDebt, 15000000.0);
        });

        test('T1.15: SupplierExcelParser.parseSuppliers handles status and creation metadata', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC005',
              'name': 'Công ty Sơn Á Đông',
              'status': '1',
              'createdBy': 'manager1',
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.status, 'active');
          expect(suppliers.first.createdBy, 'manager1');
        });
      });

      // ----------------------------------------------------------------------
      // Feature 4: Invoices Parser & Exporter
      // ----------------------------------------------------------------------
      group('Feature 4: Invoices Parser & Exporter', () {
        test('T1.16: InvoiceExcelParser.parseInvoices groups multi-line items into a single Order', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD001',
              'customerId': 'KH001',
              'customerName': 'Nguyễn Văn An',
              'total': 5000000.0,
              'amountPaid': 5000000.0,
              'productId': 'SP01',
              'productName': 'Bàn ăn',
              'quantity': 1,
              'price': 3000000.0,
            },
            {
              'orderId': 'HD001',
              'customerId': 'KH001',
              'customerName': 'Nguyễn Văn An',
              'total': 5000000.0,
              'amountPaid': 5000000.0,
              'productId': 'SP02',
              'productName': 'Ghế ăn',
              'quantity': 4,
              'price': 500000.0,
            },
          ], isDetailed: true);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 1);
          expect(orders.first.id, 'HD001');
          expect(orders.first.items.length, 2);
          expect(orders.first.items[0].productId, 'SP01');
          expect(orders.first.items[1].productId, 'SP02');
          expect(orders.first.total, 5000000.0);
        });

        test('T1.17: InvoiceExcelParser.parseInvoices parses flat summary rows with synthetic item', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD002',
              'customerId': 'KH002',
              'customerName': 'Trần Thị Bình',
              'total': 2500000.0,
              'amountPaid': 2000000.0,
              'debtAmount': 500000.0,
              'paymentMethod': 'Tiền mặt',
              'status': 'Hoàn thành',
            },
          ], isDetailed: false);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 1);
          expect(orders.first.id, 'HD002');
          expect(orders.first.debtAmount, 500000.0);
          expect(orders.first.items.length, 1);
          expect(orders.first.items.first.price, 2500000.0);
        });

        test('T1.18: InvoiceExcelParser.parseInvoices normalizes order statuses correctly', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {'orderId': 'HD_CANCEL', 'status': 'Đã hủy', 'total': 1000.0},
            {'orderId': 'HD_RETURN', 'status': 'Đã trả hàng', 'total': 2000.0},
            {'orderId': 'HD_DRAFT', 'status': 'Lưu tạm', 'total': 3000.0},
            {'orderId': 'HD_DONE', 'status': 'Hoàn thành', 'total': 4000.0},
          ], isDetailed: false);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 4);
          expect(orders.firstWhere((o) => o.id == 'HD_CANCEL').status, 'cancelled');
          expect(orders.firstWhere((o) => o.id == 'HD_RETURN').status, 'returned');
          expect(orders.firstWhere((o) => o.id == 'HD_DRAFT').status, 'draft');
          expect(orders.firstWhere((o) => o.id == 'HD_DONE').status, 'completed');
        });

        test('T1.19: InvoiceExcelParser.parseInvoices parses split payment method', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD_SPLIT',
              'total': 10000000.0,
              'amountPaid': 10000000.0,
              'cashAmount': 4000000.0,
              'transferAmount': 6000000.0,
            },
          ], isDetailed: true);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 1);
          expect(orders.first.paymentMethod, 'split');
        });

        test('T1.20: ExcelHelper.exportInvoices produces formatted Uint8List bytes', () async {
          final order = Order(
            id: 'HD000100',
            customerId: 'KH01',
            createdAt: DateTime(2026, 9, 1),
            items: [
              OrderItem(
                productId: 'SP01',
                productName: 'Tủ giày thông minh',
                quantity: 1,
                price: 1800000.0,
                warrantyMonths: 12,
                purchaseDate: DateTime(2026, 9, 1),
              ),
            ],
            total: 1800000.0,
            amountPaid: 1800000.0,
            debtAmount: 0.0,
            paymentMethod: 'cash',
            createdBy: 'admin',
            storeId: 'store_001',
          );

          final bytes = await ExcelHelper.exportInvoices(
            [order],
            storeName: 'Chi nhánh Đông Thắng',
            filterDescription: 'Tất cả hóa đơn',
          );

          expect(bytes, isNotEmpty);
          expect(bytes.length, greaterThan(500));
        });
      });

      // ----------------------------------------------------------------------
      // Feature 5: Web File Saver
      // ----------------------------------------------------------------------
      group('Feature 5: Web File Saver', () {
        late WebFileSaverMock saverMock;

        setUp(() {
          saverMock = WebFileSaverMock();
        });

        test('T1.21: saveExcelFile accepts in-memory Uint8List bytes without file path', () async {
          final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
          await saverMock.saveExcelFile(bytes, 'DanhSachSanPham.xlsx');

          expect(saverMock.isTriggered, isTrue);
          expect(saverMock.lastSavedBytes, bytes);
        });

        test('T1.22: Web download sets proper MIME type for OpenXML spreadsheet', () async {
          final bytes = Uint8List.fromList([10, 20, 30]);
          await saverMock.saveExcelFile(bytes, 'Report.xlsx');

          expect(saverMock.lastMimeType,
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        });

        test('T1.23: Web download enforces .xlsx file extension', () async {
          final bytes = Uint8List.fromList([10, 20, 30]);
          await saverMock.saveExcelFile(bytes, 'DanhSachHoaDon');

          expect(saverMock.lastFileName, 'DanhSachHoaDon.xlsx');
        });

        test('T1.24: saveExcelFile rejects empty byte payload with ArgumentError', () async {
          final emptyBytes = Uint8List(0);
          expect(
            () => saverMock.saveExcelFile(emptyBytes, 'test.xlsx'),
            throwsA(isA<ArgumentError>()),
          );
        });

        test('T1.25: saveExcelFile handles non-ASCII and Vietnamese file names safely', () async {
          final bytes = Uint8List.fromList([1, 2, 3]);
          await saverMock.saveExcelFile(bytes, 'Danh_Sách_Khách_Hàng_2026.xlsx');

          expect(saverMock.lastFileName, 'Danh_Sách_Khách_Hàng_2026.xlsx');
          expect(saverMock.isTriggered, isTrue);
        });
      });

      // ----------------------------------------------------------------------
      // Feature 6: Deduplication Result Structure
      // ----------------------------------------------------------------------
      group('Feature 6: Deduplication Result Structure', () {
        test('T1.26: ImportResult computes isSuccess == true when errors == 0', () {
          const res = ImportResult(total: 10, added: 6, updated: 4, errors: 0);
          expect(res.isSuccess, isTrue);
          expect(res.hasErrors, isFalse);
        });

        test('T1.27: ImportResult computes hasErrors == true when errors > 0', () {
          const res = ImportResult(total: 10, added: 5, updated: 3, errors: 2);
          expect(res.isSuccess, isFalse);
          expect(res.hasErrors, isTrue);
        });

        test('T1.28: ImportResult formats exact R2 summary string template', () {
          const res = ImportResult(total: 100, added: 70, updated: 25, skipped: 3, errors: 2);
          expect(res.toSummaryString(),
              'Tổng số dòng: 100 | Thêm mới: 70 | Cập nhật: 25 | Bỏ qua: 3 | Lỗi: 2');
        });

        test('T1.29: ImportResult captures error message list correctly', () {
          const res = ImportResult(
            total: 2,
            errors: 1,
            errorMessages: ['Dòng 2: Mã khách hàng bị trùng lặp.'],
          );
          expect(res.errorMessages.length, 1);
          expect(res.errorMessages.first, contains('Mã khách hàng'));
        });

        test('T1.30: ImportResult handles zero-count default values cleanly', () {
          const res = ImportResult();
          expect(res.total, 0);
          expect(res.added, 0);
          expect(res.updated, 0);
          expect(res.skipped, 0);
          expect(res.errors, 0);
          expect(res.errorMessages, isEmpty);
        });
      });

      // ----------------------------------------------------------------------
      // Feature 7: Admin/Web Guard Evaluation
      // ----------------------------------------------------------------------
      group('Feature 7: Admin/Web Guard Evaluation', () {
        const adminUser = UserAccount(
          username: 'admin1',
          role: 'admin',
          displayName: 'System Administrator',
          storeId: 'store_001',
        );

        const supervisorUser = UserAccount(
          username: 'supervisor1',
          role: 'cuahangtruong',
          displayName: 'Store Supervisor',
          storeId: 'store_001',
        );

        const staffUser = UserAccount(
          username: 'staff1',
          role: 'nhanvien',
          displayName: 'Store Staff',
          storeId: 'store_001',
        );

        test('T1.31: UI Guard allows action when kIsWeb == true and user is Admin', () {
          final visible = ExcelPermissionGuardEvaluator.shouldShowExcelActions(
            isWeb: true,
            user: adminUser,
          );
          expect(visible, isTrue);
        });

        test('T1.32: UI Guard blocks action on Native/Mobile (isWeb == false) even for Admin', () {
          final visible = ExcelPermissionGuardEvaluator.shouldShowExcelActions(
            isWeb: false,
            user: adminUser,
          );
          expect(visible, isFalse);
        });

        test('T1.33: UI Guard blocks action for Supervisor users on Web', () {
          final visible = ExcelPermissionGuardEvaluator.shouldShowExcelActions(
            isWeb: true,
            user: supervisorUser,
          );
          expect(visible, isFalse);
        });

        test('T1.34: UI Guard blocks action for Staff users on Web', () {
          final visible = ExcelPermissionGuardEvaluator.shouldShowExcelActions(
            isWeb: true,
            user: staffUser,
          );
          expect(visible, isFalse);
        });

        test('T1.35: Execution Guard rejects unauthenticated or invalid user requests', () {
          expect(
            ExcelPermissionGuardEvaluator.canExecuteExcelAction(isWeb: true, user: null),
            isFalse,
          );
          expect(
            ExcelPermissionGuardEvaluator.canExecuteExcelAction(isWeb: false, user: adminUser),
            isFalse,
          );
          expect(
            ExcelPermissionGuardEvaluator.canExecuteExcelAction(isWeb: true, user: adminUser),
            isTrue,
          );
        });
      });
    });

    // ========================================================================
    // TIER 2: BOUNDARY & CORNER CASES
    // ========================================================================
    group('TIER 2: Boundary & Corner Cases (>=5 tests per feature)', () {
      // ----------------------------------------------------------------------
      // Boundary 1: Empty & Truncated Files
      // ----------------------------------------------------------------------
      group('Boundary 1: Empty & Truncated Files', () {
        test('T2.1: 0-byte input to parseProducts throws UnsupportedError on raw empty bytes', () {
          expect(
            () => ExcelHelper.parseProducts([]),
            throwsA(isA<UnsupportedError>()),
          );
        });

        test('T2.2: 0-byte input to parseSuppliers returns empty list', () {
          final suppliers = SupplierExcelParser.parseSuppliers([]);
          expect(suppliers, isEmpty);
        });

        test('T2.3: 0-byte input to parseInvoices returns empty list', () {
          final invoices = InvoiceExcelParser.parseInvoices([]);
          expect(invoices, isEmpty);
        });

        test('T2.4: Header-only sheet with 0 data rows returns empty list', () {
          final bytes = ExcelTestWorkbookBuilder.buildHeaderOnlySheet([
            'Mã hàng',
            'Tên hàng',
            'Giá bán',
          ]);
          final products = ExcelHelper.parseProducts(bytes);
          expect(products, isEmpty);
        });

        test('T2.5: Workbook with multiple blank rows filters empty rows seamlessly', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {'code': '', 'name': '', 'price': null},
            {'code': 'SP_REAL', 'name': 'Sản phẩm thật', 'price': 50000.0},
            {'code': '', 'name': '', 'price': null},
          ]);
          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.code, 'SP_REAL');
        });
      });

      // ----------------------------------------------------------------------
      // Boundary 2: Missing IDs, Codes, and Phones
      // ----------------------------------------------------------------------
      group('Boundary 2: Missing IDs, Codes, and Phones', () {
        test('T2.6: Product row with empty code and ID is captured as an error', () async {
          final engine = ProductDeduplicationEngine();
          const badProduct = Product(
            id: '',
            code: '',
            name: 'Hàng không mã',
            price: 100.0,
            costPrice: 50.0,
            branchStocks: {},
            category: 'Khác',
          );

          final result = await engine.importProducts(
            importedProducts: [badProduct],
            targetStoreId: 'store_001',
          );

          expect(result.errors, 1);
          expect(result.added, 0);
          expect(result.errorMessages.first, contains('Mã hàng và ID không được để trống'));
        });

        test('T2.7: Customer with missing ID matches existing customer by phone', () async {
          final engine = CustomerDeduplicationEngine();
          engine.seedCustomers([
            const Customer(
              id: 'CUST_ORIGINAL',
              name: 'Anh Nam',
              phone: '0908111222',
              email: '',
              address: '',
              purchases: [],
              currentDebt: 2000000.0,
            ),
          ]);

          const importedWithoutId = Customer(
            id: '',
            name: 'Anh Nam Gỗ',
            phone: '0908111222',
            email: 'nam@example.com',
            address: 'Bình Tân',
            purchases: [],
          );

          final result = await engine.importCustomers([importedWithoutId]);
          expect(result.updated, 1);
          expect(result.added, 0);
          final updated = engine.allCustomers.firstWhere((c) => c.phone == '0908111222');
          expect(updated.id, 'CUST_ORIGINAL');
          expect(updated.name, 'Anh Nam Gỗ');
          expect(updated.currentDebt, 2000000.0);
        });

        test('T2.8: Customer with missing phone matches existing customer by ID', () async {
          final engine = CustomerDeduplicationEngine();
          engine.seedCustomers([
            const Customer(
              id: 'CUST_007',
              name: 'Chị Mai',
              phone: '0918777888',
              email: '',
              address: '',
              purchases: [],
            ),
          ]);

          const importedWithoutPhone = Customer(
            id: 'CUST_007',
            name: 'Chị Mai Cần Thơ',
            phone: '',
            email: 'mai@example.com',
            address: 'Ninh Kiều',
            purchases: [],
          );

          final result = await engine.importCustomers([importedWithoutPhone]);
          expect(result.updated, 1);
          expect(result.added, 0);
          final updated = engine.allCustomers.firstWhere((c) => c.id == 'CUST_007');
          expect(updated.phone, '0918777888'); // Preserved original phone!
        });

        test('T2.9: Customer with both missing ID and missing phone increments error count', () async {
          final engine = CustomerDeduplicationEngine();
          const anonymousCustomer = Customer(
            id: '',
            name: 'Vãng lai không số',
            phone: '',
            email: '',
            address: '',
            purchases: [],
          );

          final result = await engine.importCustomers([anonymousCustomer]);
          expect(result.errors, 1);
          expect(result.added, 0);
        });

        test('T2.10: Invoice row with empty order ID increments error count and skips row', () async {
          final engine = InvoiceDeduplicationEngine();
          final badOrder = Order(
            id: '',
            customerId: 'KH01',
            createdAt: DateTime.now(),
            items: [],
            total: 1000.0,
            amountPaid: 1000.0,
            debtAmount: 0.0,
            paymentMethod: 'cash',
            createdBy: 'admin',
            storeId: 'store_001',
          );

          final result = await engine.importInvoices(
            importedOrders: [badOrder],
            targetStoreId: 'store_001',
          );

          expect(result.errors, 1);
          expect(result.added, 0);
          expect(engine.orders, isEmpty);
        });
      });

      // ----------------------------------------------------------------------
      // Boundary 3: Negative Debts & Extreme Numerics
      // ----------------------------------------------------------------------
      group('Boundary 3: Negative Debts & Extreme Numerics', () {
        test('T2.11: Customer with negative debt (credit balance/overpayment) preserved accurately', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH_OVERPAY',
              'name': 'Khách Trả Dư',
              'phone': '0909999999',
              'currentDebt': -1500000.0,
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.currentDebt, -1500000.0);
        });

        test('T2.12: Supplier with exactly 0.0 debt parsed as 0.0 without null coercion', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC_ZERO_DEBT',
              'name': 'Nhà Cung Cấp Hết Nợ',
              'currentDebt': 0.0,
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.currentDebt, 0.0);
          expect(suppliers.first.hasDebt, isFalse);
        });

        test('T2.13: Extreme financial values (100 billion VND) parsed without overflow', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD_MEGA',
              'total': 100000000000.0,
              'amountPaid': 100000000000.0,
            },
          ], isDetailed: false);

          final invoices = InvoiceExcelParser.parseInvoices(bytes);
          expect(invoices.length, 1);
          expect(invoices.first.total, 100000000000.0);
        });

        test('T2.14: Numeric strings with commas as thousands separators parsed cleanly', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH_COMMA_NUM',
              'name': 'Khách Số Có Dấu Phẩy',
              'currentDebt': 2500000.50,
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.currentDebt, 2500000.50);
        });

        test('T2.15: Product with 0 price and 0 cost price handled as valid free sample', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'SP_SAMPLE',
              'name': 'Hàng tặng kèm',
              'price': 0.0,
              'costPrice': 0.0,
              'stock': 100.0,
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.price, 0.0);
          expect(products.first.costPrice, 0.0);
        });
      });

      // ----------------------------------------------------------------------
      // Boundary 4: Malformed Dates & Serial Timestamps
      // ----------------------------------------------------------------------
      group('Boundary 4: Malformed Dates & Serial Timestamps', () {
        test('T2.16: Excel date serial double converts accurately to target date', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH_DATE_SERIAL',
              'name': 'Khách Date Serial',
              'createdAt': '2026-09-01T12:00:00Z',
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.createdAt, isNotEmpty);
        });

        test('T2.17: ISO 8601 formatted date string parsed cleanly into DateTime', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD_ISO_DATE',
              'createdAt': '2026-08-15T14:30:00.000',
              'total': 500000.0,
            },
          ], isDetailed: false);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 1);
          expect(orders.first.createdAt.year, 2026);
          expect(orders.first.createdAt.month, 8);
          expect(orders.first.createdAt.day, 15);
        });

        test('T2.18: Non-standard date string falls back safely without unhandled crash', () {
          final bytes = ExcelTestWorkbookBuilder.buildInvoiceSheet([
            {
              'orderId': 'HD_BAD_DATE',
              'createdAt': 'Ngày mai lúc 9 giờ sáng',
              'total': 100000.0,
            },
          ], isDetailed: false);

          final orders = InvoiceExcelParser.parseInvoices(bytes);
          expect(orders.length, 1);
          expect(orders.first.createdAt, isNotNull);
        });

        test('T2.19: Supplier creation date preserves valid string format', () {
          final bytes = ExcelTestWorkbookBuilder.buildSupplierSheet([
            {
              'code': 'NCC_DATES',
              'name': 'NCC Dates',
              'createdAt': '2026-01-01T00:00:00Z',
            },
          ]);

          final suppliers = SupplierExcelParser.parseSuppliers(bytes);
          expect(suppliers.length, 1);
          expect(suppliers.first.createdAt, contains('2026'));
        });

        test('T2.20: Customer birthdate (dob) string parsed cleanly', () {
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {
              'id': 'KH_DOB',
              'name': 'Khách Ngày Sinh',
              'dob': '1995-05-20',
            },
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.dob, '1995-05-20');
        });
      });

      // ----------------------------------------------------------------------
      // Boundary 5: Special Characters & Unicode Diacritics
      // ----------------------------------------------------------------------
      group('Boundary 5: Special Characters & Unicode Diacritics', () {
        test('T2.21: Complex Vietnamese diacritics in product names preserved 100%', () {
          const testName = 'Bàn ăn bên nguyên khối - chân vuông - 8 ghế đại tựa liền';
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {'code': 'SP_VIET', 'name': testName, 'price': 15000000.0},
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.name, testName);
        });

        test('T2.22: XML special characters (&, <, >, ", \') in customer details handled without corruption', () {
          const specialName = 'Công ty T&T <Thịnh & Vượng> "Số 1"';
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {'id': 'KH_XML', 'name': specialName, 'phone': '0988776655'},
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.name, specialName);
        });

        test('T2.23: Multi-line product descriptions containing linebreaks preserved', () {
          const desc = 'Dòng 1: Gỗ sồi Nga\nDòng 2: Phủ Nano chống trầy\nDòng 3: Bảo hành 2 năm';
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {'code': 'SP_MULTILINE', 'name': 'Kệ TV', 'description': desc},
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.description, desc);
        });

        test('T2.24: Address strings containing commas and semicolons parsed without shift', () {
          const address = 'Số 45, Đường 3/2, Phường Xuân Khánh; Quận Ninh Kiều, Cần Thơ';
          final bytes = ExcelTestWorkbookBuilder.buildCustomerSheet([
            {'id': 'KH_ADDR', 'name': 'Khách Địa Chỉ', 'address': address},
          ]);

          final customers = ExcelHelper.parseCustomers(bytes);
          expect(customers.length, 1);
          expect(customers.first.address, address);
        });

        test('T2.25: Category names with special slashes or punctuation parsed safely', () {
          final bytes = ExcelTestWorkbookBuilder.buildProductSheet([
            {
              'code': 'SP_CAT',
              'name': 'Bộ salon',
              'category3Levels': 'Đồ gỗ & Nội thất>>Phòng khách (VIP)>>Bàn ghế',
            },
          ]);

          final products = ExcelHelper.parseProducts(bytes);
          expect(products.length, 1);
          expect(products.first.category3Levels, 'Đồ gỗ & Nội thất>>Phòng khách (VIP)>>Bàn ghế');
          expect(products.first.category, 'Đồ gỗ & Nội thất');
        });
      });
    });

    // ========================================================================
    // TIER 3: PAIRWISE COMBINATIONS (DATA INTEGRITY & INVARIANTS)
    // ========================================================================
    group('TIER 3: Pairwise Combinations (Data Integrity & Invariants)', () {
      test('T3.1: Invoice Import: New invoice with multiple items deducts stock from target store', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'PROD_01',
            code: 'P01',
            name: 'Bàn Trà',
            price: 2000000.0,
            costPrice: 1200000.0,
            branchStocks: {'store_001': 10},
            category: 'Bàn',
          ),
          const Product(
            id: 'PROD_02',
            code: 'P02',
            name: 'Ghế Đơn',
            price: 500000.0,
            costPrice: 300000.0,
            branchStocks: {'store_001': 20},
            category: 'Ghế',
          ),
        ]);

        final order = Order(
          id: 'HD_PAIR_01',
          customerId: 'KH01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'PROD_01',
              productName: 'Bàn Trà',
              quantity: 3,
              price: 2000000.0,
              warrantyMonths: 12,
              purchaseDate: DateTime.now(),
            ),
            OrderItem(
              productId: 'PROD_02',
              productName: 'Ghế Đơn',
              quantity: 5,
              price: 500000.0,
              warrantyMonths: 12,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 8500000.0,
          amountPaid: 8500000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        final result = await engine.importInvoices(
          importedOrders: [order],
          targetStoreId: 'store_001',
        );

        expect(result.added, 1);
        expect(engine.products['prod_01']!.branchStocks['store_001'], 7); // 10 - 3 = 7
        expect(engine.products['prod_02']!.branchStocks['store_001'], 15); // 20 - 5 = 15
        expect(engine.transactions.length, 2);
        expect(engine.transactions.first.type, TransactionType.export);
      });

      test('T3.2: Invoice Import: Stock deduction clamps at 0 if ordered qty exceeds inventory', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'PROD_LOW',
            code: 'PLOW',
            name: 'Tủ Kính',
            price: 1000000.0,
            costPrice: 700000.0,
            branchStocks: {'store_001': 2},
            category: 'Tủ',
          ),
        ]);

        final order = Order(
          id: 'HD_OVERBUY',
          customerId: 'KH01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'PROD_LOW',
              productName: 'Tủ Kính',
              quantity: 5, // Ordered 5 when only 2 available
              price: 1000000.0,
              warrantyMonths: 0,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 5000000.0,
          amountPaid: 5000000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        await engine.importInvoices(
          importedOrders: [order],
          targetStoreId: 'store_001',
        );

        expect(engine.products['prod_low']!.branchStocks['store_001'], 0); // Clamped at 0
      });

      test('T3.3: Invoice Import: Invoice with debt links to customer and accrues debt balance', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedCustomers([
          const Customer(
            id: 'KH_DEBTOR',
            name: 'Khách Hàng Nợ',
            phone: '0901112233',
            email: '',
            address: '',
            purchases: [],
            currentDebt: 3000000.0,
            totalSales: 10000000.0,
          ),
        ]);

        final creditOrder = Order(
          id: 'HD_CREDIT_01',
          customerId: 'KH_DEBTOR',
          createdAt: DateTime.now(),
          items: [],
          total: 5000000.0,
          amountPaid: 2000000.0,
          debtAmount: 3000000.0, // 3 million remaining debt
          paymentMethod: 'transfer',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        await engine.importInvoices(
          importedOrders: [creditOrder],
          targetStoreId: 'store_001',
        );

        final updatedCustomer = engine.customers['kh_debtor']!;
        expect(updatedCustomer.currentDebt, 6000000.0); // 3M + 3M = 6M
        expect(updatedCustomer.totalSales, 15000000.0); // 10M + 5M = 15M
      });

      test('T3.4: Customer Import: Duplicate by ID updates contact info while PRESERVING debt', () async {
        final engine = CustomerDeduplicationEngine();
        engine.seedCustomers([
          const Customer(
            id: 'KH_EXISTING_01',
            name: 'Anh Tấn Cũ',
            phone: '0905556677',
            email: 'tan.old@example.com',
            address: 'Đông Thắng',
            purchases: [],
            currentDebt: 18500000.0, // Existing debt!
            totalSales: 45000000.0,
          ),
        ]);

        const importedCustomer = Customer(
          id: 'KH_EXISTING_01',
          name: 'Anh Tấn (Đã đổi tên)',
          phone: '0905556677',
          email: 'tan.new@example.com',
          address: 'Cần Thơ mới',
          purchases: [],
          currentDebt: 0.0, // Excel file states 0 debt!
        );

        final result = await engine.importCustomers([importedCustomer]);
        expect(result.updated, 1);
        expect(result.added, 0);

        final preserved = engine.allCustomers.firstWhere((c) => c.id == 'KH_EXISTING_01');
        expect(preserved.name, 'Anh Tấn (Đã đổi tên)');
        expect(preserved.email, 'tan.new@example.com');
        expect(preserved.address, 'Cần Thơ mới');
        // CRITICAL INVARIANT: Outstanding debt must NOT be erased by imported placeholder!
        expect(preserved.currentDebt, 18500000.0);
        expect(preserved.totalSales, 45000000.0);
      });

      test('T3.5: Customer Import: Duplicate by normalized phone PRESERVES current debt', () async {
        final engine = CustomerDeduplicationEngine();
        engine.seedCustomers([
          const Customer(
            id: 'KH_BY_PHONE',
            name: 'Chị Lan',
            phone: '0912888999',
            email: '',
            address: '',
            purchases: [],
            currentDebt: 7500000.0,
          ),
        ]);

        const importedWithNewId = Customer(
          id: 'KH_NEW_GENERATED_ID',
          name: 'Chị Lan Sỉ',
          phone: '+84 912 888 999', // Matches by phone!
          email: 'lan@example.com',
          address: 'Quận 5',
          purchases: [],
          currentDebt: 0.0,
        );

        final result = await engine.importCustomers([importedWithNewId]);
        expect(result.updated, 1);
        expect(result.added, 0);

        final preserved = engine.allCustomers.firstWhere((c) => c.phone == '0912888999');
        expect(preserved.id, 'KH_BY_PHONE'); // Kept original primary key!
        expect(preserved.name, 'Chị Lan Sỉ');
        expect(preserved.currentDebt, 7500000.0); // Preserved!
      });

      test('T3.6: Customer Import: Duplicate customer PRESERVES existing purchases history', () async {
        final engine = CustomerDeduplicationEngine();
        engine.seedCustomers([
          Customer(
            id: 'KH_WITH_PURCHASES',
            name: 'Bác Ba',
            phone: '0903334444',
            email: '',
            address: '',
            purchases: [
              Purchase(
                productId: 'PROD_HISTORIC',
                quantity: 2,
                purchaseDate: DateTime(2025, 1, 1),
                warranty: Warranty(
                  months: 12,
                  expireDate: DateTime(2026, 1, 1),
                ),
              ),
            ],
          ),
        ]);

        const reImported = Customer(
          id: 'KH_WITH_PURCHASES',
          name: 'Bác Ba Phi',
          phone: '0903334444',
          email: 'ba@example.com',
          address: 'Cà Mau',
          purchases: [], // Excel import contains empty purchases list!
        );

        await engine.importCustomers([reImported]);
        final updated = engine.allCustomers.firstWhere((c) => c.id == 'KH_WITH_PURCHASES');
        expect(updated.purchases.length, 1);
        expect(updated.purchases.first.productId, 'PROD_HISTORIC');
      });

      test('T3.7: Supplier Import: Duplicate by code updates contact info while PRESERVING debt', () async {
        final engine = SupplierDeduplicationEngine();
        engine.seedSuppliers([
          const Supplier(
            id: 'NCC_LONG_AN',
            code: 'NCC_LONG_AN',
            name: 'Gỗ Long An Cũ',
            phone: '0272333444',
            email: 'la.old@example.com',
            address: 'Tân An',
            currentDebt: 32000000.0, // Existing accounts payable!
            totalPurchase: 120000000.0,
          ),
        ]);

        const importedSupplier = Supplier(
          id: 'NCC_LONG_AN',
          code: 'NCC_LONG_AN',
          name: 'Công ty Cổ Phần Gỗ Long An Mới',
          phone: '0272333444',
          email: 'contact@golongan.vn',
          address: 'Tân An, Long An',
          currentDebt: 0.0, // Excel says 0!
          totalPurchase: 0.0,
        );

        final result = await engine.importSuppliers([importedSupplier]);
        expect(result.updated, 1);
        expect(result.added, 0);

        final updated = engine.allSuppliers.firstWhere((s) => s.code == 'NCC_LONG_AN');
        expect(updated.name, 'Công ty Cổ Phần Gỗ Long An Mới');
        expect(updated.email, 'contact@golongan.vn');
        // CRITICAL: Accounts payable balance must NOT be clobbered!
        expect(updated.currentDebt, 32000000.0);
        expect(updated.totalPurchase, 120000000.0);
      });

      test('T3.8: Supplier Import: Duplicate by phone matches and preserves balances', () async {
        final engine = SupplierDeduplicationEngine();
        engine.seedSuppliers([
          const Supplier(
            id: 'NCC_P1',
            code: 'NCC_P1',
            name: 'Cơ khí Sài Gòn',
            phone: '0987654321',
            currentDebt: 14000000.0,
          ),
        ]);

        const importedByPhone = Supplier(
          id: 'NCC_NEW_CODE',
          code: 'NCC_NEW_CODE',
          name: 'Cơ khí Sài Gòn Mới',
          phone: '0987654321',
          currentDebt: 0.0,
        );

        final result = await engine.importSuppliers([importedByPhone]);
        expect(result.updated, 1);
        expect(result.added, 0);

        final updated = engine.allSuppliers.firstWhere((s) => s.phone == '0987654321');
        expect(updated.currentDebt, 14000000.0);
      });

      test('T3.9: Invoice Duplicate Skipping: Re-importing existing invoice ID is strictly SKIPPED', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedOrders([
          Order(
            id: 'HD_IMMUTABLE_01',
            customerId: 'KH01',
            createdAt: DateTime(2026, 9, 1),
            items: [],
            total: 5000000.0,
            amountPaid: 5000000.0,
            debtAmount: 0.0,
            paymentMethod: 'cash',
            createdBy: 'admin',
            storeId: 'store_001',
          ),
        ]);

        final reImportOrder = Order(
          id: 'HD_IMMUTABLE_01',
          customerId: 'KH01',
          createdAt: DateTime(2026, 9, 1),
          items: [],
          total: 99999999.0, // Modified data in imported row
          amountPaid: 99999999.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        final result = await engine.importInvoices(
          importedOrders: [reImportOrder],
          targetStoreId: 'store_001',
        );

        expect(result.skipped, 1);
        expect(result.added, 0);
        // Original order was NOT touched!
        expect(engine.orders['hd_immutable_01']!.total, 5000000.0);
      });

      test('T3.10: Invoice Duplicate Skipping: Skipped invoice does NOT decrement stock a second time', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'P_STOCK_SAFE',
            code: 'PSS',
            name: 'Bàn Tròn',
            price: 1000.0,
            costPrice: 500.0,
            branchStocks: {'store_001': 10},
            category: 'Bàn',
          ),
        ]);

        engine.seedOrders([
          Order(
            id: 'HD_PROCESSED_ONCE',
            customerId: 'KH01',
            createdAt: DateTime.now(),
            items: [
              OrderItem(
                productId: 'P_STOCK_SAFE',
                productName: 'Bàn Tròn',
                quantity: 4,
                price: 1000.0,
                warrantyMonths: 0,
                purchaseDate: DateTime.now(),
              ),
            ],
            total: 4000.0,
            amountPaid: 4000.0,
            debtAmount: 0.0,
            paymentMethod: 'cash',
            createdBy: 'admin',
            storeId: 'store_001',
          ),
        ]);

        final duplicateOrder = Order(
          id: 'HD_PROCESSED_ONCE',
          customerId: 'KH01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'P_STOCK_SAFE',
              productName: 'Bàn Tròn',
              quantity: 4,
              price: 1000.0,
              warrantyMonths: 0,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 4000.0,
          amountPaid: 4000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        await engine.importInvoices(
          importedOrders: [duplicateOrder],
          targetStoreId: 'store_001',
        );

        // Stock remains 10 (no second decrement)
        expect(engine.products['p_stock_safe']!.branchStocks['store_001'], 10);
        expect(engine.transactions, isEmpty);
      });

      test('T3.11: Product Import Deduplication: Duplicate by code strictly PRESERVES branchStocks', () async {
        final engine = ProductDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'PROD_STOCK_TEST',
            code: 'SP_STOCK_TEST',
            name: 'Ghế Thư Giãn Cũ',
            price: 1200000.0,
            costPrice: 800000.0,
            branchStocks: {
              'store_001': 25, // Real physical counted stock!
              'store_002': 14,
            },
            category: 'Ghế',
          ),
        ]);

        const importedProduct = Product(
          id: 'PROD_STOCK_TEST',
          code: 'SP_STOCK_TEST',
          name: 'Ghế Thư Giãn (Giá mới)',
          price: 1350000.0, // New updated price
          costPrice: 900000.0,
          branchStocks: {'store_001': 999}, // Stale Excel stock count
          category: 'Ghế Gỗ',
        );

        final result = await engine.importProducts(
          importedProducts: [importedProduct],
          targetStoreId: 'store_001',
        );

        expect(result.updated, 1);
        expect(result.added, 0);

        final updated = engine.database['prod_stock_test']!;
        expect(updated.name, 'Ghế Thư Giãn (Giá mới)');
        expect(updated.price, 1350000.0);
        // CRITICAL INVARIANT: Physical stock must NOT be clobbered by Excel!
        expect(updated.branchStocks['store_001'], 25);
        expect(updated.branchStocks['store_002'], 14);
      });

      test('T3.12: Product Import Deduplication: Duplicate by code strictly PRESERVES imageUrl', () async {
        final engine = ProductDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'P_IMG_TEST',
            code: 'P_IMG_TEST',
            name: 'Kệ Sách Gỗ',
            price: 800000.0,
            costPrice: 500000.0,
            branchStocks: {},
            category: 'Kệ',
            imageUrl: 'https://cdn.example.com/ke_sach_vip.png',
          ),
        ]);

        const importedProduct = Product(
          id: 'P_IMG_TEST',
          code: 'P_IMG_TEST',
          name: 'Kệ Sách Gỗ 4 Tầng',
          price: 850000.0,
          costPrice: 500000.0,
          branchStocks: {},
          category: 'Kệ',
          imageUrl: null, // Excel row has no image!
        );

        await engine.importProducts(
          importedProducts: [importedProduct],
          targetStoreId: 'store_001',
        );

        final updated = engine.database['p_img_test']!;
        expect(updated.imageUrl, 'https://cdn.example.com/ke_sach_vip.png');
      });
    });

    // ========================================================================
    // TIER 4: REAL-WORLD SCENARIOS
    // ========================================================================
    group('TIER 4: Real-World Scenarios', () {
      test('T4.1: Batch Import Lifecycle: End-to-end multi-entity migration', () async {
        // Step 1: Import products with initial stock
        final prodEngine = ProductDeduplicationEngine();
        const p1 = Product(
          id: 'SP001',
          code: 'SP001',
          name: 'Bộ Bàn Ăn 6 Ghế',
          price: 8000000.0,
          costPrice: 5500000.0,
          branchStocks: {'store_001': 5},
          category: 'Bàn Ăn',
        );
        final prodRes = await prodEngine.importProducts(
          importedProducts: [p1],
          targetStoreId: 'store_001',
        );
        expect(prodRes.added, 1);
        expect(prodEngine.transactions.first.type, TransactionType.import);

        // Step 2: Import suppliers
        final suppEngine = SupplierDeduplicationEngine();
        const s1 = Supplier(
          id: 'NCC_MIGRATE_01',
          code: 'NCC_MIGRATE_01',
          name: 'Tổng Kho Nội Thất Đồng Nai',
          phone: '02513999888',
          currentDebt: 45000000.0,
        );
        final suppRes = await suppEngine.importSuppliers([s1]);
        expect(suppRes.added, 1);

        // Step 3: Import customers
        final custEngine = CustomerDeduplicationEngine();
        const c1 = Customer(
          id: 'KH_MIGRATE_01',
          name: 'Khách Hàng Dự Án',
          phone: '0908889999',
          email: 'duan@example.com',
          address: 'Khu Đô Thị Mới',
          purchases: [],
        );
        final custRes = await custEngine.importCustomers([c1]);
        expect(custRes.added, 1);

        // Step 4: Import invoice consuming product and linking customer
        final invEngine = InvoiceDeduplicationEngine();
        invEngine.seedProducts(prodEngine.database.values.toList());
        invEngine.seedCustomers(custEngine.allCustomers);

        final order = Order(
          id: 'HD_MIGRATE_01',
          customerId: 'KH_MIGRATE_01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Bộ Bàn Ăn 6 Ghế',
              quantity: 2,
              price: 8000000.0,
              warrantyMonths: 24,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 16000000.0,
          amountPaid: 10000000.0,
          debtAmount: 6000000.0,
          paymentMethod: 'split',
          createdBy: 'admin',
          storeId: 'store_001',
        );

        final invRes = await invEngine.importInvoices(
          importedOrders: [order],
          targetStoreId: 'store_001',
        );

        expect(invRes.added, 1);
        expect(invEngine.products['sp001']!.branchStocks['store_001'], 3); // 5 - 2 = 3
        expect(invEngine.customers['kh_migrate_01']!.currentDebt, 6000000.0);
        expect(invEngine.transactions.first.type, TransactionType.export);
      });

      test('T4.2: Summary Format: All new records outputs exact template', () {
        const result = ImportResult(total: 5, added: 5, updated: 0, skipped: 0, errors: 0);
        expect(result.toSummaryString(),
            'Tổng số dòng: 5 | Thêm mới: 5 | Cập nhật: 0 | Bỏ qua: 0 | Lỗi: 0');
      });

      test('T4.3: Summary Format: All updated records outputs exact template', () {
        const result = ImportResult(total: 3, added: 0, updated: 3, skipped: 0, errors: 0);
        expect(result.toSummaryString(),
            'Tổng số dòng: 3 | Thêm mới: 0 | Cập nhật: 3 | Bỏ qua: 0 | Lỗi: 0');
      });

      test('T4.4: Summary Format: All skipped records outputs exact template', () {
        const result = ImportResult(total: 4, added: 0, updated: 0, skipped: 4, errors: 0);
        expect(result.toSummaryString(),
            'Tổng số dòng: 4 | Thêm mới: 0 | Cập nhật: 0 | Bỏ qua: 4 | Lỗi: 0');
      });

      test('T4.5: Summary Format: Mixed additions, updates, skips, and errors matches template', () {
        const result = ImportResult(total: 20, added: 12, updated: 5, skipped: 2, errors: 1);
        expect(result.toSummaryString(),
            'Tổng số dòng: 20 | Thêm mới: 12 | Cập nhật: 5 | Bỏ qua: 2 | Lỗi: 1');
      });

      test('T4.6: Multi-Branch Segregation: Importing stock into store_001 leaves store_002 unaffected', () async {
        final engine = ProductDeduplicationEngine();
        const p = Product(
          id: 'P_BRANCH_ISO',
          code: 'P_BRANCH_ISO',
          name: 'Giường Gỗ Sồi',
          price: 7000000.0,
          costPrice: 4500000.0,
          branchStocks: {'store_001': 10},
          category: 'Giường',
        );

        await engine.importProducts(
          importedProducts: [p],
          targetStoreId: 'store_001',
        );

        final saved = engine.database['p_branch_iso']!;
        expect(saved.branchStocks['store_001'], 10);
        expect(saved.branchStocks['store_002'], isNull);
      });

      test('T4.7: Multi-Branch Segregation: Invoice processed for store_002 deducts store_002 inventory only', () async {
        final engine = InvoiceDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'P_MULTI_BRANCH',
            code: 'PMB',
            name: 'Bàn Học Sinh',
            price: 1500000.0,
            costPrice: 900000.0,
            branchStocks: {
              'store_001': 20,
              'store_002': 15,
            },
            category: 'Bàn',
          ),
        ]);

        final orderStore2 = Order(
          id: 'HD_STORE_002',
          customerId: 'KH01',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'P_MULTI_BRANCH',
              productName: 'Bàn Học Sinh',
              quantity: 5,
              price: 1500000.0,
              warrantyMonths: 0,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 7500000.0,
          amountPaid: 7500000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          createdBy: 'admin',
          storeId: 'store_002',
        );

        await engine.importInvoices(
          importedOrders: [orderStore2],
          targetStoreId: 'store_002',
        );

        final p = engine.products['p_multi_branch']!;
        expect(p.branchStocks['store_001'], 20); // store_001 untouched!
        expect(p.branchStocks['store_002'], 10); // 15 - 5 = 10
      });

      test('T4.8: Multi-Branch Segregation: Multiple stores retain isolated branch stock maps on duplicate updates', () async {
        final engine = ProductDeduplicationEngine();
        engine.seedProducts([
          const Product(
            id: 'P_MULTI_MAP',
            code: 'PMM',
            name: 'Tủ Quần Áo',
            price: 6000000.0,
            costPrice: 4000000.0,
            branchStocks: {
              'store_001': 8,
              'store_002': 12,
              'store_003': 3,
            },
            category: 'Tủ',
          ),
        ]);

        const updatedProduct = Product(
          id: 'P_MULTI_MAP',
          code: 'PMM',
          name: 'Tủ Quần Áo Gỗ Công Nghiệp (Mới)',
          price: 6500000.0,
          costPrice: 4200000.0,
          branchStocks: {'store_001': 99}, // Stale Excel
          category: 'Tủ Quần Áo',
        );

        await engine.importProducts(
          importedProducts: [updatedProduct],
          targetStoreId: 'store_001',
        );

        final p = engine.database['p_multi_map']!;
        expect(p.name, 'Tủ Quần Áo Gỗ Công Nghiệp (Mới)');
        expect(p.branchStocks['store_001'], 8);
        expect(p.branchStocks['store_002'], 12);
        expect(p.branchStocks['store_003'], 3);
      });
    });
  });
}
