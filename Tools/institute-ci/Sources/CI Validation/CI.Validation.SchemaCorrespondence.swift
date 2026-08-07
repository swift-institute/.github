import CI_Contract
import Foundation

extension CI.Validation {
    /// `[GH-REPO-063]` — `metadata-schema.json` ↔ consumer
    /// correspondence.
    ///
    /// A key or enum value the schema declares but no consumer reads is
    /// a silent no-op: the maintainer who authors it in a
    /// `metadata.yaml` gets no effect and no error. This rule asserts
    /// that every declared thing has a reader, and every reader has a
    /// declaration. Origin: the schema documented `defaultBranchRef`
    /// while the workflow consumed `.settings.defaultBranch`
    /// (2026-07-03 settings-governance audit).
    ///
    /// Two correspondences are checked. They are separate because the
    /// consumers are different KINDS of artifact and are read
    /// differently:
    ///
    /// - **settings** — the `settings.properties` key set, against
    ///   `.settings.<key>` reads in `sync-metadata.yml`. Textual: the
    ///   workflow reads these through `jq`, so there is no structure to
    ///   parse.
    /// - **readme** — the `readme.exempt` and `readme.family` enums,
    ///   against the `EXEMPTIONS` and `FAMILIES` tuples in
    ///   `validate-readme.py`. The consumer is Python, so the constants
    ///   are extracted from module-level assignments BY NAME, and only
    ///   a tuple/list of plain string literals counts as an answer.
    ///
    /// FAILING CLOSED, exactly as the retired script did. Every way of
    /// not-knowing about a *consumer* is a finding, not a pass: a
    /// schema block that is missing or not an object, an expected enum
    /// that is missing or not a list of strings, an expected constant
    /// that is absent, non-module-level, or not a tuple of string
    /// literals. An earlier draft of the retired guard returned
    /// "consistent" when it could not find a constant, which would have
    /// made a rename of `EXEMPTIONS` read as agreement.
    ///
    /// One deliberate contract difference from the retired
    /// `.github/scripts/validate-schema-workflow-keys.py`: an *input
    /// file* that cannot be read at all — schema, workflow, or consumer
    /// absent, or the schema not valid JSON — is the exit-2
    /// `EnvironmentDefect` class here, where the script crashed with a
    /// traceback. Both fail the caller loudly; neither reports a pass.
    public struct SchemaCorrespondence: Validator {
        public let rules: [Rule] = ["GH-REPO-063"]
        public let retiredScript: String? = ".github/scripts/validate-schema-workflow-keys.py"

        /// The `readme.<field>` enum ↔ consumer-constant pairs the
        /// readme half compares. Mirrors the retired script's
        /// `(("exempt", "EXEMPTIONS"), ("family", "FAMILIES"))`.
        public static let readmePairs: [(field: String, constant: String)] = [
            ("exempt", "EXEMPTIONS"),
            ("family", "FAMILIES"),
        ]

        /// Where the three inputs live, when not at their subject-root
        /// defaults. The fixture corpus under
        /// `tests/schema-correspondence/` keeps all three files flat in
        /// one scenario directory, so its caller names them explicitly —
        /// the shape the retired script's three positional arguments
        /// had.
        public let schemaFile: String?
        public let syncWorkflowFile: String?
        public let readmeValidatorFile: String?

        public init(
            schemaFile: String? = nil,
            syncWorkflowFile: String? = nil,
            readmeValidatorFile: String? = nil
        ) {
            self.schemaFile = schemaFile
            self.syncWorkflowFile = syncWorkflowFile
            self.readmeValidatorFile = readmeValidatorFile
        }

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let schemaPath = schemaFile ?? subject.path("metadata-schema.json")
            let workflowPath = syncWorkflowFile ?? subject.path(".github/workflows/sync-metadata.yml")
            let readmePath = readmeValidatorFile ?? subject.path(".github/scripts/validate-readme.py")

            let schemaText = try Self.text(at: schemaPath)
            let workflowText = try Self.text(at: workflowPath)
            let readmeText = try Self.text(at: readmePath)
            // swift-linter:disable:next try optional
            // REASON: `JSONSerialization.jsonObject` throws untyped; its
            // failure here is exactly the defect raised on the next line.
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(schemaText.utf8)),
                let schema = object as? [String: Any]
            else {
                throw .unreadableFile(path: schemaPath)
            }

            let schemaName = Self.name(of: schemaPath)
            var problems = Self.settingsProblems(
                schema: schema, schemaName: schemaName,
                workflowName: Self.name(of: workflowPath), workflowText: workflowText)
            problems += Self.readmeProblems(
                schema: schema, schemaName: schemaName,
                consumer: Self.name(of: readmePath), consumerSource: readmeText)
            return problems.map {
                Finding(repository: subject.repository, rule: rules[0], message: $0)
            }
        }
    }
}

