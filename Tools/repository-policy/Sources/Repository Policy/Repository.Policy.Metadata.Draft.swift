extension Repository.Policy.Metadata {
    /// The bootstrap seed for a repository that has no
    /// `.github/metadata.yaml` yet — the Swift owner of the decision half
    /// of `.github/scripts/generate-metadata.sh`.
    ///
    /// Scope is **first-time bootstrap only**, and has been since the
    /// Wave 2b Decision 6 pivot. A repository that already carries a
    /// `metadata.yaml` on its default branch is never re-drafted: the
    /// YAML is the source of truth from the moment it lands, and
    /// `sync-metadata` propagates *from* it. So this type answers one
    /// question — "what should a reviewer be shown first?" — and its
    /// output is explicitly provisional: every field it cannot infer is
    /// spelled `TODO`, in the draft, where a human sees it.
    ///
    /// Everything here is a pure function of the target name, the
    /// spec-title table, and (for a primitive) the package's own
    /// description. The clone, commit, and pull request that carry the
    /// draft stay in the workflow: they are plumbing, and mixing them in
    /// would make the classification untestable without a network.
    public struct Draft: Sendable, Equatable {
        public let target: String
        public let kind: Kind
        public let metadata: Repository.Policy.Metadata

        public init(target: String, kind: Kind, metadata: Repository.Policy.Metadata) {
            self.target = target
            self.kind = kind
            self.metadata = metadata
        }
    }
}

extension Repository.Policy.Metadata.Draft {
    /// The default homepage every class carries except the two that
    /// deliberately carry none.
    public static let homepage = "https://swift-institute.org"

    /// The tag a reviewer must replace before merging. Present in the
    /// draft on purpose: a topic set that looks finished is one nobody
    /// edits.
    public static let placeholderTopic = "TODO-domain-tag"

    /// Classify one `owner/name` target and draft its metadata.
    ///
    /// - Parameter packageDescription: the `description:` literal from
    ///   the target's `Package.swift`, when the caller could read one.
    ///   Consulted only for an `L1-primitive`, matching the retired
    ///   script, which fetched the manifest for that branch alone.
    public init(
        target: String,
        titles: Titles = .init(),
        packageDescription: String = ""
    ) throws(Repository.Policy.Metadata.Error) {
        self = try Self.classified(
            target: target, titles: titles, packageDescription: packageDescription)
    }

    /// The classification itself, as one expression per branch. Separate
    /// from the initializer only because an initializer cannot return
    /// early from a branch without leaving `self` half-assigned.
    private static func classified(
        target: String, titles: Titles, packageDescription: String
    ) throws(Repository.Policy.Metadata.Error) -> Self {
        let parts = target.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw .malformedRepository(target)
        }
        let owner = String(parts[0])
        let name = String(parts[1])
        let layer = layer(of: owner)
        let authority = authority(of: owner)

        if owner == "swift-ietf", let identifier = name.remainder(after: "swift-bcp-") {
            let title = titles["bcp", identifier]
            return Self(
                target: target, kind: .namedStandard,
                metadata: .init(
                    description: title.map { "Swift implementation of BCP \(identifier): \($0)." }
                        ?? "Swift implementation of BCP \(identifier): "
                            + "TODO add title to spec-titles.yaml.",
                    topics: ["standards", "ietf", "bcp", "bcp-\(identifier)", placeholderTopic],
                    homepage: homepage))
        }

        if !authority.isEmpty, let identifier = name.remainder(after: "swift-\(authority)-") {
            return specification(
                target: target, layer: layer, authority: authority, identifier: identifier,
                titles: titles)
        }

        if name == ".github" {
            return Self(
                target: target, kind: .organizationDefaults,
                metadata: .init(
                    description: "Organization-level community-health defaults for \(owner).",
                    topics: [], homepage: ""))
        }

        if let stub = name.websiteStubLayer {
            return Self(
                target: target, kind: .websiteStub,
                metadata: .init(
                    description: "Stub for the future swift-\(stub).org website. Content will "
                        + "be developed; for now, see \(homepage).",
                    topics: [], homepage: homepage))
        }

