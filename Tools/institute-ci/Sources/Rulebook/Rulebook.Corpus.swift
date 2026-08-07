import Foundation

extension Rulebook {
    /// The markdown the canon is made of: a set of aliased roots, plus
    /// named individual files.
    ///
    /// The roots are the gate's subject and are supplied, not discovered.
    /// The three sanctioned skill roots and `Workspace/CLAUDE.md` come
    /// from the 2026-07-05 gate-root unification ruling and are defaulted
    /// at the command face, which is where the retired shell wrapper held
    /// them.
    ///
    /// An alias is a stable short name for a root (`institute`,
    /// `engagement`, `rule`), so every finding cites a path that is the
    /// same on every machine — the corpus review found machine-absolute
    /// paths in the rulebook, and a checker that reported them would have
    /// been part of the problem.
    public struct Corpus: Sendable {
        public let documents: [Document]
        public let skills: [Skill]

        public init(documents: [Document], skills: [Skill]) {
            self.documents = documents
            self.skills = skills
        }

        /// Read every `*.md` beneath each root, plus each named file.
        ///
        /// A root that is not a directory is skipped rather than
        /// refused: the sanctioned root set spans three repositories and
        /// a checkout legitimately holds a subset. An empty *result* is
        /// the defect, and the caller raises it — a run that found no
        /// corpus at all has measured nothing and must not report health.
        public static func read(
            roots: [(alias: String, path: String)],
            files: [(alias: String, path: String)]
        ) -> Self {
            var documents: [Document] = []
            var skills: [Skill] = []
            for root in roots {
                var isDirectory: ObjCBool = false
                guard
                    FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                else { continue }
                let markdown = Self.markdownFiles(under: root.path)
                for path in markdown {
                    let relative = String(path.dropFirst(root.path.count + 1))
                    guard let data = FileManager.default.contents(atPath: path) else { continue }
                    documents.append(
                        Document(
                            path: path, alias: "\(root.alias):\(relative)",
                            text: String(decoding: data, as: UTF8.self)))
                }
                for hub in markdown.filter({ ($0 as NSString).lastPathComponent == "SKILL.md" }) {
                    let directory = (hub as NSString).deletingLastPathComponent
                    // Only a directory *immediately* under the root is a
                    // skill; a SKILL.md nested deeper belongs to a skill
                    // already counted.
                    guard (directory as NSString).deletingLastPathComponent == root.path else {
                        continue
                    }
                    let relative = String(directory.dropFirst(root.path.count + 1))
                    skills.append(
                        Skill(
                            alias: "\(root.alias):\(relative)", directory: directory,
                            members: documents.filter { $0.directory == directory }))
                }
            }
            for file in files {
                guard let data = FileManager.default.contents(atPath: file.path) else { continue }
                documents.append(
                    Document(
                        path: file.path, alias: file.alias,
                        text: String(decoding: data, as: UTF8.self)))
            }
            return Self(documents: documents, skills: skills.sorted { $0.alias < $1.alias })
        }

        /// Every `*.md` beneath a directory, in path-component order.
        ///
        /// Component order, not string order: `a/b.md` and `a-c.md`
        /// compare differently under the two, and the corpus contains
        /// both shapes. Definition sites are listed in this order in a
        /// duplicate finding, so it is part of the message.
        static func markdownFiles(under root: String) -> [String] {
            guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
            var paths: [[String]] = []
            for case let relative as String in enumerator where relative.hasSuffix(".md") {
                var isDirectory: ObjCBool = false
                let full = "\(root)/\(relative)"
                guard
                    FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
                    !isDirectory.boolValue
                else { continue }
                paths.append(relative.components(separatedBy: "/"))
            }
            return paths.sorted { left, right in
                for (a, b) in zip(left, right) where a != b { return a < b }
                return left.count < right.count
            }
            .map { "\(root)/\($0.joined(separator: "/"))" }
        }
    }
}
