#!/usr/bin/env python3
"""validate-docc-structure.py — verify DocC catalog layout per documentation skill.

Wave 2b finalization (2026-05-10) — companion to validate-docc-structure.yml.
Validates an already-cloned repo's `Sources/<Module>/<Module>.docc/` layout.

Rules checked (v1):
  [DOC-020] Every Swift module MUST have a `.docc/` catalog inside its `Sources/<Module>/`.
            (Umbrella exception per [DOC-019a] is honored: a target whose only source is
             `exports.swift` is considered an umbrella and not required to have its own .docc.)
  [DOC-021] Every `.docc/` MUST contain a root page named `<Module>.md` (or `<Module name>.md`
            using the human-readable form with spaces).
  [DOC-026] `.docc/` catalogs MUST be flat — only `Resources/` is allowed as a subdir.
  [DOC-070] Catalogs containing `*.tutorial` files MUST also contain a `Tutorials.tutorial` TOC.
  [DOC-071] Tutorial `@Code(file:...)` references MUST resolve to `.docc/Resources/<file>`.
  [DOC-101] Per-symbol / topical articles MUST NOT carry `## Research`, `## Experiments`,
            or `Status: DECISION` markers (those belong in landing pages).
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

DOC_RESEARCH_FORBIDDEN = re.compile(
    r"^##\s+Research\b|^##\s+Experiments\b|^Status:\s*DECISION\b",
    re.MULTILINE,
)
TUTORIAL_CODE_REF = re.compile(r"@Code\s*\(\s*(?:name:[^,]*,\s*)?file:\s*\"([^\"]+)\"")


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def find_swift_targets(sources_dir: Path) -> list[Path]:
    """List directory entries under Sources/ that look like Swift module dirs.

    A directory is treated as a module dir if it contains at least one `.swift`
    file and its name is not a reserved subfolder.
    """
    if not sources_dir.is_dir():
        return []
    out: list[Path] = []
    for entry in sources_dir.iterdir():
        if not entry.is_dir():
            continue
        # Skip well-known non-target subfolders.
        if entry.name.startswith(".") or entry.name in {"include", "Resources"}:
            continue
        try:
            has_swift = any(entry.glob("*.swift")) or any(entry.glob("**/*.swift"))
        except Exception:
            has_swift = False
        if has_swift:
            out.append(entry)
    return out


def is_umbrella_target(module_dir: Path) -> bool:
    """True iff the only source file is exports.swift (umbrella per [DOC-019a])."""
    swift_files = list(module_dir.glob("*.swift"))
    return len(swift_files) == 1 and swift_files[0].name == "exports.swift"


def validate_docc(repo: str, repo_root: Path) -> int:
    findings = 0
    sources = repo_root / "Sources"
    if not sources.is_dir():
        return 0  # repo has no Swift code; nothing to validate
    for module_dir in find_swift_targets(sources):
        module_name = module_dir.name
        if is_umbrella_target(module_dir):
            continue  # [DOC-019a] umbrella exception
        # [DOC-020] .docc presence
        docc_path = module_dir / f"{module_name}.docc"
        if not docc_path.is_dir():
            emit(repo, "DOC-020",
                 f"module {module_name!r}: missing .docc/ catalog at {docc_path.relative_to(repo_root)}")
            findings += 1
            continue
        # [DOC-021] root page presence
        root_md_candidates = [docc_path / f"{module_name}.md"]
        # Allow human-readable variant: "Foo Bar.md" if module is "Foo_Bar"
        readable = module_name.replace("_", " ")
        if readable != module_name:
            root_md_candidates.append(docc_path / f"{readable}.md")
        if not any(c.is_file() for c in root_md_candidates):
            emit(repo, "DOC-021",
                 f"module {module_name!r}: .docc/ missing root page (expected one of "
                 f"{[c.name for c in root_md_candidates]!r})")
            findings += 1
        # [DOC-026] flat structure (only Resources/ subdir allowed)
        for sub in docc_path.iterdir():
            if sub.is_dir() and sub.name != "Resources":
                emit(repo, "DOC-026",
                     f"module {module_name!r}: .docc/ contains forbidden subdirectory "
                     f"{sub.name!r}; only Resources/ is allowed")
                findings += 1
        # [DOC-070] / [DOC-071] tutorials
        tutorial_files = list(docc_path.glob("*.tutorial"))
        if tutorial_files:
            has_toc = any(t.name == "Tutorials.tutorial" for t in tutorial_files)
            if not has_toc:
                emit(repo, "DOC-070",
                     f"module {module_name!r}: .docc/ has *.tutorial file(s) "
                     f"({[t.name for t in tutorial_files][:3]!r}) but no Tutorials.tutorial TOC")
                findings += 1
            for tutorial in tutorial_files:
                try:
                    content = tutorial.read_text()
                except Exception:
                    continue
                for match in TUTORIAL_CODE_REF.finditer(content):
                    code_file = match.group(1)
                    candidate = docc_path / "Resources" / code_file
                    candidate_alt = docc_path / code_file
                    if not (candidate.is_file() or candidate_alt.is_file()):
                        emit(repo, "DOC-071",
                             f"module {module_name!r}: tutorial {tutorial.name!r} "
                             f"references @Code(file:{code_file!r}) which is not at "
                             f".docc/Resources/{code_file}")
                        findings += 1
        # [DOC-101] per-symbol/topical articles must not carry Research/Experiments/DECISION
        for md in docc_path.glob("*.md"):
            if md.name in {f"{module_name}.md", f"{readable}.md"}:
                continue  # root page (landing) is allowed to have those sections
            try:
                content = md.read_text()
            except Exception:
                continue
            if DOC_RESEARCH_FORBIDDEN.search(content):
                emit(repo, "DOC-101",
                     f"module {module_name!r}: per-symbol article {md.name!r} carries "
                     f"## Research / ## Experiments / Status: DECISION marker (those belong "
                     f"in landing pages)")
                findings += 1
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-docc-structure.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_docc(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
