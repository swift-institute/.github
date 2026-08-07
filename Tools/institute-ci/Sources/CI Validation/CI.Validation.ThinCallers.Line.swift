import CI_Contract

extension CI.Validation.ThinCallers {
    /// One line of a workflow file, and the predicates the thin-caller
    /// rules ask of it.
    ///
    /// Each predicate corresponds to one line-anchored pattern in the
    /// retired `validate-thin-callers.py`. They are asked line by line
    /// rather than of the whole text, which is what the `re.MULTILINE`
    /// anchors meant; per-line evaluation also removes the one way the
    /// Python patterns could surprise, since `\s` there spans newlines and
    /// `^\s+steps:` could therefore begin matching on a *previous* line.
    ///
    /// A "job-level" key is anything indented, matching the retired
    /// `^\s+<key>:` form: it is true at every canonical indent (2-space,
    /// 4-space) and false at column 0, which is the whole discrimination
    /// those patterns needed.
    public struct Line: Sendable, Equatable {
        public let text: String

        /// A reusable-workflow reference to an org `.github` repository.
        public struct Reference: Sendable, Equatable {
            /// `<org>/.github/.github/workflows/<file>`.
            public let path: String
            /// Whatever follows `@`.
            public let ref: String
        }

        public init(_ text: String) { self.text = text }

        /// Every line of a workflow, in order.
        public static func all(_ text: String) -> [Line] {
            text.split(separator: "\n", omittingEmptySubsequences: false).map { Line(String($0)) }
        }

        public var indent: Int { text.prefix { $0 == " " || $0 == "\t" }.count }

        var trimmed: String { text.trimmed }

        var isBlankOrComment: Bool { trimmed.isEmpty || trimmed.hasPrefix("#") }

        /// A key at column 0 — the boundary that ends the `jobs:` block.
        /// A comment at column 0 is not one; the retired walk skipped it.
        var isTopLevelKey: Bool {
            guard let first = text.first else { return false }
            return !first.isWhitespace && !trimmed.hasPrefix("#")
        }

        /// `^jobs:\s*(#.*)?$`
        var isJobsKey: Bool { indent == 0 && keyWithNoValue == "jobs" }

        /// `^([\w-]+):\s*(#.*)?$` against the stripped line — a job
        /// boundary under `jobs:`.
        var isJobNameLine: Bool {
            guard let key = keyWithNoValue, !key.isEmpty else { return false }
            return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }

        /// The line's key when it carries no inline value — `foo:` or
        /// `foo:  # note`. `nil` when the line has a value, or no key.
        var keyWithNoValue: String? {
            guard let separator = trimmed.firstIndex(of: ":") else { return nil }
            let rest = trimmed[trimmed.index(after: separator)...].trimmed
            guard rest.isEmpty || rest.hasPrefix("#") else { return nil }
            return String(trimmed[..<separator])
        }

        /// `^\s+runs-on:`
        var isInlineRunsOn: Bool { indent > 0 && trimmed.hasPrefix("runs-on:") }

        /// `^\s+steps:\s*$` — note the retired pattern does **not** admit
        /// a trailing comment here, while its `DIRECT_JOB_STEPS` twin
        /// does. Preserved rather than harmonised: the two counts are
        /// compared against each other in the precedence proof, so
        /// changing one silently changes when the proof holds.
        var isInlineSteps: Bool { indent > 0 && trailingCommentIsAbsent && trimmed == "steps:" }

        /// `^\s+uses:\s+\S+`
        var isJobUses: Bool { indent > 0 && usesValue != nil }

        /// `^    runs-on:` — exactly four spaces, a direct key of a job.
        var isDirectJobRunsOn: Bool { text.hasPrefix("    runs-on:") }

        /// `^    steps:\s*(#.*)?$`
        var isDirectJobSteps: Bool {
            text.hasPrefix("    steps:") && keyWithNoValue == "steps"
        }

        /// `^    uses:\s+\S+`
        var isDirectJobUses: Bool {
            text.hasPrefix("    uses:") && usesValue != nil
        }

