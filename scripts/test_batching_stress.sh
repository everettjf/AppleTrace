#!/usr/bin/env bash
#
# Stress test for the per-thread batched trace writer (macOS host build).
#
# Compiles appletrace.mm together with tests/stress/stress_main.mm, runs a
# multi-threaded workload, then merges the output and asserts that no events
# were lost or duplicated across threads / flush / thread-exit.
#
# This builds for the host (no Xcode project, no simulator), so it is fast and
# independent of the simulator smoke tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/appletrace/appletrace/src"
WORK_DIR="$(mktemp -d)"
DATA_DIR="${WORK_DIR}/appletracedata"
BIN_PATH="${WORK_DIR}/appletrace_stress"

cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

echo "[1/4] Building stress harness"
clang++ -std=gnu++11 -fobjc-arc -O2 \
  -I "${SRC_DIR}" \
  -framework Foundation \
  "${SRC_DIR}/appletrace.mm" \
  "${ROOT_DIR}/tests/stress/stress_main.mm" \
  -o "${BIN_PATH}"

echo "[2/4] Running stress harness"
HARNESS_OUTPUT="$(APPLETRACE_DATA_DIR="${DATA_DIR}" "${BIN_PATH}")"
EXPECTED="$(printf '%s\n' "${HARNESS_OUTPUT}" | sed -n 's/^EXPECTED_STRESS_PAIRS=//p')"
if [[ -z "${EXPECTED}" ]]; then
  echo "Harness did not report an expected count" >&2
  exit 1
fi
echo "expected stress pairs: ${EXPECTED}"

echo "[3/4] Merging trace fragments"
python3 "${ROOT_DIR}/merge.py" -d "${DATA_DIR}"

echo "[4/4] Verifying event count"
python3 - "${DATA_DIR}/trace.json" "${EXPECTED}" <<'PY'
import json
import sys

events = json.load(open(sys.argv[1]))
expected = int(sys.argv[2])
got = sum(1 for event in events if event.get("ph") == "X" and event.get("name") == "stress")
print(f"stress complete events: {got} / expected {expected}")
if got != expected:
    raise SystemExit(f"MISMATCH: events lost or duplicated ({got} != {expected})")
print("OK: no events lost or duplicated")
PY

echo "batching stress test passed"
