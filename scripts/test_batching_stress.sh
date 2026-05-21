#!/usr/bin/env bash
#
# Stress test for the per-thread batched trace writer (macOS host build).
#
# Compiles appletrace.mm together with tests/stress/stress_main.mm, runs a
# multi-threaded workload in both the text and binary (APPLETRACE_BINARY=1)
# output modes, then merges each run and asserts that no events were lost or
# duplicated across threads / flush / thread-exit.
#
# This builds for the host (no Xcode project, no simulator), so it is fast and
# independent of the simulator smoke tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/appletrace/appletrace/src"
WORK_DIR="$(mktemp -d)"
BIN_PATH="${WORK_DIR}/appletrace_stress"

cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

echo "[build] Compiling stress harness"
clang++ -std=gnu++11 -fobjc-arc -O2 \
  -I "${SRC_DIR}" \
  -framework Foundation \
  "${SRC_DIR}/appletrace.mm" \
  "${ROOT_DIR}/tests/stress/stress_main.mm" \
  -o "${BIN_PATH}"

run_mode() {
  local label="$1"
  shift  # remaining args are extra environment assignments
  local data_dir="${WORK_DIR}/${label}"

  echo "[${label}] Running stress harness"
  local output
  output="$(APPLETRACE_DATA_DIR="${data_dir}" "$@" "${BIN_PATH}")"
  local expected
  expected="$(printf '%s\n' "${output}" | sed -n 's/^EXPECTED_STRESS_PAIRS=//p')"
  if [[ -z "${expected}" ]]; then
    echo "[${label}] harness did not report an expected count" >&2
    exit 1
  fi

  echo "[${label}] Merging and verifying (${expected} expected pairs)"
  python3 "${ROOT_DIR}/merge.py" -d "${data_dir}" >/dev/null
  python3 - "${data_dir}/trace.json" "${expected}" "${label}" <<'PY'
import json
import sys

events = json.load(open(sys.argv[1]))
expected = int(sys.argv[2])
label = sys.argv[3]
got = sum(1 for event in events if event.get("ph") == "X" and event.get("name") == "stress")
print(f"[{label}] stress complete events: {got} / expected {expected}")
if got != expected:
    raise SystemExit(f"[{label}] MISMATCH: events lost or duplicated ({got} != {expected})")
print(f"[{label}] OK: no events lost or duplicated")
PY
}

run_mode text
run_mode binary env APPLETRACE_BINARY=1

echo "batching stress test passed (text + binary)"
