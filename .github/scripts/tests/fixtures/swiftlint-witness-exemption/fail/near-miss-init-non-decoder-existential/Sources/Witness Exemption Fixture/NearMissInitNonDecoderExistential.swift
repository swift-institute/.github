// [swift-institute/.github#219] NEAR-MISS — MUST STILL FIRE: `init(from:)`
// keeps the stdlib witness's internal parameter name `decoder` but types
// it against a different existential, not the stdlib `Decoder`. The
// lookbehind/lookaround requires the literal `Decoder)` type token, so a
// different protocol name does not match and both `typed_throws_required`
// and `no_any_protocol_existential` MUST still fire below.

protocol JSONSource {
    func read() -> String
}

struct Envelope {
    init(from decoder: any JSONSource) throws {
        _ = decoder
    }
}
