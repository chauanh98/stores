#!/usr/bin/env python3
"""
test/challenger/m2_challenger_1_live_rtdb_parity_test.py

M2 Challenger 1 Empirical Verification Harness:
Live Firebase RTDB Parity & Safety Stress Test for Milestone 2.

Adversarially tests and independently verifies:
1. System Accounts & Credentials Integrity (stores/accounts)
2. Payment & VietQR Configurations Integrity (store_payment_configs)
3. Store 001 Stock Invariants: exactly 395 units across 227 SKUs (Đông Thắng)
4. Store 002 Stock Invariants: exactly 118,037 units across 882 SKUs (Thới Bình)
5. Negative Stock Boundary Item SP000685: stock = -1 preserved unclamped
6. POS Cart Safety Audit for Store 001 (Đông Thắng):
   - 100% of the 227 in-stock items ready for cart addition
   - Valid pricing, allowSale != False, non-zero stock
   - Inactive stubs (TTTR6, XD6, NDL26) safely blocked
7. Catalog Symmetry & branchStocks Schema Integrity:
   - 1,829 products in store_001 and store_002
   - 100% key-set identity
   - branchStocks['store_001'] and branchStocks['store_002'] on all records
8. Ground-Truth OpenXML Re-verification against raw files in DATA_IMPORT/
"""

import os
import sys
import json
import ssl
import re
import zipfile
import xml.etree.ElementTree as ET
import urllib.request
from decimal import Decimal

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_IMPORT_DIR = os.path.join(WORKSPACE_DIR, 'DATA_IMPORT')
BACKUP_DIR = os.path.join(WORKSPACE_DIR, 'data_staging', 'backup')
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

def parse_raw_products(xlsx_path):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sheet_xml = None
        for s in ['xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml']:
            if s in z.namelist():
                sheet_xml = z.read(s)
                break
        if sheet_xml is None:
            raise FileNotFoundError(f"No valid sheet XML found in {xlsx_path}")
        root = ET.fromstring(sheet_xml)
        skus = {}
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
            sku = (row.get(2) or '').strip()
            stock_str = (row.get(9) or '').strip()
            if not sku or sku == 'Mã hàng':
                continue
            try:
                skus[sku] = float(stock_str)
            except ValueError:
                pass
        return skus

def get_rtdb_node(path):
    if '?' in path:
        base, query = path.split('?', 1)
        url = f"{DB_URL}/{base.strip('/')}.json?{query}"
    else:
        url = f"{DB_URL}/{path.strip('/')}.json"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=60) as resp:
        content = resp.read().decode('utf-8')
        return json.loads(content)

