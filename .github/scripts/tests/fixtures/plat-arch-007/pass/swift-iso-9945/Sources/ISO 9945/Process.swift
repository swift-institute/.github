// swift-iso-9945 hosts POSIX-shared syscall wrappers — fork() lives here,
// not duplicated in swift-darwin-standard or swift-linux-standard.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension ISO_9945.Kernel {
    public enum Process {
        public static func spawn() -> Int32 {
            return fork()
        }
    }
}
