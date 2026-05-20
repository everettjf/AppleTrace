# AppleTrace Optimization & Roadmap

> Status: AppleTrace is actively developed. This document captures the
> optimization opportunities, a competitive comparison, and a phased plan that
> drive the project forward. Items marked ✅ have shipped.

## 1. Where We Are Today

- **Tracing backends**: manual `APTBeginSection`/`APTEndSection` markers, plus an
  arm64-only direct `objc_msgSend` / `objc_msgSendSuper2` rebind
  (`appletrace/appletrace/src/objc/hook_objc_msgSend.m`).
- **Runtime**: a single serial dispatch queue serializes one JSON line per event
  into an mmap-backed file (`appletrace/appletrace/src/appletrace.mm`).
- **Tooling**: `merge.py` / `scripts/appletrace_cli.py` merge fragments into a
  Chrome JSON array; `go.sh` + `get_catapult.sh` render HTML via Google Catapult.
- **CI**: Python merge tests + two simulator smoke tests (`.github/workflows`).

## 2. Optimization Opportunities

### 2.1 Hot-path performance (highest impact on trace fidelity)

The `objc_msgSend` hot path is far too heavy, which distorts the timings it is
meant to measure:

- `apt_copy_trace_name` (`hook_objc_msgSend.m:360`) does a `malloc` + `snprintf`
  to build `"[Class]selector"` on **every** message send, with no caching.
- `Trace::WriteSection` (`appletrace.mm:318`) builds a `std::string` JSON line and
  `dispatch_async`es it (block copy + enqueue) per event. Under full
  `objc_msgSend` tracing the serial queue becomes the bottleneck and memory
  balloons.

Recommended redesign:

- **String interning**: cache the formatted name keyed by `(Class, SEL)` so the
  hot path stores an integer id, not a freshly allocated string.
- **Per-thread ring buffers**: record fixed-size binary events
  `(timestamp, phase, tid, name_id)` lock-free per thread; flush in bulk on a
  background thread instead of one dispatch per event.
- **Defer formatting**: emit binary events at runtime and convert to JSON only in
  `merge.py` (or a new exporter), removing JSON string building from the hot path.

### 2.2 Visualization pipeline modernization (highest ROI / lowest risk)

The HTML pipeline depends on Google's **deprecated Catapult `trace2html`**
(`get_catapult.sh`, `go.sh`). The modern standard is **Perfetto**
(`ui.perfetto.dev`), which ingests the same Chrome JSON, runs entirely in the
browser (no multi-hundred-MB download), and scales to far larger traces.

- Make Perfetto the documented default ("open trace.json at ui.perfetto.dev").
- Keep Catapult as an optional offline path.
- Longer term: emit the Perfetto protobuf format for streaming + smaller files.

### 2.3 Trace format & expressiveness

- ✅ Support `X` (complete) events to roughly halve file size vs. paired
  `B`/`E` (`merge.py --complete`).
- ✅ Emit `thread_name` metadata events so threads are labeled in
  Perfetto/Chrome (previously only `process_name` was written).
- ✅ Add **counter** (`APTCounter`) and **instant** (`APTInstant`) events.
  Async/flow events to track work across dispatch queues are still open.
- ✅ Stream `merge.py` output instead of loading every event into memory, so
  large captures don't exhaust RAM.

### 2.4 Filtering & control

- ✅ Add runtime class-prefix allow/deny lists
  (`APPLETRACE_TRACE_CLASS_ALLOW` / `APPLETRACE_TRACE_CLASS_DENY`).
- A sampling mode (trace 1/N sends) is intentionally deferred: it does not
  compose with the nested begin/end model, so it is not on the near-term plan.

### 2.5 Housekeeping

- ✅ Add the `CONTRIBUTING.md` that the README references.
- Document the arm64-only constraint of the hook prominently and consider an
  x86_64-simulator path for broader CI.

## 3. Competitive Comparison

| Tool | Mechanism | Strengths | Position vs. AppleTrace |
|------|-----------|-----------|--------------------------|
| **Frida / frida-trace** | Dynamic injection | Cross-platform, scriptable, very active | Full-featured but heavier, needs debug/jailbreak posture |
| **InspectiveC** | fishhook `objc_msgSend` | Per-object / per-class / per-selector filtering | Closest in approach; richer filtering |
| **Instruments (os_signpost)** | OS-level | First-party, low overhead, strong timeline | Could be a low-overhead backend AppleTrace targets |
| **Perfetto** | Visualization + SDK | Modern standard, protobuf, scalable UI | Should be AppleTrace's visualization target |

**Differentiation**: AppleTrace's edge is being lightweight, embeddable directly
in an app (manual sections), and producing shareable artifacts. The roadmap
should lean into that rather than chasing Frida's full feature set.

## 4. Phased Plan

### Phase 1 — Modernize visualization (low risk, high value)
- ✅ Document Perfetto (`ui.perfetto.dev`) as the default viewer in README.
- ✅ Add a `thread_name` metadata event so threads are labeled.
- ✅ Stream `merge.py` output.
- ✅ Collapse begin/end pairs into `X` complete events (`merge.py --complete`),
  roughly halving section-event count.

### Phase 2 — Hot-path performance
- ✅ Introduce `(Class, SEL)` name interning.
- ✅ Use a zero-allocation per-thread call stack (no per-message `malloc`).
- Move event recording to per-thread ring buffers with bulk background flushing.
- Defer JSON formatting to the exporter; emit binary events at runtime.

### Phase 3 — Expressiveness & control
- ✅ Add `APTInstant` and `APTCounter` event APIs.
- ✅ Add runtime class-prefix allow/deny lists.
- Add async/flow events to track work across dispatch queues.

### Phase 4 — Reach & polish
- ✅ Add `CONTRIBUTING.md`.
- Clarify arm64-only constraints; explore x86_64-simulator support for CI.
- Explore an `os_signpost` backend and/or Perfetto protobuf export.
