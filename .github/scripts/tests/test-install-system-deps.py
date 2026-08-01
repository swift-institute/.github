#!/usr/bin/env python3
"""Positive control for nested-test system-dependency derivation.

The installer must inspect every package graph that universal CI can compile.
In particular, a sanctioned `Tests/Package.swift` graph may declare a
transitive C shim while the root graph declares no linked libraries. This
extracts the shipped composite-action script and runs it with hermetic Swift
and apt shims: the nested graph supplies `.linkedLibrary("uuid")`, and the
control proves that `uuid-dev` reaches the installer.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

ACTION = Path(__file__).parents[2] / "actions" / "install-system-deps" / "action.yml"
STEP_NAME = "Derive + install system dev-packages from .linkedLibrary"


def extract_step() -> str:
    document = yaml.safe_load(ACTION.read_text(encoding="utf-8"))
    for step in document.get("runs", {}).get("steps", []):
        if step.get("name") == STEP_NAME:
            body = step.get("run")
            if body:
                return body
            raise SystemExit(f"{ACTION}: step '{STEP_NAME}' has no run body")
    raise SystemExit(f"{ACTION}: no step named '{STEP_NAME}'")


class NestedTestGraphTests(unittest.TestCase):
    script = extract_step()

    def test_nested_graph_installs_uuid_dev(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / "Package.swift").write_text("// root graph\n", encoding="utf-8")
            nested = root / "Tests"
            nested.mkdir()
            (nested / "Package.swift").write_text("// nested graph\n", encoding="utf-8")
            dependency = nested / ".build" / "checkouts" / "swift-linux-standard"
            dependency.mkdir(parents=True)
            (dependency / "Package.swift").write_text(
                '.linkedLibrary("uuid", .when(platforms: [.linux]))\n',
                encoding="utf-8",
            )

            shims = root / "bin"
            shims.mkdir()
            apt_log = root / "apt.log"
            (shims / "swift").write_text(
                "#!/usr/bin/env bash\n"
                "test \"$1 $2\" = 'package resolve'\n",
                encoding="utf-8",
            )
            (shims / "apt-get").write_text(
                "#!/usr/bin/env bash\n"
                f'printf "%s\\n" "$*" >> "{apt_log}"\n',
                encoding="utf-8",
            )
            for shim in shims.iterdir():
                shim.chmod(0o755)

            script = root / "step.sh"
            script.write_text(self.script, encoding="utf-8")
            environment = dict(os.environ)
            environment["PATH"] = f"{shims}:{environment['PATH']}"
            result = subprocess.run(
                ["bash", str(script)],
                cwd=root,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Installing system dev-packages: uuid-dev", result.stdout)
            self.assertIn("install -qq -y uuid-dev", apt_log.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
