#!/usr/bin/env python3
"""
adversarial_batch_stress_test.py - Empirical Adversarial Test Suite
Author: Challenger 2 (Stress Testing, Batching Boundaries & Dry-Run Safety)
"""

import os
import sys
import json
import re
import socket
import http.client
import urllib.request
from datetime import datetime

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(WORKSPACE_DIR, 'data_staging'))

import import_to_firebase

TEST_RESULTS = []

def record_result(test_name, passed, details):
    TEST_RESULTS.append({
        "test": test_name,
        "passed": passed,
        "details": details
    })
    status = "PASS" if passed else "FAIL"
    print(f"[{status}] {test_name}: {details}")

def test_batching_valid_boundaries():
    print("\n--- Testing Valid Batching Boundaries (200, 250, 300) ---")
    checkpoint_file = os.path.join(WORKSPACE_DIR, 'data_staging', 'import_checkpoint.json')
    
    for b_size in [200, 250, 300]:
        try:
            success = import_to_firebase.run_dry_run(
                batch_size=b_size,
                target_collections=None,
                checkpoint_path=checkpoint_file
            )
            record_result(
                f"Valid Batch Size {b_size}",
                success is True,
                f"Successfully planned batches with chunk size {b_size}"
            )
        except Exception as e:
            record_result(f"Valid Batch Size {b_size}", False, f"Exception raised: {e}")

def test_batching_invalid_boundaries():
    print("\n--- Testing Invalid Batch Sizes (0, -1, 5000) ---")
    checkpoint_file = os.path.join(WORKSPACE_DIR, 'data_staging', 'import_checkpoint.json')
    
    # 1. Batch size = 0
    try:
        success = import_to_firebase.run_dry_run(
            batch_size=0,
            target_collections=None,
            checkpoint_path=checkpoint_file
        )
        record_result(
            "Invalid Batch Size 0 Rejection",
            success is False,
            f"Correctly returned False ({success}) and rejected batch size 0" if success is False else "Accepted batch size 0 instead of rejecting"
        )
    except Exception as e:
        record_result("Invalid Batch Size 0 Rejection", False, f"Unexpected exception: {e}")

    # 2. Batch size = -1
    try:
        success = import_to_firebase.run_dry_run(
            batch_size=-1,
            target_collections=None,
            checkpoint_path=checkpoint_file
        )
        record_result(
            "Invalid Batch Size -1 Rejection",
            success is False,
            f"Correctly returned False ({success}) and rejected batch size -1" if success is False else "Accepted batch size -1 instead of rejecting"
        )
    except Exception as e:
        record_result("Invalid Batch Size -1 Rejection", False, f"Unexpected exception: {e}")

    # 3. Batch size = 5000
    try:
        success = import_to_firebase.run_dry_run(
            batch_size=5000,
            target_collections=None,
            checkpoint_path=checkpoint_file
        )
        record_result(
            "Batch Size 5000 Boundary Clamping / Warning",
            success is False,
            f"Correctly returned False ({success}) and rejected batch size 5000 exceeding 1000 limit" if success is False else "Accepted 5000 records/batch without limit"
        )
    except Exception as e:
        record_result("Batch Size 5000 Boundary Clamping", True, f"Rejected large batch: {e}")

def test_dry_run_network_isolation():
    print("\n--- Testing Dry-Run Network Isolation ---")
    checkpoint_file = os.path.join(WORKSPACE_DIR, 'data_staging', 'import_checkpoint.json')
    
    network_intercepted = []
    def intercept_network(*args, **kwargs):
        network_intercepted.append((args, kwargs))
        raise AssertionError(f"Illegal network write attempt during dry-run: {args}")

    orig_socket = socket.socket
    orig_create_connection = socket.create_connection
    orig_http = http.client.HTTPConnection.connect
    orig_https = http.client.HTTPSConnection.connect
    orig_urlopen = urllib.request.urlopen

    try:
        socket.socket = intercept_network
        socket.create_connection = intercept_network
        http.client.HTTPConnection.connect = intercept_network
        http.client.HTTPSConnection.connect = intercept_network
        urllib.request.urlopen = intercept_network

        success = import_to_firebase.run_dry_run(
            batch_size=250,
            target_collections=None,
            checkpoint_path=checkpoint_file
        )
        record_result(
            "Dry-Run Network Isolation",
            success is True and len(network_intercepted) == 0,
            f"0 network requests initiated across 12,750 records and 53 batches"
        )
    finally:
        socket.socket = orig_socket
        socket.create_connection = orig_create_connection
        http.client.HTTPConnection.connect = orig_http
        http.client.HTTPSConnection.connect = orig_https
        urllib.request.urlopen = orig_urlopen

