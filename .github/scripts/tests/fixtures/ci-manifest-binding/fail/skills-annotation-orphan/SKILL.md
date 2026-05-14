# Synthetic SKILL.md — fail/skills-annotation-orphan fixture.
#
# Cites `WF validate-nonexistent.py` which is NOT in the manifest. The
# binding validator's check 1 (Skills → manifest) MUST fire on this.

### [TEST-ACTIVE-001] Test Rule

**Statement**: A test rule exists so check 3 stays silent (rule-id is
TEST-ACTIVE-001 — not in the CI-\d+ scope — so check 3 wouldn't fire
on its absence anyway, but we cite it here for symmetry).

**Enforcement**: Mechanical — `validate-nonexistent.py` (this annotation
intentionally references a non-existent validator to trigger check 1).
[VERIFICATION: WF validate-nonexistent.py]