extension CI.Validation.SchemaCorrespondence {
    /// `settings.properties` keys ↔ `.settings.<key>` reads in the
    /// workflow.
    static func settingsProblems(
        schema: [String: Any], schemaName: String,
        workflowName: String, workflowText: String
    ) -> [String] {
        let properties = schema["properties"] as? [String: Any]
        let settings = properties?["settings"] as? [String: Any]
        guard let declared = settings?["properties"] as? [String: Any] else {
            return [
                "\(schemaName) has no `settings.properties` object to compare "
                    + "-- the guard cannot conclude, so this is a finding, not a pass."
            ]
        }

        let schemaKeys = Set(declared.keys)
        let workflowKeys = settingsKeys(in: workflowText)
        var problems: [String] = []
        let onlySchema = schemaKeys.subtracting(workflowKeys)
        let onlyWorkflow = workflowKeys.subtracting(schemaKeys)
        if !onlySchema.isEmpty {
            problems.append(
                "declared in \(schemaName) `settings` but NOT read by "
                    + "\(workflowName): \(list(onlySchema.sorted()))")
        }
        if !onlyWorkflow.isEmpty {
            problems.append(
                "read by \(workflowName) but NOT declared in \(schemaName) "
                    + "`settings`: \(list(onlyWorkflow.sorted()))")
        }
        return problems
    }

    /// `readme.{exempt,family}` enums ↔ `EXEMPTIONS`/`FAMILIES` in the
    /// consumer.
    static func readmeProblems(
        schema: [String: Any], schemaName: String,
        consumer: String, consumerSource: String
    ) -> [String] {
        var problems: [String] = []
        let constants = moduleLevelStringSequences(
            in: consumerSource, names: Set(readmePairs.map(\.constant)))

        for (field, constant) in readmePairs {
            let declared = schemaEnum(schema, block: "readme", field: field)
            let read = constants[constant] ?? nil
            guard let declared else {
                problems.append(
                    "\(schemaName) `readme.\(field)` declares no string enum -- "
                        + "cannot compare against \(consumer) `\(constant)`.")
                continue
            }
            guard let read else {
                problems.append(
                    "\(consumer) has no module-level `\(constant)` assigned a tuple "
                        + "of string literals -- cannot compare against \(schemaName) "
                        + "`readme.\(field)`. If it was renamed or made computed, update "
                        + "this guard rather than removing the constant.")
                continue
            }
            let onlySchema = Set(declared).subtracting(read).sorted()
            let onlyConsumer = Set(read).subtracting(declared).sorted()
            if !onlySchema.isEmpty {
                problems.append(
                    "declared in \(schemaName) `readme.\(field)` enum but NOT "
                        + "handled by \(consumer) `\(constant)`: \(list(onlySchema)) -- "
                        + "authoring one of these in a metadata.yaml would be a silent "
                        + "no-op.")
            }
            if !onlyConsumer.isEmpty {
                problems.append(
                    "handled by \(consumer) `\(constant)` but NOT declared in "
                        + "\(schemaName) `readme.\(field)` enum: \(list(onlyConsumer)) -- "
                        + "schema validation would reject a value the validator "
                        + "accepts.")
            }
        }
        return problems
    }

    /// The enum declared at `properties.<block>.properties.<field>`,
    /// when it is a list of strings; `nil` for every other shape.
    static func schemaEnum(_ schema: [String: Any], block: String, field: String) -> [String]? {
        let properties = schema["properties"] as? [String: Any]
        let blockSchema = properties?[block] as? [String: Any]
        let blockProperties = blockSchema?["properties"] as? [String: Any]
        let fieldSchema = blockProperties?[field] as? [String: Any]
        guard let enumValues = fieldSchema?["enum"] as? [Any] else { return nil }
        let strings = enumValues.compactMap { $0 as? String }
        guard strings.count == enumValues.count else { return nil }
        return strings
    }

    /// Every `<key>` in a `.settings.<key>` read — the retired regex
    /// `\.settings\.([A-Za-z][A-Za-z0-9]*)`, applied to the raw text.
    static func settingsKeys(in text: String) -> Set<String> {
        var keys: Set<String> = []
        var remainder = text[...]
        while let marker = remainder.range(of: ".settings.") {
            remainder = remainder[marker.upperBound...]
            var key = ""
            for character in remainder {
                let isLetter = ("a"..."z").contains(character) || ("A"..."Z").contains(character)
                let isDigit = ("0"..."9").contains(character)
                if key.isEmpty ? isLetter : (isLetter || isDigit) {
                    key.append(character)
                } else {
                    break
                }
            }
            if !key.isEmpty { keys.insert(key) }
        }
        return keys
    }

