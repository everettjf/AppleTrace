//
//  MacroExpansionTests.swift
//  Verifies the @Traced / @TraceAll macros expand to the expected source.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

import AppleTraceMacrosPlugin

private let testMacros: [String: Macro.Type] = [
    "Traced": TracedMacro.self,
    "TraceAll": TraceAllMacro.self,
]

final class MacroExpansionTests: XCTestCase {
    func testTracedWrapsBody() {
        assertMacroExpansion(
            """
            @Traced
            func loadConfig() {
                work()
            }
            """,
            expandedSource: """
            func loadConfig() {
                AppleTrace.beginSection(#function)
                defer {
                    AppleTrace.endSection(#function)
                }
                work()
            }
            """,
            macros: testMacros
        )
    }

    func testTracedWrapsThrowingBodyWithReturn() {
        assertMacroExpansion(
            """
            @Traced
            func value() throws -> Int {
                return try compute()
            }
            """,
            expandedSource: """
            func value() throws -> Int {
                AppleTrace.beginSection(#function)
                defer {
                    AppleTrace.endSection(#function)
                }
                return try compute()
            }
            """,
            macros: testMacros
        )
    }

    func testTraceAllStampsTracedOnMethods() {
        assertMacroExpansion(
            """
            @TraceAll
            final class FeedViewModel {
                let title = "Feed"
                func reload() {
                }
                func render(_ x: Int) -> Int {
                    x
                }
            }
            """,
            expandedSource: """
            final class FeedViewModel {
                let title = "Feed"
                func reload() {
                    AppleTrace.beginSection(#function)
                    defer {
                        AppleTrace.endSection(#function)
                    }
                }
                func render(_ x: Int) -> Int {
                    AppleTrace.beginSection(#function)
                    defer {
                        AppleTrace.endSection(#function)
                    }
                    x
                }
            }
            """,
            macros: testMacros
        )
    }
}
