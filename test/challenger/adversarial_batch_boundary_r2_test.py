#!/usr/bin/env python3
"""
adversarial_batch_boundary_r2_test.py - Empirical Adversarial Test Harness for Gate Iteration 2
Author: Challenger 2 Round 2 (Boundary Testing & Hardening Re-Check)

Systematically tests CLI and functional boundaries for import_to_firebase.py:
1. Invalid batch sizes (0, -1, 5000) must exit with code 2, provide informative error messages, and produce ZERO tracebacks.
2. Valid batch sizes (200, 250, 300) must exit with code 0, complete dry-run validation with 0 writes.
3. Edge boundaries (1, 1000) must succeed with code 0.
4. Out-of-bounds edge (1001) and invalid types ('abc', '2.5') must exit with code 2 and ZERO tracebacks.
"""

import os
import sys
import subprocess
import json

WORKSPACE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT_PATH = os.path.join(WORKSPACE_DIR, 'data_staging', 'import_to_firebase.py')

def run_import_cli(args):
    cmd = [sys.executable, SCRIPT_PATH] + args
    result = subprocess.run(
        cmd,
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True
    )
    return result

def main():
    print("===================================================================")
    print("=== CHALLENGER 2 ROUND 2: BATCH BOUNDARY & HARDENING RE-CHECK ===")
    print("===================================================================\n")

    test_cases = [
        # (name, args, expected_code, stderr_substring, stdout_substring)
        (
            "CLI invalid batch-size=0",
            ["--mode=dry-run", "--batch-size=0"],
            2,
            "Invalid --batch-size: 0. Must be an integer >= 1",
            None
        ),
        (
            "CLI invalid batch-size=-1",
            ["--mode=dry-run", "--batch-size=-1"],
            2,
            "Invalid --batch-size: -1. Must be an integer >= 1",
            None
        ),
        (
            "CLI invalid batch-size=5000",
            ["--mode=dry-run", "--batch-size=5000"],
            2,
            "Invalid --batch-size: 5000. Batch size exceeds safe limit of 1000",
            None
        ),
        (
            "CLI valid batch-size=200",
            ["--mode=dry-run", "--batch-size=200"],
            0,
            None,
            "=== DRY-RUN VERIFICATION SUMMARY ==="
        ),
        (
            "CLI valid batch-size=250",
            ["--mode=dry-run", "--batch-size=250"],
            0,
            None,
            "=== DRY-RUN VERIFICATION SUMMARY ==="
        ),
        (
            "CLI valid batch-size=300",
            ["--mode=dry-run", "--batch-size=300"],
            0,
            None,
            "=== DRY-RUN VERIFICATION SUMMARY ==="
        ),
        (
            "CLI lower boundary batch-size=1",
            ["--mode=dry-run", "--batch-size=1", "--collection=suppliers"],
            0,
            None,
            "Total Batches Planned:49"
        ),
        (
            "CLI upper boundary batch-size=1000",
            ["--mode=dry-run", "--batch-size=1000", "--collection=suppliers"],
            0,
            None,
            "Total Batches Planned:1"
        ),
        (
            "CLI beyond upper boundary batch-size=1001",
            ["--mode=dry-run", "--batch-size=1001"],
            2,
            "Invalid --batch-size: 1001. Batch size exceeds safe limit of 1000",
            None
        ),
        (
            "CLI non-integer string batch-size=abc",
            ["--mode=dry-run", "--batch-size=abc"],
            2,
            "invalid int value: 'abc'",
            None
        ),
        (
            "CLI float string batch-size=2.5",
            ["--mode=dry-run", "--batch-size=2.5"],
            2,
            "invalid int value: '2.5'",
            None
        ),
    ]

    all_passed = True

    for name, args, expected_code, expected_stderr, expected_stdout in test_cases:
        res = run_import_cli(args)
        passed = True
        reasons = []

        # 1. Exit code check
        if res.returncode != expected_code:
            passed = False
            reasons.append(f"Exit code expected {expected_code}, got {res.returncode}")

        # 2. Traceback check (Adversarial check: zero tracebacks)
        combined_output = res.stdout + res.stderr
        if "Traceback (most recent call last):" in combined_output:
            passed = False
            reasons.append("Unhandled Python traceback detected in output!")

        # 3. Expected stderr substring
        if expected_stderr and expected_stderr not in res.stderr:
            passed = False
            reasons.append(f"Expected stderr substring '{expected_stderr}' not found in stderr: {res.stderr.strip()}")

        # 4. Expected stdout substring
        if expected_stdout and expected_stdout not in res.stdout:
            passed = False
            reasons.append(f"Expected stdout substring '{expected_stdout}' not found in stdout")

        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {name}")
        print(f"       Command: python3 data_staging/import_to_firebase.py {' '.join(args)}")
        print(f"       Exit code: {res.returncode} (expected {expected_code})")
        if not passed:
            all_passed = False
            for r in reasons:
                print(f"       FAILED: {r}")
            print(f"       STDERR: {res.stderr.strip()[:200]}")
        else:
            if expected_stderr:
                print(f"       Clean error message verified: \"{expected_stderr}\"")
            if expected_stdout:
                print(f"       Successful output verified: \"{expected_stdout}\"")
        print()

    # Programmatic function checks
    print("--- Checking Programmatic Invocations (run_dry_run) ---")
    sys.path.insert(0, os.path.join(WORKSPACE_DIR, 'data_staging'))
    import import_to_firebase
    checkpoint_file = os.path.join(WORKSPACE_DIR, 'data_staging', 'import_checkpoint.json')

    prog_checks = [
        ("run_dry_run(0)", 0, False),
        ("run_dry_run(-1)", -1, False),
        ("run_dry_run(5000)", 5000, False),
        ("run_dry_run(250, suppliers)", 250, True),
    ]

    for label, bsize, expected_bool in prog_checks:
        try:
            target = ["suppliers"] if expected_bool else None
            res = import_to_firebase.run_dry_run(
                batch_size=bsize,
                target_collections=target,
                checkpoint_path=checkpoint_file
            )
            if res == expected_bool:
                print(f"[PASS] Programmatic {label} returned {res} as expected.")
            else:
                all_passed = False
                print(f"[FAIL] Programmatic {label} returned {res} (expected {expected_bool}).")
        except Exception as e:
            all_passed = False
            print(f"[FAIL] Programmatic {label} raised unexpected exception: {e}")

    print("\n===================================================================")
    if all_passed:
        print("=== VERDICT: ALL BATCH BOUNDARY & HARDENING TESTS PASSED ===")
        print("===================================================================")
        sys.exit(0)
    else:
        print("=== VERDICT: HARDENING FAILURES DETECTED ===")
        print("===================================================================")
        sys.exit(1)

if __name__ == '__main__':
    main()
