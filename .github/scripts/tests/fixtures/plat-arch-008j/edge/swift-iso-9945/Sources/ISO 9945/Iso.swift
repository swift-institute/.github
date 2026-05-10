// swift-iso-9945 is the L2 POSIX spec package — platform C imports
// are PERMITTED here per [PLAT-ARCH-008j]'s L2-exclusive home rule.
// Spec encoding (including spec-mandated raw FFI) is L2's job.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ISO_9945 {
    public enum Kernel {}
}
