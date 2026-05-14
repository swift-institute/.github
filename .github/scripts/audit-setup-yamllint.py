#!/usr/bin/env python3
"""
One-time per-job setup for the γ-2 mechanical-hygiene audit:
pip install yamllint, then write the canonical /tmp/yamllint.yml config.

Replaces the inline `pip install --quiet yamllint` + heredoc shell that
lived in lint-mechanical-hygiene-weekly.yml's audit-step before Phase C
of the 2026-05-14 CI review (Q2=B). Invoked by cron-audit-base.yml's
audit-setup-script-path input, before the runner's per-target loop.

The heredoc rules MUST stay in sync with the prior inline block: the
weekly sweep's baseline numbers depend on the rule set (in particular,
line-length 200 and indentation 2-space).
"""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

YAMLLINT_CONFIG_PATH = Path("/tmp/yamllint.yml")

YAMLLINT_CONFIG = """\
extends: default
rules:
  document-start: disable
  line-length:
    max: 200
    level: warning
  truthy:
    allowed-values: ["true", "false"]
    check-keys: false
  indentation:
    spaces: 2
  comments:
    require-starting-space: false
"""


def main() -> int:
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--quiet", "yamllint"],
        check=True,
    )
    YAMLLINT_CONFIG_PATH.write_text(YAMLLINT_CONFIG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
