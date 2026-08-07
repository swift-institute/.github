import CI_Contract

extension CI.Validation {
    /// One validator invocation's whole result, in the shape a front end
    /// needs: what to print, and what to exit with.
    ///
    /// Front ends must not re-derive the exit code. The 0/1/2 triple is
    /// the contract's most misread part — `2` is an environment defect
    /// and explicitly *not* a finding — and every place that re-derived
    /// it was a place it could be re-derived wrongly.
    public struct Run: Sendable, Equatable {
        public let findings: [Finding]
        public let defect: EnvironmentDefect?

        public init(findings: [Finding], defect: EnvironmentDefect? = nil) {
            self.findings = findings
            self.defect = defect
        }

        /// Run one validator over one subject, catching the defect.
        public static func validate(_ validator: any Validator, of subject: Subject) -> Self {
            do {
                return Self(findings: try validator.findings(in: subject))
            } catch {
                return Self(findings: [], defect: error)
            }
        }

        /// The TSV body, one finding per line, in discovery order.
        public var tsv: String {
            findings.map(\.tsv).joined(separator: "\n")
        }

        /// `2` for an environment defect, `0` otherwise — **findings do
        /// not affect the exit code.**
        ///
        /// The retired corpus ran two incompatible conventions side by
        /// side, which `validate-base.yml` had to absorb with a
        /// `crash-exit-min` input: 17 scripts called `main()` bare and
        /// always exited `0`, while 19 called `sys.exit(main(...))` and
        /// returned the finding *count*. The second is a live defect —
        /// a run with exactly two findings exits `2`, which is the
        /// environment-defect code, so a dirty repository reports as a
        /// broken machine. Counts above 255 wrap, too.
        ///
        /// Findings travel on stdout as TSV; that is the channel
        /// `validate-base.yml` aggregates. The exit code answers a
        /// different question — *did the validator run?* — so it carries
        /// only that.
        ///
        /// This normalisation composes with both existing caller
        /// settings. Under `crash-exit-min: 1` (every pre-existing
        /// caller) findings exit `0` and a defect's `2` is a crash; under
        /// `crash-exit-min: 2` the same holds. No caller needs changing.
        public var exitCode: Int32 {
            defect == nil ? 0 : EnvironmentDefect.exitCode
        }
    }
}
