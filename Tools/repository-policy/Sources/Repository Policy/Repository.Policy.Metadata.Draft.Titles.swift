extension Repository.Policy.Metadata.Draft {
    /// `spec-titles.yaml`, read: authority → spec identifier → title.
    ///
    /// A lookup table rather than a document type because that is all the
    /// draft needs of it, and because a miss is ordinary. An absent title
    /// produces a `TODO` in the draft and a reviewer fills it in; that is
    /// the designed path, not a failure.
    public struct Titles: Sendable, Equatable {
        public let entries: [String: [String: String]]

        public init(_ entries: [String: [String: String]] = [:]) {
            self.entries = entries
        }

        /// `spec-titles.yaml`, read.
        ///
        /// The document's shape is fixed by its own header — an authority
        /// key at column zero, one indented `'<spec-id>': 'Title'` per
        /// line — so it is read directly rather than through a general
        /// YAML reader this package does not have and does not otherwise
        /// need. A line that does not match either shape is skipped, as
        /// comments and blanks are: the table is additive, and a reader
        /// that refused the whole file over one malformed row would take
        /// every other title down with it.
        public init(parsing text: String) {
            var entries: [String: [String: String]] = [:]
            var authority = ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmedASCIIWhitespace
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                guard let separator = trimmed.firstIndex(of: ":") else { continue }
                let key = String(trimmed[..<separator]).unquoted
                let value = String(trimmed[trimmed.index(after: separator)...])
                    .trimmedASCIIWhitespace.unquoted
                if line.first == " " || line.first == "\t" {
                    guard !authority.isEmpty, !key.isEmpty else { continue }
                    entries[authority, default: [:]][key] = value
                } else {
                    authority = value.isEmpty ? key : ""
                }
            }
            self.init(entries)
        }

        /// The title recorded for one spec under one authority, or `nil`.
        public subscript(authority: String, identifier: String) -> String? {
            guard let title = entries[authority]?[identifier], !title.isEmpty, title != "null"
            else { return nil }
            return title
        }
    }
}

extension StringProtocol {
    /// The value without leading or trailing ASCII whitespace.
    fileprivate var trimmedASCIIWhitespace: String {
        var value = Substring(self)
        let whitespace: Set<Character> = [" ", "\t", "\r"]
        while let first = value.first, whitespace.contains(first) { value = value.dropFirst() }
        while let last = value.last, whitespace.contains(last) { value = value.dropLast() }
        return String(value)
    }
}

extension String {
    /// The value with one matched pair of surrounding quotes removed.
    fileprivate var unquoted: String {
        for quote in ["'", "\""] where count >= 2 && hasPrefix(quote) && hasSuffix(quote) {
            return String(dropFirst().dropLast())
        }
        return self
    }
}
