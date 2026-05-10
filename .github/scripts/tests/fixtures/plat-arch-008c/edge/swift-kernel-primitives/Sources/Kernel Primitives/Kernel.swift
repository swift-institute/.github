// swift-kernel-primitives is exempt from [PLAT-ARCH-008c] per the
// MOD-EXCEPT-001 carve-out — platform-vocabulary primitives MAY contain
// platform conditionals because they ARE the cross-platform vocabulary
// layer that other L1 primitives compose against.

public enum Kernel {
    public enum File {
        public static var pathSeparator: Swift.String {
            #if os(Windows)
            return "\\"
            #else
            return "/"
            #endif
        }
    }
}
