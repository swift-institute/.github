#!/usr/bin/env python3
"""validate-gitignore.py — verify the canonical package `.gitignore`.

Companion to validate-gitignore.yml. Canon lives at `canon/gitignore-package.txt`
in swift-institute/.github.

The canonical package `.gitignore` is a WHITELIST: `/*` denies every top-level
entry and the `!/...` lines re-include the ones that carry real work, plus
`**/.*/` denying tool-state dot-directories at every depth. That posture is why
`.swift-lint/` — 3,384 files written into the worktree by swift-linter — was
already ignored in every repository carrying the canonical file, without anyone
having named it.

Rules checked:
  [GH-IGNORE-001] The CANONICAL section of a package's `.gitignore` MUST match
                  `canon/gitignore-package.txt` byte-for-byte, and the file MUST
                  have such a section. Content after `END CANONICAL` is the
                  package's own and is not compared.

  [GH-IGNORE-002] The whitelist MUST NOT deny any path that carries real work.
                  A fixed probe set of legitimate paths is run through
                  `git check-ignore`; any probe that comes back ignored is a
                  violation.

Why 002 exists, and why it is the half of this gate that matters. A whitelist
inverts the failure mode. Before it, junk crept in and `git status` showed you.
After it, anything not explicitly allowed is untracked and `git status` says
NOTHING — on 2026-07-29 a research paper in this ecosystem existed only as an
untracked directory, one `git clean` from being lost. A validator that asks only
"is junk denied?" would have reported that repository clean. This one asks "is
real work still tracked?" as well, which is what makes the work-loss failure
mode loud rather than silent. If a future canon edit narrows the whitelist, 002
fires before anyone loses a file. Do not weaken it to a warning, and when the
whitelist gains a directory, add a probe for it here in the same change.

Both checks evaluate the `.gitignore` the way git will: the file is copied into
a throwaway `git init` tree with the probe paths materialized, and `git
check-ignore` decides. Reading the patterns and reasoning about them is how the
premise of this whole change came to be wrong in the first place — the absence
of a `.swift-lint` deny-line was read as the absence of denial, when the
whitelist was denying it all along.

Usage: validate-gitignore.py <repo> <root> [--canon <path>]
Exit:  0 clean · 1 findings emitted · 2 invocation error.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

CANONICAL_END = "# ========== END CANONICAL =========="

# Paths that carry real work. Every one of these MUST survive the whitelist.
# Kept as (path, is_directory) so directory-only patterns like `**/.*/` are
# exercised the way git evaluates them — a pattern with a trailing slash never
# matches a path git does not know to be a directory.
WORK_PROBES: list[tuple[str, bool]] = [
    ("Sources/Core/Type.swift", False),
    ("Sources/Core/Type.docc/Article.md", False),
    ("Sources/Core/Type.docc/asset.png", False),
    ("Tests/Core Tests/Type Tests.swift", False),
    ("Tests/Core Tests/Fixtures/case.json", False),
    ("Benchmarks/bench/main.swift", False),
    ("Research/paper.md", False),
    ("Experiments/probe/main.swift", False),
    ("Package.swift", False),
    ("Lint.swift", False),
    ("README.md", False),
    ("LICENSE.md", False),
    (".github/workflows/ci.yml", False),
    (".spi.yml", False),
    (".gitignore", False),
]

# Paths that MUST be denied. Not a rule of its own — a positive control on the
# probe harness. If these come back tracked, `git check-ignore` is not being
# reached and every 002 pass in the run is vacuous, which is exactly the shape
# of green this ecosystem has been burned by.
JUNK_PROBES: list[tuple[str, bool]] = [
    (".swift-lint/eval/Package.swift", False),
    ("Sources/.swift-lint/manifest.json", False),
    (".build/debug/thing.o", False),
]


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def canonical_section(text: str) -> str | None:
    """The file up to and including the END CANONICAL marker, or None."""
    index = text.find(CANONICAL_END)
    if index < 0:
        return None
    return text[: index + len(CANONICAL_END)] + "\n"


def check_ignored(gitignore: str, probes: list[tuple[str, bool]]) -> dict[str, bool]:
    """Ask git, in a throwaway tree, which probes `gitignore` ignores."""
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        for relative, is_directory in probes:
            target = root / relative
            if is_directory:
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("", encoding="utf-8")
        # LAST, and deliberately so: `.gitignore` is itself a probe (the file
        # must not ignore itself), and materializing probes as empty files would
        # otherwise truncate the very file under test — every verdict in the run
        # then reflects an empty ignore file, so all junk reads as tracked and
        # all work reads as kept. The JUNK_PROBES control caught exactly this.
        (root / ".gitignore").write_text(gitignore, encoding="utf-8")
        subprocess.run(
            ["git", "init", "-q", "."], cwd=root, check=True, capture_output=True
        )
        verdicts: dict[str, bool] = {}
        for relative, _ in probes:
            completed = subprocess.run(
                ["git", "check-ignore", "-q", "--", relative],
                cwd=root,
                capture_output=True,
            )
            # 0 = ignored, 1 = not ignored, >1 = git itself failed.
            if completed.returncode > 1:
                raise RuntimeError(
                    f"git check-ignore failed on {relative}: "
                    f"{completed.stderr.decode('utf-8', 'replace').strip()}"
                )
            verdicts[relative] = completed.returncode == 0
        return verdicts


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])

    canon_path = Path(__file__).resolve().parents[2] / "canon" / "gitignore-package.txt"
    if "--canon" in argv:
        canon_path = Path(argv[argv.index("--canon") + 1])
    if not canon_path.is_file():
        print(f"canon not found: {canon_path}", file=sys.stderr)
        return 2
    canon = canon_path.read_text(encoding="utf-8")
    canon_section = canonical_section(canon)
    if canon_section is None:
        print(f"canon has no {CANONICAL_END} marker: {canon_path}", file=sys.stderr)
        return 2

    # Packages only. A repo with no manifest is not what this canon describes.
    if not (root / "Package.swift").is_file():
        return 0

    findings = 0
    path = root / ".gitignore"

    if not path.is_file():
        emit(repo, "GH-IGNORE-001", "no .gitignore; the canonical whitelist is absent")
        return 1

    text = path.read_text(encoding="utf-8")
    section = canonical_section(text)
    if section is None:
        emit(
            repo,
            "GH-IGNORE-001",
            "no CANONICAL section; file predates the canonical whitelist",
        )
        findings += 1
    elif section != canon_section:
        emit(
            repo,
            "GH-IGNORE-001",
            "CANONICAL section diverges from canon/gitignore-package.txt",
        )
        findings += 1

    # 002 evaluates the repo's ACTUAL file, canonical or not — a divergent file
    # that loses real work should say so on its own terms, not only via 001.
    try:
        verdicts = check_ignored(text, WORK_PROBES + JUNK_PROBES)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        emit(repo, "GH-IGNORE-002", f"probe harness failed: {error}")
        return 1

    denied = [relative for relative, _ in WORK_PROBES if verdicts[relative]]
    for relative in denied:
        emit(
            repo,
            "GH-IGNORE-002",
            f"whitelist denies real work: `{relative}` would be silently untracked",
        )
        findings += 1

    tracked_junk = [relative for relative, _ in JUNK_PROBES if not verdicts[relative]]
    if tracked_junk:
        # The control failed. Report it as a finding rather than passing: a
        # harness that cannot detect denial makes every clean 002 above vacuous.
        emit(
            repo,
            "GH-IGNORE-002",
            "probe control failed — tool state not denied ("
            + ", ".join(f"`{relative}`" for relative in tracked_junk)
            + "); this run's whitelist verdicts are not evidence",
        )
        findings += 1

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
