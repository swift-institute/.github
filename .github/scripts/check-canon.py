#!/usr/bin/env python3
"""check-canon.py — canon guard engine for the skill rulebook (markdown corpus).

The rulebook checks itself: these five checks read the markdown skill corpus
(NOT Swift source — swift-linter owns that layer) and verify the canon's
internal referential integrity. Engine behind check-canon.sh; see that
wrapper for family-consistent CLI, roots, and exit-code conventions.

Checks (per HANDOFF-mechanization-arc W0):
  1. citations      — every [ID] cite resolves to a definition in one of the
                      THREE sanctioned forms: heading `### [ID]` (level 2+ per
                      [AUDIT-028]b), table-row `| [ID] |` under a
                      "Rules in this file" registry ([SKILL-CREATE-005c]),
                      or body sub-label indexed by that registry ([AUDIT-028]c).
                      En-dash/em-dash ranges resolve on their ENDPOINTS
                      (sparse ranges are corpus-legal, e.g. PATTERN-012–062);
                      wildcards [FOO-*] resolve if any FOO- id exists.
                      Placeholder grammar and YAML frontmatter (changelog
                      history lines) are exempt; fenced code blocks skipped.
  2. duplicates     — same ID defined at 2+ sites fails, EXCEPT allowlisted
                      mirrors per [SKILL-CREATE-016] (.check-canon-allowlist).
  3. artifacts      — every cited workspace path/script exists OR the citing
                      line carries an aspirational-tense marker per
                      [SKILL-LIFE-027].
  4. hub-index      — every companion file is named from its SKILL.md; every
                      companion-defined ID is visible from the hub (literal
                      mention or range coverage); registry claims reconcile
                      against the file body.
  5. last-reviewed  — implement the [SKILL-LIFE-005] in-rule spec: per skill,
                      the newest git commit date touching the skill's .md
                      files must not exceed SKILL.md's `last_reviewed`
                      frontmatter + 1 day.

Baseline: .check-canon-baseline (sibling file) — prune-only ratchet, same
contract as .skill-size-baseline. Lines: `<check> <stable-key…>`; `#` comments.
Allowlist: .check-canon-allowlist — sanctioned duplicate-definition mirrors,
lines: `<ID> <root-alias:relative-path>`.

Modes: report-only by default (exit 0, findings printed). --enforce exits 1
on any non-baselined finding. Flipping the sync/CI wiring to --enforce
requires an explicit principal YES (HANDOFF-mechanization-arc constraint).

Provenance: HANDOFF-mechanization-arc.md W0; REPORT-corpus-review.md (2026-07-05)
proved the guarded/unguarded health split this gate closes.
"""

import argparse
import datetime
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# --- ID grammar ---------------------------------------------------------------
# Numeric rule IDs: PREFIX(-SEGMENT)*-NNN with optional single letter suffix
# (e.g. API-NAME-001, PLAT-ARCH-008g, HANDOFF-024a).
NUMERIC_ID = r"[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*-[0-9]{1,3}[a-z]?"
# Word-form axioms per swift-institute-core: [IMPL-INTENT], [MOD-DOMAIN] —
# all-cap segments, no digits.
WORD_ID = r"[A-Z]{2,}(?:-[A-Z]{2,})+"
# A dash in range notation: hyphen, en dash, or em dash, optionally spaced.
DASH = r"\s?[-–—]\s?"

# Bracketed citation tokens, in decreasing specificity:
#   [PREFIX-010–020]      in-bracket range ([AUDIT-028]a)
#   [PREFIX-010]–[PREFIX-020]  cross-bracket range
#   [PREFIX-*]            wildcard
#   [PREFIX-010] / [IMPL-INTENT]  single cite
RE_INBRACKET_RANGE = re.compile(
    r"\[(" + NUMERIC_ID + r")" + DASH + r"([0-9]{1,3}[a-z]?)\]"
)
RE_CROSS_RANGE = re.compile(
    r"\[(" + NUMERIC_ID + r")\]" + DASH + r"\[(" + NUMERIC_ID + r")\]"
)
RE_WILDCARD = re.compile(r"\[([A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*)-\*\]")
RE_SINGLE = re.compile(r"\[(" + NUMERIC_ID + r"|" + WORD_ID + r")\]")

