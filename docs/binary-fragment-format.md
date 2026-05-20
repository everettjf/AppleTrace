# AppleTrace Binary Fragment Format

Status: format locked; **exporter implemented and tested**
(`appletrace_binary.py`, wired into `merge.py`). The native runtime writer is
the next step — see "Runtime producer" below. This is the follow-on to the
per-thread batching work in [perf-batching-design.md](perf-batching-design.md).

## Why

The text format writes one JSON line per event, so every event pays for string
formatting on (or near) the hot path. The binary format keeps formatting off the
hot path entirely: each unique event name is interned once, and events are
fixed-layout records that reference a name by id. The exporter (`merge.py`)
decodes fragments back into the exact Chrome/Perfetto JSON it already produces,
so Perfetto/visualization is unchanged.

## Layout (little-endian)

```
header:
    magic   : 8 bytes  = "APLTRC01"
    pid     : uint32

records (repeated until 0x00 tag or EOF):
    0x00            end / zero padding  -> stop decoding
    0x01            string definition   -> name_id:uint32  len:uint32  utf8[len]
    <ASCII phase>   event               -> name_id:uint32  tid:uint64  ts:uint64  arg:uint64
```

- A string definition assigns `name_id -> string`. The producer emits it the
  first time a name is used; later events reference the id. Decoders build the
  table in stream order, so fragments are self-contained.
- `pid` is constant per fragment (per process) and is injected into every
  decoded event.
- `ts` is microseconds since trace start (ignored for `M`).

### Phase tags and `arg`

| phase | meaning            | `arg`                              | decoded JSON extras            |
|-------|--------------------|------------------------------------|--------------------------------|
| `B`   | section begin      | 0                                  | `cat`, `ts`                    |
| `E`   | section end        | 0                                  | `cat`, `ts`                    |
| `i`   | instant            | 0                                  | `cat`, `ts`, `s:"t"`           |
| `C`   | counter            | IEEE-754 double bits of the value  | `cat`, `ts`, `args.value`      |
| `b`   | async begin        | async id                           | `cat`, `ts`, `id`              |
| `e`   | async end          | async id                           | `cat`, `ts`, `id`              |
| `M`   | metadata           | name_id of the value string        | `args.name` (no `cat`/`ts`)    |

Counter values are decoded as an integer when integral (e.g. `60`), else a
float (e.g. `142.5`), matching the text producer.

## Robustness

- Decoding stops at a `0x00` tag, so zero padding left by a crashed process
  (an mmap region not truncated on clean close) is tolerated, exactly like the
  text path's trailing-garbage handling.
- Truncated records at EOF stop decoding instead of raising.
- An event referencing an undefined `name_id` is a hard error (corruption).

## Exporter integration

- `appletrace_binary.py` provides `MAGIC`, `is_binary_fragment(bytes)`,
  `decode(bytes)`, and an `Encoder` (reference producer, used by tests).
- `merge.py` discovers `trace[_N].appletrace` (text) and
  `trace[_N].appletracebin` (binary) fragments, detects each file by magic, and
  decodes accordingly. Both feed the same `X`-complete-event collapsing.

## Runtime producer (next step)

The native writer (`appletrace.mm`) would, behind an opt-in
`APPLETRACE_BINARY=1` flag:

- Append fixed-layout records to the per-thread batch buffer (already byte
  buffers after the batching change) instead of JSON text.
- Maintain a process-wide `(string -> name_id)` interning table; emit a string
  definition the first time an id is used. The `objc_msgSend` hook already
  interns `(Class, SEL)` names, so the two tables can share.
- Name fragments `trace[_N].appletracebin` so the exporter auto-detects them.

Keeping it opt-in preserves the text path (and the existing smoke-test
assertions) until the binary path is validated on device.
