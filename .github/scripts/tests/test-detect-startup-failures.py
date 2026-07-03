#!/usr/bin/env python3
"""test-detect-startup-failures.py — LOCAL prove-it-can-fail test for the
startup-failure probe's detection.

Two proofs:
  1. Function-level: import `find_startup_failures` and assert it flags a
     synthetic startup_failure entry and returns nothing on clean data.
  2. Exit-code (the [CI-104]-style prove-it-can-fail): feed mock run data
     containing one startup_failure to the CLI via stdin and assert a NON-ZERO
     exit; feed clean data and assert exit 0.

Run: python3 .github/scripts/tests/test-detect-startup-failures.py
Exit 0 = all proofs held; exit 1 = a proof failed (including: the detector
could NOT be made to fail on dirty data — a false-green detector).
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
SCRIPT = SCRIPTS_DIR / "detect-startup-failures.py"

# Load the hyphenated script as a module for the function-level assertions.
_spec = importlib.util.spec_from_file_location("detect_startup_failures", SCRIPT)
_mod = importlib.util.module_from_spec(_spec)
assert _spec and _spec.loader
_spec.loader.exec_module(_mod)

DIRTY = {
    "workflow_runs": [
        {"conclusion": "success", "name": "swift-ci", "id": 1, "html_url": "u1"},
        {"conclusion": "startup_failure", "name": "swift-docs", "id": 2, "html_url": "u2"},
    ]
}
CLEAN = {
    "workflow_runs": [
        {"conclusion": "success", "name": "swift-ci", "id": 1},
        {"conclusion": "failure", "name": "swift-docs", "id": 2},
        {"conclusion": None, "name": "in-progress", "id": 3},
    ]
}


def _run_cli(payload: dict) -> int:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "-"],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
    )
    return proc.returncode


def main() -> int:
    failures = 0

    # 1. Function-level.
    dirty_runs = _mod.extract_runs(DIRTY)
    if len(_mod.find_startup_failures(dirty_runs)) == 1:
        print("  PASS function: dirty data flags exactly one startup_failure")
    else:
        print("  FAIL function: dirty data did NOT flag one startup_failure")
        failures += 1
    if _mod.find_startup_failures(_mod.extract_runs(CLEAN)) == []:
        print("  PASS function: clean data flags nothing")
    else:
        print("  FAIL function: clean data flagged something")
        failures += 1

    # 2. Exit-code prove-it-can-fail.
    rc_dirty = _run_cli(DIRTY)
    if rc_dirty != 0:
        print(f"  PASS exit-code: dirty data -> non-zero exit ({rc_dirty})")
    else:
        print(f"  FAIL exit-code: dirty data -> exit {rc_dirty} (expected non-zero) "
              "-- prove-it-can-fail FAILED, detector is false-green")
        failures += 1
    rc_clean = _run_cli(CLEAN)
    if rc_clean == 0:
        print("  PASS exit-code: clean data -> exit 0")
    else:
        print(f"  FAIL exit-code: clean data -> exit {rc_clean} (expected 0)")
        failures += 1

    print()
    if failures == 0:
        print("Total: all proofs held (detector flags startup_failure, passes on clean).")
        return 0
    print(f"Total: {failures} proof(s) FAILED.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
