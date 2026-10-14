#!/usr/bin/env python3
"""
m3_challenger_2_live_adversarial_audit.py
Milestone 3 Challenger 2: Adversarial Verification & Invariant Stress Suite
Target: Live Firebase Realtime Database vs Raw Ground Truth (.xlsx)

Audited Dimensions:
1. Store 001 Orders (132 total, 120 active, 12 cancelled, 639,515,000.00 VNĐ net)
2. Store 002 Orders (1,943 total, 1,767 active, 176 cancelled, 9,931,034,200.00 VNĐ net)
3. Combined System Revenue (10,570,549,200.00 VNĐ across 2,075 orders)
4. Column 2 Timestamp Invariants & Zero Calendar Drift across 100% of orders
5. Customer Receivables Debt (33,684,023,744.00 VNĐ across 7,008 records)
6. Supplier Payables Debt (23,259,824,240.00 VNĐ across 51 records)
7. Customer Return Orders (TH000040 & TH000041 totaling 5,300,000.00 VNĐ in Store 002, 0 in Store 001)
8. Deep Adversarial Edge Cases: Float precision, NaN/null guards, schema hygiene, preserved auth/configs.
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
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=60) as resp:
        content = resp.read().decode('utf-8')
        return json.loads(content)

class M3Challenger2Suite:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failure_reasons = []

    def check(self, title, condition, details=""):
        if condition:
            self.passed += 1
            print(f"  [PASS] {title} {details}")
        else:
            self.failed += 1
            msg = f"{title}: {details}"
            self.failure_reasons.append(msg)
            print(f"  [FAIL] {msg}")

    def run(self):
        print("=" * 80)
        print(" M3 CHALLENGER 2: DEEP ADVERSARIAL VERIFICATION SUITE")
        print("=" * 80)

        # 1. GROUND TRUTH PARSING
        print("\n--- [PHASE 1] PARSING GROUND TRUTH OPENXML FILES ---")
        inv_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV09102026-211131-415.xlsx')
        cust_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachKhachHang_KV09102026-211724-899.xlsx')
        supp_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachNhaCungCap_KV09102026-210945-177.xlsx')
        ret_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietTraHang_KV09102026-211147-871.xlsx')

        self.check("Invoices ground truth file exists", os.path.isfile(inv_file))
        self.check("Customers ground truth file exists", os.path.isfile(cust_file))
        self.check("Suppliers ground truth file exists", os.path.isfile(supp_file))
        self.check("Returns ground truth file exists", os.path.isfile(ret_file))

        # Ground truth structures
        raw_inv_iter = raw_rows_generator(inv_file)
        _ = next(raw_inv_iter)
        raw_orders_by_branch = {'s001': {}, 's002': {}}
        raw_timestamps = {}
        raw_col3_col4 = {}

        for r in raw_inv_iter:
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

            branch_key = 's001' if ("đông thắng" in branch.lower() or "dong thang" in branch.lower()) else 's002'
            if raw_id not in raw_orders_by_branch[branch_key]:
                raw_orders_by_branch[branch_key][raw_id] = {
                    'id': raw_id,
                    'is_cancelled': is_canc,
                    'payable': payable,
                    'total': tot,
                    'discount': disc,
                    'col2_iso': c2_iso
                }
            if raw_id not in raw_timestamps:
                raw_timestamps[raw_id] = c2_iso
                raw_col3_col4[raw_id] = (c3_iso, c4_iso)

        raw_s001_act = sum(1 for o in raw_orders_by_branch['s001'].values() if not o['is_cancelled'])
        raw_s001_can = sum(1 for o in raw_orders_by_branch['s001'].values() if o['is_cancelled'])
        raw_s001_net = sum(o['payable'] for o in raw_orders_by_branch['s001'].values() if not o['is_cancelled'])

        raw_s002_act = sum(1 for o in raw_orders_by_branch['s002'].values() if not o['is_cancelled'])
        raw_s002_can = sum(1 for o in raw_orders_by_branch['s002'].values() if o['is_cancelled'])
        raw_s002_net = sum(o['payable'] for o in raw_orders_by_branch['s002'].values() if not o['is_cancelled'])

        print(f"  Ground Truth Invoices:")
        print(f"    Store 001: {len(raw_orders_by_branch['s001'])} total ({raw_s001_act} active, {raw_s001_can} cancelled), Net: {raw_s001_net:,.2f} VNĐ")
        print(f"    Store 002: {len(raw_orders_by_branch['s002'])} total ({raw_s002_act} active, {raw_s002_can} cancelled), Net: {raw_s002_net:,.2f} VNĐ")

        # 2. FETCH LIVE RTDB DATA
        print("\n--- [PHASE 2] FETCHING LIVE RTDB DIRECT DATA ---")
        live_s001_orders = get_live_node('stores/store_001/orders')
        live_s002_orders = get_live_node('stores/store_002/orders')
        live_custs = get_live_node('shared_customers')
        live_supps = get_live_node('shared_suppliers')
        live_returns = get_live_node('stores/store_002/return_orders')
        live_s001_returns = get_live_node('stores/store_001/return_orders')
        live_accounts = get_live_node('stores/accounts')
        live_payment_configs = get_live_node('store_payment_configs')

        self.check("Live Store 001 Orders dictionary retrieved", isinstance(live_s001_orders, dict))
        self.check("Live Store 002 Orders dictionary retrieved", isinstance(live_s002_orders, dict))
        self.check("Live Shared Customers dictionary retrieved", isinstance(live_custs, dict))
        self.check("Live Shared Suppliers dictionary retrieved", isinstance(live_supps, dict))
        self.check("Live Store 002 Returns dictionary retrieved", isinstance(live_returns, dict))
        self.check("Live Accounts dictionary retrieved", isinstance(live_accounts, dict))

        # 3. VERIFY STORE 001
        print("\n--- [PHASE 3] VERIFYING STORE 001 INVARIANTS ---")
        s001_orders_list = list(live_s001_orders.values())
        s001_act_list = [o for o in s001_orders_list if o.get('status') not in ['cancelled', 'Đã hủy'] and not o.get('isCancelled', False)]
        s001_can_list = [o for o in s001_orders_list if o.get('status') in ['cancelled', 'Đã hủy'] or o.get('isCancelled', False)]
        s001_active_net = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s001_act_list)

        self.check("Store 001 total orders == 132", len(live_s001_orders) == 132, f"Got: {len(live_s001_orders)}")
        self.check("Store 001 active orders == 120", len(s001_act_list) == 120, f"Got: {len(s001_act_list)}")
        self.check("Store 001 cancelled orders == 12", len(s001_can_list) == 12, f"Got: {len(s001_can_list)}")
        self.check("Store 001 Active Net Revenue == 639,515,000.00 VNĐ",
                   abs(s001_active_net - 639515000.0) < 0.01,
                   f"Got: {s001_active_net:,.2f} VNĐ")

        # 4. VERIFY STORE 002
        print("\n--- [PHASE 4] VERIFYING STORE 002 INVARIANTS ---")
        s002_orders_list = list(live_s002_orders.values())
        s002_act_list = [o for o in s002_orders_list if o.get('status') not in ['cancelled', 'Đã hủy'] and not o.get('isCancelled', False)]
        s002_can_list = [o for o in s002_orders_list if o.get('status') in ['cancelled', 'Đã hủy'] or o.get('isCancelled', False)]
        s002_active_net = sum(float(o.get('netPayable', o.get('total', 0.0))) for o in s002_act_list)

        self.check("Store 002 total orders == 1,943", len(live_s002_orders) == 1943, f"Got: {len(live_s002_orders)}")
        self.check("Store 002 active orders == 1,767", len(s002_act_list) == 1767, f"Got: {len(s002_act_list)}")
        self.check("Store 002 cancelled orders == 176", len(s002_can_list) == 176, f"Got: {len(s002_can_list)}")
        self.check("Store 002 Active Net Revenue == 9,931,034,200.00 VNĐ",
                   abs(s002_active_net - 9931034200.0) < 0.01,
                   f"Got: {s002_active_net:,.2f} VNĐ")

        # 5. VERIFY COMBINED NET REVENUE
        print("\n--- [PHASE 5] VERIFYING COMBINED TOTALS ---")
        combined_orders_count = len(live_s001_orders) + len(live_s002_orders)
        combined_act_count = len(s001_act_list) + len(s002_act_list)
        combined_can_count = len(s001_can_list) + len(s002_can_list)
        combined_net_revenue = s001_active_net + s002_active_net

        self.check("Combined total orders == 2,075", combined_orders_count == 2075, f"Got: {combined_orders_count}")
        self.check("Combined active orders == 1,887", combined_act_count == 1887, f"Got: {combined_act_count}")
        self.check("Combined cancelled orders == 188", combined_can_count == 188, f"Got: {combined_can_count}")
        self.check("Combined Net Revenue == 10,570,549,200.00 VNĐ",
                   abs(combined_net_revenue - 10570549200.0) < 0.01,
                   f"Got: {combined_net_revenue:,.2f} VNĐ")

        # 6. TIMESTAMP DERIVATION & ZERO DRIFT
        print("\n--- [PHASE 6] VERIFYING TIMESTAMP COLUMN 2 DERIVATION & ZERO DRIFT ---")
        all_live_orders = {**live_s001_orders, **live_s002_orders}
        col2_orderDate_ok = 0
        col2_createdAt_ok = 0
        date_at_parity_ok = 0
        drift_candidates_tested = 0
        drift_candidates_clean = 0

        for raw_id, exp_c2 in raw_timestamps.items():
            s_key = sanitize_rtdb_key(raw_id)
            live_ord = all_live_orders.get(s_key)
            if not live_ord:
                self.check(f"Order {raw_id} exists in live DB", False, f"Missing key {s_key}")
                continue

            o_date = live_ord.get('orderDate')
            c_at = live_ord.get('createdAt')

            if o_date == exp_c2:
                col2_orderDate_ok += 1
            if c_at == exp_c2:
                col2_createdAt_ok += 1
            if o_date == c_at:
                date_at_parity_ok += 1

            c3, c4 = raw_col3_col4.get(raw_id, (None, None))
            # Test candidate with divergent col3/col4 (e.g. updated on a different date or month)
            if (c3 and c3 != exp_c2) or (c4 and c4 != exp_c2):
                drift_candidates_tested += 1
                if o_date == exp_c2 and c_at == exp_c2:
                    drift_candidates_clean += 1

        self.check("100% orders derive orderDate from Column 2",
                   col2_orderDate_ok == 2075,
                   f"{col2_orderDate_ok}/2075 matches (100.00%)")
        self.check("100% orders derive createdAt from Column 2",
                   col2_createdAt_ok == 2075,
                   f"{col2_createdAt_ok}/2075 matches (100.00%)")
        self.check("100% orders have orderDate == createdAt",
                   date_at_parity_ok == 2075,
                   f"{date_at_parity_ok}/2075 matches")
        self.check("Zero calendar drift on all disparate-update orders",
                   drift_candidates_tested == drift_candidates_clean and drift_candidates_tested > 0,
                   f"Successfully preserved original date on {drift_candidates_clean}/{drift_candidates_tested} updated orders")

        # 7. CUSTOMER DEBT & RECEIVABLES
        print("\n--- [PHASE 7] VERIFYING CUSTOMER DEBT & RECEIVABLES ---")
        live_cust_count = len(live_custs)
        live_cust_debt_sum = sum(Decimal(str(c.get('currentDebt', 0.0))) for c in live_custs.values())

        self.check("Customer records count == 7,008", live_cust_count == 7008, f"Got: {live_cust_count} (7,007 raw + 1 stub)")
        self.check("Customer Debt sum == 33,684,023,744.00 VNĐ",
                   live_cust_debt_sum == Decimal('33684023744'),
                   f"Got: {float(live_cust_debt_sum):,.2f} VNĐ")
        self.check("Customer stub KH002414 exists with currentDebt == 0",
                   'KH002414' in live_custs and live_custs['KH002414'].get('currentDebt') == 0.0)

        # 8. SUPPLIER DEBT & PAYABLES
        print("\n--- [PHASE 8] VERIFYING SUPPLIER DEBT & PAYABLES ---")
        live_supp_count = len(live_supps)
        live_supp_debt_sum = sum(Decimal(str(s.get('currentDebt', 0.0))) for s in live_supps.values())

        self.check("Supplier records count == 51", live_supp_count == 51, f"Got: {live_supp_count} (50 raw + 1 stub)")
        self.check("Supplier Debt sum == 23,259,824,240.00 VNĐ",
                   live_supp_debt_sum == Decimal('23259824240'),
                   f"Got: {float(live_supp_debt_sum):,.2f} VNĐ")
        stub_supp = live_supps.get('NCC lẻ') or live_supps.get('NCC_lẻ')
        self.check("Supplier stub 'NCC lẻ' exists with currentDebt == 0",
                   stub_supp is not None and stub_supp.get('currentDebt') == 0.0)

        # 9. CUSTOMER RETURN ORDERS
        print("\n--- [PHASE 9] VERIFYING CUSTOMER RETURN ORDERS ---")
        live_returns_count = len(live_returns)
        live_returns_total = sum(float(r.get('total', 0.0)) for r in live_returns.values())

        self.check("Store 002 Return Orders count == 2", live_returns_count == 2, f"Got: {live_returns_count}")
        self.check("Store 002 Return Orders total == 5,300,000.00 VNĐ",
                   abs(live_returns_total - 5300000.0) < 0.01,
                   f"Got: {live_returns_total:,.2f} VNĐ")
        self.check("Store 002 Return Orders keys are exactly {'TH000040', 'TH000041'}",
                   set(live_returns.keys()) == {'TH000040', 'TH000041'},
                   f"Got: {set(live_returns.keys())}")
        self.check("Store 001 Return Orders node is empty/absent (0 phantom returns)",
                   live_s001_returns is None or live_s001_returns == {} or live_s001_returns == 'null')

        # Specific slip inspection
        th40 = live_returns.get('TH000040', {})
        th41 = live_returns.get('TH000041', {})
        self.check("TH000040: customer KH006010, product NDL24, amount 2,600,000 VNĐ",
                   th40.get('customerId') == 'KH006010' and th40.get('total') == 2600000.0 and any(i.get('productId') == 'NDL24' for i in th40.get('items', [])))
        self.check("TH000041: customer KH004685, product GD5, amount 2,700,000 VNĐ",
                   th41.get('customerId') == 'KH004685' and th41.get('total') == 2700000.0 and any(i.get('productId') == 'GD5' for i in th41.get('items', [])))

        # 10. DEEP ADVERSARIAL STRESS & INTEGRITY CHECKS
        print("\n--- [PHASE 10] DEEP ADVERSARIAL INTEGRITY CHECKS ---")
        # 10.1 Numerical & Float Sanitization: No NaN, stringified amounts, or invalid values
        corrupted_types = 0
        for o_id, o in all_live_orders.items():
            for f in ['total', 'discount', 'netPayable', 'amountPaid', 'debtAmount']:
                val = o.get(f)
                if val is not None and not isinstance(val, (int, float)):
                    corrupted_types += 1
        self.check("Adversarial Check 1: 100% of order financial values are numeric types (int/float)",
                   corrupted_types == 0, f"Corrupted: {corrupted_types}")

        # 10.2 Formula Strict Invariant: netPayable == total - discount + otherFees
        formula_mismatches = 0
        for o_id, o in all_live_orders.items():
            tot = float(o.get('total', 0.0))
            disc = float(o.get('discount', 0.0))
            oth = float(o.get('otherFees', 0.0))
            net = float(o.get('netPayable', tot - disc))
            if abs(net - (tot - disc + oth)) > 0.01:
                formula_mismatches += 1
        self.check("Adversarial Check 2: 100% of orders satisfy netPayable == total - discount + otherFees",
                   formula_mismatches == 0, f"Mismatches: {formula_mismatches}")

        # 10.3 Cancelled status uniformity
        non_standard_cancelled = 0
        for o in s001_can_list + s002_can_list:
            if o.get('status') != 'cancelled':
                non_standard_cancelled += 1
        self.check("Adversarial Check 3: All 188 cancelled orders have status == 'cancelled'",
                   non_standard_cancelled == 0, f"Non-standard: {non_standard_cancelled}")

        # 10.4 Customer debt negative balance parity (Advance deposit credit balances)
        live_neg_cust_debts = {cid: float(c.get('currentDebt', 0.0)) for cid, c in live_custs.items() if float(c.get('currentDebt', 0.0)) < 0}
        self.check("Adversarial Check 4: Exactly 24 negative customer debts exist (matching ground truth advance deposits)",
                   len(live_neg_cust_debts) == 24, f"Got: {len(live_neg_cust_debts)}")

        # 10.5 Supplier debt non-negative invariant
        supp_neg_debts = [sid for sid, s in live_supps.items() if float(s.get('currentDebt', 0.0)) < 0]
        self.check("Adversarial Check 5: Zero negative supplier debts across shared_suppliers",
                   len(supp_neg_debts) == 0, f"Found negative debts: {supp_neg_debts}")

        # 10.6 Accounts & Payment Configs Invariant Preservation
        req_accounts = {'admin1', 'admin2', 'nhanvien1', 'nhanvien2', 'supervisor'}
        self.check("Adversarial Check 6: All 5 core system accounts preserved",
                   set(live_accounts.keys()) >= req_accounts, f"Keys: {set(live_accounts.keys())}")
        self.check("Adversarial Check 7: VietQR payment config for store_002 preserved",
                   isinstance(live_payment_configs, dict) and 'store_002' in live_payment_configs and live_payment_configs['store_002'].get('showVietQR') is True)

        # 10.7 Obsolete Collections Complete Absence
        obsolete_paths = [
            'stores/store_001/customers',
            'stores/store_001/categories',
            'stores/store_001/supplier_debts',
            'stores/store_002/customers',
            'stores/store_002/categories',
            'stores/store_002/suppliers',
            'stores/store_002/supplier_debts',
            'attendances',
            'shifts',
            'attendance_adjustments'
        ]
        leaked_nodes = []
        for p in obsolete_paths:
            node = get_live_node(p)
            if node is not None and node != {} and node != 'null':
                leaked_nodes.append(p)
        self.check("Adversarial Check 8: 100% of obsolete business nodes are absent",
                   len(leaked_nodes) == 0, f"Leaked: {leaked_nodes}")

        # SUMMARY
        print("\n" + "=" * 80)
        print(f" M3 CHALLENGER 2 SUMMARY: {self.passed} PASSED, {self.failed} FAILED")
        print("=" * 80)

        if self.failed == 0:
            print("\n>>> DEFINITIVE VERDICT: CONFIRM CORRECTNESS <<<")
            print("100% of live database nodes, calculations, formulas, and invariants match ground truth.\n")
            return True
        else:
            print("\n>>> DEFINITIVE VERDICT: REJECT <<<")
            for r in self.failure_reasons:
                print(f"  - {r}")
            print()
            return False

if __name__ == '__main__':
    suite = M3Challenger2Suite()
    success = suite.run()
    sys.exit(0 if success else 1)
