# AppleTrace 🍎

<div align="center">

[![GitHub Stars](https://img.shields.io/github/stars/everettjf/AppleTrace?style=flat-square&color=4ECDC4)](https://github.com/everettjf/AppleTrace/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/everettjf/AppleTrace?style=flat-square&color=4ECDC4)](https://github.com/everettjf/AppleTrace/network)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/everettjf/AppleTrace?style=flat-square)](https://github.com/everettjf/AppleTrace/commits/master)
[![Contributors](https://img.shields.io/github/contributors/everettjf/AppleTrace?style=flat-square)](https://github.com/everettjf/AppleTrace/graphs/contributors)

**Objective-C Method Tracing & Call Graph Analysis Tool**

[English](README.md) | [中文](README_CN.md)

</div>

> 🚀 **Actively developed.** AppleTrace is a lightweight, embeddable tracer that
> produces shareable Chrome/Perfetto traces. See [ROADMAP.md](ROADMAP.md) for
> what's planned next.

## What's New

- **Faster `objc_msgSend` hook** — `(Class, SEL)` name interning plus a
  zero-allocation per-thread call stack remove the per-message `malloc`/`snprintf`
  churn from the hot path.
- **Thread names** — traces now label each thread (Perfetto/Chrome show real
  names instead of bare ids).
- **More event types** — `APTInstant` markers and `APTCounter` series (memory,
  FPS, custom metrics) in addition to begin/end sections.
- **Runtime filtering** — limit automatic tracing with class-prefix allow/deny
  lists (`APPLETRACE_TRACE_CLASS_ALLOW` / `APPLETRACE_TRACE_CLASS_DENY`).
- **Perfetto-first visualization** — open `trace.json` at
  [ui.perfetto.dev](https://ui.perfetto.dev) with no download required (Catapult
  HTML export remains available offline).
- Python 3 tooling with a unified CLI (`scripts/appletrace_cli.py`), automated
  tests, GitHub Actions CI, and streaming trace merging for large captures.
- Runtime controls: `APTFlush`, `APTSetEnabled`, `APTIsEnabled`,
  `APTGetTraceDirectory`, plus configurable output directory and mmap block size.

---

## 🎯 What is AppleTrace?

AppleTrace is an iOS tracing toolkit

![AppleTrace Demo](https://everettjf.github.io/stuff/appletrace/appletrace.gif) that captures your app's execution timeline and renders it with Chrome's tracing tools.

![AppleTrace Demo](image/appletrace-small.png)

### Key Features

- 📊 **Method Tracing** - Directly rebind `objc_msgSend` on arm64 to capture Objective-C method activity
- 🎯 **Custom Sections** - Define custom trace sections with APTBeginSection/APTEndSection
- 📈 **Call Graph** - Visualize call relationships and execution flow
- 🌐 **Chrome Integration** - Export traces to chrome://tracing or generate shareable HTML reports
- 🔧 **Dual Modes** - Manual instrumentation or dynamic hooking via direct `objc_msgSend` rebinding

### Current Hook Status

- Stable path: manual sections plus delayed `objc_msgSend` hook installation are covered by simulator smoke tests.
- Experimental path: app-owned nested Objective-C sends, `objc_msgSendSuper2`, cross-thread events, a 10-argument Objective-C call, floating-point argument/return handling, and small aggregate return values are now covered by a second simulator trace scenario.
- Recommended release posture: ship the current direct hook as an arm64 preview, with manual sections still available as the lowest-risk baseline.

### Use Cases

- 🔍 **Performance Analysis** - Identify performance bottlenecks
- 🐛 **Debugging** - Trace method execution flow
- 📚 **Learning** - Understand how iOS frameworks work
- 🛡️ **Security Research** - Analyze third-party app behavior

---

## ⚡ Quick Start

### 1. Install Dependencies

```bash
# macOS with Homebrew
brew install python ldid git

# Clone the repository
git clone https://github.com/everettjf/AppleTrace.git
cd AppleTrace

# Download Catapult tooling
sh get_catapult.sh

# Optional but recommended: install Python tooling
python3 -m pip install -r requirements.txt
```

### 2. Choose Your Mode

#### Mode A: Manual Instrumentation (Recommended)

```objc
// Add to your Objective-C code
#import <appletrace/appletrace.h>

- (void)yourMethod {
    APTBegin;
    // Your code here
    APTEnd;
}
```

#### Mode B: Dynamic Hooking (Advanced)

```bash
# Requires arm64 and explicit hook installation
# Call APTInstallObjcMsgSendHook() after app launch
```

### 3. Capture & Visualize

```bash
# Run your app on simulator/device
# Traces are saved to /Library/appletracedata

# Merge trace files
python3 merge.py -d /Library/appletracedata

# Generate HTML report (requires Catapult)
sh go.sh /Library/appletracedata

# Open in Chrome
open /Library/appletracedata/trace.html
```

### 4. View Results

- **Option 1 (recommended):** Open [ui.perfetto.dev](https://ui.perfetto.dev) and
  drag in `trace.json` — runs in the browser, scales to large traces, no download
- **Option 2:** Open `trace.html` directly in Chrome (offline Catapult export)
- **Option 3:** Drag `trace.json` into chrome://tracing
- **Option 4:** Use the [online demo](sampledata/trace.html)

---

## 📦 Installation

### Requirements

| Requirement | Version | Description |
|-------------|---------|-------------|
| **macOS** | 10.15+ | Build environment |
| **Xcode** | 12+ | iOS/macOS development |
| **Python** | 3.9+ | Trace processing scripts and test tooling |
| **Chrome** | Any | Trace visualization |
| **LLDB** | (Optional) | Dynamic hook mode |

### Setup Steps

```bash
# 1. Clone the repository
git clone https://github.com/everettjf/AppleTrace.git
cd AppleTrace

# 2. Download Catapult (required for HTML export)
sh get_catapult.sh

# 3. Build the framework
cd appletrace/appletrace.xcodeproj
xcodebuild -project appletrace.xcodeproj -scheme appletrace -configuration Release build

# 4. (Optional) Install signing tool for iOS
brew install ldid
```

---

## 📁 Project Structure

```
AppleTrace/
├── appletrace/              # Core tracing framework
│   ├── appletrace.xcodeproj
│   ├── appletrace/          # Framework source
│   └── appletraceTests/
├── loader/                  # Dynamic library loader
│   └── AppleTraceLoader/
├── sample/                  # Example projects
│   ├── ManualSectionDemo/   # Manual instrumentation demo
│   └── TraceAllMsgDemo/     # Dynamic hook demo
├── image/                   # Documentation images
├── sampledata/              # Demo trace files
├── scripts/                 # Utility scripts
│   └── appletrace_cli.py    # Merge + HTML generation CLI
├── merge.py                 # Merge trace files
├── go.sh                    # One-shot merge + HTML generation
├── get_catapult.sh          # Download Catapult
├── requirements.txt         # Python dependencies
├── tests/                   # Python regression tests
├── README.md               # English documentation
└── README_CN.md            # Chinese documentation
```

---

## 🛠️ Usage

### Manual Instrumentation

#### Objective-C

```objc
#import <appletrace/appletrace.h>

- (void)viewDidLoad {
    APTBegin;
    [super viewDidLoad];
    // Your code
    APTEnd;
}

// Or with custom section name
- (void)networkRequest {
    APTBeginSection("network");
    // Network code
    APTEndSection("network");
}
```

#### C/C++

```cpp
#include <appletrace/appletrace.h>

void complexFunction() {
    APTBeginSection("processing");
    // C++ code
    APTEndSection("processing");
}

void saferCppFunction() {
    APTScopeSection("processing");
    // C++ code
}
```

### Instant Markers & Counters

```objc
// Mark a point in time on the current thread's timeline
APTInstant("cache_miss");

// Plot a value over time (memory, FPS, queue depth, ...)
APTCounter("resident_mb", 142.5);
APTCounter("fps", 60);
```

### Dynamic Hooking Smoke Test

```bash
./scripts/test_objc_msgsend_hook.sh
./scripts/test_objc_msgsend_hook_experimental.sh
```

The first script validates the baseline delayed-install flow. The second script validates nested sample method tracing, `super` dispatch, cross-thread events, explicit section pairing, stack-passed Objective-C arguments, floating-point Objective-C arguments and return values, and small aggregate returns.

### Runtime Controls

```objc
APTSetEnabled(NO);   // Temporarily disable trace recording
APTSetEnabled(YES);  // Re-enable
APTFlush();          // Force buffered writes to disk
NSLog(@"trace dir = %s", APTGetTraceDirectory());
```

### Dynamic Hook Mode

```bash
# 1. Build your app with AppleTraceLoader
# 2. Run under LLDB
lldb YourApp.app

# 3. Load the dynamic library
(lldb) command script import loader/AppleTraceLoader.py
(lldb) AppleTraceLoader.load()

# 4. Run your app - all objc_msgSend calls will be traced
```

### Processing Traces

```bash
# Merge all trace files
python3 merge.py -d /path/to/appletracedata

# Or use the unified CLI
python3 scripts/appletrace_cli.py merge /path/to/appletracedata

# Generate HTML (requires Catapult)
python3 catapult/tracing/bin/trace2html \
  /path/to/appletracedata/trace.json \
  --output=/path/to/appletracedata/trace.html

# Or use the helper script
sh go.sh /path/to/appletracedata

# One-shot merge + HTML via CLI
python3 scripts/appletrace_cli.py all /path/to/appletracedata --open
```

### Runtime Environment Variables

```bash
export APPLETRACE_ENABLED=1
export APPLETRACE_DATA_DIR="$HOME/tmp/appletracedata"
export APPLETRACE_BLOCK_SIZE_MB=32
export APPLETRACE_KEEP_EXISTING=1

# Automatic objc_msgSend hook (arm64)
export APPLETRACE_AUTO_HOOK_OBJC_MSGSEND=1
# Only trace classes with these comma-separated prefixes
export APPLETRACE_TRACE_CLASS_ALLOW="MyApp,UI"
# Never trace classes with these prefixes (takes precedence over allow)
export APPLETRACE_TRACE_CLASS_DENY="NSKVO,_"
```

---

## 🛠️ Tech Stack

<div align="center">

**Core Technologies**
![Objective-C](https://img.shields.io/badge/Objective--C-438APD?style=flat-square&logo=apple)
![C](https://img.shields.io/badge/C-00599C?style=flat-square&logo=c)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python)
![Xcode](https://img.shields.io/badge/Xcode-147EFB?style=flat-square&logo=xcode)

**Key Dependencies**
![HookZz](https://img.shields.io/badge/HookZz-FF6B6B?style=flat-square&logo=github)
![Catapult](https://img.shields.io/badge/Catapult-4ECDC4?style=flat-square&logo=google-chrome)
![LLDB](https://img.shields.io/badge/LLDB-1A73E8?style=flat-square&logo=llvm)

</div>

---

## 📊 Demo

### Interactive Demo

Explore a pre-recorded trace directly in Chrome:

- 📂 **[Interactive Trace Demo](sampledata/trace.html)** - Open in Chrome to see AppleTrace in action

![Demo Preview](image/appletrace-small.png)

*The trace visualization shows method execution timeline and call relationships.*

---

## ❓ FAQ

### Q: Is AppleTrace still maintained?

**Yes — AppleTrace is actively developed.** Recent work focuses on hot-path
performance, richer trace events, and modern Perfetto-based visualization. See
[ROADMAP.md](ROADMAP.md) for what's coming next, and contributions are welcome.

### Q: Does AppleTrace work on iOS 17+?

Yes, but with limitations:
- ✅ Manual instrumentation works on all iOS versions
- ⚠️ Dynamic hook mode may have compatibility issues on iOS 17+

### Q: Can I trace third-party apps?

Yes! See the Chinese guide: [搭载MonkeyDev可 trace 第三方 App](http://everettjf.github.io/2017/10/12/appletrace-dancewith-monkeydev/)

### Q: Why is Python 3 required?

Python 2.x reached end-of-life in 2020. AppleTrace now requires Python 3.8+ for security and compatibility.

### Q: Can I use this on macOS apps?

Yes! AppleTrace works for both iOS and macOS applications.

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Commit** your changes: `git commit -m 'Add amazing feature'`
4. **Push** to the branch: `git push origin feature/amazing-feature`
5. **Submit** a Pull Request

### Code Style

- **Objective-C:** [Google Objective-C Style Guide](https://google.github.io/styleguide/objcguide.html)
- **Python:** [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- **Shell:** [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

### Testing

```bash
# Build the framework
xcodebuild -project appletrace/appletrace.xcodeproj \
  -scheme appletrace \
  -configuration Release \
  -sdk iphonesimulator build

# Run merge script
python3 merge.py -d sampledata/
```

---

## 📜 License

AppleTrace is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

<div align="center">

**Core Dependencies**

<a href="https://github.com/jmpews/HookZz">
  <img src="https://img.shields.io/badge/HookZz-FF6B6B?style=for-the-badge&logo=github" />
</a>

<a href="https://github.com/catapult-project/catapult">
  <img src="https://img.shields.io/badge/Catapult-4ECDC4?style=for-the-badge&logo=github" />
</a>

**Inspired by**
- Facebook's [fbtrace](https://github.com/facebookarchive/fbtrace)
- Google's [Chrome Tracing](https://www.chromium.org/developers/how-tos/trace-event-profiling-tool)

</div>

---

## 📈 Star History

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=everettjf/AppleTrace&type=Date&theme=dark)](https://star-history.com/#everettjf/AppleTrace&Date)

</div>

---

## 📞 Support

<div align="center">

<a href="https://github.com/everettjf/AppleTrace/issues">
  <img src="https://img.shields.io/badge/Issues-Bug_Reports-FF6B6B?style=for-the-badge&logo=github" />
</a>
<a href="https://github.com/everettjf/AppleTrace/discussions">
  <img src="https://img.shields.io/badge/Discussions-Questions-4ECDC4?style=for-the-badge&logo=github" />
</a>
<a href="http://everettjf.github.io/2017/09/21/appletrace/">
  <img src="https://img.shields.io/badge/Docs-中文教程-45B7D1?style=for-the-badge&logo=readthedocs" />
</a>

**中文交流：** 欢迎关注微信订阅号

<img src="image/wechat.png" alt="WeChat" width="150"/>

</div>

---

<div align="center">

**Made with ❤️ by [Everett](https://github.com/everettjf)**

**Project Link:** [https://github.com/everettjf/AppleTrace](https://github.com/everettjf/AppleTrace)

</div>
