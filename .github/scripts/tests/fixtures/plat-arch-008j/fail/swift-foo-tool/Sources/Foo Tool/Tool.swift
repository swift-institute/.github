// Non-L2 package importing platform C — VIOLATION of [PLAT-ARCH-008j].
// Platform C imports are RESTRICTED to L2 spec packages (swift-iso-9945,
// swift-linux-standard, swift-darwin-standard, swift-windows-32). Other
// packages MUST compose via L2's typed API exclusively.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum Tool {
    public static let name: Swift.String = "tool"
}
