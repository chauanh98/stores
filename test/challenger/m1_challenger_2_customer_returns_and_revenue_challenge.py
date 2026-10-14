#!/usr/bin/env python3
"""
m1_challenger_2_customer_returns_and_revenue_challenge.py
Adversarial Verification Suite for Milestone 1 Iteration 2 Data Ingestion.

Authored by M1 Iteration 2 Challenger 2 (Empirical Challenger).
Independently verifies:
1. Customer Returns Invariants & Anti-Corruption:
   - Deep inspection of data_staging/output/store_002_returns.json
   - Exactly 2 return slips: TH000041 (2.7M VNĐ) and TH000040 (2.6M VNĐ)
   - Grand total = exactly 5,300,000.0 VNĐ
   - Genuine items GD5 and NDL24 (both present in catalog, positive prices and line totals)
   - Valid customer IDs KH004685 and KH006010 (both present in shared_customers)
   - Status == "Đã trả"
   - Absolute absence of corrupted strings:
     - No "Đã trả" as productId
     - No "0" as status
     - No "Khánh Đăng" as customerId
     - No "KH004685" as customerName
     - No 0.0 total
   - Cross-check against raw OpenXML ground truth (both export files)
2. Referential Integrity & Historical Invariants:
   - TH000041 links to existing invoice HD012225 (matched customer, item, amount, time within 60s)
   - TH000040 links to historical invoice HD011315 (prior to export start window HD011402)
   - Synthetic stubs TTTR6, XD6, NDL26 validated with zero stock and inactive status
   - Zero foreign key orphan SKUs across all transactions and returns
3. Revenue Invariants:
   - Store 001: 132 orders, active net revenue = 639,515,000.00 VNĐ
   - Store 002: 1,943 orders, active net revenue = 9,931,034,200.00 VNĐ
   - Combined: 2,075 orders, active net revenue = 10,570,549,200.00 VNĐ
   - Post-return net revenue calculation: 10,565,249,200.00 VNĐ
4. Timestamp Integrity & Anti-Drift:
   - 100% of 2,075 orders derived strictly from Column 2 ("Thời gian")
   - Zero month drift and zero date drift
   - 203 orders with non-empty Col 4 and 144 orders with Col 3 divergence verified
5. Customer & Supplier Debt Invariants:
   - Customer debt = 33,684,023,744.00 VNĐ (7,007 raw + 1 stub)
   - Supplier debt = 23,259,824,240.00 VNĐ (50 raw + 1 stub)
"""

import os
import sys
import json
import zipfile
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from decimal import Decimal
from collections import defaultdict

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_IMPORT_DIR = os.path.join(WORKSPACE_DIR, 'DATA_IMPORT')
OUTPUT_DIR = os.path.join(WORKSPACE_DIR, 'data_staging', 'output')

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

def col2idx(c_str):
    idx = 0
    for ch in c_str:
        idx = idx * 26 + (ord(ch) - ord('A') + 1)
    return idx - 1

def parse_cell_ref(ref):
    m = re.match(r'^([A-Z]+)([0-9]+)$', ref)
    if not m:
        return 0, 0
    c_str, r_str = m.groups()
    return int(r_str) - 1, col2idx(c_str)

def read_raw_excel_sheet(xlsx_path, preferred_sheets=('xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml')):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        shared_strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            sroot = ET.fromstring(z.read('xl/sharedStrings.xml'))
            for si in sroot.findall(f'.//{NS}si'):
                t = si.find(f'{NS}t')
                shared_strings.append(t.text if t is not None and t.text else '')

        sheet_xml = None
        for s in preferred_sheets:
            if s in z.namelist():
                sheet_xml = z.read(s)
                break
        if sheet_xml is None:
            for n in z.namelist():
                if n.startswith('xl/worksheets/sheet') and n.endswith('.xml'):
                    sheet_xml = z.read(n)
                    break
        if sheet_xml is None:
            raise FileNotFoundError(f"Worksheet not found in {xlsx_path}")

        root = ET.fromstring(sheet_xml)
        for r_elem in root.findall(f'.//{NS}row'):
            row_dict = {}
            for c_elem in r_elem.findall(f'{NS}c'):
                r_ref = c_elem.get('r')
                if not r_ref:
                    continue
                _, c_idx = parse_cell_ref(r_ref)
                t_attr = c_elem.get('t')
                v_elem = c_elem.find(f'{NS}v')
                val = v_elem.text.strip() if v_elem is not None and v_elem.text is not None else ''
                if t_attr == 's' and val.isdigit() and int(val) < len(shared_strings):
                    val = shared_strings[int(val)]
                row_dict[c_idx] = val
            yield row_dict