    /// Module-level `NAME = ("a", "b")` assignments for `names`,
    /// extracted from Python source without executing it.
    ///
    /// The retired script used `ast` for this; a Swift port scans for
    /// column-zero assignments to exactly the requested names, which
    /// answers the same question for every module-level simple
    /// assignment. As there, an absent name, a non-module-level
    /// assignment (indented, so never at column zero), or a value that
    /// is not a tuple/list of plain string literals maps to `nil` — the
    /// caller reports that rather than skipping it — and the LAST
    /// module-level assignment wins.
    static func moduleLevelStringSequences(
        in source: String, names: Set<String>
    ) -> [String: [String]?] {
        var found: [String: [String]?] = [:]
        for name in names { found[name] = .some(nil) }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }
            guard let name = names.first(where: { matches(line, name: $0) }) else { continue }
            // Everything after the `=`, plus continuation lines until
            // the brackets balance (or the file ends).
            guard let equals = line.firstIndex(of: "=") else { continue }
            var expression = String(line[line.index(after: equals)...])
            var lookahead = index
            while !bracketsBalance(expression), lookahead + 1 < lines.count {
                lookahead += 1
                expression += "\n" + lines[lookahead]
            }
            found[name] = .some(parseStringSequence(expression))
        }
        return found
    }

    /// Does this line begin the module-level assignment `name = …`?
    /// Column zero, the exact identifier, then `=` (and not `==`).
    private static func matches(_ line: Substring, name: String) -> Bool {
        guard line.hasPrefix(name) else { return false }
        var rest = line.dropFirst(name.count)
        // The identifier must end here: `EXEMPTIONS2 = …` is a
        // different name.
        if let next = rest.first,
            next.isLetter || next.isNumber || next == "_"
        { return false }
        while rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
        return rest.first == "=" && !rest.hasPrefix("==")
    }

    /// Are all `(`/`[` closed, counting only outside string literals?
    private static func bracketsBalance(_ text: String) -> Bool {
        var depth = 0
        var quote: Character? = nil
        var escaped = false
        for character in text {
            if let active = quote {
                if escaped { escaped = false } else if character == "\\" {
                    escaped = true
                } else if character == active { quote = nil }
                continue
            }
            switch character {
            case "'", "\"": quote = character
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "#": return depth <= 0
            default: break
            }
        }
        return depth <= 0
    }

    /// The string elements of a tuple/list literal, else `nil`.
    ///
    /// `nil` means "could not establish", and every caller treats that
    /// as a finding. A partially-literal sequence (an f-string, a name,
    /// a splat, a nested structure) is rejected whole: half an answer
    /// here is indistinguishable from agreement.
    static func parseStringSequence(_ text: String) -> [String]? {
        var characters = Array(text)[...]

        func skipInert() {
            while let first = characters.first {
                if first == " " || first == "\t" || first == "\n" || first == "\r" {
                    characters = characters.dropFirst()
                } else if first == "#" {
                    while let next = characters.first, next != "\n" {
                        characters = characters.dropFirst()
                    }
                } else {
                    break
                }
            }
        }

        skipInert()
        guard let open = characters.first, open == "(" || open == "[" else { return nil }
        let close: Character = open == "(" ? ")" : "]"
        characters = characters.dropFirst()

        var values: [String] = []
        var expectsElement = true
        while true {
            skipInert()
            guard let first = characters.first else { return nil }
            if first == close {
                characters = characters.dropFirst()
                break
            }
            guard expectsElement, first == "'" || first == "\"" else { return nil }
            characters = characters.dropFirst()
            var value = ""
            var closed = false
            while let character = characters.first {
                characters = characters.dropFirst()
                if character == "\\" {
                    guard let escapedCharacter = characters.first else { return nil }
                    characters = characters.dropFirst()
                    switch escapedCharacter {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "r": value.append("\r")
                    case "\\", "'", "\"": value.append(escapedCharacter)
                    default:
                        // Python keeps an unrecognised escape verbatim.
                        value.append("\\")
                        value.append(escapedCharacter)
                    }
                } else if character == first {
                    closed = true
                    break
                } else if character == "\n" {
                    return nil
                } else {
                    value.append(character)
                }
            }
            guard closed else { return nil }
            values.append(value)
            expectsElement = false
            skipInert()
            if characters.first == "," {
                characters = characters.dropFirst()
                expectsElement = true
            }
        }
        skipInert()
        guard characters.isEmpty else { return nil }
        return values
    }

    /// `['a', 'b']` — the Python `repr` of a sorted list of strings,
    /// preserved because it appears verbatim inside finding messages
    /// the differential gate compared byte-for-byte.
    static func list(_ values: [String]) -> String {
        "[" + values.map { "'\($0)'" }.joined(separator: ", ") + "]"
    }

    /// The text of one input file. Absence is a defect, not a finding:
    /// this validator's subject IS the three files, so a missing one
    /// means the question cannot be asked.
    private static func text(at path: String) throws(CI.Validation.EnvironmentDefect) -> String {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw .missingSupportFile(path: path)
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw .unreadableFile(path: path)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
