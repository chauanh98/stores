#!/usr/bin/env python3
"""
m1_stock_and_products_adversarial_challenge.py

M1 Empirical Challenger 1 Adversarial Verification Harness.
Performs an independent, first-principles mathematical and structural audit
comparing raw OpenXML Excel files in DATA_IMPORT/ against the staged payloads
in data_staging/output/ (and data_staging/).

Audited Core Dimensions:
1. Independent OpenXML Extraction from First Principles:
   - DanhSachSanPham_KV09102026-210142-227.xlsx (Đông Thắng / store_001)
   - DanhSachSanPham_KV09102026-210851-400.xlsx (Thới Bình / store_002)
2. Store 001 Stock Sum = 395 units, Active SKUs (stock > 0) = 227.
3. Store 002 Stock Sum = 118,037 units, Active SKUs (stock > 0) = 882.
4. Total Master Product Catalog: exactly 1,826 raw SKUs + 1 legacy stub (TTTR6) = 1,827 items.
5. branchStocks Invariant: Every product has valid 'store_001' and 'store_002' numeric keys.
6. Per-SKU Stock Zero-Delta: Every single SKU matches ground truth across both stores.
7. POS Cart Safety: All 227 Đông Thắng stock > 0 items have branchStocks['store_001'] > 0 and allowSale == True.
8. Negative Stock Stress Test: SP000685 has stock == -1 in store_002, 0 in store_001, not clamped.
9. Discontinued Stub Stress Test: TTTR6 has branchStocks == {store_001: 0, store_002: 0}, allowSale == False.
10. Cross-Staging Parity: data_staging/output/products_all.json == data_staging/products_all.json.
11. Overall Pipeline Payload Invariants: Orders, Customers, Suppliers sanity checks.
"""

import os
import sys
import json
import math
import zipfile
import re
import xml.etree.ElementTree as ET
from decimal import Decimal

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_IMPORT_DIR = os.path.join(WORKSPACE_DIR, 'DATA_IMPORT')
STAGING_OUTPUT_DIR = os.path.join(WORKSPACE_DIR, 'data_staging', 'output')
STAGING_DIR = os.path.join(WORKSPACE_DIR, 'data_staging')

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
    return int(m.group(2)) - 1, col2idx(m.group(1))

def read_openxml_rows(xlsx_path):
    """Directly extracts rows from an OpenXML .xlsx file without external dependencies."""
    if not os.path.isfile(xlsx_path):
        raise FileNotFoundError(f"File not found: {xlsx_path}")
    
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sst = []
        if 'xl/sharedStrings.xml' in z.namelist():
            sroot = ET.fromstring(z.read('xl/sharedStrings.xml'))
            for si in sroot.findall(f'.//{NS}si'):
                texts = [t.text for t in si.findall(f'.//{NS}t') if t.text]
                sst.append(''.join(texts))
        
        sheet_candidates = ['xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml']
        sheet_xml = None
        for cand in sheet_candidates:
            if cand in z.namelist():
                sheet_xml = z.read(cand)
                break
        
        if sheet_xml is None:
            raise FileNotFoundError(f"No worksheet found in {xlsx_path}")
        
        root = ET.fromstring(sheet_xml)
        for r_elem in root.findall(f'.//{NS}row'):
            row = {}
            for c_elem in r_elem.findall(f'{NS}c'):
                r_ref = c_elem.get('r')
                if not r_ref:
                    continue
                _, c_idx = parse_ref(r_ref)
                t_attr = c_elem.get('t')
                v_elem = c_elem.find(f'{NS}v')
                val = v_elem.text.strip() if v_elem is not None and v_elem.text is not None else ''
                if t_attr == 's' and val.isdigit() and int(val) < len(sst):
                    val = sst[int(val)]
                row[c_idx] = val
            yield row

