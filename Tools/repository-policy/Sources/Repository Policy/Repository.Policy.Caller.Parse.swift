extension Repository.Policy.Caller {
    /// The inverse of `Render`: a rendered caller, read back to the spec
    /// that models it.
    ///
    /// This is the half of the retired `generate-caller.py` that had no
    /// Swift owner — `parse_existing_caller` plus the `parse` CLI mode
    /// (F16 C3; the named owner gap on swift-institute/.github#404).
    ///
    /// Three admissible input shapes, and nothing else:
    ///
    /// - **legacy two-job** (`ci` + `docs`) — the pre-TX8 fleet shape, in
    ///   which the `docs:` job calls the *same* wrapper org's
    ///   `swift-docs.yml` and its `with:` overrides map onto the spec's
    ///   `docs-*` pass-through inputs;
    /// - **current single-job** — `Render.current`'s own output, read
    ///   back for idempotent resume;
    /// - **direct single-job** — `Render.direct`'s output, which the
    ///   Python never saw because it predates the F13/F14 terminal form.
    ///   Recorded here as a deliberate widening, not an accident: `Parse`
    ///   is defined as `Render`'s inverse, and a form `Render` can emit
    ///   but `Parse` cannot read would make that false.
    ///
    /// Comments and blank lines are allowed to differ freely; every real
    /// caller in the corpus carries them. A difference in job set,
    /// `uses:`, `with:` keys or values, or an inline `runs-on:`/`steps:`
    /// fails closed with `Error.unknownCustomization` naming exactly what
    /// did not fit. Refusing is the point: a caller carrying something
    /// this type does not model is a typed exception for review, never
    /// something to silently regenerate over.
    ///
    /// `Parse` deliberately takes no dependency on the `CI Workflow`
    /// reader. `Render` is a closed line-oriented projection — it emits a
    /// fixed grammar and refuses everything else — so its inverse reads
    /// that same closed grammar. A general YAML reader would let `Parse`
    /// accept documents `Render` can never produce, which is the opposite
    /// of the fail-closed contract; it would also invert the package
    /// graph, since `CI Validation` depends on this package.
    public enum Parse {
        /// The `docs:` job's legacy `with:` keys, and the terminal
        /// `docs-*` input each recovers onto. Ordered, so a spec built
        /// from a legacy caller is deterministic.
        static let legacyDocsInputs: [(legacy: String, terminal: String)] = [
            ("umbrella-module", "docs-umbrella-module"),
            ("umbrella-display-name", "docs-umbrella-display-name"),
            ("umbrella-bundle-id", "docs-umbrella-bundle-id"),
            ("umbrella-docc-path", "docs-umbrella-docc-path"),
            ("exclude-modules", "docs-exclude-modules"),
            ("swift-version", "docs-swift-version"),
        ]

        /// The renderer-owned `with:` keys a rendered caller carries that
        /// are *not* caller state: `lint-bundle` is a layer property the
        /// direct form transfers (K-12), and `integrated-docs` is the
        /// bridge input TX10 deleted, admitted only as `true`.
        static let rendererOwnedInputs: Set<String> = ["lint-bundle", "integrated-docs"]

        /// The universal reusable the direct form calls, in place of a
        /// layer wrapper.
        static let universalReusable = "swift-institute/.github/.github/workflows/swift-ci.yml@main"

        /// The caller spec that models `text`.
        ///
        /// - Parameter repository: the `owner/name` the caller belongs
        ///   to. Supplied rather than inferred — a workflow file does not
        ///   name its own repository, and inferring one from the `uses:`
        ///   org would be the very confusion `Caller.sameOrganization`
        ///   exists to avoid.
        public static func caller(
            _ text: String, repository: String
        ) throws(Repository.Policy.Caller.Error) -> Repository.Policy.Caller {
            let jobs = try self.jobs(text)
            guard let ci = jobs.first(where: { $0.name == "ci" }) else {
                throw .unknownCustomization(
                    "no `ci` job; found \(jobs.map(\.name).sorted())")
            }
            let form = try self.form(ci, alongside: jobs.map(\.name))
            let layer = try self.layer(ci, form: form)
            try admit(jobs.map(\.name), form: form, repository: repository)

            var inputs = try self.inputs(ci)
            if form == .legacy {
                guard let docs = jobs.first(where: { $0.name == "docs" }) else {
                    throw .unknownCustomization("legacy shape without a `docs` job")
                }
                inputs = try merging(inputs, recoveredFrom: docs, layer: layer)
            }

            let caller = try Repository.Policy.Caller(
                repository: repository, layer: layer,
                inputs: canonical(inputs))

            // The structural fixpoint. A single-job caller claims to be
            // this renderer's own output, so re-rendering it must
            // reproduce the job block it came from; anything else is a
            // customization this type does not model and must not erase.
            // The legacy shape is exempt by construction — the terminal
            // form is the point of parsing it, so byte equality with the
            // input is impossible by design and the invariant there is
            // spec-level only. (`parse_existing_caller`'s closing check,
            // generalized over the form.)
            if form != .legacy {
                let rendered = form == .direct
                    ? Repository.Policy.Caller.Render.direct(
                        caller, privateDependencyClosure: ci.declares("secrets:"))
                    : Repository.Policy.Caller.Render.current(caller)
                guard try self.jobs(rendered).map(\.significantLines)
                    == jobs.map(\.significantLines)
                else {
                    throw .unknownCustomization(
                        "single-job caller does not match the canonical \(form.rawValue) "
                            + "shape (a customization this renderer does not model)")
                }
            }
            return caller
        }

        /// The layer a rendered caller routes through, recovered from the
        /// workflow it actually calls.
        ///
        /// Never from the repository's org: the org is compared *against*
        /// a known-good layer signal, never used to produce one, which is
        /// the same discipline `Caller.sameOrganization` follows.
        public static func layer(
            of text: String
        ) throws(Repository.Policy.Caller.Error) -> Repository.Policy.Caller.Layer {
            let jobs = try self.jobs(text)
            guard let ci = jobs.first(where: { $0.name == "ci" }) else {
                throw .unknownCustomization(
                    "no `ci` job; found \(jobs.map(\.name).sorted())")
            }
            return try layer(ci, form: try form(ci, alongside: jobs.map(\.name)))
        }
    }
}

