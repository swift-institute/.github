// VIOLATION of [PLAT-ARCH-027]: the variant target's Exports.swift is
// missing `@_exported public import Darwin_Primitives_Core`, so the
// Darwin namespace does not flow through this variant.
import Kernel_Primitives
