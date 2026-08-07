// Nest.Name namespace shell (FT1-ratification.json;
// naming-annex-nest-name.md).
//
// `Rulebook` owns the rulebook checking itself. Its subject is the
// **markdown skill corpus** — the prose layer that states the rules —
// and never Swift source, which swift-linter owns. The 2026-07-05 corpus
// review is why it exists: eight fatal cross-rule contradictions and
// around thirty dangling references, every one of them in prose that no
// gate read.
//
// The retired shape was a pair — `check-canon.sh` and `check-canon.py`,
// one wrapper and one engine, two files stating one semantic. The
// semantic is ported once. What the wrapper contributed (the sanctioned
// roots, the developer-root derivation, the exit-code convention) is
// argument defaulting, and it lives at the command face; what the engine
// contributed is here.
//
// `Rulebook.Census` is the second retired shell script, `check-rule-count.sh`.
// It counts rather than judges, so it is not a check — but it reads the
// same corpus in the same two definition forms, and a counter that
// disagreed with the checker about what a rule looks like is exactly the
// undercount [SKILL-CREATE-005c] exists to forbid.
//
// **Not `Canon`.** The retired scripts are called `check-canon`, and the
// output text still says so, but `CI.Canon` in this package already owns
// a different thing entirely: the canonical *documents this control plane
// distributes* — `.gitignore` and its kin, rendered into every repository
// and checked there. Two unrelated "canons" one import apart is precisely
// the second spelling the manifest exists to prevent, so the domain is
// named for what it actually is. The corpus states rules; it is a
// rulebook. The command keeps the name `check-canon`, because that is the
// face its callers already invoke.
public enum Rulebook {}