        /// `^\s*workflow_call:` — at any indent, including column 0.
        var declaresWorkflowCall: Bool { trimmed.hasPrefix("workflow_call:") }

        /// `^\s+secrets:\s+inherit\s*(#.*)?$`
        var isSecretsInherit: Bool {
            guard indent > 0, trimmed.hasPrefix("secrets:") else { return false }
            return value(after: "secrets:")?.beforeComment.trimmed == "inherit"
        }

        /// `^\s+secrets:\s*(#.*)?$` — the block-form opener.
        var isSecretsBlock: Bool { indent > 0 && keyWithNoValue == "secrets" }

        /// `^\s+secrets:\s*\{` — the inline-map form.
        var isSecretsInlineMap: Bool {
            indent > 0 && (value(after: "secrets:")?.hasPrefix("{") ?? false)
        }

        /// The `uses:` target, when the line declares one with a
        /// non-empty value.
        var usesValue: String? {
            guard trimmed.hasPrefix("uses:"), let value = value(after: "uses:"), !value.isEmpty
            else { return nil }
            return value
        }

        /// The intra-Institute reusable this line references.
        ///
        /// The discriminator is the `<org>/.github/.github/workflows/`
        /// double infix, unique to org-`.github` repositories: from
        /// GitHub's point of view the calling repository is third-party,
        /// so the `<org>/.github` repository's own `.github/workflows/`
        /// directory is reached through the nested path. A third-party
        /// reusable has the single-infix shape and is not one of these.
        var intraInstituteReference: Reference? {
            guard indent > 0, let value = usesValue,
                let separator = value.lastIndex(of: "@")
            else { return nil }
            let path = String(value[..<separator])
            let ref = String(value[value.index(after: separator)...])
            guard !ref.isEmpty, !ref.contains(where: \.isWhitespace) else { return nil }
            let segments = path.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 5, segments[1] == ".github", segments[2] == ".github",
                segments[3] == "workflows",
                segments[0].allSatisfy(Self.isReferenceCharacter),
                segments[4].allSatisfy(Self.isReferenceCharacter)
            else { return nil }
            return Reference(path: path, ref: ref)
        }

        /// `^\s+NAME:\s*\$\{\{\s*secrets\.NAME\s*\}\}\s*(#.*)?$` — the
        /// exact forwarding line a cross-org caller must carry per name.
        func forwards(_ name: String) -> Bool {
            guard indent > 0, trimmed.hasPrefix("\(name):"),
                let value = value(after: "\(name):")?.beforeComment.trimmed,
                value.hasPrefix("${{"), value.hasSuffix("}}")
            else { return false }
            let inner = value.dropFirst(3).dropLast(2).trimmed
            return inner == "secrets.\(name)"
        }

        /// The `NAME` of a mapping entry, when the line is one.
        var mappingKey: String? {
            guard let separator = trimmed.firstIndex(of: ":") else { return nil }
            let key = String(trimmed[..<separator])
            guard !key.isEmpty,
                key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
            else { return nil }
            return key
        }

        /// The text after `key`, trimmed. `nil` when the line does not
        /// open with it.
        func value(after key: String) -> String? {
            guard trimmed.hasPrefix(key) else { return nil }
            return String(trimmed.dropFirst(key.count)).trimmed
        }

        /// Whether the line carries no `#` comment at all — the one place
        /// the retired patterns differ from each other.
        var trailingCommentIsAbsent: Bool { !text.contains("#") }

        static func isReferenceCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "-"
                || character == "."
        }
    }
}

extension StringProtocol {
    /// Leading and trailing spaces and tabs removed.
    fileprivate var trimmed: String {
        var value = self[...]
        while let first = value.first, first == " " || first == "\t" { value = value.dropFirst() }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        return String(value)
    }

    /// Everything before a `#` that opens the string or follows
    /// whitespace, which is YAML's own comment rule.
    fileprivate var beforeComment: String {
        var kept = ""
        var previous: Character?
        for character in self {
            if character == "#", previous == nil || previous == " " || previous == "\t" { break }
            kept.append(character)
            previous = character
        }
        return kept
    }
}
