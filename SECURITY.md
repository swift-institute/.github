# Security Policy

## Reporting a vulnerability

If you believe you have discovered a security vulnerability in any Swift Institute
package, report it privately rather than opening a public issue.

The reporting channel is GitHub's private vulnerability reporting:

- **[Open a security advisory](https://github.com/swift-institute/swift-institute/security/advisories/new)**

This routes the report directly to the maintainer and keeps the details private
until a fix is coordinated. Please include:

- A description of the issue and its impact
- Steps to reproduce (minimal example where possible)
- The Swift toolchain version and platform on which you observed the issue
- Any suggested mitigations

## Response

Reports are acknowledged and triaged by the maintainer. A coordinated disclosure
timeline is agreed with the reporter. Reporters receive credit in the release
notes for the fix unless they prefer to remain anonymous.

## Scope

This policy applies to all packages in the Swift Institute ecosystem:

- [swift-primitives](https://github.com/swift-primitives)
- [swift-standards](https://github.com/swift-standards) and per-authority organizations
- [swift-foundations](https://github.com/swift-foundations)
- [swift-institute](https://github.com/swift-institute)

For vulnerabilities in dependencies (Swift standard library, toolchain, external
packages), report to the upstream project directly.