# Definition forms.
RE_HEADING_DEF = re.compile(r"^#{2,6}\s+\[(" + NUMERIC_ID + r"|" + WORD_ID + r")\]")
RE_RULES_IN_FILE = re.compile(r"^\*\*Rules in this file:?\*\*\s*:?", re.IGNORECASE)
RE_TABLE_ROW = re.compile(r"^\|\s*\[(" + NUMERIC_ID + r")\]\s*\|")

# Placeholder grammar (exempt from check 1). Prefix-based: template/example
# prefixes that never name real rules (CLAIM/ASSUMP are research-doc-local
# registry families per research-process, not rulebook IDs). Numeric-part-based:
# NNN/N/NUMBER/XXX tokens.
PLACEHOLDER_PREFIXES = {"PREFIX", "X", "ID", "ID-PREFIX", "FOO", "OTHER", "OTHER-ID",
                        "CLAIM", "ASSUMP"}
RE_PLACEHOLDER_TOKEN = re.compile(
    r"\[(?:\{[^}]*\}|<[^>]*>|[A-Z-]*(?:NNN|N\b|NUMBER|WORD|SECTION|XXX)[A-Za-z0-9+.-]*)\]"
)

# Aspirational-tense markers per [SKILL-LIFE-027] (case-insensitive, same line),
# plus negative-assertion idioms: a path cited as forbidden ("Never
# `Research/audit.md`") or as a violation pattern to grep for carries no
# existence claim.
ASPIRATIONAL_MARKERS = (
    "aspirational", "pending", "future", "once it lands", "currently in draft",
    "missing as of", "not yet", "planned", "does not exist yet", "when it lands",
    "missing on disk", "re-locate or re-create",
    "never", "must not", "forbidden", "anti-pattern", "violation",
)

# Historical-reference markers: a citation of a RETIRED id is deliberate when
# the line carries a supersession idiom ([SKILL-LIFE-020] redirect notices,
# [SKILL-LIFE-028] burned slots, "Subsumes [X]" absorption notes). A dangling
# cite WITHOUT such a marker is the [SKILL-LIFE-007] rot class this check exists
# to catch.
HISTORICAL_MARKERS = (
    "subsume", "demoted", "burned", "absorbed", "superseded", "supersedes",
    "formerly", "renumbered", "retired", "the former", "ghost", "deleted",
    "no rule body", "slot stays", "never defined", "redirect",
)

# Path-citation extraction for check 3: backtick-quoted tokens that look like
# workspace paths. Conservative by construction — template placeholders,
# globs, and bare filenames are skipped; the check exists to catch concrete
# stale paths (ST-6/ST-7/ST-13 class), not to inventory every mention.
RE_BACKTICK = re.compile(r"`([^`\n]+)`")
PATH_EXTENSIONS = (".sh", ".py", ".md", ".yml", ".yaml", ".swift", ".tsv", ".json")
PATH_SKIP_CHARS = ("{", "}", "<", ">", "*", "$", "…", "…", " ")


def is_placeholder(token_text: str) -> bool:
    inner = token_text.strip("[]")
    prefix_parts = inner.split("-")
    if prefix_parts[0] in PLACEHOLDER_PREFIXES:
        return True
    if inner.rstrip("]").startswith(("{", "<")):
        return True
    return bool(RE_PLACEHOLDER_TOKEN.fullmatch(token_text))


def id_sort_key(rule_id: str):
    m = re.match(r"^(.*)-([0-9]+)([a-z]?)$", rule_id)
    if not m:
        return (rule_id, -1, "")
    return (m.group(1), int(m.group(2)), m.group(3))