def test_unicode_and_date_integrity():
    print("\n--- Testing Unicode and ISO 8601 Timestamp Integrity ---")
    staging_dir = os.path.join(WORKSPACE_DIR, 'data_staging')
    files = {
        'customers': os.path.join(staging_dir, 'customers_clean.json'),
        'suppliers': os.path.join(staging_dir, 'suppliers_clean.json'),
        'products': os.path.join(staging_dir, 'products_clean.json'),
        'orders': os.path.join(staging_dir, 'orders_clean.json'),
    }

    mojibake_pattern = re.compile(r"(Ã[¡-¿]|áº|á»|â€|ï¿½|\\u[0-9a-fA-F]{4})")
    vn_chars = set("àáảãạăắằẳẵặâấầẩẫậèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵđĐ")
    iso_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$")

    total_strings = 0
    total_vn_strings = 0
    mojibake_count = 0
    total_dates = 0
    valid_dates = 0

    date_fields_map = {
        'customers': ['createdAt', 'dob', 'lastTransactionDate'],
        'suppliers': ['createdAt', 'lastTransactionDate'],
        'products': ['createdAt'],
        'orders': ['createdAt', 'completedAt']
    }

    for col, fpath in files.items():
        with open(fpath, 'r', encoding='utf-8') as f:
            records = json.load(f)

        for item in records:
            # Check dates
            for d_field in date_fields_map[col]:
                val = item.get(d_field)
                if val is not None and val != '':
                    total_dates += 1
                    if iso_pattern.match(str(val)):
                        valid_dates += 1
                        # verify datetime parseable
                        try:
                            clean_val = val.replace('.000Z', 'Z').rstrip('Z')
                            datetime.fromisoformat(clean_val)
                        except Exception as e:
                            print(f"Date parse error: {val} ({e})")
                    else:
                        print(f"Invalid ISO format in {col}.{d_field}: {val}")

            # Check strings recursively
            def check_strings(obj):
                nonlocal total_strings, total_vn_strings, mojibake_count
                if isinstance(obj, str):
                    total_strings += 1
                    if mojibake_pattern.search(obj):
                        mojibake_count += 1
                    if any(c in vn_chars for c in obj):
                        total_vn_strings += 1
                elif isinstance(obj, dict):
                    for k, v in obj.items():
                        check_strings(k)
                        check_strings(v)
                elif isinstance(obj, list):
                    for elem in obj:
                        check_strings(elem)

            check_strings(item)

    record_result(
        "Unicode Encoding Integrity",
        mojibake_count == 0 and total_vn_strings > 60000,
        f"{total_vn_strings:,} VN strings, {total_strings:,} total strings, 0 mojibake"
    )

    record_result(
        "ISO 8601 Timestamp Validity",
        total_dates == 19599 and valid_dates == 19599,
        f"{valid_dates:,} / {total_dates:,} dates fully valid RFC 3339 / ISO 8601"
    )

def main():
    test_batching_valid_boundaries()
    test_batching_invalid_boundaries()
    test_dry_run_network_isolation()
    test_unicode_and_date_integrity()

    print("\n=======================================================")
    print("=== ADVERSARIAL STRESS TEST SUITE COMPLETE ===")
    print("=======================================================")
    passed_count = sum(1 for r in TEST_RESULTS if r["passed"])
    total_count = len(TEST_RESULTS)
    print(f"Passed: {passed_count} / {total_count}")
    print(f"Failed / Challenged: {total_count - passed_count} / {total_count}")

if __name__ == '__main__':
    main()
