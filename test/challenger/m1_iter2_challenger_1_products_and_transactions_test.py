#!/usr/bin/env python3
"""
m1_iter2_challenger_1_products_and_transactions_test.py

Empirical Challenger 1 Test Harness for M1 Iteration 2:
1. Product Catalog Verification: exactly 1,829 products in data_staging/output/products_all.json.
2. Legacy Discontinued Stubs Verification: TTTR6, XD6, NDL26.
   - Zero stock for both branches (store_001 == 0, store_002 == 0, stock == 0).
   - allowSale is False.
   - status is 'inactive'.
   - Schema evaluation for isActive.
3. Transaction Referential Integrity:
   - Exactly 199 transactions in store_001_tx.json.
   - Exactly 1,497 transactions in store_002_tx.json.
   - Exactly 1,696 total transactions.
   - Exactly 0 orphan SKUs across all 1,696 transactions.
4. Dual-Branch Stock Invariants:
   - Store 001 (Đông Thắng): exactly 395 units across 227 SKUs.
   - Store 002 (Thới Bình): exactly 118,037 units across 882 SKUs.
5. Cross-Collection Referential Integrity:
   - store_002_returns.json (2 returns, 2 items): 0 orphan SKUs.
   - store_001_orders.json (132 orders): 0 orphan SKUs.
   - store_002_orders.json (1,943 orders): 0 orphan SKUs.
6. Stress Testing & Edge Cases:
   - Negative stock SKU SP000685 is preserved (-1 in store_002, 0 in store_001).
   - All 227 in-stock SKUs at Đông Thắng have allowSale == True and can be sold at POS.
   - Transaction types breakdown and non-empty SKU check.
   - Mirror file parity between data_staging/output/ and data_staging/.
"""

import os
import sys
import json

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT_DIR = os.path.join(WORKSPACE_DIR, 'data_staging', 'output')
STAGING_DIR = os.path.join(WORKSPACE_DIR, 'data_staging')