def id_prefix_num(rule_id: str):
    """Split a numeric ID into (prefix, number, letter-suffix) or None."""
    m = re.match(r"^(.*)-([0-9]+)([a-z]?)$", rule_id)
    if not m:
        return None
    return m.group(1), int(m.group(2)), m.group(3)


class MdFile:
    """One markdown file, pre-split into frontmatter / body, code-block-aware."""

    def __init__(self, path: Path, alias: str):
        self.path = path
        self.alias = alias  # e.g. "institute:code-surface/SKILL.md"
        text = path.read_text(encoding="utf-8", errors="replace")
        self.lines = text.splitlines()
        self.frontmatter_end = 0
        if self.lines and self.lines[0].strip() == "---":
            for i in range(1, len(self.lines)):
                if self.lines[i].strip() == "---":
                    self.frontmatter_end = i + 1
                    break
        self.frontmatter = self.lines[: self.frontmatter_end]
        # Body lines annotated with in-code-block state.
        self.body = []  # (lineno_1based, line, in_code_block)
        in_code = False
        for i in range(self.frontmatter_end, len(self.lines)):
            line = self.lines[i]
            if re.match(r"^\s*(```|~~~)", line):
                self.body.append((i + 1, line, True))
                in_code = not in_code
                continue
            self.body.append((i + 1, line, in_code))

    def prose_lines(self):
        """Body lines outside fenced code blocks."""
        return [(n, l) for (n, l, c) in self.body if not c]

    def all_body_lines(self):
        return [(n, l) for (n, l, _) in self.body]

    def frontmatter_value(self, key: str):
        for line in self.frontmatter:
            m = re.match(r"^\s*" + re.escape(key) + r"\s*:\s*(\S+)", line)
            if m:
                return m.group(1).strip("'\"")
        return None


# --- Corpus loading ------------------------------------------------------------

def load_corpus(roots, extra_files):
    """Return (files, skills). files: list[MdFile]. skills: {alias_dir: [MdFile]}
    where alias_dir identifies a skill directory (contains SKILL.md)."""
    files = []
    skills = {}
    for alias, root in roots:
        root = Path(root)
        if not root.is_dir():
            continue
        for md in sorted(root.rglob("*.md")):
            rel = md.relative_to(root)
            f = MdFile(md, f"{alias}:{rel}")
            files.append(f)
        for skill_dir in sorted(p.parent for p in root.glob("*/SKILL.md")):
            alias_dir = f"{alias}:{skill_dir.relative_to(root)}"
            members = [f for f in files
                       if f.path.parent == skill_dir and f.path.suffix == ".md"]
            skills[alias_dir] = {"dir": skill_dir, "members": members}
    for alias, p in extra_files:
        p = Path(p)
        if p.is_file():
            files.append(MdFile(p, alias))
    return files, skills


# --- Definition census ----------------------------------------------------------

def registry_ids(f: MdFile):
    """IDs enumerated by a file's 'Rules in this file' registry header
    (covers table-row catalogue rules per [SKILL-CREATE-005c] and body
    sub-labels per [AUDIT-028]c). Registry ranges expand FULLY — the header
    is an explicit claim of each member."""
    ids = set()
    for n, line in f.prose_lines():
        if not RE_RULES_IN_FILE.match(line):
            continue
        for m in RE_CROSS_RANGE.finditer(line):
            ids.update(expand_range(m.group(1), m.group(2)))
        # Strip cross-bracket ranges so their endpoints aren't double-counted.
        stripped = RE_CROSS_RANGE.sub(" ", line)
        for m in RE_INBRACKET_RANGE.finditer(stripped):
            ids.update(expand_range(m.group(1), m.group(1).rsplit("-", 1)[0] + "-" + m.group(2)))
        stripped = RE_INBRACKET_RANGE.sub(" ", stripped)
        for m in RE_SINGLE.finditer(stripped):
            ids.add(m.group(1))
    return ids


