public enum ISO_9945: Sendable {}

extension ISO_9945 {
    public enum Kernel {}
}

extension ISO_9945.Kernel {
    public struct Descriptor: ~Copyable {
        public let _rawValue: Int32
    }
}
