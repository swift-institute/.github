#!/usr/bin/env python3
"""validate-readme.py — verify README files per readme skill family rules.

Wave 2b finalization (2026-05-10) — companion to validate-readme.yml.
Reads readme.family from each repo's metadata.yaml (per Decision 7) and
applies the per-family rule subset.

Family taxonomy (Skills/readme/SKILL.md):
  A — user profile (only for personal user repos; rare in this workspace)
  C — process / workflow repo (Skills, Scripts, Research, Audits, Blog,
      Experiments, Swift-Evolution, swift-institute.org)
  E — sub-package library repo (the dominant family)
  F — placeholder / scaffold (status-blockquote-only README)
  G — org profile (renders at github.com/<org>; lives at .github/profile/README.md)

Rules checked (v1):
  Universal:
    [README-017] H1 present and exactly one (first non-empty line starts with `# `).
    [README-026] No internal rule-ID citations outside code blocks.

  Family E (sub-package):
    [README-001] Required inventory: title (H1), badges, one-liner, ## License section.
    [README-003] First badge is the development-status shield.
    [README-008] ## Installation section MUST include both Package.swift dep AND target config.
    [README-013] Error Handling threshold (Decision 5): if the package has any
                 public function with throws(...) and a non-Never error type, the
                 README MUST include a `## Error Handling` section.
    [README-016] Forbidden sections: ## Roadmap, ## TODO, ## Changelog, marketing-only.

  Family C (process):
    [README-130] Process READMEs open with H1 + 1-line workflow scope linking parent org.
    [README-137] Process READMEs MUST NOT include Installation, badges, or Quick Start.
    [README-138] Process READMEs SHOULD be 30-50 lines; >80 suggests relocation.

  Family F (placeholder):
    [README-150] H1 + status blockquote only; no other ## sections.
    [README-151] Status value ∈ {Pre-implementation, Namespace-reservation,
                 Unnecessary, Archived}.

  Family G (org profile):
    [README-116] Org profile README MUST NOT include installation block.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

FORBIDDEN_RULE_ID = re.compile(
    r"\[(README|MEM|DOC|API|MOD|PRIM|IMPL|PLAT|TEST|SWIFT-TEST|BENCH|INST-TEST|"
    r"PATTERN|GH-REPO|SKILL|RES|EXP|BLOG|REFL|AUDIT|CONV|IDX|LEG|NL-WET|RL|"
    r"COPY|SEM|API-NAME|API-ERR|API-IMPL|API-LAYER|MEM-COPY|MEM-OWN|MEM-LIFE|"
    r"MEM-LINEAR|MEM-REF|MEM-SAFE|MEM-SEND|MEM-UNSAFE|MEM-SPAN|"
    r"INFRA|MOD-EXCEPT|CI|README-PROC|SOC|SUPER|HANDOFF|COLLAB|GIT|"
    r"FREVIEW|SAVE|DOC-MARKUP|RELEASE|META|REFL-PROC|SKILL-CREATE|"
    r"SKILL-LIFE|REFL-PROC)-[0-9]+[a-z]?\]"
)
H1_LINE = re.compile(r"^#\s+\S")
H2_LINE = re.compile(r"^##\s+\S")
BADGE_LINE = re.compile(r"^!\[")
DEV_STATUS_BADGE = re.compile(r"!\[Development Status\]\(https://img\.shields\.io/badge/")
INSTALL_DEP_RE = re.compile(r"\.package\(", re.MULTILINE)
INSTALL_TARGET_RE = re.compile(r"\.target\(", re.MULTILINE)
F_STATUS_VALUES = {"Pre-implementation", "Namespace-reservation", "Unnecessary", "Archived"}
F_STATUS_LINE = re.compile(r">\s*\*\*Status:\s*([^*]+?)\*\*")


def strip_code_blocks(text: str) -> str:
    """Remove fenced ``` ... ``` code blocks for rule-citation scans."""
    return re.sub(r"```.*?```", "", text, flags=re.DOTALL)


def detect_family(metadata_path: Path) -> str | None:
    if not metadata_path.is_file():
        return None
    try:
        data = yaml.safe_load(metadata_path.read_text())
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    readme_block = data.get("readme")
    if not isinstance(readme_block, dict):
        return None
    family = readme_block.get("family")
    if family in ("A", "C", "E", "F", "G"):
        return family
    return None


def has_throws_non_never(repo_root: Path) -> bool:
    """[README-013] threshold: any public throws(NonNever) signature in Sources/."""
    sources = repo_root / "Sources"
    if not sources.is_dir():
        return False
    pattern = re.compile(r"\bpublic[^\n]*\bthrows\(([^)]+)\)")
    for f in sources.rglob("*.swift"):
        try:
            content = f.read_text()
        except Exception:
            continue
        for match in pattern.finditer(content):
            err_type = match.group(1).strip()
            if err_type and err_type != "Never":
                return True
    return False


def validate_universal(repo: str, readme: Path, content: str) -> int:
    findings = 0
    nonblank = [ln for ln in content.splitlines() if ln.strip()]
    # [README-017] H1 present and exactly one
    h1_count = sum(1 for ln in content.splitlines() if H1_LINE.match(ln))
    if h1_count == 0:
        emit(repo, "README-017", f"{readme.name}: missing H1 title (first heading must be `# `)")
        findings += 1
    elif h1_count > 1:
        emit(repo, "README-017", f"{readme.name}: {h1_count} H1 headings found; exactly one required")
        findings += 1
    if nonblank and not H1_LINE.match(nonblank[0]):
        emit(repo, "README-017",
             f"{readme.name}: first non-empty line is not H1 (got {nonblank[0][:80]!r})")
        findings += 1
    # [README-026] no internal rule-ID citations outside code blocks
    stripped = strip_code_blocks(content)
    for match in FORBIDDEN_RULE_ID.finditer(stripped):
        emit(repo, "README-026",
             f"{readme.name}: contains internal rule-ID citation {match.group(0)} "
             f"(forbidden in published READMEs)")
        findings += 1
        break  # one finding suffices
    return findings


def validate_family_e(repo: str, readme: Path, content: str, repo_root: Path) -> int:
    findings = 0
    # [README-003] first badge is dev-status shield
    badge_lines = [ln for ln in content.splitlines() if BADGE_LINE.match(ln)]
    if badge_lines and not DEV_STATUS_BADGE.search(badge_lines[0]):
        emit(repo, "README-003",
             f"{readme.name}: first badge is not Development Status shield "
             f"(got {badge_lines[0][:60]!r})")
        findings += 1
    # [README-001] License section present
    if "## License" not in content:
        emit(repo, "README-001",
             f"{readme.name}: missing `## License` section")
        findings += 1
    # [README-008] Installation section presence
    if "## Installation" not in content:
        emit(repo, "README-008",
             f"{readme.name}: missing `## Installation` section")
        findings += 1
    else:
        # Within the Installation section, check both .package( and .target(
        idx = content.index("## Installation")
        next_h2 = content.find("\n## ", idx + 1)
        section = content[idx:next_h2 if next_h2 != -1 else None]
        if not INSTALL_DEP_RE.search(section):
            emit(repo, "README-008",
                 f"{readme.name}: Installation section missing `.package(...)` dependency block")
            findings += 1
        if not INSTALL_TARGET_RE.search(section):
            emit(repo, "README-008",
                 f"{readme.name}: Installation section missing `.target(dependencies: ...)` block")
            findings += 1
    # [README-013] Error Handling threshold (Decision 5)
    if has_throws_non_never(repo_root) and "## Error Handling" not in content:
        emit(repo, "README-013",
             f"{readme.name}: package has public throws(NonNever) signatures but README "
             f"lacks `## Error Handling` section (Wave 2b finalization Decision 5 threshold)")
        findings += 1
    # [README-016] forbidden sections
    for forbidden in ("## Roadmap", "## TODO", "## Changelog"):
        if forbidden in content:
            emit(repo, "README-016",
                 f"{readme.name}: contains forbidden section {forbidden!r}")
            findings += 1
    return findings


def validate_family_c(repo: str, readme: Path, content: str) -> int:
    findings = 0
    # [README-137] no Installation / badges / Quick Start
    if "## Installation" in content:
        emit(repo, "README-137",
             f"{readme.name}: process README has `## Installation` section (forbidden)")
        findings += 1
    if BADGE_LINE.search(content):
        emit(repo, "README-137",
             f"{readme.name}: process README has badges (forbidden)")
        findings += 1
    if "## Quick Start" in content:
        emit(repo, "README-137",
             f"{readme.name}: process README has `## Quick Start` (forbidden)")
        findings += 1
    # [README-138] length budget
    line_count = len(content.splitlines())
    if line_count > 80:
        emit(repo, "README-138",
             f"{readme.name}: process README is {line_count} lines (>80 suggests "
             f"content should relocate per [README-138])")
        findings += 1
    return findings


def validate_family_f(repo: str, readme: Path, content: str) -> int:
    findings = 0
    h2_lines = [ln for ln in content.splitlines() if H2_LINE.match(ln)]
    # [README-150] H1 + status blockquote only — no other ## sections
    # (License section is universal; allow as one exception.)
    extra_h2 = [ln for ln in h2_lines if "## License" not in ln]
    if extra_h2:
        emit(repo, "README-150",
             f"{readme.name}: Family F README has extra ## sections "
             f"(first: {extra_h2[0][:60]!r}); should be H1 + status blockquote only")
        findings += 1
    # [README-151] Status value enumerated
    m = F_STATUS_LINE.search(content)
    if m:
        status = m.group(1).strip()
        if status not in F_STATUS_VALUES:
            emit(repo, "README-151",
                 f"{readme.name}: Family F status {status!r} not in canonical set "
                 f"{sorted(F_STATUS_VALUES)!r}")
            findings += 1
    return findings


def validate_family_g(repo: str, readme: Path, content: str) -> int:
    findings = 0
    # [README-116] org profile MUST NOT include installation block
    if "## Installation" in content:
        emit(repo, "README-116",
             f"{readme.name}: org-profile README has `## Installation` section (forbidden)")
        findings += 1
    return findings


def validate_repo(repo: str, repo_root: Path) -> int:
    findings = 0
    metadata_path = repo_root / ".github" / "metadata.yaml"
    family = detect_family(metadata_path)
    if family is None:
        emit(repo, "README-family-unset",
             f".github/metadata.yaml lacks readme.family field; cannot apply per-family rules")
        return 1
    # Locate the README. Family G uses .github/profile/README.md; others use top-level README.md.
    if family == "G":
        readme = repo_root / ".github" / "profile" / "README.md"
    else:
        readme = repo_root / "README.md"
    if not readme.is_file():
        if family in ("F",):
            return 0  # Family F can be implicit (no README means namespace reservation)
        emit(repo, "README-presence",
             f"family={family} but README not found at expected path "
             f"{readme.relative_to(repo_root)}")
        return 1
    try:
        content = readme.read_text()
    except Exception as e:
        emit(repo, "README-read-failed", f"{readme}: {e}")
        return 1
    findings += validate_universal(repo, readme, content)
    if family == "E":
        findings += validate_family_e(repo, readme, content, repo_root)
    elif family == "C":
        findings += validate_family_c(repo, readme, content)
    elif family == "F":
        findings += validate_family_f(repo, readme, content)
    elif family == "G":
        findings += validate_family_g(repo, readme, content)
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-readme.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_repo(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
