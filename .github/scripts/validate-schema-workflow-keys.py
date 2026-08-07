#!/usr/bin/env python3
# RETAINED (F16 residual sweep, swift-institute/.github#404): no port class
# owns this guard. It has no Swift owner and TWO live unconditional callers
# (validate-schema-correspondence.yml and validate-github-metadata.yml), and
# it reads both metadata-schema.json and validate-readme.py's source text. A
# faithful port is not S-class: the correspondence it checks spans the schema,
# the README validator's constants, and the settings keys. Follow-up owner:
# GH-REPO-063 re-specification, which must be re-sequenced to follow the
# validate-readme.py port rather than precede it (see #404). Do not delete.
"""[GH-REPO-063] metadata-schema.json <-> consumer correspondence guard.

A key or enum value the schema declares but no consumer reads is a silent
no-op: the maintainer who authors it in a metadata.yaml gets no effect and no
error. This guard asserts that every declared thing has a reader, and every
reader has a declaration.

Origin: the schema documented `defaultBranchRef` while the workflow consumed
`.settings.defaultBranch` (2026-07-03 settings-governance audit).

Two correspondences are checked. They are separate because the consumers are
different KINDS of artifact and are read differently:

  settings  the `settings.properties` key set, against `.settings.<key>` reads
            in sync-metadata.yml. Textual: the workflow reads these through
            `jq`, so there is no structure to parse.

  readme    the `readme.exempt` and `readme.family` enums, against the
            EXEMPTIONS and FAMILIES tuples in validate-readme.py. Structural:
            the consumer is Python, so the constants are extracted with `ast`
            rather than by regex, and are looked up BY NAME.

The `readme` half was added 2026-07-28. Before that this guard saw only the
`settings` block and never opened validate-readme.py at all, so a `readme`
enum value with no reader had NO machine check whatsoever -- the correspondence
was maintained by a comment asking the next editor to remember. That is the
same shape as the inert gates in swift-institute/Internal's
VALIDATOR-DISCIPLINE.md: a control that looks like coverage and provides none.

FAILING CLOSED. Every way of not-knowing is a finding, not a pass:

  - a schema block is missing or is not an object;
  - an expected enum is missing, or is not a list of strings;
  - an expected constant is absent from validate-readme.py, is not a
    module-level assignment, or is not a tuple/list of string literals.

An earlier draft returned "consistent" when it could not find a constant,
which would have made a rename of EXEMPTIONS read as agreement.

Usage:
  validate-schema-workflow-keys.py [SCHEMA_JSON SYNC_WORKFLOW_YML [README_PY]]
Defaults resolve relative to the swift-institute/.github repo root.
"""
from __future__ import annotations

import ast
import json
import pathlib
import re
import sys


def literal_string_sequence(node: ast.AST) -> list[str] | None:
    """Return the string elements of a tuple/list literal, else None.

    None means "could not establish", and every caller treats that as a
    finding. A partially-literal sequence (an f-string, a name, a splat) is
    rejected whole: half an answer here is indistinguishable from agreement.
    """
    if not isinstance(node, (ast.Tuple, ast.List)):
        return None
    values: list[str] = []
    for element in node.elts:
        if not isinstance(element, ast.Constant) or not isinstance(element.value, str):
            return None
        values.append(element.value)
    return values


def module_level_string_constants(
    source: str, names: set[str]
) -> dict[str, list[str] | None]:
    """Extract module-level `NAME = ("a", "b")` assignments for `names`.

    Parsed rather than executed: importing validate-readme.py would run its
    module body (and its PyYAML hard-dependency check), which is a needless
    way for a consistency guard to fail for an unrelated reason.

    A name that is absent, assigned at non-module level, or assigned something
    other than a tuple/list of string literals maps to None -- the caller
    reports that rather than skipping it.
    """
    found: dict[str, list[str] | None] = {name: None for name in names}
    seen: set[str] = set()
    tree = ast.parse(source)
    for statement in tree.body:  # module level only, deliberately
        if not isinstance(statement, ast.Assign):
            continue
        for target in statement.targets:
            if isinstance(target, ast.Name) and target.id in names:
                seen.add(target.id)
                found[target.id] = literal_string_sequence(statement.value)
    for name in names - seen:
        found[name] = None
    return found


