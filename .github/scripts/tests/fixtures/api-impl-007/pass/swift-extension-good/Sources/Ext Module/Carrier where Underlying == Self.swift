// `Carrier where Underlying == Self.swift` — pure-extension file whose
// basename uses the where-clause shape per [API-IMPL-007]. Detection is
// satisfied by the ` where ` segment in the basename.

extension Carrier where Underlying == Self {
    public func roundTrip() -> Self { self }
}

// Stand-in declarations so the file parses standalone.
public protocol Carrier {
    associatedtype Underlying
}
