import Binary_Base_Primitives
import Byte_Primitives

extension RepositoryPolicy {
    /// Lowercase RFC 4648 §8 base-16 alphabet for SHA coordinates.
    static let lowercaseHexAlphabet: [Byte] = Array("0123456789abcdef".utf8).map(Byte.init)

    /// True when `value` is exactly `digits` lowercase base-16 characters.
    ///
    /// The single hex-validity wrapper for this package: length is checked
    /// here, character validity by `Binary.Base.16` decode against the
    /// lowercase alphabet (Goal swift-institute/.github#358, re-use ledger
    /// finding 3).
    static func isLowercaseHex(_ value: String, digits: Int) -> Bool {
        value.count == digits
            && Binary.Base.`16`.decode(value, alphabet: lowercaseHexAlphabet) != nil
    }
}
