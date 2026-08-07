import Foundation
import Testing

/// Positive control for nested-test system-dependency derivation.
///
/// The installer must inspect every package graph universal CI can
/// compile. A sanctioned `Tests/Package.swift` graph may declare a
/// transitive C shim while the root graph declares no linked libraries,
/// so this runs the shipped composite-action step against hermetic
/// Swift and apt shims: the nested graph supplies `.linkedLibrary("uuid")`,
/// and the control proves `uuid-dev` reaches the installer.
@Suite
struct SystemDependencyDerivationTests {
    @Test func `a nested graph's linked library installs its dev package`() throws {
        let shell = try EmbeddedShell.actionStep(
            ".github/actions/install-system-deps/action.yml",
            step: "Derive + install system dev-packages from .linkedLibrary")

        let root = URL(
            fileURLWithPath: NSTemporaryDirectory() + "system-deps-" + UUID().uuidString)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        try "// root graph\n".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8)
        let dependency = root.appendingPathComponent(
            "Tests/.build/checkouts/swift-linux-standard")
        try manager.createDirectory(at: dependency, withIntermediateDirectories: true)
        try "// nested graph\n".write(
            to: root.appendingPathComponent("Tests/Package.swift"),
            atomically: true, encoding: .utf8)
        try #".linkedLibrary("uuid", .when(platforms: [.linux]))"# .appending("\n")
            .write(
                to: dependency.appendingPathComponent("Package.swift"),
                atomically: true, encoding: .utf8)

        let shims = root.appendingPathComponent("bin")
        try manager.createDirectory(at: shims, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("apt.log")
        try "#!/usr/bin/env bash\ntest \"$1 $2\" = 'package resolve'\n".write(
            to: shims.appendingPathComponent("swift"), atomically: true, encoding: .utf8)
        try "#!/usr/bin/env bash\nprintf \"%s\\n\" \"$*\" >> \"\(log.path)\"\n".write(
            to: shims.appendingPathComponent("apt-get"), atomically: true, encoding: .utf8)
        for shim in try manager.contentsOfDirectory(atPath: shims.path) {
            try manager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: shims.appendingPathComponent(shim).path)
        }

        let result = try shell.run(path: shims.path, in: root)
        #expect(result.status == 0, "\(result.log)")
        #expect(result.log.contains("Installing system dev-packages: uuid-dev"))
        #expect(
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
                .contains("install -qq -y uuid-dev"))
    }
}
