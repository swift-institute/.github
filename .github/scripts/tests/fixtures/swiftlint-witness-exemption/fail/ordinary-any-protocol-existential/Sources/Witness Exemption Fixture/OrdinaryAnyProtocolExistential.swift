// [swift-institute/.github#219] VIOLATION: ordinary `any <Protocol>`
// parameter outside any witness position. #219 exempts protocol witnesses
// only, not general API surface — `no_any_protocol_existential` MUST
// still fire below.

func describe(_ value: any CustomStringConvertible) {
    print(value)
}
