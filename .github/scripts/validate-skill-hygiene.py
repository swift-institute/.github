#!/usr/bin/env python3
"""validate-skill-hygiene.py — publication hygiene for a public skill corpus.

Companion to validate-skill-hygiene.yml. Checks mechanical, objective facts
about skill files as published artifacts. It deliberately checks NOTHING about
the writing itself: no length ceiling, no line cap, no required sections, no
opinion about tone, structure, or phrasing. Skills are lightweight guides and
are expected to carry judgment rather than prescription; the only things worth
gating in CI are the facts that decide whether a skill loads at all and whether
it is safe to have published.

Findings (TSV column 2), named for the behaviour rather than an internal
requirement ID:

  skill-corpus-empty      No SKILL.md found anywhere in the target repo. Fails
                          closed: a corpus that silently moved or vanished must
                          not read as a clean scan.
  skill-frontmatter       SKILL.md is not valid UTF-8, has no frontmatter block,
                          has an unterminated block, or the block does not parse
                          as a YAML mapping. Such a skill cannot be loaded.
  skill-identity          `name` or `description` is missing or empty, or `name`
                          does not equal the containing directory name. The
                          description is the routing interface; an absent one
                          makes the skill unreachable. Existence only — this
                          check never inspects what the description says.
  skill-links             A relative markdown link does not resolve to a file in
                          the repo. Progressive disclosure means companion
                          documents carry real content; a pointer that 404s
                          silently removes what it was meant to disclose.
  skill-machine-path      A maintainer home-directory or machine-local absolute
                          path appears in a public file.
  skill-internal-rule-id  An internal rule ID is cited in published prose.

Scope:
  skill-frontmatter / skill-identity   every <dir>/SKILL.md
  the remaining three                  every .md file in the repo

Layout-agnostic: skills are discovered by locating SKILL.md at any depth, so a
repo whose skills sit at the root and one that nests them under Skills/ are both
handled without a configured path input.

Exit convention: main() is invoked WITHOUT sys.exit(), so the process exits 0
even when findings exist. Findings signal through the TSV on stdout. A nonzero
exit therefore means the validator itself crashed, which validate-base.yml
reports as validator-crashed rather than as a clean scan.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

from validate_lib import emit, require_yaml

yaml = require_yaml()

# Maintainer home directories. `/Users/runner` and `/home/runner` are the shared
# GitHub-hosted runner paths -- generic infrastructure, not anyone's machine --
# so they are excluded rather than reported.
MACHINE_PATH = re.compile(
    r"(?<![A-Za-z0-9_])(?:/Users/|/home/)(?!runner(?:[/\s]|$))[A-Za-z0-9._-]+/"
    r"|[A-Za-z]:\\Users\\[A-Za-z0-9._-]+\\"
)

# Internal rule-ID citations. The curated first segment is what separates an
# internal ID from an external standards citation such as [RFC-7231] or
# [ISO-8601], which are legitimate in public prose. Mirrors the vocabulary
# already used by validate-readme.py for the same distinction.
INTERNAL_RULE_ID = re.compile(
    r"\[(?:README|MEM|DOC|API|MOD|PRIM|IMPL|PLAT|ARCH|TEST|SWIFT-TEST|BENCH|"
    r"INST-TEST|PATTERN|GH-REPO|SKILL|RES|EXP|BLOG|REFL|AUDIT|CONV|IDX|LEG|"
    r"NL-WET|RL|COPY|SEM|INFRA|CI|SOC|SUPER|HANDOFF|COLLAB|GIT|FREVIEW|SAVE|"
    r"RELEASE|META|PROMOTE|VERIFICATION|SKILL-CREATE|SKILL-LIFE)"
    r"(?:-[A-Z][A-Z0-9]*)*-[0-9]+[a-z]?\]"
)

# Inline markdown links: [text](target). Reference-style links are not covered;
# the corpus uses none, and a check that silently half-covers a syntax is worse
# than one whose scope is stated.
MD_LINK = re.compile(r"\[[^\]]*\]\(\s*([^)\s]+)(?:\s+[\"'][^\"']*[\"'])?\s*\)")

SKIP_LINK_PREFIXES = ("http://", "https://", "mailto:", "tel:", "#", "<")


def iter_markdown(repo_root: Path):
    """Yield every .md file in the repo, skipping VCS internals."""
    for path in sorted(repo_root.rglob("*.md")):
        if any(part == ".git" for part in path.relative_to(repo_root).parts):
            continue
        yield path


def read_text(path: Path) -> str | None:
    """Return decoded text, or None if the file is not valid UTF-8."""
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def split_frontmatter(text: str) -> str | None:
    """Return the raw frontmatter block, or None if absent/unterminated."""
    if not text.startswith("---"):
        return None
    rest = text[3:]
    if not rest.startswith("\n") and not rest.startswith("\r\n"):
        return None
    end = re.search(r"^---\s*$", rest, re.MULTILINE)
    if end is None:
        return None
    return rest[: end.start()]


def check_skill_file(repo: str, skill_md: Path, repo_root: Path) -> int:
    """Frontmatter and identity checks for one SKILL.md."""
    rel = skill_md.relative_to(repo_root)
    findings = 0

    text = read_text(skill_md)
    if text is None:
        emit(repo, "skill-frontmatter", f"{rel}: not valid UTF-8; the file cannot be loaded")
        return 1

    block = split_frontmatter(text)
    if block is None:
        emit(
            repo,
            "skill-frontmatter",
            f"{rel}: no terminated YAML frontmatter block "
            f"(expected a leading '---' line and a closing '---' line)",
        )
        return 1

    try:
        data = yaml.safe_load(block)
    except Exception as exc:  # noqa: BLE001 -- any parser error is one finding
        detail = str(exc).replace("\n", " ")
        emit(repo, "skill-frontmatter", f"{rel}: frontmatter does not parse as YAML: {detail}")
        return 1

    if not isinstance(data, dict):
        emit(repo, "skill-frontmatter", f"{rel}: frontmatter is not a YAML mapping")
        return 1

    for field in ("name", "description"):
        value = data.get(field)
        if value is None:
            emit(repo, "skill-identity", f"{rel}: frontmatter has no `{field}` field")
            findings += 1
        elif not isinstance(value, str) or not value.strip():
            emit(repo, "skill-identity", f"{rel}: `{field}` is empty")
            findings += 1

    name = data.get("name")
    expected = skill_md.parent.name
    if isinstance(name, str) and name.strip() and name.strip() != expected:
        emit(
            repo,
            "skill-identity",
            f"{rel}: `name` is '{name.strip()}' but the directory is '{expected}'; "
            f"they must match so the skill projects unambiguously",
        )
        findings += 1

    return findings


def check_links(repo: str, path: Path, text: str, repo_root: Path) -> int:
    """Every relative markdown link must resolve to a file in the repo."""
    rel = path.relative_to(repo_root)
    findings = 0
    for target in MD_LINK.findall(text):
        if target.startswith(SKIP_LINK_PREFIXES) or "://" in target:
            continue
        cleaned = unquote(target.split("#", 1)[0]).strip()
        if not cleaned:
            continue
        if cleaned.startswith("/"):
            resolved = repo_root / cleaned.lstrip("/")
        else:
            resolved = path.parent / cleaned
        if not resolved.exists():
            emit(
                repo,
                "skill-links",
                f"{rel}: link target '{target}' does not resolve to a file in the repository",
            )
            findings += 1
    return findings


def check_prose(repo: str, path: Path, text: str, repo_root: Path) -> int:
    """Machine-path and internal-rule-ID checks for one markdown file."""
    rel = path.relative_to(repo_root)
    findings = 0
    for lineno, line in enumerate(text.splitlines(), start=1):
        for match in MACHINE_PATH.finditer(line):
            emit(
                repo,
                "skill-machine-path",
                f"{rel}:{lineno}: machine-local path '{match.group(0)}' in a public file",
            )
            findings += 1
        for match in INTERNAL_RULE_ID.finditer(line):
            emit(
                repo,
                "skill-internal-rule-id",
                f"{rel}:{lineno}: internal rule ID '{match.group(0)}' in published prose; "
                f"name the behaviour instead",
            )
            findings += 1
    return findings


def main(repo: str, repo_root_arg: str) -> int:
    repo_root = Path(repo_root_arg)
    findings = 0

    skill_files = [
        p for p in sorted(repo_root.rglob("SKILL.md"))
        if ".git" not in p.relative_to(repo_root).parts
    ]

    if not skill_files:
        # Fail closed. If the corpus moved or the clone is wrong, a silent zero
        # would be indistinguishable from a clean scan.
        emit(
            repo,
            "skill-corpus-empty",
            "no SKILL.md found anywhere in the repository; "
            "the scan covered nothing and cannot be read as a pass",
        )
        return 1

    for skill_md in skill_files:
        findings += check_skill_file(repo, skill_md, repo_root)

    for md in iter_markdown(repo_root):
        text = read_text(md)
        if text is None:
            # SKILL.md files already reported above; report any other file once.
            if md.name != "SKILL.md":
                rel = md.relative_to(repo_root)
                emit(repo, "skill-frontmatter", f"{rel}: not valid UTF-8")
                findings += 1
            continue
        findings += check_links(repo, md, text, repo_root)
        findings += check_prose(repo, md, text, repo_root)

    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-skill-hygiene.py <owner/name> <repo_root>")
    # Called without sys.exit(): findings signal via TSV, exit stays 0 so that a
    # nonzero code unambiguously means the validator crashed.
    main(sys.argv[1], sys.argv[2])
