extension CI.Contract {
    /// The package-relevant part of a repository change.
    ///
    /// This classifier is deliberately fail closed. A path is non-package
    /// content only when it belongs to the small, repository-independent
    /// documentation/provenance vocabulary below. Everything else can alter
    /// resolution, compilation, or tests and therefore selects package work.
    public enum Package {
        public struct Content: Sendable, Equatable {
            public struct Change: Sendable, Equatable {
                public let path: String
                public let previousPath: String?

                public init(path: String, previousPath: String? = nil) {
                    self.path = path
                    self.previousPath = previousPath
                }

                var paths: [String] { [path, previousPath].compactMap { $0 } }
            }

            public let declaredRoots: Set<String>

            public init(declaredRoots: some Sequence<String>) {
                self.declaredRoots = Set(declaredRoots.map(Self.normalizedRoot)).union([""])
            }

            /// `true` means at least one path can affect package work. An
            /// empty, completely enumerated diff is non-package content; a
            /// missing or malformed enumeration is represented by the caller
            /// as a refusal, never as an empty list.
            public func changed(_ changes: [Change]) -> Bool {
                changes.contains { change in
                    change.paths.contains { affectsPackage($0) }
                }
            }

            func affectsPackage(_ rawPath: String) -> Bool {
                let path = Self.normalizedPath(rawPath)
                guard !path.isEmpty else { return true }
                if path == "Package.swift" || path.hasSuffix("/Package.swift") { return true }
                if path.hasPrefix(".swiftpm/") || path == ".swift-version"
                    || path.hasPrefix(".swift-version/") || path == "Package.resolved"
                {
                    return true
                }
                for root in declaredRoots
                where Self.isPackageInput(path, root: root) {
                    return true
                }
                return !Self.isKnownNonPackage(path)
            }

            static func isPackageInput(_ path: String, root: String) -> Bool {
                let prefix = root.isEmpty ? "" : root + "/"
                guard path.hasPrefix(prefix) else { return false }
                let relative = String(path.dropFirst(prefix.count))
                return ["Sources/", "Tests/", "Plugins/", "Resources/"].contains {
                    relative.hasPrefix($0)
                } || relative == "module.modulemap" || relative.hasSuffix(".modulemap")
                    || [".c", ".cc", ".cpp", ".h", ".m", ".mm"].contains {
                        relative.hasSuffix($0)
                    }
            }

            static func isKnownNonPackage(_ path: String) -> Bool {
                if ["Research/", "Experiments/", "Documentation/", "Docs/", "Provenance/"]
                    .contains(where: path.hasPrefix)
                {
                    return true
                }
                if path.hasPrefix(".snapshots/") { return true }
                if path.hasPrefix("README") && !path.contains("/") { return true }
                if ["LICENSE", "NOTICE", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", ".gitignore"]
                    .contains(path)
                {
                    return true
                }
                return path.hasSuffix(".md") && !path.hasPrefix("Sources/")
                    && !path.hasPrefix("Tests/")
            }

            static func normalizedRoot(_ root: String) -> String {
                let normalized = normalizedPath(root)
                return normalized == "." ? "" : normalized
            }

            static func normalizedPath(_ path: String) -> String {
                path.split(separator: "/").filter { $0 != "." && !$0.isEmpty }
                    .joined(separator: "/")
            }
        }
    }
}
