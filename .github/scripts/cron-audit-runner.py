#!/usr/bin/env python3
"""
Generic per-target runner for cron-audit-base.yml callers.

Replaces the per-caller `audit-step:` shell snippet (~30 lines of bash
duplicated across 3 callers) with a single Python driver invoked via the
structured-input contract introduced in Phase C of the 2026-05-14 CI
review (Q2=B). The contract removes the caller-supplied shell string and
thereby closes the template-injection class on the cross-org App-token-
holding job in cron-audit-base.yml.

Per-target loop:
    1. `gh repo list <org> --limit 2000 --visibility public` → targets
    2. for each target: git-clone (depth 1) with GH_TOKEN
    3. invoke `<audit-script> --package-dir <workdir> --json <tmpjson>`
    4. parse JSON via dotted `json_totals_path`
    5. extract values at `count_keys`; accumulate totals
    6. (optional) format per-package extra line via `extra_template`
       gated by `extra_when_keys`
    7. cleanup workdir

Output:
    /tmp/<ORG>-counts.txt   comma-separated totals in count_keys order
    /tmp/<ORG>-extra.txt    newline-separated per-package extras
    GITHUB_STEP_SUMMARY     markdown summary (when env var set)

CLI:
    cron-audit-runner.py
        --audit-script /tmp/audit-script.py
        --org swift-primitives
        --args-json '{"json_totals_path":"totals",
                       "count_keys":["missing","files_scanned"],
                       "extra_template":"- `{pkg}`: {missing}/{files_scanned} missing",
                       "extra_when_keys":["missing"],
                       "summary_label":"license-header sweep"}'

Trust contract:
    All caller input arrives as the JSON-decoded `args_json` dict. No
    `subprocess(..., shell=True)` calls; no eval; no exec; no shell
    interpolation. The audit-script invocation uses subprocess list-args.
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def gh_list_targets(org: str) -> list[str]:
    """Return public, non-archived nameWithOwner repo paths in `org`."""
    result = subprocess.run(
        ["gh", "repo", "list", org, "--limit", "2000",
         "--visibility", "public",
         "--json", "nameWithOwner,isArchived",
         "--jq", ".[] | select(.isArchived==false) | .nameWithOwner"],
        capture_output=True, text=True, check=True,
    )
    return [line for line in result.stdout.splitlines() if line.strip()]


def clone_target(target: str, workdir: Path, gh_token: str) -> bool:
    """Shallow-clone `target` into `workdir`. Return True on success."""
    url = f"https://x-access-token:{gh_token}@github.com/{target}.git"
    result = subprocess.run(
        ["git", "clone", "--depth", "1", "--quiet", url, str(workdir)],
        capture_output=True,
    )
    return result.returncode == 0


def navigate_path(obj: dict, dotted: str) -> dict:
    """Navigate a dotted path into a nested dict. Empty path → obj itself."""
    if not dotted:
        return obj
    cur = obj
    for key in dotted.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return {}
        cur = cur[key]
    return cur if isinstance(cur, dict) else {}


def run_audit(audit_script: Path, workdir: Path, json_out: Path) -> dict:
    """Invoke audit-script per-package; return parsed JSON or empty dict."""
    subprocess.run(
        ["python3", str(audit_script),
         "--package-dir", str(workdir),
         "--json", str(json_out)],
        capture_output=True, check=False,
    )
    try:
        return json.loads(json_out.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def main() -> int:
    ap = argparse.ArgumentParser(description="Generic cron-audit per-target runner")
    ap.add_argument("--audit-script", type=Path, required=True)
    ap.add_argument("--org", required=True)
    ap.add_argument("--args-json", required=True,
                    help="JSON-encoded config dict (see module docstring)")
    args = ap.parse_args()

    cfg = json.loads(args.args_json)
    json_totals_path = cfg.get("json_totals_path", "totals")
    count_keys = list(cfg.get("count_keys", []))
    extra_template = cfg.get("extra_template", "")
    extra_when_keys = list(cfg.get("extra_when_keys", count_keys))
    summary_label = cfg.get("summary_label", "audit")

    gh_token = os.environ.get("GH_TOKEN", "")
    if not gh_token:
        print("error: GH_TOKEN not set in environment", file=sys.stderr)
        return 2

    targets = gh_list_targets(args.org)
    totals: dict[str, int] = {k: 0 for k in count_keys}
    per_pkg: list[str] = []

    for target in targets:
        workdir = Path(tempfile.mkdtemp())
        json_out = Path(tempfile.gettempdir()) / f"{target.replace('/', '__')}.json"
        try:
            if not clone_target(target, workdir, gh_token):
                continue
            audit_json = run_audit(args.audit_script, workdir, json_out)
            totals_dict = navigate_path(audit_json, json_totals_path)
            values = {k: int(totals_dict.get(k, 0) or 0) for k in count_keys}
            for k, v in values.items():
                totals[k] += v
            if extra_template and any(values.get(k, 0) > 0 for k in extra_when_keys):
                pkg_name = target.rsplit("/", 1)[-1]
                per_pkg.append(extra_template.format(pkg=pkg_name, **values))
        finally:
            shutil.rmtree(workdir, ignore_errors=True)
            try:
                json_out.unlink()
            except OSError:
                pass

    counts_line = ",".join(str(totals[k]) for k in count_keys)
    Path(f"/tmp/{args.org}-counts.txt").write_text(counts_line + "\n")
    if per_pkg:
        Path(f"/tmp/{args.org}-extra.txt").write_text("\n".join(per_pkg) + "\n")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a") as f:
            f.write(f"## Org {args.org} — {summary_label}\n")
            for k in count_keys:
                f.write(f"- {k}: {totals[k]}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
