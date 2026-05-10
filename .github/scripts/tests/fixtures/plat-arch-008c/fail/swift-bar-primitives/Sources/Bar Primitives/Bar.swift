// L1 primitive with platform-conditional code — VIOLATION of [PLAT-ARCH-008c].
// Platform-specific behavior MUST move to platform packages (L2/L3 spec/policy);
// L1 stays unconditionally platform-agnostic.

public enum Bar {
    public static func describe() -> Swift.String {
        #if os(macOS)
        return "macOS"
        #elseif os(Linux)
        return "Linux"
        #else
        return "other"
        #endif
    }
}