class M2ChallengerLiveRTDBParityTest:
    def __init__(self):
        self.passed_count = 0
        self.failed_count = 0
        self.failures = []

    def check(self, desc, condition, detail=""):
        if condition:
            self.passed_count += 1
            print(f"  [PASS] {desc}")
        else:
            self.failed_count += 1
            err = f"  [FAIL] {desc} - {detail}"
            print(err)
            self.failures.append(err)

    def check_eq(self, desc, expected, actual, unit=""):
        cond = (expected == actual)
        detail = f"expected {expected}{unit}, got {actual}{unit}"
        self.check(desc, cond, detail)

    def run_all(self):
        print("=" * 80)
        print("M2 CHALLENGER 1: LIVE RTDB EMPIRICAL PARITY & SAFETY SUITE")
        print("=" * 80)
        print(f"Live RTDB Target: {DB_URL}")
        print()

        self.test_1_system_accounts_integrity()
        self.test_2_payment_configs_integrity()
        self.test_3_store_001_stock_and_skus()
        self.test_4_store_002_stock_and_skus()
        self.test_5_negative_stock_sp000685_preservation()
        self.test_6_pos_cart_safety_store_001()
        self.test_7_catalog_symmetry_and_branch_stocks()
        self.test_8_ground_truth_reconciliation()

        print("\n" + "=" * 80)
        print(f"TEST RUN COMPLETED: {self.passed_count} PASSED, {self.failed_count} FAILED")
        print("=" * 80)
        if self.failed_count == 0:
            print(">>> FINAL VERDICT: CONFIRM CORRECTNESS <<<")
            return 0
        else:
            print(">>> FINAL VERDICT: REJECT <<<")
            for f in self.failures:
                print(f)
            return 1

    def test_1_system_accounts_integrity(self):
        print("--- PHASE 1: SYSTEM ACCOUNTS & CREDENTIALS INTEGRITY ---")
        accounts = get_rtdb_node('stores/accounts')
        self.check("stores/accounts is a non-empty dictionary", isinstance(accounts, dict) and len(accounts) > 0)
        self.check_eq("Total accounts count", 5, len(accounts))

        expected_accounts = {'admin1', 'admin2', 'nhanvien1', 'nhanvien2', 'supervisor'}
        self.check_eq("Account usernames match expected set", expected_accounts, set(accounts.keys()))

        # Check roles and passwords
        valid_roles = {'admin', 'nhanvien', 'supervisor'}
        for username, acc in accounts.items():
            self.check(f"Account '{username}' has valid role ({acc.get('role')})", acc.get('role') in valid_roles)
            has_pw = bool(acc.get('password') or acc.get('passwordHash'))
            self.check(f"Account '{username}' has credentials present", has_pw)
            self.check(f"Account '{username}' has valid storeId ({acc.get('storeId')})", acc.get('storeId') in {'store_001', 'store_002'})

        # Compare with backup
        backup_path = os.path.join(BACKUP_DIR, 'accounts_backup.json')
        if os.path.exists(backup_path):
            with open(backup_path, 'r', encoding='utf-8') as f:
                backup_data = json.load(f)
            self.check_eq("Live accounts identical to pre-migration backup", backup_data, accounts)
        else:
            self.check("Pre-migration accounts backup exists", False, f"Missing {backup_path}")

    def test_2_payment_configs_integrity(self):
        print("\n--- PHASE 2: STORE PAYMENT CONFIGS & VIETQR INTEGRITY ---")
        configs = get_rtdb_node('store_payment_configs')
        self.check("store_payment_configs is a non-empty dictionary", isinstance(configs, dict) and len(configs) > 0)
        self.check("store_002 exists in store_payment_configs", 'store_002' in configs)

        s2_cfg = configs.get('store_002', {})
        self.check_eq("Payment config bankId", 'vietinbank', s2_cfg.get('bankId'))
        self.check_eq("Payment config accountNo", '0917865300', s2_cfg.get('accountNo'))
        self.check_eq("Payment config showVietQR is True", True, s2_cfg.get('showVietQR'))
        self.check_eq("Payment config paperSize", 'k80', s2_cfg.get('paperSize'))
        self.check("Payment config accountName is non-empty", bool(s2_cfg.get('accountName')))
        self.check("Payment config storeName is non-empty", bool(s2_cfg.get('storeName')))

        # Compare with backup
        backup_path = os.path.join(BACKUP_DIR, 'store_payment_configs_backup.json')
        if os.path.exists(backup_path):
            with open(backup_path, 'r', encoding='utf-8') as f:
                backup_data = json.load(f)
            self.check_eq("Live payment configs identical to pre-migration backup", backup_data, configs)
        else:
            self.check("Pre-migration payment configs backup exists", False, f"Missing {backup_path}")

    def test_3_store_001_stock_and_skus(self):
        print("\n--- PHASE 3: STORE 001 STOCK & SKU INVARIANTS (ĐÔNG THẮNG) ---")
        prods_001 = get_rtdb_node('stores/store_001/products')
        self.check("stores/store_001/products fetched successfully", isinstance(prods_001, dict) and len(prods_001) > 0)
        self.check_eq("Store 001 total product records", 1829, len(prods_001))

        # Filter active positive stock items
        s001_pos = {}
        s001_stock_sum = 0
        for sku, p in prods_001.items():
            b_stocks = p.get('branchStocks') or {}
            qty = b_stocks.get('store_001', 0)
            if qty > 0:
                s001_pos[sku] = qty
                s001_stock_sum += qty

        self.check_eq("Store 001 SKUs with stock > 0", 227, len(s001_pos), " SKUs")
        self.check_eq("Store 001 Total Stock Units", 395, s001_stock_sum, " units")

        # Verify no items in store_001 have negative stock in branchStocks['store_001']
        negative_in_001 = [sku for sku, p in prods_001.items() if (p.get('branchStocks') or {}).get('store_001', 0) < 0]
        self.check_eq("Store 001 zero negative stock items", [], negative_in_001)

    def test_4_store_002_stock_and_skus(self):
        print("\n--- PHASE 4: STORE 002 STOCK & SKU INVARIANTS (THỚI BÌNH) ---")
        prods_002 = get_rtdb_node('stores/store_002/products')
        self.check("stores/store_002/products fetched successfully", isinstance(prods_002, dict) and len(prods_002) > 0)
        self.check_eq("Store 002 total product records", 1829, len(prods_002))

        # Filter active positive stock items
        s002_pos = {}
        s002_pos_sum = 0
        for sku, p in prods_002.items():
            b_stocks = p.get('branchStocks') or {}
            qty = b_stocks.get('store_002', 0)
            if qty > 0:
                s002_pos[sku] = qty
                s002_pos_sum += qty

        self.check_eq("Store 002 SKUs with stock > 0", 882, len(s002_pos), " SKUs")
        self.check_eq("Store 002 Total Positive Stock Units (excl negative SP000685)", 118038, s002_pos_sum, " units")

        # Total net stock sum across all items (including SP000685 = -1)
        s002_net_sum = sum((p.get('branchStocks') or {}).get('store_002', 0) for p in prods_002.values())
        self.check_eq("Store 002 Net Total Stock Units (including -1 for SP000685)", 118037, s002_net_sum, " units")

    def test_5_negative_stock_sp000685_preservation(self):
        print("\n--- PHASE 5: NEGATIVE STOCK BOUNDARY ITEM SP000685 PRESERVATION ---")
        prods_001 = get_rtdb_node('stores/store_001/products')
        prods_002 = get_rtdb_node('stores/store_002/products')

        # Check in Store 001
        self.check("SP000685 exists in store_001 catalog", 'SP000685' in prods_001)
        p1 = prods_001.get('SP000685', {})
        p1_stocks = p1.get('branchStocks') or {}
        self.check_eq("SP000685 store_001 branchStocks['store_001'] == 0", 0, p1_stocks.get('store_001'))
        self.check_eq("SP000685 store_001 branchStocks['store_002'] == -1 (unclamped)", -1, p1_stocks.get('store_002'))
        self.check_eq("SP000685 store_001 allowSale is True", True, p1.get('allowSale'))
        self.check_eq("SP000685 store_001 status is active", 'active', p1.get('status'))

        # Check in Store 002
        self.check("SP000685 exists in store_002 catalog", 'SP000685' in prods_002)
        p2 = prods_002.get('SP000685', {})
        p2_stocks = p2.get('branchStocks') or {}
        self.check_eq("SP000685 store_002 branchStocks['store_001'] == 0", 0, p2_stocks.get('store_001'))
        self.check_eq("SP000685 store_002 branchStocks['store_002'] == -1 (unclamped)", -1, p2_stocks.get('store_002'))
        self.check_eq("SP000685 store_002 allowSale is True", True, p2.get('allowSale'))
        self.check_eq("SP000685 store_002 status is active", 'active', p2.get('status'))
        self.check_eq("SP000685 store_002 stock field is -1", -1, p2.get('stock'))

        # Adversarial check: Are there ANY other negative stock SKUs in store_002?
        all_s002_neg = [sku for sku, p in prods_002.items() if (p.get('branchStocks') or {}).get('store_002', 0) < 0]
        self.check_eq("SP000685 is the ONLY negative stock SKU in store_002", ['SP000685'], all_s002_neg)

    def test_6_pos_cart_safety_store_001(self):
        print("\n--- PHASE 6: POS CART SAFETY AUDIT FOR STORE 001 (ĐÔNG THẮNG) ---")
        prods_001 = get_rtdb_node('stores/store_001/products')

        s001_in_stock = {sku: p for sku, p in prods_001.items() if (p.get('branchStocks') or {}).get('store_001', 0) > 0}
        self.check_eq("Target set for POS safety audit is 227 SKUs", 227, len(s001_in_stock))

        disallowed_sales = []
        invalid_prices = []
        missing_names = []
        stock_mismatches = []
        cart_simulation_failures = []

        for sku, p in s001_in_stock.items():
            stock_qty = p.get('branchStocks', {}).get('store_001')
            allow_sale = p.get('allowSale')
            price = p.get('price')
            name = p.get('name')

            # Flutter ProductModel.fromMap simulation:
            # allowSale resolves to true if allowSale is not False
            resolved_allow_sale = allow_sale if allow_sale is not None else (p.get('isActive') if p.get('isActive') is not None else True)

            if resolved_allow_sale is not True:
                disallowed_sales.append(sku)

            if price is None or price < 0:
                invalid_prices.append(sku)

            if not name or not isinstance(name, str):
                missing_names.append(sku)

            if not isinstance(stock_qty, (int, float)) or stock_qty <= 0:
                stock_mismatches.append(sku)

            # POS Cart logic simulation:
            # addToCart(Product product, {quantity: 1})
            # requires: product.allowSale == True and quantity <= stock_qty
            can_add_to_cart = (resolved_allow_sale is True) and (1 <= stock_qty)
            if not can_add_to_cart:
                cart_simulation_failures.append(sku)

        self.check_eq("0 disallowed sale items among in-stock Đông Thắng items", [], disallowed_sales)
        self.check_eq("0 invalid prices among in-stock Đông Thắng items", [], invalid_prices)
        self.check_eq("0 missing product names among in-stock Đông Thắng items", [], missing_names)
        self.check_eq("0 stock quantity mismatches among in-stock Đông Thắng items", [], stock_mismatches)
        self.check_eq("100% of 227 in-stock items succeed in POS cart simulation", 0, len(cart_simulation_failures))

        # Check legacy inactive stubs: TTTR6, XD6, NDL26
        # These are historical stubs for referential integrity and MUST NOT be sellable
        stubs = ['TTTR6', 'XD6', 'NDL26']
        for stub_sku in stubs:
            stub_p = prods_001.get(stub_sku)
            self.check(f"Legacy stub '{stub_sku}' exists in catalog", stub_p is not None)
            if stub_p:
                stub_s1 = stub_p.get('branchStocks', {}).get('store_001', 0)
                stub_s2 = stub_p.get('branchStocks', {}).get('store_002', 0)
                stub_allow = stub_p.get('allowSale', False)
                self.check(f"Legacy stub '{stub_sku}' has stock 0 in store_001", stub_s1 == 0)
                self.check(f"Legacy stub '{stub_sku}' has stock 0 in store_002", stub_s2 == 0)
                self.check(f"Legacy stub '{stub_sku}' allowSale is False (blocked from POS)", stub_allow is False)

    def test_7_catalog_symmetry_and_branch_stocks(self):
        print("\n--- PHASE 7: CATALOG SYMMETRY & branchStocks SCHEMA INTEGRITY ---")
        prods_001 = get_rtdb_node('stores/store_001/products')
        prods_002 = get_rtdb_node('stores/store_002/products')

        self.check_eq("Store 001 catalog size", 1829, len(prods_001))
        self.check_eq("Store 002 catalog size", 1829, len(prods_002))

        s1_keys = set(prods_001.keys())
        s2_keys = set(prods_002.keys())
        self.check_eq("Store 001 and Store 002 have 100% identical SKU keys", s1_keys, s2_keys)

        # Check branchStocks schema consistency across all 1829 items in both stores
        malformed_schema_001 = []
        malformed_schema_002 = []

        for sku in s1_keys:
            p1 = prods_001[sku]
            bs1 = p1.get('branchStocks')
            if not isinstance(bs1, dict) or 'store_001' not in bs1 or 'store_002' not in bs1:
                malformed_schema_001.append(sku)

            p2 = prods_002[sku]
            bs2 = p2.get('branchStocks')
            if not isinstance(bs2, dict) or 'store_001' not in bs2 or 'store_002' not in bs2:
                malformed_schema_002.append(sku)

        self.check_eq("All 1,829 items in store_001 have valid branchStocks schema", [], malformed_schema_001)
        self.check_eq("All 1,829 items in store_002 have valid branchStocks schema", [], malformed_schema_002)

    def test_8_ground_truth_reconciliation(self):
        print("\n--- PHASE 8: GROUND-TRUTH OPENXML RECONCILIATION ---")
        f_dt = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV09102026-210142-227.xlsx')
        f_tb = os.path.join(DATA_IMPORT_DIR, 'DanhSachSanPham_KV09102026-210851-400.xlsx')

        self.check("Raw Excel Đông Thắng exists", os.path.exists(f_dt))
        self.check("Raw Excel Thới Bình exists", os.path.exists(f_tb))

        # Parse raw Đông Thắng
        raw_dt = parse_raw_products(f_dt)
        raw_dt_pos = {k: v for k, v in raw_dt.items() if v > 0}
        raw_dt_sum = sum(raw_dt_pos.values())
        self.check_eq("Raw Excel Đông Thắng SKUs with stock > 0", 227, len(raw_dt_pos))
        self.check_eq("Raw Excel Đông Thắng Total Stock Units", 395.0, raw_dt_sum)

        # Parse raw Thới Bình
        raw_tb = parse_raw_products(f_tb)
        raw_tb_pos = {k: v for k, v in raw_tb.items() if v > 0}
        raw_tb_pos_sum = sum(raw_tb_pos.values())
        raw_tb_net_sum = sum(raw_tb.values())
        self.check_eq("Raw Excel Thới Bình SKUs with stock > 0", 882, len(raw_tb_pos))
        self.check_eq("Raw Excel Thới Bình Total Positive Stock Units", 118038.0, raw_tb_pos_sum)
        self.check_eq("Raw Excel Thới Bình Total Net Stock Units (including -1 for SP000685)", 118037.0, raw_tb_net_sum)
        self.check_eq("Raw Excel Thới Bình SP000685 stock is -1", -1.0, raw_tb.get('SP000685'))

        # Fetch Live RTDB and do SKU-by-SKU delta comparison
        prods_001 = get_rtdb_node('stores/store_001/products')
        prods_002 = get_rtdb_node('stores/store_002/products')

        sku_deltas_001 = []
        for sku, raw_qty in raw_dt.items():
            live_qty = (prods_001.get(sku, {}).get('branchStocks') or {}).get('store_001', 0)
            if round(raw_qty) != live_qty:
                sku_deltas_001.append((sku, raw_qty, live_qty))

        sku_deltas_002 = []
        for sku, raw_qty in raw_tb.items():
            live_qty = (prods_002.get(sku, {}).get('branchStocks') or {}).get('store_002', 0)
            if round(raw_qty) != live_qty:
                sku_deltas_002.append((sku, raw_qty, live_qty))

        self.check_eq("Zero delta across all Đông Thắng SKUs against raw Excel", [], sku_deltas_001)
        self.check_eq("Zero delta across all Thới Bình SKUs against raw Excel", [], sku_deltas_002)

if __name__ == '__main__':
    tester = M2ChallengerLiveRTDBParityTest()
    sys.exit(tester.run_all())
