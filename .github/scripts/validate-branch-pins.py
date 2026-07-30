#!/usr/bin/env python3
"""validate-branch-pins.py — [BRANCH-PIN-001] branch-pinned Institute dependencies.

Manifest-only text scan (Package.swift / Package@swift-*.swift at the repo
root; no build, no resolve; sub-second). Deliberately NOT `swift package
dump-package`: the JSON route needs a toolchain at or above every manifest's
tools-version floor, which is exactly the trap that produced #61's 81%
not-scanned. A text scan has no toolchain dependency and cannot silently
skip a target for environmental reasons.

Rule checked: [BRANCH-PIN-001] — a dependency declaration on an Institute-org
URL whose requirement is `branch:` (or the legacy `.branch(`) is a moving
target: a green over it proves nothing about any tagged state. Institute
manifests pin Institute dependencies to versions.

Exception (principal ruling, 2026-07-30, recorded at
swift-standards/swift-mailgun-standard#13): the Institute develops solely on
`main`, tags are heritage/vestigial and will not be cut, and untagged
Institute dependencies are tracked with `branch: "main"` per ecosystem
convention. A `branch: "main"` (or `.branch("main")`) pin on an
Institute-owned dependency therefore passes validation. Any other branch
name on an Institute-owned dependency still fires BRANCH-PIN-001; a branch
pin on a non-Institute dependency stays outside this rule's scope
regardless of branch name.

The Institute org list comes from the canonical read-orgs manifest
(.github/actions/read-orgs/orgs.yaml), not a second inline copy. Override
with --orgs-file when the script runs outside a full checkout (the swift-ci
fast-check copies the script, manifest, and baseline out before scanning).

Baseline: --baseline <file> names the burn-down ledger (lines
`owner/repo<TAB>dependency-url`, `#` comments; a missing file is an empty
baseline). A finding whose (repo, url) pair is baselined is emitted as
BRANCH-PIN-BASELINE (informational, never fails); every other finding is
BRANCH-PIN-001. The baseline is shrink-only; lint-validator-fixtures.yml
rejects growth.

Scanning shape: comments are stripped first (string-aware, nested block
comments handled), then each `.package(` call is captured to its matching
close paren, so multiline declarations are one window and commented-out
declarations are invisible — both covered by fixtures under
tests/fixtures/branch-pin-001/.

Output: TSV findings `repo<TAB>rule<TAB>message`.
Exit: 1 when any non-baselined BRANCH-PIN-001 finding fired, else 0
(>=2 signals a crash / usage error, per the harness convention).

Usage:
  validate-branch-pins.py <repo-name> <repo-root> [--orgs-file F] [--baseline F]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

RULE = "BRANCH-PIN-001"
RULE_BASELINE = "BRANCH-PIN-BASELINE"

RE_MANIFEST = re.compile(r"Package(@swift-[\d.]+)?\.swift")
RE_URL = re.compile(r'url:\s*"(?P<url>[^"]+)"')
RE_BRANCH_LABEL = re.compile(r'branch:\s*"(?P<name>[^"]*)"')
RE_BRANCH_LEGACY = re.compile(r'\.branch\(\s*"(?P<name>[^"]*)"\s*\)')


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def strip_comments(text: str) -> str:
    """Remove // line comments and (nested) /* */ block comments.

    String-aware: `//` inside a string literal (every https URL) is not a
    comment. Stripped spans are replaced with spaces so offsets inside the
    surviving code stay stable and tokens never fuse across a removal.
    """
    out = list(text)
    i, n = 0, len(text)
    in_string = False
    block_depth = 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if block_depth > 0:
            if c == "/" and nxt == "*":
                block_depth += 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if c == "*" and nxt == "/":
                block_depth -= 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if c != "\n":
                out[i] = " "
            i += 1
            continue
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if c == "/" and nxt == "*":
            block_depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            continue
        i += 1
    return "".join(out)


def package_calls(code: str) -> list[str]:
    """Return the text of each `.package(...)` call, close-paren matched.

    Operates on comment-stripped code; tracks string state so parens inside
    literals do not unbalance the window. An unterminated call runs to EOF —
    a malformed manifest is not this validator's finding to make.
    """
    calls: list[str] = []
    for m in re.finditer(r"\.package\s*\(", code):
        depth = 1
        i = m.end()
        in_string = False
        while i < len(code) and depth > 0:
            c = code[i]
            if in_string:
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    in_string = False
            elif c == '"':
                in_string = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        calls.append(code[m.start():i])
    return calls


def load_orgs(orgs_file: Path) -> set[str]:
    try:
        import yaml
    except ImportError:
        print("# error: PyYAML not installed", file=sys.stderr)
        sys.exit(2)
    records = yaml.safe_load(orgs_file.read_text(encoding="utf-8"))
    if not isinstance(records, list) or not records:
        print(f"# error: orgs manifest {orgs_file} is empty or malformed", file=sys.stderr)
        sys.exit(2)
    return {
        r["name"]
        for r in records
        if isinstance(r, dict) and r.get("name") and r.get("status") != "archived"
    }


def load_baseline(path: Path | None) -> set[tuple[str, str]]:
    if path is None or not path.is_file():
        return set()
    entries: set[tuple[str, str]] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) == 2:
            entries.add((parts[0], parts[1]))
    return entries


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("root")
    ap.add_argument("--orgs-file", default=None)
    ap.add_argument("--baseline", default=None)
    args = ap.parse_args()

    orgs_file = (
        Path(args.orgs_file)
        if args.orgs_file
        else Path(__file__).resolve().parent.parent / "actions" / "read-orgs" / "orgs.yaml"
    )
    orgs = load_orgs(orgs_file)
    baseline = load_baseline(Path(args.baseline) if args.baseline else None)
    root = Path(args.root)

    findings = 0
    for manifest in sorted(root.glob("Package*.swift")):
        if not RE_MANIFEST.fullmatch(manifest.name):
            continue
        try:
            code = strip_comments(manifest.read_text(errors="replace"))
        except OSError:
            continue
        for call in package_calls(code):
            url_m = RE_URL.search(call)
            if url_m is None:
                continue
            url = url_m.group("url")
            gh = re.match(r"https://github\.com/([^/]+)/[^/]+?(?:\.git)?$", url)
            if gh is None or gh.group(1) not in orgs:
                continue
            branch_m = RE_BRANCH_LABEL.search(call) or RE_BRANCH_LEGACY.search(call)
            if branch_m is None:
                continue
            branch = branch_m.group("name")
            if branch == "main":
                # Ruled convention: an untagged Institute dependency pinned
                # to "main" is not a moving-target violation.
                continue
            if (args.repo, url) in baseline:
                emit(args.repo, RULE_BASELINE,
                     f"{manifest.name}: `{url}` pinned to branch \"{branch}\" — baselined; burn-down owned by the package/release record")
            else:
                emit(args.repo, RULE,
                     f"{manifest.name}: `{url}` pinned to branch \"{branch}\" — Institute dependencies pin to versions; a branch is a moving target")
                findings += 1
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
