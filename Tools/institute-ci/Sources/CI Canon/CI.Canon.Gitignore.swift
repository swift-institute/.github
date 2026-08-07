import CI_Contract

extension CI.Canon {
    /// A package `.gitignore`, read as the two-part document the canon
    /// defines it to be.
    ///
    /// ```
    /// # ========== CANONICAL (auto-synced, do not edit) ==========
    /// …                          <- owned by canon, replaced wholesale
    /// # ========== END CANONICAL ==========
    /// …                          <- owned by the package, PRESERVED
    /// ```
    ///
    /// The canonical text is a **whitelist**: `/*` denies every top-level
    /// entry and the `!/…` lines re-include the ones that carry real
    /// work, plus `**/.*/` denying tool-state dot-directories at every
    /// depth. That posture is why `.swift-lint/` — 3,384 files written
    /// into the worktree by swift-linter — was already ignored in every
    /// repository carrying the canonical file, without anyone having
    /// named it.
    ///
    /// This type owns exactly one thing: where the canonical half ends.
    /// Both consumers ask it — the renderer that splices canon over a
    /// package's own tail, and the `[GH-IGNORE-001]` predicate that
    /// compares the two halves — so a marker change cannot land in one
    /// and miss the other.
    public struct Gitignore: Sendable, Equatable {
        /// The line that closes the canonical half. Matched as a
        /// substring, exactly as the retired pair matched it, so a file
        /// with trailing content on the marker line is still recognised.
        public static let terminator = "# ========== END CANONICAL =========="

        public let text: String

        public init(_ text: String) {
            self.text = text
        }

        /// The canonical half — everything through the terminator, plus
        /// the newline that closes it — or `nil` when the file carries no
        /// terminator at all.
        ///
        /// `nil` is the *pre-canonical* file: one written before the
        /// whitelist existed. It is a finding under `[GH-IGNORE-001]` and
        /// a preserve-verbatim case for the renderer; the two readings
        /// are different, which is why this returns the absence rather
        /// than deciding it.
        public var canonical: String? {
            guard let range = text.firstRange(of: Self.terminator) else { return nil }
            return String(text[text.startIndex..<range.upperBound]) + "\n"
        }

        /// The package's own half — everything after the terminator's
        /// line — or `nil` when the file is pre-canonical.
        ///
        /// One character past the terminator is dropped: the newline that
        /// ends the marker line, which `canonical` re-supplies. Without
        /// that, splicing the two halves back together doubles it.
        public var local: String? {
            guard let range = text.firstRange(of: Self.terminator) else { return nil }
            let tail = text[range.upperBound...]
            return tail.isEmpty ? "" : String(tail.dropFirst())
        }
    }
}
