# AppleTrace Agent Guide

This reference is for AI agents and contributors working inside the AppleTrace repository. It summarizes how the project is organized, how to run and verify changes, and the expectations for contributions.

## Project Overview
- AppleTrace instruments iOS apps so you can analyze performance hotspots in [Perfetto](https://ui.perfetto.dev).
- Developers can either add manual `APTBeginSection` / `APTEndSection` markers (plus `APTInstant` / `APTCounter` / `APTAsyncBegin` / `APTAsyncEnd` events) or hook every `objc_msgSend` via a fishhook-style direct symbol rebind (arm64 and arm64e; see `appletrace/appletrace/src/objc/hook_objc_msgSend.m`).
- `merge.py` and `scripts/appletrace_cli.py` (and the helper `go.sh`) merge sandbox fragments into a `trace.json` you open directly in Perfetto. Visualization is Perfetto-only; there is no Catapult/Chrome HTML pipeline.
- Releases bundle a loader tweaked for arm64, but the source can be rebuilt via the included Xcode projects.

## Repository Map
- `appletrace/` — Core framework sources (`appletrace.xcodeproj`, Objective-C runtime hooks, exported headers).
- `loader/` — Loader/packaging project plus `resign.sh` for re-signing the embedded `appletrace.framework`.
- `sample/TraceAllMsgDemo` — Objective-C Xcode sample showing both manual instrumentation (`APTBeginSection`) and automatic `objc_msgSend` tracing.
- `sample/AppleTraceSwiftDemo` — Swift sample (SwiftUI) that consumes the local SwiftPM package and demonstrates both Swift routes: the `@Traced`/`@TraceAll`/`withSpan` macros and the `AppleTraceAuto` SwiftTrace bridge. Build with `-destination` only (no `-sdk`, which would force the macro plugin onto the wrong SDK).
- `springboard/AppleTraceSpringBoard` — Additional loader project for SpringBoard-focused experiments.
- `go.sh`, `merge.py`, `scripts/appletrace_cli.py` — Scripts for merging trace fragments into `trace.json` and opening Perfetto.
- `sampledata/` — Ready-made trace (`trace.json`) for verifying the visualization pipeline in Perfetto.
- `release/` — Notes and artifacts for the prebuilt loader (arm64).
- `image/`, `wechat.png` — Documentation assets.

## Running the Project Locally
1. **Clone & prerequisites**
   - `git clone https://github.com/everettjf/AppleTrace.git`
   - Install Xcode, Python 3, LLDB, and `ldid` (for re-signing loader builds).
   - Optional: `python3 -m pip install -r requirements.txt` for local test tooling.
   - Visualization is browser-based at [ui.perfetto.dev](https://ui.perfetto.dev); nothing to download.
2. **Build instrumentation**
   - For Objective-C (manual sections and/or the `objc_msgSend` hook), open `appletrace/appletrace.xcodeproj`, build the framework, and embed it into your target (see `sample/TraceAllMsgDemo`).
   - For Swift, add the SwiftPM package and use the `@Traced`/`@TraceAll`/`withSpan` macros (see `sample/AppleTraceSwiftDemo`).
3. **Collect data**
   - Run the instrumented app; trace segments are written to `<app sandbox>/Library/appletracedata`.
   - Pull the folder from the Simulator or device.
4. **Process traces**
   - Quick path: `sh go.sh <path-to-appletracedata>` to merge and open Perfetto.
   - Manual path: `python3 merge.py -d <path>` then drag `<path>/trace.json` into [ui.perfetto.dev](https://ui.perfetto.dev).
   - Unified path: `python3 scripts/appletrace_cli.py open <path-to-appletracedata>`.

## Testing
- Automated coverage (also run in CI on `macos-latest`, see `.github/workflows/python-tests.yml`):
  - `python3 -m pytest tests` — Python trace merge pipeline + binary fragment format.
  - `scripts/test_objc_msgsend_hook.sh` — builds and runs `TraceAllMsgDemo` on an iOS Simulator, asserting the `objc_msgSend` hook produces trace fragments without crashing.
  - `scripts/test_objc_msgsend_hook_experimental.sh` — same harness with the experimental scenario, validating `super` dispatch, cross-thread events, stack-passed/floating-point arguments, and small aggregate returns.
  - `scripts/test_batching_stress.sh` — host build of the per-thread batched writer; runs the multithreaded workload in both text and binary (`APPLETRACE_BINARY=1`) modes and asserts no events are lost or duplicated.
  - The Simulator on Apple silicon runs the arm64 slice, so the hook ABI is exercised on a real arm64 target. The scripts assume a Python 3 with `pytest` available (e.g. a venv) on `PATH`.
- Local-only (needs hardware, not run in CI):
  - `scripts/test_objc_msgsend_hook_device.sh` — builds, installs, and runs `TraceAllMsgDemo` on a connected, unlocked arm64 device via `devicectl`, then pulls and verifies the trace in both text and binary modes. Requires a signing identity; set `DEVICE_UDID` to target a specific device.
- Still manual:
  - Instruments profiling of the batched writer (`docs/perf-batching-design.md` section 9, step 3).
  - On-device validation of the loader / LLDB dylib-injection path on a real arm64 device.

## Linting & Formatting
- No dedicated Objective-C lint/format pipeline exists. Follow existing Objective-C/C/C++/Python conventions in the repo (clang/Xcode defaults, 4-space indentation in Python).
- Keep public headers tidy and update comments where behavior changes.

## Build & Release
- **Frameworks**: Use `appletrace.xcodeproj` targets. Make sure exported headers remain in `appletrace.framework`.
- **Loader**: After swapping in a rebuilt framework (`loader/AppleTraceLoader/Package/Library/Frameworks/appletrace.framework`), run `loader/resign.sh` to re-sign with `ldid`.
- **Visualization**: Traces open in Perfetto (`ui.perfetto.dev`) directly; there is no bundled HTML exporter to keep in sync.
- **Deliverables**: The `release/` folder targets arm64; highlight this in release notes and README when publishing new binaries.

## Coding Style & Conventions
- Prefer concise Objective-C with explicit `APTBeginSection` markers; avoid introducing new macros unless necessary.
- Keep Objective-C source under `appletrace/src`; Python utilities now live both at repo root (`merge.py`) and under `scripts/` for higher-level workflows.
- Use descriptive section names inside traces to keep Perfetto timelines meaningful.

## Debugging
- Use LLDB breakpoints around the rebinding/wrapper code (`appletrace/appletrace/src/objc/hook_objc_msgSend.m`) when troubleshooting automatic tracing.
- Inspect intermediate `trace.appletrace` files before merging to ensure data is written.
- Open `trace.json` in [ui.perfetto.dev](https://ui.perfetto.dev) to verify event ordering and timing.
- Compare against `sampledata/trace.json` if output looks incorrect.

## Rules for Making Changes
- Keep changes scoped: avoid mixing instrumentation updates with tooling refactors or documentation tweaks.
- Target arm64 and arm64e; x86_64 is out of scope for the Objective-C hook. Keep the arm64e iOS 27 real-device PAC smoke test passing.
- Visualization is Perfetto-only — do not reintroduce a Catapult/Chrome HTML pipeline.
- Update README/AGENT/wiki when changing workflows, scripts, or dependencies.
- Never remove diagnostic scripts (`merge.py`, `go.sh`) without providing replacements.
- Preserve existing assets (images, sample traces) so documentation stays accurate.

## Pull Request Checklist
- [ ] Build the relevant Xcode targets (framework, loader, and/or samples) and ensure they run on device or Simulator.
- [ ] Run `python3 -m pytest tests` when touching Python tooling.
- [ ] Run `python3 merge.py -d <path>` (or `sh go.sh <path>`) against fresh trace data to confirm the pipeline still works.
- [ ] Update `README.md`/`AGENT.md` if instructions changed; keep images/links in sync.
- [ ] Re-sign loader artifacts with `loader/resign.sh` if the embedded framework changed.
- [ ] Document manual testing performed (devices, iOS versions, Simulator).
- [ ] Ensure no unrelated files or formatting-only changes are included.
