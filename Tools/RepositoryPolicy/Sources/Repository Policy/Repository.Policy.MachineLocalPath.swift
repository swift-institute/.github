import Foundation

// ===----------------------------------------------------------------------===//
// Machine-local absolute paths in committed files
// (swift-institute/.github#247).
//
// A committed path that resolves only on one machine does not fail for its
// author — the author is the one person who cannot observe the breakage. It
// fails silently for everyone else, forever. The peer Rule Institute's
// `swift-nl-wetgever` census (2026-08-03, 1,060 repositories) found 1,056 of
// 1,059 manifests carrying an absolute path into one machine's home
// directory; the three clean repositories were simply the recently-touched
// ones, so the class was the default outcome rather than an occasional slip.
//
// Two independent predicates, both report-only (`advisories`, never
// `violations`):
//
//   REPO-PATH-001  a home-rooted absolute path (`/Users/<name>`,
//                  `/home/<name>`) in any committed text file.
//
//   REPO-PATH-002  a manifest `path:` argument that resolves outside the
//                  package — an absolute path, or a relative path that
//                  ascends out of the package and then descends into a
//                  *named* sibling.
//
// REPO-PATH-002 is deliberately "resolves outside the repository" rather than
// "is a path dependency", because two lawful shapes must survive, both
// encountered during the census:
//
//   1. `path:` also appears on target declarations — `path: "Tests/X Tests"`
//      is an ordinary in-repository target layout. Matching `path:` as a
//      token corrupts target layouts and would fire on a large fraction of
//      the fleet. This scanner only reads the `path:` label of a
//      `.package(...)` call for the escape test; a target `path:` is read
//      only for the absolute test, which a repo-relative target layout can
//      never trip.
//
//   2. A nested test package legitimately references its own parent —
//      `.package(path: "../..")` is correct and must be preserved. A pure
//      ascent names an *ancestor* of the manifest's own directory, which is
//      by construction inside the same checkout. An ascent followed by a
//      descent (`../../swift-other`) names a *sibling* checkout, which is a
//      different repository and is unresolvable without it. That
//      ascent-then-descent distinction is the whole test.
//
// Enumeration, not matching, is where this class of predicate actually
// fails, so the manifest scan is a character stream over the whole file with
// `.package(...)` membership tracked by paren depth, never a line-oriented
// match on `.package(path:`. That is what lets it see all of:
//
//   - the two-argument `.package(name:path:)` form;
//   - a wrapped argument list, with `path:` and its literal on different
//     lines;
//   - a dependency inside `#if`, which is lawful and conditionally compiled.
//
// STATED NON-GOAL: a **computed** path — one built from a variable, a
// constant, or string interpolation — is invisible to any text predicate,
// including this one. It is out of scope, and `machineLocalPathCannotSeeA
// ComputedPath` is a *negative* control that encodes the blind spot as a
// test. This matters because the completion criterion for a remediation
// sweep must never be "re-run the same predicate and see zero": any form the
// predicate cannot see reports converged. A clean report from this rule means
// "no literal machine-local path", not "no machine-local path".
//
// Convergent prior art: `.github/scripts/validate-skill-hygiene.py` carries a
// `skill-machine-path` check over published Skill corpora, and independently
// arrived at the same hosted-runner exemption. That check is narrower in
// scope (SKILL.md only) and lives on the Python side that Goal #113 is
// retiring; consolidating it into this predicate is a follow-up, not this
// change, because it is a firing gate today and this one is report-only.
// ===----------------------------------------------------------------------===//

extension RepositoryPolicy {
    /// Detects committed paths that resolve on exactly one machine.
    ///
    /// Report-only by construction: every finding this produces is routed to
    /// `SurfaceReport.advisories`, which does not affect `passed`. Graduation
    /// to `violations` follows the standard path once a corpus is clean and a
    /// positive control reproduces in central CI.
    public enum MachineLocalPath {
        /// One finding, carrying the line it was read from so a report line
        /// is actionable without re-deriving the match.
        public struct Finding: Equatable, Sendable {
            public let identifier: String
            public let line: Int
            public let message: String
        }

        /// User-home roots.
        ///
        /// A path under one of these names an account on a specific machine,
        /// which is what makes it unportable — the property is "names one
        /// machine's home directory", not "is absolute".
        static let homeRoots = ["Users", "home"]

        /// The single exempt home component.
        ///
        /// `/home/runner` and `/Users/runner` are the GitHub-hosted runner
        /// homes: fixed by the platform and identical for every caller, so they
        /// are machine-*independent* and the predicate is simply false for
        /// them. This is the only name exempted, by exact match on the
        /// component.
        static let hostedRunnerHome = "runner"

        /// Characters that make a path component a template rather than a
        /// name.
        ///
        /// `/Users/$USER`, `/home/${HOME}`, and `/Users/<user>` in
        /// documentation name no machine at all, so the predicate is false
        /// for them too. An all-dots component (`/Users/...`, the elision
        /// prose uses) is covered by the same reasoning.
        static let templateMarkers: Set<Character> = ["$", "{", "}", "<", ">", "*", "%"]