def expand_range(start_id: str, end_id: str):
    """Expand [X-010]…[X-015] to member IDs. Returns {start,end} when the
    pair doesn't share a prefix or has letter suffixes (no arithmetic)."""
    s, e = id_prefix_num(start_id), id_prefix_num(end_id)
    if not s or not e or s[0] != e[0] or s[2] or e[2] or e[1] < s[1] or e[1] - s[1] > 200:
        return {start_id, end_id}
    width = len(re.match(r"^.*-([0-9]+)", start_id).group(1))
    return {f"{s[0]}-{str(n).zfill(width)}" for n in range(s[1], e[1] + 1)}


def build_definitions(files):
    """{ID: [(alias, lineno, form)]} across the corpus."""
    defs = defaultdict(list)
    for f in files:
        for n, line in f.prose_lines():
            m = RE_HEADING_DEF.match(line)
            if m:
                defs[m.group(1)].append((f.alias, n, "heading"))
        for rid in registry_ids(f):
            defs[rid].append((f.alias, 0, "registry"))
    return defs


# --- Check 1: citation resolution ----------------------------------------------

def check_citations(files, defs, verbose=False):
    findings = []
    defined = set(defs.keys())
    # A wildcard [FOO-*] (and a bare word-form family reference like
    # [MOD-EXCEPT]) resolves if any defined id extends it: [MEM-*] is anchored
    # by MEM-COPY-001 just as [MEM-COPY-*] is.
    def family_anchored(prefix):
        probe = prefix + "-"
        return any(d.startswith(probe) for d in defined)

    for f in files:
        for n, line in f.prose_lines():
            historical = any(m in line.lower() for m in HISTORICAL_MARKERS)

            def emit(token, msg):
                if not historical:
                    findings.append((f"{f.alias} [{token}]", msg))

            for m in RE_CROSS_RANGE.finditer(line):
                for endpoint in (m.group(1), m.group(2)):
                    if endpoint not in defined:
                        emit(endpoint,
                             f"{f.alias}:{n} range endpoint [{endpoint}] unresolved")
            stripped = RE_CROSS_RANGE.sub(lambda m: " " * len(m.group(0)), line)
            for m in RE_INBRACKET_RANGE.finditer(stripped):
                start = m.group(1)
                end = start.rsplit("-", 1)[0] + "-" + m.group(2)
                for endpoint in (start, end):
                    if endpoint not in defined:
                        emit(endpoint,
                             f"{f.alias}:{n} in-bracket range endpoint [{endpoint}] unresolved")
            stripped = RE_INBRACKET_RANGE.sub(lambda m: " " * len(m.group(0)), stripped)
            for m in RE_WILDCARD.finditer(stripped):
                if m.group(1) in PLACEHOLDER_PREFIXES:
                    continue
                if not family_anchored(m.group(1)):
                    emit(f"{m.group(1)}-*",
                         f"{f.alias}:{n} wildcard [{m.group(1)}-*] matches no defined id")
            stripped = RE_WILDCARD.sub(lambda m: " " * len(m.group(0)), stripped)
            for m in RE_SINGLE.finditer(stripped):
                tok = m.group(1)
                if is_placeholder(f"[{tok}]"):
                    continue
                if tok in defined:
                    continue
                # Word-form token that names a defined family is a prefix
                # reference ("the [MOD-EXCEPT] family"), not a dangle.
                if re.fullmatch(WORD_ID, tok) and family_anchored(tok):
                    continue
                emit(tok, f"{f.alias}:{n} citation [{tok}] unresolved")
    return dedupe(findings)


# --- Check 2: duplicate definitions ---------------------------------------------

