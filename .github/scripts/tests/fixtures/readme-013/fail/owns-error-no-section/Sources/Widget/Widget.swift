// An owner package: it declares its OWN error enum and throws it. README-013
// MUST fire when the README lacks a `## Error Handling` section, because the
// remedy (document the OWN error tree) is possible here.
public struct Widget {
    public enum Error: Swift.Error {
        case notFound
        case invalid
        case timedOut
    }

    public func load() throws(Self.Error) {}
}
