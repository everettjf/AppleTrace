#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT_DIR/scripts/appletrace_cli.py" all "$ROOT_DIR/sampledata" --open
