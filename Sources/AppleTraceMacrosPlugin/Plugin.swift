//
//  Plugin.swift
//  SwiftSyntax implementation of the AppleTrace tracing macros.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Traced` — a body macro that wraps the function body in a trace section
/// named after `#function`, closed via `defer` so it survives throws / early
/// returns.
public struct TracedMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        let original = declaration.body?.statements ?? []
        var statements: [CodeBlockItemSyntax] = [
            "AppleTrace.beginSection(#function)",
            "defer { AppleTrace.endSection(#function) }",
        ]
        statements.append(contentsOf: original)
        return statements
    }
}

/// `@TraceAll` — a member-attribute macro that stamps `@Traced` onto every
/// method (with a body) declared directly in the type or extension.
public struct TraceAllMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let function = member.as(FunctionDeclSyntax.self), function.body != nil else {
            return []
        }
        let alreadyTraced = function.attributes.contains { element in
            element.as(AttributeSyntax.self)?
                .attributeName.trimmedDescription == "Traced"
        }
        return alreadyTraced ? [] : ["@Traced"]
    }
}

@main
struct AppleTraceMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TracedMacro.self,
        TraceAllMacro.self,
    ]
}
