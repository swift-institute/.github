"""validate_lib.py — shared helpers for .github/scripts/validate-*.py.

Phase B-1 of CI-REVIEW-PHASE-B-DESIGN-2026-05-14 §2. Centralizes the
boilerplate that the 14 yaml-importing per-rule validators replicate
inline (try/except yaml import + emit() helper + on:/jobs: walks +
parse-and-emit shape). v1 API is intentionally minimal — only the
shape that appears identically across the existing corpus is
centralized; rule-specific helpers stay in the per-rule scripts.

Import shape (preferred):

    from validate_lib import emit, require_yaml, parse_on_block, iter_jobs, load_workflow_yaml_or_emit
    yaml = require_yaml()

The explicit-name import surfaces in grep when auditing helper usage.
The companion `validators-manifest.yaml` records which per-rule
scripts have been migrated to validate_lib.

Co-located with validate-*.py scripts so Python's default sys.path
resolution finds validate_lib without extra setup.
"""
from __future__ import annotations
import sys
from pathlib import Path
from typing import Iterator, Optional, Tuple


def emit(repo: str, rule: str, message: str) -> None:
    """Emit a single TSV finding line: repo<TAB>rule<TAB>message.

    Tabs and newlines in message are flattened to spaces so downstream
    awk-friendly aggregation (validate-base.yml step `aggregate findings`)
    can parse columns reliably.
    """
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def require_yaml():
    """Import PyYAML; exit(2) with a structured error if absent.

    Returns the yaml module on success. Idempotent (Python's import
    machinery caches the module). Per the existing inline pattern
    across 14 validators, exit code 2 signals 'environment defect,
    not a finding' to the fixture harness and CI.
    """
    try:
        import yaml
        return yaml
    except ImportError:
        print("# error: PyYAML not installed", file=sys.stderr)
        sys.exit(2)


def parse_on_block(data: dict) -> Optional[dict]:
    """Return the `on:` mapping from a parsed workflow YAML doc.

    Handles three forms:
      - bare keyword:   `on: push`             (PyYAML parses as None or True)
      - list form:      `on: [push, pr]`       (returns None — callers handle)
      - map form:       `on: {workflow_call: ...}`  (returns dict)

    PyYAML's `on:` quirk: bare `on:` parses as Python `True` (yaml 1.1
    booleans). The fallback `data.get(True)` recovers this case.

    Returns the dict for the map form; returns None for absent /
    scalar / list shapes. Callers handle None as 'no map-form triggers'.
    """
    on = data.get("on")
    if on is None:
        on = data.get(True)
    return on if isinstance(on, dict) else None


def iter_jobs(data: dict) -> Iterator[Tuple[str, dict]]:
    """Yield (job_name, job_data) for every job in a parsed workflow doc.

    Skips malformed jobs (non-dict values). Returns nothing if jobs:
    is absent or malformed at the top level. The skip-malformed
    behavior matches the per-validator inline pattern.
    """
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return
    for name, jdata in jobs.items():
        if isinstance(jdata, dict):
            yield name, jdata


def load_workflow_yaml_or_emit(repo: str, rule: str, path: Path) -> Optional[dict]:
    """Read + safe_load a workflow YAML file. On parse failure, emit() a
    finding citing the parser error and return None. On success, return
    the parsed dict (or None if top-level is not a dict).

    The `rule` argument is the rule-ID cited on parse-failure findings
    (e.g., 'CI-040' for validate-cache-policy). When a validator covers
    multiple rules, cite the primary rule-ID — parse failures are
    rule-agnostic in practice but the TSV column needs SOME value.
    """
    yaml = require_yaml()
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, rule, f"{path.name}: YAML parse failed: {e}")
        return None
    return data if isinstance(data, dict) else None
