#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$(mktemp -d /tmp/appletrace-arm64e-derived.XXXXXX)"

cleanup() {
  rm -rf "${DERIVED_DATA_DIR}"
}
trap cleanup EXIT

cd "${ROOT_DIR}"

echo "[1/9] Swift package tests"
swift test

echo "[2/9] Python exporter tests"
python3 -m unittest discover -s Tests -p 'test_*.py'

echo "[3/9] Text and binary writer stress test"
./scripts/test_batching_stress.sh

echo "[4/9] Embedded Web Console"
./scripts/build_web_console.sh

echo "[5/9] Jailbreak Agent/daemon protocol"
./scripts/test_jailbreak_ipc.sh

echo "[6/9] Standard simulator hook scenario"
./scripts/test_objc_msgsend_hook.sh

echo "[7/9] Experimental simulator ABI and late-image scenario"
./scripts/test_objc_msgsend_hook_experimental.sh

echo "[8/9] iOS arm64e compile and slice inspection"
xcodebuild \
  -project sample/TraceAllMsgDemo/TraceAllMsgDemo.xcodeproj \
  -scheme TraceAllMsgDemo \
  -configuration Debug \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  ARCHS=arm64e \
  "VALID_ARCHS=arm64 arm64e" \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_BINARY="${DERIVED_DATA_DIR}/Build/Products/Debug-iphoneos/TraceAllMsgDemo.app/TraceAllMsgDemo"
FRAMEWORK_BINARY="${DERIVED_DATA_DIR}/Build/Products/Debug-iphoneos/TraceAllMsgDemo.app/Frameworks/appletrace.framework/appletrace"
[[ "$(lipo -archs "${APP_BINARY}")" == "arm64e" ]]
[[ "$(lipo -archs "${FRAMEWORK_BINARY}")" == "arm64e" ]]

echo "[9/9] AppleTraceServer iOS cross-build"
swift build --triple arm64-apple-ios15.0 --target AppleTraceServer

if [[ "${RUN_THEOS_PACKAGE_TESTS:-0}" == "1" ]]; then
  if [[ -z "${THEOS:-}" || ! -d "${THEOS}" ]]; then
    echo "RUN_THEOS_PACKAGE_TESTS=1 requires THEOS to name an installed Theos checkout." >&2
    exit 1
  fi
  echo "[extra] Rootless and rootful Theos packages"
  make -C Jailbreak clean package THEOS_PACKAGE_SCHEME=rootless
  make -C Jailbreak clean package THEOS_PACKAGE_SCHEME=
fi

echo "All checks available without a physical device passed."
