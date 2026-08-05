import Foundation
import Repository_Policy

extension Main {
    /// `repository-policy render-caller --repository <owner/name> --layer
    /// <primitives|standards|institute> [--input <key>=<value>]...
    /// [--form <current|direct>] [--private-dependency-closure]`
    ///
    /// Prints the deterministic host projection to stdout (F3; #366).
    static func renderCaller(_ arguments: [String]) throws {
        var repository: String?
        var layer: Repository.Policy.Caller.Layer?
        var inputs: [(key: String, value: String)] = []
        var form = "current"
        var privateClosure = false
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--repository": repository = iterator.next()
            case "--layer":
                guard let raw = iterator.next(),
                      let value = Repository.Policy.Caller.Layer(rawValue: raw) else {
                    throw RepositoryPolicy.ConfigurationError("--layer must be primitives|standards|institute")
                }
                layer = value
            case "--input":
                guard let raw = iterator.next(),
                      let separator = raw.firstIndex(of: "=") else {
                    throw RepositoryPolicy.ConfigurationError("--input needs <key>=<value>")
                }
                let key = String(raw[..<separator])
                guard Repository.Policy.Caller.approvedTypedInputs.contains(key) else {
                    throw RepositoryPolicy.ConfigurationError("unapproved input key \(key)")
                }
                inputs.append((key: key, value: String(raw[raw.index(after: separator)...])))
            case "--form": form = iterator.next() ?? "current"
            case "--private-dependency-closure": privateClosure = true
            default:
                throw RepositoryPolicy.ConfigurationError("unknown render-caller argument \(argument)")
            }
        }
        guard let repository, let layer else {
            throw RepositoryPolicy.ConfigurationError("render-caller requires --repository and --layer")
        }
        let caller = try Repository.Policy.Caller(
            repository: repository, layer: layer, inputs: inputs)
        switch form {
        case "current":
            print(Repository.Policy.Caller.Render.current(caller), terminator: "")
        case "direct":
            print(Repository.Policy.Caller.Render.direct(
                caller, privateDependencyClosure: privateClosure), terminator: "")
        default:
            throw RepositoryPolicy.ConfigurationError("--form must be current|direct")
        }
    }
}
