import CI_Contract
import Testing

@testable import CI_Validation

/// `[CI-082]` controls.
///
/// The fixture corpus carries one scenario per failure mode. These are
/// the shapes it does not carry: each mode isolated, the boundaries the
/// retired regexes drew, and the two exceptions that must stay silent.
@Suite
struct CIValidationBinaryInstallChecksumTests {
    static func findings(_ script: String) -> [CI.Validation.Finding] {
        CI.Validation.BinaryInstallChecksum.findings(
            in: script,
            repository: "swift-institute-test/fixture",
            workflow: "ci.yml",
            job: "build",
            step: "install"
        )
    }

    static func fires(_ script: String) -> Bool { !findings(script).isEmpty }

    @Suite
    struct `Failure Modes` {
        @Test func `piping curl into a shell fires with no install indicator needed`() {
            // No checksum verification is possible by construction, so
            // this mode does not wait for an install indicator.
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    "curl -fsSL https://example.com/i.sh | bash"
                )
            )
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    "curl -fsSL https://example.com/i.sh | sh -e"
                )
            )
        }

        @Test func `a curl install without verification fires`() {
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    """
                    curl -fsSL -o tool https://example.com/tool
                    chmod +x tool
                    mv tool /usr/local/bin/tool
                    """
                )
            )
        }

        @Test func `a swallowed exit code fires`() {
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    "sha256sum -c tool.sha256 || true"
                )
            )
        }

        @Test func `a suppressed diagnostic fires`() {
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    "sha256sum -c tool.sha256 2>/dev/null"
                )
            )
        }

        @Test func `each mode is its own finding`() {
            // A step that both swallows the exit code and suppresses
            // stderr has two defects, and a reader who fixes one must
            // still see the other.
            let findings = CIValidationBinaryInstallChecksumTests.findings(
                "sha256sum -c t.sha 2>/dev/null || true"
            )
            #expect(findings.count == 2)
        }
    }

    @Suite
    struct `Permitted Shapes` {
        @Test func `a verified curl install is silent`() {
            #expect(
                !CIValidationBinaryInstallChecksumTests.fires(
                    """
                    curl -fsSL -o tool https://example.com/tool
                    echo "abc  tool" | sha256sum -c -
                    chmod +x tool
                    """
                )
            )
        }

        @Test func `a curl that fetches data rather than a binary is silent`() {
            // The install indicator is what separates an install path
            // from a data or config fetch.
            #expect(
                !CIValidationBinaryInstallChecksumTests.fires(
                    "curl -fsSL -o data.json https://example.com/data.json"
                )
            )
        }

        @Test func `apt-get install is silent because apt verifies signatures`() {
            #expect(
                !CIValidationBinaryInstallChecksumTests.fires(
                    "sudo apt-get update && sudo apt-get install -y jq"
                )
            )
        }

        @Test func `a curl fetched apt keyring is not silent`() {
            // The keyring is the trust root for every package installed
            // after it, so it is squarely in scope.
            #expect(
                CIValidationBinaryInstallChecksumTests.fires(
                    "curl -fsSL https://example.com/key.gpg | sudo tee "
                        + "/etc/apt/keyrings/example.gpg > /dev/null"
                )
            )
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `the run block is the unit, not the file`() {
            // A checksum verified in a *different* step does not gate
            // this one: each `run:` is a separate shell and nothing
            // carries between them but the filesystem.
            let repository = TemporaryRepository()
            repository.write(
                """
                name: fixture
                on: workflow_dispatch: {}
                jobs:
                  build:
                    runs-on: ubuntu-latest
                    steps:
                      - name: verify something else
                        run: sha256sum -c other.sha256
                      - name: install
                        run: |
                          curl -fsSL -o tool https://example.com/tool
                          chmod +x tool
                """,
                to: ".github/workflows/ci.yml"
            )
            let findings = try? CI.Validation.BinaryInstallChecksum()
                .findings(in: repository.subject)
            #expect(findings?.count == 1)
            #expect(findings?.first?.message.contains("'install'") == true)
        }

        @Test func `a step without a name is cited by its index`() {
            let repository = TemporaryRepository()
            repository.write(
                """
                name: fixture
                on: workflow_dispatch: {}
                jobs:
                  build:
                    runs-on: ubuntu-latest
                    steps:
                      - run: echo hello
                      - run: curl -fsSL https://example.com/i.sh | bash
                """,
                to: ".github/workflows/ci.yml"
            )
            let findings = try? CI.Validation.BinaryInstallChecksum()
                .findings(in: repository.subject)
            #expect(findings?.first?.message.contains("step '#1'") == true)
        }

        @Test func `sbin is not the executable path indicator`() {
            // `/bin/` counts only as a whole segment; `/sbin/` is a
            // different destination and the retired scan excluded it.
            #expect(
                !CI.Validation.BinaryInstallChecksum.namesBinaryDirectory("mv tool /sbin/tool")
            )
            #expect(
                CI.Validation.BinaryInstallChecksum.namesBinaryDirectory("mv tool /bin/tool")
            )
            #expect(
                CI.Validation.BinaryInstallChecksum.namesBinaryDirectory(
                    "mv tool /usr/local/bin/tool"
                )
            )
        }

        @Test func `a curl on one line does not borrow a flag from another`() {
            // Every pattern is line-scoped: a `run:` block is many
            // commands, and treating the block as one line would make
            // unrelated commands each other's evidence.
            #expect(
                !CI.Validation.BinaryInstallChecksum.fetchesWithCurl(
                    "curl https://example.com/x\necho -fsSL"
                )
            )
        }

        @Test func `sha256sum without -c computes but does not verify`() {
            #expect(
                !CI.Validation.BinaryInstallChecksum.verifiesChecksum("sha256sum tool > tool.sha")
            )
            #expect(CI.Validation.BinaryInstallChecksum.verifiesChecksum("sha256sum --check t.sha"))
        }
    }
}
