#!/usr/bin/env python3
"""Fail-closed controls for swift-ci.yml's prebuilt-linter identity check.

#43 item 4: the `ci-binaries` release tag is mutable and its SHA256SUMS
travels with the binaries it attests, so a download that verifies only
against the fetched sums has no immutable identity — the whole set can
move together. The shipped step therefore requires MANIFEST.txt to name
the engine commit and requires it to match the engine's current main
HEAD, falling back closed (ok=false → pinned source build) otherwise.

Reasoning that the step would fall back is not watching it fall back, so
this suite extracts the shipped step body from swift-ci.yml (same
discipline as test-ci-ok-aggregate.py: the bytes under test are the
bytes that ship) and runs it hermetically — `curl`, `git`, and `install`
are PATH shims, the release set is a seeded fixture — asserting:

  - a manifest that omits `engine=` sets ok=false (fetch omitted the
    immutable identity);
  - a manifest whose engine mismatches the resolved main HEAD sets
    ok=false (stale or moved release);
  - an unresolvable engine HEAD sets ok=false;
  - the matching case still installs and sets ok=true (positive control
    that the fast path survives the gate);
  - a corrupted binary still fails the checksum leg (the pre-existing
    gate keeps firing behind the new one).
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

WORKFLOW = Path(__file__).parents[2] / "workflows" / "swift-ci.yml"
STEP_NAME = "Download prebuilt linter binaries"
JOB_ID = "swift-linter"

ENGINE_SHA = "a" * 40
OTHER_SHA = "b" * 40


def extract_step() -> str:
    document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = document.get("jobs", {}).get(JOB_ID)
    if job is None:
        raise SystemExit(f"{WORKFLOW}: no job '{JOB_ID}' — extraction target gone")
    for step in job.get("steps", []):
        if step.get("name") == STEP_NAME:
            body = step.get("run")
            if not body:
                raise SystemExit(f"{WORKFLOW}: step '{STEP_NAME}' has no run: body")
            return body
    raise SystemExit(
        f"{WORKFLOW}: job '{JOB_ID}' has no step named '{STEP_NAME}'. "
        "This suite tests the shipped bytes by name; rename it here too."
    )


class IdentityGateTests(unittest.TestCase):
    script = extract_step()

    def run_step(self, manifest: str, head_sha: str | None, corrupt: bool = False):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            release = root / "release"
            release.mkdir()
            (release / "swift-linter").write_bytes(b"#!binary-one\n")
            (release / "swift-linter-runner").write_bytes(b"#!binary-two\n")
            (release / "MANIFEST.txt").write_text(manifest, encoding="utf-8")
            subprocess.run(
                "sha256sum MANIFEST.txt swift-linter swift-linter-runner > SHA256SUMS",
                cwd=release, shell=True, check=True,
            )
            if corrupt:
                (release / "swift-linter").write_bytes(b"#!tampered\n")

            shims = root / "bin"
            shims.mkdir()
            (shims / "curl").write_text(
                "#!/usr/bin/env bash\n"
                '# hermetic shim: last two args are -o <dest> ... <url>; serve the fixture file\n'
                'dest=""; url=""\n'
                'while [ $# -gt 0 ]; do\n'
                '  case "$1" in\n'
                '    -o) dest="$2"; shift 2 ;;\n'
                '    *) url="$1"; shift ;;\n'
                '  esac\n'
                'done\n'
                f'cp "{release}/$(basename "$url")" "$dest"\n',
                encoding="utf-8",
            )
            git_body = "#!/usr/bin/env bash\n"
            if head_sha is None:
                git_body += "exit 0\n"
            else:
                git_body += f'printf "%s\\trefs/heads/main\\n" "{head_sha}"\n'
            (shims / "git").write_text(git_body, encoding="utf-8")
            installed = root / "installed.log"
            (shims / "install").write_text(
                "#!/usr/bin/env bash\n"
                f'echo "$@" >> "{installed}"\n',
                encoding="utf-8",
            )
            for shim in shims.iterdir():
                shim.chmod(0o755)

            script = root / "step.sh"
            script.write_text(self.script, encoding="utf-8")
            output = root / "github_output"
            output.touch()
            env = dict(os.environ)
            env["PATH"] = f"{shims}:{env['PATH']}"
            env["GITHUB_OUTPUT"] = str(output)
            result = subprocess.run(
                ["bash", str(script)], capture_output=True, text=True, env=env
            )
            return result, output.read_text(encoding="utf-8"), installed.exists()

    def manifest(self, engine_line: str) -> str:
        return f"digest={'c' * 64}\n{engine_line}built-at=2026-07-30T00:00:00Z\n"

    def test_missing_engine_identity_falls_back_closed(self) -> None:
        result, output, installed = self.run_step(self.manifest(""), ENGINE_SHA)
        self.assertIn("ok=false", output, result.stdout + result.stderr)
        self.assertIn("names no engine commit", result.stdout)
        self.assertFalse(installed)

    def test_engine_mismatch_falls_back_closed(self) -> None:
        result, output, installed = self.run_step(
            self.manifest(f"engine={OTHER_SHA}\n"), ENGINE_SHA
        )
        self.assertIn("ok=false", output, result.stdout + result.stderr)
        self.assertIn("does not match engine main HEAD", result.stdout)
        self.assertFalse(installed)

    def test_unresolvable_head_falls_back_closed(self) -> None:
        result, output, installed = self.run_step(
            self.manifest(f"engine={ENGINE_SHA}\n"), None
        )
        self.assertIn("ok=false", output, result.stdout + result.stderr)
        self.assertFalse(installed)

    def test_matching_identity_installs(self) -> None:
        result, output, installed = self.run_step(
            self.manifest(f"engine={ENGINE_SHA}\n"), ENGINE_SHA
        )
        self.assertIn("ok=true", output, result.stdout + result.stderr)
        self.assertTrue(installed)

    def test_checksum_still_gates_behind_identity(self) -> None:
        result, output, installed = self.run_step(
            self.manifest(f"engine={ENGINE_SHA}\n"), ENGINE_SHA, corrupt=True
        )
        self.assertIn("ok=false", output, result.stdout + result.stderr)
        self.assertFalse(installed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