class M1Iter2Challenger1Harness:
    def __init__(self):
        self.total_checks = 0
        self.passed_checks = 0
        self.failed_checks = 0
        self.failures = []

    def check(self, desc, condition, details=""):
        self.total_checks += 1
        if condition:
            self.passed_checks += 1
            print(f"  [PASS] {desc} {details}")
        else:
            self.failed_checks += 1
            msg = f"[FAIL] {desc} {details}"
            self.failures.append(msg)
            print(f"  {msg}")

    def run(self):
        print("=" * 80)
        print("M1 ITERATION 2 CHALLENGER 1: EMPIRICAL HARNESS")
        print("Auditing Products, Stubs, Stock Invariants & Transaction Referential Integrity")
        print("=" * 80)

        # ---------------------------------------------------------------------
        # 1. LOAD DATA PAYLOADS
        # ---------------------------------------------------------------------
        products_file = os.path.join(OUTPUT_DIR, 'products_all.json')
        tx1_file = os.path.join(OUTPUT_DIR, 'store_001_tx.json')
        tx2_file = os.path.join(OUTPUT_DIR, 'store_002_tx.json')
        returns_file = os.path.join(OUTPUT_DIR, 'store_002_returns.json')
        orders1_file = os.path.join(OUTPUT_DIR, 'store_001_orders.json')
        orders2_file = os.path.join(OUTPUT_DIR, 'store_002_orders.json')

        self.check("products_all.json exists", os.path.isfile(products_file))
        self.check("store_001_tx.json exists", os.path.isfile(tx1_file))
        self.check("store_002_tx.json exists", os.path.isfile(tx2_file))
        self.check("store_002_returns.json exists", os.path.isfile(returns_file))

        with open(products_file, 'r', encoding='utf-8') as f:
            products = json.load(f)
        with open(tx1_file, 'r', encoding='utf-8') as f:
            tx1 = json.load(f)
        with open(tx2_file, 'r', encoding='utf-8') as f:
            tx2 = json.load(f)
        with open(returns_file, 'r', encoding='utf-8') as f:
            returns = json.load(f)
        with open(orders1_file, 'r', encoding='utf-8') as f:
            orders1 = json.load(f)
        with open(orders2_file, 'r', encoding='utf-8') as f:
            orders2 = json.load(f)

        # ---------------------------------------------------------------------
        # 2. PRODUCT CATALOG COUNT VERIFICATION
        # ---------------------------------------------------------------------
        print("\n--- SECTION 1: Product Catalog Count Verification ---")
        self.check("Catalog contains exactly 1,829 products", len(products) == 1829, f"(actual: {len(products)})")

        # ---------------------------------------------------------------------
        # 3. STUBS AUDIT: TTTR6, XD6, NDL26
        # ---------------------------------------------------------------------
        print("\n--- SECTION 2: Stubs Audit (TTTR6, XD6, NDL26) ---")
        stubs = ['TTTR6', 'XD6', 'NDL26']
        for stub_id in stubs:
            self.check(f"Stub {stub_id} exists in products_all.json", stub_id in products)
            p = products.get(stub_id, {})
            bs = p.get('branchStocks', {})
            s1 = bs.get('store_001')
            s2 = bs.get('store_002')
            stock = p.get('stock')
            allow_sale = p.get('allowSale')
            status = p.get('status')
            is_active_raw = p.get('isActive')
            # Domain isActive resolution:
            is_active_resolved = allow_sale if allow_sale is not None else (is_active_raw if is_active_raw is not None else True)

            self.check(f"Stub {stub_id} store_001 stock == 0", s1 == 0, f"(actual: {s1})")
            self.check(f"Stub {stub_id} store_002 stock == 0", s2 == 0, f"(actual: {s2})")
            self.check(f"Stub {stub_id} master stock == 0", stock == 0, f"(actual: {stock})")
            self.check(f"Stub {stub_id} allowSale is False", allow_sale is False, f"(actual: {allow_sale})")
            self.check(f"Stub {stub_id} status is 'inactive'", status == 'inactive', f"(actual: '{status}')")
            self.check(f"Stub {stub_id} domain resolved isActive is False", is_active_resolved is False, f"(raw: {is_active_raw}, resolved: {is_active_resolved})")

        # Specific check: confirm XD6 and NDL26 have raw isActive: False
        self.check("XD6 has raw 'isActive' == False", products.get('XD6', {}).get('isActive') is False)
        self.check("NDL26 has raw 'isActive' == False", products.get('NDL26', {}).get('isActive') is False)
        # Note TTTR6 schema: TTTR6 uses allowSale=False and status='inactive'
        tttr6_has_is_active = 'isActive' in products.get('TTTR6', {})
        print(f"  [INFO] TTTR6 raw 'isActive' present: {tttr6_has_is_active} (allowSale={products.get('TTTR6', {}).get('allowSale')}, status='{products.get('TTTR6', {}).get('status')}')")

        # ---------------------------------------------------------------------
        # 4. TRANSACTIONS & REFERENTIAL INTEGRITY (0 ORPHAN SKUS)
        # ---------------------------------------------------------------------
        print("\n--- SECTION 3: Transaction Referential Integrity (0 Orphan SKUs) ---")
        self.check("Store 001 transactions count == 199", len(tx1) == 199, f"(actual: {len(tx1)})")
        self.check("Store 002 transactions count == 1,497", len(tx2) == 1497, f"(actual: {len(tx2)})")
        total_tx = len(tx1) + len(tx2)
        self.check("Combined transactions count == 1,696", total_tx == 1696, f"(actual: {total_tx})")

        catalog_skus = set(products.keys())

        # Audit tx1 for orphan SKUs and empty productIds
        orphans_tx1 = []
        empty_pid_tx1 = []
        for tx_id, item in tx1.items():
            pid = item.get('productId')
            if not pid or not str(pid).strip():
                empty_pid_tx1.append(tx_id)
            elif pid not in catalog_skus:
                orphans_tx1.append((tx_id, pid))

        self.check("Store 001 transactions: 0 empty or null productIds", len(empty_pid_tx1) == 0, f"(empty: {len(empty_pid_tx1)})")
        self.check("Store 001 transactions: 0 orphan SKUs across all 199 records", len(orphans_tx1) == 0, f"(orphans: {len(orphans_tx1)})")

        # Audit tx2 for orphan SKUs and empty productIds
        orphans_tx2 = []
        empty_pid_tx2 = []
        historical_audit_hits = {'XD6': 0, 'NDL26': 0}
        for tx_id, item in tx2.items():
            pid = item.get('productId')
            if not pid or not str(pid).strip():
                empty_pid_tx2.append(tx_id)
            elif pid not in catalog_skus:
                orphans_tx2.append((tx_id, pid))
            if pid in historical_audit_hits:
                historical_audit_hits[pid] += 1

        self.check("Store 002 transactions: 0 empty or null productIds", len(empty_pid_tx2) == 0, f"(empty: {len(empty_pid_tx2)})")
        self.check("Store 002 transactions: 0 orphan SKUs across all 1,497 records", len(orphans_tx2) == 0, f"(orphans: {len(orphans_tx2)})")
        self.check("Historical audit transaction references XD6 successfully resolved", historical_audit_hits['XD6'] >= 1, f"(occurrences: {historical_audit_hits['XD6']})")
        self.check("Historical audit transaction references NDL26 successfully resolved", historical_audit_hits['NDL26'] >= 1, f"(occurrences: {historical_audit_hits['NDL26']})")

        total_orphans = len(orphans_tx1) + len(orphans_tx2)
        self.check("Total orphan SKUs across all 1,696 transactions == 0", total_orphans == 0, f"(orphans: {total_orphans})")

        # ---------------------------------------------------------------------
        # 5. DUAL-BRANCH STOCK INVARIANTS
        # ---------------------------------------------------------------------
        print("\n--- SECTION 4: Dual-Branch Stock Invariants ---")
        s001_stock_sum = sum(p['branchStocks']['store_001'] for p in products.values())
        s001_active_skus = [sku for sku, p in products.items() if p['branchStocks']['store_001'] > 0]
        s002_stock_sum = sum(p['branchStocks']['store_002'] for p in products.values())
        s002_active_skus = [sku for sku, p in products.items() if p['branchStocks']['store_002'] > 0]

        self.check("Store 001 Stock Sum == 395 units", s001_stock_sum == 395, f"(actual: {s001_stock_sum})")
        self.check("Store 001 Active SKUs (stock > 0) == 227 SKUs", len(s001_active_skus) == 227, f"(actual: {len(s001_active_skus)})")
        self.check("Store 002 Stock Sum == 118,037 units", s002_stock_sum == 118037, f"(actual: {s002_stock_sum})")
        self.check("Store 002 Active SKUs (stock > 0) == 882 SKUs", len(s002_active_skus) == 882, f"(actual: {len(s002_active_skus)})")

        # ---------------------------------------------------------------------
        # 6. CROSS-COLLECTION REFERENTIAL INTEGRITY (RETURNS & ORDERS)
        # ---------------------------------------------------------------------
        print("\n--- SECTION 5: Cross-Collection Referential Integrity ---")
        # Returns
        orphan_returns = []
        for ret_id, ret in returns.items():
            for item in ret.get('items', []):
                pid = item.get('productId')
                if pid not in catalog_skus:
                    orphan_returns.append((ret_id, pid))
        self.check("Customer Returns count == 2 slips", len(returns) == 2, f"(actual: {len(returns)})")
        self.check("Customer Returns 0 orphan SKUs", len(orphan_returns) == 0, f"(orphans: {len(orphan_returns)})")

        # Orders 001 & 002
        orphan_orders1 = []
        for o_id, o in orders1.items():
            for item in o.get('items', []):
                pid = item.get('productId')
                if pid not in catalog_skus:
                    orphan_orders1.append((o_id, pid))
        self.check("Store 001 Orders count == 132 orders", len(orders1) == 132, f"(actual: {len(orders1)})")
        self.check("Store 001 Orders 0 orphan SKUs", len(orphan_orders1) == 0, f"(orphans: {len(orphan_orders1)})")

        orphan_orders2 = []
        for o_id, o in orders2.items():
            for item in o.get('items', []):
                pid = item.get('productId')
                if pid not in catalog_skus:
                    orphan_orders2.append((o_id, pid))
        self.check("Store 002 Orders count == 1,943 orders", len(orders2) == 1943, f"(actual: {len(orders2)})")
        self.check("Store 002 Orders 0 orphan SKUs", len(orphan_orders2) == 0, f"(orphans: {len(orphan_orders2)})")

        # ---------------------------------------------------------------------
        # 7. ADVERSARIAL STRESS TESTING
        # ---------------------------------------------------------------------
        print("\n--- SECTION 6: Adversarial Stress Testing ---")
        # Stress 1: POS Cart unblocking for all 227 Store 001 active products
        blocked_pos = []
        for sku in s001_active_skus:
            p = products[sku]
            if not p.get('allowSale', True) or p.get('status') != 'active':
                blocked_pos.append(sku)
        self.check("All 227 Store 001 in-stock products have allowSale==True and status=='active'", len(blocked_pos) == 0, f"(blocked: {len(blocked_pos)})")

        # Stress 2: Negative stock item SP000685
        sp685 = products.get('SP000685', {})
        self.check("Negative stock item SP000685 exists", 'SP000685' in products)
        self.check("SP000685 store_001 stock is 0", sp685.get('branchStocks', {}).get('store_001') == 0)
        self.check("SP000685 store_002 stock is -1 (unclamped)", sp685.get('branchStocks', {}).get('store_002') == -1)
        self.check("SP000685 allowSale is True", sp685.get('allowSale') is True)

        # Stress 3: Staged vs Root Mirror parity
        root_products_file = os.path.join(STAGING_DIR, 'products_all.json')
        if os.path.isfile(root_products_file):
            with open(root_products_file, 'r', encoding='utf-8') as f:
                root_products = json.load(f)
            self.check("data_staging/products_all.json exists and matches output/ 100%", root_products == products)

        # ---------------------------------------------------------------------
        # SUMMARY & VERDICT
        # ---------------------------------------------------------------------
        print("\n" + "=" * 80)
        print("SUMMARY OF EMPIRICAL CHECKS")
        print("=" * 80)
        print(f"Total Checks:  {self.total_checks}")
        print(f"Passed Checks: {self.passed_checks}")
        print(f"Failed Checks: {self.failed_checks}")

        if self.failed_checks == 0:
            print("\n>>> VERDICT: CONFIRM CORRECTNESS <<<")
            print("Catalog (1,829 products), stubs, and all 1,696 transactions referential integrity confirmed 100%.")
            return True
        else:
            print(f"\n>>> VERDICT: REJECT ({self.failed_checks} failures) <<<")
            for f in self.failures:
                print(f"  - {f}")
            return False

if __name__ == '__main__':
    harness = M1Iter2Challenger1Harness()
    success = harness.run()
    sys.exit(0 if success else 1)
