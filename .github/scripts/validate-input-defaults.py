#!/usr/bin/env python3
"""validate-input-defaults.py — verify [CI-058] reusable-workflow input defaults.

Pilot 24 of `/promote-rule` (2026-05-14) — companion to validate-input-defaults.yml.

Single-repo multi-file integrity check sub-shape.

Rules checked:
  [CI-058]  Any reusable workflow that declares an `enable-private-repos`
            input MUST default it to `true`. Three known target files:
              - swift-institute/.github/.github/workflows/swift-ci.yml
              - swift-institute/.github/.github/workflows/swift-docs.yml
              - swift-primitives/.github/.github/workflows/swift-ci.yml
            The validator is repo-agnostic: it scans every workflow under
            `<repo_root>/.github/workflows/*.yml,yaml`, locates the
            `on.workflow_call.inputs.enable-private-repos` path, and fires
            if its `default:` is not `True`. Workflows that don't declare
            the input are out of scope.

  No file-level carve-outs.

Detection shape: PyYAML walk; navigate to the named input declaration; check
its default literal.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

INPUT_NAME = "enable-private-repos"
REQUIRED_DEFAULT = True


def check_workflow(repo: str, wf_path: Path) -> int:
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-058", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    # PyYAML parses bare `on:` key as Python True. Look up by both spellings.
    on_block = data.get("on", data.get(True))
    if not isinstance(on_block, dict):
        return 0
    wc = on_block.get("workflow_call")
    if not isinstance(wc, dict):
        return 0
    inputs = wc.get("inputs")
    if not isinstance(inputs, dict):
        return 0
    spec = inputs.get(INPUT_NAME)
    if not isinstance(spec, dict):
        return 0  # workflow doesn't declare this input — out of scope
    default = spec.get("default")
    if default is REQUIRED_DEFAULT:
        return 0
    emit(
        repo,
        "CI-058",
        f"{wf_path.name}: `on.workflow_call.inputs.{INPUT_NAME}.default` "
        f"must be `true` per [CI-058] — the canonical case (most consumers "
        f"depend on private intra-Institute siblings) wants the default "
        f"to enable the private-repo configure-git step. Public-only "
        f"consumers MAY pass `with: {{ {INPUT_NAME}: false }}` explicitly "
        f"to opt out. Got default={default!r}.",
    )
    return 1


def main(repo: str, repo_root: str) -> int:
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
        sys.exit("usage: validate-input-defaults.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