        /// Every finding for one file. `path` selects which predicates apply:
        /// REPO-PATH-001 runs on all text files, REPO-PATH-002 additionally
        /// on manifests.
        public static func findings(path: String, contents: String) -> [Finding] {
            var findings = homeRootedFindings(contents: contents)
            if isManifest(path: path) {
                let occupied = Set(findings.map(\.line))
                // A home-rooted manifest path is one defect, not two:
                // REPO-PATH-001 already named that line, so REPO-PATH-002
                // reports only what REPO-PATH-001 could not see.
                findings += manifestFindings(contents: contents)
                    .filter { !occupied.contains($0.line) }
            }
            return findings.sorted {
                $0.line != $1.line ? $0.line < $1.line : $0.identifier < $1.identifier
            }
        }

        /// `Package.swift` and its version-specific siblings
        /// (`Package@swift-6.1.swift`), at any depth — a nested test package
        /// carries one too.
        static func isManifest(path: String) -> Bool {
            let name = String(path.split(separator: "/").last ?? "")
            return name == "Package.swift"
                || (name.hasPrefix("Package@swift-") && name.hasSuffix(".swift"))
        }

        // MARK: - REPO-PATH-001

        static func homeRootedFindings(contents: String) -> [Finding] {
            var findings = [Finding]()
            for (offset, line) in contents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).enumerated() {
                for root in homeRoots {
                    for home in homeReferences(root: root, in: line) {
                        findings.append(
                            .init(
                                identifier: "REPO-PATH-001",
                                line: offset + 1,
                                message:
                                    "absolute path into a machine-local home directory "
                                    + "(/\(root)/\(home)); it resolves only on that machine"
                            )
                        )
                    }
                }
            }
            return findings
        }

        /// The home components named by `/<root>/<component>` occurrences in
        /// `line`, excluding hosted-runner homes, template components, and
        /// occurrences inside a URL.
        static func homeReferences(root: String, in line: Substring) -> [String] {
            let characters = Array(line)
            let needle = Array("/\(root)/")
            var components = [String]()
            var index = 0
            while index + needle.count <= characters.count {
                guard Array(characters[index..<(index + needle.count)]) == needle else {
                    index += 1
                    continue
                }
                var end = index + needle.count
                while end < characters.count, !isPathTerminator(characters[end]) {
                    end += 1
                }
                let component = String(characters[(index + needle.count)..<end])
                if !component.isEmpty,
                    component != hostedRunnerHome,
                    !component.allSatisfy({ $0 == "." }),
                    !component.contains(where: templateMarkers.contains),
                    !isInsideURL(characters: characters, matchStart: index)
                {
                    components.append(component)
                }
                index = end
            }
            return components
        }

        /// A path component ends at a separator, at whitespace, or at any
        /// delimiter that cannot appear in a shell/Swift/YAML path token.
        static func isPathTerminator(_ character: Character) -> Bool {
            character == "/" || character.isWhitespace
                || "\"'`,;:)]}>|&".contains(character)
        }

        /// True when the match sits inside a URL — `https://host/home/x` is a
        /// remote resource, not a machine-local path.
        ///
        /// Scans back over the contiguous token and looks for a scheme
        /// separator.
        static func isInsideURL(characters: [Character], matchStart: Int) -> Bool {
            var start = matchStart
            while start > 0, !isTokenBoundary(characters[start - 1]) {
                start -= 1
            }
            guard start < matchStart else { return false }
            let token = String(characters[start..<matchStart])
            return token.contains("://")
        }

        static func isTokenBoundary(_ character: Character) -> Bool {
            character.isWhitespace || "\"'`,;()[]{}<>|&=".contains(character)
        }

        // MARK: - REPO-PATH-002

        static func manifestFindings(contents: String) -> [Finding] {
            var findings = [Finding]()
            let characters = Array(contents)
            var lineStarts = [0]
            for (index, character) in characters.enumerated() where character == "\n" {
                lineStarts.append(index + 1)
            }
            func line(at offset: Int) -> Int {
                var low = 0
                var high = lineStarts.count - 1
                while low < high {
                    let middle = (low + high + 1) / 2
                    if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
                }
                return low + 1
            }

            for argument in pathArguments(characters: characters) {
                guard let verdict = verdict(for: argument.value, inPackageCall: argument.inPackageCall)
                else { continue }
                findings.append(
                    .init(
                        identifier: "REPO-PATH-002",
                        line: line(at: argument.offset),
                        message: "manifest path \"\(argument.value)\" \(verdict)"
                    )
                )
            }
            return findings
        }

        struct PathArgument {
            let value: String
            let offset: Int
            let inPackageCall: Bool
        }

