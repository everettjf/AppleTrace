# Repository Guidelines

AppleTrace is an iOS/macOS tracing library that records Objective-C and Swift calls and exports Perfetto-compatible traces. Preserve low overhead and binary compatibility in the C/Objective-C++ core.

## Structure

- `Sources/CAppleTrace`: C-family trace runtime.
- `Sources/AppleTrace`: Swift API and tracing macros.
- `Sources/AppleTraceAuto`: automatic Swift tracing bridge.
- `Tests/AppleTraceTests`: package and macro tests.
- `appletrace/`, `loader/`, `hookzz/`: legacy Xcode/runtime components.
- `Tutorial/` and `docs/`: user-facing guides.

## Build and Test

```bash
swift build
swift test
swift run AppleTraceAutoExample
```

Run package tests after Swift API or macro changes. For runtime-hook changes, also exercise a real iOS/macOS host and open the exported trace in Perfetto.

## Conventions

- Keep event writes allocation-light and thread-safe.
- Do not move trace-core work onto the main thread.
- Preserve the documented Objective-C API while adding Swift-friendly wrappers.
- Add regression coverage for macro expansion, nested calls, concurrent calls, disabled tracing, and malformed configuration.
- Never commit generated traces, app binaries, signing material, or local package caches.

Keep `README.md`, `README_CN.md`, and tutorials aligned. Use the canonical repository URL `https://github.com/everettjf/appletrace`.
