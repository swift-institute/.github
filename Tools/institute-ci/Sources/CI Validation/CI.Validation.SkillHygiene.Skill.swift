import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation.SkillHygiene {
    /// One `SKILL.md`, asked the two questions that decide whether it
    /// loads at all: does its frontmatter parse, and does it identify
    /// itself.
    ///
    /// Nothing here inspects what the description *says*. The
    /// description is the routing interface, so its absence makes the
    /// skill unreachable; its content is a judgment no CI check can make.
    struct Skill {
        private typealias Rules = CI.Validation.SkillHygiene

        let path: String
        let tree: Tree

        init(path: String, in tree: Tree) {
            self.path = path
            self.tree = tree
        }

        func findings(for subject: CI.Validation.Subject) -> [CI.Validation.Finding] {
            let relative = tree.relative(path)

            func finding(_ rule: CI.Validation.Rule, _ message: String) -> CI.Validation.Finding {
                CI.Validation.Finding(
                    repository: subject.repository, rule: rule, message: "\(relative): \(message)")
            }

            guard let text = tree.text(at: path) else {
                return [finding(Rules.frontmatter, "not valid UTF-8; the file cannot be loaded")]
            }

            guard let block = Self.frontmatterBlock(of: text) else {
                return [
                    finding(
                        Rules.frontmatter,
                        "no terminated YAML frontmatter block "
                            + "(expected a leading '---' line and a closing '---' line)")
                ]
            }

            let node: CI.Workflow.YAML.Node
            do throws(CI.Workflow.YAML.Error) {
                node = try CI.Workflow.YAML.Parser.parse(block)
            } catch {
                return [
                    finding(Rules.frontmatter, "frontmatter does not parse as YAML: \(error.message)")
                ]
            }

            guard let mapping = node.mapping else {
                return [finding(Rules.frontmatter, "frontmatter is not a YAML mapping")]
            }

            var findings: [CI.Validation.Finding] = []
            for field in ["name", "description"] {
                switch mapping[field] {
                case nil, .some(.null):
                    findings.append(finding(Rules.identity, "frontmatter has no `\(field)` field"))
                case .some(.text(let value)) where !value.trimmed.isEmpty:
                    continue
                default:
                    // Present but not a non-empty string — a number, a
                    // boolean, a mapping, or whitespace. All of them
                    // leave the field unusable, and the retired script
                    // reported them under one message.
                    findings.append(finding(Rules.identity, "`\(field)` is empty"))
                }
            }

            let expected = (path as NSString).deletingLastPathComponent
            let directory = (expected as NSString).lastPathComponent
            if let name = mapping["name"]?.text.map(\.trimmed), !name.isEmpty, name != directory {
                findings.append(
                    finding(
                        Rules.identity,
                        "`name` is '\(name)' but the directory is '\(directory)'; "
                            + "they must match so the skill projects unambiguously"))
            }
            return findings
        }

        /// The raw frontmatter block, or `nil` when it is absent or
        /// unterminated.
        ///
        /// A leading `---` line, then everything up to the first line
        /// that is `---` followed only by whitespace. The terminator
        /// search is deliberately the whole remaining text rather than a
        /// line scan: `\s` spans newlines, so a `---` immediately
        /// followed by a blank line terminates there — the retired
        /// behaviour, and what the `unterminated` fixture pins.
        static func frontmatterBlock(of text: String) -> String? {
            guard text.hasPrefix("---") else { return nil }
            let rest = text.dropFirst(3)
            guard rest.hasPrefix("\n") || rest.hasPrefix("\r\n") else { return nil }
            let body = String(rest)
            guard let terminator = Pattern.frontmatterTerminator.firstMatch(in: body) else {
                return nil
            }
            return String(body[body.startIndex..<terminator.range.lowerBound])
        }
    }
}

extension String {
    /// `str.strip()` — whitespace as Python's `str.strip()` removes it.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
