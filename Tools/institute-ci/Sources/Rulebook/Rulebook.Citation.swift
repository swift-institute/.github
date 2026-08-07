extension Rulebook {
    /// One bracketed reference on one line.
    ///
    /// The corpus cites in four forms, and they are recognised in
    /// decreasing specificity so that a more general form never claims a
    /// token a more specific one owns:
    ///
    /// ```
    /// [PREFIX-010]–[PREFIX-020]   cross-bracket range   → both endpoints
    /// [PREFIX-010–020]            in-bracket range      → both endpoints
    /// [PREFIX-*]                  wildcard              → the family
    /// [PREFIX-010]  [IMPL-INTENT] single                → the identifier
    /// ```
    ///
    /// Ranges resolve on their **endpoints**, never on their members: a
    /// sparse range is corpus-legal, and requiring every member to exist
    /// would fail `PATTERN-012–062` for the fifty numbers nobody ever
    /// used.
    ///
    /// The retired engine ran four regular expressions in that order and
    /// blanked each match before the next, which is what kept a
    /// cross-range's endpoints from being re-counted as two singles.
    /// Scanning brackets once and consuming spans expresses the same
    /// precedence directly, and the ordering is the part to preserve.
    public struct Citation: Sendable, Equatable {
        public enum Form: Sendable, Equatable {
            /// `[A]–[B]` — the two endpoints.
            case crossRange(Identifier, Identifier)
            /// `[A–NNN]` — the two endpoints, the second completed from
            /// the first's family.
            case inBracketRange(Identifier, Identifier)
            /// `[FAMILY-*]` — resolves if any identifier extends the
            /// family.
            case wildcard(String)
            /// `[A]`.
            case single(Identifier)
        }

        public let form: Form

        public init(form: Form) { self.form = form }
    }
}

extension Rulebook.Citation {
    /// A `[…]` span and where it sat: the shape the precedence cascade
    /// consumes.
    private typealias Bracket = (inner: String, start: Int, end: Int)

    /// Every citation on a line, in the precedence order above.
    public static func scan(_ line: String) -> [Self] {
        let characters = Array(line)
        var brackets: [Bracket] = []
        var index = 0
        var open: Int?
        while index < characters.count {
            switch characters[index] {
            case "[":
                // The **innermost** pair is the citation. `[per [RES-019]]`
                // and `[[ALL-OK]]` are both real corpus shapes, and a
                // scanner that took the outermost bracket would read
                // `per [RES-019` — a token matching no grammar — and
                // report the file as clean.
                open = index
            case "]":
                if let start = open {
                    brackets.append(
                        (inner: String(characters[start + 1..<index]), start: start, end: index))
                    open = nil
                }
            default:
                break
            }
            index += 1
        }

        var consumed = Set<Int>()
        var citations: [Self] = []

        // 1. Cross-bracket ranges. Two numeric brackets separated by
        //    nothing but an optionally-spaced hyphen, en dash, or em dash.
        for position in brackets.indices.dropLast() where !consumed.contains(position) {
            let left = brackets[position]
            let right = brackets[position + 1]
            guard Rulebook.Identifier.isNumeric(left.inner),
                Rulebook.Identifier.isNumeric(right.inner),
                isDash(String(characters[(left.end + 1)..<right.start]))
            else { continue }
            consumed.insert(position)
            consumed.insert(position + 1)
            citations.append(
                Self(form: .crossRange(.init(left.inner), .init(right.inner))))
        }

        // 2. In-bracket ranges.
        for position in brackets.indices where !consumed.contains(position) {
            guard let (start, end) = inBracketRange(brackets[position].inner) else { continue }
            consumed.insert(position)
            citations.append(Self(form: .inBracketRange(start, end)))
        }

        // 3. Wildcards.
        for position in brackets.indices where !consumed.contains(position) {
            let inner = brackets[position].inner
            guard inner.hasSuffix("-*") else { continue }
            let family = String(inner.dropLast(2))
            guard Rulebook.Identifier.isPrefix(family) else { continue }
            consumed.insert(position)
            citations.append(Self(form: .wildcard(family)))
        }

        // 4. Singles.
        for position in brackets.indices where !consumed.contains(position) {
            let inner = brackets[position].inner
            guard Rulebook.Identifier.isNumeric(inner) || Rulebook.Identifier.isWord(inner) else {
                continue
            }
            citations.append(Self(form: .single(.init(inner))))
        }

        return citations
    }

    /// Whether the text between two brackets is a range dash: a hyphen,
    /// en dash, or em dash, with at most one space on either side.
    static func isDash(_ text: String) -> Bool {
        var body = Substring(text)
        if body.first == " " { body = body.dropFirst() }
        if body.last == " " { body = body.dropLast() }
        return body == "-" || body == "–" || body == "—"
    }

    /// The endpoints of an in-bracket range, or `nil` when the text is
    /// not one.
    ///
    /// The tail is a bare number, so the end identifier is completed from
    /// the start's family: `API-NAME-001–005` ends at `API-NAME-005`.
    static func inBracketRange(_ inner: String) -> (Rulebook.Identifier, Rulebook.Identifier)? {
        for (offset, character) in Array(inner).enumerated().reversed()
        where character == "-" || character == "–" || character == "—" {
            var head = String(Array(inner)[..<offset])
            var tail = String(Array(inner)[(offset + 1)...])
            if head.hasSuffix(" ") { head = String(head.dropLast()) }
            if tail.hasPrefix(" ") { tail = String(tail.dropFirst()) }
            guard Rulebook.Identifier.isNumeric(head) else { continue }
            var digits = Substring(tail)
            if let final = digits.last, final.isLowercase, final.isLetter {
                digits = digits.dropLast()
            }
            guard (1...3).contains(digits.count), digits.allSatisfy(\.isNumber) else { continue }
            guard let family = Rulebook.Identifier(head).parts?.family else { continue }
            return (.init(head), .init("\(family)-\(tail)"))
        }
        return nil
    }
}
