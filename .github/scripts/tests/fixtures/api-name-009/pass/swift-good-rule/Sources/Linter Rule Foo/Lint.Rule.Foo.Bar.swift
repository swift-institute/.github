// A diagnostic-emitting rule whose message follows the canonical
// educational-diagnostic format per [API-NAME-009].

extension Lint.Rule.Foo {
    public struct Bar {
        static let message: String =
            "[foo_bar] [API-ERR-001]: typed throws are required at this "
            + "boundary; bare `throws` erases the error type."
    }
}
