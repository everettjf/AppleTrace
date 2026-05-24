//
//  MacroUsageTests.swift
//  Compiles and runs code that actually applies @Traced / @TraceAll, proving
//  the macros work end-to-end (not just in expansion tests) and emit events.
//

import XCTest
@testable import AppleTrace

@Traced
private func tracedFreeFunction() {
    _ = (1...10).reduce(0, +)
}

@TraceAll
private final class TracedSample {
    func alpha() {
        beta()
    }

    func beta() {
        _ = (1...10).reduce(0, +)
    }
}

final class MacroUsageTests: XCTestCase {
    func testMacrosEmitSections() throws {
        tracedFreeFunction()
        TracedSample().alpha()
        flush()

        let dir = traceDirectory
        let fragments = try FileManager.default
            .contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".appletrace") }
        XCTAssertFalse(fragments.isEmpty)

        let url = URL(fileURLWithPath: dir).appendingPathComponent(fragments[0])
        let text = String(decoding: try Data(contentsOf: url).filter { $0 != 0 }, as: UTF8.self)
        XCTAssertTrue(text.contains("tracedFreeFunction()"), "@Traced free function missing")
        XCTAssertTrue(text.contains("alpha()"), "@TraceAll method alpha missing")
        XCTAssertTrue(text.contains("beta()"), "@TraceAll method beta missing")
    }
}
