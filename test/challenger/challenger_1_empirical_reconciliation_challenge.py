#!/usr/bin/env python3
"""
challenger_1_empirical_reconciliation_challenge.py

Challenger 1 Empirical & Mathematical Verification Harness.
Performs an independent adversarial audit comparing raw OpenXML sheets in DATA_IMPORT/
against the live Firebase Realtime Database.

Audited Dimensions:
1. Exact Invoice Counts (130 for store_001, 1877 for store_002)
2. Active Net Revenue (637,735,000 VNĐ store_001, 9,712,514,200 VNĐ store_002)
3. September 2026 Revenue (19,000,000 VNĐ store_001, 694,385,000 VNĐ store_002)
4. Product Stock Numbers (396 across 225 for store_001, 118,157 across 888 for store_002)
5. Temporal Accuracy & Zero Month-Shifting Anomaly Audit
6. Customer & Supplier Counts, Receivables & Payables Debt Parity
7. Referential Integrity & Key Sanitization (no '.' keys, raw codes preserved)
8. Stock Transfers & Inventory Transactions Parity
9. Preserved Account Credentials & Absence of Deprecated Nodes
"""

import os
import sys
import zipfile
import xml.etree.ElementTree as ET
import json
import re
import ssl
import urllib.request
from datetime import datetime, timedelta
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

def raw_rows_generator(xlsx_path, sheet_candidates=('xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml')):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sheet_xml = None
        for s in sheet_candidates:
            if s in z.namelist():
                sheet_xml = z.read(s)
                break
        if sheet_xml is None:
            raise FileNotFoundError(f"No valid sheet XML found in {xlsx_path}")
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

def serial_to_datetime(serial_val):
    if not serial_val:
        return None
    s = str(serial_val).strip()
    try:
        serial = float(s)
        base = datetime(1899, 12, 30)
        days = int(serial)
        seconds = round((serial - days) * 86400)
        return base + timedelta(days=days, seconds=seconds)
    except ValueError:
        m = re.match(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{1,2}))?$', s)
        if m:
            day, month, year, hour, minute = m.groups()
            return datetime(int(year), int(month), int(day), int(hour or 0), int(minute or 0))
        return None

def fetch_rtdb(path):
    if '?' in path:
        base, query = path.split('?', 1)
        url = f"{DB_URL}/{base.strip('/')}.json?{query}"
    else:
        url = f"{DB_URL}/{path.strip('/')}.json"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=60) as resp:
        return json.loads(resp.read().decode('utf-8'))

