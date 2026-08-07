import CI_Contract
import Testing

@testable import CI_Canon

@Suite
struct CICanonGitignoreTests {
    static let terminator = CI.Canon.Gitignore.terminator
    static let canon = "# CANONICAL\n/*\n!/Sources/\n\(terminator)\n"

    @Suite
    struct Unit {
        @Test func `the canonical half ends at the terminator`() {
            let file = CI.Canon.Gitignore(CICanonGitignoreTests.canon + "own/\n")
            #expect(file.canonical == CICanonGitignoreTests.canon)
            #expect(file.local == "own/\n")
        }

        @Test func `a pre canonical file has neither half`() {
            // Absence, not a decision: it is a [GH-IGNORE-001] finding to
            // the validator and a preserve-verbatim case to the renderer.
            let file = CI.Canon.Gitignore(".build/\n")
            #expect(file.canonical == nil)
            #expect(file.local == nil)
        }

        @Test func `rendering over a canonical file replaces only the canonical half`() throws {
            let existing = CI.Canon.Gitignore("# OLD\n\(CI.Canon.Gitignore.terminator)\nown/\n")
            let rendered = try CI.Canon.Gitignore.Render(
                canon: .init(CICanonGitignoreTests.canon))(over: existing)
            #expect(rendered == CICanonGitignoreTests.canon + "own/\n")
        }

        @Test func `rendering over no file emits canon whole`() throws {
            // Canon already carries an empty LOCAL OVERRIDES block, so it
            // is not truncated at the terminator.
            let canon = CICanonGitignoreTests.canon + "# LOCAL\n"
            let rendered = try CI.Canon.Gitignore.Render(canon: .init(canon))(over: nil)
            #expect(rendered == canon)
        }

        @Test func `rendering is idempotent`() throws {
            // The caller byte-compares before committing, so a second
            // render of a conformant file must produce no change.
            let render = try CI.Canon.Gitignore.Render(canon: .init(CICanonGitignoreTests.canon))
            let once = render(over: nil)
            let twice = render(over: .init(once))
            #expect(once == twice)
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a pre canonical file is preserved whole beneath canon`() throws {
            // Replacing it would delete rules a package deliberately
            // added, which is not recoverable from the diff alone.
            let rendered = try CI.Canon.Gitignore.Render(
                canon: .init(CICanonGitignoreTests.canon))(over: .init("\n\nlegacy/\n"))
            #expect(rendered.hasPrefix(CICanonGitignoreTests.canon))
            #expect(rendered.hasSuffix("legacy/\n"))
            #expect(rendered.contains("# ========== LOCAL OVERRIDES =========="))
            // The leading blank lines of the old file are dropped, but
            // not a byte of its content.
            #expect(!rendered.contains("\n\n\nlegacy/"))
        }

        @Test func `a file ending at the terminator has an empty local half`() {
            let file = CI.Canon.Gitignore("/*\n\(CI.Canon.Gitignore.terminator)")
            #expect(file.local == "")
            #expect(file.canonical?.hasSuffix("\n") == true)
        }

        @Test func `canon without a terminator is refused, not reported`() {
            // An unusable control-plane document is not a verdict about
            // any package.
            #expect(throws: CI.Canon.Gitignore.Render.Error.terminatorAbsent) {
                try CI.Canon.Gitignore.Render(canon: .init("/*\n"))
            }
        }
    }
}
