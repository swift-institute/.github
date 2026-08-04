# Real caller fixtures (Task 5-01, swift-institute/.github#276, #282)

Byte-for-byte snapshots of real `.github/workflows/ci.yml` files, fetched
live during this task's authoring, used by
`test-generate-caller.py`'s `RealCallerRoundTripTests`. Each file's
provenance (source repository, ref, fetch date) is below rather than
duplicated per-file — these are point-in-time evidence like the Task 1-01
wrapper snapshots, not a live sync.

| File | Source repository | Class |
|---|---|---|
| `array-primitives.yml` | `swift-primitives/swift-array-primitives` | same-org, Primitives, no typed input |
| `domain-standard.yml` | `swift-standards/swift-domain-standard` | same-org, Standards, no typed input |
| `copy-on-write.yml` | `swift-foundations/swift-copy-on-write` | same-org, Foundations, no typed input |
| `rfc-3986.yml` | `swift-ietf/swift-rfc-3986` | cross-org, Standards, no typed input |
| `linux-standard.yml` | `swift-linux-foundation/swift-linux-standard` | cross-org, Standards, `platform-support: apple,linux` |
| `windows-32.yml` | `swift-microsoft/swift-windows-32` | cross-org, Standards, `platform-support: windows` |
| `iso-9945.yml` | `swift-iso/swift-iso-9945` | cross-org, Standards, `platform-support: apple,linux` |

Fetched: 2026-08-04, via `gh api repos/<repo>/contents/.github/workflows/ci.yml`.