        /// Every `path:` string-literal argument in the manifest, tagged with
        /// whether it sits inside a `.package(...)` call.
        ///
        /// Tagging is what keeps an in-repository target layout out of the
        /// escape test.
        static func pathArguments(characters: [Character]) -> [PathArgument] {
            var arguments = [PathArgument]()
            let label = Array("path:")
            let packageCall = Array(".package(")
            let lineComment = Array("//")
            let blockCommentOpen = Array("/*")
            let blockCommentClose = Array("*/")
            var packageCallDepths = [Int]()
            var depth = 0
            var index = 0
            var inString = false

            while index < characters.count {
                let character = characters[index]

                if inString {
                    if character == "\\" {
                        index += 2
                        continue
                    }
                    if character == "\"" { inString = false }
                    index += 1
                    continue
                }
                if character == "\"" {
                    inString = true
                    index += 1
                    continue
                }
                // Comments are skipped before paren counting, because a
                // stray `)` in a comment would unbalance the depth and
                // silently drop every `.package(...)` after it — a
                // fail-toward-not-firing bug, the exact failure this rule
                // exists to prevent.
                if matches(lineComment, characters: characters, at: index) {
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                    continue
                }
                if matches(blockCommentOpen, characters: characters, at: index) {
                    var nesting = 1
                    index += blockCommentOpen.count
                    while index < characters.count, nesting > 0 {
                        if matches(blockCommentOpen, characters: characters, at: index) {
                            nesting += 1
                            index += blockCommentOpen.count
                        } else if matches(blockCommentClose, characters: characters, at: index) {
                            nesting -= 1
                            index += blockCommentClose.count
                        } else {
                            index += 1
                        }
                    }
                    continue
                }
                if character == "(" {
                    depth += 1
                    index += 1
                    continue
                }
                if character == ")" {
                    if packageCallDepths.last == depth { packageCallDepths.removeLast() }
                    depth = max(0, depth - 1)
                    index += 1
                    continue
                }
                if matches(packageCall, characters: characters, at: index) {
                    depth += 1
                    packageCallDepths.append(depth)
                    index += packageCall.count
                    continue
                }
                if matches(label, characters: characters, at: index),
                    index == 0 || !isIdentifierCharacter(characters[index - 1])
                {
                    // Whitespace, not spaces: the argument list may be
                    // wrapped, putting the literal on the line after its
                    // label. A single-line reading is blind to that, which
                    // is how the peer's census predicate missed a shape.
                    var cursor = index + label.count
                    while cursor < characters.count, characters[cursor].isWhitespace {
                        cursor += 1
                    }
                    if cursor < characters.count, characters[cursor] == "\"",
                        let value = stringLiteral(characters: characters, openingQuote: cursor)
                    {
                        arguments.append(
                            .init(
                                value: value,
                                offset: index,
                                inPackageCall: !packageCallDepths.isEmpty
                            )
                        )
                    }
                    index += label.count
                    continue
                }
                index += 1
            }
            return arguments
        }

        /// The reason a manifest path is machine-local, or `nil` when it is
        /// lawful.
        ///
        /// Absolute is unlawful anywhere in a manifest: an in-repository
        /// target layout is always repo-relative, so an absolute `path:` on
        /// either a target or a dependency can only name this machine.
        /// Escape is tested only on `.package(...)` because only a dependency
        /// may legitimately point outside its own directory at all.
        static func verdict(for value: String, inPackageCall: Bool) -> String? {
            if value.hasPrefix("/") {
                return "is absolute; it resolves only on the machine that has that directory"
            }
            guard inPackageCall else { return nil }
            // Normalize first, so `Sources/../Other` is read as the
            // in-repository `Other` it actually resolves to. What survives
            // normalization is a count of components that escape the package
            // (`ascent`) and what is named below them (`descent`).
            var ascent = 0
            var descent = [Substring]()
            for component in value.split(separator: "/", omittingEmptySubsequences: true) {
                switch component {
                case ".":
                    continue
                case "..":
                    if descent.isEmpty { ascent += 1 } else { descent.removeLast() }
                default:
                    descent.append(component)
                }
            }
            guard ascent > 0 else { return nil }
            // A pure ascent names an ancestor directory of this package,
            // which is by construction inside the same checkout — the lawful
            // nested-test-package-references-its-parent shape.
            guard !descent.isEmpty else { return nil }
            return
                "ascends out of the package and descends into a sibling checkout "
                + "(\(descent.joined(separator: "/"))); a pure ascent such as \"../..\" — a "
                + "nested package referencing its own parent — is lawful, because it names a "
                + "directory this package is already inside"
        }

        // MARK: - Scanning helpers

        static func matches(_ needle: [Character], characters: [Character], at index: Int) -> Bool {
            guard index + needle.count <= characters.count else { return false }
            for offset in needle.indices where characters[index + offset] != needle[offset] {
                return false
            }
            return true
        }

        static func isIdentifierCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        static func stringLiteral(characters: [Character], openingQuote: Int) -> String? {
            var index = openingQuote + 1
            var value = ""
            while index < characters.count {
                let character = characters[index]
                if character == "\\" {
                    index += 2
                    continue
                }
                if character == "\"" { return value }
                if character == "\n" { return nil }
                value.append(character)
                index += 1
            }
            return nil
        }
    }
}
