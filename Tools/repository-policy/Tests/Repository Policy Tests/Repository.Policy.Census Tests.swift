import Foundation
import Repository_Policy
import Testing

@Suite
struct RepositoryPolicyCensusTests {
    @Test
    func csvQuotingMatchesMinimalDialect() {
        #expect(Repository.Policy.Census.quoted("plain") == "plain")
        #expect(Repository.Policy.Census.quoted("a,b") == "\"a,b\"")
        #expect(Repository.Policy.Census.quoted("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(Repository.Policy.Census.quoted("line\nbreak") == "\"line\nbreak\"")
    }

    @Test
    func generatorScansWorkflowCoordinates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("census-fixture-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let workflows = root + "/.github/workflows"
        try FileManager.default.createDirectory(
            atPath: workflows, withIntermediateDirectories: true)
        let yaml = """
        on: push
        jobs:
          demo:
            runs-on: ${{ matrix.os }}
            steps:
              - uses: actions/checkout@0000000000000000000000000000000000000000
              - name: block
                run: |
                  python3 script.py
                  echo done
              - name: inline
                run: gh api /rate_limit
        """
        try Data(yaml.utf8).write(
            to: URL(fileURLWithPath: workflows + "/demo.yml"))
        let census = try Repository.Policy.Census.Generator(
            repos: [.init(name: "fixture/repo", root: root, headSha: String(repeating: "a", count: 40))]
        ).run()
        func rows(_ kind: Repository.Policy.Census.Kind) -> [Repository.Policy.Census.Row] {
            census.rows.filter { $0.coordinateKind == kind && $0.repository == "fixture/repo" }
        }
        #expect(rows(.file).count == 1)
        #expect(rows(.expression).count == 1)
        #expect(rows(.usesEdge).count == 1)
        #expect(rows(.usesEdge).first?.notes.hasPrefix("actions/checkout@") == true)
        #expect(rows(.runBlock).count == 2)
        // `python3` and `gh` count; `echo` is a skip-listed builtin.
        #expect(rows(.commandReference).map(\.notes).sorted() == ["gh", "python3"])
        // Frozen family and sentinel rows always present.
        #expect(census.rows.contains { $0.coordinateId == "family:leaf-callers" })
        #expect(census.rows.filter { $0.measurement == "UNMEASURED" }.count == 5)
    }

    @Test
    func capabilityRecordsAreFrozen() throws {
        #expect(Repository.Policy.Capability.records.count == 12)
        #expect(Repository.Policy.Capability.records.first?.id == "D-01")
        let data = try Repository.Policy.Capability.recordsJSON()
        let decoded = try JSONDecoder().decode(
            [Repository.Policy.Capability].self, from: data)
        #expect(decoded == Repository.Policy.Capability.records)
    }
}
