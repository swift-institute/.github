import CI_Contract
import CI_Workflow
import Foundation
import Testing

@testable import CI_Inventory

/// The two gates the retired `test-verdict-inventory.py` existed for,
/// re-derived for the current topology.
///
/// **Drift** — the committed corpus must equal what deriving the
/// inventory from *this checkout's* `swift-ci.yml` produces right now,
/// byte for byte. A workflow edit that changes the verdict's shape and
/// leaves the corpus alone is a test failure, not silent staleness.
///
/// **Reality** — the corpus must agree with a real hosted full-tier run.
/// This is the half the retired suite never had: it compared the
/// inventory only against the YAML it was derived from, so an inventory
/// could be perfectly faithful to a workflow that no longer described
/// what GitHub actually ran. The recorded run is
/// `swift-primitives/swift-cache-primitives` **31151036569**
/// (`workflow_dispatch` on `main`, conclusion `success`), read from the
/// run object and its jobs, and vendored here verbatim.
@Suite
struct CIInventoryDriftTests {
    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    @Test func `the committed corpus is what the shipped workflow derives to`() throws {
        let derived = try CIInventoryTests.shipped().canonicalJSON + "\n"
        let committed = try String(
            contentsOf: Self.fixtures.appendingPathComponent("verdict-inventory.json"),
            encoding: .utf8)
        #expect(
            derived == committed,
            """
            verdict-inventory.json is stale relative to \
            .github/workflows/swift-ci.yml. Regenerate it:
              institute-ci verdict-inventory --universal .github/workflows/swift-ci.yml \\
                > 'Tools/institute-ci/Tests/CI Inventory Tests/Fixtures/verdict-inventory.json'
            """)
    }

    // MARK: - The live run

    /// One job of the recorded run.
    struct ObservedJob {
        let name: String
        let conclusion: String

        /// The job's own display name: the run reports every job of the
        /// universal under the caller's `ci / matrix / ` prefix — which
        /// is the one-hop topology, visible in the wire format — and a
        /// job that itself delegates adds a further ` / <step job>`
        /// segment.
        var displayName: String? {
            let prefix = "ci / matrix / "
            guard name.hasPrefix(prefix) else { return nil }
            return name.dropFirst(prefix.count).components(separatedBy: " / ").first
        }
    }

    static func recordedRun() throws -> [String: Any] {
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("run-31151036569.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func observedJobs() throws -> [ObservedJob] {
        let jobs = try #require(try recordedRun()["jobs"] as? [[String: Any]])
        return jobs.map {
            ObservedJob(
                name: $0["name"] as? String ?? "",
                conclusion: $0["conclusion"] as? String ?? "")
        }
    }

    /// Whether a rendered display name could have come from a job's
    /// `name:` template. `${{ … }}` expansions are unknowable outside a
    /// run, so each becomes a hole and the surrounding literals must
    /// appear in order.
    static func rendered(_ candidate: String, matches template: String) -> Bool {
        var literals: [String] = []
        var current = ""
        var rest = Substring(template)
        while let start = rest.range(of: "${{") {
            current += rest[rest.startIndex..<start.lowerBound]
            literals.append(current)
            current = ""
            guard let end = rest.range(of: "}}", range: start.upperBound..<rest.endIndex) else {
                return false
            }
            rest = rest[end.upperBound...]
        }
        literals.append(current + rest)

        guard candidate.hasPrefix(literals.first ?? "") else { return false }
        guard candidate.hasSuffix(literals.last ?? "") else { return false }
        var cursor = candidate.index(candidate.startIndex, offsetBy: (literals.first ?? "").count)
        for literal in literals.dropFirst() where !literal.isEmpty {
            guard let found = candidate.range(of: literal, range: cursor..<candidate.endIndex)
            else { return false }
            cursor = found.upperBound
        }
        return true
    }

    /// Which declared job produced a rendered display name.
    ///
    /// Most-specific-wins, and it is needed. Three of the shipped
    /// templates overlap: `linux-release` is
    /// `Ubuntu (Swift ${{ inputs.swift-version }}, release)`, whose hole
    /// also swallows the *literal* names of `linux-nightly`
    /// (`Ubuntu (Swift main nightly, release)`) and `linux-6-4`
    /// (`Ubuntu (Swift 6.4.x nightly, release)`). A name carrying no
    /// hole is the more specific pattern and takes the match; the
    /// wildcard only claims what no literal did.
    ///
    /// This is a real property of the shipped workflow, not an artefact
    /// of the matcher: a reader of a run — human or machine — cannot
    /// resolve those three job names from the wire format alone either.
    static func resolve(
        _ displayName: String, in universal: CI.Inventory.Universal
    ) -> [CI.Inventory.Job] {
        let candidates = universal.jobs.filter {
            rendered(displayName, matches: $0.displayName ?? $0.id)
        }
        let literal = candidates.filter { !($0.displayName ?? $0.id).contains("${{") }
        return literal.isEmpty ? candidates : literal
    }

    @Test func `every job the live run reported resolves to exactly one declared job`() throws {
        let universal = try CIInventoryTests.shipped().universal
        for observed in try Self.observedJobs() {
            let displayName = try #require(
                observed.displayName,
                "'\(observed.name)' is not under the one-hop 'ci / matrix / ' prefix")
            let matches = Self.resolve(displayName, in: universal)
            #expect(matches.count == 1, "'\(displayName)' resolved to \(matches.map(\.id))")
        }
    }

    @Test func `every job the inventory declares appeared in the live full-tier run`() throws {
        let universal = try CIInventoryTests.shipped().universal
        let resolved = Set(
            try Self.observedJobs()
                .compactMap(\.displayName)
                .flatMap { Self.resolve($0, in: universal).map(\.id) })
        for job in universal.jobs {
            #expect(
                resolved.contains(job.id),
                "declared job '\(job.id)' produced no job in run 31151036569")
        }
    }

    @Test func `every gating job the inventory names succeeded in the live run`() throws {
        let universal = try CIInventoryTests.shipped().universal
        let observed = try Self.observedJobs()
        for id in universal.aggregate.gatingJobs {
            let reported = observed.filter { job in
                job.displayName.map { Self.resolve($0, in: universal).map(\.id) == [id] } ?? false
            }
            #expect(!reported.isEmpty, "gating job '\(id)' did not report")
            #expect(
                reported.allSatisfy { $0.conclusion == "success" },
                "gating job '\(id)' reported \(reported.map(\.conclusion))")
        }
    }

    @Test func `the recorded run is a green full-tier run on main`() throws {
        let run = try Self.recordedRun()
        #expect(run["conclusion"] as? String == "success")
        #expect(run["event"] as? String == "workflow_dispatch")
    }

    @Test func `the aggregate itself reported success under the one-hop context`() throws {
        let observed = try Self.observedJobs()
        let aggregate = observed.filter { $0.name == CI.Inventory.Aggregate.checkContext }
        #expect(aggregate.count == 1, "the required check context did not appear exactly once")
        #expect(aggregate.first?.conclusion == "success")
    }

    @Test func `a matrix job is the only place one declared job reports more than once`() throws {
        let universal = try CIInventoryTests.shipped().universal
        let observed = try Self.observedJobs().compactMap(\.displayName)
        for job in universal.jobs where !job.hasMatrix {
            let count = observed.filter { Self.resolve($0, in: universal).map(\.id) == [job.id] }
                .count
            #expect(count <= 1, "non-matrix job '\(job.id)' reported \(count) times")
        }
    }
}
