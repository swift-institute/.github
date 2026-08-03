// [swift-institute/.github#219] EXEMPT: SwiftSyntaxMacros protocol
// witnesses. Every macro role protocol (MemberMacro, ExtensionMacro,
// MemberAttributeMacro, AccessorMacro, ...) names its requirement
// `static func expansion(...)` and ends the parameter list with
// `in context: some MacroExpansionContext`, immediately before an untyped
// `throws` fixed by the upstream protocol declaration (shape verified
// against swift-foundations/swift-copy-on-write's `CoWMacro.swift`, the
// #219 red-A evidence). `typed_throws_required` must NOT fire below.
// (`no_any_protocol_existential` was never at risk here: the parameter is
// `some MacroExpansionContext`, not `any`.)

import SwiftSyntax
import SwiftSyntaxMacros

public struct SampleMacro {}

extension SampleMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return []
    }
}
