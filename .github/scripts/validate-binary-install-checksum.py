#!/usr/bin/env python3
"""validate-binary-install-checksum.py — verify [CI-082] binary-install checksum verification.

Pilot 18 of `/promote-rule` (2026-05-14) — companion to validate-binary-install-checksum.yml.

Single-repo multi-file integrity check sub-shape (same shape as
validate-visibility-gate.py / validate-cache-policy.py / validate-harden-runner.py
from pilots 13/14/15).

Rules checked:
  [CI-082]  Workflow steps that fetch versioned binaries via curl MUST verify
            the artifact via `sha256sum -c` in the same `run:` block before
            installation. The verification step's exit code MUST NOT be
            swallowed (`|| true`, `2>/dev/null`).

  Four failure modes detected:
    (A) `curl ... | bash` or `curl ... | sh` — no checksum verification
        possible by construction.
    (B) `curl -fsSL` (or equivalent) + binary-install indicators in the same
        `run:` block, BUT no `sha256sum -c` in the same block.
    (C) `sha256sum ... || true` — swallowed exit code.
    (D) `sha256sum ... 2>/dev/null` — swallowed stderr (the verification's
        FAIL message goes to stderr; suppressing it disables the gate).

  Binary-install indicators (presence in the run-block flags the curl as
  an install path, distinguishing it from data/config fetches):
    - `mv ... /usr/local/bin/`, `mv ... /usr/bin/`, `mv ... /bin/`
    - `chmod +x` (mode change to executable)
    - `tar -x`, `tar xz`, `tar zx`, `tar -xf`, `tar -xzf`, `tar -xJf`
    - `unzip`
    - `install -m` (Unix install command with mode)
    - `tee /etc/apt/keyrings/` (apt keyring install — trust root for
      subsequent apt-get installs per [CI-060] / supply-chain reasoning)
    - `gunzip`, `xz -d`

  Permitted-exception (from rule body): `apt-get install` packages don't
  fire because apt itself verifies signatures via keyring. The validator
  does NOT inspect apt-get install steps. But a curl-fetched apt keyring
  IS in scope — the keyring is the trust root and its integrity must be
  verified before it gates downstream package installs.

  No file-level carve-outs. [CI-082] applies to every workflow regardless
  of trigger shape (reusable, standalone, cron orchestrator).

Detection shape: per-step shell-content inspection. Walks YAML to enumerate
steps, then inspects each step's `run:` block as plain text. No shell
parser dependency; regex matches against the shell-script text body.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

# curl trigger: `-fsSL`, `--fail --silent --location`, or `--silent --location`
# combinations. Real-world workflow installs converge on `-fsSL`; the regex
# also matches the spelled-out form to avoid silent under-firing on equivalent
# invocations.
CURL_TRIGGER_RE = re.compile(
    r"\bcurl\b[^\n]*?(?:-fsSL\b|--fail\s+--silent\s+--location\b|--silent\s+--location\b|-sSL\b|-Lf\b|-fL\b)",
)

# Pipe-to-bash / pipe-to-sh — pattern (A). The pipe target may have flags
# (`bash -s`, `sh -e`) so match `\bbash\b` or `\bsh\b` after the pipe.
CURL_PIPE_TO_SHELL_RE = re.compile(
    r"\bcurl\b[^\n|]*?\|[^\n|]*?(?:\bbash\b|\bsh\b)(?:[\s\\;]|$)",
)

# Binary-install indicators — pattern (B). Presence in the same run-block
# flags the curl as an install path. Each indicator is a robust shell-level
# pattern.
INSTALL_INDICATORS = (
    re.compile(r"\bmv\b[^\n]*?(?:/usr/local/bin/|/usr/bin/|(?<!\w)/bin/)"),
    re.compile(r"\bchmod\b[^\n]*?\+x\b"),
    re.compile(r"\btar\b[^\n]*?(?:-x\w*|x[^\n]*?\b[Jcjzv]+\b)"),
    re.compile(r"\bunzip\b"),
    re.compile(r"\binstall\b\s+-\w*m\d"),
    re.compile(r"\btee\b[^\n]*?/etc/apt/keyrings/"),
    re.compile(r"\bgunzip\b"),
    re.compile(r"\bxz\b\s+-d\b"),
)

# sha256sum-c verification — the canonical PASS shape. `-c` (or `--check`)
# reads digest+filename pairs and verifies; without `-c` the tool computes
# but doesn't verify.
SHA256SUM_VERIFY_RE = re.compile(r"\bsha256sum\b[^\n|]*?(?:-c\b|--check\b)")

# Swallowed exit code — pattern (C). `|| true` after sha256sum nullifies the
# gate.
SHA256SUM_OR_TRUE_RE = re.compile(
    r"\bsha256sum\b[^\n]*?\|\|\s*(?:true|:)\b",
)

# Swallowed stderr — pattern (D). `2>/dev/null` after sha256sum hides the
# FAIL message; combined with `|| true` would also swallow the exit code.
SHA256SUM_2_DEVNULL_RE = re.compile(
    r"\bsha256sum\b[^\n]*?2>/dev/null\b",
)


def iter_steps(jobs: dict):
    """Yield (job_name, step_index, step_data) for every step in every job."""
    for job_name, job_data in jobs.items():
        if not isinstance(job_data, dict):
            continue
        steps = job_data.get("steps")
        if not isinstance(steps, list):
            continue
        for idx, step in enumerate(steps):
            if isinstance(step, dict):
                yield job_name, idx, step


def has_install_indicator(run_block: str) -> bool:
    """True if the run-block contains any binary-install indicator."""
    return any(pat.search(run_block) for pat in INSTALL_INDICATORS)


def check_run_block(
    repo: str,
    wf_name: str,
    job_name: str,
    step_label: str,
    run_block: str,
) -> int:
    """Apply [CI-082] checks to a single shell `run:` block."""
    findings = 0
    # Pattern A: pipe-to-shell — fire regardless of install indicators.
    if CURL_PIPE_TO_SHELL_RE.search(run_block):
        emit(
            repo,
            "CI-082",
            f"{wf_name}: job {job_name!r} step {step_label!r} pipes curl "
            f"output directly into a shell (`curl ... | bash` or "
            f"`curl ... | sh`) — per [CI-082] this is forbidden because "
            f"no checksum verification is possible by construction. Fetch "
            f"to a file, `sha256sum -c` against a pinned digest, then exec.",
        )
        findings += 1
    # Pattern C/D: swallowed sha256sum verification.
    if SHA256SUM_OR_TRUE_RE.search(run_block):
        emit(
            repo,
            "CI-082",
            f"{wf_name}: job {job_name!r} step {step_label!r} has "
            f"`sha256sum ... || true` — per [CI-082] the verification step "
            f"MUST fail-closed. The `|| true` swallow nullifies the gate; "
            f"remove it so a digest mismatch fails the job.",
        )
        findings += 1
    if SHA256SUM_2_DEVNULL_RE.search(run_block):
        emit(
            repo,
            "CI-082",
            f"{wf_name}: job {job_name!r} step {step_label!r} has "
            f"`sha256sum ... 2>/dev/null` — per [CI-082] the FAIL message "
            f"MUST be visible. Suppressing stderr disables the gate's "
            f"diagnostic surface.",
        )
        findings += 1
    # Pattern B: curl + install indicators without sha256sum-c.
    if CURL_TRIGGER_RE.search(run_block) and has_install_indicator(run_block):
        if not SHA256SUM_VERIFY_RE.search(run_block):
            emit(
                repo,
                "CI-082",
                f"{wf_name}: job {job_name!r} step {step_label!r} fetches "
                f"an artifact via curl AND installs it (mv to bin path, "
                f"chmod +x, tar/unzip, apt keyring) WITHOUT `sha256sum -c` "
                f"verification in the same run-block — per [CI-082] every "
                f"curl-fetched binary install MUST verify the artifact "
                f"against a pinned SHA-256 before installation. Reference "
                f"shape: see the lychee install in [CI-082] body.",
            )
            findings += 1
    return findings


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every step's run-block in the workflow against [CI-082]."""
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-082", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return 0
    findings = 0
    for job_name, step_idx, step in iter_steps(jobs):
        run_block = step.get("run")
        if not isinstance(run_block, str) or not run_block.strip():
            continue
        step_name = step.get("name")
        step_label = step_name if isinstance(step_name, str) and step_name else f"#{step_idx}"
        findings += check_run_block(repo, wf_path.name, job_name, step_label, run_block)
    return findings


def main(repo: str, repo_root: str) -> int:
    """Validate every workflow under <repo_root>/.github/workflows/."""
    findings = 0
    workflows_dir = Path(repo_root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return 0
    targets = sorted(list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml")))
    for wf in targets:
        findings += check_workflow(repo, wf)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-binary-install-checksum.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