        if name.hasSuffix("-primitives") {
            return Self(
                target: target, kind: .primitive,
                metadata: .init(
                    description: packageDescription.isEmpty
                        ? "TODO content phrase for Swift." : "\(packageDescription) for Swift.",
                    topics: ["primitives", placeholderTopic], homepage: homepage))
        }

        return Self(
            target: target, kind: .other,
            metadata: .init(
                description: "TODO content phrase for Swift.",
                topics: [layer.isEmpty ? "foundations" : layer, placeholderTopic],
                homepage: homepage))
    }

    /// The two authority-spec branches: a numbered spec, and a spec named
    /// rather than numbered.
    ///
    /// The ISO fallback is the one place the table is consulted twice. A
    /// joint spec is filed under `iso-iec`, and when it is found there
    /// the *whole* projection changes — the authority reads `ISO/IEC` in
    /// the description and the topic set gains `iso-iec` — so the second
    /// lookup cannot be folded into the first.
    private static func specification(
        target: String, layer: String, authority: String, identifier: String, titles: Titles
    ) -> Self {
        let upper = authority.uppercased()
        guard identifier.isSpecificationNumber else {
            let title = titles[authority, identifier]
            return Self(
                target: target, kind: .namedStandard,
                metadata: .init(
                    description: title.map { "Swift implementation of \(upper) \($0)." }
                        ?? "Swift implementation of \(upper) TODO-standard-name.",
                    topics: [layer, authority, placeholderTopic], homepage: homepage))
        }
        var name = upper
        var title = titles[authority, identifier]
        var topics: [String] = []
        if authority == "iso", title == nil, let joint = titles["iso-iec", identifier] {
            name = "ISO/IEC"
            title = joint
            topics = [layer, "iso", "iso-iec", "iso-\(identifier)", placeholderTopic]
        }
        if topics.isEmpty {
            topics = [layer, authority, "\(authority)-\(identifier)", placeholderTopic]
        }
        return Self(
            target: target, kind: .singleSpec,
            metadata: .init(
                description: title.map { "Swift implementation of \(name) \(identifier): \($0)." }
                    ?? "Swift implementation of \(name) \(identifier): "
                        + "TODO add title to spec-titles.yaml.",
                topics: topics, homepage: homepage))
    }

    /// The Institute layer an organization belongs to, or the empty
    /// string when the organization names none.
    static func layer(of owner: String) -> String {
        switch owner {
        case "swift-primitives": "primitives"
        case "swift-standards": "standards"
        case "swift-foundations": "foundations"
        case "swift-ietf", "swift-iso", "swift-ieee", "swift-iec", "swift-w3c", "swift-whatwg",
            "swift-ecma", "swift-incits":
            "standards"
        default: ""
        }
    }

    /// The standards authority an organization publishes for, or the
    /// empty string.
    static func authority(of owner: String) -> String {
        switch owner {
        case "swift-ietf": "rfc"
        case "swift-iso": "iso"
        case "swift-ieee": "ieee"
        case "swift-iec": "iec"
        case "swift-w3c": "w3c"
        case "swift-whatwg": "whatwg"
        case "swift-ecma": "ecma"
        case "swift-incits": "incits"
        default: ""
        }
    }
}

extension String {
    /// The remainder after `prefix`, or `nil` when the value does not
    /// carry it or carries nothing after it — the `^prefix(.+)$` match
    /// the retired script wrote as a bash regex.
    fileprivate func remainder(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let remainder = dropFirst(prefix.count)
        return remainder.isEmpty ? nil : String(remainder)
    }

    /// The layer named by a `swift-<layer>.org` repository, or `nil`.
    fileprivate var websiteStubLayer: String? {
        guard hasSuffix(".org"), let layer = String(dropLast(4)).remainder(after: "swift-") else { return nil }
        return layer
    }

    /// Whether the value is a spec *number* — `9945`, `10646-1` — rather
    /// than a spec name.
    fileprivate var isSpecificationNumber: Bool {
        let groups = split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count <= 2, !groups.isEmpty else { return false }
        return groups.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
