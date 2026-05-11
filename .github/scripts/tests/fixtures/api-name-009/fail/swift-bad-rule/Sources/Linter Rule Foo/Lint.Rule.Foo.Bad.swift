// A diagnostic-emitting rule whose message is bare prose — no rule_id
// bracket, no citation, no `:`. VIOLATION of [API-NAME-009].

extension Lint.Rule.Foo {
    public struct Bad {
        static let message: String =
            "Avoid bare throws and use typed throws instead."
    }
}
