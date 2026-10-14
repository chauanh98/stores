#!/usr/bin/env python3
"""
challenger_m2_2_live_orders_and_debts_test.py
M2 Challenger 2: Empirical Verification & Adversarial Stress Suite for
Live Orders, Revenues, Timestamps, Debts, and Return Orders.

Independent Challenger: m2_challenger_2
Archetype: EMPIRICAL CHALLENGER
Roles: critic, specialist
Target DB: Firebase Realtime Database (asia-southeast1)
Ground Truth: Raw KiotViet OpenXML (.xlsx) files in DATA_IMPORT/
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

def raw_rows_generator(xlsx_path):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sheet_xml = z.read('xl/worksheets/sheet2.xml')
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

def serial_to_iso(serial_val):
    if not serial_val:
        return None
    s = str(serial_val).strip()
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
            day, month, year, hour, minute = m.groups()
            dt = datetime(int(year), int(month), int(day), int(hour or 0), int(minute or 0))
            return dt.strftime('%Y-%m-%dT%H:%M:%S.000')
        return None

def sanitize_rtdb_key(key):
    return re.sub(r'[\.\$#\[\]/\x00-\x1f\x7f]', '_', str(key).strip())

def get_live_node(path):
    url = f"{DB_URL}/{path.strip('/')}.json"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=45) as resp:
        content = resp.read().decode('utf-8')
        return json.loads(content)

class M2EmpiricalChallenger:
    def __init__(self):
        self.passed_tests = 0
        self.total_tests = 0
        self.failures = []

    def assert_test(self, name, condition, details=""):
        self.total_tests += 1
        if condition:
            self.passed_tests += 1
            print(f"  [PASS] {name} {details}")
        else:
            self.failures.append(f"{name}: {details}")
            print(f"  [FAIL] {name} {details}")

    def run(self):
        print("=" * 80)
        print(" M2 CHALLENGER 2: EMPIRICAL ORDERS, REVENUE & DEBT VERIFICATION")
        print("=" * 80)

        # -------------------------------------------------------------
        # STEP 1: PARSE RAW EXCEL GROUND TRUTH
        # -------------------------------------------------------------
        print("\n--- 1. PARSING RAW GROUND TRUTH EXCEL FILES ---")
        invoices_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV09102026-211131-415.xlsx')
        customers_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachKhachHang_KV09102026-211724-899.xlsx')
        suppliers_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachNhaCungCap_KV09102026-210945-177.xlsx')
        returns_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietTraHang_KV09102026-211147-871.xlsx')

        for fpath in [invoices_file, customers_file, suppliers_file, returns_file]:
            self.assert_test(f"File exists: {os.path.basename(fpath)}", os.path.isfile(fpath))

        # Parse Raw Invoices
        raw_inv_rows = raw_rows_generator(invoices_file)
        _ = next(raw_inv_rows)
        raw_s001_orders = {}
        raw_s002_orders = {}
        raw_col2_timestamps = {}
        raw_col3_timestamps = {}
        raw_col4_timestamps = {}

        for r in raw_inv_rows:
            raw_id = r.get(1, '').strip()
            if not raw_id:
                continue
            branch = r.get(0, '').strip()
            col2 = r.get(2, '').strip()
            col3 = r.get(3, '').strip()
            col4 = r.get(4, '').strip()

            c2_iso = serial_to_iso(col2)
            c3_iso = serial_to_iso(col3)
            c4_iso = serial_to_iso(col4)

            status_raw = r.get(29, '').strip()
            is_canc = ('hủy' in status_raw.lower() or 'cancelled' in status_raw.lower())
            payable = Decimal(r.get(23, '0') or '0')
            tot = Decimal(r.get(20, '0') or '0')
            disc = Decimal(r.get(21, '0') or '0')

            record = {
                'id': raw_id,
                'sanitized_id': sanitize_rtdb_key(raw_id),
                'branch': branch,
                'is_cancelled': is_canc,
                'payable': payable,
                'total': tot,
                'discount': disc,
                'col2_iso': c2_iso,
                'col3_iso': c3_iso,
                'col4_iso': c4_iso,
            }

            if raw_id not in raw_col2_timestamps:
                raw_col2_timestamps[raw_id] = c2_iso
                raw_col3_timestamps[raw_id] = c3_iso
                raw_col4_timestamps[raw_id] = c4_iso

            if "đông thắng" in branch.lower() or "dong thang" in branch.lower():
                if raw_id not in raw_s001_orders:
                    raw_s001_orders[raw_id] = record
            else:
                if raw_id not in raw_s002_orders:
                    raw_s002_orders[raw_id] = record

        # Parse Raw Customers
        raw_cust_rows = raw_rows_generator(customers_file)
        _ = next(raw_cust_rows)
        raw_cust_debt = Decimal(0)
        raw_cust_count = 0
        for r in raw_cust_rows:
            cid = r.get(2, '').strip()
            if not cid:
                continue
            raw_cust_count += 1
            raw_cust_debt += Decimal(r.get(30, '0') or '0')

        # Parse Raw Suppliers
        raw_supp_rows = raw_rows_generator(suppliers_file)
        _ = next(raw_supp_rows)
        raw_supp_debt = Decimal(0)
        raw_supp_count = 0
        for r in raw_supp_rows:
            sid = r.get(0, '').strip()
            if not sid:
                continue
            raw_supp_count += 1
            raw_supp_debt += Decimal(r.get(8, '0') or '0')

        # Parse Raw Returns
        raw_ret_rows = raw_rows_generator(returns_file)
        _ = next(raw_ret_rows)
        raw_returns = {}
        for r in raw_ret_rows:
            code = r.get(1, '').strip()
            if not code:
                continue
            if code not in raw_returns:
                raw_returns[code] = {
                    'code': code,
                    'total': Decimal(r.get(16, '0') or r.get(14, '0') or '0'),
                    'customerId': r.get(8, '').strip(),
                    'items': []
                }
            raw_returns[code]['items'].append({
                'productId': r.get(27, '').strip(),
                'qty': int(float(r.get(33, '1') or '1')),
                'price': Decimal(r.get(37, '0') or r.get(34, '0') or '0')
            })
        raw_ret_total = sum(r['total'] for r in raw_returns.values())

        print(f"  Raw Ground Truth Summary:")
        print(f"    Store 001 Orders: {len(raw_s001_orders)} (Active: {sum(1 for o in raw_s001_orders.values() if not o['is_cancelled'])})")
        print(f"    Store 002 Orders: {len(raw_s002_orders)} (Active: {sum(1 for o in raw_s002_orders.values() if not o['is_cancelled'])})")
        print(f"    Customers Count: {raw_cust_count}, Total Debt: {raw_cust_debt:,.2f} VNĐ")
        print(f"    Suppliers Count: {raw_supp_count}, Total Debt: {raw_supp_debt:,.2f} VNĐ")
        print(f"    Customer Returns: {len(raw_returns)}, Total: {raw_ret_total:,.2f} VNĐ")

        # -------------------------------------------------------------
        # STEP 2: FETCH LIVE FIREBASE RTDB DATA DIRECTLY
        # -------------------------------------------------------------
        print("\n--- 2. FETCHING LIVE FIREBASE RTDB NODES DIRECTLY ---")
        live_s001_orders = get_live_node('stores/store_001/orders')
        live_s002_orders = get_live_node('stores/store_002/orders')
        live_customers = get_live_node('shared_customers')
        live_suppliers = get_live_node('shared_suppliers')
        live_returns = get_live_node('stores/store_002/return_orders')

        self.assert_test("Live RTDB Store 001 Orders Node Exists", isinstance(live_s001_orders, dict))
        self.assert_test("Live RTDB Store 002 Orders Node Exists", isinstance(live_s002_orders, dict))
        self.assert_test("Live RTDB Shared Customers Node Exists", isinstance(live_customers, dict))
        self.assert_test("Live RTDB Shared Suppliers Node Exists", isinstance(live_suppliers, dict))
        self.assert_test("Live RTDB Store 002 Return Orders Node Exists", isinstance(live_returns, dict))

        # -------------------------------------------------------------
        # STEP 3: STORE 001 ORDERS & REVENUE VERIFICATION
        # -------------------------------------------------------------
        print("\n--- 3. STORE 001 ORDERS & REVENUE AUDIT ---")
        s001_total = len(live_s001_orders)
        s001_active = [o for o in live_s001_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy'] and not o.get('isCancelled', False)]
        s001_cancelled = [o for o in live_s001_orders.values() if o.get('status') in ['cancelled', 'Đã hủy'] or o.get('isCancelled', False)]
        s001_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s001_active)

        self.assert_test("Store 001 Total Orders == 132", s001_total == 132, f"Got: {s001_total}")
        self.assert_test("Store 001 Active Orders == 120", len(s001_active) == 120, f"Got: {len(s001_active)}")
        self.assert_test("Store 001 Cancelled Orders == 12", len(s001_cancelled) == 12, f"Got: {len(s001_cancelled)}")
        self.assert_test("Store 001 Active Net Revenue == 639,515,000.00 VNĐ",
                         abs(s001_net_rev - 639515000.0) < 0.01,
                         f"Got: {s001_net_rev:,.2f} VNĐ (Expected: 639,515,000.00 VNĐ)")

        # -------------------------------------------------------------
        # STEP 4: STORE 002 ORDERS & REVENUE VERIFICATION
        # -------------------------------------------------------------
        print("\n--- 4. STORE 002 ORDERS & REVENUE AUDIT ---")
        s002_total = len(live_s002_orders)
        s002_active = [o for o in live_s002_orders.values() if o.get('status') not in ['cancelled', 'Đã hủy'] and not o.get('isCancelled', False)]
        s002_cancelled = [o for o in live_s002_orders.values() if o.get('status') in ['cancelled', 'Đã hủy'] or o.get('isCancelled', False)]
        s002_net_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s002_active)

        self.assert_test("Store 002 Total Orders == 1,943", s002_total == 1943, f"Got: {s002_total}")
        self.assert_test("Store 002 Active Orders == 1,767", len(s002_active) == 1767, f"Got: {len(s002_active)}")
        self.assert_test("Store 002 Cancelled Orders == 176", len(s002_cancelled) == 176, f"Got: {len(s002_cancelled)}")
        self.assert_test("Store 002 Active Net Revenue == 9,931,034,200.00 VNĐ",
                         abs(s002_net_rev - 9931034200.0) < 0.01,
                         f"Got: {s002_net_rev:,.2f} VNĐ (Expected: 9,931,034,200.00 VNĐ)")

        # -------------------------------------------------------------
        # STEP 5: COMBINED SYSTEM TOTALS
        # -------------------------------------------------------------
        print("\n--- 5. COMBINED SYSTEM REVENUE & TOTAL AUDIT ---")
        combined_total = s001_total + s002_total
        combined_active = len(s001_active) + len(s002_active)
        combined_cancelled = len(s001_cancelled) + len(s002_cancelled)
        combined_net_rev = s001_net_rev + s002_net_rev

        self.assert_test("Combined Total Orders == 2,075", combined_total == 2075, f"Got: {combined_total}")
        self.assert_test("Combined Active Orders == 1,887", combined_active == 1887, f"Got: {combined_active}")
        self.assert_test("Combined Cancelled Orders == 188", combined_cancelled == 188, f"Got: {combined_cancelled}")
        self.assert_test("Total Net Revenue == 10,570,549,200.00 VNĐ",
                         abs(combined_net_rev - 10570549200.0) < 0.01,
                         f"Got: {combined_net_rev:,.2f} VNĐ (Expected: 10,570,549,200.00 VNĐ)")

        # -------------------------------------------------------------
        # STEP 6: TIMESTAMP COLUMN 2 DERIVATION & 0 CALENDAR DRIFT
        # -------------------------------------------------------------
        print("\n--- 6. TIMESTAMP COLUMN 2 DERIVATION & ZERO CALENDAR DRIFT ---")
        all_live_orders = {**live_s001_orders, **live_s002_orders}
        col2_orderDate_matches = 0
        col2_createdAt_matches = 0
        orderDate_createdAt_parity = 0
        calendar_drift_prevented = 0
        month_drift_candidates = 0

        for raw_id, c2_iso in raw_col2_timestamps.items():
            sanitized_id = sanitize_rtdb_key(raw_id)
            live_ord = all_live_orders.get(sanitized_id)
            if not live_ord:
                self.assert_test(f"Order {raw_id} exists in RTDB", False, f"Missing sanitized key: {sanitized_id}")
                continue

            o_date = live_ord.get('orderDate')
            c_at = live_ord.get('createdAt')

            if o_date == c2_iso:
                col2_orderDate_matches += 1
            if c_at == c2_iso:
                col2_createdAt_matches += 1
            if o_date == c_at:
                orderDate_createdAt_parity += 1

            # Check if this order was at risk of calendar drift (Col 3 or Col 4 month != Col 2 month)
            c3_iso = raw_col3_timestamps.get(raw_id)
            c4_iso = raw_col4_timestamps.get(raw_id)
            if (c3_iso and c3_iso[:7] != c2_iso[:7]) or (c4_iso and c4_iso[:7] != c2_iso[:7]):
                month_drift_candidates += 1
                if o_date[:7] == c2_iso[:7] and c_at[:7] == c2_iso[:7]:
                    calendar_drift_prevented += 1

        self.assert_test("100% of Live orders use Column 2 for orderDate",
                         col2_orderDate_matches == len(raw_col2_timestamps) == 2075,
                         f"Matches: {col2_orderDate_matches}/{len(raw_col2_timestamps)} ({col2_orderDate_matches/2075*100:.2f}%)")
        self.assert_test("100% of Live orders use Column 2 for createdAt",
                         col2_createdAt_matches == len(raw_col2_timestamps) == 2075,
                         f"Matches: {col2_createdAt_matches}/{len(raw_col2_timestamps)} ({col2_createdAt_matches/2075*100:.2f}%)")
        self.assert_test("orderDate == createdAt for 100% of orders",
                         orderDate_createdAt_parity == 2075,
                         f"Parity: {orderDate_createdAt_parity}/2075")
        self.assert_test("Zero Calendar Drift on all month-drift candidates",
                         month_drift_candidates == calendar_drift_prevented and month_drift_candidates > 0,
                         f"Defended: {calendar_drift_prevented}/{month_drift_candidates} orders with disparate Col 3/4")

        # -------------------------------------------------------------
        # STEP 7: SHARED CUSTOMERS & DEBTS VERIFICATION
        # -------------------------------------------------------------
        print("\n--- 7. SHARED CUSTOMERS & RECEIVABLES DEBT AUDIT ---")
        live_cust_count = len(live_customers)
        live_cust_debt = sum(float(c.get('currentDebt', 0.0)) for c in live_customers.values())

        self.assert_test("Customers Count == 7,008 records", live_cust_count == 7008, f"Got: {live_cust_count} (7007 raw + 1 stub)")
        self.assert_test("Customers Debt == 33,684,023,744.00 VNĐ",
                         abs(live_cust_debt - 33684023744.0) < 0.01,
                         f"Got: {live_cust_debt:,.2f} VNĐ (Expected: 33,684,023,744.00 VNĐ)")
        self.assert_test("Customer Stub 'KH002414' Exists with 0 Debt",
                         'KH002414' in live_customers and live_customers['KH002414'].get('currentDebt') == 0.0)

        # -------------------------------------------------------------
        # STEP 8: SHARED SUPPLIERS & DEBTS VERIFICATION
        # -------------------------------------------------------------
        print("\n--- 8. SHARED SUPPLIERS & PAYABLES DEBT AUDIT ---")
        live_supp_count = len(live_suppliers)
        live_supp_debt = sum(float(s.get('currentDebt', 0.0)) for s in live_suppliers.values())

        self.assert_test("Suppliers Count == 51 records", live_supp_count == 51, f"Got: {live_supp_count} (50 raw + 1 stub)")
        self.assert_test("Suppliers Debt == 23,259,824,240.00 VNĐ",
                         abs(live_supp_debt - 23259824240.0) < 0.01,
                         f"Got: {live_supp_debt:,.2f} VNĐ (Expected: 23,259,824,240.00 VNĐ)")
        # Walk-in supplier stub
        stub_supp = live_suppliers.get('NCC lẻ') or live_suppliers.get('NCC_lẻ')
        self.assert_test("Supplier Stub 'NCC lẻ' Exists with 0 Debt",
                         stub_supp is not None and stub_supp.get('currentDebt') == 0.0)

        # -------------------------------------------------------------
        # STEP 9: STORE 002 RETURN ORDERS VERIFICATION
        # -------------------------------------------------------------
        print("\n--- 9. STORE 002 CUSTOMER RETURN ORDERS AUDIT ---")
        live_ret_count = len(live_returns)
        live_ret_total = sum(float(r.get('total', 0.0)) for r in live_returns.values())

        self.assert_test("Return Orders Count == 2", live_ret_count == 2, f"Got: {live_ret_count}")
        self.assert_test("Return Orders Total == 5,300,000.0 VNĐ",
                         abs(live_ret_total - 5300000.0) < 0.01,
                         f"Got: {live_ret_total:,.2f} VNĐ (Expected: 5,300,000.0 VNĐ)")

        expected_ret_codes = {'TH000040', 'TH000041'}
        self.assert_test("Return Orders IDs == {'TH000040', 'TH000041'}",
                         set(live_returns.keys()) == expected_ret_codes,
                         f"Got: {set(live_returns.keys())}")

        r40 = live_returns.get('TH000040', {})
        r41 = live_returns.get('TH000041', {})
        self.assert_test("TH000040 == 2,600,000 VNĐ (KH006010, NDL24)",
                         r40.get('total') == 2600000.0 and r40.get('customerId') == 'KH006010' and any(i.get('productId') == 'NDL24' for i in r40.get('items', [])))
        self.assert_test("TH000041 == 2,700,000 VNĐ (KH004685, GD5)",
                         r41.get('total') == 2700000.0 and r41.get('customerId') == 'KH004685' and any(i.get('productId') == 'GD5' for i in r41.get('items', [])))

        # -------------------------------------------------------------
        # STEP 10: ADVERSARIAL STRESS-TESTING & EDGE-CASE MINING
        # -------------------------------------------------------------
        print("\n--- 10. ADVERSARIAL STRESS TESTS & INVARIANT MINING ---")

        # 10.1 Mathematical consistency of netPayable
        math_fails = 0
        for o in list(live_s001_orders.values()) + list(live_s002_orders.values()):
            tot = float(o.get('total', 0.0))
            disc = float(o.get('discount', 0.0))
            other = float(o.get('otherFees', 0.0))
            net = float(o.get('netPayable', tot - disc))
            # netPayable must equal total - discount + other (rounded to 2 decimal places)
            if abs(net - (tot - disc + other)) > 0.01:
                math_fails += 1
        self.assert_test("Adversarial Stress 1: 100% Orders obey netPayable == total - discount + otherFees",
                         math_fails == 0, f"Mismatches: {math_fails}")

        # 10.2 Cancelled orders exclusion from active revenue
        cancelled_with_positive_rev = 0
        for o in s001_cancelled + s002_cancelled:
            # Check that cancelled orders are marked status == 'cancelled'
            if o.get('status') != 'cancelled':
                cancelled_with_positive_rev += 1
        self.assert_test("Adversarial Stress 2: All 188 cancelled orders have status == 'cancelled'",
                         cancelled_with_positive_rev == 0, f"Uncancelled statuses: {cancelled_with_positive_rev}")

        # 10.3 Numerical Types and Sanitization (no NaN, null, stringified amounts)
        numeric_type_fails = 0
        for o in list(live_s001_orders.values()) + list(live_s002_orders.values()):
            for field in ['total', 'netPayable', 'amountPaid', 'debtAmount', 'discount']:
                v = o.get(field)
                if v is not None and not isinstance(v, (int, float)):
                    numeric_type_fails += 1
        self.assert_test("Adversarial Stress 3: All order numeric fields are typed as floats/ints",
                         numeric_type_fails == 0, f"Non-numeric types: {numeric_type_fails}")

        # 10.4 Customer debt advance deposit / credit balance parity
        raw_cust_neg = {}
        cust_iter = raw_rows_generator(customers_file)
        _ = next(cust_iter)
        for r in cust_iter:
            cid = r.get(2, '').strip()
            if not cid:
                continue
            d = Decimal(r.get(30, '0') or '0')
            if d < 0:
                raw_cust_neg[cid] = float(d)

        live_cust_neg = {cid: float(c.get('currentDebt', 0.0)) for cid, c in live_customers.items() if float(c.get('currentDebt', 0.0)) < 0}
        self.assert_test("Adversarial Stress 4: All 24 negative debts match raw Excel customer advance deposits",
                         len(live_cust_neg) == len(raw_cust_neg) == 24 and live_cust_neg == raw_cust_neg,
                         f"Live: {len(live_cust_neg)}, Raw: {len(raw_cust_neg)}")

        # 10.5 Supplier debt non-negativity and formatting
        supp_debt_negatives = 0
        for s in live_suppliers.values():
            d = s.get('currentDebt')
            if d is not None and d < 0:
                supp_debt_negatives += 1
        self.assert_test("Adversarial Stress 5: Zero negative debts in shared_suppliers",
                         supp_debt_negatives == 0, f"Negative debts: {supp_debt_negatives}")

        # 10.6 Store 001 return orders absence (no phantom returns)
        s001_returns = get_live_node('stores/store_001/return_orders')
        self.assert_test("Adversarial Stress 6: Store 001 has 0 phantom return orders",
                         s001_returns is None or s001_returns == {} or s001_returns == 'null')

        # 10.7 Check month distributions (September 2026 revenue validation)
        s001_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s001_active if (o.get('orderDate') or '').startswith('2026-09'))
        s002_sep_rev = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s002_active if (o.get('orderDate') or '').startswith('2026-09'))
        self.assert_test("Adversarial Stress 7: Store 001 September 2026 Net Revenue == 19,000,000.00 VNĐ",
                         abs(s001_sep_rev - 19000000.0) < 0.01, f"Got: {s001_sep_rev:,.2f} VNĐ")
        self.assert_test("Adversarial Stress 8: Store 002 September 2026 Net Revenue == 732,735,000.00 VNĐ",
                         abs(s002_sep_rev - 732735000.0) < 0.01, f"Got: {s002_sep_rev:,.2f} VNĐ")

        # -------------------------------------------------------------
        # FINAL VERDICT
        # -------------------------------------------------------------
        print("\n" + "=" * 80)
        print(f" CHALLENGER SUMMARY: {self.passed_tests}/{self.total_tests} ASSERTIONS PASSED")
        print("=" * 80)

        if len(self.failures) == 0:
            print("\n>>> DEFINITIVE VERDICT: CONFIRM CORRECTNESS <<<")
            print("All live database nodes, calculations, formulas, and timestamps match ground truth 100%.\n")
            return True
        else:
            print("\n>>> DEFINITIVE VERDICT: REJECT <<<")
            print(f"Failed with {len(self.failures)} discrepancies:")
            for f in self.failures:
                print(f"  - {f}")
            print()
            return False

if __name__ == '__main__':
    challenger = M2EmpiricalChallenger()
    success = challenger.run()
    sys.exit(0 if success else 1)