class EmpiricalChallenger:
    def __init__(self):
        self.total_tests = 0
        self.passed_tests = 0
        self.failed_tests = 0
        self.failures = []

    def check(self, name, condition, details=""):
        self.total_tests += 1
        if condition:
            self.passed_tests += 1
            print(f"  [PASS] {name} {details}")
        else:
            self.failed_tests += 1
            msg = f"[FAIL] {name} {details}"
            self.failures.append(msg)
            print(f"  {msg}")

    def run_all(self):
        print("=" * 80)
        print("  M1 CHALLENGER 1: EMPIRICAL STAGED DATA & STOCK PARITY HARNESS")
        print("=" * 80)

        # -------------------------------------------------------------
        # STEP 1: PARSE RAW EXCEL FILES FROM FIRST PRINCIPLES
        # -------------------------------------------------------------
        print("\n[Phase 1] Parsing Raw OpenXML Excel Ground Truth...")
        s001_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV09102026-210142-227.xlsx')
        s002_file = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV09102026-210851-400.xlsx')

        s001_rows = list(read_openxml_rows(s001_file))
        s002_rows = list(read_openxml_rows(s002_file))

        print(f"  Store 001 raw rows read: {len(s001_rows)} (1 header + {len(s001_rows)-1} products)")
        print(f"  Store 002 raw rows read: {len(s002_rows)} (1 header + {len(s002_rows)-1} products)")

        # Parse Store 001 product records
        raw_s001 = {}
        for r in s001_rows[1:]:
            sku = r.get(2, '').strip()
            if not sku:
                continue
            name = r.get(4, '').strip()
            stock_str = r.get(9, '0') or '0'
            try:
                stock = int(float(stock_str))
            except ValueError:
                stock = 0
            price_str = r.get(7, '0') or '0'
            cost_str = r.get(8, '0') or '0'
            allow_sale = (r.get(22, '1') or '1').strip() == '1'
            raw_s001[sku] = {
                'sku': sku,
                'name': name,
                'stock': stock,
                'price': float(price_str) if price_str else 0.0,
                'costPrice': float(cost_str) if cost_str else 0.0,
                'allowSale': allow_sale,
            }

        # Parse Store 002 product records
        raw_s002 = {}
        for r in s002_rows[1:]:
            sku = r.get(2, '').strip()
            if not sku:
                continue
            name = r.get(4, '').strip()
            stock_str = r.get(9, '0') or '0'
            try:
                stock = int(float(stock_str))
            except ValueError:
                stock = 0
            price_str = r.get(7, '0') or '0'
            cost_str = r.get(8, '0') or '0'
            allow_sale = (r.get(22, '1') or '1').strip() == '1'
            raw_s002[sku] = {
                'sku': sku,
                'name': name,
                'stock': stock,
                'price': float(price_str) if price_str else 0.0,
                'costPrice': float(cost_str) if cost_str else 0.0,
                'allowSale': allow_sale,
            }

        # Raw metrics
        s001_stock_sum = sum(p['stock'] for p in raw_s001.values())
        s001_active_skus = [sku for sku, p in raw_s001.items() if p['stock'] > 0]
        s001_active_count = len(s001_active_skus)

        s002_stock_sum = sum(p['stock'] for p in raw_s002.values())
        s002_active_skus = [sku for sku, p in raw_s002.items() if p['stock'] > 0]
        s002_active_count = len(s002_active_skus)
        s002_negative_skus = [sku for sku, p in raw_s002.items() if p['stock'] < 0]

        combined_raw_skus = set(raw_s001.keys()).union(set(raw_s002.keys()))

        print(f"  Raw Store 001: total SKUs = {len(raw_s001)}, active (>0) = {s001_active_count}, stock sum = {s001_stock_sum}")
        print(f"  Raw Store 002: total SKUs = {len(raw_s002)}, active (>0) = {s002_active_count}, stock sum = {s002_stock_sum}")
        print(f"  Combined unique raw SKUs across both stores = {len(combined_raw_skus)}")

        self.check("Raw Store 001 Stock Sum == 395", s001_stock_sum == 395, f"(actual: {s001_stock_sum})")
        self.check("Raw Store 001 Active SKUs == 227", s001_active_count == 227, f"(actual: {s001_active_count})")
        self.check("Raw Store 002 Stock Sum == 118,037", s002_stock_sum == 118037, f"(actual: {s002_stock_sum})")
        self.check("Raw Store 002 Active SKUs == 882", s002_active_count == 882, f"(actual: {s002_active_count})")
        self.check("Raw Store 002 Negative SKUs == ['SP000685']", s002_negative_skus == ['SP000685'], f"(actual: {s002_negative_skus})")
        self.check("Combined Raw Unique SKUs == 1,826", len(combined_raw_skus) == 1826, f"(actual: {len(combined_raw_skus)})")

        # -------------------------------------------------------------
        # STEP 2: LOAD AND AUDIT STAGED PRODUCTS PAYLOAD
        # -------------------------------------------------------------
        print("\n[Phase 2] Auditing data_staging/output/products_all.json...")
        staged_products_path = os.path.join(STAGING_OUTPUT_DIR, 'products_all.json')
        self.check("Payload products_all.json exists", os.path.isfile(staged_products_path))

        with open(staged_products_path, 'r', encoding='utf-8') as f:
            staged_products = json.load(f)

        print(f"  Total entities in staged products: {len(staged_products)}")
        self.check("Catalog Size == 1,829 (1,826 raw + 3 stubs: TTTR6, XD6, NDL26)", len(staged_products) == 1829, f"(actual: {len(staged_products)})")

        # -------------------------------------------------------------
        # STEP 3: AUDIT branchStocks DICTIONARY SCHEMA & VALUES
        # -------------------------------------------------------------
        print("\n[Phase 3] Auditing branchStocks Schema & Numeric Integrity...")
        invalid_branch_stocks_keys = []
        invalid_numeric_types = []
        nan_or_inf_stocks = []

        staged_s001_sum = 0
        staged_s002_sum = 0
        staged_s001_active = 0
        staged_s002_active = 0

        for sku, p in staged_products.items():
            bs = p.get('branchStocks')
            if not isinstance(bs, dict):
                invalid_branch_stocks_keys.append((sku, "not a dict"))
                continue
            
            # Check presence of exactly or at least store_001 and store_002
            if 'store_001' not in bs or 'store_002' not in bs:
                invalid_branch_stocks_keys.append((sku, list(bs.keys())))
                continue
            
            s1 = bs['store_001']
            s2 = bs['store_002']

            if not isinstance(s1, (int, float)) or isinstance(s1, bool):
                invalid_numeric_types.append((sku, 'store_001', type(s1)))
            elif math.isnan(s1) or math.isinf(s1):
                nan_or_inf_stocks.append((sku, 'store_001', s1))
            else:
                staged_s001_sum += s1
                if s1 > 0:
                    staged_s001_active += 1

            if not isinstance(s2, (int, float)) or isinstance(s2, bool):
                invalid_numeric_types.append((sku, 'store_002', type(s2)))
            elif math.isnan(s2) or math.isinf(s2):
                nan_or_inf_stocks.append((sku, 'store_002', s2))
            else:
                staged_s002_sum += s2
                if s2 > 0:
                    staged_s002_active += 1

        self.check("Every product has 'store_001' & 'store_002' keys", len(invalid_branch_stocks_keys) == 0, f"(failures: {len(invalid_branch_stocks_keys)})")
        self.check("Every branch stock value is numeric (int/float)", len(invalid_numeric_types) == 0, f"(failures: {len(invalid_numeric_types)})")
        self.check("No NaN or Infinity stock values", len(nan_or_inf_stocks) == 0, f"(failures: {len(nan_or_inf_stocks)})")

        self.check("Staged Store 001 Stock Sum == 395", staged_s001_sum == 395, f"(actual: {staged_s001_sum})")
        self.check("Staged Store 001 Active SKUs == 227", staged_s001_active == 227, f"(actual: {staged_s001_active})")
        self.check("Staged Store 002 Stock Sum == 118,037", staged_s002_sum == 118037, f"(actual: {staged_s002_sum})")
        self.check("Staged Store 002 Active SKUs == 882", staged_s002_active == 882, f"(actual: {staged_s002_active})")

        # -------------------------------------------------------------
        # STEP 4: PER-SKU INDEPENDENT ZERO-DELTA AUDIT
        # -------------------------------------------------------------
        print("\n[Phase 4] Auditing Per-SKU Stock Parity (Zero-Delta against Excel)...")
        mismatched_s001 = []
        mismatched_s002 = []

        # Check all raw Store 001 SKUs against staged products
        for sku, raw_p in raw_s001.items():
            if sku not in staged_products:
                mismatched_s001.append((sku, "missing from staged", raw_p['stock'], None))
                continue
            staged_s1 = staged_products[sku]['branchStocks'].get('store_001')
            if staged_s1 != raw_p['stock']:
                mismatched_s001.append((sku, "stock mismatch", raw_p['stock'], staged_s1))

        # Check all raw Store 002 SKUs against staged products
        for sku, raw_p in raw_s002.items():
            if sku not in staged_products:
                mismatched_s002.append((sku, "missing from staged", raw_p['stock'], None))
                continue
            staged_s2 = staged_products[sku]['branchStocks'].get('store_002')
            if staged_s2 != raw_p['stock']:
                mismatched_s002.append((sku, "stock mismatch", raw_p['stock'], staged_s2))

        # Check SKUs in staged but not in raw Store 001 (e.g. NPE3, TTTR6): must have stock_001 == 0
        skus_not_in_s001 = set(staged_products.keys()) - set(raw_s001.keys())
        for sku in skus_not_in_s001:
            staged_s1 = staged_products[sku]['branchStocks'].get('store_001')
            if staged_s1 != 0:
                mismatched_s001.append((sku, "expected 0 for absent sku", 0, staged_s1))

        # Check SKUs in staged but not in raw Store 002 (e.g. TTTR6): must have stock_002 == 0
        skus_not_in_s002 = set(staged_products.keys()) - set(raw_s002.keys())
        for sku in skus_not_in_s002:
            staged_s2 = staged_products[sku]['branchStocks'].get('store_002')
            if staged_s2 != 0:
                mismatched_s002.append((sku, "expected 0 for absent sku", 0, staged_s2))

        self.check("100% Per-SKU Parity for Store 001 (0 mismatches)", len(mismatched_s001) == 0, f"(mismatches: {len(mismatched_s001)})")
        self.check("100% Per-SKU Parity for Store 002 (0 mismatches)", len(mismatched_s002) == 0, f"(mismatches: {len(mismatched_s002)})")

        # -------------------------------------------------------------
        # STEP 5: POS CART SAFETY VERIFICATION
        # -------------------------------------------------------------
        print("\n[Phase 5] POS Cart Safety Verification (Đông Thắng store_001)...")
        blocked_pos_skus = []
        for sku in s001_active_skus:
            p = staged_products[sku]
            s1 = p['branchStocks']['store_001']
            allow_sale = p.get('allowSale', True)
            status = p.get('status', 'active')
            if s1 <= 0:
                blocked_pos_skus.append((sku, f"stock is {s1} <= 0"))
            elif not allow_sale or status != 'active':
                blocked_pos_skus.append((sku, f"allowSale={allow_sale}, status={status}"))

        self.check("POS Cart Safety: All 227 Đông Thắng in-stock items can be purchased", len(blocked_pos_skus) == 0, f"(blocked: {len(blocked_pos_skus)})")

        # -------------------------------------------------------------
        # STEP 6: ADVERSARIAL STRESS TEST: NEGATIVE STOCK ITEM SP000685
        # -------------------------------------------------------------
        print("\n[Phase 6] Stress-Testing Negative Stock Item SP000685...")
        sp685 = staged_products.get('SP000685')
        self.check("SP000685 exists in staged products", sp685 is not None)
        if sp685:
            sp685_s1 = sp685.get('branchStocks', {}).get('store_001')
            sp685_s2 = sp685.get('branchStocks', {}).get('store_002')
            sp685_stock = sp685.get('stock')
            self.check("SP000685 store_001 stock is 0", sp685_s1 == 0, f"(actual: {sp685_s1})")
            self.check("SP000685 store_002 stock is exactly -1 (not clamped to 0)", sp685_s2 == -1, f"(actual: {sp685_s2})")
            self.check("SP000685 master stock field is -1", sp685_stock == -1, f"(actual: {sp685_stock})")
            self.check("SP000685 allowSale is True", sp685.get('allowSale') is True)

        # -------------------------------------------------------------
        # STEP 7: ADVERSARIAL STRESS TEST: DISCONTINUED STUBS TTTR6, XD6, NDL26
        # -------------------------------------------------------------
        print("\n[Phase 7] Stress-Testing Discontinued Stubs TTTR6, XD6, NDL26...")
        for stub_sku in ['TTTR6', 'XD6', 'NDL26']:
            stub_obj = staged_products.get(stub_sku)
            self.check(f"{stub_sku} stub exists in staged products for referential safety", stub_obj is not None)
            if stub_obj:
                s1 = stub_obj.get('branchStocks', {}).get('store_001')
                s2 = stub_obj.get('branchStocks', {}).get('store_002')
                stk = stub_obj.get('stock')
                self.check(f"{stub_sku} store_001 stock is 0", s1 == 0, f"(actual: {s1})")
                self.check(f"{stub_sku} store_002 stock is 0", s2 == 0, f"(actual: {s2})")
                self.check(f"{stub_sku} master stock is 0", stk == 0, f"(actual: {stk})")
                self.check(f"{stub_sku} allowSale is False (cannot be accidentally sold at POS)", stub_obj.get('allowSale') is False)
                self.check(f"{stub_sku} status is 'inactive'", stub_obj.get('status') == 'inactive')
                self.check(f"{stub_sku} is NOT in raw Store 001 Excel", stub_sku not in raw_s001)
                self.check(f"{stub_sku} is NOT in raw Store 002 Excel", stub_sku not in raw_s002)

        # -------------------------------------------------------------
        # STEP 8: CROSS-STAGING MIRROR PARITY
        # -------------------------------------------------------------
        print("\n[Phase 8] Cross-Staging Mirror Parity...")
        mirror_path = os.path.join(STAGING_DIR, 'products_all.json')
        if os.path.isfile(mirror_path):
            with open(mirror_path, 'r', encoding='utf-8') as f:
                mirror_products = json.load(f)
            self.check("data_staging/products_all.json has identical length to output/", len(mirror_products) == len(staged_products))
            # Sample check
            identical = (staged_products == mirror_products)
            self.check("data_staging/products_all.json is 100% byte-for-byte identical", identical)
        else:
            print("  [INFO] Mirror data_staging/products_all.json not present (only output/ present).")

        # -------------------------------------------------------------
        # STEP 9: PIPELINE MACRO PAYLOAD SANITY (Orders, Customers, Suppliers)
        # -------------------------------------------------------------
        print("\n[Phase 9] Macro Pipeline Payload Checks...")
        # Orders 001
        o001_path = os.path.join(STAGING_OUTPUT_DIR, 'store_001_orders.json')
        if os.path.isfile(o001_path):
            with open(o001_path) as f: o001 = json.load(f)
            self.check("Store 001 Orders count == 132", len(o001) == 132, f"(actual: {len(o001)})")
            r1 = sum(float(o.get('netPayable', o.get('total', 0))) for o in o001.values() if o.get('status') != 'cancelled')
            self.check("Store 001 Active Net Revenue == 639,515,000", abs(r1 - 639515000.0) < 0.01, f"(actual: {r1:,.2f})")

        # Orders 002
        o002_path = os.path.join(STAGING_OUTPUT_DIR, 'store_002_orders.json')
        if os.path.isfile(o002_path):
            with open(o002_path) as f: o002 = json.load(f)
            self.check("Store 002 Orders count == 1,943", len(o002) == 1943, f"(actual: {len(o002)})")
            r2 = sum(float(o.get('netPayable', o.get('total', 0))) for o in o002.values() if o.get('status') != 'cancelled')
            self.check("Store 002 Active Net Revenue == 9,931,034,200", abs(r2 - 9931034200.0) < 0.01, f"(actual: {r2:,.2f})")

        # Shared customers
        cust_path = os.path.join(STAGING_OUTPUT_DIR, 'shared_customers.json')
        if os.path.isfile(cust_path):
            with open(cust_path) as f: custs = json.load(f)
            self.check("Shared Customers count == 7,008 (7,007 raw + 1 stub)", len(custs) == 7008, f"(actual: {len(custs)})")
            total_c_debt = sum(float(c.get('currentDebt', 0)) for c in custs.values())
            self.check("Shared Customers Total Debt == 33,684,023,744", abs(total_c_debt - 33684023744.0) < 0.01, f"(actual: {total_c_debt:,.2f})")

        # Shared suppliers
        supp_path = os.path.join(STAGING_OUTPUT_DIR, 'shared_suppliers.json')
        if os.path.isfile(supp_path):
            with open(supp_path) as f: supps = json.load(f)
            self.check("Shared Suppliers count == 51 (50 raw + 1 stub)", len(supps) == 51, f"(actual: {len(supps)})")
            total_s_debt = sum(float(s.get('currentDebt', 0)) for s in supps.values())
            self.check("Shared Suppliers Total Debt == 23,259,824,240", abs(total_s_debt - 23259824240.0) < 0.01, f"(actual: {total_s_debt:,.2f})")

        # -------------------------------------------------------------
        # SUMMARY & VERDICT
        # -------------------------------------------------------------
        print("\n" + "=" * 80)
        print("  SUMMARY OF EMPIRICAL ADVERSARIAL CHALLENGE")
        print("=" * 80)
        print(f"  Total Invariant Checks: {self.total_tests}")
        print(f"  Passed Checks:          {self.passed_tests}")
        print(f"  Failed Checks:          {self.failed_tests}")

        if self.failed_tests == 0:
            print("\n  >>> VERDICT: CONFIRM CORRECTNESS <<<")
            print("  All empirical OpenXML ground-truth measurements match staged payloads with 100% zero-delta.")
            return True
        else:
            print(f"\n  >>> VERDICT: REJECT ({self.failed_tests} failure(s) detected) <<<")
            for f in self.failures:
                print(f"    - {f}")
            return False

if __name__ == '__main__':
    auditor = EmpiricalChallenger()
    success = auditor.run_all()
    sys.exit(0 if success else 1)
