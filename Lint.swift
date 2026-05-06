// ===----------------------------------------------------------------------===//
// Tier 1 — ecosystem-wide canonical Lint configuration.
//
// Mirrors the prior swift-institute-lint-canonical Swift package (now
// retired in favor of the file-based canonical pattern at
// swift-institute/.github/Lint.swift). Activates ZERO rules at present —
// rules graduate to Tier 1 only when they apply universally across every
// piece of Swift Institute code. Per-package consumers inherit from Tier 2
// (swift-primitives/.github/Lint.swift) for primitives-specific rules;
// Tier 2 inherits from this file for ecosystem-wide rules.
//
// File-based canonical pattern: a typed `let manifest: Lint.Manifest` at
// file scope is JSON-serialized via swift-manifest's subprocess loader and
// reconstructed by `Lint.SwiftDriver.resolveConfiguration(...)` at lint
// time. Parent-chain inheritance via the `// parent: <URL>` directive at
// the top of Tier 2 / consumer manifests; Tier 1 is the chain root and
// declares no parent directive.
// ===----------------------------------------------------------------------===//

import Linter

let manifest = Lint.Manifest(enabledRuleIDs: [])
