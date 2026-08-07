import CI_Contract

extension CI.Workflow.YAML {
    /// One resolved YAML node.
    ///
    /// Scalars arrive already resolved, so a caller never re-implements
    /// the 1.1 resolver at a use site. `null` is a distinct case rather
    /// than an absent value because an explicitly empty workflow key
    /// (`permissions:`) and a missing one mean different things to
    /// several rules.
    public indirect enum Node: Sendable, Equatable {
        case null
        case boolean(Bool)
        case integer(Int)
        case number(Double)
        case text(String)
        case sequence([Node])
        case mapping(Mapping)
    }
}

extension CI.Workflow.YAML.Node {
    /// The node's text when it is a string scalar, otherwise `nil`.
    ///
    /// Deliberately narrow: it does **not** stringify a boolean or an
    /// integer. A rule that means "the key holds the word `true`" and a
    /// rule that means "the key holds the boolean true" are different
    /// predicates, and conflating them is how the Python corpus grew its
    /// `value is True or value == "true"` pairs.
    public var text: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }

    /// The node's boolean when it is a boolean scalar, otherwise `nil`.
    public var boolean: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    /// The node's integer when it is an integer scalar, otherwise `nil`.
    public var integer: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    /// The node's mapping when it is a mapping, otherwise `nil`.
    public var mapping: CI.Workflow.YAML.Mapping? {
        guard case .mapping(let value) = self else { return nil }
        return value
    }

    /// The node's elements when it is a sequence, otherwise `nil`.
    public var sequence: [Self]? {
        guard case .sequence(let value) = self else { return nil }
        return value
    }

    /// Lookup through a mapping node by string key; `nil` for any other
    /// node shape or a missing key.
    public subscript(key: String) -> Self? {
        mapping?[key]
    }
}
