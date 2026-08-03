// [swift-institute/.github#219] NEAR-MISS — MUST STILL FIRE: a non-witness
// function that happens to be named `encode`, but with a different
// internal parameter name and a different existential type than the
// stdlib `Encodable.encode(to:)` requirement. Neither exemption's
// lookaround/lookbehind matches "to stream:" / "any Writable" — this is
// the #219 discriminator's near-miss contract, and both
// `typed_throws_required` and `no_any_protocol_existential` MUST fire.

protocol Writable {
    func write(_ text: String)
}

func encode(to stream: any Writable) throws {
    stream.write("x")
}
