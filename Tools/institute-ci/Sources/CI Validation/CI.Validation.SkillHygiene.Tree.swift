import CI_Contract
import Foundation

extension CI.Validation.SkillHygiene {
    /// The scanned repository as a set of files.
    ///
    /// Enumerated once, up front, rather than re-walked per check: the
    /// retired script walked the tree three times (`rglob("SKILL.md")`,
    /// `rglob("*.md")`, and a link-target `exists()` per link) and the
    /// walks could disagree about what was present.
    ///
    /// `.git` is excluded because a checkout's object store is not
    /// published content; every other directory is in scope, which is
    /// what makes the check layout-agnostic.
    struct Tree {
        let root: String

        /// Every file in the repository, ordered.
        let paths: [String]

        private let present: Set<String>

        init(root: String) throws(CI.Validation.EnvironmentDefect) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { throw .unreadableSubject(root: root) }

            self.root = root
            var found: [String] = []
            var seen: Set<String> = []
            var stack = [root]
            while let directory = stack.popLast() {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
                for name in names where name != ".git" {
                    let path = "\(directory)/\(name)"
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    else { continue }
                    if isDirectory.boolValue {
                        stack.append(path)
                    } else {
                        found.append(path)
                        seen.insert(path)
                    }
                }
            }
            self.paths = found.sorted { Self.componentsPrecede($0, $1) }
            self.present = seen
        }

        /// A path inside the tree.
        func path(_ relative: String) -> String { "\(root)/\(relative)" }

        /// The path a finding cites: relative to the repository root.
        func relative(_ path: String) -> String {
            path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
        }

        /// Every file whose last path component is `name`, in tree order.
        func files(named name: String) -> [String] {
            paths.filter { ($0 as NSString).lastPathComponent == name }
        }

        /// Every file whose name ends in `suffix`, in tree order.
        func files(withExtension suffix: String) -> [String] {
            paths.filter { $0.hasSuffix(suffix) }
        }

        /// The file's text, or `nil` when it is absent or not valid
        /// UTF-8.
        ///
        /// Strict decoding, not `String(decoding:as:)`. The
        /// `skill-frontmatter` rule reports a file that cannot be
        /// decoded, so a lossy read that substitutes replacement
        /// characters would turn that finding into a silent pass.
        func text(at path: String) -> String? {
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        /// Whether a path resolves to something in the repository.
        ///
        /// Consults the enumerated set first — the common case, and free
        /// — and falls back to the filesystem for a path that traverses
        /// `..` or names a directory, both of which the retired script's
        /// `Path.exists()` accepted.
        func resolves(_ path: String) -> Bool {
            present.contains(path) || FileManager.default.fileExists(atPath: path)
        }

        /// Orders two paths the way `sorted(Path.rglob(...))` does:
        /// component by component, not as flat strings.
        ///
        /// The two disagree — `"a.md"` precedes `"a/b.md"` as a string
        /// but follows it as components — and the difference is visible
        /// in emission order. It does not affect the differential gate,
        /// which sorts both streams, but matching the retired ordering
        /// keeps a live step summary readable against its predecessor.
        static func componentsPrecede(_ lhs: String, _ rhs: String) -> Bool {
            lhs.split(separator: "/", omittingEmptySubsequences: false).lexicographicallyPrecedes(
                rhs.split(separator: "/", omittingEmptySubsequences: false))
        }
    }
}

extension CI.Validation.SkillHygiene {
    /// The lines Python's `str.splitlines()` produces: split on every
    /// boundary Python treats as a line ending, with no empty trailing
    /// element.
    ///
    /// Reproduced rather than approximated because line numbers appear
    /// in the finding messages the differential gate compares byte for
    /// byte: a file containing a form feed or a U+2028 would shift every
    /// number after it. `"\r\n"` needs no special case — Swift reads it
    /// as one grapheme cluster, which is exactly the boundary Python
    /// treats it as.
    static func lines(of text: String) -> [String] {
        let breaks: Set<Character> = [
            "\n", "\r", "\r\n", "\u{0b}", "\u{0c}", "\u{1c}", "\u{1d}", "\u{1e}",
            "\u{85}", "\u{2028}", "\u{2029}",
        ]
        var lines: [String] = []
        var current = ""
        for character in text {
            if breaks.contains(character) {
                lines.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
