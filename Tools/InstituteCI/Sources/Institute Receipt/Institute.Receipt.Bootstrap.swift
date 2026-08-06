extension Institute.Receipt {
    /// Bootstrap identity and cache-entry provenance for the exact-main
    /// Workspace source build (F10). The cache key is the witness digest
    /// of the complete frozen package-inputs tuple; a cache entry is
    /// acceleration only and is validated against its manifest before
    /// any restored executable is trusted (DEL-06/CO-10).
    public enum Bootstrap {}
}
