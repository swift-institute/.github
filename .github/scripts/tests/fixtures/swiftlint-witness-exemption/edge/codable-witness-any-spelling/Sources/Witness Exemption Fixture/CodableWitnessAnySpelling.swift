// [swift-institute/.github#219] EXEMPT: stdlib `Encodable`/`Decodable`
// witnesses using the `any Encoder` / `any Decoder` spelling (live in the
// fleet at e.g. swift-standards/swift-domain-standard,
// swift-standards/swift-emailaddress-standard). The stdlib protocol
// requirement fixes both the untyped `throws` and the existential
// parameter type — neither is expressible any other way without breaking
// the conformance. `typed_throws_required` and `no_any_protocol_existential`
// must NOT fire on either witness below.

struct Envelope: Codable {
    let payload: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(payload)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.payload = try container.decode(String.self)
    }
}
