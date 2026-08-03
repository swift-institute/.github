// [swift-institute/.github#260] EXEMPT: a `throws` function whose ONLY
// untyped-throws source is rethrowing a generic closure parameter's error
// alongside the function's own failures. Swift typed throws has no
// error-union type (`throws(E | F)` is inexpressible), so this shape cannot
// express both the function's own typed failures and the closure's
// caller-supplied error under one `throws(E)` clause. Modeled on
// swift-foundations/swift-resource-pool `ResourcePool.withResource(timeout:_:)`
// (head 8ca28f8). `typed_throws_required` must NOT fire on either `throws`
// below: the closure parameter's own declared `throws`, and the enclosing
// function's own trailing `throws`.

enum PoolError: Error {
    case timeout
    case closed
}

struct Resource {}

struct Pool {
    func withResource<T: Sendable>(
        timeout: Int = 30,
        _ operation: (Resource) async throws -> T
    ) async throws -> T {
        guard timeout > 0 else { throw PoolError.timeout }
        return try await operation(Resource())
    }
}
