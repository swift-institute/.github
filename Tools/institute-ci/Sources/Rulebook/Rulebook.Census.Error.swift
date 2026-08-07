import Foundation

extension Rulebook.Census {
    /// The census could not be taken.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// No root was named, or none of the named roots exists. A count
        /// from no roots is not zero rules; it is no measurement.
        case noRoots
    }
}
