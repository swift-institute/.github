# Synthetic SKILL.md — fail/active-rule-id-missing-from-skills fixture.
#
# Cites `WF validate-foo.py` (so check 1 stays silent) but does NOT contain
# `[CI-EXAMPLE-001]`. The binding validator's check 3 (manifest → Skills)
# MUST fire on this because CI-EXAMPLE-001 is status=active AND matches the
# CI-numeric scope.

### [CI-OTHER-001] Some Other Rule

**Statement**: A different rule, present here so SKILL.md is non-empty
but does not cite CI-EXAMPLE-001.

**Enforcement**: Mechanical — `validate-foo.py` (citing the real fixture
validator so check 1 resolves cleanly). [VERIFICATION: WF validate-foo.py]
