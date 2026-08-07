extension Repository.Policy.Metadata.Draft {
    /// The class a repository is detected to be, from its owner and name
    /// alone.
    ///
    /// Mechanical on purpose: no network call and no file read decides
    /// it, so the same target always drafts the same class. The token is
    /// written into the draft's header comment, and a reviewer reading
    /// `# Detected class: L2-single-spec` is being told which branch
    /// produced everything below it.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// `swift-iso-9945`, `swift-rfc-3986` — one numbered spec.
        case singleSpec = "L2-single-spec"
        /// `swift-bcp-47`, or an authority spec named rather than
        /// numbered.
        case namedStandard = "L2-named-standard"
        /// `swift-byte-primitives` and siblings.
        case primitive = "L1-primitive"
        /// An organization's `.github` repository.
        case organizationDefaults = "org-github"
        /// `swift-<layer>.org` — a placeholder for a future website.
        case websiteStub = "org-website-stub"
        /// Everything else.
        case other = "L3-foundation-or-other"
    }
}
