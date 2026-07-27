import Foundation
import Repository_Policy
import Testing

@Suite
struct RepositoryPolicyTests {
    @Test
    func eligibilityFixtures() throws {
        let url = try #require(Bundle.module.url(forResource: "eligibility", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))

        #expect(fixtures.count == 9)
        for fixture in fixtures {
            let state = fixture.pvr.flatMap(RepositoryPolicy.VulnerabilityReporting.init(rawValue:))
            let decision = RepositoryPolicy.decision(
                for: fixture.repository,
                manifestKind: fixture.manifestKind,
                vulnerabilityReporting: state
            )
            #expect(render(decision) == fixture.decision, "\(fixture.name)")
        }
    }

    @Test
    func scopeRejectsDeniedOwner() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: nil,
                repository: "tenthijeboonkkamp/package"
            )
        }
    }

    @Test
    func scopeRequiresExactlyOneSelector() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(organization: nil, repository: nil)
        }
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: "swift-foundations",
                repository: "swift-foundations/swift-example"
            )
        }
    }

    private func render(_ decision: RepositoryPolicy.Decision) -> String {
        switch decision {
        case .excluded(let reason): reason.rawValue
        case .converged: "converged"
        case .enable: "enable"
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let repository: RepositoryPolicy.Repository
        let manifestKind: String?
        let pvr: String?
        let decision: String

        enum CodingKeys: String, CodingKey {
            case name
            case repository
            case manifestKind = "manifest_kind"
            case pvr
            case decision
        }
    }
}
