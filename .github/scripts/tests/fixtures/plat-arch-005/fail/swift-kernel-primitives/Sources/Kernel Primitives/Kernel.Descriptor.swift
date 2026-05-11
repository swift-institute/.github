// VIOLATION of [PLAT-ARCH-005]: swift-kernel-primitives MUST NOT define a
// concrete Descriptor type. The L2-canonical Descriptor lives at the spec
// layer; L1 hosts no Descriptor.
extension Kernel {
    public struct Descriptor: ~Copyable {
        public let _rawValue: Int32
    }
}

public enum Kernel {}
