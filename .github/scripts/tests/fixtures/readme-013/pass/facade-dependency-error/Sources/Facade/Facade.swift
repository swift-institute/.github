// A facade / re-export package: it throws a *dependency-owned* error type and
// declares no error enum of its own. README-013 must not fire — documenting an
// OWN error tree is impossible here.
public enum Facade {
    public static func run(_ descriptor: borrowing ISO_9945.Kernel.Descriptor) throws(ISO_9945.Kernel.Sysctl.Error) {}

    public static func flush(_ descriptor: borrowing ISO_9945.Kernel.Descriptor) throws(Self.Error) {}
}
