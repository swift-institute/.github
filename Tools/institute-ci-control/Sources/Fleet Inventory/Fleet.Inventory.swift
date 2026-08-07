// Nest.Name namespace shells (FT1-ratification.json). `Fleet.Inventory`
// owns the portable per-repository census (A-07 shape: every zero is
// positive-controlled, every row carries exact heads). `Fleet.Convergence`
// (sibling target) extends the same `Fleet` namespace.
public enum Fleet {}

extension Fleet {
    public enum Inventory {}
}
