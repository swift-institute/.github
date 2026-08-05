#!/usr/bin/env python3
"""census-generator.py — FT1 non-Swift executable census (Goal #358, FT1 #361).

Regenerates the sixteen-field non-Swift executable census from live heads.
The parallel review's census CSV was produced in its read-only venue and not
committed; FT1 freezes this regenerated census as the canonical root.
Evidence tooling; #113-exempt (census/receipt document generator, no
workflow or product semantics).

Coordinate kinds:
  file               one non-Swift executable/semantic file
  run-block          one `run:` block in a workflow or action
  expression         one ${{ ... }} actions expression
  uses-edge          one `uses:` reference
  command-reference  one leading executable token on a run-block line

Sixteen fields per row (census schema 1):
  censusVersion, repository, headSha, path, coordinateKind, coordinateId,
  line, engine, excerptSha256, family, intendedOwner, disposition,
  measurement, cause, generatedBy, notes
"""
import csv
import hashlib
import json
import os
import re
import subprocess
import sys

EXPR = re.compile(r"\$\{\{.*?\}\}", re.S)
USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(\S+)", re.M)
RUN = re.compile(r"^(\s*)run:\s*(\||>|\|-|>-)?", re.M)
CMD = re.compile(r"^\s*([A-Za-z0-9_.\/-]+)")
SKIP_CMD = {"if", "then", "else", "fi", "for", "do", "done", "while", "case",
            "esac", "echo", "printf", "exit", "set", "cd", "export", "shift",
            "local", "return", "true", "false", "read", "trap", "wait", "{",
            "}", "elif", "EOF"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def head(repo_dir: str) -> str:
    return subprocess.check_output(
        ["git", "-C", repo_dir, "rev-parse", "origin/main"], text=True).strip()


def family_for(path: str) -> str:
    if "/workflows/" in path and path.endswith("swift-ci.yml"):
        return "universal-or-wrapper-workflow"
    if "/workflows/" in path:
        return "central-workflow"
    if "/actions/" in path:
        return "composite-action"
    if "/scripts/tests/" in path:
        return "script-test"
    if "/scripts/" in path:
        return "semantic-script"
    return "other"


OWNER = {
    "universal-or-wrapper-workflow": "CI Contract host projection (F12/F15)",
    "central-workflow": "named Swift owners (F2-F16)",
    "composite-action": "Workspace bootstrap + named owners (F10/F16)",
    "semantic-script": "named Swift owners (F2-F16)",
    "script-test": "owner test suites (F16)",
    "other": "FT1 adjudication",
}


def rows_for_file(repo: str, sha: str, root: str, rel: str, out: list) -> None:
    path = os.path.join(root, rel)
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8", errors="replace")
    fam = family_for("/" + rel)
    base = {
        "censusVersion": "1", "repository": repo, "headSha": sha,
        "path": rel, "family": fam, "intendedOwner": OWNER[fam],
        "disposition": "reduce", "measurement": "MEASURED", "cause": "",
        "generatedBy": "census-generator.py", "notes": "",
    }
    ext = rel.rsplit(".", 1)[-1]
    engine = {"py": "python", "sh": "shell", "yml": "actions-yaml",
              "yaml": "actions-yaml"}.get(ext, "other")
    out.append({**base, "coordinateKind": "file", "coordinateId": f"file:{rel}",
                "line": 1, "engine": engine, "excerptSha256": sha256(raw)})
    if engine != "actions-yaml":
        return
    for i, m in enumerate(EXPR.finditer(text)):
        line = text[:m.start()].count("\n") + 1
        out.append({**base, "coordinateKind": "expression",
                    "coordinateId": f"expr:{rel}:{i}", "line": line,
                    "engine": "actions-expression",
                    "excerptSha256": sha256(m.group(0).encode())})
    for i, m in enumerate(USES.finditer(text)):
        line = text[:m.start()].count("\n") + 1
        out.append({**base, "coordinateKind": "uses-edge",
                    "coordinateId": f"uses:{rel}:{i}", "line": line,
                    "engine": "actions-yaml",
                    "excerptSha256": sha256(m.group(1).encode()),
                    "notes": m.group(1)})
    lines = text.split("\n")
    for i, m in enumerate(RUN.finditer(text)):
        line = text[:m.start()].count("\n") + 1
        indent = len(m.group(1))
        block = []
        if m.group(2):
            j = line
            while j < len(lines):
                ln = lines[j]
                if ln.strip() and (len(ln) - len(ln.lstrip())) <= indent:
                    break
                block.append(ln)
                j += 1
        else:
            block = [text[m.end():].split("\n", 1)[0]]
        body = "\n".join(block)
        out.append({**base, "coordinateKind": "run-block",
                    "coordinateId": f"run:{rel}:{i}", "line": line,
                    "engine": "shell",
                    "excerptSha256": sha256(body.encode())})
        for k, bl in enumerate(block):
            c = CMD.match(bl)
            if c and c.group(1) not in SKIP_CMD and not bl.strip().startswith("#"):
                out.append({**base, "coordinateKind": "command-reference",
                            "coordinateId": f"cmd:{rel}:{i}:{k}",
                            "line": line + 1 + k, "engine": "shell",
                            "excerptSha256": sha256(c.group(1).encode()),
                            "notes": c.group(1)})


def main() -> None:
    ws = "/Users/coen/Developer/coenttb/swift-institute"
    repos = [
        ("swift-institute/.github", os.path.join(ws, ".github")),
        ("swift-primitives/.github", os.path.join(ws, "swift-primitives/.github")),
        ("swift-standards/.github", os.path.join(ws, "swift-standards/.github")),
        ("swift-foundations/.github", os.path.join(ws, "swift-foundations/.github")),
    ]
    out: list[dict] = []
    for repo, root in repos:
        sha = head(root)
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, ".github")):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in sorted(filenames):
                if not name.endswith((".yml", ".yaml", ".py", ".sh")):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                rows_for_file(repo, sha, root, rel, out)
    # Leaf caller family: 449 generated ci.yml files, byte-uniform per
    # generator revision; counted as one family row bound to the terminal
    # census (not re-read per repository here).
    out.append({
        "censusVersion": "1", "repository": "17-organization fleet",
        "headSha": "per-repo (review-inputs/reclosure/v1-per-root.json)",
        "path": ".github/workflows/ci.yml", "coordinateKind": "file",
        "coordinateId": "family:leaf-callers", "line": 1,
        "engine": "actions-yaml", "excerptSha256": "",
        "family": "generated-leaf-caller",
        "intendedOwner": "Repository Policy (generated projection; F13/F14)",
        "disposition": "regenerate", "measurement": "MEASURED",
        "cause": "", "generatedBy": "census-generator.py",
        "notes": "449 callers; per-repo heads and caller blob SHAs frozen in v1-per-root.json (digest 56d8309c...)"})
    # UNMEASURED sentinels.
    sentinels = [
        ("private-ordinary-repositories",
         "~182 private ordinary repositories: workflow bytes not enumerated in this public census",
         "R33 posture; private coordinates stay opaque in public artifacts"),
        ("private-verification-private-side",
         "private verifier repository workflow/scripts not enumerated here",
         "split-credential boundary; owned by Private.Verification at F8"),
        ("workspace-repo-automation",
         "swift-institute/Workspace repository automation not enumerated in this census pass",
         "Workspace owns its own package facts; F2 binds its API"),
        ("skills-repo-automation",
         "swift-institute/Skills repository automation not enumerated in this census pass",
         "F17 owns Skills correspondence"),
        ("swift-linter-repo-automation",
         "swift-foundations/swift-linter repository automation not enumerated in this census pass",
         "F9 owns linter parity"),
    ]
    for name, detail, cause in sentinels:
        out.append({
            "censusVersion": "1", "repository": "sentinel", "headSha": "",
            "path": "", "coordinateKind": "family", "coordinateId": f"sentinel:{name}",
            "line": 0, "engine": "", "excerptSha256": "", "family": name,
            "intendedOwner": "typed at owning transaction", "disposition": "sentinel",
            "measurement": "UNMEASURED", "cause": cause,
            "generatedBy": "census-generator.py", "notes": detail})

    fields = ["censusVersion", "repository", "headSha", "path",
              "coordinateKind", "coordinateId", "line", "engine",
              "excerptSha256", "family", "intendedOwner", "disposition",
              "measurement", "cause", "generatedBy", "notes"]
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "non-swift-executable-inventory.csv")
    with open(dest, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for row in out:
            w.writerow(row)
    counts: dict[str, int] = {}
    for row in out:
        counts[row["coordinateKind"]] = counts.get(row["coordinateKind"], 0) + 1
    print(json.dumps({"total": len(out), "byKind": counts,
                      "csvSha256": sha256(open(dest, "rb").read())},
                     indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
