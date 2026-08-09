import Foundation
import Repository_Policy
import Testing

extension Repository.Policy.Approval.Caller {
    @Suite struct Convergence {
        @Suite struct Unit {
            let source = Data("canonical private caller\n".utf8)
        }
    }
}

extension Repository.Policy.Approval.Caller.Convergence.Unit {
    @Test
    func `an absent private caller requires a guarded pull request`() throws {
        let decision = try Repository.Policy.Approval.Caller.decision(
            state: .init(
                visibility: "private",
                archived: false,
                branch: "main",
                file: nil
            ),
            source: source
        )
        #expect(decision == .pullRequest(base: "main", revision: nil))
    }

    @Test
    func `exact canonical bytes are converged`() throws {
        let decision = try Repository.Policy.Approval.Caller.decision(
            state: .init(
                visibility: "private",
                archived: false,
                branch: "main",
                file: .init(revision: "source-revision", contents: source)
            ),
            source: source
        )
        #expect(decision == .converged)
    }

    @Test
    func `a stale caller carries its guarded revision into the proposal`() throws {
        let decision = try Repository.Policy.Approval.Caller.decision(
            state: .init(
                visibility: "private",
                archived: false,
                branch: "main",
                file: .init(
                    revision: "source-revision",
                    contents: Data("stale\n".utf8)
                )
            ),
            source: source
        )
        #expect(decision == .pullRequest(base: "main", revision: "source-revision"))
    }

    @Test(arguments: [
        Repository.Policy.Approval.Caller.State(
            visibility: "public", archived: false, branch: "main", file: nil
        ),
        Repository.Policy.Approval.Caller.State(
            visibility: "private", archived: true, branch: "main", file: nil
        ),
        Repository.Policy.Approval.Caller.State(
            visibility: "private", archived: false, branch: "", file: nil
        ),
    ])
    func `a non private or inactive target fails closed`(
        _ state: Repository.Policy.Approval.Caller.State
    ) {
        #expect(throws: Repository.Policy.Approval.Caller.Error.self) {
            try Repository.Policy.Approval.Caller.decision(state: state, source: source)
        }
    }

    @Test
    func `the public receipt carries only aggregate counts`() throws {
        let receipt = Repository.Policy.Approval.Caller.Receipt(
            examined: 2,
            proposed: 1,
            opened: 1,
            dryRun: false
        )
        let encoded = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
        #expect(encoded.contains("\"examined\":2"))
        #expect(encoded.contains("\"proposed\":1"))
        #expect(encoded.contains("\"opened\":1"))
        #expect(!encoded.contains("repository"))
        #expect(!encoded.contains("target"))
    }
}
