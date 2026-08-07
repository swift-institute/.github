// Nest.Name namespace shells for the Swift-native programme surfaces
// (FT1-ratification.json; naming-annex-nest-name.md). The pre-existing flat
// `RepositoryPolicy` namespace stays until its owners migrate; new
// programme-era types nest under `Repository.Policy`.
public enum Repository {}

extension Repository {
    public enum Policy {}
}
