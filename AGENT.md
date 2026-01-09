# AppleTrace Agent Guide

This reference is for AI agents and contributors working inside the AppleTrace repository. It summarizes how the project is organized, how to run and verify changes, and the expectations for contributions.

## Project Overview
- AppleTrace instruments iOS apps so you can analyze performance hotspots with Chrome's tracing viewer.
- Developers can either add manual `APTBeginSection` / `APTEndSection` markers or hook every `objc_msgSend` via HookZz (arm64 only).
- `merge.py`, Catapult's `trace2html`, and the helper `go.sh` script transform sandbox data into `trace.json` and `trace.html`.
- Releases bundle a loader tweaked for arm64, but the source can be rebuilt via the included Xcode projects.

## Repository Map
- `appletrace/` — Core framework sources (`appletrace.xcodeproj`, Objective-C runtime hooks, exported headers).
- `loader/` — Loader/packaging project plus `resign.sh` for re-signing the embedded `appletrace.framework`.
- `sample/ManualSectionDemo` and `sample/TraceAllMsgDemo` — Xcode samples that show manual instrumentation and HookZz-based tracing.
- `springboard/AppleTraceSpringBoard` — Additional loader project for SpringBoard-focused experiments.
- `hookzz/` — Embedded HookZz dependency used to hook `objc_msgSend`.
- `go.sh`, `merge.py`, `get_catapult.sh` — Scripts for merging trace files, converting them with Catapult, and downloading Catapult.
- `sampledata/` — Ready-made traces (`trace.html`) for verifying the visualization pipeline.
- `release/` — Notes and artifacts for the prebuilt loader (arm64 only).
- `image/`, `wechat.png` — Documentation assets.

## Running the Project Locally
1. **Clone & prerequisites**
   - `git clone https://github.com/everettjf/AppleTrace.git`
   - Install Xcode, Python 2.x, Chrome, LLDB, and `ldid` (for re-signing loader builds).
   - Run `sh get_catapult.sh` once to fetch Catapult (`catapult/tracing/bin/trace2html` must exist before generating HTML reports).
2. **Build instrumentation**
   - For manual tracing, open `appletrace/appletrace.xcodeproj`, build the framework, and embed it into your target (see `sample/ManualSectionDemo`).
   - For automatic tracing, build the HookZz-based dynamic library (see `sample/TraceAllMsgDemo`). This mode must run on arm64 under LLDB.
3. **Collect data**
   - Run the instrumented app; trace segments are written to `<app sandbox>/Library/appletracedata`.
   - Pull the folder from the Simulator or device.
4. **Process traces**
   - Quick path: `sh go.sh <path-to-appletracedata>` to run `merge.py`, `trace2html`, and open Chrome.
   - Manual path: `python merge.py -d <path>` followed by `python catapult/tracing/bin/trace2html <path>/trace.json --output=<path>/trace.html` or drop `trace.json` onto `chrome://tracing`.

## Testing
- There are no automated tests. Validation is manual:
  - Run the sample projects and confirm the generated `trace.json`/`trace.html`.
  - Inspect traces in Chrome to ensure new instrumentation appears as expected.
  - When touching the loader or HookZz code, test on a real arm64 device under LLDB.

## Linting & Formatting
- No dedicated lint/format pipeline exists. Follow existing Objective-C/C/C++/Python conventions in the repo (clang/Xcode defaults, 4-space indentation in Python).
- Keep public headers tidy and update comments where behavior changes.

## Build & Release
- **Frameworks**: Use `appletrace.xcodeproj` targets. Make sure exported headers remain in `appletrace.framework`.
- **Loader**: After swapping in a rebuilt framework (`loader/AppleTraceLoader/Package/Library/Frameworks/appletrace.framework`), run `loader/resign.sh` to re-sign with `ldid`.
- **Catapult**: Keep the downloaded Catapult copy in sync if `trace2html` changes; document updates in README/AGENT when bumping instructions.
- **Deliverables**: The `release/` folder is arm64-only; highlight this in release notes and README when publishing new binaries.

## Coding Style & Conventions
- Prefer concise Objective-C with explicit `APTBeginSection` markers; avoid introducing new macros unless necessary.
- Stick to existing file organization (Objective-C source under `appletrace/src`, Python utilities at repo root).
- Use descriptive section names inside traces to keep Chrome timelines meaningful.

## Debugging
- Use LLDB breakpoints around the HookZz injection points (`appletrace/src/objc/hook_objc_msgSend.m`) when troubleshooting automatic tracing.
- Inspect intermediate `trace.appletrace` files before merging to ensure data is written.
- Open `chrome://tracing` with `trace.json` to verify event ordering before generating HTML.
- Compare against `sampledata/trace.html` if output looks incorrect.

## Rules for Making Changes
- Keep changes scoped: avoid mixing instrumentation updates with tooling refactors or documentation tweaks.
- Maintain compatibility with existing arm64-only assumption unless explicitly widening platform support.
- Update README/AGENT/wiki when changing workflows, scripts, or dependencies.
- Never remove diagnostic scripts (`merge.py`, `go.sh`) without providing replacements.
- Preserve existing assets (images, sample traces) so documentation stays accurate.

## Pull Request Checklist
- [ ] Build the relevant Xcode targets (framework, loader, and/or samples) and ensure they run on device or Simulator.
- [ ] Run `python merge.py -d <path>` (or `sh go.sh <path>`) against fresh trace data to confirm the pipeline still works.
- [ ] Update `README.md`/`AGENT.md` if instructions changed; keep images/links in sync.
- [ ] Re-sign loader artifacts with `loader/resign.sh` if the embedded framework changed.
- [ ] Document manual testing performed (devices, iOS versions, Simulator).
- [ ] Ensure no unrelated files or formatting-only changes are included.
