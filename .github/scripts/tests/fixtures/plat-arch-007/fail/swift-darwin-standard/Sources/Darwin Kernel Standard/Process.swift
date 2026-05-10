// swift-darwin-standard wrapping a POSIX-shared syscall — VIOLATION of
// [PLAT-ARCH-007]. fork() is POSIX-shared (IEEE 1003.1) and MUST live in
// swift-iso-9945, NOT be duplicated in swift-darwin-standard.

import Darwin

extension Darwin.Kernel {
    public enum Process {
        public static func spawn() -> Int32 {
            return fork()
        }
    }
}
