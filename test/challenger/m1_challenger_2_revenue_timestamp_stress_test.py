#!/usr/bin/env python3
"""
m1_challenger_2_revenue_timestamp_stress_test.py
Adversarial Verification Suite for Milestone 1 Data Ingestion (09/10/2026).

Authored by M1 Challenger 2 (Empirical Challenger).
Independently verifies:
1. Orders & Net Revenues Parity:
   - Store 001: 132 orders (120 active, 12 cancelled); Active Net Revenue = 639,515,000.00 VNĐ
   - Store 002: 1,943 orders (1,767 active, 176 cancelled); Active Net Revenue = 9,931,034,200.00 VNĐ
   - Total System: 2,075 orders (1,887 active, 188 cancelled); Active Net Revenue = 10,570,549,200.00 VNĐ
2. Timestamp Integrity & Anti-Drift Adversarial Stress Test:
   - All 2,075 orders verified against Column 2 ("Thời gian")
   - Specifically tests the 144 orders with Col 3 divergence (>= 60s amendment drift)
   - Specifically tests the 203 orders with Col 4 populated ("Ngày cập nhật")
   - Proves zero calendar month drift and zero date drift across all orders
   - Quantifies the simulated distortion if Col 4 or Col 3 were erroneously used
3. Receivables & Payables Debt Invariants:
   - Customer debt = 33,684,023,744.00 VNĐ (7,007 raw + 1 stub)
   - Supplier debt = 23,259,824,240.00 VNĐ (50 raw + 1 stub)
   - 100% individual entity matching between raw Excel and staged JSON payloads
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

def read_raw_excel_sheet(xlsx_path, sheet_names=('xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml')):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        shared_strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            sroot = ET.fromstring(z.read('xl/sharedStrings.xml'))
            for si in sroot.findall(f'.//{NS}si'):
                t = si.find(f'{NS}t')
                shared_strings.append(t.text if t is not None and t.text else '')

        sheet_xml = None
        for s in sheet_names:
            if s in z.namelist():
                sheet_xml = z.read(s)
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

class ChallengerTestHarness:
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
        print("M1 CHALLENGER 2: ADVERSARIAL REVENUE, TIMESTAMP & DEBT STRESS TEST")
        print("=" * 80)

        # -------------------------------------------------------------
        # SUITE 1: RAW EXCEL INVOICES RECONCILIATION
        # -------------------------------------------------------------
        print("\n--- SUITE 1: Raw Excel Invoices Parsing from First Principles ---")
        inv_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachChiTietHoaDon_KV09102026-211131-415.xlsx')
        self.check("Invoices file exists", os.path.isfile(inv_file), inv_file)

        raw_invoices = {}
        line_item_count = 0
        for r in read_raw_excel_sheet(inv_file):
            inv_code = r.get(1, '').strip()
            if not inv_code or inv_code == 'Mã hóa đơn':
                continue
            line_item_count += 1
            if inv_code not in raw_invoices:
                branch = r.get(0, '').strip()
                store_id = 'store_001' if ('đông thắng' in branch.lower() or 'dong thang' in branch.lower()) else 'store_002'
                status_raw = r.get(29, '').strip()
                is_cancelled = ('hủy' in status_raw.lower() or 'cancelled' in status_raw.lower())
                c2_iso = serial_to_iso(r.get(2))
                c3_iso = serial_to_iso(r.get(3))
                c4_raw = r.get(4, '').strip()
                c4_iso = serial_to_iso(c4_raw) if c4_raw else None

                tot_goods = Decimal(r.get(20, '0') or '0')
                disc = Decimal(r.get(21, '0') or '0')
                net_payable = Decimal(r.get(23, '0') or '0')
                paid = Decimal(r.get(24, '0') or '0')

                raw_invoices[inv_code] = {
                    'code': inv_code,
                    'store_id': store_id,
                    'is_cancelled': is_cancelled,
                    'status_raw': status_raw,
                    'col2_raw': r.get(2, '').strip(),
                    'col3_raw': r.get(3, '').strip(),
                    'col4_raw': c4_raw,
                    'c2_iso': c2_iso,
                    'c3_iso': c3_iso,
                    'c4_iso': c4_iso,
                    'total_goods': tot_goods,
                    'discount': disc,
                    'net_payable': net_payable,
                    'paid': paid,
                    'lines': []
                }
            raw_invoices[inv_code]['lines'].append({
                'prod_id': r.get(31, '').strip(),
                'qty': r.get(37, '0') or '0',
                'price': r.get(41, '0') or '0',
                'total': r.get(42, '0') or '0'
            })

        self.check("Total raw line items count", line_item_count == 3079, f"{line_item_count} lines")
        self.check("Total unique invoices count", len(raw_invoices) == 2075, f"{len(raw_invoices)} invoices")

        s1_raw = {k: v for k, v in raw_invoices.items() if v['store_id'] == 'store_001'}
        s2_raw = {k: v for k, v in raw_invoices.items() if v['store_id'] == 'store_002'}

        s1_active = [v for v in s1_raw.values() if not v['is_cancelled']]
        s1_cancelled = [v for v in s1_raw.values() if v['is_cancelled']]
        s2_active = [v for v in s2_raw.values() if not v['is_cancelled']]
        s2_cancelled = [v for v in s2_raw.values() if v['is_cancelled']]

        self.check("Store 001 total orders count", len(s1_raw) == 132, f"{len(s1_raw)} orders")
        self.check("Store 001 active orders count", len(s1_active) == 120, f"{len(s1_active)} active")
        self.check("Store 001 cancelled orders count", len(s1_cancelled) == 12, f"{len(s1_cancelled)} cancelled")

        self.check("Store 002 total orders count", len(s2_raw) == 1943, f"{len(s2_raw)} orders")
        self.check("Store 002 active orders count", len(s2_active) == 1767, f"{len(s2_active)} active")
        self.check("Store 002 cancelled orders count", len(s2_cancelled) == 176, f"{len(s2_cancelled)} cancelled")

        s1_net_rev = sum(v['net_payable'] for v in s1_active)
        s2_net_rev = sum(v['net_payable'] for v in s2_active)
        total_net_rev = s1_net_rev + s2_net_rev

        self.check("Store 001 active net revenue", s1_net_rev == Decimal('639515000.00'), f"{s1_net_rev:,.2f} VNĐ")
        self.check("Store 002 active net revenue", s2_net_rev == Decimal('9931034200.00'), f"{s2_net_rev:,.2f} VNĐ")
        self.check("System combined active net revenue", total_net_rev == Decimal('10570549200.00'), f"{total_net_rev:,.2f} VNĐ")

        # -------------------------------------------------------------
        # SUITE 2: STAGED PAYLOADS PARITY & STRUCTURAL INTEGRITY
        # -------------------------------------------------------------
        print("\n--- SUITE 2: Staged Order Payloads Validation against Raw Excel ---")
        s1_json_path = os.path.join(OUTPUT_DIR, 'store_001_orders.json')
        s2_json_path = os.path.join(OUTPUT_DIR, 'store_002_orders.json')

        self.check("Store 001 JSON exists", os.path.isfile(s1_json_path), s1_json_path)
        self.check("Store 002 JSON exists", os.path.isfile(s2_json_path), s2_json_path)

        with open(s1_json_path, 'r', encoding='utf-8') as f:
            staged_s1 = json.load(f)
        with open(s2_json_path, 'r', encoding='utf-8') as f:
            staged_s2 = json.load(f)

        self.check("Staged Store 001 orders count", len(staged_s1) == 132, f"{len(staged_s1)} entities")
        self.check("Staged Store 002 orders count", len(staged_s2) == 1943, f"{len(staged_s2)} entities")

        staged_all = {**staged_s1, **staged_s2}
        self.check("Combined staged orders count", len(staged_all) == 2075, f"{len(staged_all)} entities")

        staged_s1_active_rev = sum(Decimal(str(o['netPayable'])) for o in staged_s1.values() if o['status'] != 'cancelled')
        staged_s2_active_rev = sum(Decimal(str(o['netPayable'])) for o in staged_s2.values() if o['status'] != 'cancelled')
        staged_total_active_rev = staged_s1_active_rev + staged_s2_active_rev

        self.check("Staged Store 001 active net revenue", staged_s1_active_rev == Decimal('639515000.0'), f"{staged_s1_active_rev:,.2f} VNĐ")
        self.check("Staged Store 002 active net revenue", staged_s2_active_rev == Decimal('9931034200.0'), f"{staged_s2_active_rev:,.2f} VNĐ")
        self.check("Staged total active net revenue", staged_total_active_rev == Decimal('10570549200.0'), f"{staged_total_active_rev:,.2f} VNĐ")

        # -------------------------------------------------------------
        # SUITE 3: ADVERSARIAL TIMESTAMP INTEGRITY & DRIFT ANALYSIS
        # -------------------------------------------------------------
        print("\n--- SUITE 3: Adversarial Timestamp Integrity & Drift Stress Test ---")

        # 3.1 Verify 100% of 2,075 staged orders match Col 2
        order_date_mismatches = []
        created_at_mismatches = []
        for raw_code, raw_ord in raw_invoices.items():
            staged_key = sanitize_key(raw_code)
            staged_ord = staged_all.get(staged_key)
            if not staged_ord:
                self.check(f"Staged entity exists for {raw_code}", False, f"Key {staged_key} missing")
                continue
            if staged_ord.get('orderDate') != raw_ord['c2_iso']:
                order_date_mismatches.append((raw_code, staged_ord.get('orderDate'), raw_ord['c2_iso']))
            if staged_ord.get('createdAt') != raw_ord['c2_iso']:
                created_at_mismatches.append((raw_code, staged_ord.get('createdAt'), raw_ord['c2_iso']))

        self.check("100% (2,075/2,075) orders: orderDate derived strictly from Col 2",
                   len(order_date_mismatches) == 0,
                   f"{len(order_date_mismatches)} mismatches")
        self.check("100% (2,075/2,075) orders: createdAt derived strictly from Col 2",
                   len(created_at_mismatches) == 0,
                   f"{len(created_at_mismatches)} mismatches")

        # 3.2 Adversarial stress test on the 203 orders with non-empty Col 4 ("Ngày cập nhật")
        col4_populated_orders = {k: v for k, v in raw_invoices.items() if v['col4_raw']}
        self.check("Raw invoices with non-empty Col 4 count", len(col4_populated_orders) == 203, f"{len(col4_populated_orders)} orders")

        # Check month drift if Col 4 had been used instead of Col 2
        col4_month_drift = []
        col4_day_drift = []
        for inv_code, raw in col4_populated_orders.items():
            dt_sale = datetime.fromisoformat(raw['c2_iso'])
            dt_update = datetime.fromisoformat(raw['c4_iso'])
            if (dt_sale.year, dt_sale.month) != (dt_update.year, dt_update.month):
                col4_month_drift.append((inv_code, raw['c2_iso'], raw['c4_iso'], raw['net_payable']))
            if dt_sale.date() != dt_update.date():
                col4_day_drift.append((inv_code, raw['c2_iso'], raw['c4_iso']))

        print(f"  [INFO] Adversarial simulation: if Col 4 had been used for orderDate:")
        print(f"         -> {len(col4_month_drift)} orders would drift across CALENDAR MONTHS")
        print(f"         -> {len(col4_day_drift)} orders would drift across CALENDAR DAYS")
        distorted_month_rev = sum(x[3] for x in col4_month_drift)
        print(f"         -> Net revenue distorted by month drift: {distorted_month_rev:,.2f} VNĐ")

        # Verify all 203 Col 4 orders in staged payload have orderDate == Col 2 (zero drift)
        staged_col4_drift = [
            k for k in col4_populated_orders
            if staged_all[sanitize_key(k)]['orderDate'] != col4_populated_orders[k]['c2_iso']
        ]
        self.check("Col 4 populated orders (203/203) exhibit ZERO month/date drift in staged data",
                   len(staged_col4_drift) == 0,
                   f"{len(staged_col4_drift)} drift instances")

        # 3.3 Adversarial stress test on the 144 orders with Col 3 divergence (creation time drift >= 60s)
        col3_divergent_orders = {}
        for inv_code, raw in raw_invoices.items():
            dt_sale = datetime.fromisoformat(raw['c2_iso'])
            dt_create = datetime.fromisoformat(raw['c3_iso'])
            if abs((dt_create - dt_sale).total_seconds()) >= 60:
                col3_divergent_orders[inv_code] = raw

        self.check("Raw invoices with Col 3 vs Col 2 divergence (>= 60s amendment)",
                   len(col3_divergent_orders) == 144,
                   f"{len(col3_divergent_orders)} orders")

        # Check how many of these 144 orders cross dates or months
        col3_date_cross = [
            k for k, v in col3_divergent_orders.items()
            if datetime.fromisoformat(v['c2_iso']).date() != datetime.fromisoformat(v['c3_iso']).date()
        ]
        col3_month_cross = [
            k for k, v in col3_divergent_orders.items()
            if (datetime.fromisoformat(v['c2_iso']).year, datetime.fromisoformat(v['c2_iso']).month) !=
               (datetime.fromisoformat(v['c3_iso']).year, datetime.fromisoformat(v['c3_iso']).month)
        ]
        print(f"  [INFO] Analysis of 144 modified orders:")
        print(f"         -> {len(col3_date_cross)} orders cross date boundaries between sale and creation")
        print(f"         -> {len(col3_month_cross)} orders cross month boundaries between sale and creation")

        # Verify all 144 orders in staged payload have orderDate == Col 2 (zero drift)
        staged_col3_drift = [
            k for k in col3_divergent_orders
            if staged_all[sanitize_key(k)]['orderDate'] != col3_divergent_orders[k]['c2_iso']
        ]
        self.check("144 modified orders exhibit ZERO month/date drift in staged data",
                   len(staged_col3_drift) == 0,
                   f"{len(staged_col3_drift)} drift instances")

        # -------------------------------------------------------------
        # SUITE 4: CUSTOMER DEBT INVARIANT VERIFICATION
        # -------------------------------------------------------------
        print("\n--- SUITE 4: Customer Debt Invariants Verification ---")
        cust_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachKhachHang_KV09102026-211724-899.xlsx')
        self.check("Customers file exists", os.path.isfile(cust_file), cust_file)

        raw_customers = {}
        raw_cust_debt_sum = Decimal(0)
        for r in read_raw_excel_sheet(cust_file):
            cid = r.get(2, '').strip()
            if not cid or cid == 'Mã khách hàng':
                continue
            debt = Decimal(r.get(30, '0') or '0')
            raw_customers[cid] = {
                'name': r.get(3, '').strip(),
                'phone': r.get(5, '').strip(),
                'debt': debt
            }
            raw_cust_debt_sum += debt

        self.check("Raw customers record count", len(raw_customers) == 7007, f"{len(raw_customers)} customers")
        self.check("Raw customer receivables debt total",
                   raw_cust_debt_sum == Decimal('33684023744.00'),
                   f"{raw_cust_debt_sum:,.2f} VNĐ")

        staged_cust_file = os.path.join(OUTPUT_DIR, 'shared_customers.json')
        with open(staged_cust_file, 'r', encoding='utf-8') as f:
            staged_customers = json.load(f)

        self.check("Staged shared_customers count (7,007 raw + 1 KH002414 stub)",
                   len(staged_customers) == 7008,
                   f"{len(staged_customers)} customers")

        staged_cust_debt_sum = sum(Decimal(str(c.get('currentDebt', 0.0))) for c in staged_customers.values())
        self.check("Staged customer receivables debt total",
                   staged_cust_debt_sum == Decimal('33684023744.00'),
                   f"{staged_cust_debt_sum:,.2f} VNĐ")

        # Verify 1-to-1 parity for all 7,007 customers
        cust_debt_discrepancies = []
        for cid, rc in raw_customers.items():
            s_key = sanitize_key(cid)
            sc = staged_customers.get(s_key)
            if not sc:
                cust_debt_discrepancies.append((cid, "Missing in staged payload", None))
                continue
            staged_d = Decimal(str(sc.get('currentDebt', 0.0)))
            if staged_d != rc['debt']:
                cust_debt_discrepancies.append((cid, rc['debt'], staged_d))

        self.check("1-to-1 customer debt parity (7,007/7,007 matched with 0 delta)",
                   len(cust_debt_discrepancies) == 0,
                   f"{len(cust_debt_discrepancies)} mismatches")

        # Check stub KH002414
        stub_c = staged_customers.get('KH002414')
        self.check("Customer referential integrity stub KH002414 exists",
                   stub_c is not None and stub_c.get('currentDebt') == 0.0,
                   f"status={stub_c.get('status') if stub_c else 'missing'}")

        # -------------------------------------------------------------
        # SUITE 5: SUPPLIER DEBT INVARIANT VERIFICATION
        # -------------------------------------------------------------
        print("\n--- SUITE 5: Supplier Debt Invariants Verification ---")
        supp_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachNhaCungCap_KV09102026-210945-177.xlsx')
        self.check("Suppliers file exists", os.path.isfile(supp_file), supp_file)

        raw_suppliers = {}
        raw_supp_debt_sum = Decimal(0)
        for r in read_raw_excel_sheet(supp_file):
            sid = r.get(0, '').strip()
            if not sid or sid == 'Mã nhà cung cấp':
                continue
            debt = Decimal(r.get(8, '0') or '0')
            raw_suppliers[sid] = {
                'name': r.get(1, '').strip(),
                'debt': debt
            }
            raw_supp_debt_sum += debt

        self.check("Raw suppliers record count", len(raw_suppliers) == 50, f"{len(raw_suppliers)} suppliers")
        self.check("Raw supplier payables debt total",
                   raw_supp_debt_sum == Decimal('23259824240.00'),
                   f"{raw_supp_debt_sum:,.2f} VNĐ")

        staged_supp_file = os.path.join(OUTPUT_DIR, 'shared_suppliers.json')
        with open(staged_supp_file, 'r', encoding='utf-8') as f:
            staged_suppliers = json.load(f)

        self.check("Staged shared_suppliers count (50 raw + 1 NCC lẻ stub)",
                   len(staged_suppliers) == 51,
                   f"{len(staged_suppliers)} suppliers")

        staged_supp_debt_sum = sum(Decimal(str(s.get('currentDebt', 0.0))) for s in staged_suppliers.values())
        self.check("Staged supplier payables debt total",
                   staged_supp_debt_sum == Decimal('23259824240.00'),
                   f"{staged_supp_debt_sum:,.2f} VNĐ")

        # Verify 1-to-1 parity for all 50 suppliers
        supp_debt_discrepancies = []
        for sid, rs in raw_suppliers.items():
            s_key = sanitize_key(sid)
            ss = staged_suppliers.get(s_key)
            if not ss:
                supp_debt_discrepancies.append((sid, "Missing in staged payload", None))
                continue
            staged_d = Decimal(str(ss.get('currentDebt', 0.0)))
            if staged_d != rs['debt']:
                supp_debt_discrepancies.append((sid, rs['debt'], staged_d))

        self.check("1-to-1 supplier debt parity (50/50 matched with 0 delta)",
                   len(supp_debt_discrepancies) == 0,
                   f"{len(supp_debt_discrepancies)} mismatches")

        # Check stub NCC lẻ
        stub_s = staged_suppliers.get('NCC_le') or staged_suppliers.get('NCC lẻ')
        self.check("Supplier referential integrity stub NCC lẻ exists",
                   stub_s is not None and stub_s.get('currentDebt') == 0.0,
                   f"id={stub_s.get('id') if stub_s else 'missing'}")

        # -------------------------------------------------------------
        # SUITE 6: MONTHLY REVENUE DISTRIBUTION & RECONCILIATION
        # -------------------------------------------------------------
        print("\n--- SUITE 6: Monthly Revenue Distribution Verification ---")
        monthly_raw = defaultdict(lambda: {'s1': Decimal(0), 's2': Decimal(0)})
        for raw in raw_invoices.values():
            if raw['is_cancelled']:
                continue
            month_key = raw['c2_iso'][:7]
            if raw['store_id'] == 'store_001':
                monthly_raw[month_key]['s1'] += raw['net_payable']
            else:
                monthly_raw[month_key]['s2'] += raw['net_payable']

        monthly_staged = defaultdict(lambda: {'s1': Decimal(0), 's2': Decimal(0)})
        for ord_obj in staged_all.values():
            if ord_obj['status'] == 'cancelled':
                continue
            month_key = ord_obj['orderDate'][:7]
            if ord_obj['storeId'] == 'store_001':
                monthly_staged[month_key]['s1'] += Decimal(str(ord_obj['netPayable']))
            else:
                monthly_staged[month_key]['s2'] += Decimal(str(ord_obj['netPayable']))

        all_months = sorted(set(monthly_raw.keys()) | set(monthly_staged.keys()))
        month_matches = True
        for m in all_months:
            r1 = monthly_raw[m]['s1']
            r2 = monthly_raw[m]['s2']
            s1 = monthly_staged[m]['s1']
            s2 = monthly_staged[m]['s2']
            if r1 != s1 or r2 != s2:
                month_matches = False
                print(f"  [MISMATCH] Month {m}: Raw (s1={r1}, s2={r2}) vs Staged (s1={s1}, s2={s2})")
            else:
                print(f"  [PASS] Month {m} Revenue Parity: Store 001={s1:,.2f} VNĐ, Store 002={s2:,.2f} VNĐ (Total={s1+s2:,.2f} VNĐ)")

        self.check("All 10 calendar months match raw Excel calculations with 0 delta", month_matches)

        # -------------------------------------------------------------
        # FINAL VERDICT
        # -------------------------------------------------------------
        print("\n" + "=" * 80)
        total_checks = self.passed_checks + self.failed_checks
        print(f"TEST EXECUTION COMPLETED: {self.passed_checks}/{total_checks} CHECKS PASSED")
        print("=" * 80)

        if self.failed_checks == 0:
            print("\n>>> FINAL VERDICT: CONFIRM CORRECTNESS <<<")
            print("All orders, revenues, timestamps, and customer/supplier debt invariants 100% verified!\n")
            return True
        else:
            print(f"\n>>> FINAL VERDICT: REJECT ({self.failed_checks} failures) <<<")
            for d in self.discrepancies:
                print(f"  - {d}")
            print()
            return False

if __name__ == '__main__':
    harness = ChallengerTestHarness()
    success = harness.run_all()
    sys.exit(0 if success else 1)
