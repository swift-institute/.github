#!/usr/bin/env python3
"""generate-caller.py — the canonical typed generator for per-package
`.github/workflows/ci.yml` files (Task 5-01 → TX2, swift-institute/.github#276,
#282; CI/CD Completion Programme §5.1/§8.8).

TERMINAL FORM (TX6 pass A, "integrated docs bridge"). This generator now
emits the terminal caller the Completion Programme §5.1 prescribes for
every ordinary package repository:

  - exactly ONE `ci` job calling the semantic layer wrapper `@main`;
  - `integrated-docs: true` (the [temp-integrated-docs-4-01] bridge input
    — TX8 elides it once TX7 makes central docs unconditional);
  - NO separate `docs:` job (the universal chain runs DocC exactly once);
  - canonical events: push `main` + tags `'*'` (all ordinary classes,
    same-org and cross-org — §5.1 "same canonical contract"),
    pull_request `main`, workflow_dispatch;
  - top-level `permissions: actions: read / contents: read`;
  - concurrency `ci-${{ github.ref }}`, cancel-in-progress;
  - `secrets: inherit` same-org, the closed CI-059 four-secret forward
    set cross-org.

The companion `parse_existing_caller()` reads a repository's CURRENT
`ci.yml` — either the legacy two-job (`ci` + `docs`) form or an
already-terminal single-job form — and recovers the typed spec, or raises
`UnknownCustomization` naming exactly what it does not recognize. A
legacy caller's `docs:` job `with:` overrides are recovered onto the
spec's `docs-*` pass-through inputs (the wrapper forwards them verbatim
to the universal's nested docs call). An unknown input, inline
`runs-on:`/`steps:`, an extra job, a cross-wrapper docs reference, or
any other bespoke logic is NEVER silently erased — generation refuses
and routes the repository to typed-exception review instead.

Usage:
  python3 .github/scripts/generate-caller.py generate <spec.json>
  python3 .github/scripts/generate-caller.py parse <ci.yml> <owner/repo>
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass

import yaml

# The migration-compatibility docs contract is live in swift-ci.yml and all
# three layer wrappers ([temp-integrated-docs-4-01]); the terminal caller
# passes `integrated-docs: true` until TX8 elides it after TX7.
INTEGRATED_DOCS_SUPPORTED = True

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

# The exact set of caller-supplied `with:` keys this generator preserves,
# in canonical emission order. `integrated-docs` is generator-owned (always
# emitted `true`), never caller-supplied state. Anything else discovered in
# an existing caller is an UnknownCustomization — never silently dropped.
APPROVED_TYPED_INPUTS = (
    "platform-support",
    "embedded-target",
    "swift-version",
    "enable-private-repos",
    "test-filter",
    "docs-umbrella-module",
    "docs-umbrella-display-name",
    "docs-umbrella-bundle-id",
    "docs-umbrella-docc-path",
    "docs-exclude-modules",
    "docs-swift-version",
)

# Legacy separate-docs-job `with:` keys → the terminal caller's `docs-*`
# pass-through inputs on the single `ci` job (the wrapper forwards each
# verbatim into the universal's nested swift-docs.yml call).
LEGACY_DOCS_INPUT_MAP = {
    "umbrella-module": "docs-umbrella-module",
    "umbrella-display-name": "docs-umbrella-display-name",
    "umbrella-bundle-id": "docs-umbrella-bundle-id",
    "umbrella-docc-path": "docs-umbrella-docc-path",
    "exclude-modules": "docs-exclude-modules",
    "swift-version": "docs-swift-version",
}

_SPEC_FIELD_FOR_INPUT = {key: key.replace("-", "_") for key in APPROVED_TYPED_INPUTS}


class UnknownCustomization(Exception):
    """Raised when an existing caller carries something this generator does
    not recognize: an unapproved `with:` key, inline `runs-on:`/`steps:`,
    an extra job, a cross-wrapper docs reference, or any workflow shape
    this generator does not own. The caller carrying it is NOT a defect —
    it is a typed exception this generator refuses to silently regenerate
    over."""


@dataclass(frozen=True)
class CallerSpec:
    repository: str  # "owner/name"
    layer: str  # one of LAYER_WRAPPER_ORG's keys
    platform_support: str | None = None
    embedded_target: str | None = None
    swift_version: str | None = None
    enable_private_repos: bool | None = None
    test_filter: str | None = None
    docs_umbrella_module: str | None = None
    docs_umbrella_display_name: str | None = None
    docs_umbrella_bundle_id: str | None = None
    docs_umbrella_docc_path: str | None = None
    docs_exclude_modules: str | None = None
    docs_swift_version: str | None = None

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
        # 10 and TX2 both require).
        return self.owner == self.wrapper_org

    @property
    def with_lines(self) -> list[str]:
        # `integrated-docs: true` is unconditional in the terminal bridge
        # form and leads the block; caller-preserved typed inputs follow
        # in canonical APPROVED_TYPED_INPUTS order.
        lines = ["      integrated-docs: true"]
        for key in APPROVED_TYPED_INPUTS:
            value = getattr(self, _SPEC_FIELD_FOR_INPUT[key])
            if value is None or value == "":
                continue
            if isinstance(value, bool):
                rendered = str(value).lower()
            else:
                rendered = str(value)
            lines.append(f"      {key}: {rendered}")
        return lines


def _secrets_block(spec: CallerSpec, indent: str = "    ") -> list[str]:
    if spec.same_org:
        return [f"{indent}secrets: inherit"]
    lines = [f"{indent}secrets:"]
    for name in CI059_SECRET_NAMES:
        lines.append(f"{indent}  {name}: ${{{{ secrets.{name} }}}}")
    return lines


def generate(spec: CallerSpec) -> str:
    """Render the canonical terminal `ci.yml` text for one caller spec."""
    lines = [
        "name: CI",
        "",
        "on:",
        "  push:",
        "    branches:",
        "      - main",
        "    tags:",
        "      - '*'",
        "  pull_request:",
        "    branches:",
        "      - main",
        "  workflow_dispatch:",
        "",
        "permissions:",
        "  actions: read",
        "  contents: read",
        "",
        "concurrency:",
        "  group: ci-${{ github.ref }}",
        "  cancel-in-progress: true",
        "",
        "jobs:",
        "  ci:",
        f"    uses: {spec.wrapper_org}/.github/.github/workflows/swift-ci.yml@main",
        "    with:",
    ]
    lines += spec.with_lines
    lines += _secrets_block(spec)
    return "\n".join(lines) + "\n"


def _job_uses_or_raise(job_id: str, job: dict) -> str:
    if "steps" in job or "runs-on" in job:
        raise UnknownCustomization(
            f"'{job_id}' job carries inline steps/runs-on, not a thin caller"
        )
    if "uses" not in job:
        raise UnknownCustomization(
            f"'{job_id}' job has no uses: — not a reusable-workflow call"
        )
    return job["uses"]


def parse_existing_caller(text: str, repository: str, layer: str) -> CallerSpec:
    """Recover the typed spec that models `text`, or raise
    UnknownCustomization naming exactly what does not fit.

    Two admissible input shapes:

      - legacy two-job (`ci` + separate `docs`): the docs job must call
        the SAME wrapper org's swift-docs.yml; its `with:` overrides are
        mapped onto the spec's `docs-*` inputs;
      - terminal single-job (`ci` with `integrated-docs: true`): already
        this generator's own output shape; parsed for idempotent resume.

    Comment/whitespace formatting is allowed to differ; a real difference
    in job set, `uses:`, `with:` keys/values, or secrets shape fails
    closed."""
    document = yaml.safe_load(text)
    jobs = document.get("jobs") or {}
    wrapper_org = LAYER_WRAPPER_ORG[layer]

    if set(jobs) == {"ci", "docs"}:
        legacy = True
    elif set(jobs) == {"ci"}:
        legacy = False
    else:
        raise UnknownCustomization(
            f"unexpected job set {sorted(jobs)}, expected ['ci'] or ['ci', 'docs']"
        )

    ci_uses = _job_uses_or_raise("ci", jobs["ci"])
    expected_ci_uses = f"{wrapper_org}/.github/.github/workflows/swift-ci.yml@main"
    if ci_uses != expected_ci_uses:
        raise UnknownCustomization(
            f"ci uses {ci_uses!r}, expected {expected_ci_uses!r} for layer {layer!r}"
        )

    fields: dict[str, object] = {}
    with_block = dict(jobs["ci"].get("with") or {})
    # `integrated-docs` in an existing caller is the bridge input itself,
    # not caller state — accept `true`, refuse anything else.
    if "integrated-docs" in with_block:
        if with_block.pop("integrated-docs") is not True:
            raise UnknownCustomization("integrated-docs is present but not true")
    unknown_keys = set(with_block) - set(APPROVED_TYPED_INPUTS)
    if unknown_keys:
        raise UnknownCustomization(f"unapproved with: keys {sorted(unknown_keys)}")
    for key, value in with_block.items():
        fields[_SPEC_FIELD_FOR_INPUT[key]] = value

    if legacy:
        docs_uses = _job_uses_or_raise("docs", jobs["docs"])
        expected_docs_uses = (
            f"{wrapper_org}/.github/.github/workflows/swift-docs.yml@main"
        )
        if docs_uses != expected_docs_uses:
            raise UnknownCustomization(
                f"docs uses {docs_uses!r}, expected {expected_docs_uses!r} "
                f"(cross-wrapper docs routes are typed exceptions)"
            )
        docs_with = dict(jobs["docs"].get("with") or {})
        unknown_docs_keys = set(docs_with) - set(LEGACY_DOCS_INPUT_MAP)
        if unknown_docs_keys:
            raise UnknownCustomization(
                f"unapproved docs with: keys {sorted(unknown_docs_keys)}"
            )
        for key, value in docs_with.items():
            terminal_key = LEGACY_DOCS_INPUT_MAP[key]
            field = _SPEC_FIELD_FOR_INPUT[terminal_key]
            if field in fields and fields[field] != value:
                raise UnknownCustomization(
                    f"docs job {key!r} conflicts with ci job {terminal_key!r}"
                )
            fields[field] = value

    spec = CallerSpec(repository=repository, layer=layer, **fields)

    # Structural round-trip on the TERMINAL regeneration: re-parse the
    # freshly generated text and require its recovered spec to equal this
    # one. (Byte equality with a LEGACY input is impossible by design —
    # the terminal form is the point — so the invariant is spec-level.)
    regenerated = yaml.safe_load(generate(spec))
    regenerated_jobs = regenerated.get("jobs") or {}
    if not legacy:
        # The bridge input is generator-owned: normalize its (lawful)
        # absence in the input before demanding structural equality.
        normalized = {"ci": dict(jobs["ci"])}
        ci_with = dict(normalized["ci"].get("with") or {})
        ci_with["integrated-docs"] = True
        normalized["ci"]["with"] = ci_with
        if regenerated_jobs != normalized:
            raise UnknownCustomization(
                "single-job caller does not match the canonical terminal shape "
                "(a customization this generator does not yet model)"
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
    payload = {"layer": spec.layer, "same_org": spec.same_org}
    for key in APPROVED_TYPED_INPUTS:
        payload[_SPEC_FIELD_FOR_INPUT[key]] = getattr(spec, _SPEC_FIELD_FOR_INPUT[key])
    json.dump(payload, sys.stdout, indent=2)
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
