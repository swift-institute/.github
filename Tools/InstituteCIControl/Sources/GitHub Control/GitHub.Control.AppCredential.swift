import GitHub

extension GitHub.Control {
    /// A minted App installation token, scoped per step. Minting is
    /// composed through the sanctioned Workspace command boundary
    /// (`workspace github token --org … --permission …`), which owns App
    /// identity and RS256 signing (D-01); this package never sees the
    /// private key and implements no signing. The token value is held
    /// only for the step's lifetime and never logged.
    public struct AppCredential: Sendable {
        public let organization: String
        /// Narrowed permissions requested at mint (name=level); empty
        /// means the installation's whole grant, which trusted steps
        /// should avoid.
        public let permissions: [String: String]
        public let token: String

        public init(
            organization: String, permissions: [String: String],
            token: String
        ) {
            self.organization = organization
            self.permissions = permissions
            self.token = token
        }

        /// The exact argument vector for the sanctioned mint. The caller
        /// executes it through its process owner and constructs the
        /// credential from stdout; the vector is data so tests can prove
        /// the composition without minting.
        public static func mintArguments(
            organization: String, permissions: [String: String]
        ) -> [String] {
            var arguments = ["github", "token", "--org", organization]
            for (name, level) in permissions.sorted(by: { $0.key < $1.key }) {
                arguments += ["--permission", "\(name)=\(level)"]
            }
            return arguments
        }
    }
}
