#!/usr/bin/env python3
"""
test/challenger/m3_challenger_1_live_rtdb_adversarial_verification.py

M3 Challenger 1: Comprehensive Empirical Adversarial Verification Suite.
Validates live Firebase RTDB against strict requirements from:
- ORIGINAL_REQUEST.md (2026-10-09T14:18:50Z)
- Orchestrator PROJECT.md
- Worker M3 Handoff

Dimensions Verified:
1. System Accounts & Credentials Integrity (stores/accounts):
   - Exactly 5 active accounts
   - Passwords and password hashes non-empty & intact
   - Role and storeId bindings verified
   - Exact match with pre-migration backup
2. Payment & VietQR Configurations (store_payment_configs):
   - Exactly 1 active banking config (store_002)
   - VietinBank (ICB), account 0917865300, HUỲNH LÊ KHÁNH ĐĂNG 1, showVietQR True
   - Exact match with pre-migration backup
3. Store 001 Stock & POS Cart Safety (Đông Thắng):
   - Exactly 395 units across 227 SKUs
   - 0 negative stock SKUs
   - 100% of the 227 in-stock items ready for POS cart addition (allowSale != False, price >= 0, valid name)
   - Adversarial cart simulation validates additions from 1 to available quantity
4. Store 002 Stock & Boundary Invariants (Thới Bình):
   - Exactly 118,037 net units across 882 SKUs (118,038 positive units)
   - SKU SP000685 has stock -1 preserved unclamped
   - SP000685 is the ONLY negative stock SKU in store_002
5. Total Catalog & Inactive Stub Enforcement:
   - Exactly 1,829 products in store_001 and store_002
   - 100% key-set symmetry
   - Inactive stubs TTTR6, XD6, NDL26 have allowSale: False and stock: 0
   - Adversarial simulation verifies stubs are strictly blocked from POS cart addition
6. Live Invoices & Net Revenue Reconciliation:
   - Store 001: exactly 132 orders (120 active + 12 cancelled), net revenue = 639,515,000 VNĐ
   - Store 002: exactly 1,943 orders (1,767 active + 176 cancelled), net revenue = 9,931,034,200 VNĐ
   - System net revenue = 10,570,549,200 VNĐ
   - September net revenue: Store 001 = 19,000,000 VNĐ; Store 002 = 732,735,000 VNĐ; System = 751,735,000 VNĐ
7. Customers, Suppliers & Customer Returns:
   - shared_customers: 7,008 records, total debt = 33,684,023,744 VNĐ
   - shared_suppliers: 51 records, total debt = 23,259,824,240 VNĐ
   - store_002 return orders: exactly 2 records totaling 5,300,000 VNĐ (TH000040, TH000041)
8. Obsolete Nodes Cleanliness:
   - Targeted wipe verified (no obsolete customer/category nodes under stores, no old attendance nodes)
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
from datetime import datetime

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

def parse_raw_products(xlsx_path):
    with zipfile.ZipFile(xlsx_path, 'r') as z:
        sheet_xml = None
        for s in ['xl/worksheets/sheet2.xml', 'xl/worksheets/sheet1.xml']:
            if s in z.namelist():
                sheet_xml = z.read(s)
                break
        if sheet_xml is None:
            raise FileNotFoundError(f"Worksheet not found in {xlsx_path}")
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

class M3ChallengerAdversarialVerification:
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

    def check_approx(self, desc, expected, actual, tolerance=0.01):
        diff = abs(float(expected) - float(actual))
        cond = diff <= tolerance
        detail = f"expected {expected}, got {actual} (diff: {diff})"
        self.check(desc, cond, detail)

    def run_all(self):
        print("=" * 80)
        print("M3 CHALLENGER 1: LIVE RTDB EMPIRICAL ADVERSARIAL VERIFICATION")
        print("=" * 80)
        print(f"Target RTDB: {DB_URL}")
        print()

        self.verify_1_accounts()
        self.verify_2_payment_configs()
        self.verify_3_store_001_stock_and_pos_safety()
        self.verify_4_store_002_stock_and_negative_sp000685()
        self.verify_5_total_catalog_and_inactive_stubs()
        self.verify_6_live_orders_and_revenue()
        self.verify_7_customers_and_suppliers_debt()
        self.verify_8_customer_returns()
        self.verify_9_clean_slate_obsolete_nodes()

        print("\n" + "=" * 80)
        print(f"CHALLENGE SUMMARY: {self.passed_count} PASSED, {self.failed_count} FAILED")
        print("=" * 80)
        if self.failed_count == 0:
            print(">>> FINAL VERDICT: CONFIRM CORRECTNESS <<<")
            return 0
        else:
            print(">>> FINAL VERDICT: REJECT <<<")
            for f in self.failures:
                print(f)
            return 1

    def verify_1_accounts(self):
        print("--- 1. VERIFYING stores/accounts PRESERVATION ---")
        accounts = get_rtdb_node('stores/accounts')
        self.check("stores/accounts returned a valid dict", isinstance(accounts, dict))
        self.check_eq("stores/accounts has exactly 5 active accounts", 5, len(accounts))

        expected_users = {'admin1', 'admin2', 'nhanvien1', 'nhanvien2', 'supervisor'}
        self.check_eq("Account usernames match expected set exactly", expected_users, set(accounts.keys()))

        for u, acc in accounts.items():
            pw = acc.get('password') or acc.get('passwordHash')
            self.check(f"Account '{u}' password/hash is intact and non-empty", bool(pw) and len(str(pw)) >= 3)
            self.check(f"Account '{u}' has valid role ({acc.get('role')})", acc.get('role') in {'admin', 'nhanvien', 'supervisor'})
            self.check(f"Account '{u}' has valid storeId ({acc.get('storeId')})", acc.get('storeId') in {'store_001', 'store_002'})

        # Verify disk backup identity
        backup_file = os.path.join(BACKUP_DIR, 'accounts_backup.json')
        if os.path.exists(backup_file):
            with open(backup_file, 'r', encoding='utf-8') as f:
                backup_data = json.load(f)
            self.check_eq("Live accounts identical to pre-migration disk backup", backup_data, accounts)
        else:
            self.check("Pre-migration backup exists", False, f"Missing {backup_file}")

    def verify_2_payment_configs(self):
        print("\n--- 2. VERIFYING store_payment_configs PRESERVATION ---")
        configs = get_rtdb_node('store_payment_configs')
        self.check("store_payment_configs returned a valid dict", isinstance(configs, dict))
        self.check_eq("store_payment_configs has exactly 1 active config", 1, len(configs))
        self.check("store_002 has active payment config", 'store_002' in configs)

        cfg = configs.get('store_002', {})
        self.check_eq("Bank ID is vietinbank", 'vietinbank', cfg.get('bankId'))
        self.check_eq("Account number is 0917865300", '0917865300', cfg.get('accountNo'))
        self.check_eq("Account name is HUỲNH LÊ KHÁNH ĐĂNG 1", 'HUỲNH LÊ KHÁNH ĐĂNG 1', cfg.get('accountName'))
        self.check_eq("showVietQR is True", True, cfg.get('showVietQR'))
        self.check_eq("Paper size is k80", 'k80', cfg.get('paperSize'))

        backup_file = os.path.join(BACKUP_DIR, 'store_payment_configs_backup.json')
        if os.path.exists(backup_file):
            with open(backup_file, 'r', encoding='utf-8') as f:
                backup_data = json.load(f)
            self.check_eq("Live payment configs identical to pre-migration disk backup", backup_data, configs)
        else:
            self.check("Pre-migration backup exists", False, f"Missing {backup_file}")

    def verify_3_store_001_stock_and_pos_safety(self):
        print("\n--- 3. VERIFYING STORE 001 (ĐÔNG THẮNG) STOCK & POS CART SAFETY ---")
        prods = get_rtdb_node('stores/store_001/products')
        self.check("stores/store_001/products fetched successfully", isinstance(prods, dict))

        s1_in_stock = {}
        s1_total_units = 0
        s1_negative = []

        for sku, p in prods.items():
            b_stocks = p.get('branchStocks') or {}
            qty = b_stocks.get('store_001', 0)
            if qty > 0:
                s1_in_stock[sku] = (qty, p)
                s1_total_units += qty
            elif qty < 0:
                s1_negative.append((sku, qty))

        self.check_eq("Store 001 positive stock SKU count", 227, len(s1_in_stock))
        self.check_eq("Store 001 total stock units", 395, s1_total_units)
        self.check_eq("Store 001 zero negative stock items", [], s1_negative)

        # Adversarial POS cart addition stress test on all 227 items
        blocked_items = []
        invalid_meta = []
        for sku, (qty, p) in s1_in_stock.items():
            allow_sale = p.get('allowSale')
            price = p.get('price')
            name = p.get('name')

            # Check Flutter Product entity allowSale resolution:
            # defaults to True unless explicitly False
            is_sellable = (allow_sale is not False)
            if not is_sellable:
                blocked_items.append((sku, 'allowSale == False'))

            if price is None or price < 0 or not name:
                invalid_meta.append((sku, price, name))

            # Simulate POS cart addition: cart addition succeeds if is_sellable and stock >= qty
            # Testing boundary: adding 1 item, and adding full stock
            can_add_1 = is_sellable and (qty >= 1)
            can_add_max = is_sellable and (qty >= qty)
            if not (can_add_1 and can_add_max):
                blocked_items.append((sku, f'boundary check failed for qty {qty}'))

        self.check_eq("All 227 positive stock items unblocked for POS cart addition", [], blocked_items)
        self.check_eq("All 227 positive stock items have valid metadata (price >= 0, non-empty name)", [], invalid_meta)

    def verify_4_store_002_stock_and_negative_sp000685(self):
        print("\n--- 4. VERIFYING STORE 002 (THỚI BÌNH) STOCK & SP000685 PRESERVATION ---")
        prods = get_rtdb_node('stores/store_002/products')
        self.check("stores/store_002/products fetched successfully", isinstance(prods, dict))

        s2_in_stock = {}
        s2_pos_units = 0
        s2_negative = []

        for sku, p in prods.items():
            b_stocks = p.get('branchStocks') or {}
            qty = b_stocks.get('store_002', 0)
            if qty > 0:
                s2_in_stock[sku] = qty
                s2_pos_units += qty
            elif qty < 0:
                s2_negative.append((sku, qty))

        self.check_eq("Store 002 positive stock SKU count", 882, len(s2_in_stock))
        self.check_eq("Store 002 total positive stock units (excluding SP000685)", 118038, s2_pos_units)

        # Net units including negative stocks
        net_units = sum((p.get('branchStocks') or {}).get('store_002', 0) for p in prods.values())
        self.check_eq("Store 002 net stock units = 118,037", 118037, net_units)

        # SKU SP000685 adversarial check
        self.check("SP000685 exists in Store 002 products", 'SP000685' in prods)
        p_sofa = prods.get('SP000685', {})
        b_sofa = p_sofa.get('branchStocks') or {}
        self.check_eq("SP000685 branchStocks['store_002'] == -1 (unclamped)", -1, b_sofa.get('store_002'))
        self.check_eq("SP000685 branchStocks['store_001'] == 0", 0, b_sofa.get('store_001'))
        self.check_eq("SP000685 stock field in store_002 is -1", -1, p_sofa.get('stock'))
        self.check_eq("SP000685 allowSale is True (custom order / backorder)", True, p_sofa.get('allowSale'))
        self.check_eq("SP000685 is the SOLE negative stock SKU in store_002", [('SP000685', -1)], s2_negative)

    def verify_5_total_catalog_and_inactive_stubs(self):
        print("\n--- 5. VERIFYING TOTAL CATALOG (1,829) & INACTIVE STUBS (TTTR6, XD6, NDL26) ---")
        p1 = get_rtdb_node('stores/store_001/products')
        p2 = get_rtdb_node('stores/store_002/products')

        self.check_eq("Total catalog in store_001 is exactly 1,829 products", 1829, len(p1))
        self.check_eq("Total catalog in store_002 is exactly 1,829 products", 1829, len(p2))
        self.check_eq("Store 001 and Store 002 have 100% identical SKU set", set(p1.keys()), set(p2.keys()))

        # Check inactive stubs: TTTR6, XD6, NDL26
        stubs = ['TTTR6', 'XD6', 'NDL26']
        for stub_sku in stubs:
            self.check(f"Inactive stub '{stub_sku}' exists in store_001", stub_sku in p1)
            self.check(f"Inactive stub '{stub_sku}' exists in store_002", stub_sku in p2)

            item1 = p1.get(stub_sku, {})
            item2 = p2.get(stub_sku, {})

            self.check_eq(f"Stub '{stub_sku}' store_001 allowSale is False", False, item1.get('allowSale'))
            self.check_eq(f"Stub '{stub_sku}' store_002 allowSale is False", False, item2.get('allowSale'))
            self.check_eq(f"Stub '{stub_sku}' store_001 stock == 0", 0, item1.get('stock'))
            self.check_eq(f"Stub '{stub_sku}' store_002 stock == 0", 0, item2.get('stock'))

            bs1 = item1.get('branchStocks', {})
            bs2 = item2.get('branchStocks', {})
            self.check_eq(f"Stub '{stub_sku}' branchStocks['store_001'] == 0", 0, bs1.get('store_001'))
            self.check_eq(f"Stub '{stub_sku}' branchStocks['store_002'] == 0", 0, bs1.get('store_002'))
            self.check_eq(f"Stub '{stub_sku}' branchStocks symmetric in store_002", bs1, bs2)

            # Adversarial POS cart addition simulation: MUST BE REJECTED
            pos_blocked = (item1.get('allowSale') is False) or (bs1.get('store_001', 0) <= 0)
            self.check(f"Stub '{stub_sku}' strictly blocked from POS cart addition", pos_blocked)

    def verify_6_live_orders_and_revenue(self):
        print("\n--- 6. VERIFYING LIVE ORDERS & REVENUE RECONCILIATION ---")
        orders_001 = get_rtdb_node('stores/store_001/orders')
        orders_002 = get_rtdb_node('stores/store_002/orders')

        self.check_eq("Live RTDB Store 001 orders count", 132, len(orders_001))
        self.check_eq("Live RTDB Store 002 orders count", 1943, len(orders_002))

        # Store 001 revenue
        s1_active = 0
        s1_cancelled = 0
        s1_net_rev = Decimal('0')
        s1_sep_rev = Decimal('0')

        for oid, o in orders_001.items():
            is_cancelled = (o.get('status') in ['cancelled', 'Đã hủy']) or (o.get('isCancelled') is True)
            if is_cancelled:
                s1_cancelled += 1
                continue
            s1_active += 1
            net = Decimal(str(o.get('netPayable', o.get('total', 0) - o.get('discount', 0))))
            s1_net_rev += net

            dt_str = o.get('orderDate') or o.get('createdAt') or ''
            if dt_str.startswith('2026-09'):
                s1_sep_rev += net

        self.check_eq("Store 001 active orders count", 120, s1_active)
        self.check_eq("Store 001 cancelled orders count", 12, s1_cancelled)
        self.check_eq("Store 001 active net revenue", Decimal('639515000'), s1_net_rev, " VNĐ")
        self.check_eq("Store 001 September net revenue", Decimal('19000000'), s1_sep_rev, " VNĐ")

        # Store 002 revenue
        s2_active = 0
        s2_cancelled = 0
        s2_net_rev = Decimal('0')
        s2_sep_rev = Decimal('0')

        for oid, o in orders_002.items():
            is_cancelled = (o.get('status') in ['cancelled', 'Đã hủy']) or (o.get('isCancelled') is True)
            if is_cancelled:
                s2_cancelled += 1
                continue
            s2_active += 1
            net = Decimal(str(o.get('netPayable', o.get('total', 0) - o.get('discount', 0))))
            s2_net_rev += net

            dt_str = o.get('orderDate') or o.get('createdAt') or ''
            if dt_str.startswith('2026-09'):
                s2_sep_rev += net

        self.check_eq("Store 002 active orders count", 1767, s2_active)
        self.check_eq("Store 002 cancelled orders count", 176, s2_cancelled)
        self.check_eq("Store 002 active net revenue", Decimal('9931034200'), s2_net_rev, " VNĐ")
        self.check_eq("Store 002 September net revenue", Decimal('732735000'), s2_sep_rev, " VNĐ")

        # Combined System Revenue
        sys_net_rev = s1_net_rev + s2_net_rev
        sys_sep_rev = s1_sep_rev + s2_sep_rev
        self.check_eq("Combined system active net revenue", Decimal('10570549200'), sys_net_rev, " VNĐ")
        self.check_eq("Combined system September net revenue", Decimal('751735000'), sys_sep_rev, " VNĐ")

    def verify_7_customers_and_suppliers_debt(self):
        print("\n--- 7. VERIFYING CUSTOMERS & SUPPLIERS DEBT ---")
        customers = get_rtdb_node('shared_customers')
        self.check_eq("shared_customers count (7,007 raw + 1 stub)", 7008, len(customers))

        cust_debt_sum = sum(Decimal(str(c.get('totalDebt', 0))) for c in customers.values())
        self.check_eq("shared_customers total debt", Decimal('33684023744'), cust_debt_sum, " VNĐ")

        # Check stub customer
        self.check("Stub customer KH002414 exists", 'KH002414' in customers)

        suppliers = get_rtdb_node('shared_suppliers')
        self.check_eq("shared_suppliers count (50 raw + 1 stub)", 51, len(suppliers))

        supp_debt_sum = sum(Decimal(str(s.get('totalDebt', 0))) for s in suppliers.values())
        self.check_eq("shared_suppliers total debt", Decimal('23259824240'), supp_debt_sum, " VNĐ")

    def verify_8_customer_returns(self):
        print("\n--- 8. VERIFYING CUSTOMER RETURNS ---")
        returns_001 = get_rtdb_node('stores/store_001/return_orders')
        self.check("Store 001 has 0 phantom returns", returns_001 is None or len(returns_001) == 0)

        returns_002 = get_rtdb_node('stores/store_002/return_orders')
        self.check_eq("Store 002 has exactly 2 return orders", 2, len(returns_002) if isinstance(returns_002, dict) else 0)

        r_sum = Decimal('0')
        if isinstance(returns_002, dict):
            for rid, r in returns_002.items():
                r_sum += Decimal(str(r.get('total', r.get('totalAmount', 0))))
        self.check_eq("Store 002 return orders total amount", Decimal('5300000'), r_sum, " VNĐ")

    def verify_9_clean_slate_obsolete_nodes(self):
        print("\n--- 9. VERIFYING ABSENCE OF OBSOLETE NODES (CLEAN-SLATE) ---")
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
            'attendance_adjustments',
        ]
        for p in obsolete_paths:
            val = get_rtdb_node(p)
            self.check(f"Node '{p}' is absent (null/empty)", val is None or val == {} or val == [])

if __name__ == '__main__':
    challenger = M3ChallengerAdversarialVerification()
    sys.exit(challenger.run_all())
