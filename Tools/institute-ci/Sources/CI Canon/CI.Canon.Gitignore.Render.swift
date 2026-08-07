import CI_Contract

extension CI.Canon.Gitignore {
    /// The propagation half of the gitignore pair — the Swift owner of
    /// `.github/scripts/render-gitignore.py`, driven by
    /// `sync-gitignore.yml`.
    ///
    /// Rendering is deterministic and byte-compared by the caller, so a
    /// repository that is already conformant produces no commit. Nothing
    /// a package wrote is discarded: a pre-canonical file, which has no
    /// terminator, is preserved *whole* beneath a freshly prepended
    /// canonical section per the 2026-03-12 gitignore-sync-strategy
    /// decision. Replacing it would delete rules a package deliberately
    /// added, and that is not recoverable from the diff alone.
    public struct Render: Sendable, Equatable {
        /// The canonical half of canon, resolved once at construction.
        /// Canon being unusable is a refusal about the control plane, and
        /// it is settled here so that applying the renderer to a package
        /// cannot fail at all.
        public let canonical: String

        /// The whole canon text, emitted verbatim when the package has no
        /// `.gitignore` yet.
        public let canon: String

        public init(canon: CI.Canon.Gitignore) throws(Error) {
            guard let canonical = canon.canonical else { throw .terminatorAbsent }
            self.canonical = canonical
            self.canon = canon.text
        }
    }
}

extension CI.Canon.Gitignore.Render {
    /// The header that introduces a preserved pre-canonical file.
    /// Emitted byte-for-byte as the retired renderer emitted it —
    /// leading newline included — because every already-synced
    /// repository carries this text and a changed byte is a commit
    /// against every one of them.
    public static let preservedHeader = """

        # ========== LOCAL OVERRIDES ==========
        # Preserved verbatim from this package's pre-canonical .gitignore. Rules here
        # may duplicate the canonical section above; that is harmless, and deleting
        # them is not this script's call to make.

        """

    /// The file to write into a package, given the package's current
    /// `.gitignore` (`nil` when it has none).
    public func callAsFunction(over existing: CI.Canon.Gitignore?) -> String {
        guard let existing else {
            // No file at all: canon already carries an empty LOCAL
            // OVERRIDES block, so it is emitted whole rather than
            // truncated at the terminator.
            return canon
        }
        if let local = existing.local { return canonical + local }
        return canonical + Self.preservedHeader + "\n"
            + String(existing.text.drop(while: { $0 == "\n" }))
    }

    /// The one way a canonical document refuses.
    ///
    /// Refusing is about *canon*, never about the package under it: an
    /// unusable control-plane document is not a verdict on any
    /// repository, and the two must not travel on the same channel.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Canon carries no `END CANONICAL` terminator.
        case terminatorAbsent

        public var message: String {
            switch self {
            case .terminatorAbsent:
                "canon has no \(CI.Canon.Gitignore.terminator) marker"
            }
        }
    }
}
