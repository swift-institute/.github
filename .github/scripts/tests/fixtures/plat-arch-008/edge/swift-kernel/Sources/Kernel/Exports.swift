// swift-kernel IS the L3-unifier — it is permitted to import L3-policy
// (and below) modules. [PLAT-ARCH-008] is a consumer-side rule and does
// not apply within the platform stack.
@_exported public import Darwin_Kernel
@_exported public import Linux_Kernel
@_exported public import Windows_Kernel
@_exported public import POSIX_Kernel
