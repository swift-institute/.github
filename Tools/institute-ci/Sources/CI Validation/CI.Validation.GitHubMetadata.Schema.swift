import CI_Contract
import CI_Workflow

extension CI.Validation.GitHubMetadata {
    /// A deliberately bounded JSON-Schema (draft 2020-12) evaluator for
    /// `metadata-schema.json`.
    ///
    /// This is **not** a general JSON-Schema implementation and must not
    /// be presented as one. It covers exactly the keywords that schema
    /// uses — `type`, `enum`, `minLength`/`maxLength`, `pattern`,
    /// `minItems`/`maxItems`/`uniqueItems`, `items`,
    /// `additionalProperties`, `properties`, `required`, `not`, `oneOf` —
    /// and reproduces the *messages* of Python's `jsonschema`
    /// `Draft202012Validator`, because the retired script embedded those
    /// messages in its findings and the differential gate compares
    /// finding text. `format` is annotation-only there (no format
    /// checker was installed) and is annotation-only here.
    ///
    /// Instances and schemas are both `CI.Workflow.YAML.Node`, so the
    /// Python `repr` renderings the messages quote come from the one
    /// existing owner of that rendering.
    public struct Schema: Sendable {
        public typealias Node = CI.Workflow.YAML.Node

        /// One validation error: where, and `jsonschema`'s sentence.
        public struct Issue: Sendable, Equatable {
            /// One step of an error path — a property name or an array
            /// index, matching `jsonschema`'s mixed `str`/`int` deque.
            public enum Element: Sendable, Equatable, CustomStringConvertible {
                case key(String)
                case index(Int)

                public var description: String {
                    switch self {
                    case .key(let name): name
                    case .index(let position): String(position)
                    }
                }
            }

            public let path: [Element]
            public let message: String

            /// `"/".join(str(p) for p in err.path) or "/"`.
            public var location: String {
                path.isEmpty ? "/" : path.map(\.description).joined(separator: "/")
            }

            /// `sorted(errors, key=lambda e: list(e.path))` — elementwise,
            /// shorter prefix first; `nil` when the paths are equal so the
            /// caller can keep the emission order, as Python's stable sort
            /// does.
            public static func ordered(_ lhs: [Element], _ rhs: [Element]) -> Bool? {
                for (left, right) in zip(lhs, rhs) {
                    switch (left, right) {
                    case (.index(let a), .index(let b)):
                        if a != b { return a < b }
                    default:
                        let (a, b) = (left.description, right.description)
                        if a != b { return a < b }
                    }
                }
                return lhs.count == rhs.count ? nil : lhs.count < rhs.count
            }
        }

        public let root: Node

        /// The schema's path, cited when the machine — not the subject —
        /// is what cannot answer (an unreadable `pattern`, a malformed
        /// subschema).
        public let source: String

        public init(_ root: Node, source: String) {
            self.root = root
            self.source = source
        }

        /// Every validation error in the instance, in discovery order.
        public func issues(in instance: Node) throws(CI.Validation.EnvironmentDefect) -> [Issue] {
            try evaluate(instance, against: root, at: [])
        }

        // MARK: - Evaluation