def serial_to_iso(serial_val):
    if not serial_val:
        return None
    s = str(serial_val).strip()
    if not s:
        return None
    try:
        serial = float(s)
        base = datetime(1899, 12, 30)
        days = int(serial)
        seconds = round((serial - days) * 86400)
        dt = base + timedelta(days=days, seconds=seconds)
        return dt.strftime('%Y-%m-%dT%H:%M:%S.000')
    except ValueError:
        m = re.match(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{1,2}))?$', s)
        if m:
            d, mo, y, h, mi = m.groups()
            dt = datetime(int(y), int(mo), int(d), int(h or 0), int(mi or 0))
            return dt.strftime('%Y-%m-%dT%H:%M:%S.000')
        return s

def sanitize_key(k):
    return re.sub(r'[\.\$#\[\]/\x00-\x1f\x7f]', '_', str(k).strip())

class ChallengerReturnsAndRevenueHarness:
    def __init__(self):
        self.passed_checks = 0
        self.failed_checks = 0
        self.discrepancies = []

    def check(self, name, condition, details=""):
        if condition:
            self.passed_checks += 1
            print(f"  [PASS] {name}" + (f" -> {details}" if details else ""))
        else:
            self.failed_checks += 1
            msg = f"[FAIL] {name}" + (f" -> {details}" if details else "")
            self.discrepancies.append(msg)
            print(f"  {msg}")

    def run_all(self):
        print("=" * 80)
        print("M1 ITERATION 2 CHALLENGER 2: ADVERSARIAL CUSTOMER RETURNS & REVENUE TEST")
        print("=" * 80)

        # -------------------------------------------------------------
        # SUITE 1: RAW OPENXML CUSTOMER RETURNS EXTRACTION FROM FIRST PRINCIPLES
        # -------------------------------------------------------------
        print("\n--- SUITE 1: Raw OpenXML Customer Returns Ground Truth Extraction ---")
        ret_file_1 = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietTraHang_KV09102026-211147-871.xlsx')
        ret_file_2 = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietTraHang_KV09102026-210750-582.xlsx')
        self.check("Returns raw Excel file 1 exists", os.path.isfile(ret_file_1), ret_file_1)
        self.check("Returns raw Excel file 2 exists", os.path.isfile(ret_file_2), ret_file_2)

        raw_returns_1 = list(read_raw_excel_sheet(ret_file_1))
        raw_returns_2 = list(read_raw_excel_sheet(ret_file_2))

        self.check("Excel file 1 total rows (header + data)", len(raw_returns_1) == 3, f"{len(raw_returns_1)} rows")
        self.check("Excel file 2 total rows (header + data)", len(raw_returns_2) == 3, f"{len(raw_returns_2)} rows")
        self.check("Both returns Excel files are byte/data identical", raw_returns_1 == raw_returns_2)

        # Parse header row
        header = raw_returns_1[0]
        self.check("Col 1 header is 'Mã trả hàng'", header.get(1) == 'Mã trả hàng')
        self.check("Col 4 header is 'Mã hóa đơn'", header.get(4) == 'Mã hóa đơn')
        self.check("Col 5 header is 'Mã vận đơn bán'", header.get(5) == 'Mã vận đơn bán')
        self.check("Col 6 header is 'Mã vận đơn trả'", header.get(6) == 'Mã vận đơn trả')
        self.check("Col 7 header is 'Người bán'", header.get(7) == 'Người bán')
        self.check("Col 8 header is 'Mã khách hàng'", header.get(8) == 'Mã khách hàng')
        self.check("Col 9 header is 'Tên khách hàng'", header.get(9) == 'Tên khách hàng')
        self.check("Col 16 header is 'Tổng sau giảm giá'", header.get(16) == 'Tổng sau giảm giá')
        self.check("Col 26 header is 'Trạng thái'", header.get(26) == 'Trạng thái')
        self.check("Col 27 header is 'Mã hàng'", header.get(27) == 'Mã hàng')
        self.check("Col 29 header is 'Tên hàng'", header.get(29) == 'Tên hàng')
        self.check("Col 33 header is 'Số lượng'", header.get(33) == 'Số lượng')
        self.check("Col 37 header is 'Giá nhập lại'", header.get(37) == 'Giá nhập lại')

        # Parse data rows
        row1 = raw_returns_1[1]
        row2 = raw_returns_1[2]

        # Row 1 ground truth: TH000041
        self.check("Row 1 code is TH000041", row1.get(1) == 'TH000041')
        self.check("Row 1 branch is 'Chi nhánh Thới Bình'", row1.get(0) == 'Chi nhánh Thới Bình')
        self.check("Row 1 invoice is HD012225", row1.get(4) == 'HD012225')
        self.check("Row 1 customerId is KH004685", row1.get(8) == 'KH004685')
        self.check("Row 1 customerName is 'Kim Ngọc'", row1.get(9) == 'Kim Ngọc')
        self.check("Row 1 total is 2,700,000.0 VNĐ", Decimal(row1.get(16)) == Decimal('2700000.0000'))
        self.check("Row 1 status is 'Đã trả'", row1.get(26) == 'Đã trả')
        self.check("Row 1 productId is GD5", row1.get(27) == 'GD5')
        self.check("Row 1 productName is 'Ghế dây căm xe'", row1.get(29) == 'Ghế dây căm xe')
        self.check("Row 1 quantity is 1", int(row1.get(33)) == 1)
        self.check("Row 1 price is 2,700,000.0 VNĐ", Decimal(row1.get(37)) == Decimal('2700000.0000'))

        # Row 2 ground truth: TH000040
        self.check("Row 2 code is TH000040", row2.get(1) == 'TH000040')
        self.check("Row 2 branch is 'Chi nhánh Thới Bình'", row2.get(0) == 'Chi nhánh Thới Bình')
        self.check("Row 2 invoice is HD011315", row2.get(4) == 'HD011315')
        self.check("Row 2 customerId is KH006010", row2.get(8) == 'KH006010')
        self.check("Row 2 customerName is 'Chị Do'", row2.get(9) == 'Chị Do')
        self.check("Row 2 total is 2,600,000.0 VNĐ", Decimal(row2.get(16)) == Decimal('2600000.0000'))
        self.check("Row 2 status is 'Đã trả'", row2.get(26) == 'Đã trả')
        self.check("Row 2 productId is NDL24", row2.get(27) == 'NDL24')
        self.check("Row 2 productName is 'Tủ nhựa ĐL 1m6 x C1m6'", row2.get(29) == 'Tủ nhựa ĐL 1m6 x C1m6')
        self.check("Row 2 quantity is 1", int(row2.get(33)) == 1)
        self.check("Row 2 price is 2,600,000.0 VNĐ", Decimal(row2.get(37)) == Decimal('2600000.0000'))

        raw_total_return = Decimal(row1.get(16)) + Decimal(row2.get(16))
        self.check("Raw returns grand total = exactly 5,300,000.00 VNĐ",
                   raw_total_return == Decimal('5300000.0000'),
                   f"{raw_total_return:,.2f} VNĐ")

        # -------------------------------------------------------------
        # SUITE 2: DEEP STAGED CUSTOMER RETURNS INSPECTION & ANTI-CORRUPTION
        # -------------------------------------------------------------
        print("\n--- SUITE 2: Deep Staged Customer Returns Inspection & Anti-Corruption ---")
        returns_json_path = os.path.join(OUTPUT_DIR, 'store_002_returns.json')
        self.check("store_002_returns.json exists", os.path.isfile(returns_json_path), returns_json_path)

        with open(returns_json_path, 'r', encoding='utf-8') as f:
            staged_returns = json.load(f)

        self.check("store_002_returns has exactly 2 return receipts", len(staged_returns) == 2, f"{len(staged_returns)} receipts")
        self.check("Return IDs match {'TH000041', 'TH000040'}", set(staged_returns.keys()) == {'TH000041', 'TH000040'})

        # Confirm no customer returns for store_001
        s1_returns_json = os.path.join(OUTPUT_DIR, 'store_001_returns.json')
        self.check("store_001 has no customer return orders file (zero returns at branch 001)",
                   not os.path.exists(s1_returns_json) or len(json.load(open(s1_returns_json))) == 0)

        # Deep inspection of TH000041
        ret41 = staged_returns.get('TH000041')
        self.check("TH000041: receipt exists", ret41 is not None)
        self.check("TH000041: storeId == 'store_002'", ret41.get('storeId') == 'store_002')
        self.check("TH000041: invoiceId == 'HD012225'", ret41.get('invoiceId') == 'HD012225')
        self.check("TH000041: orderId == 'HD012225'", ret41.get('orderId') == 'HD012225')
        self.check("TH000041: customerId == 'KH004685'", ret41.get('customerId') == 'KH004685')
        self.check("TH000041: customerName == 'Kim Ngọc'", ret41.get('customerName') == 'Kim Ngọc')
        self.check("TH000041: seller == 'Khánh Đăng'", ret41.get('seller') == 'Khánh Đăng')
        self.check("TH000041: total == 2,700,000.0 VNĐ", ret41.get('total') == 2700000.0)
        self.check("TH000041: totalReturnAmount == 2,700,000.0 VNĐ", ret41.get('totalReturnAmount') == 2700000.0)
        self.check("TH000041: totalRefund == 2,700,000.0 VNĐ", ret41.get('totalRefund') == 2700000.0)
        self.check("TH000041: cashRefunded == 2,700,000.0 VNĐ", ret41.get('cashRefunded') == 2700000.0)
        self.check("TH000041: status == 'Đã trả'", ret41.get('status') == 'Đã trả')
        self.check("TH000041: date == '2026-04-13T08:16:59.000'", ret41.get('date') == '2026-04-13T08:16:59.000')
        self.check("TH000041: items list length == 1", len(ret41.get('items', [])) == 1)
        item41 = ret41['items'][0]
        self.check("TH000041: item productId == 'GD5'", item41.get('productId') == 'GD5')
        self.check("TH000041: item productName == 'Ghế dây căm xe'", item41.get('productName') == 'Ghế dây căm xe')
        self.check("TH000041: item quantity == 1", item41.get('quantity') == 1)
        self.check("TH000041: item price == 2,700,000.0 VNĐ", item41.get('price') == 2700000.0)
        self.check("TH000041: item total == 2,700,000.0 VNĐ", item41.get('total') == 2700000.0)

        # Deep inspection of TH000040
        ret40 = staged_returns.get('TH000040')
        self.check("TH000040: receipt exists", ret40 is not None)
        self.check("TH000040: storeId == 'store_002'", ret40.get('storeId') == 'store_002')
        self.check("TH000040: invoiceId == 'HD011315'", ret40.get('invoiceId') == 'HD011315')
        self.check("TH000040: orderId == 'HD011315'", ret40.get('orderId') == 'HD011315')
        self.check("TH000040: customerId == 'KH006010'", ret40.get('customerId') == 'KH006010')
        self.check("TH000040: customerName == 'Chị Do'", ret40.get('customerName') == 'Chị Do')
        self.check("TH000040: seller == 'Khánh Đăng'", ret40.get('seller') == 'Khánh Đăng')
        self.check("TH000040: total == 2,600,000.0 VNĐ", ret40.get('total') == 2600000.0)
        self.check("TH000040: totalReturnAmount == 2,600,000.0 VNĐ", ret40.get('totalReturnAmount') == 2600000.0)
        self.check("TH000040: totalRefund == 2,600,000.0 VNĐ", ret40.get('totalRefund') == 2600000.0)
        self.check("TH000040: cashRefunded == 0.0 VNĐ", ret40.get('cashRefunded') == 0.0)
        self.check("TH000040: status == 'Đã trả'", ret40.get('status') == 'Đã trả')
        self.check("TH000040: date == '2026-01-04T14:44:04.000'", ret40.get('date') == '2026-01-04T14:44:04.000')
        self.check("TH000040: items list length == 1", len(ret40.get('items', [])) == 1)
        item40 = ret40['items'][0]
        self.check("TH000040: item productId == 'NDL24'", item40.get('productId') == 'NDL24')
        self.check("TH000040: item productName == 'Tủ nhựa ĐL 1m6 x C1m6'", item40.get('productName') == 'Tủ nhựa ĐL 1m6 x C1m6')
        self.check("TH000040: item quantity == 1", item40.get('quantity') == 1)
        self.check("TH000040: item price == 2,600,000.0 VNĐ", item40.get('price') == 2600000.0)
        self.check("TH000040: item total == 2,600,000.0 VNĐ", item40.get('total') == 2600000.0)

        # Anti-corruption stress checks
        for ret_id, r_obj in staged_returns.items():
            self.check(f"{ret_id}: total > 0 (not zero/corrupted)", r_obj.get('total', 0) > 0)
            self.check(f"{ret_id}: status != '0'", r_obj.get('status') != '0')
            self.check(f"{ret_id}: customerId != 'Khánh Đăng' (seller is not customer)", r_obj.get('customerId') != 'Khánh Đăng')
            self.check(f"{ret_id}: customerId != 'Kim Ngọc' (name is not id)", r_obj.get('customerId') != 'Kim Ngọc')
            self.check(f"{ret_id}: customerId != 'Chị Do' (name is not id)", r_obj.get('customerId') != 'Chị Do')
            for itm in r_obj.get('items', []):
                self.check(f"{ret_id}: item.productId != 'Đã trả' (status not as product)", itm.get('productId') != 'Đã trả')
                self.check(f"{ret_id}: item.productId != '0'", itm.get('productId') != '0')
                self.check(f"{ret_id}: item.price > 0", itm.get('price', 0) > 0)
                self.check(f"{ret_id}: item.total > 0", itm.get('total', 0) > 0)

        staged_returns_sum = sum(r['total'] for r in staged_returns.values())
        self.check("Staged returns total == exactly 5,300,000.0 VNĐ", staged_returns_sum == 5300000.0, f"{staged_returns_sum:,.2f} VNĐ")

        # -------------------------------------------------------------
        # SUITE 3: CROSS-ENTITY REFERENTIAL INTEGRITY AUDIT
        # -------------------------------------------------------------
        print("\n--- SUITE 3: Cross-Entity Referential Integrity Audit ---")
        with open(os.path.join(OUTPUT_DIR, 'shared_customers.json'), 'r', encoding='utf-8') as f:
            customers = json.load(f)
        with open(os.path.join(OUTPUT_DIR, 'products_all.json'), 'r', encoding='utf-8') as f:
            products = json.load(f)
        with open(os.path.join(OUTPUT_DIR, 'store_001_tx.json'), 'r', encoding='utf-8') as f:
            tx1 = json.load(f)
        with open(os.path.join(OUTPUT_DIR, 'store_002_tx.json'), 'r', encoding='utf-8') as f:
            tx2 = json.load(f)
        with open(os.path.join(OUTPUT_DIR, 'store_002_orders.json'), 'r', encoding='utf-8') as f:
            orders2 = json.load(f)

        # 3.1 Return Customers exist in shared_customers
        self.check("KH004685 exists in shared_customers.json", 'KH004685' in customers)
        self.check("KH006010 exists in shared_customers.json", 'KH006010' in customers)
        self.check("KH004685 customer name matches 'Kim Ngọc'", customers['KH004685']['name'] == 'Kim Ngọc')
        self.check("KH006010 customer name matches 'Chị Do'", customers['KH006010']['name'] == 'Chị Do')

        # 3.2 Return Products exist in products_all
        self.check("GD5 exists in products_all.json", 'GD5' in products)
        self.check("NDL24 exists in products_all.json", 'NDL24' in products)
        self.check("GD5 product is active and sellable", products['GD5']['status'] == 'active' and products['GD5']['allowSale'])
        self.check("NDL24 product is active and sellable", products['NDL24']['status'] == 'active' and products['NDL24']['allowSale'])
        self.check("GD5 name is 'Ghế dây căm xe'", products['GD5']['name'] == 'Ghế dây căm xe')
        self.check("NDL24 name is 'Tủ nhựa ĐL 1m6 x C1m6'", products['NDL24']['name'] == 'Tủ nhựa ĐL 1m6 x C1m6')

        # 3.3 Historical stock audit stubs verification
        self.check("Master product catalog has exactly 1,829 entities", len(products) == 1829, f"{len(products)} entities")
        for stub_sku in ['TTTR6', 'XD6', 'NDL26']:
            self.check(f"Synthetic stub {stub_sku} exists in catalog", stub_sku in products)
            stub = products[stub_sku]
            self.check(f"Stub {stub_sku} stock == 0 in both branches",
                       stub['stock'] == 0 and stub['branchStocks']['store_001'] == 0 and stub['branchStocks']['store_002'] == 0)
            self.check(f"Stub {stub_sku} is inactive and not sellable",
                       not stub['allowSale'] and stub['status'] == 'inactive')

        # 3.4 Zero orphan SKUs across all collections
        cat_keys = set(products.keys())
        orphans_tx1 = {t['productId'] for t in tx1.values() if t.get('productId') and t['productId'] not in cat_keys}
        orphans_tx2 = {t['productId'] for t in tx2.values() if t.get('productId') and t['productId'] not in cat_keys}
        orphans_ret = {item['productId'] for r in staged_returns.values() for item in r.get('items', []) if item.get('productId') not in cat_keys}

        self.check("Zero orphan SKUs in store_001_tx", len(orphans_tx1) == 0, f"{orphans_tx1}")
        self.check("Zero orphan SKUs in store_002_tx", len(orphans_tx2) == 0, f"{orphans_tx2}")
        self.check("Zero orphan SKUs in store_002_returns", len(orphans_ret) == 0, f"{orphans_ret}")

        # 3.5 Invoice link audit
        self.check("TH000041 linked invoice HD012225 exists in store_002_orders", 'HD012225' in orders2)
        inv41 = orders2['HD012225']
        self.check("HD012225 customerId is KH004685", inv41['customerId'] == 'KH004685')
        self.check("HD012225 contains returned item GD5", any(it['productId'] == 'GD5' for it in inv41['items']))
        self.check("HD012225 total is 2,700,000.0 VNĐ", inv41['total'] == 2700000.0)
        self.check("HD012225 update timestamp matches return creation within 60s",
                   inv41['updatedAt'] == '2026-04-13T08:16:00.000' and ret41['createdAt'] == '2026-04-13T08:16:59.000')

        # TH000040 references early historical invoice HD011315
        self.check("TH000040 historical invoice HD011315 correctly identified as pre-dating export cutoff HD011402",
                   'HD011315' not in orders2 and min(orders2.keys()) == 'HD011402')

        # -------------------------------------------------------------
        # SUITE 4: INVOICE NET REVENUES RE-VERIFICATION
        # -------------------------------------------------------------
        print("\n--- SUITE 4: Invoice Net Revenues Invariants Re-Verification ---")
        inv_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV09102026-211131-415.xlsx')
        raw_invoices = {}
        for r in read_raw_excel_sheet(inv_file):
            inv_code = r.get(1, '').strip()
            if not inv_code or inv_code == 'Mã hóa đơn':
                continue
            if inv_code not in raw_invoices:
                branch = r.get(0, '').strip()
                store_id = 'store_001' if ('đông thắng' in branch.lower() or 'dong thang' in branch.lower()) else 'store_002'
                status_raw = r.get(29, '').strip()
                is_cancelled = ('hủy' in status_raw.lower() or 'cancelled' in status_raw.lower())
                c2_iso = serial_to_iso(r.get(2))
                c3_iso = serial_to_iso(r.get(3))
                c4_raw = r.get(4, '').strip()
                c4_iso = serial_to_iso(c4_raw) if c4_raw else None
                net_payable = Decimal(r.get(23, '0') or '0')

                raw_invoices[inv_code] = {
                    'code': inv_code,
                    'store_id': store_id,
                    'is_cancelled': is_cancelled,
                    'c2_iso': c2_iso,
                    'c3_iso': c3_iso,
                    'c4_raw': c4_raw,
                    'c4_iso': c4_iso,
                    'net_payable': net_payable
                }

        self.check("Raw unique invoices count == 2,075", len(raw_invoices) == 2075, f"{len(raw_invoices)} invoices")

        s1_raw = {k: v for k, v in raw_invoices.items() if v['store_id'] == 'store_001'}
        s2_raw = {k: v for k, v in raw_invoices.items() if v['store_id'] == 'store_002'}

        s1_active = [v for v in s1_raw.values() if not v['is_cancelled']]
        s2_active = [v for v in s2_raw.values() if not v['is_cancelled']]

        self.check("Store 001 total orders == 132", len(s1_raw) == 132)
        self.check("Store 001 active orders == 120", len(s1_active) == 120)
        self.check("Store 001 cancelled orders == 12", len(s1_raw) - len(s1_active) == 12)

        self.check("Store 002 total orders == 1,943", len(s2_raw) == 1943)
        self.check("Store 002 active orders == 1,767", len(s2_active) == 1767)
        self.check("Store 002 cancelled orders == 176", len(s2_raw) - len(s2_active) == 176)

        s1_net_rev = sum(v['net_payable'] for v in s1_active)
        s2_net_rev = sum(v['net_payable'] for v in s2_active)
        tot_net_rev = s1_net_rev + s2_net_rev

        self.check("Store 001 active net revenue == 639,515,000.00 VNĐ",
                   s1_net_rev == Decimal('639515000.00'), f"{s1_net_rev:,.2f} VNĐ")
        self.check("Store 002 active net revenue == 9,931,034,200.00 VNĐ",
                   s2_net_rev == Decimal('9931034200.00'), f"{s2_net_rev:,.2f} VNĐ")
        self.check("Total combined active net revenue == 10,570,549,200.00 VNĐ",
                   tot_net_rev == Decimal('10570549200.00'), f"{tot_net_rev:,.2f} VNĐ")

        with open(os.path.join(OUTPUT_DIR, 'store_001_orders.json'), 'r', encoding='utf-8') as f:
            staged_s1 = json.load(f)
        staged_s2 = orders2

        staged_s1_rev = sum(Decimal(str(o['netPayable'])) for o in staged_s1.values() if o['status'] != 'cancelled')
        staged_s2_rev = sum(Decimal(str(o['netPayable'])) for o in staged_s2.values() if o['status'] != 'cancelled')

        self.check("Staged Store 001 net revenue matches raw Excel with 0 delta", staged_s1_rev == s1_net_rev)
        self.check("Staged Store 002 net revenue matches raw Excel with 0 delta", staged_s2_rev == s2_net_rev)

        # -------------------------------------------------------------
        # SUITE 5: TIMESTAMP INTEGRITY ACROSS ALL 2,075 ORDERS
        # -------------------------------------------------------------
        print("\n--- SUITE 5: Timestamp Derivation & Anti-Drift Verification ---")
        staged_all_orders = {**staged_s1, **staged_s2}
        col2_mismatches = []
        for raw_code, raw_ord in raw_invoices.items():
            staged_key = sanitize_key(raw_code)
            staged_ord = staged_all_orders.get(staged_key)
            if not staged_ord:
                col2_mismatches.append((raw_code, "Missing"))
                continue
            if staged_ord.get('orderDate') != raw_ord['c2_iso'] or staged_ord.get('createdAt') != raw_ord['c2_iso']:
                col2_mismatches.append((raw_code, staged_ord.get('orderDate'), raw_ord['c2_iso']))

        self.check("100% of 2,075 orders: orderDate & createdAt derived strictly from Col 2",
                   len(col2_mismatches) == 0,
                   f"{len(col2_mismatches)} mismatches")

        # Stress test the 203 orders with Col 4 populated
        col4_orders = {k: v for k, v in raw_invoices.items() if v['c4_raw']}
        self.check("Raw orders with Col 4 populated == 203", len(col4_orders) == 203)
        col4_drift = [k for k, v in col4_orders.items() if staged_all_orders[sanitize_key(k)]['orderDate'] != v['c2_iso']]
        self.check("203 Col 4 orders exhibit zero date/month drift in staged data", len(col4_drift) == 0)

        # Stress test the 144 orders with Col 3 divergence
        col3_div = {
            k: v for k, v in raw_invoices.items()
            if abs((datetime.fromisoformat(v['c3_iso']) - datetime.fromisoformat(v['c2_iso'])).total_seconds()) >= 60
        }
        self.check("Raw orders with Col 3 divergence >= 60s == 144", len(col3_div) == 144)
        col3_drift = [k for k, v in col3_div.items() if staged_all_orders[sanitize_key(k)]['orderDate'] != v['c2_iso']]
        self.check("144 amended orders exhibit zero date/month drift in staged data", len(col3_drift) == 0)

        # -------------------------------------------------------------
        # SUITE 6: NET SYSTEM CASHFLOW & REVENUE POST-RETURNS
        # -------------------------------------------------------------
        print("\n--- SUITE 6: Net System Cashflow & Revenue Invariants Post-Returns ---")
        post_returns_s2_rev = s2_net_rev - Decimal(str(staged_returns_sum))
        post_returns_tot_rev = tot_net_rev - Decimal(str(staged_returns_sum))

        self.check("Store 002 post-returns net revenue = 9,925,734,200.00 VNĐ",
                   post_returns_s2_rev == Decimal('9925734200.00'),
                   f"{post_returns_s2_rev:,.2f} VNĐ")
        self.check("Total system post-returns net revenue = 10,565,249,200.00 VNĐ",
                   post_returns_tot_rev == Decimal('10565249200.00'),
                   f"{post_returns_tot_rev:,.2f} VNĐ")

        tot_cash_refunded = sum(r.get('cashRefunded', 0.0) for r in staged_returns.values())
        self.check("Total cash refunded to customers = exactly 2,700,000.0 VNĐ (TH000041: 2.7M, TH000040: 0.0)",
                   tot_cash_refunded == 2700000.0,
                   f"{tot_cash_refunded:,.2f} VNĐ")

        # -------------------------------------------------------------
        # SUITE 7: CUSTOMER & SUPPLIER DEBT INVARIANTS
        # -------------------------------------------------------------
        print("\n--- SUITE 7: Customer & Supplier Debt Invariants ---")
        cust_debt_sum = sum(Decimal(str(c.get('currentDebt', 0.0))) for c in customers.values())
        self.check("Customer receivables debt total == 33,684,023,744.00 VNĐ across 7,008 entities",
                   cust_debt_sum == Decimal('33684023744.00') and len(customers) == 7008,
                   f"{cust_debt_sum:,.2f} VNĐ ({len(customers)} customers)")

        with open(os.path.join(OUTPUT_DIR, 'shared_suppliers.json'), 'r', encoding='utf-8') as f:
            suppliers = json.load(f)
        supp_debt_sum = sum(Decimal(str(s.get('currentDebt', 0.0))) for s in suppliers.values())
        self.check("Supplier payables debt total == 23,259,824,240.00 VNĐ across 51 entities",
                   supp_debt_sum == Decimal('23259824240.00') and len(suppliers) == 51,
                   f"{supp_debt_sum:,.2f} VNĐ ({len(suppliers)} suppliers)")

        # -------------------------------------------------------------
        # FINAL VERDICT
        # -------------------------------------------------------------
        print("\n" + "=" * 80)
        total_checks = self.passed_checks + self.failed_checks
        print(f"TEST EXECUTION COMPLETED: {self.passed_checks}/{total_checks} CHECKS PASSED")
        print("=" * 80)

        if self.failed_checks == 0:
            print("\n>>> FINAL VERDICT: CONFIRM CORRECTNESS <<<")
            print("Customer returns (5.3M VNĐ, genuine GD5 & NDL24, valid KH004685 & KH006010, no garbage fields)")
            print("and all revenue/timestamp invariants are 100% verified with zero-delta!\n")
            return True
        else:
            print(f"\n>>> FINAL VERDICT: REJECT ({self.failed_checks} failures) <<<")
            for d in self.discrepancies:
                print(f"  - {d}")
            print()
            return False

if __name__ == '__main__':
    harness = ChallengerReturnsAndRevenueHarness()
    success = harness.run_all()
    sys.exit(0 if success else 1)