def check_duplicates(defs, allowlist):
    findings = []
    for rid, sites in sorted(defs.items(), key=lambda kv: id_sort_key(kv[0])):
        # Heading-form sites only: a registry entry naming a heading-defined id
        # in the SAME file is indexing, not redefinition; registry entries in
        # OTHER files would be surfaced by hub reconciliation, not here.
        heading_sites = [(a, n) for (a, n, form) in sites if form == "heading"]
        if len(heading_sites) < 2:
            continue
        allowed = {a for (i, a) in allowlist if i == rid}
        effective = [a for (a, n) in heading_sites if a.split(":")[0] + ":" + a.split(":", 1)[1] not in allowed and a not in allowed]
        # Same-file double definition (CR-1 class) always fails.
        by_file = defaultdict(int)
        for a, n in heading_sites:
            by_file[a] += 1
        same_file_dup = any(c > 1 for c in by_file.values())
        if len(effective) > 1 or same_file_dup:
            sites_s = ", ".join(f"{a}:{n}" for a, n in heading_sites)
            findings.append((f"[{rid}]", f"[{rid}] defined at {len(heading_sites)} sites: {sites_s}"))
    return dedupe(findings)


# --- Check 3: artifact existence ------------------------------------------------

# First path segments the checker treats as workspace-anchored (verifiable).
# Relative paths outside this set are consumer-repo-relative templates
# (`.github/workflows/ci.yml`, `Tests/Package.swift`, …) — unverifiable from
# the workspace, deliberately skipped.
ANCHOR_SEGMENTS = {
    "Scripts", "Research", "Skills", "Workspace", "Audits", "Blog",
    "Experiments", "Engagement", "Reflections", "handoffs",
    "swift-institute", "rule-institute", "rule-law", "rule-legal",
    "swift-law", "swift-nl-wetgever", "swift-us-nv-legislature",
}
PLACEHOLDER_PATH_PARTS = ("XXX", "foo.", "bar.", "/tmp/")


def looks_like_path(tok: str) -> bool:
    if "/" not in tok:
        return False
    if any(c in tok for c in PATH_SKIP_CHARS):
        return False
    if any(p in tok for p in PLACEHOLDER_PATH_PARTS) or tok.startswith("/tmp"):
        return False
    if "/.../" in tok:  # abbreviated path, not a concrete citation
        return False
    if tok.startswith("/") and tok.count("/") == 1:
        return False  # URL path fragment (`/categories.json`), not filesystem
    if tok.startswith(("http://", "https://", "git@", "-", "--")):
        return False
    last = tok.rstrip("/").rsplit("/", 1)[-1]
    return last.endswith(PATH_EXTENSIONS)


def anchored(tok: str) -> bool:
    if tok.startswith(("/", "~")):
        return True
    first = tok.split("/", 1)[0]
    return (first in ANCHOR_SEGMENTS
            or first.startswith(("swift-", "rule-")))


def resolve_workspace_path(tok: str, citing_file: Path, dev_root: Path):
    """Resolve an anchored token against the workspace. Absolute and ~ paths
    resolve directly; relative anchored paths try the citing dir, its
    ancestors up to the dev root, and the standard org/repo bases."""
    if tok.startswith("~"):
        return Path(os.path.expanduser(tok)).exists()
    if tok.startswith("/"):
        return Path(tok).exists()
    if tok.startswith("./"):
        tok = tok[2:]
    candidates = [citing_file.parent / tok, dev_root / tok]
    p = citing_file.parent
    while dev_root in p.parents or p == dev_root:
        candidates.append(p / tok)
        if p == dev_root:
            break
        p = p.parent
    for base in ("swift-institute", "swift-institute/Workspace",
                 "swift-institute/Research", "swift-institute/Engagement",
                 "swift-primitives", "swift-standards", "swift-foundations",
                 "rule-institute", "rule-law"):
        candidates.append(dev_root / base / tok)
    return any(c.exists() for c in candidates)


