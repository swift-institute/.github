// VIOLATION of [PLAT-ARCH-006]: swift-darwin's Exports.swift does not
// re-export any Darwin_* L2 spec module. The re-export chain is broken;
// consumers cannot reach the L2 spec types via `import Darwin_Kernel`.
import Random_Primitives
