#!/usr/bin/env python3
"""validate-github-metadata.py — JSON-Schema validate a repo's metadata.yaml.

Wave 2b finalization (2026-05-10) — companion to validate-github-metadata.yml.
Loads `swift-institute/.github/metadata-schema.json` and validates the given
repo's `.github/metadata.yaml` against it. Emits one TSV row per finding:
    <repo>\t<rule-id>\t<message>

Rule IDs are derived from the JSON-Schema validation error path. The schema
itself encodes the underlying institutional rule citations ([GH-REPO-020],
[GH-REPO-021], [GH-REPO-022], [GH-REPO-031], etc.) in description fields.

Provenance: Skills/github-repository [GH-REPO-021]; HANDOFF-wave-2b-finalization.md
Decision 6 architectural pivot.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("# error: PyYAML not installed", file=sys.stderr)
    sys.exit(2)

try:
    import jsonschema
except ImportError:
    print("# error: jsonschema not installed (pip install jsonschema)", file=sys.stderr)
    sys.exit(2)


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def validate_metadata(repo: str, metadata_path: Path, schema: dict) -> int:
    try:
        with metadata_path.open() as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        emit(repo, "metadata-missing",
             f"{metadata_path}: file not found")
        return 1
    except yaml.YAMLError as e:
        emit(repo, "metadata-malformed",
             f"{metadata_path}: YAML parse error — {e}")
        return 1

    if data is None:
        # Empty file. Allowed at present.
        return 0
    if not isinstance(data, dict):
        emit(repo, "metadata-shape",
             f"{metadata_path}: top-level value must be a mapping; got {type(data).__name__}")
        return 1

    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
    findings = 0
    for err in errors:
        path = "/".join(str(p) for p in err.path) or "/"
        rule_id = "GH-REPO-021"
        if "topics" in [str(p) for p in err.path]:
            rule_id = "GH-REPO-021-or-022"
        elif "description" in [str(p) for p in err.path]:
            rule_id = "GH-REPO-011"
        elif "homepage" in [str(p) for p in err.path]:
            rule_id = "GH-REPO-030-or-031"
        elif "readme" in [str(p) for p in err.path]:
            rule_id = "README-family"
        emit(repo, rule_id,
             f"{path}: {err.message[:200]}")
        findings += 1
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("usage: validate-github-metadata.py <repo-name> <metadata-yaml> <schema-json>",
              file=sys.stderr)
        return 2
    repo = argv[1]
    metadata_path = Path(argv[2])
    schema_path = Path(argv[3])
    try:
        with schema_path.open() as f:
            schema = json.load(f)
    except Exception as e:
        emit(repo, "schema-load-failed", f"{schema_path}: {e}")
        return 2
    findings = validate_metadata(repo, metadata_path, schema)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
