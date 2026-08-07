import Foundation

extension Fleet.Audit {
    /// The caller-supplied sweep configuration.
    ///
    /// This is the typed form of `cron-audit-base.yml`'s
    /// `audit-runner-args` JSON — the structured-input contract from
    /// Phase C of the 2026-05-14 CI review ([CI-081]), which exists so a
    /// caller can configure the credentialed job without handing it a
    /// shell string. Keeping it a decoded value rather than a dictionary
    /// preserves that property in Swift: there is no member here that
    /// can become a command.
    public struct Configuration: Sendable, Equatable {
        /// Dotted path to the totals object inside an audit report.
        /// Empty means the report's own root.
        public let totalsPath: String

        /// The counter names, in the order the counts artefact lists
        /// them. Order is load-bearing: `count-labels` on the caller
        /// side is positional.
        public let countKeys: [String]

        /// Per-package line template, `{pkg}` plus one placeholder per
        /// count key. Empty disables the per-package artefact.
        public let extraTemplate: String

        /// The counters whose being positive admits a per-package line.
        /// Defaults to every count key.
        public let extraWhenKeys: [String]

        /// Human label for the step summary heading.
        public let summaryLabel: String

        public enum Error: Swift.Error, Equatable {
            case malformedJSON
            case notAnObject
            case wrongType(member: String)
        }

        public init(
            totalsPath: String = "totals",
            countKeys: [String] = [],
            extraTemplate: String = "",
            extraWhenKeys: [String]? = nil,
            summaryLabel: String = "audit"
        ) {
            self.totalsPath = totalsPath
            self.countKeys = countKeys
            self.extraTemplate = extraTemplate
            self.extraWhenKeys = extraWhenKeys ?? countKeys
            self.summaryLabel = summaryLabel
        }

        /// Decode the caller's `audit-runner-args` document.
        ///
        /// Absent members take the retired runner's defaults rather than
        /// refusing, because three live callers rely on them; a member
        /// that is present with the wrong type refuses, where the
        /// retired runner would have raised somewhere further in.
        public init(json text: String) throws(Error) {
            guard let data = text.data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data)
            else { throw .malformedJSON }
            guard let object = any as? [String: Any] else { throw .notAnObject }

            func string(_ member: String, default fallback: String) throws(Error) -> String {
                guard let raw = object[member] else { return fallback }
                guard let value = raw as? String else { throw .wrongType(member: member) }
                return value
            }
            func strings(_ member: String) throws(Error) -> [String]? {
                guard let raw = object[member] else { return nil }
                guard let value = raw as? [String] else { throw .wrongType(member: member) }
                return value
            }

            let countKeys = try strings("count_keys") ?? []
            self.init(
                totalsPath: try string("json_totals_path", default: "totals"),
                countKeys: countKeys,
                extraTemplate: try string("extra_template", default: ""),
                extraWhenKeys: try strings("extra_when_keys"),
                summaryLabel: try string("summary_label", default: "audit"))
        }
    }
}
