import Byte_Primitives
import Foundation
import Institute_Receipt
import Testing

/// The startup-failure probe, ported from
/// `.github/scripts/tests/test-detect-startup-failures.py`.
///
/// The point of the original suite is not that the detector passes on
/// clean data — anything that returns nothing does that. It is that the
/// detector can be *made* to fail: a probe that cannot be shown flagging
/// dirty data is a false-green probe, and this class of check is
/// invisible to every other gate, so nothing else would notice.
extension Institute.Receipt.Run.Startup {
    @Suite
    struct Test {
        @Suite
        struct Integration {}

        static let dirty: [Institute.Receipt.Run.Summary] = [
            .init(id: 1, name: "swift-ci", conclusion: .success, htmlURL: "u1"),
            .init(id: 2, name: "swift-docs", conclusion: .startupFailure, htmlURL: "u2"),
        ]
        static let clean: [Institute.Receipt.Run.Summary] = [
            .init(id: 1, name: "a", conclusion: .success, htmlURL: nil),
            .init(id: 2, name: "b", conclusion: .failure, htmlURL: nil),
            .init(id: 3, name: "c", conclusion: nil, htmlURL: nil),
        ]

        static func payload(_ object: Any) throws -> [Byte] {
            [UInt8](try JSONSerialization.data(withJSONObject: object)).map(Byte.init)
        }

        @Suite
        struct Unit {
            @Test func `the one run that never started is flagged`() {
                let probe = Institute.Receipt.Run.Startup(
                    scanning: Institute.Receipt.Run.Startup.Test.dirty)
                #expect(probe.flagged.map(\.id) == [2])
                #expect(!probe.isClean)
                #expect(probe.inspected.count == 2)
            }

            @Test func `clean data flags nothing`() {
                let probe = Institute.Receipt.Run.Startup(
                    scanning: Institute.Receipt.Run.Startup.Test.clean)
                #expect(probe.flagged.isEmpty)
                #expect(probe.isClean)
            }

            @Test func `an in flight run is not a startup failure`() {
                let probe = Institute.Receipt.Run.Startup(
                    scanning: [.init(id: 9, name: "x", conclusion: nil, htmlURL: nil)])
                #expect(probe.isClean)
            }
        }

        @Suite
        struct `Edge Case` {
            @Test func `the REST object shape and a bare array read the same`() throws {
                let rows: [[String: Any]] = [
                    ["conclusion": "success", "name": "swift-ci", "id": 1, "html_url": "u1"],
                    ["conclusion": "startup_failure", "name": "swift-docs", "id": 2,
                     "html_url": "u2"],
                ]
                let wrapped = try Institute.Receipt.Run.Summary.collection(
                    Institute.Receipt.Run.Startup.Test.payload(["workflow_runs": rows]))
                let bare = try Institute.Receipt.Run.Summary.collection(
                    Institute.Receipt.Run.Startup.Test.payload(rows))
                #expect(wrapped == bare)
                #expect(Institute.Receipt.Run.Startup(scanning: wrapped).flagged.count == 1)
            }

            @Test func `a payload carrying no runs is a scan over zero runs, not an error`() throws {
                let probe = Institute.Receipt.Run.Startup(
                    scanning: try Institute.Receipt.Run.Summary.collection(
                        Institute.Receipt.Run.Startup.Test.payload(["total_count": 0])))
                #expect(probe.inspected.isEmpty)
                #expect(probe.isClean)
            }

            @Test func `invalid JSON is refused rather than read as clean`() {
                #expect(throws: Institute.Receipt.Run.Summary.Error.malformed("invalid JSON input")) {
                    try Institute.Receipt.Run.Summary.collection(
                        Array("{not json".utf8).map(Byte.init))
                }
            }
        }
    }
}
