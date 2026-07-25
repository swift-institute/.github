#!/usr/bin/env python3
"""Mutation harness for validate-rule-claims.py ([GH-REPO-063a]).

A validator that catches nothing is indistinguishable from a clean corpus, so
this asserts in BOTH directions: a clean fixture must pass, and each of four
deliberate breakages must be caught by the intended check.

FALSE-PASS GUARD: before trusting "the validator caught it", each mutation is
asserted to (a) EXIST and (b) DIFFER from the baseline. Without this a crashed
mutation generator yields a validator that fires on a missing/empty file, and
the harness records a pass for the wrong reason. (Failure mode observed in a
sibling lane, 2026-07-25.)

Usage:  test-validate-rule-claims.py     -> exit 0 all pass, 1 any fail
"""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
VALIDATOR = HERE / "validate-rule-claims.py"

CLEAN_SKILL = """# Fixture skill

### [FIX-001] A rule whose named enforcer exists and mentions its subject
**Statement**: Callers MUST be thin. Enforced by `real-enforcer.yml`.
[VERIFICATION: WF real-enforcer.py]

### [GH-REPO-014] Spec-title lookup table
**Statement**: The canonical source is `spec-titles.yaml`. Drift is a defect
surfaced by `sync-metadata.yml`'s validation pass.

### [GH-REPO-023] Topic count range
**Statement**: Topic count MUST be between 2 and 10 inclusive on production
packages.
"""

SCHEMA_CLEAN = '{"properties": {"topics": {"minItems": 2, "maxItems": 10}}}'
# sync-metadata.yml mentions spec-title -> [GH-REPO-014]'s claim is TRUE here.
SYNC_CLEAN = "name: sync-metadata\n# reads spec-title table and templates\n"


def build(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    skills = root / "Skills" / "fixture"
    gh = root / "github"
    (skills).mkdir(parents=True)
    (gh / ".github" / "workflows").mkdir(parents=True)
    (gh / ".github" / "scripts").mkdir(parents=True)
    (skills / "SKILL.md").write_text(CLEAN_SKILL)
    (gh / "metadata-schema.json").write_text(SCHEMA_CLEAN)
    (gh / ".github" / "workflows" / "real-enforcer.yml").write_text("name: x\n")
    (gh / ".github" / "scripts" / "real-enforcer.py").write_text("# x\n")
    (gh / ".github" / "workflows" / "sync-metadata.yml").write_text(SYNC_CLEAN)
    return skills.parent, gh


def run_validator(skills: pathlib.Path, gh: pathlib.Path):
    p = subprocess.run(
        [sys.executable, str(VALIDATOR), "--skills", str(skills),
         "--github", str(gh), "--schema", str(gh / "metadata-schema.json")],
        capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# Each mutation: (name, expected check tag, mutate(skills, gh))
def m_missing_verification_artifact(skills, gh):
    f = skills / "fixture" / "SKILL.md"
    f.write_text(f.read_text().replace("real-enforcer.py", "ghost-script.py"))
    return f


def m_nonexistent_enforcer(skills, gh):
    f = skills / "fixture" / "SKILL.md"
    f.write_text(f.read_text().replace("`real-enforcer.yml`", "`ghost-flow.yml`"))
    return f


def m_enforcer_lost_its_subject(skills, gh):
    # sync-metadata.yml no longer mentions spec-title -> [GH-REPO-014] C2b
    f = gh / ".github" / "workflows" / "sync-metadata.yml"
    f.write_text("name: sync-metadata\n# no longer reads the table\n")
    return f


def m_bound_drift(skills, gh):
    f = gh / "metadata-schema.json"
    f.write_text('{"properties": {"topics": {"minItems": 0, "maxItems": 20}}}')
    return f


MUTATIONS = [
    ("VERIFICATION names a ghost artifact", "C1", m_missing_verification_artifact),
    ("rule names a nonexistent enforcer", "C2", m_nonexistent_enforcer),
    ("enforcer stops mentioning its bound subject", "C2b",
     m_enforcer_lost_its_subject),
    ("schema bound drifts from rule text", "C3", m_bound_drift),
]


def main() -> int:
    failures = []

    # --- negative control: clean fixture must PASS -------------------------
    with tempfile.TemporaryDirectory() as td:
        skills, gh = build(pathlib.Path(td))
        code, out = run_validator(skills, gh)
        if code != 0:
            failures.append(
                f"NEGATIVE CONTROL FAILED: clean fixture should exit 0, got "
                f"{code}. Harness is unsound; mutation results below mean "
                f"nothing.\n{out}")
            print("\n".join(failures))
            return 1
        print("negative control OK — clean fixture passes (exit 0)")

    # --- mutations: each must be CAUGHT by the intended check --------------
    for name, tag, mutate in MUTATIONS:
        with tempfile.TemporaryDirectory() as td:
            skills, gh = build(pathlib.Path(td))
            baseline = {p: p.read_bytes()
                        for p in pathlib.Path(td).rglob("*") if p.is_file()}
            target = mutate(skills, gh)

            # FALSE-PASS GUARD -- the mutation must have actually happened.
            if not target.exists():
                failures.append(f"[{tag}] {name}: mutation target vanished "
                                f"({target}) — validator would fire for the "
                                f"wrong reason")
                continue
            if target.read_bytes() == baseline.get(target):
                failures.append(f"[{tag}] {name}: mutation did NOT change "
                                f"{target.name} — a pass here would be false")
                continue

            code, out = run_validator(skills, gh)
            if code == 0:
                failures.append(f"[{tag}] {name}: NOT CAUGHT (exit 0)\n{out}")
            elif f"[{tag}]" not in out:
                failures.append(f"[{tag}] {name}: caught, but by the wrong "
                                f"check (expected {tag})\n{out}")
            else:
                print(f"mutation OK — {tag}: {name}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"\nall {len(MUTATIONS)} mutations caught by the intended check; "
          f"clean fixture passes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
