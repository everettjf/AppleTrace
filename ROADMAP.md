# AppleTrace Optimization & Roadmap

> Status: AppleTrace is in maintenance mode. This document captures concrete
> optimization opportunities, a competitive comparison, and a phased plan so
> that future work (or a successor project) has a clear technical baseline.

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

- Support `X` (complete) events to roughly halve file size vs. paired `B`/`E`.
- Emit `thread_name` metadata events (today only `process_name` is written,
  `appletrace.mm:367`), so threads are labeled in Perfetto/Chrome.
- Add **counter** events (memory, FPS), **instant** markers, and **async/flow**
  events to track work across dispatch queues — the most useful profiling axes.
- Stream `merge.py` output instead of `list()`-ing all events in memory
  (`merge.py:73`) so large captures don't exhaust RAM.

### 2.4 Filtering & control

- Add runtime class-prefix allow/deny lists. The existing range-based filter is
  effectively dead because `gLogAllSelectors`/`gLogAllClasses` default to `YES`
  (`hook_objc_msgSend.m:308`).
- Add a sampling mode (trace 1/N sends) to bound overhead on hot apps.

### 2.5 Housekeeping

- README references a `CONTRIBUTING.md` that does not exist — add it or drop the
  link.
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
- Document Perfetto (`ui.perfetto.dev`) as the default viewer in README/AGENT.
- Add a `thread_name` metadata event and emit `X` complete events.
- Stream `merge.py` output.

### Phase 2 — Hot-path performance
- Introduce `(Class, SEL)` name interning.
- Move to per-thread ring buffers with bulk background flushing.
- Defer JSON formatting to the exporter; emit binary events at runtime.

### Phase 3 — Expressiveness & control
- Add counter / instant / async-flow event APIs.
- Add runtime class-prefix allow/deny lists and a sampling mode.

### Phase 4 — Reach & polish
- Add `CONTRIBUTING.md`; clarify arm64-only constraints.
- Explore an `os_signpost` backend and/or Perfetto protobuf export.
- Evaluate x86_64-simulator support to broaden CI coverage.
