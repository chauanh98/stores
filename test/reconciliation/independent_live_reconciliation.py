#!/usr/bin/env python3
"""
independent_live_reconciliation.py
Comprehensive Independent Live Reconciliation Suite.

Directly reads raw OpenXML (.xlsx) files from DATA_IMPORT/ and performs live REST
queries against Firebase Realtime Database (RTDB), asserting 100% zero-delta
parity across:
  1. Store 001 & Store 002 order counts (130 vs 1,877)
  2. Net revenue calculations (all-time and September 2026)
  3. Store 001 & Store 002 product catalog & branch stocks
  4. Shared customers & total receivables debt
  5. Shared suppliers & total payables debt
  6. Preserved account credentials
  7. Verification of clean database (absence of obsolete nodes)
"""

import os
import sys
import zipfile
import xml.etree.ElementTree as ET
import json
import re
import ssl
import urllib.request
from datetime import datetime
from decimal import Decimal
from collections import defaultdict

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_IMPORT_DIR = os.path.join(WORKSPACE_DIR, 'DATA_IMPORT')
DB_URL = "https://khanh-dang-store-default-rtdb.asia-southeast1.firebasedatabase.app"
SSL_CTX = ssl._create_unverified_context()
NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

def col2idx(c_str):
    idx = 0
    for ch in c_str:
        idx = idx * 26 + (ord(ch) - ord('A') + 1)
    return idx - 1

def parse_ref(ref):
    m = re.match(r'^([A-Z]+)([0-9]+)$', ref)
    if not m:
        return 0, 0
    c_str, r_str = m.groups()
    return int(r_str) - 1, col2idx(c_str)

def raw_rows_generator(xlsx_path, sheet_names=('xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml')):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sheet_xml = None
        for s in sheet_names:
            if s in z.namelist():
                sheet_xml = z.read(s)
                break
        if sheet_xml is None:
            raise FileNotFoundError(f"Could not find worksheet in {xlsx_path}")
        root = ET.fromstring(sheet_xml)
        for r_elem in root.findall(f'.//{NS}row'):
            row = {}
            for c_elem in r_elem.findall(f'{NS}c'):
                ref = c_elem.get('r')
                if not ref:
                    continue
                _, c_idx = parse_ref(ref)
                v_elem = c_elem.find(f'{NS}v')
                if v_elem is not None and v_elem.text is not None:
                    row[c_idx] = v_elem.text.strip()
                else:
                    row[c_idx] = ''
            yield row

def get_rtdb_node(path):
    if '?' in path:
        base, query = path.split('?', 1)
        url = f"{DB_URL}/{base.strip('/')}.json?{query}"
    else:
        url = f"{DB_URL}/{path.strip('/')}.json"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=45) as resp:
        content = resp.read().decode('utf-8')
        return json.loads(content)

def serial_to_datetime(serial_val):
    if not serial_val:
        return None
    s = str(serial_val).strip()
    try:
        serial = float(s)
        base = datetime(1899, 12, 30)
        days = int(serial)
        seconds = round((serial - days) * 86400)
        from datetime import timedelta
        return base + timedelta(days=days, seconds=seconds)
    except ValueError:
        m = re.match(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{1,2}))?$', s)
        if m:
            day, month, year, hour, minute = m.groups()
            return datetime(int(year), int(month), int(day), int(hour or 0), int(minute or 0))
        return None

