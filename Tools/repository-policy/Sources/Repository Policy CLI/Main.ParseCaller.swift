import Foundation
import Repository_Policy

extension Main {
    /// `repository-policy parse-caller --caller <ci.yml> --repository
    /// <owner/name>`
    ///
    /// The inverse of `render-caller`, and the Swift owner of the retired
    /// `generate-caller.py parse` mode (F16 C3).
    ///
    /// Prints the recovered spec as JSON in the shape the retired mode
    /// emitted — `layer`, `same_org`, and one snake-cased field per
    /// approved typed input, `null` where the caller supplies none — so a
    /// consumer reading the old payload reads this one. A caller carrying
    /// something the renderer does not model exits non-zero naming it,
    /// rather than reporting a spec that would silently erase it.
    static func parseCaller(_ arguments: [String]) throws {
        var caller: String?
        var repository: String?
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--caller": caller = iterator.next()
            case "--repository": repository = iterator.next()
            default:
                throw RepositoryPolicy.ConfigurationError(
                    "unknown parse-caller argument \(argument)")
            }
        }
        guard let caller, let repository else {
            throw RepositoryPolicy.ConfigurationError(
                "parse-caller requires --caller <ci.yml> and --repository <owner/name>")
        }
        let text = try String(contentsOf: URL(filePath: caller), encoding: .utf8)
        let spec = try Repository.Policy.Caller.Parse.caller(text, repository: repository)

        var payload: [String: String?] = [
            "layer": spec.layer.rawValue,
            "same_org": spec.sameOrganization ? "true" : "false",
        ]
        for key in Repository.Policy.Caller.approvedTypedInputs {
            payload[key.replacingOccurrences(of: "-", with: "_")] =
                spec.inputs.first { $0.key == key }?.value
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(payload)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
