import Byte_Primitives
import FIPS_180_4
import Foundation

extension Repository.Policy.Census {
    /// Regenerates the census from checked-out trees at frozen heads.
    ///
    /// Semantics mirror the FT1 generator (SWIFT-NATIVE-PROGRAMME/
    /// census-generator.py) coordinate-for-coordinate; traversal order is
    /// deterministic (sorted), so parity against the FT1 artifact is
    /// order-normalized via `Census.normalized`.
    ///
    /// Excerpt digests compose onto the Institute FIPS 180-4 SHA-256
    /// witness (R37, swift-fips-180-4): pure, in-process, cross-platform.
    public struct Generator: Sendable {
        public struct Repo: Sendable {
            public let name: String
            public let root: String
            public let headSha: String

            public init(name: String, root: String, headSha: String) {
                self.name = name
                self.root = root
                self.headSha = headSha
            }
        }

        public enum Error: Swift.Error {
            case unreadable(path: String)
        }

        public let repos: [Repo]

        public init(repos: [Repo]) {
            self.repos = repos
        }

        static let skipCommands: Set<String> = [
            "if", "then", "else", "fi", "for", "do", "done", "while", "case",
            "esac", "echo", "printf", "exit", "set", "cd", "export", "shift",
            "local", "return", "true", "false", "read", "trap", "wait", "{",
            "}", "elif", "EOF",
        ]

        static let ownerByFamily: [String: String] = [
            "universal-or-wrapper-workflow": "CI Contract host projection (F12/F15)",
            "central-workflow": "named Swift owners (F2-F16)",
            "composite-action": "Workspace bootstrap + named owners (F10/F16)",
            "semantic-script": "named Swift owners (F2-F16)",
            "script-test": "owner test suites (F16)",
            "other": "FT1 adjudication",
        ]

        static func family(forPath path: String) -> String {
            if path.contains("/workflows/") && path.hasSuffix("swift-ci.yml") {
                return "universal-or-wrapper-workflow"
            }
            if path.contains("/workflows/") { return "central-workflow" }
            if path.contains("/actions/") { return "composite-action" }
            if path.contains("/scripts/tests/") { return "script-test" }
            if path.contains("/scripts/") { return "semantic-script" }
            return "other"
        }

        public func run() throws -> Repository.Policy.Census {
            var rows: [Row] = []
            let hasher = Hasher()
            for repo in repos {
                let githubRoot = repo.root + "/.github"
                for rel in try Self.walk(root: repo.root, under: githubRoot) {
                    try Self.rows(
                        for: rel, repo: repo, hasher: hasher, into: &rows)
                }
            }
            rows.append(Self.leafCallerFamilyRow)
            rows.append(contentsOf: Self.sentinelRows)
            return Repository.Policy.Census(rows: rows)
        }

        // MARK: traversal

        static func walk(root: String, under directory: String) throws -> [String] {
            let fm = FileManager.default
            var results: [String] = []
            var stack = [directory]
            while let dir = stack.popLast() {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for entry in entries.sorted() {
                    if entry == ".git" { continue }
                    let full = dir + "/" + entry
                    var isDirectory: ObjCBool = false
                    fm.fileExists(atPath: full, isDirectory: &isDirectory)
                    if isDirectory.boolValue {
                        stack.append(full)
                    } else if entry.hasSuffix(".yml") || entry.hasSuffix(".yaml")
                        || entry.hasSuffix(".py") || entry.hasSuffix(".sh") {
                        results.append(String(full.dropFirst(root.count + 1)))
                    }
                }
            }
            return results.sorted()
        }

        // MARK: per-file coordinates

