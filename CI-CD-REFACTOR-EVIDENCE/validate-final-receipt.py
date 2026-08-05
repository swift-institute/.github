#!/usr/bin/env python3
"""§6.3/§6.4 structural validator for the completion receipt (R29 phases).
--phase pre-finalization validates the candidate (no post-action content
required); --phase post-finalization additionally requires the post-action
readback section, P27/P28 MET, and the absence of the candidate banner."""
import argparse
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--phase", choices=["pre-finalization", "post-finalization"], required=True)
ap.add_argument("receipt")
a = ap.parse_args()
text = open(a.receipt).read()
errors = []

TABLES = [
    "Governing heads at start and finish", "Programme and work objects",
    "App installations and permissions", "Mutations", "Local evidence",
    "Workflow evidence", "Positive and negative controls",
    "Re-derived population", "Caller convergence",
    "Required-check and ruleset migration", "Private verification",
    "Effective-runtime receipts", "Inline annotations", "Scheduled workflows",
    "Deletions and zero-use proofs", "Operational stops encountered",
]
if text.count("## Authority\n") != 1:
    errors.append("exactly one Authority block required")
for t in TABLES:
    if text.count(f"## {t}\n") != 1:
        errors.append(f"table section missing or duplicated: {t}")
    else:
        seg = text.split(f"## {t}\n", 1)[1].split("\n## ", 1)[0]
        if "|---" not in seg:
            errors.append(f"section is not a table: {t}")
if text.count("## Workspace reconciliation\n") != 1:
    errors.append("exactly one Workspace reconciliation list required")
else:
    seg = text.split("## Workspace reconciliation\n", 1)[1].split("\n## ", 1)[0]
    for field in ("Effective inventory digest", "Committed public inventory digest",
                  "Private runtime inventory digest", "Represented", "Missing",
                  "Stale", "Unexplained", "UNMEASURED"):
        if f"- {field}:" not in seg:
            errors.append(f"reconciliation field missing: {field}")
checked = re.findall(r"^- \[x\] ", text, re.M)
unchecked = re.findall(r"^- \[ \] ", text, re.M)
if len(checked) != 16 or unchecked:
    errors.append(f"exactly 16 checked assertions required (found {len(checked)} checked, {len(unchecked)} unchecked)")
if "name-reservation class (Corrigendum §11.2)" not in text:
    errors.append("Corrigendum §11.2 name-reservation population row missing")
if "Overall result: COMPLETE" not in text:
    errors.append("Authority overall result must be COMPLETE")
# §6.4: no private subject coordinates. The one private subject this
# programme touched must appear only as its opaque request-id.
for leak in ("swift-rfc-6455", "swift-rfc-9457", "swift-rfc-9000"):
    if leak in text:
        errors.append(f"private subject coordinate present: {leak}")
if "diag0005run0005" not in text:
    errors.append("opaque private subject ID missing from Private verification")
# §6.4 full-SHA rule: every backticked hex token of 7-39 chars that is not
# part of a 40/64-char token is a short SHA.
for m in re.finditer(r"`([0-9a-f]{7,63})`", text):
    tok = m.group(1)
    if len(tok) not in (40, 64):
        errors.append(f"short SHA in evidence field: {tok}")
if a.phase == "post-finalization":
    if "## Post-action readbacks (R29)" not in text:
        errors.append("post-finalization requires the post-action readback section")
    if "MET — the receipt you are reading contains the post-action readbacks" not in text:
        errors.append("P27/P28 must read MET in the final receipt")
    if "pre-finalization candidate" in text:
        errors.append("final receipt must not carry the candidate banner")
    if "MISSING" in text:
        errors.append("post-action readback fields incomplete")
else:
    if "pre-finalization candidate (R29)" not in text:
        errors.append("candidate must carry the R29 candidate banner")

if errors:
    print(f"FAIL ({a.phase}): {len(errors)} error(s)")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print(f"PASS ({a.phase}): 1 Authority block, 16 tables, 1 reconciliation list, "
      f"16 assertions, name-reservation row, opaque subject, full-SHA rule")
