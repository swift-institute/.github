# Synthetic SKILL.md — pass/skills-cross-resolves-clean fixture.
#
# Cites both the rule-id (`[CI-997]`) AND the validator
# (`[VERIFICATION: WF validate-foo.py]`). Both Skills cross-checks (1 + 3)
# stay silent because everything resolves bidirectionally.

### [CI-997] Test Rule For Pass Fixture

**Statement**: Synthetic rule used to verify the clean cross-reference
path. The manifest entry CI-997 points at validate-foo.py and
this SKILL.md cites both.

**Enforcement**: Mechanical — `validate-foo.py`. [VERIFICATION: WF validate-foo.py]
