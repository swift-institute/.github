// [swift-institute/.github#219] VIOLATION: ordinary untyped `throws` on a
// non-witness function. #219 exempts protocol witnesses only, not general
// API surface — `typed_throws_required` MUST still fire below.

func parse(_ input: String) throws {
    print(input)
}