def schema_enum(schema: dict, block: str, field: str) -> list[str] | None:
    """Return the enum declared at `properties.<block>.properties.<field>`."""
    properties = schema.get("properties")
    if not isinstance(properties, dict):
        return None
    block_schema = properties.get(block)
    if not isinstance(block_schema, dict):
        return None
    block_properties = block_schema.get("properties")
    if not isinstance(block_properties, dict):
        return None
    field_schema = block_properties.get(field)
    if not isinstance(field_schema, dict):
        return None
    enum = field_schema.get("enum")
    if not isinstance(enum, list) or not all(isinstance(v, str) for v in enum):
        return None
    return enum


def check_settings(schema: dict, schema_name: str,
                   workflow_path: pathlib.Path) -> list[str]:
    """settings.properties keys <-> `.settings.<key>` reads in the workflow."""
    problems: list[str] = []
    properties = schema.get("properties", {})
    settings = properties.get("settings") if isinstance(properties, dict) else None
    declared = settings.get("properties") if isinstance(settings, dict) else None
    if not isinstance(declared, dict):
        return [f"{schema_name} has no `settings.properties` object to compare "
                f"-- the guard cannot conclude, so this is a finding, not a pass."]

    schema_keys = set(declared)
    workflow_keys = set(re.findall(r"\.settings\.([A-Za-z][A-Za-z0-9]*)",
                                   workflow_path.read_text()))
    only_schema = schema_keys - workflow_keys
    only_workflow = workflow_keys - schema_keys
    if only_schema:
        problems.append(
            f"declared in {schema_name} `settings` but NOT read by "
            f"{workflow_path.name}: {sorted(only_schema)}")
    if only_workflow:
        problems.append(
            f"read by {workflow_path.name} but NOT declared in {schema_name} "
            f"`settings`: {sorted(only_workflow)}")
    if not problems:
        print(f"[GH-REPO-063] settings OK -- {len(schema_keys)} keys consistent "
              f"with {workflow_path.name}: {sorted(schema_keys)}")
    return problems


def check_readme(schema: dict, schema_name: str,
                 readme_validator_path: pathlib.Path) -> list[str]:
    """readme.{exempt,family} enums <-> EXEMPTIONS/FAMILIES in the validator."""
    problems: list[str] = []
    pairs = (("exempt", "EXEMPTIONS"), ("family", "FAMILIES"))
    constants = module_level_string_constants(
        readme_validator_path.read_text(),
        {constant for _, constant in pairs},
    )
    consumer = readme_validator_path.name

    for field, constant in pairs:
        declared = schema_enum(schema, "readme", field)
        read = constants[constant]
        if declared is None:
            problems.append(
                f"{schema_name} `readme.{field}` declares no string enum -- "
                f"cannot compare against {consumer} `{constant}`.")
            continue
        if read is None:
            problems.append(
                f"{consumer} has no module-level `{constant}` assigned a tuple "
                f"of string literals -- cannot compare against {schema_name} "
                f"`readme.{field}`. If it was renamed or made computed, update "
                f"this guard rather than removing the constant.")
            continue
        only_schema = sorted(set(declared) - set(read))
        only_consumer = sorted(set(read) - set(declared))
        if only_schema:
            problems.append(
                f"declared in {schema_name} `readme.{field}` enum but NOT "
                f"handled by {consumer} `{constant}`: {only_schema} -- "
                f"authoring one of these in a metadata.yaml would be a silent "
                f"no-op.")
        if only_consumer:
            problems.append(
                f"handled by {consumer} `{constant}` but NOT declared in "
                f"{schema_name} `readme.{field}` enum: {only_consumer} -- "
                f"schema validation would reject a value the validator "
                f"accepts.")
        if not only_schema and not only_consumer:
            print(f"[GH-REPO-063] readme.{field} OK -- {len(declared)} value(s) "
                  f"consistent with {consumer} `{constant}`: {sorted(declared)}")
    return problems


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    schema_path = repo_root / "metadata-schema.json"
    workflow_path = repo_root / ".github" / "workflows" / "sync-metadata.yml"
    readme_validator_path = repo_root / ".github" / "scripts" / "validate-readme.py"
    if len(sys.argv) >= 3:
        schema_path = pathlib.Path(sys.argv[1])
        workflow_path = pathlib.Path(sys.argv[2])
    if len(sys.argv) == 4:
        readme_validator_path = pathlib.Path(sys.argv[3])
    if len(sys.argv) > 4:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        return 2

    schema = json.loads(schema_path.read_text())
    problems = check_settings(schema, schema_path.name, workflow_path)
    problems += check_readme(schema, schema_path.name, readme_validator_path)

    if problems:
        print("[GH-REPO-063] schema<->consumer correspondence mismatch:")
        for problem in problems:
            print(f"  {problem}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