        private func evaluate(
            _ instance: Node, against schema: Node, at path: [Issue.Element]
        ) throws(CI.Validation.EnvironmentDefect) -> [Issue] {
            // A boolean schema: `true` admits everything, `false` nothing.
            if case .boolean(let admits) = schema {
                return admits
                    ? []
                    : [Issue(path: path, message: "\(instance.pythonRepr) is disallowed")]
            }
            guard case .mapping(let keywords) = schema else {
                throw .missingSupportFile(path: source)
            }
            var issues: [Issue] = []

            if let expected = keywords["type"], !Self.matches(instance, type: expected) {
                let names: [Node] = expected.sequence ?? [expected]
                issues.append(
                    Issue(
                        path: path,
                        message: "\(instance.pythonRepr) is not of type "
                            + names.map(\.pythonRepr).joined(separator: ", ")))
            }

            if let admitted = keywords["enum"]?.sequence, !admitted.contains(instance) {
                issues.append(
                    Issue(
                        path: path,
                        message: "\(instance.pythonRepr) is not one of "
                            + Node.sequence(admitted).pythonRepr))
            }

            if case .text(let text) = instance {
                let length = text.unicodeScalars.count
                if let minimum = keywords["minLength"]?.integer, length < minimum {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) "
                                + (minimum == 1 ? "should be non-empty" : "is too short")))
                }
                if let maximum = keywords["maxLength"]?.integer, length > maximum {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) "
                                + (maximum == 0 ? "is expected to be empty" : "is too long")))
                }
                if case .text(let pattern)? = keywords["pattern"] {
                    // swift-linter:disable:next try optional
                    // REASON: `Regex.init(_:)` throws untyped; a schema
                    // whose pattern the engine refuses is the machine
                    // failing, which is the defect below.
                    guard let regex = try? Regex(pattern) else {
                        throw .missingSupportFile(path: source)
                    }
                    // swift-linter:disable:next try optional
                    // REASON: `Regex.firstMatch(in:)` throws untyped; its
                    // only failure here is an engine limit, and Python's
                    // `re.search` answered the same question with no
                    // failure channel at all.
                    if (try? regex.firstMatch(in: text)) == nil {
                        issues.append(
                            Issue(
                                path: path,
                                message: "\(instance.pythonRepr) does not match "
                                    + Node.repr(pattern)))
                    }
                }
            }

            if case .sequence(let elements) = instance {
                if let minimum = keywords["minItems"]?.integer, elements.count < minimum {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) "
                                + (minimum == 1 ? "should be non-empty" : "is too short")))
                }
                if let maximum = keywords["maxItems"]?.integer, elements.count > maximum {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) "
                                + (maximum == 0 ? "is expected to be empty" : "is too long")))
                }
                if keywords["uniqueItems"]?.boolean == true, Self.hasDuplicates(elements) {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) has non-unique elements"))
                }
                if let items = keywords["items"] {
                    for (index, element) in elements.enumerated() {
                        issues += try evaluate(
                            element, against: items, at: path + [.index(index)])
                    }
                }
            }

            if case .mapping(let object) = instance {
                if case .boolean(false)? = keywords["additionalProperties"] {
                    let declared = Set(keywords["properties"]?.mapping?.textKeys ?? [])
                    let extras = object.textKeys.filter { !declared.contains($0) }.sorted()
                    if !extras.isEmpty {
                        issues.append(
                            Issue(
                                path: path,
                                message: "Additional properties are not allowed ("
                                    + extras.map(Node.repr).joined(separator: ", ")
                                    + (extras.count == 1 ? " was" : " were") + " unexpected)"))
                    }
                }
                if let required = keywords["required"]?.sequence {
                    for case .text(let name) in required where object[name] == nil {
                        issues.append(
                            Issue(
                                path: path,
                                message: "\(Node.repr(name)) is a required property"))
                    }
                }
                if let properties = keywords["properties"]?.mapping {
                    for entry in properties.entries {
                        guard case .text(let name) = entry.key,
                            let value = object[name]
                        else { continue }
                        issues += try evaluate(
                            value, against: entry.value, at: path + [.key(name)])
                    }
                }
            }

            if let branches = keywords["oneOf"]?.sequence {
                var valid: [Node] = []
                for branch in branches
                where try evaluate(instance, against: branch, at: path).isEmpty {
                    valid.append(branch)
                }
                if valid.isEmpty {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) is not valid under any"
                                + " of the given schemas"))
                } else if valid.count > 1 {
                    issues.append(
                        Issue(
                            path: path,
                            message: "\(instance.pythonRepr) is valid under each of "
                                + valid.map(\.pythonRepr).joined(separator: ", ")))
                }
            }

            if let negated = keywords["not"],
                try evaluate(instance, against: negated, at: path).isEmpty
            {
                issues.append(
                    Issue(
                        path: path,
                        message: "\(instance.pythonRepr) should not be valid under "
                            + negated.pythonRepr))
            }

            return issues
        }

        /// `is_type`, with Python's carve-outs: a boolean is not an
        /// integer, an integer is also a number.
        static func matches(_ instance: Node, type expected: Node) -> Bool {
            if let names = expected.sequence {
                return names.contains { matches(instance, type: $0) }
            }
            guard case .text(let name) = expected else { return true }
            switch (name, instance) {
            case ("object", .mapping): return true
            case ("array", .sequence): return true
            case ("string", .text): return true
            case ("boolean", .boolean): return true
            case ("integer", .integer): return true
            case ("number", .integer), ("number", .number): return true
            case ("null", .null): return true
            default: return false
            }
        }

        /// Pairwise, as `jsonschema.uniq` degrades to for unhashable
        /// members; the arrays here are a handful of topic strings.
        static func hasDuplicates(_ elements: [Node]) -> Bool {
            for (index, element) in elements.enumerated()
            where elements[(index + 1)...].contains(element) {
                return true
            }
            return false
        }
    }
}
