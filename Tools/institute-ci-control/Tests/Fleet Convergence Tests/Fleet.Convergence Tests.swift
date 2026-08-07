import Fleet_Convergence
import Fleet_Inventory
import Testing

@Suite
struct FleetConvergenceTests {
    func plan(_ count: Int = 3) -> Fleet.Convergence.Plan {
        .init(id: "wave-1", steps: (0..<count).map {
            .init(repository: "org/repo\($0)", coordinate: ".github/workflows/ci.yml",
                  preimageDigest: "pre\($0)", reversePayload: "old\($0)",
                  payload: "new\($0)")
        })
    }

    @Test
    func happyPathReachesTerminalReadback() throws {
        var apply = Fleet.Convergence.Apply(plan: plan(1))
        try apply.verifyPreimage(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml",
                                 observedDigest: "pre0")
        try apply.recordWrite(repository: "org/repo0",
                              coordinate: ".github/workflows/ci.yml")
        try apply.recordReadback(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml",
                                 digest: "post0")
        #expect(apply.terminal)
        #expect(apply.journal[0].readbackDigest == "post0")
    }

    @Test
    func preimageDriftRefusesTheWrite() {
        var apply = Fleet.Convergence.Apply(plan: plan(1))
        #expect(throws: Fleet.Convergence.Apply.Error.preimageDrift(
            repository: "org/repo0", expected: "pre0", observed: "drifted")) {
            try apply.verifyPreimage(repository: "org/repo0",
                                     coordinate: ".github/workflows/ci.yml",
                                     observedDigest: "drifted")
        }
    }

    @Test
    func writeWithoutPreimageVerificationIsIllegal() {
        var apply = Fleet.Convergence.Apply(plan: plan(1))
        #expect(throws: Fleet.Convergence.Apply.Error.illegalTransition(
            from: .pending, to: .written)) {
            try apply.recordWrite(repository: "org/repo0",
                                  coordinate: ".github/workflows/ci.yml")
        }
    }

    @Test
    func resumeContinuesNotRestarts() throws {
        let plan = plan(3)
        var apply = Fleet.Convergence.Apply(plan: plan)
        try apply.verifyPreimage(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml",
                                 observedDigest: "pre0")
        try apply.recordWrite(repository: "org/repo0",
                              coordinate: ".github/workflows/ci.yml")
        try apply.recordReadback(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml",
                                 digest: "post0")
        let state = try Fleet.Convergence.Resume.from(
            plan: plan, journal: apply.journal)
        #expect(state.remaining.map(\.repository) == ["org/repo1", "org/repo2"])
        #expect(state.apply.nextPending?.repository == "org/repo1")
    }

    @Test
    func shuffledJournalRefusesRehydration() {
        let plan = plan(2)
        let shuffled = [
            Fleet.Convergence.Apply.Entry(
                repository: "org/repo1", coordinate: ".github/workflows/ci.yml"),
            Fleet.Convergence.Apply.Entry(
                repository: "org/repo0", coordinate: ".github/workflows/ci.yml"),
        ]
        #expect(throws: Fleet.Convergence.Apply.Error.self) {
            try Fleet.Convergence.Resume.from(plan: plan, journal: shuffled)
        }
    }

    @Test
    func failureRollsBackAndTerminates() throws {
        var apply = Fleet.Convergence.Apply(plan: plan(1))
        try apply.verifyPreimage(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml",
                                 observedDigest: "pre0")
        try apply.recordFailure(repository: "org/repo0",
                                coordinate: ".github/workflows/ci.yml",
                                note: "write refused")
        try apply.recordRollback(repository: "org/repo0",
                                 coordinate: ".github/workflows/ci.yml")
        #expect(apply.terminal)
    }

    @Test
    func readbackConvergenceCompares() {
        let readback = Fleet.Convergence.Readback(
            repository: "org/repo0", coordinate: "c",
            expectedDigest: "d", observedDigest: "d")
        #expect(readback.converged)
    }

    @Test
    func censusRefusesUncontrolledZeroAndDuplicates() throws {
        #expect(throws: Fleet.Inventory.Census.Error.zeroWithoutPositiveControl) {
            try Fleet.Inventory.Census(rows: [], positiveControls: [])
        }
        let row = Fleet.Inventory.Census.Row(
            repository: "org/r", headSha: "h", callerBlobSha: "b",
            classification: "ordinary")
        #expect(throws: Fleet.Inventory.Census.Error.duplicateRepository("org/r")) {
            try Fleet.Inventory.Census(rows: [row, row], positiveControls: [])
        }
        let census = try Fleet.Inventory.Census(
            rows: [], positiveControls: [.init(name: "seeded", fired: true)])
        #expect(census.rows.isEmpty)
    }
}
