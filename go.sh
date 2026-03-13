#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: sh go.sh <path to appletracedata directory>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRACE_DIR="$1"

echo "AppleTrace export starting"
echo "trace dir: $TRACE_DIR"

python3 "$SCRIPT_DIR/scripts/appletrace_cli.py" all "$TRACE_DIR" --open

echo "AppleTrace export finished"
