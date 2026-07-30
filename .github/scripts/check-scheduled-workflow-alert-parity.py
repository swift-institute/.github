#!/usr/bin/env python3
"""check-scheduled-workflow-alert-parity.py — fail closed on watch-list drift (#123).

`.github/workflows/alert-scheduled-workflow-failure.yml` observes scheduled
control-plane workflow failures via a `workflow_run` trigger, which GitHub
requires to name its subject workflows explicitly (`on.workflow_run.workflows:`
— an exact-name list, not a wildcard or a query over `schedule:` triggers).
That list is therefore a second, hand-maintained copy of "which workflows in
this repository run on a schedule" — the exact drift class #123 exists to
close, one level up: a scheduled workflow added or renamed without a matching
entry here would silently fall outside observability again, the same way
`reconcile-project-invariants.yml` fell silent after 747eeaa5 (#120).

This script discovers every workflow file in `.github/workflows/` with an
`on.schedule:` trigger (never a hard-coded roster) and asserts the set of
their `name:` fields matches the alert workflow's watch list exactly in both
directions:

  - missing-from-watch-list: a workflow has a `schedule:` trigger but its
    name is absent from the watch list (the #123 silent-gap scenario).
  - stale-watch-entry: a name is on the watch list but no workflow in the
    directory currently has a `schedule:` trigger with that name (a rename,
    removal, or trigger change left a dead entry — harmless for alerting but
    evidence the list stopped tracking reality).

Usage:
    check-scheduled-workflow-alert-parity.py [workflows-dir] [alert-workflow-path]

Exit 0 with no output when the watch list matches the scheduled-workflow set
exactly. Exit 1 with one TSV finding line per gap otherwise. Exit 2 on a
structural read/parse failure (missing directory, missing alert workflow,
missing `on.workflow_run.workflows`, PyYAML absent) — an environment/shape
defect, not a drift finding.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

REPO = "swift-institute/.github"
RULE = "SCHEDULED-WORKFLOW-ALERT-DRIFT"

DEFAULT_WORKFLOWS_DIR = ".github/workflows"
DEFAULT_ALERT_PATH = ".github/workflows/alert-scheduled-workflow-failure.yml"


def emit(message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{REPO}\t{RULE}\t{safe}")


def require_yaml():
    try:
        import yaml
        return yaml
    except ImportError:
        print("# error: PyYAML not installed", file=sys.stderr)
        sys.exit(2)


def parse_on_block(data: dict) -> dict | None:
    # PyYAML's yaml-1.1 boolean quirk: a bare `on:` key parses as Python
    # `True`, not the string "on". Recover it the same way validate_lib.py's
    # parse_on_block and validate-visibility-gate.py's equivalent do.
    on = data.get("on")
    if on is None:
        on = data.get(True)
    return on if isinstance(on, dict) else None


def scheduled_names_from_docs(docs: dict[str, dict]) -> dict[str, str]:
    """docs: filename -> parsed workflow YAML dict.

    Returns {workflow-name: filename} for every doc whose `on:` block has a
    `schedule:` key. The workflow `name:` field is the key GitHub matches
    `workflow_run.workflows:` entries against; falls back to the filename
    stem when `name:` is absent (no shipped workflow currently omits it, but
    a missing field should not silently drop the workflow from the set).
    """
    scheduled: dict[str, str] = {}
    for filename, data in docs.items():
        if not isinstance(data, dict):
            continue
        on = parse_on_block(data)
        if isinstance(on, dict) and "schedule" in on:
            name = data.get("name") or Path(filename).stem
            scheduled[str(name)] = filename
    return scheduled


def watched_names_from_alert_doc(alert_data: dict) -> set[str]:
    on = parse_on_block(alert_data) or {}
    workflow_run = on.get("workflow_run") or {}
    if not isinstance(workflow_run, dict):
        raise LookupError("alert workflow's on: block has no workflow_run: mapping")
    workflows = workflow_run.get("workflows")
    if not isinstance(workflows, list):
        raise LookupError("alert workflow's on.workflow_run has no workflows: list")
    return {str(w) for w in workflows}


def compute_drift(scheduled: dict[str, str], watched: set[str]) -> list[tuple[str, str, str]]:
    """Return (name, surface, message) findings. Empty means the watch list
    matches the scheduled-workflow set exactly in both directions."""
    findings: list[tuple[str, str, str]] = []

    for name in sorted(scheduled):
        if name not in watched:
            filename = scheduled[name]
            findings.append((
                name, "missing-from-watch-list",
                f"'{filename}' has a schedule: trigger (workflow name '{name}') but is "
                f"absent from alert-scheduled-workflow-failure.yml's on.workflow_run.workflows list",
            ))

    for name in sorted(watched):
        if name not in scheduled:
            findings.append((
                name, "stale-watch-entry",
                f"'{name}' is listed in alert-scheduled-workflow-failure.yml's "
                f"on.workflow_run.workflows list but no workflow in the workflows "
                f"directory currently has a schedule: trigger with that name",
            ))

    return findings


def load_docs(workflows_dir: Path, yaml: Any, exclude: set[str]) -> dict[str, dict]:
    docs: dict[str, dict] = {}
    for path in sorted(workflows_dir.glob("*.yml")):
        if path.name in exclude:
            continue
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - surface as a structural error, not a finding
            print(f"# error: cannot parse {path}: {exc}", file=sys.stderr)
            sys.exit(2)
        if isinstance(data, dict):
            docs[path.name] = data
    return docs


def main(argv: list[str]) -> int:
    yaml = require_yaml()
    workflows_dir = Path(argv[1] if len(argv) > 1 else DEFAULT_WORKFLOWS_DIR)
    alert_path = Path(argv[2] if len(argv) > 2 else DEFAULT_ALERT_PATH)

    if not workflows_dir.is_dir():
        print(f"# error: no such directory: {workflows_dir}", file=sys.stderr)
        return 2
    if not alert_path.is_file():
        print(f"# error: no such file: {alert_path}", file=sys.stderr)
        return 2

    try:
        alert_data = yaml.safe_load(alert_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"# error: cannot parse {alert_path}: {exc}", file=sys.stderr)
        return 2
    if not isinstance(alert_data, dict):
        print(f"# error: {alert_path} did not parse to a mapping", file=sys.stderr)
        return 2

    # The alert workflow itself carries no schedule: trigger (it is
    # workflow_run-triggered only), so excluding it from the scan is belt
    # and suspenders rather than a load-bearing exclusion.
    docs = load_docs(workflows_dir, yaml, exclude={alert_path.name})
    scheduled = scheduled_names_from_docs(docs)

    try:
        watched = watched_names_from_alert_doc(alert_data)
    except LookupError as exc:
        print(f"# error: {alert_path} does not have the expected shape: {exc}", file=sys.stderr)
        return 2

    findings = compute_drift(scheduled, watched)

    for name, surface, message in findings:
        emit(f"{surface}: {message}")

    if findings:
        print(f"::error::{len(findings)} scheduled-workflow watch-list drift finding(s). "
              f"A workflow with a schedule: trigger must be named in "
              f"alert-scheduled-workflow-failure.yml's on.workflow_run.workflows list, "
              f"and every entry on that list must name a workflow that still has a "
              f"schedule: trigger. See findings above.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
