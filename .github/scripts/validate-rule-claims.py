#!/usr/bin/env python3
"""[GH-REPO-063a] Rule-text <-> mechanism consistency guard.

Sibling to validate-schema-workflow-keys.py ([GH-REPO-063]), which asserts that
metadata-schema.json's settings keys match sync-metadata.yml's reads. This one
generalises the same idea to a different pair of artifacts: a RULE'S CLAIM ABOUT
A MECHANISM, versus the mechanism.

Origin — four instances in one night (2026-07-25), four subsystems, one shape:
  * [GH-REPO-014] cited a `sync-metadata.yml` validation pass that never existed.
  * [GH-REPO-011] repeated the same false claim in a second location.
  * [GH-REPO-023] asserts topics 2-10 while the enforced schema bound is 0-20.
  * a census harness carried a comment describing a skip never implemented.

A rule and its enforcement are authored together, then drift apart silently,
because nothing compares the rule's claim about a mechanism against the
mechanism. The dangerous half is not the unenforced rule -- that gets found when
someone looks -- but the rule enforced at a DIFFERENT threshold than it states,
which reports success forever.

Checks
------
C1  VERIFICATION-artifact existence. Every `[VERIFICATION: ... <file>]` tag
    naming a .py/.yml/.sh must name an artifact that exists.
C2  Prose enforcement claims. A sentence asserting that a named workflow/script
    validates/enforces/surfaces something must name an artifact that (a) exists
    and (b) actually mentions the subject it supposedly checks.
C3  Declared numeric bounds. A rule stating a bound for a schema-backed field
    must agree with the schema's declared bound.

Known limits -- stated because a validator's blind spots look identical to a
clean corpus, and a reader who does not know them will over-trust a green run:

1. NOT CHECKABLE: whether a mechanism's LOGIC implements the semantic a rule
   describes. The census-harness defect of 2026-07-25 -- a comment describing a
   nested-package skip that was never implemented -- is invisible here: the
   file exists, and the claim lives inside the very artifact it describes, so
   there are not two artifacts to compare. That class needs a TEST, not a
   linter. C2b narrows it to "does the enforcer even mention the subject",
   which is necessary but nowhere near sufficient.
2. NOT CHECKABLE: whether a gate that exists is actually WIRED and BLOCKING.
   A validator invoked with `dry-run: true`, or never called by any workflow,
   passes every check here. ([GH-REPO-023]'s gate is real AND wired; that had
   to be established by hand.)
3. SILENT ZERO by construction: C2b and C3 only cover rules registered in
   CLAIM_BINDINGS / BOUND_BINDINGS. An unregistered claim is not checked and
   produces no output -- the standing cost of preferring exactness over
   inference. The advisory arm (C4) exists to surface candidates for
   registration; it is heuristic and must never gate.
4. Prose parsing is regex over hard-wrapped Markdown. Two known failure shapes
   are handled explicitly (whitespace normalisation, sentence-bounded negation)
   because both silently under-report; others certainly remain.

Usage:
  validate-rule-claims.py [--skills DIR] [--github DIR] [--selftest]
Exit 0 clean, 1 findings, 2 usage/IO error.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

# --------------------------------------------------------------------------
# C3 binding table. Explicit and auditable on purpose: inferring which schema
# node a prose bound refers to is exactly the kind of magic that fails toward a
# silent zero. Add a row when a rule states a bound over a schema-backed field.
#   rule id -> (regex capturing (low, high), JSON path in the schema,
#               schema key for min, schema key for max)
# --------------------------------------------------------------------------
BOUND_BINDINGS = [
    {
        "rule": "GH-REPO-023",
        "pattern": re.compile(
            r"MUST be between (\d+) and (\d+) inclusive", re.I),
        "schema_path": ("properties", "topics"),
        "min_key": "minItems",
        "max_key": "maxItems",
    },
]

# C2: verbs that assert a mechanism enforces something.
# --------------------------------------------------------------------------
# C2b binding table. "Does mechanism M actually implement semantic S?" is not
# decidable from text (see "Known limits"). Where the subject IS known, bind it
# explicitly and the check becomes exact and gating. A rule with no binding is
# covered only by the heuristic advisory arm -- i.e. an unregistered claim is a
# SILENT ZERO, which is the standing cost of this design.
#   rule id -> (enforcer named by the rule, token the enforcer must contain)
# --------------------------------------------------------------------------
CLAIM_BINDINGS = [
    # Both seeded 2026-07-25 from the defects that motivated this validator;
    # both rule texts were corrected in Skills@c4c8fc8, so these fire only
    # against the pre-fix fixture -- which is exactly the regression guard.
    {"rule": "GH-REPO-014", "artifact": "sync-metadata.yml",
     "must_contain": "spec-title",
     "why": "the claimed drift check would have to read the title table"},
    {"rule": "GH-REPO-011", "artifact": "sync-metadata.yml",
     "must_contain": "template",
     "why": "the claimed template-conformance check would have to know templates"},
]

CLAIM_RE = re.compile(
    r"(?P<verb>validates?|enforced by|enforces|surfaced by|checked by|"
    r"caught by|gated by)"
    r"[^.`]{0,80}`(?P<artifact>[A-Za-z0-9._/-]+\.(?:yml|py|sh))`",
    re.I,
)
# also the reversed word order: `X.yml` ... validates ...
CLAIM_RE_REV = re.compile(
    r"`(?P<artifact>[A-Za-z0-9._/-]+\.(?:yml|py|sh))`"
    r"[^.]{0,40}?(?P<verb>validates|enforces|checks)\b",
    re.I,
)

NEGATION_RE = re.compile(
    r"\b(no workflow|nothing|never|not validated|is not|does not|do not cite|"
    r"contains no|no such|neither)\b")

VERIFICATION_RE = re.compile(r"\[VERIFICATION:([^\]]*)\]")
ARTIFACT_IN_TAG_RE = re.compile(r"[A-Za-z0-9._-]+\.(?:py|yml|sh)")
RULE_ID_RE = re.compile(r"\[([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)\]")
# A backticked token from the claim's own rule block, used as the subject the
# named artifact must mention. Filters out the artifact name itself.
SUBJECT_RE = re.compile(r"`([A-Za-z0-9._-]{3,})`")


class Finding:
    def __init__(self, check: str, rule: str, path: pathlib.Path, msg: str):
        self.check, self.rule, self.path, self.msg = check, rule, path, msg

    def __str__(self) -> str:
        return f"  [{self.check}] {self.rule or '-'} ({self.path.name}): {self.msg}"


def resolve_artifact(github_root: pathlib.Path, name: str,
                     workspace_root: pathlib.Path | None = None) -> str:
    """Return 'found' | 'missing' | 'unverifiable'.

    Citations come in two flavours and conflating them produced four false
    positives on first run (2026-07-25, caught by ECO-CI1):

      * IN-REPO      `validate-thin-callers.py`      -> .github/{scripts,workflows}
      * WORKSPACE    `swift-institute/Scripts/x.sh`  -> a SIBLING repo, one level
                                                        ABOVE the .github root

    Resolving only against the .github root reported every sibling-repo citation
    as missing. Worse, that is the failure direction that looks like a real
    finding, so it got reported upstream as a deleted script before anyone ran
    `ls`.

    'unverifiable' exists because sibling repos are not checked out in CI (and
    swift-institute/Scripts is private). Absence there is NOT evidence of
    deletion, so it must be surfaced as a logged skip rather than silently
    passed or falsely reported.
    """
    base = name.split("/")[-1]
    for sub in ("workflows", "scripts", "actions"):
        if (github_root / ".github" / sub / base).is_file():
            return "found"
    if (github_root / name).is_file() or (github_root / base).is_file():
        return "found"

    if workspace_root is not None:
        # Citations are workspace-relative: strip a leading repo name if the
        # citation already carries one, then try both spellings.
        candidates = [workspace_root / name]
        parts = name.split("/")
        if len(parts) > 1:
            candidates.append(workspace_root / "/".join(parts[1:]))
            candidates.append(workspace_root.parent / name)
        for c in candidates:
            if c.is_file():
                return "found"
        # Does the sibling repo the citation names even exist here?
        top = parts[0] if len(parts) > 1 else None
        if top and not (workspace_root / top).is_dir() \
                and not (workspace_root.parent / top).is_dir():
            return "unverifiable"
        if len(parts) > 1:
            return "missing"

        # BARE filename ("sync-gitignore.sh"), which carries no location. Search
        # a bounded set of sibling locations before concluding anything: one
        # level of sibling repo, plus each one's Scripts/ dir.
        for sib in sorted(workspace_root.iterdir()):
            if not sib.is_dir() or sib.name.startswith("."):
                continue
            if (sib / base).is_file() or (sib / "Scripts" / base).is_file():
                return "found"

        # Still not found. Two bare-name classes live in THIS repo by
        # convention, so absence IS evidence for them:
        #   * `*.yml`            -> .github/workflows/
        #   * `validate-*.py`    -> .github/scripts/ (manifest convention)
        # Any other bare name (a Script-class `.sh`, a helper `.py`) may live in
        # a sibling repo that simply is not checked out, so absence proves
        # nothing and must be reported as unverified rather than missing.
        if base.endswith(".yml") or (base.startswith("validate-")
                                     and base.endswith(".py")):
            return "missing"
        return "unverifiable"
    return "unverifiable"


def artifact_exists(github_root: pathlib.Path, name: str,
                    workspace_root: pathlib.Path | None = None) -> bool:
    return resolve_artifact(github_root, name, workspace_root) != "missing"


def read_artifact(github_root: pathlib.Path, name: str) -> str | None:
    base = name.split("/")[-1]
    for sub in ("workflows", "scripts"):
        p = github_root / ".github" / sub / base
        if p.is_file():
            return p.read_text(errors="replace")
    return None


def split_rule_blocks(text: str) -> list[tuple[str, str]]:
    """Split a SKILL.md into (rule-id, block-text). Blocks start at a heading
    carrying a bracketed rule id; text before the first is attributed to ''."""
    lines = text.splitlines()
    blocks, cur_id, buf = [], "", []
    for ln in lines:
        if ln.startswith("#"):
            m = RULE_ID_RE.search(ln)
            if m:
                blocks.append((cur_id, "\n".join(buf)))
                cur_id, buf = m.group(1), [ln]
                continue
        buf.append(ln)
    blocks.append((cur_id, "\n".join(buf)))
    return blocks


def check_c1(skill_files, github_root, workspace_root, skips) -> list[Finding]:
    out = []
    for f in skill_files:
        text = f.read_text(errors="replace")
        for rid, block in split_rule_blocks(text):
            for tag in VERIFICATION_RE.findall(block):
                for art in ARTIFACT_IN_TAG_RE.findall(tag):
                    state = resolve_artifact(github_root, art, workspace_root)
                    if state == "unverifiable":
                        skips.append(f"C1 {rid or '-'}: `{art}` (sibling repo "
                                     f"not present here)")
                    elif state == "missing":
                        out.append(Finding(
                            "C1", rid, f,
                            f"[VERIFICATION] names `{art}`, which does not exist"))
    return out


def _claims(block: str):
    """Yield (artifact, verb) for each enforcement claim in a rule block.

    Whitespace is normalised FIRST. Rule prose is hard-wrapped, so a
    multi-word verb straddles a newline ("surfaced\\nby") and a pattern with a
    literal space silently matches nothing. That failure is invisible: it
    returns a clean zero over a block full of claims. Caught 2026-07-25 when
    the validator missed [GH-REPO-014], the very defect it was built for.
    """
    block = re.sub(r"\s+", " ", block)
    seen = set()
    for rx in (CLAIM_RE, CLAIM_RE_REV):
        for m in rx.finditer(block):
            art = m.group("artifact")
            if art in seen:
                continue
            # Negation guard. A rule that correctly says "NO workflow validates
            # this" names the same verb+artifact as one that falsely claims it
            # does. Without this the validator flags accurate prose -- and the
            # cheapest way to silence it would be to delete the true statement,
            # so the check would actively push the corpus toward being wrong.
            # Bound the window to the CONTAINING SENTENCE. A fixed-width window
            # reaches into the previous sentence and suppresses real findings:
            # [DS-026] was silently dropped because an unrelated preceding
            # clause ended "...are never visited." Over-suppression is the
            # dangerous direction -- it looks exactly like a clean corpus.
            start = block.rfind(". ", 0, m.start()) + 1
            window = block[start:m.end()].lower()
            if NEGATION_RE.search(window):
                continue
            seen.add(art)
            yield art, m.group("verb").lower()


def check_c2(skill_files, github_root, workspace_root, skips) -> list[Finding]:
    """GATE: a rule naming an enforcer must name one that exists.

    Mechanical, but only where the artifact is RESOLVABLE here -- citations
    into sibling repos absent from this checkout are logged as skips, never
    reported as missing. See resolve_artifact().
    """
    out = []
    for f in skill_files:
        for rid, block in split_rule_blocks(f.read_text(errors="replace")):
            for art, verb in _claims(block):
                state = resolve_artifact(github_root, art, workspace_root)
                if state == "unverifiable":
                    skips.append(f"C2 {rid or '-'}: `{art}` (sibling repo not "
                                 f"present here)")
                elif state == "missing":
                    out.append(Finding(
                        "C2", rid, f,
                        f"claims `{art}` {verb} it, but `{art}` does not exist"))
    return out


def check_c2b(skill_files, github_root) -> list[Finding]:
    """GATE: where a rule's subject is explicitly bound, the enforcer it names
    must actually mention that subject. Exact, not heuristic -- the binding
    table supplies the subject a regex cannot infer."""
    out = []
    for f in skill_files:
        blocks = dict(split_rule_blocks(f.read_text(errors="replace")))
        for b in CLAIM_BINDINGS:
            block = blocks.get(b["rule"])
            if not block:
                continue
            named = [a for a, _ in _claims(block)
                     if a.split("/")[-1] == b["artifact"]]
            if not named:
                continue  # rule no longer claims this enforcer
            body = read_artifact(github_root, b["artifact"])
            if body is None:
                continue  # existence is C2's job
            body = _resolve_delegated(github_root, body)
            if b["must_contain"].lower() not in body.lower():
                out.append(Finding(
                    "C2b", b["rule"], f,
                    f"names `{b['artifact']}` as its enforcer, but that file "
                    f"never mentions `{b['must_contain']}` — {b['why']}"))
    return out


def _resolve_delegated(github_root: pathlib.Path, body: str) -> str:
    """Append the text of scripts/workflows a workflow delegates to (one hop).

    Without this, every thin workflow that calls a .py validator looks like it
    'mentions nothing' -- the dominant false positive in the advisory arm.
    """
    extra = []
    for ref in set(re.findall(r"[A-Za-z0-9._/-]+\.(?:py|sh)", body)):
        sub = read_artifact(github_root, ref)
        if sub:
            extra.append(sub)
    for ref in set(re.findall(r"uses:\s*[^\s]*/([A-Za-z0-9._-]+\.yml)", body)):
        sub = read_artifact(github_root, ref)
        if sub:
            extra.append(sub)
    return body + "\n".join(extra)


def check_c4_advisory(skill_files, github_root) -> list[Finding]:
    """ADVISORY (non-gating): the named enforcer exists but appears not to
    mention the rule's subject, so it may not check what the rule claims.

    Heuristic by construction: it follows only one delegation hop and matches
    on surface tokens, so it both over- and under-reports. Reviewed by a human,
    never gated. See "Known limits".
    """
    out = []
    for f in skill_files:
        for rid, block in split_rule_blocks(f.read_text(errors="replace")):
            for art, verb in _claims(block):
                body = read_artifact(github_root, art)
                if body is None:
                    continue  # existence is C2's job
                body = _resolve_delegated(github_root, body).lower()
                # Subjects: backticked file-like tokens the rule is ABOUT,
                # excluding the enforcer itself. A bare rule id is NOT a
                # subject -- mechanisms are not required to cite rule ids.
                subjects = {
                    s for s in SUBJECT_RE.findall(block)
                    if "." in s and s.lower() != art.lower()
                    and not s.endswith((".yml", ".py", ".sh"))
                }
                if not subjects:
                    continue
                missing = sorted(s for s in subjects if s.lower() not in body)
                if len(missing) == len(subjects):
                    out.append(Finding(
                        "C4?", rid, f,
                        f"`{art}` {verb} it, but mentions none of "
                        f"{missing[:4]} — verify it checks what the rule says"))
    return out


def check_c3(skill_files, schema: dict) -> list[Finding]:
    out = []
    for f in skill_files:
        text = f.read_text(errors="replace")
        blocks = dict(split_rule_blocks(text))
        for b in BOUND_BINDINGS:
            block = blocks.get(b["rule"])
            if not block:
                continue
            m = b["pattern"].search(block)
            if not m:
                continue
            lo, hi = int(m.group(1)), int(m.group(2))
            node = schema
            for k in b["schema_path"]:
                node = node.get(k, {})
            slo, shi = node.get(b["min_key"]), node.get(b["max_key"])
            if (slo, shi) != (lo, hi):
                out.append(Finding(
                    "C3", b["rule"], f,
                    f"rule states bound {lo}-{hi} but schema declares "
                    f"{slo}-{shi} ({'/'.join(b['schema_path'])}) — the schema "
                    f"is what CI enforces"))
    return out


def check_c3b(skill_files) -> list[Finding]:
    """GATE: a rule stating the same numeric bound twice must agree with itself.

    Suggested by ECO-CI1 2026-07-25 after [GH-REPO-023] turned out to be a
    THREE-way disagreement: the statement says 2-10, the schema example in the
    same file says 3-10, and metadata-schema.json declares 0-20. Adjudicating
    "the skill is canonical" is ambiguous until the skill agrees with itself.
    """
    out = []
    for f in skill_files:
        text = f.read_text(errors="replace")
        for b in BOUND_BINDINGS:
            rid = b["rule"]
            blocks = dict(split_rule_blocks(text))
            if rid not in blocks:
                continue
            m = b["pattern"].search(blocks[rid])
            if not m:
                continue
            stated = (int(m.group(1)), int(m.group(2)))
            # Any other "N-M entries per [RULE]" restatement in the same file.
            for om in re.finditer(
                    rf"(\d+)\s*-\s*(\d+)\s+entries per \[{re.escape(rid)}\]",
                    text):
                other = (int(om.group(1)), int(om.group(2)))
                if other != stated:
                    out.append(Finding(
                        "C3b", rid, f,
                        f"states bound {stated[0]}-{stated[1]} but restates it "
                        f"as {other[0]}-{other[1]} elsewhere in the same file — "
                        f"the rule contradicts itself"))
    return out


def run(skills_root: pathlib.Path, github_root: pathlib.Path,
        schema_path: pathlib.Path, workspace_root: pathlib.Path | None = None):
    skill_files = sorted(skills_root.rglob("*.md"))
    skill_files = [p for p in skill_files if ".git/" not in str(p)]
    if not skill_files:
        print(f"error: no .md files under {skills_root}", file=sys.stderr)
        raise SystemExit(2)
    schema = json.loads(schema_path.read_text()) if schema_path.is_file() else {}
    skips: list[str] = []
    gating = (check_c1(skill_files, github_root, workspace_root, skips)
              + check_c2(skill_files, github_root, workspace_root, skips)
              + check_c2b(skill_files, github_root)
              + check_c3(skill_files, schema)
              + check_c3b(skill_files))
    advisory = check_c4_advisory(skill_files, github_root)

    # Coverage. A validator that checked 3 things and found 3 is not the same
    # instrument as one that checked 200 and found 5; without this, a clean run
    # and a broken run print the same reassuring line.
    tags = claims = 0
    for f in skill_files:
        for _rid, block in split_rule_blocks(f.read_text(errors="replace")):
            tags += len([a for t in VERIFICATION_RE.findall(block)
                         for a in ARTIFACT_IN_TAG_RE.findall(t)])
            claims += len(list(_claims(block)))
    cov = {"files": len(skill_files), "verification_artifacts": tags,
           "prose_claims": claims, "claim_bindings": len(CLAIM_BINDINGS),
           "bound_bindings": len(BOUND_BINDINGS), "skipped": skips}
    return gating, advisory, cov


def main() -> int:
    here = pathlib.Path(__file__).resolve()
    default_github = here.parents[2]
    default_skills = default_github.parent / "Skills"
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills", type=pathlib.Path, default=default_skills)
    ap.add_argument("--github", type=pathlib.Path, default=default_github)
    ap.add_argument("--schema", type=pathlib.Path, default=None)
    ap.add_argument("--advisory", action="store_true",
                    help="also print non-gating heuristic findings")
    ap.add_argument("--workspace", type=pathlib.Path, default=None,
                    help="root holding sibling institute repos; citations like "
                         "`swift-institute/Scripts/x.sh` resolve against it. "
                         "Defaults to the .github repo's parent.")
    args = ap.parse_args()
    schema = args.schema or (args.github / "metadata-schema.json")
    workspace = args.workspace or args.github.resolve().parent

    gating, advisory, cov = run(args.skills, args.github, schema, workspace)
    print(f"[GH-REPO-063a] checked {cov['files']} skill files: "
          f"{cov['verification_artifacts']} VERIFICATION artifacts, "
          f"{cov['prose_claims']} prose claims, "
          f"{cov['claim_bindings']} bound claims, "
          f"{cov['bound_bindings']} bound numerics.")
    if cov["skipped"]:
        # Logged, never silent: an unresolvable citation is not a pass.
        print(f"[GH-REPO-063a] {len(cov['skipped'])} citation(s) NOT VERIFIED "
              f"(sibling repo absent from this checkout — absence here is not "
              f"evidence of deletion):")
        for s in cov["skipped"]:
            print(f"  - {s}")

    if args.advisory and advisory:
        print(f"[GH-REPO-063a] {len(advisory)} ADVISORY (non-gating, heuristic — "
              f"review by hand, do not treat as defects):")
        for f in advisory:
            print(f)
        print()

    if gating:
        print(f"[GH-REPO-063a] {len(gating)} rule-claim finding(s):")
        for f in gating:
            print(f)
        return 1
    # The clean line MUST carry the unverified count. "OK" beside a silent skip
    # list reads as "everything was checked", which is the vacuous-green shape
    # this validator exists to catch -- one level up. If coverage is bounded,
    # the bound has to be a number someone sees, not a line in a log.
    tail = []
    if cov["skipped"]:
        tail.append(f"{len(cov['skipped'])} NOT VERIFIED")
    if advisory:
        tail.append(f"{len(advisory)} advisory")
    suffix = f" ({', '.join(tail)})" if tail else ""
    print(f"[GH-REPO-063a] OK — all VERIFIABLE gated rule claims match their "
          f"mechanisms{suffix}.")
    if cov["skipped"]:
        print("[GH-REPO-063a] NOTE: green here does NOT mean those citations "
              "were checked. Deleting one of them would still pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
