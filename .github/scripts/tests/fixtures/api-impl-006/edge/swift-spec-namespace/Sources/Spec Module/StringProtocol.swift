// Exact extension-target parity is an API-IMPL-006 edge case: the compound
// basename matches `StringProtocol`, so this rule must not fire. The file's
// pure-extension shape remains independently governed by [API-IMPL-007].

extension StringProtocol {}
