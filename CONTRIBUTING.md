# Contributing to AppleTrace

Thanks for your interest in improving AppleTrace! This guide covers how to get
set up, what we expect from changes, and how to validate them.

## Getting Started

```bash
git clone https://github.com/everettjf/AppleTrace.git
cd AppleTrace
python3 -m pip install -r requirements.txt
```

You will need Xcode 12+ (macOS 10.15+) to build the framework and samples, and a
recent Python 3 for the tooling and tests.

## Project Layout

- `appletrace/` — core tracing framework (Objective-C/C++ runtime, public headers).
- `appletrace/appletrace/src/objc/hook_objc_msgSend.m` — arm64 `objc_msgSend` hook.
- `loader/`, `springboard/` — loader/packaging projects.
- `merge.py`, `scripts/appletrace_cli.py`, `go.sh` — tooling (merge + open in Perfetto).
- `tests/` — Python regression tests.

See [AGENT.md](AGENT.md) for a deeper map and build/release details, and
[ROADMAP.md](ROADMAP.md) for where the project is headed.

## Making Changes

- Keep changes scoped: don't mix instrumentation, tooling, and docs in one PR.
- The `objc_msgSend` hook targets arm64 only — preserve that assumption
  (arm64e and other architectures are out of scope; the hook hard-errors on arm64e).
- Avoid adding work to the tracing hot path; prefer caching/interning and
  per-thread state over per-event allocation.
- Update `README.md` / `README_CN.md` / `AGENT.md` when workflows or APIs change.

## Testing

```bash
# Python tooling
python3 -m pytest tests

# objc_msgSend hook smoke tests (run on a Mac)
./scripts/test_objc_msgsend_hook.sh
./scripts/test_objc_msgsend_hook_experimental.sh

# Verify the merge + export pipeline on real data
python3 merge.py -d <path-to-appletracedata>
```

When touching the framework, build the relevant Xcode targets and confirm a
trace renders correctly in [Perfetto](https://ui.perfetto.dev).

## Code Style

- **Objective-C:** [Google Objective-C Style Guide](https://google.github.io/styleguide/objcguide.html)
- **Python:** [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- **Shell:** [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

## Pull Requests

1. Fork and create a feature branch.
2. Make your change with tests where applicable.
3. Run the test commands above and note any manual testing (device, iOS version).
4. Open a PR describing the change and its motivation.
