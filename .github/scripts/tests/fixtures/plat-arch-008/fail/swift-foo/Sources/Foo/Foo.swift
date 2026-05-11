// swift-foo is NOT part of the platform stack. Importing a platform-
// specific L2-spec module is a VIOLATION of [PLAT-ARCH-008] — consumers
// MUST `import Kernel`, not `import Darwin_Kernel_Standard`.
import Darwin_Kernel_Standard

public enum Foo {}
