// swift-linter-tools-version: 0.1
// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-institute .github repository
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the Swift Institute project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//
//
// This was the only package under Tools/ with no root Lint.swift. Doctrine is
// that a consumer activates exactly one bundle in one, so its absence was a
// conformance gap; it activates the same bundle as its three siblings.
//
// Measured, because the obvious claim would have been wrong: adding this file
// changes NOTHING about what the linter reports. Before and after, the package
// lints at 103 active rules, 22 files, 65 violations — the effective
// configuration was already identical by inheritance. This is a conformance
// change, not a coverage change, and it is worth saying so rather than letting
// a reader assume findings were previously hidden.

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
        branch: "main",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
