import Foundation

extension Rulebook {
    /// How many rules the corpus states.
    ///
    /// The Swift owner of `check-rule-count.sh`, and the reason it is a
    /// type rather than a `grep` is `[SKILL-CREATE-005c]`: rule-counting
    /// tooling **must** union the heading form with the table-row form.
    /// A counter that recognised only `### [ID]` silently undercounts
    /// every skill written in the sanctioned catalogue variant, and an
    /// undercount is worse than no count — it reads as evidence.
    ///
    /// A census reports; it does not judge. There is no pass, no
    /// baseline, and no finding here. Its one failure mode is being asked
    /// about roots that do not exist, which is a defect and not a count
    /// of zero.
    public struct Census: Sendable, Equatable {
        /// `### [ID]` and deeper.
        public let headingForm: Int
        /// `| [ID] |` catalogue rows.
        public let tableForm: Int

        public init(headingForm: Int, tableForm: Int) {
            self.headingForm = headingForm
            self.tableForm = tableForm
        }

        /// The count `[SKILL-CREATE-005c]` means by "the rule count".
        public var union: Int { headingForm + tableForm }

        /// Count across a set of roots.
        ///
        /// Counts **lines**, not identifiers, exactly as the retired
        /// counter did: two headings for one identifier count twice.
        /// That is the right shape for a census — the duplicate is the
        /// duplicate check's finding, and hiding it here would make the
        /// two disagree.
        public static func taken(over roots: [String]) throws(Error) -> Self {
            guard !roots.isEmpty else { throw .noRoots }
            var heading = 0
            var table = 0
            for root in roots {
                for path in Corpus.markdownFiles(under: root) {
                    guard let data = FileManager.default.contents(atPath: path) else { continue }
                    for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                        if isHeadingRow(line) { heading += 1 }
                        if isTableRow(line) { table += 1 }
                    }
                }
            }
            return Self(headingForm: heading, tableForm: table)
        }

        /// `^##+ \[ID\]` — level 2 and deeper.
        static func isHeadingRow(_ line: String) -> Bool {
            var rest = Substring(line)
            var hashes = 0
            while rest.first == "#" {
                hashes += 1
                rest = rest.dropFirst()
            }
            guard hashes >= 2, rest.first == " " else { return false }
            return bracketed(rest.dropFirst()) != nil
        }

        /// `^\| \[ID\] \|` — a catalogue row.
        static func isTableRow(_ line: String) -> Bool {
            guard line.hasPrefix("| ") else { return false }
            let rest = line.dropFirst(2)
            guard let identifier = bracketed(rest) else { return false }
            return rest.dropFirst(identifier.count + 2).hasPrefix(" |")
        }

        /// The identifier in a leading `[…]`, when it is a numeric one.
        ///
        /// The retired counter's regex was
        /// `\[[A-Z][A-Z0-9-]*-[0-9]+[a-z]?\]`, which admits any
        /// hyphen-separated capital run before the number — deliberately
        /// looser than the citation grammar, because a census that
        /// undercounted on a grammar technicality would be the exact
        /// defect `[SKILL-CREATE-005c]` names.
        static func bracketed(_ text: Substring) -> String? {
            guard text.first == "[", let close = text.firstIndex(of: "]") else { return nil }
            let inner = text[text.index(after: text.startIndex)..<close]
            guard let first = inner.first, first.isUppercase, first.isLetter else { return nil }
            var digits = inner
            if let final = digits.last, final.isLowercase, final.isLetter {
                digits = digits.dropLast()
            }
            var trailing = 0
            while let last = digits.last, last.isNumber {
                trailing += 1
                digits = digits.dropLast()
            }
            guard trailing > 0, digits.last == "-" else { return nil }
            let head = digits.dropLast()
            guard
                head.allSatisfy({ ($0.isUppercase && $0.isLetter) || $0.isNumber || $0 == "-" })
            else { return nil }
            return String(inner)
        }
    }
}
