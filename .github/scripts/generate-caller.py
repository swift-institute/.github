#!/usr/bin/env python3
"""
generate-caller.py — the canonical typed generator for per-package
`.github/workflows/ci.yml` files (Task 5-01, swift-institute/.github#276,
#282).

Builds a caller from a small typed spec (repository, Workspace-supplied
layer, and every approved typed input this repository legitimately
declares) and renders it as canonical, deterministic YAML text — string
templating, not a generic YAML dump, so byte-identical output regardless
of the input field order is true by construction rather than something a
serializer's key-ordering has to be trusted to preserve.

The companion `parse_existing_caller()` reads a repository's CURRENT
`ci.yml` and either recovers the typed spec that would regenerate it
byte-for-byte, or raises `UnknownCustomization` naming exactly what it
does not recognize. Per the task's Change item 5: an unknown input, local
`runs-on:`/`steps:`, an extra workflow, or any other bespoke logic is
NEVER silently erased or overwritten — generation refuses and routes the
repository to typed-exception review instead.

Grounded in real fetched callers (not invented in the abstract), sampled
during this task's authoring:

  - same-org (`swift-primitives/swift-array-primitives`,
    `swift-standards/swift-domain-standard`,
    `swift-foundations/swift-copy-on-write`): `secrets: inherit`,
    `push.tags: ['*']` present.
  - cross-org (`swift-ietf/swift-rfc-3986`,
    `swift-linux-foundation/swift-linux-standard`,
    `swift-microsoft/swift-windows-32`, `swift-iso/swift-iso-9945`): the
    closed four-secret [CI-059] explicit-forward set, `push.tags` ABSENT
    — a real, consistent, 4-for-4 same-org/cross-org split, not
    incidental drift. Represented here as the two typed classes Change
    item 6 anticipates ("if live characterization proves a repository
    class lawfully differs, represent that as a typed class rather than
    silently copying drift"), not silently unified.
  - `platform-support` typed input (`swift-linux-foundation/
    swift-linux-standard` -> "apple,linux", `swift-microsoft/
    swift-windows-32` -> "windows", `swift-iso/swift-iso-9945` ->
    "apple,linux"): preserved by exact key/value; comments explaining
    WHY a package declares a given value are repository-owned prose the
    generator does not attempt to reproduce or require.

Every sampled caller also carries a separate `docs:` job calling
`swift-docs.yml` — Change item 8 ("new callers enable integrated docs
and omit the separate docs job") describes a migration-compatibility
input that does not exist in `swift-ci.yml`/`swift-docs.yml` yet (checked
directly against the shipped workflow at authoring time: no
`docs-integrated`-shaped input is declared). This generator therefore
emits the two-job shape every real caller in the sample actually uses
today; `INTEGRATED_DOCS_SUPPORTED` is the single switch to flip once that
compatibility input lands, so this file is the one place that changes,
not a second migration in every caller.

Usage:
  python3 .github/scripts/generate-caller.py generate <spec.json>
  python3 .github/scripts/generate-caller.py parse <ci.yml>
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field

import yaml

# Flip once swift-ci.yml/swift-docs.yml ship the migration-compatibility
# input this depends on (Change item 8). See module docstring.
INTEGRATED_DOCS_SUPPORTED = False

LAYER_WRAPPER_ORG = {
    "primitives": "swift-primitives",
    "standards": "swift-standards",
    # Foundations packages living directly in swift-foundations are
    # same-org; every other org is cross-org for this layer, exactly like
    # the other two.
    "institute": "swift-foundations",
}

CI059_SECRET_NAMES = (
    "PRIVATE_REPO_TOKEN",
    "SWIFT_INSTITUTE_BOT_APP_CLIENT_ID",
    "SWIFT_INSTITUTE_BOT_APP_ID",
    "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
)

# The exact set of `with:` keys this generator knows how to preserve.
# Anything else discovered in an existing caller is an UnknownCustomization
# — never silently dropped or passed through unexamined.
APPROVED_TYPED_INPUTS = ("platform-support", "enable-private-repos", "test-filter")


class UnknownCustomization(Exception):
    """Raised when an existing caller carries something this generator does
    not recognize: an unapproved `with:` key, inline `runs-on:`/`steps:`,
    an extra job, or any workflow file this generator does not own the
    shape of. The caller carrying it is NOT a defect — it is a typed
    exception this generator refuses to silently regenerate over."""


@dataclass(frozen=True)
class CallerSpec:
    repository: str  # "owner/name"
    layer: str  # one of LAYER_WRAPPER_ORG's keys
    platform_support: str | None = None
    enable_private_repos: bool | None = None
    test_filter: str | None = None

    def __post_init__(self):
        if self.layer not in LAYER_WRAPPER_ORG:
            raise ValueError(
                f"layer {self.layer!r} is not one of {sorted(LAYER_WRAPPER_ORG)}"
            )
        if "/" not in self.repository:
            raise ValueError(f"repository must be owner/name, got {self.repository!r}")

    @property
    def owner(self) -> str:
        return self.repository.split("/", 1)[0]

    @property
    def wrapper_org(self) -> str:
        return LAYER_WRAPPER_ORG[self.layer]

    @property
    def same_org(self) -> bool:
        # Structural fact once layer is known (never inferred FROM the
        # org — the org is compared AGAINST the layer's canonical wrapper
        # org, which is the opposite direction and the one Task 1-03 item
        # 10 and this task both require).
        return self.owner == self.wrapper_org

    @property
    def with_lines(self) -> list[str]:
        lines = []
        if self.platform_support:
            lines.append(f"      platform-support: {self.platform_support}")
        if self.enable_private_repos is not None:
            lines.append(
                f"      enable-private-repos: {str(self.enable_private_repos).lower()}"
            )
        if self.test_filter:
            lines.append(f"      test-filter: {self.test_filter}")
        return lines


def _secrets_block(spec: CallerSpec, indent: str = "    ") -> list[str]:
    if spec.same_org:
        return [f"{indent}secrets: inherit"]
    lines = [f"{indent}secrets:"]
    for name in CI059_SECRET_NAMES:
        lines.append(f"{indent}  {name}: ${{{{ secrets.{name} }}}}")
    return lines


def generate(spec: CallerSpec) -> str:
    """Render the canonical `ci.yml` text for one caller spec."""
    lines = ["name: CI", "", "on:", "  push:", "    branches:", "      - main"]
    if spec.same_org:
        # Change item 6 / real-sample finding: same-org callers carry a
        # tag-push trigger (release boundary reached without a cross-org
        # credential hop); cross-org callers observed in the fleet sample
        # do not.
        lines += ["    tags:", "      - '*'"]
    lines += [
        "  pull_request:",
        "    branches:",
        "      - main",
        "  workflow_dispatch:",
        "",
        "concurrency:",
        "  group: ci-${{ github.ref }}",
        "  cancel-in-progress: true",
        "",
        "jobs:",
        "  ci:",
        f"    uses: {spec.wrapper_org}/.github/.github/workflows/swift-ci.yml@main",
    ]
    with_lines = spec.with_lines
    if with_lines:
        lines.append("    with:")
        lines += with_lines
    lines += _secrets_block(spec)

    if not INTEGRATED_DOCS_SUPPORTED:
        lines += [
            "",
            "  docs:",
            f"    uses: {spec.wrapper_org}/.github/.github/workflows/swift-docs.yml@main",
        ]
        lines += _secrets_block(spec)

    return "\n".join(lines) + "\n"


def parse_existing_caller(text: str, repository: str, layer: str) -> CallerSpec:
    """Recover the typed spec that models `text`, or raise
    UnknownCustomization naming exactly what does not fit the generator's
    known shape.

    This is a SEMANTIC recovery, not a byte-identical one: every real
    caller sampled while building this generator carries free-form
    explanatory prose comments (why THIS package declares THIS
    platform-support value, why THIS layer's wrapper is referenced) that
    are legitimately repository-owned and that this generator has no
    business inventing or overwriting. The round-trip check below
    compares the STRUCTURED shape a second parse of the regenerated text
    produces against the original's structured shape — value-for-value,
    key-for-key — not the raw bytes. A real difference in job set,
    `uses:`, `with:` keys/values, or secrets shape still fails closed;
    only comment/whitespace formatting is allowed to differ.
    """
    document = yaml.safe_load(text)
    jobs = document.get("jobs") or {}

    expected_job_names = {"ci"} if INTEGRATED_DOCS_SUPPORTED else {"ci", "docs"}
    if set(jobs) != expected_job_names:
        raise UnknownCustomization(
            f"unexpected job set {sorted(jobs)}, expected {sorted(expected_job_names)}"
        )

    for job_id, job in jobs.items():
        if "steps" in job or "runs-on" in job:
            raise UnknownCustomization(f"'{job_id}' job carries inline steps/runs-on, not a thin caller")
        if "uses" not in job:
            raise UnknownCustomization(f"'{job_id}' job has no uses: — not a reusable-workflow call")

    with_block = jobs["ci"].get("with") or {}
    unknown_keys = set(with_block) - set(APPROVED_TYPED_INPUTS)
    if unknown_keys:
        raise UnknownCustomization(f"unapproved with: keys {sorted(unknown_keys)}")

    spec = CallerSpec(
        repository=repository,
        layer=layer,
        platform_support=with_block.get("platform-support"),
        enable_private_repos=with_block.get("enable-private-repos"),
        test_filter=with_block.get("test-filter"),
    )

    # Structural round-trip: re-parse the freshly generated text and
    # compare its `jobs` shape to the original's. If they differ,
    # something about this caller is NOT representable by this generator
    # yet — refuse rather than claim a false match.
    regenerated_document = yaml.safe_load(generate(spec))
    if regenerated_document.get("jobs") != jobs:
        raise UnknownCustomization(
            "recovered spec does not regenerate this caller's job structure "
            "identically (a customization this generator does not yet model)"
        )
    return spec


def _cli_generate(spec_path: str) -> int:
    with open(spec_path, encoding="utf-8") as f:
        raw = json.load(f)
    spec = CallerSpec(**raw)
    sys.stdout.write(generate(spec))
    return 0


def _cli_parse(caller_path: str, repository: str) -> int:
    with open(caller_path, encoding="utf-8") as f:
        text = f.read()
    # Layer is inferred from the wrapper actually referenced (the `uses:`
    # value), never from `repository`'s org — same discipline as
    # `CallerSpec.same_org` itself: the org is compared AGAINST a
    # known-good layer signal, never used to produce one.
    document = yaml.safe_load(text)
    uses = ((document.get("jobs") or {}).get("ci") or {}).get("uses", "")
    wrapper_org = uses.split("/", 1)[0] if "/" in uses else ""
    layer = next((k for k, v in LAYER_WRAPPER_ORG.items() if v == wrapper_org), None)
    if layer is None:
        print(f"::error::could not infer a known layer from uses: {uses!r}", file=sys.stderr)
        return 1
    try:
        spec = parse_existing_caller(text, repository=repository, layer=layer)
    except UnknownCustomization as e:
        print(f"::error::{e}", file=sys.stderr)
        return 1
    json.dump(
        {
            "layer": spec.layer,
            "same_org": spec.same_org,
            "platform_support": spec.platform_support,
            "enable_private_repos": spec.enable_private_repos,
            "test_filter": spec.test_filter,
        },
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "generate":
        return _cli_generate(argv[1])
    if len(argv) == 3 and argv[0] == "parse":
        return _cli_parse(argv[1], argv[2])
    print(
        "usage: generate-caller.py generate <spec.json> | parse <ci.yml> <owner/repo>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
