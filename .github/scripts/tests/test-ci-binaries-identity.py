#!/usr/bin/env python3
"""Fail-closed controls for swift-ci.yml's published-linter installer.

The workflow now installs the checksum-sealed `ci-binaries` release directly;
it no longer has a mutable-release identity comparison or a source-build
fallback. This suite extracts the shipped installation step and executes it
against a hermetic release fixture, proving that a complete manifest installs
and that missing authority provenance or a checksum mismatch still refuses to
install.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

WORKFLOW = Path(__file__).parents[2] / "workflows" / "swift-ci.yml"
STEP_NAME = "Install published linter binaries"
JOB_ID = "swift-linter"

AUTHORITIES = [
    "engine",
    "swift-primitives-linter-rules",
    "swift-standards-linter-rules",
    "swift-institute-linter-rules",
    "swift-linter-rules",
    "swift-linter-primitives",
]


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


class PublishedBinariesInstallerTests(unittest.TestCase):
    script = extract_step()

    def run_step(self, manifest: str, corrupt: bool = False):
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
                '# hermetic shim: serve the requested release fixture asset\n'
                'dest=""; url=""\n'
                'while [ $# -gt 0 ]; do\n'
                '  case "$1" in\n'
                '    -o|--output) dest="$2"; shift 2 ;;\n'
                '    *) url="$1"; shift ;;\n'
                '  esac\n'
                'done\n'
                f'cp "{release}/$(basename "$url")" "$dest"\n',
                encoding="utf-8",
            )
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
            env["GITHUB_STEP_SUMMARY"] = str(root / "github_summary")
            env["GITHUB_ENV"] = str(root / "github_env")
            env["LINTER_RELEASE"] = "https://fixture.invalid/ci-binaries"
            result = subprocess.run(
                ["bash", str(script)], capture_output=True, text=True, env=env
            )
            return result, output.read_text(encoding="utf-8"), installed.exists()

    def manifest(self, omitted: str | None = None) -> str:
        return "".join(
            f"{authority}={'a' * 40}\n"
            for authority in AUTHORITIES
            if authority != omitted
        )

    def test_complete_manifest_installs(self) -> None:
        result, _, installed = self.run_step(self.manifest())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(installed)

    def test_missing_authority_refuses_install(self) -> None:
        result, _, installed = self.run_step(self.manifest(omitted="engine"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("omits 'engine'", result.stdout)
        self.assertFalse(installed)

    def test_checksum_mismatch_refuses_install(self) -> None:
        result, _, installed = self.run_step(self.manifest(), corrupt=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(installed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
