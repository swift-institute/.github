# Synthetic SKILL.md — edge/skills-cross-deprecated-skipped fixture.
#
# Intentionally does NOT contain `[CI-EXAMPLE-DEPRECATED]`. Check 3 must
# stay silent because the manifest entry for CI-EXAMPLE-DEPRECATED has
# status=deprecated (not active) — outside the check 3 scope filter.

### [CI-EXAMPLE-OTHER] Another Rule

**Statement**: An unrelated rule, present here so SKILL.md is non-empty
and parseable by the validator. Note: CI-EXAMPLE-OTHER is itself NOT
declared in the manifest, so check 3 does not look for it — only
manifest entries drive check 3 lookups, not arbitrary SKILL.md citations.