extension Repository.Policy.Caller.Parse {
    static func form(
        _ ci: Job, alongside names: [String]
    ) throws(Repository.Policy.Caller.Error) -> Form {
        if ci.declares("steps:") || ci.declares("runs-on:") {
            throw .unknownCustomization(
                "`ci` job carries inline steps/runs-on, not a thin caller")
        }
        guard let uses = ci.uses else {
            throw .unknownCustomization("`ci` job has no uses: — not a reusable-workflow call")
        }
        if uses == universalReusable { return .direct }
        return names.contains("docs") ? .legacy : .current
    }

    static func layer(
        _ ci: Job, form: Form
    ) throws(Repository.Policy.Caller.Error) -> Repository.Policy.Caller.Layer {
        guard let uses = ci.uses else {
            throw .unknownCustomization("`ci` job has no uses:")
        }
        if form == .direct {
            // The direct form calls one universal for every layer, so the
            // wrapper org carries no layer signal. The layer's lint
            // bundle does — it is exactly the property the wrapper hop
            // used to own and the direct leaf transfers (K-12).
            let bundles = try inputs(ci, includingRendererOwned: true)
            guard let bundle = bundles.first(where: { $0.key == "lint-bundle" })?.value,
                let layer = Repository.Policy.Caller.Layer.allCases
                    .first(where: { $0.lintBundle == bundle })
            else {
                throw .unknownCustomization(
                    "direct caller carries no recognised `lint-bundle:`, so its "
                        + "layer cannot be recovered")
            }
            return layer
        }
        let organization = String(uses.prefix { $0 != "/" })
        guard let layer = Repository.Policy.Caller.Layer.allCases
            .first(where: { $0.wrapperOrganization == organization })
        else {
            throw .unknownCustomization(
                "could not infer a known layer from uses: \(uses)")
        }
        guard uses == "\(organization)/.github/.github/workflows/swift-ci.yml@main" else {
            throw .unknownCustomization(
                "ci uses \(uses), expected "
                    + "\(organization)/.github/.github/workflows/swift-ci.yml@main")
        }
        return layer
    }

    /// Whether the job set is one this type models.
    static func admit(
        _ names: [String], form: Form, repository: String
    ) throws(Repository.Policy.Caller.Error) {
        var admitted: Set<String> = ["ci"]
        if form == .legacy { admitted.insert("docs") }
        // The ruled second job for the five rule-pack repositories is
        // renderer output, not a customization (principal ruling
        // 2026-08-06). It is admitted for exactly those repositories.
        if Repository.Policy.Caller.linterRulePackRepositories.contains(repository) {
            admitted.insert("notify-linter-republish")
        }
        guard Set(names) == admitted else {
            throw .unknownCustomization(
                "unexpected job set \(names.sorted()), expected \(admitted.sorted())")
        }
    }

    /// The `ci` job's caller-supplied `with:` inputs, in document order.
    static func inputs(
        _ job: Job, includingRendererOwned: Bool = false
    ) throws(Repository.Policy.Caller.Error) -> [(key: String, value: String)] {
        var recovered: [(key: String, value: String)] = []
        for (key, value) in try block(job, under: "with:") {
            if rendererOwnedInputs.contains(key) {
                if key == "integrated-docs", value != "true" {
                    throw .unknownCustomization("integrated-docs is present but not true")
                }
                if includingRendererOwned { recovered.append((key: key, value: value)) }
                continue
            }
            guard Repository.Policy.Caller.approvedTypedInputs.contains(key) else {
                throw .unknownCustomization("unapproved with: key \(key)")
            }
            recovered.append((key: key, value: value))
        }
        return recovered
    }

