//
//  AppleTraceAuto.swift
//  Secondary (zero-annotation) Swift tracing route.
//
//  Bridges the proven SwiftTrace runtime hook into AppleTrace's pipeline:
//  SwiftTrace patches Swift vtables/witness tables with trampolines, and this
//  module forwards each traced method's entry/exit to APTBeginSection /
//  APTEndSection so the calls land in the same Perfetto trace as everything
//  else.
//
//  This is a development/diagnostics tool, **best suited to the Simulator and
//  macOS**. SwiftTrace patches vtable function pointers, which are
//  pointer-authenticated on real devices, so tracing typically isn't safe
//  on-device — gate calls with `#if targetEnvironment(simulator)` and rely on
//  the @Traced / @TraceAll macros there (they work everywhere). Per SwiftTrace's
//  own limitations it also cannot see `final`/internal methods the optimizer
//  dispatches directly. For exact, dispatch-agnostic coverage of your own code,
//  prefer the macros; use this for zero-annotation coverage of class hierarchies
//  in the Simulator.

import CAppleTrace
import SwiftTrace

/// A SwiftTrace swizzle that emits an AppleTrace section spanning each traced
/// method invocation.
///
/// It subclasses the lightweight `Swizzle` (not `Decorated`) and deliberately
/// does not call `super`: the trampoline performs the real call and only uses
/// `onEntry`/`onExit` as observers, so emitting begin/end here is sufficient.
/// This avoids `Decorated`'s argument-reflection/logging path, which is heavier
/// and less robust across threads and platforms.
final class AppleTraceSwizzle: SwiftTrace.Swizzle {
    override func onEntry(stack: inout SwiftTrace.EntryStack, invocation: Invocation) {
        APTBeginSection(signature)
    }

    override func onExit(stack: inout SwiftTrace.ExitStack, invocation: Invocation) {
        APTEndSection(signature)
    }
}

public enum AppleTraceAuto {
    /// Routes SwiftTrace through AppleTrace. Called automatically by the
    /// `trace*` helpers; call it yourself before using SwiftTrace's own API.
    public static func installBridge() {
        SwiftTrace.swizzleFactory = AppleTraceSwizzle.self
    }

    /// Traces every method of `aClass` into the AppleTrace timeline.
    public static func trace(aClass: AnyClass) {
        installBridge()
        SwiftTrace.trace(aClass: aClass)
    }

    /// Traces classes whose name matches `pattern` (a regular expression).
    public static func traceClasses(matchingPattern pattern: String) {
        installBridge()
        SwiftTrace.traceClasses(matchingPattern: pattern)
    }

    /// Traces all classes in the bundle that defines `aClass`.
    public static func traceBundle(containing aClass: AnyClass) {
        installBridge()
        SwiftTrace.traceBundle(containing: aClass)
    }

    /// Removes all installed traces.
    public static func stop() {
        SwiftTrace.removeAllTraces()
    }
}