        static func rows(
            for rel: String, repo: Repo, hasher: Hasher,
            into rows: inout [Row]
        ) throws {
            let full = repo.root + "/" + rel
            guard let raw = FileManager.default.contents(atPath: full) else {
                throw Error.unreadable(path: full)
            }
            let text = String(decoding: raw, as: UTF8.self)
            let fam = family(forPath: "/" + rel)
            let owner = ownerByFamily[fam] ?? ownerByFamily["other"]!
            let ext = rel.split(separator: ".").last.map(String.init) ?? ""
            let engine: String
            switch ext {
            case "py": engine = "python"
            case "sh": engine = "shell"
            case "yml", "yaml": engine = "actions-yaml"
            default: engine = "other"
            }
            func row(
                _ kind: Kind, _ id: String, line: Int, engine: String,
                digest: String, notes: String = ""
            ) -> Row {
                Row(repository: repo.name, headSha: repo.headSha, path: rel,
                    coordinateKind: kind, coordinateId: id, line: line,
                    engine: engine, excerptSha256: digest, family: fam,
                    intendedOwner: owner, disposition: "reduce", notes: notes)
            }
            // Collected locally: the regex enumeration closures below are
            // escaping, and an escaping closure cannot capture the `rows`
            // inout parameter (rejected by the Swift 6.3 Linux toolchain).
            var collected: [Row] = []
            defer { rows.append(contentsOf: collected) }
            collected.append(row(.file, "file:\(rel)", line: 1, engine: engine,
                                 digest: hasher.digest(raw)))
            guard engine == "actions-yaml" else { return }

            let ns = text as NSString
            func lineNumber(at location: Int) -> Int {
                var count = 1
                var index = 0
                while index < location {
                    if ns.character(at: index) == 0x0A { count += 1 }
                    index += 1
                }
                return count
            }

            let expression = try NSRegularExpression(
                pattern: "\\$\\{\\{.*?\\}\\}",
                options: [.dotMatchesLineSeparators])
            var i = 0
            expression.enumerateMatches(
                in: text, range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                guard let match else { return }
                let excerpt = ns.substring(with: match.range)
                collected.append(row(.expression, "expr:\(rel):\(i)",
                                line: lineNumber(at: match.range.location),
                                engine: "actions-expression",
                                digest: hasher.digest(Data(excerpt.utf8))))
                i += 1
            }

            let uses = try NSRegularExpression(
                pattern: "^\\s*(?:-\\s+)?uses:\\s*(\\S+)",
                options: [.anchorsMatchLines])
            i = 0
            uses.enumerateMatches(
                in: text, range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                guard let match else { return }
                let target = ns.substring(with: match.range(at: 1))
                collected.append(row(.usesEdge, "uses:\(rel):\(i)",
                                line: lineNumber(at: match.range.location),
                                engine: "actions-yaml",
                                digest: hasher.digest(Data(target.utf8)),
                                notes: target))
                i += 1
            }

            let lines = text.components(separatedBy: "\n")
            let runPattern = try NSRegularExpression(
                pattern: "^(\\s*)run:\\s*(\\||>|\\|-|>-)?",
                options: [.anchorsMatchLines])
            let command = try NSRegularExpression(pattern: "^\\s*([A-Za-z0-9_.\\/-]+)")
            i = 0
            runPattern.enumerateMatches(
                in: text, range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                guard let match else { return }
                let startLine = lineNumber(at: match.range.location)
                let indent = match.range(at: 1).length
                var block: [String] = []
                if match.range(at: 2).location != NSNotFound {
                    var j = startLine
                    while j < lines.count {
                        let candidate = lines[j]
                        let stripped = candidate.trimmingCharacters(in: .whitespaces)
                        let candidateIndent = candidate.count - candidate.drop { $0 == " " || $0 == "\t" }.count
                        if !stripped.isEmpty && candidateIndent <= indent { break }
                        block.append(candidate)
                        j += 1
                    }
                } else {
                    let rest = ns.substring(from: match.range.location + match.range.length)
                    block = [String(rest.prefix { $0 != "\n" })]
                }
                let body = block.joined(separator: "\n")
                collected.append(row(.runBlock, "run:\(rel):\(i)", line: startLine,
                                engine: "shell",
                                digest: hasher.digest(Data(body.utf8))))
                for (k, blockLine) in block.enumerated() {
                    let blockRange = NSRange(location: 0, length: (blockLine as NSString).length)
                    guard let commandMatch = command.firstMatch(in: blockLine, range: blockRange) else { continue }
                    let token = (blockLine as NSString).substring(with: commandMatch.range(at: 1))
                    if skipCommands.contains(token) { continue }
                    if blockLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
                    collected.append(row(.commandReference, "cmd:\(rel):\(i):\(k)",
                                    line: startLine + 1 + k, engine: "shell",
                                    digest: hasher.digest(Data(token.utf8)),
                                    notes: token))
                }
                i += 1
            }
        }

        // MARK: frozen family and sentinel rows

        static var leafCallerFamilyRow: Row {
            Row(repository: "17-organization fleet",
                headSha: "per-repo (review-inputs/reclosure/v1-per-root.json)",
                path: ".github/workflows/ci.yml", coordinateKind: .file,
                coordinateId: "family:leaf-callers", line: 1,
                engine: "actions-yaml", excerptSha256: "",
                family: "generated-leaf-caller",
                intendedOwner: "Repository Policy (generated projection; F13/F14)",
                disposition: "regenerate",
                notes: "449 callers; per-repo heads and caller blob SHAs frozen in v1-per-root.json (digest 56d8309c...)")
        }

        static var sentinelRows: [Row] {
            let sentinels: [(String, String, String)] = [
                ("private-ordinary-repositories",
                 "~182 private ordinary repositories: workflow bytes not enumerated in this public census",
                 "R33 posture; private coordinates stay opaque in public artifacts"),
                ("private-verification-private-side",
                 "private verifier repository workflow/scripts not enumerated here",
                 "split-credential boundary; owned by Private.Verification at F8"),
                ("workspace-repo-automation",
                 "swift-institute/Workspace repository automation not enumerated in this census pass",
                 "Workspace owns its own package facts; F2 binds its API"),
                ("skills-repo-automation",
                 "swift-institute/Skills repository automation not enumerated in this census pass",
                 "F17 owns Skills correspondence"),
                ("swift-linter-repo-automation",
                 "swift-foundations/swift-linter repository automation not enumerated in this census pass",
                 "F9 owns linter parity"),
            ]
            return sentinels.map { name, detail, cause in
                Row(repository: "sentinel", headSha: "", path: "",
                    coordinateKind: .family, coordinateId: "sentinel:\(name)",
                    line: 0, engine: "", excerptSha256: "", family: name,
                    intendedOwner: "typed at owning transaction",
                    disposition: "sentinel", measurement: "UNMEASURED",
                    cause: cause, notes: detail)
            }
        }
    }
}

extension Repository.Policy.Census.Generator {
    /// Excerpt SHA-256 composed onto the Institute FIPS 180-4 witness
    /// (R37): a pure, in-process digest, so no process spawn, tool probe,
    /// or cache is needed.
    struct Hasher {
        func digest(_ data: Data) -> String {
            FIPS_180_4.SHA256.digest([UInt8](data).map { Byte($0) }).hex
        }
    }
}