def check_artifacts(files, dev_root: Path):
    findings = []
    for f in files:
        for n, line in f.all_body_lines():
            lowered = line.lower()
            if any(m in lowered for m in ASPIRATIONAL_MARKERS):
                continue
            for m in RE_BACKTICK.finditer(line):
                tok = m.group(1).strip()
                if not looks_like_path(tok) or not anchored(tok):
                    continue
                if not resolve_workspace_path(tok, f.path, dev_root):
                    findings.append((f"{f.alias} {tok}",
                                     f"{f.alias}:{n} cited path `{tok}` not found (annotate per [SKILL-LIFE-027] or re-point)"))
    return dedupe(findings)


# --- Check 4: hub-index completeness --------------------------------------------

def check_hub_index(skills):
    findings = []
    for alias_dir, info in sorted(skills.items()):
        members = info["members"]
        hub = next((f for f in members if f.path.name == "SKILL.md"), None)
        companions = [f for f in members if f.path.name != "SKILL.md"]
        if not hub or not companions:
            continue
        hub_text = "\n".join(l for _, l in hub.prose_lines())
        # (a) every companion named from the hub
        for c in companions:
            if c.path.name not in hub_text:
                findings.append((f"{alias_dir} {c.path.name}",
                                 f"{alias_dir}: companion {c.path.name} not named from SKILL.md"))
        # Hub-visible IDs: literal mentions + full expansion of hub ranges.
        visible = set()
        for _, line in hub.prose_lines():
            for m in RE_CROSS_RANGE.finditer(line):
                visible.update(expand_range(m.group(1), m.group(2)))
            stripped = RE_CROSS_RANGE.sub(" ", line)
            for m in RE_INBRACKET_RANGE.finditer(stripped):
                visible.update(expand_range(m.group(1), m.group(1).rsplit("-", 1)[0] + "-" + m.group(2)))
            stripped = RE_INBRACKET_RANGE.sub(" ", stripped)
            for m in RE_SINGLE.finditer(stripped):
                visible.add(m.group(1))
        # (b) every companion-defined ID visible from the hub
        for c in companions:
            c_ids = {m.group(1) for _, l in c.prose_lines() for m in [RE_HEADING_DEF.match(l)] if m}
            c_ids |= registry_ids(c)
            for rid in sorted(c_ids, key=id_sort_key):
                if rid not in visible:
                    findings.append((f"{alias_dir} [{rid}]",
                                     f"{alias_dir}: [{rid}] defined in {c.path.name} but invisible from SKILL.md"))
        # (c) registry claims with no trace in the file body (registry lines
        # excluded — a range claim never carries member literals itself)
        for c in companions + [hub]:
            body = "\n".join(l for _, l in c.prose_lines()
                             if not RE_RULES_IN_FILE.match(l))
            for rid in sorted(registry_ids(c), key=id_sort_key):
                if rid not in body:
                    findings.append((f"{alias_dir} registry [{rid}]",
                                     f"{alias_dir}: registry of {c.path.name} claims [{rid}] but the body never carries it"))
    return dedupe(findings)


# --- Check 5: last_reviewed drift ([SKILL-LIFE-005]) ------------------------------

def check_last_reviewed(skills):
    findings = []
    for alias_dir, info in sorted(skills.items()):
        skill_dir = info["dir"]
        hub = next((f for f in info["members"] if f.path.name == "SKILL.md"), None)
        if hub is None:
            continue
        last_reviewed = hub.frontmatter_value("last_reviewed")
        if not last_reviewed:
            findings.append((f"{alias_dir} missing",
                             f"{alias_dir}: no last_reviewed frontmatter in SKILL.md"))
            continue
        try:
            reviewed = datetime.date.fromisoformat(last_reviewed)
        except ValueError:
            findings.append((f"{alias_dir} malformed",
                             f"{alias_dir}: malformed last_reviewed '{last_reviewed}'"))
            continue
        try:
            out = subprocess.run(
                ["git", "-C", str(skill_dir), "log", "-1", "--format=%cs", "--", "."],
                capture_output=True, text=True, timeout=30, check=True,
            ).stdout.strip()
        except (subprocess.SubprocessError, OSError):
            continue  # not a git checkout (CI shallow layouts handled by wrapper)
        if not out:
            continue
        modified = datetime.date.fromisoformat(out)
        if modified > reviewed + datetime.timedelta(days=1):
            # Key carries the modified date: a baselined drift entry masks only
            # THIS drift — any newer commit re-fires and must be freshly fixed.
            findings.append((f"{alias_dir} drift {modified}",
                             f"{alias_dir}: modified {modified} > last_reviewed {reviewed} + 1 day ([SKILL-LIFE-005])"))
    return dedupe(findings)


