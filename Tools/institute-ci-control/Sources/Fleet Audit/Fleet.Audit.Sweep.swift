extension Fleet.Audit {
    /// The accumulation the cron sweep performs over one org.
    ///
    /// `cron-audit-runner.py` interleaved four concerns in one loop:
    /// listing an org, cloning each target, running the audit, and
    /// adding up what came back. Only the last is a decision. It is
    /// therefore the only part here — the sweep takes reports and
    /// produces the three artefacts the workflow publishes, and never
    /// learns what a clone or a token is.
    public struct Sweep: Sendable, Equatable {
        public let organization: String
        public let configuration: Configuration

        public init(organization: String, configuration: Configuration) {
            self.organization = organization
            self.configuration = configuration
        }

        /// What one org's sweep produced.
        public struct Outcome: Sendable, Equatable {
            /// Counter totals across every package that reported.
            public let totals: [String: Int]
            /// Rendered per-package lines, in report order.
            public let perPackage: [String]

            /// The `<org>-counts.txt` body: totals in `countKeys` order,
            /// comma-separated, one trailing newline. Positional, and
            /// read positionally by the caller's `count-labels`.
            public func countsArtefact(keys: [String]) -> String {
                keys.map { String(totals[$0] ?? 0) }.joined(separator: ",") + "\n"
            }

            /// The `<org>-extra.txt` body, or `nil` when no package
            /// qualified — the retired runner wrote no file at all in
            /// that case and `upload-artifact` was told to ignore it.
            public var extraArtefact: String? {
                perPackage.isEmpty ? nil : perPackage.joined(separator: "\n") + "\n"
            }

            /// The markdown appended to `GITHUB_STEP_SUMMARY`.
            public func summary(organization: String, label: String, keys: [String]) -> String {
                var text = "## Org \(organization) — \(label)\n"
                for key in keys { text += "- \(key): \(totals[key] ?? 0)\n" }
                return text
            }
        }

        public enum Error: Swift.Error, Equatable {
            /// A per-package template named something the report has no
            /// counter for. The retired runner raised `KeyError` here;
            /// naming the placeholder is the whole improvement.
            case unknownPlaceholder(String)
            /// An unbalanced brace in the template.
            case malformedTemplate(String)
        }

        /// Accumulate reports into the sweep's artefacts.
        public func accumulate(
            _ reports: [(package: String, report: Report)]
        ) throws(Error) -> Outcome {
            var totals: [String: Int] = [:]
            for key in configuration.countKeys { totals[key] = 0 }
            var perPackage: [String] = []

            for (package, report) in reports {
                for key in configuration.countKeys {
                    totals[key, default: 0] += report.counters[key] ?? 0
                }
                guard !configuration.extraTemplate.isEmpty else { continue }
                let qualifies = configuration.extraWhenKeys.contains {
                    (report.counters[$0] ?? 0) > 0
                }
                guard qualifies else { continue }
                perPackage.append(
                    try Self.render(
                        configuration.extraTemplate,
                        package: package,
                        counters: report.counters))
            }
            return Outcome(totals: totals, perPackage: perPackage)
        }

        /// Render a per-package template.
        ///
        /// The retired runner reached `str.format`, which is a general
        /// evaluator over caller-controlled text — attribute access,
        /// indexing and format specs all included — reached for named
        /// substitution. This is the substitution and nothing else:
        /// `{pkg}`, `{counter}`, and `{{` / `}}` for a literal brace.
        static func render(
            _ template: String, package: String, counters: [String: Int]
        ) throws(Error) -> String {
            var output = ""
            var rest = Substring(template)
            while let open = rest.firstIndex(where: { $0 == "{" || $0 == "}" }) {
                output += rest[rest.startIndex..<open]
                let character = rest[open]
                let after = rest.index(after: open)
                if after < rest.endIndex, rest[after] == character {
                    output.append(character)
                    rest = rest[rest.index(after: after)...]
                    continue
                }
                guard character == "{", let close = rest[after...].firstIndex(of: "}") else {
                    throw .malformedTemplate(template)
                }
                let name = String(rest[after..<close])
                if name == "pkg" {
                    output += package
                } else if let value = counters[name] {
                    output += String(value)
                } else {
                    throw .unknownPlaceholder(name)
                }
                rest = rest[rest.index(after: close)...]
            }
            return output + rest
        }
    }
}
