# AppleTrace
> AppleTrace is an iOS tracing toolkit that captures your app's execution timeline and renders it with Chrome's tracing tools.

*>> I have developed a replacement called [Messier](https://messier.github.io/) which is much easier to use. :)*

![logo](/image/appletrace-small.png)

**Additional documentation (Chinese)**  
- [中文说明，开发思路及方法](http://everettjf.github.io/2017/09/21/appletrace/)  
- [搭载MonkeyDev可 trace 第三方 App](http://everettjf.github.io/2017/10/12/appletrace-dancewith-monkeydev/)

![appletrace](https://everettjf.github.io/stuff/appletrace/appletrace.gif)

## Badges
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](#)

## Table of Contents
- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [FAQ](#faq)
- [Configuration](#configuration)
- [Examples](#examples)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)
- [Star History](#star-history)

## Features
1. Define custom trace sections anywhere in Objective-C or C/C++ code with `APTBeginSection` / `APTEndSection`.
2. Automatically trace Objective-C method calls by hooking every `objc_msgSend` using HookZz (arm64, LLDB).
3. Export data that can be dropped directly into `chrome://tracing` or converted into shareable HTML reports.

## Quick Start
1. **Clone** the repository with `git clone https://github.com/everettjf/AppleTrace.git`. For stable builds refer to [Releases](https://github.com/everettjf/AppleTrace/releases).
2. **Instrument** your app by either adding `appletrace.framework` and manual `APTBegin`/`APTEnd` macros or by running the provided HookZz-based dynamic library to trace every `objc_msgSend`.
3. **Run** the app on a Simulator or arm64 device (debugger/LLDB required for HookZz mode) to produce trace files inside `<app sandbox>/Library/appletracedata`.
4. **Merge & visualize** the trace by running `sh go.sh <path-to-appletracedata>`. The script calls `python merge.py` and `catapult/tracing/bin/trace2html` when Catapult is available, then opens Chrome with the generated `trace.html`. Without Catapult you can still drag `trace.json` into `chrome://tracing`.

## Installation
- **Dependencies**
  - macOS with Xcode (to build the framework, samples, and loader).
  - Python 2.x (for `merge.py` and `go.sh`).
  - Chrome browser for viewing traces.
  - LLDB if you plan to hook every `objc_msgSend`.
- **Clone the source**
  ```bash
  git clone https://github.com/everettjf/AppleTrace.git
  ```
- **Catapult tooling**  
  Run `sh get_catapult.sh` once to fetch the [catapult-project/catapult](https://github.com/catapult-project/catapult) repository used by `trace2html`.
- **Release builds**  
  The packaged loader under `release/` currently targets **arm64 only** (`release/README.md`). Use the `AppleTraceLoader` target and `loader/resign.sh` to rebuild or refresh it.

## Usage
AppleTrace follows a four-step workflow. The sections below expand on each step.

### 1. Produce trace data
There are two supported modes:

**Manual instrumentation**
```objc
void anyKindsOfMethod(){
    APTBeginSection("process");
    // some code
    APTEndSection("process");
}

- (void)anyObjectiveCMethod{
    APTBegin;
    // some code
    APTEnd;
}
```
Use the `sample/ManualSectionDemo` Xcode project as a reference integration.

**Dynamic hook**
- Use the HookZz-based dynamic library that hooks every `objc_msgSend`.
- Requires arm64 and running under LLDB.
- `sample/TraceAllMsgDemo` demonstrates this setup.

### 2. Copy the raw data
After the device/session run completes, copy `<app sandbox>/Library/appletracedata` from either the Simulator or the physical device.

![appletracedata](image/appletracedata.png)

### 3. Merge trace files
Merge and preprocess the captured `trace.appletrace`, `trace_*.appletrace`, etc.
```bash
python merge.py -d <appletracedata directory>
```
The script writes `trace.json` into the same directory. The helper script `sh go.sh <appletracedata directory>` executes the merge and (optionally) generates HTML in one step.

### 4. Generate HTML / visualize
1. Run `sh get_catapult.sh` once to download Catapult.
2. Convert the JSON into HTML:
   ```bash
   python catapult/tracing/bin/trace2html appletracedata/trace.json --output=appletracedata/trace.html
   open appletracedata/trace.html
   ```
3. Alternatively drop `trace.json` onto `chrome://tracing`.  
   *`trace.html` is only supported by Chrome.*

## FAQ
Additional answers live in the [project wiki](https://github.com/everettjf/AppleTrace/wiki).

## Configuration
- **Instrumentation macros** — Use `APTBeginSection(name)`/`APTEndSection(name)` for C/C++ and `APTBegin`/`APTEnd` in Objective-C. Create sections that reflect your business logic to highlight performance hotspots.
- **Hook configuration** — The HookZz-based mode hooks every `objc_msgSend`, requires LLDB, and currently supports arm64 only.
- **Data location** — Traces are stored under `<app sandbox>/Library/appletracedata`. The `merge.py` output is `trace.json` in that directory.
- **Catapult path** — `catapult/tracing/bin/trace2html` is invoked during report generation. Use the bundled `get_catapult.sh` script to download the correct version.
- **Loader/signing** — When replacing `loader/AppleTraceLoader/Package/Library/Frameworks/appletrace.framework`, run `loader/resign.sh` (uses `ldid -S`) to keep the loader deployable.

## Examples
- `sample/ManualSectionDemo` — demonstrates manual section markers in Objective-C.
- `sample/TraceAllMsgDemo` — shows how to run the HookZz dynamic hook for capturing every method call.
- `sampledata/trace.html` — open the bundled HTML in Chrome to explore a pre-recorded trace.

## Development
- Open `appletrace/appletrace.xcodeproj` in Xcode to hack on the framework and Objective-C runtime hooks.
- Use the sample projects under `sample/` to validate manual instrumentation and HookZz integrations.
- `get_catapult.sh`, `merge.py`, and `go.sh` compose the trace-processing toolchain—keep them in sync when upgrading dependencies.
- The loader artifacts live in `loader/AppleTraceLoader`. After swapping in a rebuilt framework, execute `loader/resign.sh` to re-sign with `ldid`.
- Run `python merge.py -d <path>` and inspect the resulting `trace.json`/`trace.html` during development to verify new instrumentation.

## Contributing
Issues, pull requests, and ideas are welcome. Please:
- Keep PRs focused on a single improvement (instrumentation, tooling, docs, etc.).
- Test changes with the sample projects or your own app and attach relevant traces.
- Update documentation (README/AGENT/wiki) whenever behavior changes.

## License
AppleTrace is released under the [MIT License](LICENSE).

## Acknowledgements
- [HookZz](https://github.com/jmpews/HookZz) powers the `objc_msgSend` hook mode.
- [Catapult](https://github.com/catapult-project/catapult) provides `trace2html`.
- 欢迎关注微信订阅号，更多有趣的性能优化点点滴滴：  
  ![fun](wechat.png)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=everettjf/AppleTrace&type=Date)](https://star-history.com/#everettjf/AppleTrace&Date)