    /// The legacy `docs:` job's overrides, recovered onto the terminal
    /// `docs-*` inputs and merged with the `ci` job's.
    static func merging(
        _ inputs: [(key: String, value: String)], recoveredFrom docs: Job,
        layer: Repository.Policy.Caller.Layer
    ) throws(Repository.Policy.Caller.Error) -> [(key: String, value: String)] {
        let expected = "\(layer.wrapperOrganization)/.github/.github/workflows/swift-docs.yml@main"
        guard let uses = docs.uses else {
            throw .unknownCustomization("`docs` job has no uses: — not a reusable-workflow call")
        }
        guard uses == expected else {
            throw .unknownCustomization(
                "docs uses \(uses), expected \(expected) "
                    + "(cross-wrapper docs routes are typed exceptions)")
        }
        var merged = inputs
        for (key, value) in try block(docs, under: "with:") {
            guard let terminal = legacyDocsInputs.first(where: { $0.legacy == key })?.terminal
            else {
                throw .unknownCustomization("unapproved docs with: key \(key)")
            }
            if let existing = merged.first(where: { $0.key == terminal }) {
                guard existing.value == value else {
                    throw .unknownCustomization(
                        "docs job \(key) conflicts with ci job \(terminal)")
                }
                continue
            }
            merged.append((key: terminal, value: value))
        }
        return merged
    }

    /// The key/value children of a block-form mapping in a job body.
    ///
    /// Indentation-tracked: children are the contiguous run of
    /// more-indented `key: value` lines after the opener; the first
    /// significant line at or below the opener's indent closes the block.
    /// A child that is itself a block opener is a nesting this renderer
    /// never emits, and refusing it is what keeps `Parse` closed.
    static func block(
        _ job: Job, under opener: String
    ) throws(Repository.Policy.Caller.Error) -> [(key: String, value: String)] {
        var children: [(key: String, value: String)] = []
        var openerIndent: Int?
        for line in job.significantLines {
            if let indent = openerIndent {
                if line.indent > indent {
                    guard let separator = line.firstIndex(of: ":") else {
                        throw .unknownCustomization("unreadable `\(opener)` entry: \(line.trimmed)")
                    }
                    let key = String(line[..<separator]).trimmed
                    let value = String(line[line.index(after: separator)...]).trimmed
                    guard !value.isEmpty else {
                        throw .unknownCustomization(
                            "nested mapping under `\(opener)`: \(key)")
                    }
                    children.append((key: key, value: unquoted(value)))
                    continue
                }
                openerIndent = nil
            }
            if line.trimmed == opener { openerIndent = line.indent }
        }
        return children
    }

    /// Every job under `jobs:`, in document order.
    ///
    /// The same indentation-tracking walk the retired corpus used: `jobs:`
    /// at column 0, job names at indent 2, everything deeper belonging to
    /// the current job, and the first column-0 key after the block ending
    /// it.
    static func jobs(_ text: String) throws(Repository.Policy.Caller.Error) -> [Job] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { significant($0)?.trimmed == "jobs:" && $0.indent == 0 })
        else {
            throw .unknownCustomization("no top-level `jobs:` block")
        }
        var jobs: [Job] = []
        var name: String?
        var body: [String] = []
        for line in lines[lines.index(after: start)...] {
            guard let content = significant(line) else {
                if name != nil { body.append(line) }
                continue
            }
            if content.indent == 0 { break }
            if content.indent == 2, content.trimmed.hasSuffix(":"),
                content.trimmed.dropLast().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            {
                if let name { jobs.append(Job(name: name, lines: body)) }
                name = String(content.trimmed.dropLast())
                body = []
                continue
            }
            guard name != nil else {
                throw .unknownCustomization("content under `jobs:` before the first job")
            }
            body.append(line)
        }
        if let name { jobs.append(Job(name: name, lines: body)) }
        return jobs
    }

    /// A line with its trailing comment removed, or `nil` when the line
    /// carries no content.
    ///
    /// A `#` counts as a comment only when it opens the line or follows
    /// whitespace, which is YAML's own rule and is what keeps
    /// `group: ci-${{ github.ref }}` intact.
    static func significant(_ line: String) -> String? {
        var kept = ""
        var previous: Character?
        for character in line {
            if character == "#", previous == nil || previous == " " || previous == "\t" {
                break
            }
            kept.append(character)
            previous = character
        }
        while kept.last == " " || kept.last == "\t" { kept.removeLast() }
        return kept.trimmed.isEmpty ? nil : kept
    }

    /// A scalar with one layer of matching quotes removed.
    static func unquoted(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Inputs in the renderer's emission order, so a parsed spec compares
    /// equal to the spec that rendered it regardless of the order the
    /// document happened to carry.
    static func canonical(
        _ inputs: [(key: String, value: String)]
    ) -> [(key: String, value: String)] {
        Repository.Policy.Caller.approvedTypedInputs.compactMap { key in
            inputs.first { $0.key == key }
        }
    }
}

extension String {
    fileprivate var trimmed: String {
        var value = Substring(self)
        while let first = value.first, first == " " || first == "\t" { value = value.dropFirst() }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        return String(value)
    }

    fileprivate var indent: Int {
        prefix { $0 == " " || $0 == "\t" }.count
    }
}
