// [swift-institute/.github#219] EXEMPT: the pre-`any` spelling of the same
// stdlib `Encodable`/`Decodable` witnesses (live in the fleet at e.g.
// swift-standards/swift-locale-standard, swift-iso/swift-iso-15924). Both
// spellings are structurally the same protocol requirement; neither the
// untyped `throws` nor the (implicit) existential parameter type can be
// changed without breaking the conformance. `typed_throws_required` and
// `no_any_protocol_existential` must NOT fire on either witness below.

struct Label: Codable {
    let value: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }
}