class LiveReconciliationAuditor:
    def __init__(self):
        self.discrepancies = []
        self.checks_passed = 0
        self.checks_total = 0

    def assert_equal(self, dimension, expected, actual, unit=""):
        self.checks_total += 1
        passed = (expected == actual)
        delta = actual - expected if isinstance(expected, (int, float, Decimal)) else "N/A"
        if passed:
            self.checks_passed += 1
            print(f"  [PASS] {dimension}: {actual}{unit} (delta: {delta})")
        else:
            msg = f"[FAIL] {dimension}: Expected {expected}{unit}, got {actual}{unit} (delta: {delta})"
            self.discrepancies.append(msg)
            print(f"  {msg}")

    def assert_close(self, dimension, expected, actual, tolerance=1.0, unit=""):
        self.checks_total += 1
        diff = abs(Decimal(str(expected)) - Decimal(str(actual)))
        passed = (diff <= Decimal(str(tolerance)))
        if passed:
            self.checks_passed += 1
            print(f"  [PASS] {dimension}: {actual:,.2f}{unit} (expected: {expected:,.2f}{unit}, diff: {diff})")
        else:
            msg = f"[FAIL] {dimension}: Expected {expected:,.2f}{unit}, got {actual:,.2f}{unit} (diff: {diff})"
            self.discrepancies.append(msg)
            print(f"  {msg}")

    def run(self):
        print("\n" + "=" * 70)
        print("  COMPREHENSIVE INDEPENDENT LIVE RECONCILIATION SUITE")
        print("=" * 70)

        # -------------------------------------------------------------
        # STEP 1: PARSE RAW EXCEL INVOICES FROM FIRST PRINCIPLES
        # -------------------------------------------------------------
        print("\n--- 1. PARSING RAW OPENXML INVOICE DATA ---")
        invoices_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV26092026-210027-980.xlsx')
        assert os.path.isfile(invoices_file), f"Missing {invoices_file}"

        rows_iter = raw_rows_generator(invoices_file)
        _header = next(rows_iter)

        raw_s001_orders = {}
        raw_s002_orders = {}

        for r in rows_iter:
            raw_inv_id = r.get(1, '').strip()
            if not raw_inv_id:
                continue

            raw_branch = r.get(0, '').strip()
            dt = serial_to_datetime(r.get(2)) # Col 2: "Thời gian" (sale time VN UTC+7)
            raw_status = r.get(29, '').strip()
            is_cancelled = ('hủy' in raw_status.lower() or 'cancelled' in raw_status.lower())

            payable = Decimal(r.get(23, '0') or '0') # Col 23: net payable
            paid = Decimal(r.get(24, '0') or '0')

            order_record = {
                'code': raw_inv_id,
                'branch': raw_branch,
                'datetime': dt,
                'is_cancelled': is_cancelled,
                'payable': payable,
                'paid': paid,
            }

            if "đông thắng" in raw_branch.lower() or "dong thang" in raw_branch.lower():
                if raw_inv_id not in raw_s001_orders:
                    raw_s001_orders[raw_inv_id] = order_record
            else:
                if raw_inv_id not in raw_s002_orders:
                    raw_s002_orders[raw_inv_id] = order_record

        # Calculations from raw Excel
        raw_s001_count = len(raw_s001_orders)
        raw_s002_count = len(raw_s002_orders)

        raw_s001_active = [o for o in raw_s001_orders.values() if not o['is_cancelled']]
        raw_s002_active = [o for o in raw_s002_orders.values() if not o['is_cancelled']]

        raw_s001_net_rev = sum(o['payable'] for o in raw_s001_active)
        raw_s002_net_rev = sum(o['payable'] for o in raw_s002_active)
        raw_system_net_rev = raw_s001_net_rev + raw_s002_net_rev

        raw_s001_sep = [o for o in raw_s001_active if o['datetime'] and o['datetime'].year == 2026 and o['datetime'].month == 9]
        raw_s002_sep = [o for o in raw_s002_active if o['datetime'] and o['datetime'].year == 2026 and o['datetime'].month == 9]

        raw_s001_sep_rev = sum(o['payable'] for o in raw_s001_sep)
        raw_s002_sep_rev = sum(o['payable'] for o in raw_s002_sep)
        raw_system_sep_rev = raw_s001_sep_rev + raw_s002_sep_rev

        print(f"  Raw OpenXML Store 001: {raw_s001_count} orders (Active: {len(raw_s001_active)})")
        print(f"  Raw OpenXML Store 002: {raw_s002_count} orders (Active: {len(raw_s002_active)})")
        print(f"  Raw OpenXML Store 001 Net Rev: {raw_s001_net_rev:,.2f} VNĐ (Sep: {raw_s001_sep_rev:,.2f} VNĐ)")
        print(f"  Raw OpenXML Store 002 Net Rev: {raw_s002_net_rev:,.2f} VNĐ (Sep: {raw_s002_sep_rev:,.2f} VNĐ)")
        print(f"  Raw OpenXML System Net Rev:    {raw_system_net_rev:,.2f} VNĐ (Sep: {raw_system_sep_rev:,.2f} VNĐ)")

        # Verify raw OpenXML against KiotViet known targets
        self.assert_equal("Raw Excel Store 001 Orders Count", 130, raw_s001_count)
        self.assert_equal("Raw Excel Store 002 Orders Count", 1877, raw_s002_count)
        self.assert_close("Raw Excel Store 001 Net Revenue", 637735000.0, float(raw_s001_net_rev), unit=" VNĐ")
        self.assert_close("Raw Excel Store 001 Sep Revenue", 19000000.0, float(raw_s001_sep_rev), unit=" VNĐ")
        self.assert_close("Raw Excel Store 002 Net Revenue", 9712514200.0, float(raw_s002_net_rev), unit=" VNĐ")
        self.assert_close("Raw Excel Store 002 Sep Revenue", 694385000.0, float(raw_s002_sep_rev), unit=" VNĐ")
        self.assert_close("Raw Excel System Net Revenue", 10350249200.0, float(raw_system_net_rev), unit=" VNĐ")
        self.assert_close("Raw Excel System Sep Revenue", 713385000.0, float(raw_system_sep_rev), unit=" VNĐ")

        # -------------------------------------------------------------
        # STEP 2: QUERY LIVE RTDB ORDERS & RECONCILE
        # -------------------------------------------------------------
        print("\n--- 2. RECONCILING LIVE RTDB ORDERS ---")
        live_s001_orders = get_rtdb_node('stores/store_001/orders')
        live_s002_orders = get_rtdb_node('stores/store_002/orders')

        self.assert_equal("Live RTDB Store 001 Orders Count", raw_s001_count, len(live_s001_orders))
        self.assert_equal("Live RTDB Store 002 Orders Count", raw_s002_count, len(live_s002_orders))

        # Check RTDB active revenues
        live_s001_active = [o for o in live_s001_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy']]
        live_s002_active = [o for o in live_s002_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy']]

        live_s001_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_s001_active)
        live_s002_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_s002_active)
        live_system_net_rev = live_s001_net_rev + live_s002_net_rev

        self.assert_close("Live RTDB Store 001 Net Revenue", float(raw_s001_net_rev), live_s001_net_rev, unit=" VNĐ")
        self.assert_close("Live RTDB Store 002 Net Revenue", float(raw_s002_net_rev), live_s002_net_rev, unit=" VNĐ")
        self.assert_close("Live RTDB System Net Revenue", float(raw_system_net_rev), live_system_net_rev, unit=" VNĐ")

        # Check RTDB September revenue
        def is_sep_2026(dt_str):
            if not dt_str:
                return False
            return str(dt_str).startswith('2026-09')

        live_s001_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_s001_active if is_sep_2026(o.get('orderDate')))
        live_s002_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_s002_active if is_sep_2026(o.get('orderDate')))
        live_system_sep_rev = live_s001_sep_rev + live_s002_sep_rev

        self.assert_close("Live RTDB Store 001 Sep Revenue", float(raw_s001_sep_rev), live_s001_sep_rev, unit=" VNĐ")
        self.assert_close("Live RTDB Store 002 Sep Revenue", float(raw_s002_sep_rev), live_s002_sep_rev, unit=" VNĐ")
        self.assert_close("Live RTDB System Sep Revenue", float(raw_system_sep_rev), live_system_sep_rev, unit=" VNĐ")

        # -------------------------------------------------------------
        # STEP 3: PARSE RAW EXCEL PRODUCTS & RECONCILE STOCKS
        # -------------------------------------------------------------
        print("\n--- 3. RECONCILING RAW EXCEL PRODUCTS & LIVE STOCKS ---")
        p_dt_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV26092026-210308-937.xlsx')
        p_tb_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV26092026-205802-806.xlsx')

        dt_p_rows = list(raw_rows_generator(p_dt_file))
        tb_p_rows = list(raw_rows_generator(p_tb_file))

        # Đông Thắng raw metrics
        raw_dt_stock_map = {}
        for r in dt_p_rows[1:]:
            code = r.get(2, '').strip()
            if not code:
                continue
            stock = int(float(r.get(9, '0') or '0'))
            raw_dt_stock_map[code] = stock

        raw_dt_items_gt0 = sum(1 for s in raw_dt_stock_map.values() if s > 0)
        raw_dt_stock_sum = sum(raw_dt_stock_map.values())

        # Thới Bình raw metrics
        raw_tb_stock_map = {}
        for r in tb_p_rows[1:]:
            code = r.get(2, '').strip()
            if not code:
                continue
            stock = int(float(r.get(9, '0') or '0'))
            raw_tb_stock_map[code] = stock

        raw_tb_items_gt0 = sum(1 for s in raw_tb_stock_map.values() if s > 0)
        raw_tb_stock_sum = sum(raw_tb_stock_map.values())

        self.assert_equal("Raw Excel Store 001 Items with Stock > 0", 225, raw_dt_items_gt0)
        self.assert_equal("Raw Excel Store 001 Total Stock Units", 396, raw_dt_stock_sum, unit=" units")
        self.assert_equal("Raw Excel Store 002 Items with Stock > 0", 888, raw_tb_items_gt0)
        self.assert_equal("Raw Excel Store 002 Total Stock Units", 118157, raw_tb_stock_sum, unit=" units")

        # Fetch Live RTDB Products
        live_s001_prods = get_rtdb_node('stores/store_001/products')
        live_s002_prods = get_rtdb_node('stores/store_002/products')

        self.assert_equal("Live RTDB Store 001 Product Catalog Count", 1832, len(live_s001_prods))
        self.assert_equal("Live RTDB Store 002 Product Catalog Count", 1832, len(live_s002_prods))

        live_dt_active = [p for p in live_s001_prods.values() if (p.get('branchStocks') or {}).get('store_001', 0) > 0]
        live_dt_stock = sum((p.get('branchStocks') or {}).get('store_001', 0) for p in live_s001_prods.values())

        live_tb_active = [p for p in live_s002_prods.values() if (p.get('branchStocks') or {}).get('store_002', 0) > 0]
        live_tb_stock = sum((p.get('branchStocks') or {}).get('store_002', 0) for p in live_s002_prods.values())

        self.assert_equal("Live RTDB Store 001 Active Stock Items", raw_dt_items_gt0, len(live_dt_active))
        self.assert_equal("Live RTDB Store 001 Total Stock Units", raw_dt_stock_sum, live_dt_stock, unit=" units")
        self.assert_equal("Live RTDB Store 002 Active Stock Items", raw_tb_items_gt0, len(live_tb_active))
        self.assert_equal("Live RTDB Store 002 Total Stock Units", raw_tb_stock_sum, live_tb_stock, unit=" units")

        # -------------------------------------------------------------
        # STEP 4: RECONCILE CUSTOMERS & DEBT
        # -------------------------------------------------------------
        print("\n--- 4. RECONCILING CUSTOMERS & RECEIVABLES DEBT ---")
        cust_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachKhachHang_KV26092026-211128-685.xlsx')
        c_rows = list(raw_rows_generator(cust_file))
        raw_cust_count = 0
        raw_cust_debt = Decimal(0)
        for r in c_rows[1:]:
            cid = r.get(2, '').strip()
            if not cid:
                continue
            raw_cust_count += 1
            debt = Decimal(r.get(30, '0') or '0')
            raw_cust_debt += debt

        self.assert_equal("Raw Excel Customers Count", 6965, raw_cust_count)
        self.assert_close("Raw Excel Customer Debt", 33518997744.0, float(raw_cust_debt), unit=" VNĐ")

        live_customers = get_rtdb_node('shared_customers')
        live_c_count = len(live_customers)
        live_c_debt = sum(float(c.get('currentDebt', 0.0)) for c in live_customers.values())

        # Including synthetic walk-in stub (+1)
        self.assert_equal("Live RTDB Shared Customers Count (+1 stub)", 6966, live_c_count)
        self.assert_close("Live RTDB Total Customer Debt", float(raw_cust_debt), live_c_debt, unit=" VNĐ")

        # -------------------------------------------------------------
        # STEP 5: RECONCILE SUPPLIERS & DEBT
        # -------------------------------------------------------------
        print("\n--- 5. RECONCILING SUPPLIERS & PAYABLES DEBT ---")
        supp_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachNhaCungCap_KV26092026-205910-385.xlsx')
        s_rows = list(raw_rows_generator(supp_file))
        raw_supp_count = 0
        raw_supp_debt = Decimal(0)
        for r in s_rows[1:]:
            sid = r.get(0, '').strip()
            if not sid:
                continue
            raw_supp_count += 1
            debt = Decimal(r.get(8, '0') or '0')
            raw_supp_debt += debt

        self.assert_equal("Raw Excel Suppliers Count", 50, raw_supp_count)
        self.assert_close("Raw Excel Supplier Debt", 23137736240.0, float(raw_supp_debt), unit=" VNĐ")

        live_suppliers = get_rtdb_node('shared_suppliers')
        live_s_count = len(live_suppliers)
        live_s_debt = sum(float(s.get('currentDebt', 0.0)) for s in live_suppliers.values())

        # Including synthetic walk-in stub (+1)
        self.assert_equal("Live RTDB Shared Suppliers Count (+1 stub)", 51, live_s_count)
        self.assert_close("Live RTDB Total Supplier Debt", float(raw_supp_debt), live_s_debt, unit=" VNĐ")

        # -------------------------------------------------------------
        # STEP 6: VERIFY SYSTEM ACCOUNTS & STORE METADATA
        # -------------------------------------------------------------
        print("\n--- 6. VERIFYING SYSTEM ACCOUNTS & METADATA ---")
        live_accounts = get_rtdb_node('stores/accounts')
        account_names = set(live_accounts.keys()) if isinstance(live_accounts, dict) else set()
        expected_accounts = {'admin1', 'admin2', 'nhanvien1', 'nhanvien2', 'supervisor'}
        self.assert_equal("Live Accounts Count", 5, len(account_names))
        self.assert_equal("All Required Accounts Preserved", True, expected_accounts.issubset(account_names))

        # -------------------------------------------------------------
        # STEP 7: VERIFY ABSENCE OF OBSOLETE/REDUNDANT NODES
        # -------------------------------------------------------------
        print("\n--- 7. VERIFYING ABSENCE OF OBSOLETE NODES ---")
        obsolete_paths = [
            "stores/store_001/customers",
            "stores/store_001/categories",
            "stores/store_001/supplier_debts",
            "stores/store_002/customers",
            "stores/store_002/categories",
            "stores/store_002/suppliers",
            "stores/store_002/supplier_debts",
            "attendances",
            "shifts",
            "attendance_adjustments"
        ]
        for p in obsolete_paths:
            val = get_rtdb_node(f"{p}?shallow=true")
            is_absent = (val is None or val == {} or val == 'null')
            self.assert_equal(f"Node {p} is absent", True, is_absent)

        # -------------------------------------------------------------
        # FINAL VERDICT
        # -------------------------------------------------------------
        print("\n" + "=" * 70)
        print(f"  RECONCILIATION SUMMARY: {self.checks_passed}/{self.checks_total} CHECKS PASSED")
        print("=" * 70)

        if len(self.discrepancies) == 0:
            print("  >>> VERDICT: 100% ZERO-DELTA MATHEMATICAL RECONCILIATION PASSED! <<<")
            print("=" * 70 + "\n")
            return True
        else:
            print(f"  >>> VERDICT: FAILED WITH {len(self.discrepancies)} DISCREPANCIES <<<")
            for d in self.discrepancies:
                print(f"    - {d}")
            print("=" * 70 + "\n")
            return False

if __name__ == '__main__':
    auditor = LiveReconciliationAuditor()
    success = auditor.run()
    sys.exit(0 if success else 1)
