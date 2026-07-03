#!/usr/bin/env python3
"""[GH-REPO-063] Schema <-> workflow settings-key consistency guard.

Asserts that the set of keys declared under `settings.properties` in
metadata-schema.json is identical to the set of `.settings.<key>` reads in
sync-metadata.yml. A key in one but not the other is a silent no-op: a
maintainer authoring it in a metadata.yaml gets no effect and no error.

Origin: the schema documented `defaultBranchRef` while the workflow consumed
`.settings.defaultBranch` (2026-07-03 settings-governance audit).

Usage:
  validate-schema-workflow-keys.py [SCHEMA_JSON SYNC_WORKFLOW_YML]
Defaults resolve relative to the swift-institute/.github repo root.
"""
import json
import pathlib
import re
import sys


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    schema_path = repo_root / "metadata-schema.json"
    workflow_path = repo_root / ".github" / "workflows" / "sync-metadata.yml"
    if len(sys.argv) == 3:
        schema_path, workflow_path = (pathlib.Path(p) for p in sys.argv[1:3])

    schema = json.loads(schema_path.read_text())
    schema_keys = set(schema["properties"]["settings"]["properties"].keys())
    workflow_keys = set(re.findall(r"\.settings\.([A-Za-z][A-Za-z0-9]*)",
                                   workflow_path.read_text()))

    only_schema = schema_keys - workflow_keys
    only_workflow = workflow_keys - schema_keys
    if only_schema or only_workflow:
        print("[GH-REPO-063] settings-key mismatch between schema and workflow:")
        if only_schema:
            print(f"  declared in {schema_path.name} but NOT read by "
                  f"{workflow_path.name}: {sorted(only_schema)}")
        if only_workflow:
            print(f"  read by {workflow_path.name} but NOT declared in "
                  f"{schema_path.name}: {sorted(only_workflow)}")
        return 1

    print(f"[GH-REPO-063] OK — {len(schema_keys)} settings keys consistent: "
          f"{sorted(schema_keys)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