# --- Harness ---------------------------------------------------------------------

def dedupe(findings):
    seen, out = set(), []
    for key, msg in findings:
        if key not in seen:
            seen.add(key)
            out.append((key, msg))
    return out


def load_baseline(path: Path):
    entries = set()
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                entries.add(line)
    return entries


def load_allowlist(path: Path):
    entries = set()
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                parts = line.split(None, 1)
                if len(parts) == 2:
                    entries.add((parts[0].strip("[]"), parts[1]))
    return entries


CHECKS = ["citations", "duplicates", "artifacts", "hub-index", "last-reviewed"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", action="append", default=[],
                    help="alias=path skill root (repeatable)")
    ap.add_argument("--file", action="append", default=[],
                    help="alias=path extra scanned file, e.g. Workspace/CLAUDE.md")
    ap.add_argument("--check", action="append", choices=CHECKS, default=[],
                    help="run only these checks (repeatable; default all)")
    ap.add_argument("--enforce", action="store_true",
                    help="exit 1 on non-baselined findings (default: report-only)")
    ap.add_argument("--emit-baseline", action="store_true",
                    help="print baseline lines for current findings and exit 0")
    ap.add_argument("--dev-root", default=str(Path.home() / "Developer"))
    args = ap.parse_args()

    roots = [tuple(r.split("=", 1)) for r in args.root]
    extra = [tuple(f.split("=", 1)) for f in args.file]
    active = args.check or CHECKS

    script_dir = Path(__file__).resolve().parent
    baseline = load_baseline(script_dir / ".check-canon-baseline")
    allowlist = load_allowlist(script_dir / ".check-canon-allowlist")

    files, skills = load_corpus(roots, extra)
    if not files:
        print("::error::check-canon: no corpus files found", file=sys.stderr)
        return 2
    defs = build_definitions(files)

    results = {}
    if "citations" in active:
        results["citations"] = check_citations(files, defs)
    if "duplicates" in active:
        results["duplicates"] = check_duplicates(defs, allowlist)
    if "artifacts" in active:
        results["artifacts"] = check_artifacts(files, Path(args.dev_root))
    if "hub-index" in active:
        results["hub-index"] = check_hub_index(skills)
    if "last-reviewed" in active:
        results["last-reviewed"] = check_last_reviewed(skills)

    if args.emit_baseline:
        for check, findings in results.items():
            for key, _ in findings:
                print(f"{check} {key}")
        return 0

    new_count = 0
    baselined_count = 0
    for check in CHECKS:
        if check not in results:
            continue
        findings = results[check]
        fresh = [(k, m) for k, m in findings if f"{check} {k}" not in baseline]
        baselined_count += len(findings) - len(fresh)
        new_count += len(fresh)
        status = "OK" if not fresh else f"{len(fresh)} finding(s)"
        print(f"check-canon[{check}]: {status}"
              + (f" ({len(findings) - len(fresh)} baselined)" if len(findings) - len(fresh) else ""))
        for _, msg in fresh:
            print(f"  {msg}")

    print(f"check-canon: {new_count} new finding(s), {baselined_count} baselined, "
          f"{len(files)} files, {len(defs)} defined ids"
          + ("" if args.enforce else " [report-only]"))
    if args.enforce and new_count:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
