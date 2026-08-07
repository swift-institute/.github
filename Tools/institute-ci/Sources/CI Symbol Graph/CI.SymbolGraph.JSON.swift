import CI_Contract
import Foundation

extension CI.SymbolGraph {
    /// A JSON value, preserved whole.
    ///
    /// A symbol graph is a document this step edits in two places and
    /// must otherwise hand to DocC unchanged, so it is read as a value
    /// rather than decoded into a model of the parts we happen to know
    /// about: anything the compiler emits that we have no type for still
    /// survives the round trip.
    public enum JSON: Sendable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSON])
        case object([String: JSON])

        public enum Error: Swift.Error, Equatable {
            case malformed(String)
        }

        public subscript(member: String) -> JSON? {
            guard case .object(let members) = self else { return nil }
            return members[member]
        }

        public var array: [JSON]? {
            guard case .array(let elements) = self else { return nil }
            return elements
        }

        public var string: String? {
            guard case .string(let text) = self else { return nil }
            return text
        }

        /// Replace a member of an object; a no-op on any other value.
        public mutating func set(_ member: String, to value: JSON) {
            guard case .object(var members) = self else { return }
            members[member] = value
            self = .object(members)
        }

        public init(text: String) throws(Error) {
            guard let data = text.data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(
                    with: data, options: [.fragmentsAllowed])
            else { throw .malformed("not JSON") }
            self = Self(any)
        }

        init(_ any: Any) {
            switch any {
            case is NSNull: self = .null
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else {
                    self = .number(number.doubleValue)
                }
            case let text as String: self = .string(text)
            case let elements as [Any]: self = .array(elements.map(Self.init))
            case let members as [String: Any]:
                self = .object(members.mapValues(Self.init))
            default: self = .null
            }
        }

        var foundation: Any {
            switch self {
            case .null: NSNull()
            case .bool(let value): value
            case .number(let value): value == value.rounded() && abs(value) < 1e15
                ? Int(value) as Any : value as Any
            case .string(let value): value
            case .array(let elements): elements.map(\.foundation)
            case .object(let members): members.mapValues(\.foundation)
            }
        }

        /// The value as text. Keys are sorted, because a Swift
        /// dictionary has no order to preserve and DocC has no opinion
        /// about one — and a sorted rendering is comparable.
        public func text() throws(Error) -> String {
            guard let data = try? JSONSerialization.data(
                withJSONObject: foundation,
                options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            else { throw .malformed("not serialisable") }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