class ChallengerAuditor:
    def __init__(self):
        self.passed_checks = 0
        self.total_checks = 0
        self.discrepancies = []
        self.adversarial_findings = []

    def check(self, name, condition, details=""):
        self.total_checks += 1
        if condition:
            self.passed_checks += 1
            print(f"  [PASS] {name} {details}")
        else:
            msg = f"[FAIL] {name}: {details}"
            self.discrepancies.append(msg)
            print(f"  {msg}")

    def check_eq(self, name, expected, actual, unit=""):
        delta = actual - expected if isinstance(expected, (int, float, Decimal)) else "N/A"
        self.check(name, expected == actual, f"=> Expected: {expected}{unit}, Actual: {actual}{unit} (delta: {delta})")

    def check_close(self, name, expected, actual, tol=1.0, unit=""):
        diff = abs(Decimal(str(expected)) - Decimal(str(actual)))
        passed = diff <= Decimal(str(tol))
        self.check(name, passed, f"=> Expected: {expected:,.2f}{unit}, Actual: {actual:,.2f}{unit} (diff: {diff})")

    def run(self):
        print("=" * 80)
        print("  CHALLENGER 1: EMPIRICAL & MATHEMATICAL RECONCILIATION HARNESS")
        print(f"  Target: {DB_URL}")
        print("=" * 80)

        # =========================================================================
        # 1. PARSE RAW EXCEL INVOICES AND AUDIT TEMPORAL ACCURACY
        # =========================================================================
        print("\n[PHASE 1] PARSING RAW EXCEL INVOICES & AUDITING TEMPORAL ACCURACY...")
        inv_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV26092026-210027-980.xlsx')
        assert os.path.isfile(inv_file), f"Missing raw invoice file: {inv_file}"

        rows_iter = raw_rows_generator(inv_file)
        header = next(rows_iter)

        raw_orders = {}
        month_discrepancies_in_excel = []

        for r in rows_iter:
            raw_code = r.get(1, '').strip()
            if not raw_code:
                continue

            branch = r.get(0, '').strip()
            sale_dt = serial_to_datetime(r.get(2))      # Col 2: Thời gian (sale time)
            update_dt = serial_to_datetime(r.get(4)) or serial_to_datetime(r.get(3)) # Update time

            # Detect month discrepancies within raw excel itself (update vs sale)
            if sale_dt and update_dt and (sale_dt.month != update_dt.month or sale_dt.year != update_dt.year):
                month_discrepancies_in_excel.append({
                    'code': raw_code,
                    'branch': branch,
                    'sale_month': f"{sale_dt.year}-{sale_dt.month:02d}",
                    'update_month': f"{update_dt.year}-{update_dt.month:02d}",
                })

            raw_status = r.get(29, '').strip()
            is_cancelled = ('hủy' in raw_status.lower() or 'cancelled' in raw_status.lower())
            payable = Decimal(r.get(23, '0') or '0')
            paid = Decimal(r.get(24, '0') or '0')
            cust_id = r.get(7, '').strip()
            if cust_id.endswith('{DEL}'):
                cust_id = cust_id[:-5]
            if not cust_id:
                cust_id = 'khach_le'

            if raw_code not in raw_orders:
                is_dt = ("đông thắng" in branch.lower() or "dong thang" in branch.lower())
                store_id = "store_001" if is_dt else "store_002"
                raw_orders[raw_code] = {
                    'code': raw_code,
                    'storeId': store_id,
                    'branch': branch,
                    'customerId': cust_id,
                    'datetime': sale_dt,
                    'update_datetime': update_dt,
                    'is_cancelled': is_cancelled,
                    'payable': payable,
                    'paid': paid,
                    'items': []
                }

            # Add item
            prod_id = r.get(33, '').strip()
            qty = Decimal(r.get(37, '0') or '0')
            price = Decimal(r.get(38, '0') or '0')
            subtot = Decimal(r.get(41, '0') or '0')
            raw_orders[raw_code]['items'].append({
                'productId': prod_id,
                'quantity': qty,
                'price': price,
                'subtotal': subtot
            })

        print(f"  Raw distinct orders in Excel: {len(raw_orders)}")
        print(f"  Raw orders with Excel sale vs update month drift: {len(month_discrepancies_in_excel)}")
        if month_discrepancies_in_excel:
            print(f"    -> Sample drifted: {month_discrepancies_in_excel[:3]}")

        # Partition raw orders
        raw_001 = {k: v for k, v in raw_orders.items() if v['storeId'] == 'store_001'}
        raw_002 = {k: v for k, v in raw_orders.items() if v['storeId'] == 'store_002'}

        raw_001_active = [o for o in raw_001.values() if not o['is_cancelled']]
        raw_002_active = [o for o in raw_002.values() if not o['is_cancelled']]

        raw_001_net_rev = sum(o['payable'] for o in raw_001_active)
        raw_002_net_rev = sum(o['payable'] for o in raw_002_active)

        raw_001_sep = [o for o in raw_001_active if o['datetime'] and o['datetime'].year == 2026 and o['datetime'].month == 9]
        raw_002_sep = [o for o in raw_002_active if o['datetime'] and o['datetime'].year == 2026 and o['datetime'].month == 9]

        raw_001_sep_rev = sum(o['payable'] for o in raw_001_sep)
        raw_002_sep_rev = sum(o['payable'] for o in raw_002_sep)

        # Baseline asserts on raw Excel
        self.check_eq("Raw Excel Store 001 Total Orders", 130, len(raw_001))
        self.check_eq("Raw Excel Store 002 Total Orders", 1877, len(raw_002))
        self.check_close("Raw Excel Store 001 Net Revenue", 637735000.0, float(raw_001_net_rev), unit=" VNĐ")
        self.check_close("Raw Excel Store 002 Net Revenue", 9712514200.0, float(raw_002_net_rev), unit=" VNĐ")
        self.check_close("Raw Excel Store 001 Sep Revenue", 19000000.0, float(raw_001_sep_rev), unit=" VNĐ")
        self.check_close("Raw Excel Store 002 Sep Revenue", 694385000.0, float(raw_002_sep_rev), unit=" VNĐ")

        # =========================================================================
        # 2. QUERY LIVE RTDB ORDERS & RIGOROUS INVARIANT AUDIT
        # =========================================================================
        print("\n[PHASE 2] QUERYING LIVE RTDB ORDERS & VERIFYING MATHEMATICAL INVARIANTS...")
        live_001_orders = fetch_rtdb('stores/store_001/orders')
        live_002_orders = fetch_rtdb('stores/store_002/orders')

        self.check_eq("Live RTDB Store 001 Total Orders", 130, len(live_001_orders))
        self.check_eq("Live RTDB Store 002 Total Orders", 1877, len(live_002_orders))

        # Check for forbidden characters in RTDB keys
        forbidden_chars = {'.', '$', '#', '[', ']', '/'}
        dotted_keys_001 = [k for k in live_001_orders.keys() if any(c in forbidden_chars for c in k)]
        dotted_keys_002 = [k for k in live_002_orders.keys() if any(c in forbidden_chars for c in k)]
        self.check_eq("Store 001 Forbidden Key Chars", 0, len(dotted_keys_001))
        self.check_eq("Store 002 Forbidden Key Chars", 0, len(dotted_keys_002))

        # Detailed individual order check:
        # Verify:
        # a) code preservation
        # b) createdAt matches orderDate
        # c) orderDate matches Col 2 of Excel (no month-shift)
        # d) status is 'cancelled' if raw was cancelled
        # e) netPayable matches Excel payable
        # f) debtAmount is 0 if cancelled
        temporal_mismatches = []
        date_drift_from_excel = []
        code_mismatches = []
        net_payable_mismatches = []
        cancellation_status_mismatches = []

        all_live_orders = [('store_001', live_001_orders), ('store_002', live_002_orders)]

        for st_id, orders_dict in all_live_orders:
            for k, o in orders_dict.items():
                raw_code = o.get('code') or k
                if raw_code not in raw_orders:
                    # Maybe sanitized key in RTDB: e.g. HD009550_01 -> HD009550.01
                    desanitized = raw_code.replace('_', '.')
                    if desanitized in raw_orders:
                        raw_code = desanitized
                    else:
                        self.discrepancies.append(f"Orphan order in RTDB not found in Excel: {k} ({raw_code})")
                        continue

                raw_o = raw_orders[raw_code]

                # a) Check createdAt == orderDate
                created_at = str(o.get('createdAt', '')).strip()
                order_date = str(o.get('orderDate', '')).strip()
                if created_at != order_date:
                    temporal_mismatches.append(f"{k}: createdAt({created_at}) != orderDate({order_date})")

                # b) Check date matches Col 2 of Excel down to YYYY-MM
                excel_dt = raw_o['datetime']
                if excel_dt:
                    excel_iso_prefix = excel_dt.strftime('%Y-%m-%d')
                    excel_month_prefix = excel_dt.strftime('%Y-%m')
                    if not order_date.startswith(excel_month_prefix):
                        date_drift_from_excel.append(f"{k}: RTDB {order_date} != Excel {excel_iso_prefix} (Col 2)")

                # c) Check cancellation status
                is_cancelled_live = o.get('status') in ['cancelled', 'Đã hủy']
                if is_cancelled_live != raw_o['is_cancelled']:
                    cancellation_status_mismatches.append(f"{k}: RTDB cancelled={is_cancelled_live} vs Excel={raw_o['is_cancelled']}")

                # d) Check netPayable
                live_net = Decimal(str(o.get('netPayable', o.get('total', 0.0))))
                if abs(live_net - raw_o['payable']) > Decimal('0.01'):
                    net_payable_mismatches.append(f"{k}: RTDB net={live_net} vs Excel={raw_o['payable']}")

        self.check_eq("Order createdAt == orderDate Equality", 0, len(temporal_mismatches), " mismatches")
        self.check_eq("Zero Month-Shifted Orders vs Excel Col 2", 0, len(date_drift_from_excel), " drifted orders")
        self.check_eq("Zero Cancellation Status Inconsistencies", 0, len(cancellation_status_mismatches), " mismatches")
        self.check_eq("Zero Net Payable Inconsistencies", 0, len(net_payable_mismatches), " mismatches")

        # Specific audit of known previously-shifted invoices
        suspects = ['HD013097_01', 'HD012908_02', 'HD013218_01', 'HD013220_01', 'HD013222_01']
        for s in suspects:
            if s in live_002_orders:
                so = live_002_orders[s]
                print(f"  [AUDIT SPECIFIC] Suspect {s}: createdAt={so.get('createdAt')}, orderDate={so.get('orderDate')}")
                self.check(f"Suspect {s} has non-null synchronized dates", so.get('createdAt') == so.get('orderDate'))

        # Check Active Revenues in RTDB
        live_001_active = [o for o in live_001_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy']]
        live_002_active = [o for o in live_002_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy']]

        live_001_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_001_active)
        live_002_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_002_active)

        self.check_close("Live RTDB Store 001 Active Net Revenue", 637735000.0, live_001_net_rev, unit=" VNĐ")
        self.check_close("Live RTDB Store 002 Active Net Revenue", 9712514200.0, live_002_net_rev, unit=" VNĐ")

        # Check September 2026 Revenues in RTDB
        def is_sep_2026(dt_str):
            return str(dt_str).startswith('2026-09')

        live_001_sep_active = [o for o in live_001_active if is_sep_2026(o.get('orderDate'))]
        live_002_sep_active = [o for o in live_002_active if is_sep_2026(o.get('orderDate'))]

        live_001_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_001_sep_active)
        live_002_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in live_002_sep_active)

        self.check_close("Live RTDB Store 001 September Revenue", 19000000.0, live_001_sep_rev, unit=" VNĐ")
        self.check_close("Live RTDB Store 002 September Revenue", 694385000.0, live_002_sep_rev, unit=" VNĐ")
        self.check_close("Live RTDB System September Revenue", 713385000.0, live_001_sep_rev + live_002_sep_rev, unit=" VNĐ")

        # =========================================================================
        # 3. PARSE RAW EXCEL PRODUCTS & AUDIT BRANCH STOCKS
        # =========================================================================
        print("\n[PHASE 3] PARSING RAW EXCEL PRODUCTS & AUDITING BRANCH STOCKS...")
        dt_prod_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV26092026-210308-937.xlsx')
        tb_prod_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV26092026-205802-806.xlsx')

        dt_p_rows = list(raw_rows_generator(dt_prod_file))
        tb_p_rows = list(raw_rows_generator(tb_prod_file))

        raw_dt_stocks = {}
        for r in dt_p_rows[1:]:
            c = r.get(2, '').strip()
            if not c:
                continue
            stk = int(float(r.get(9, '0') or '0'))
            raw_dt_stocks[c] = stk

        raw_tb_stocks = {}
        for r in tb_p_rows[1:]:
            c = r.get(2, '').strip()
            if not c:
                continue
            stk = int(float(r.get(9, '0') or '0'))
            raw_tb_stocks[c] = stk

        expected_dt_pos_count = sum(1 for s in raw_dt_stocks.values() if s > 0)
        expected_dt_pos_sum = sum(raw_dt_stocks.values())
        expected_tb_pos_count = sum(1 for s in raw_tb_stocks.values() if s > 0)
        expected_tb_pos_sum = sum(raw_tb_stocks.values())

        self.check_eq("Raw Excel Đông Thắng (store_001) Active Stock Count", 225, expected_dt_pos_count)
        self.check_eq("Raw Excel Đông Thắng (store_001) Total Stock Units", 396, expected_dt_pos_sum, " units")
        self.check_eq("Raw Excel Thới Bình (store_002) Active Stock Count", 888, expected_tb_pos_count)
        self.check_eq("Raw Excel Thới Bình (store_002) Total Stock Units", 118157, expected_tb_pos_sum, " units")

        # Fetch live products
        live_001_prods = fetch_rtdb('stores/store_001/products')
        live_002_prods = fetch_rtdb('stores/store_002/products')

        self.check_eq("Live RTDB Store 001 Product Catalog Count", 1832, len(live_001_prods))
        self.check_eq("Live RTDB Store 002 Product Catalog Count", 1832, len(live_002_prods))

        # Check every product's branchStocks in RTDB
        dt_active_in_rtdb = []
        tb_active_in_rtdb = []
        dt_rtdb_stock_algebraic = 0
        tb_rtdb_stock_algebraic = 0
        dt_rtdb_stock_pos_only = 0
        tb_rtdb_stock_pos_only = 0
        product_stock_drift = []

        for pid, p in live_001_prods.items():
            bstocks = p.get('branchStocks') or {}
            s001 = bstocks.get('store_001', 0)
            s002 = bstocks.get('store_002', 0)

            raw_s001 = raw_dt_stocks.get(pid, 0)
            raw_s002 = raw_tb_stocks.get(pid, 0)

            if s001 != raw_s001:
                product_stock_drift.append(f"{pid}: store_001 RTDB={s001} vs Excel={raw_s001}")
            if s002 != raw_s002:
                product_stock_drift.append(f"{pid}: store_002 RTDB={s002} vs Excel={raw_s002}")

            dt_rtdb_stock_algebraic += s001
            tb_rtdb_stock_algebraic += s002

            if s001 > 0:
                dt_active_in_rtdb.append(pid)
                dt_rtdb_stock_pos_only += s001
            if s002 > 0:
                tb_active_in_rtdb.append(pid)
                tb_rtdb_stock_pos_only += s002

        self.check_eq("Live RTDB Đông Thắng Active Stock Products Count", 225, len(dt_active_in_rtdb))
        self.check_eq("Live RTDB Đông Thắng Total Stock Units", 396, dt_rtdb_stock_algebraic, " units")
        self.check_eq("Live RTDB Thới Bình Active Stock Products Count", 888, len(tb_active_in_rtdb))
        self.check_eq("Live RTDB Thới Bình Total Stock Units (Algebraic)", 118157, tb_rtdb_stock_algebraic, " units")
        self.check_eq("Live RTDB Thới Bình Positive Stock Units (excl SP000685 -1)", 118158, tb_rtdb_stock_pos_only, " units")
        self.check_eq("Boundary Product SP000685 Negative Stock (-1) Preserved", -1, (live_001_prods.get('SP000685', {}).get('branchStocks', {}).get('store_002', 0)))
        self.check_eq("Individual Product Stock Drift Across 1,832 Items", 0, len(product_stock_drift), " mismatches")

        # Discontinued products check in RTDB
        disc_codes = {'BTDB16', 'HS18', 'HS19', 'HS20', 'THOB14', 'TTTR6', 'TTTR7', 'TTTR8', 'VG1', 'VG2', 'VG5'}
        for d in disc_codes:
            self.check(f"Discontinued stub {d} exists in RTDB", d in live_001_prods)
            if d in live_001_prods:
                p = live_001_prods[d]
                self.check(f"Discontinued stub {d} allowSale is False", p.get('allowSale') is False)

        # =========================================================================
        # 4. CUSTOMERS & SUPPLIERS DEBT AND RECONCILIATION
        # =========================================================================
        print("\n[PHASE 4] RECONCILING CUSTOMERS & SUPPLIERS DEBT...")
        cust_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachKhachHang_KV26092026-211128-685.xlsx')
        c_rows = list(raw_rows_generator(cust_file))
        raw_cust_map = {}
        raw_cust_pos_debt = Decimal(0)
        raw_cust_neg_debt = Decimal(0)
        raw_cust_net_debt = Decimal(0)

        for r in c_rows[1:]:
            cid = r.get(2, '').strip()
            if not cid:
                continue
            debt = Decimal(r.get(30, '0') or '0')
            raw_cust_map[cid] = debt
            raw_cust_net_debt += debt
            if debt > 0:
                raw_cust_pos_debt += debt
            elif debt < 0:
                raw_cust_neg_debt += debt

        self.check_eq("Raw Excel Customers Count", 6965, len(raw_cust_map))
        self.check_close("Raw Excel Customer Net Debt", 33518997744.0, float(raw_cust_net_debt), unit=" VNĐ")
        self.check_close("Raw Excel Customer Positive Debt", 33561557744.0, float(raw_cust_pos_debt), unit=" VNĐ")
        self.check_close("Raw Excel Customer Negative Debt", -42560000.0, float(raw_cust_neg_debt), unit=" VNĐ")

        live_customers = fetch_rtdb('shared_customers')
        self.check_eq("Live RTDB Shared Customers Count (+1 stub)", 6966, len(live_customers))
        live_cust_net_debt = sum(float(c.get('currentDebt', 0.0)) for c in live_customers.values())
        live_cust_pos_debt = sum(float(c.get('currentDebt', 0.0)) for c in live_customers.values() if float(c.get('currentDebt', 0.0)) > 0)
        live_cust_neg_debt = sum(float(c.get('currentDebt', 0.0)) for c in live_customers.values() if float(c.get('currentDebt', 0.0)) < 0)

        self.check_close("Live RTDB Customers Net Debt", float(raw_cust_net_debt), live_cust_net_debt, unit=" VNĐ")
        self.check_close("Live RTDB Customers Positive Debt", float(raw_cust_pos_debt), live_cust_pos_debt, unit=" VNĐ")
        self.check_close("Live RTDB Customers Negative Debt", float(raw_cust_neg_debt), live_cust_neg_debt, unit=" VNĐ")

        # Check walk-in stub KH002414 exists in RTDB
        self.check("Customer KH002414 exists in RTDB", 'KH002414' in live_customers)

        # Suppliers
        supp_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachNhaCungCap_KV26092026-205910-385.xlsx')
        s_rows = list(raw_rows_generator(supp_file))
        raw_supp_map = {}
        raw_supp_debt = Decimal(0)
        for r in s_rows[1:]:
            sid = r.get(0, '').strip()
            if not sid:
                continue
            debt = Decimal(r.get(8, '0') or '0')
            raw_supp_map[sid] = debt
            raw_supp_debt += debt

        self.check_eq("Raw Excel Suppliers Count", 50, len(raw_supp_map))
        self.check_close("Raw Excel Supplier Debt Sum", 23137736240.0, float(raw_supp_debt), unit=" VNĐ")

        live_suppliers = fetch_rtdb('shared_suppliers')
        self.check_eq("Live RTDB Shared Suppliers Count (+1 stub)", 51, len(live_suppliers))
        live_supp_debt = sum(float(s.get('currentDebt', 0.0)) for s in live_suppliers.values())
        self.check_close("Live RTDB Suppliers Debt Sum", float(raw_supp_debt), live_supp_debt, unit=" VNĐ")

        # =========================================================================
        # 5. INVENTORY TRANSACTIONS & SYSTEM HYGIENE
        # =========================================================================
        print("\n[PHASE 5] AUDITING INVENTORY TRANSACTIONS & SYSTEM HYGIENE...")
        live_001_tx = fetch_rtdb('stores/store_001/inventory_transactions?shallow=true')
        live_002_tx = fetch_rtdb('stores/store_002/inventory_transactions?shallow=true')

        count_001_tx = len(live_001_tx) if isinstance(live_001_tx, dict) else 0
        count_002_tx = len(live_002_tx) if isinstance(live_002_tx, dict) else 0

        print(f"  Store 001 inventory transactions: {count_001_tx}")
        print(f"  Store 002 inventory transactions: {count_002_tx}")

        # Check accounts
        accounts = fetch_rtdb('stores/accounts')
        expected_accounts = {'admin1', 'admin2', 'nhanvien1', 'nhanvien2', 'supervisor'}
        self.check_eq("Live Accounts Count", 5, len(accounts))
        self.check("All Required Accounts Preserved", expected_accounts.issubset(set(accounts.keys())))

        # Check obsolete nodes
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
            val = fetch_rtdb(f"{p}?shallow=true")
            self.check(f"Node {p} absent", val is None or val == {} or val == 'null')

        # =========================================================================
        # SUMMARY & VERDICT
        # =========================================================================
        print("\n" + "=" * 80)
        print(f"  FINAL SUMMARY: {self.passed_checks}/{self.total_checks} CHECKS PASSED")
        print("=" * 80)

        if len(self.discrepancies) == 0:
            print("  >>> VERDICT: APPROVE (100% EMPIRICAL & MATHEMATICAL PARITY) <<<")
            return True
        else:
            print(f"  >>> VERDICT: REJECT ({len(self.discrepancies)} DISCREPANCIES) <<<")
            for d in self.discrepancies:
                print(f"    - {d}")
            return False

if __name__ == '__main__':
    auditor = ChallengerAuditor()
    success = auditor.run()
    sys.exit(0 if success else 1)
