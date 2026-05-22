#!/usr/bin/env python3
"""Convenience CLI for AppleTrace: merge fragments and open them in Perfetto."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from merge import merge_trace_directory

PERFETTO_URL = "https://ui.perfetto.dev"


def open_url(url: str) -> None:
    if shutil.which("open") is not None:
        subprocess.run(["open", url], check=False)


def print_perfetto_hint(trace_json: Path) -> None:
    print()
    print(f"Trace ready: {trace_json}")
    print(f"Open {PERFETTO_URL} and drag in the file above (or use 'Open trace file').")


def cmd_merge(args: argparse.Namespace) -> int:
    output = Path(args.output).expanduser().resolve() if args.output else None
    merged = merge_trace_directory(
        Path(args.directory).expanduser().resolve(), output, not args.raw
    )
    print(merged)
    return 0


def cmd_open(args: argparse.Namespace) -> int:
    output = Path(args.output).expanduser().resolve() if args.output else None
    merged = merge_trace_directory(
        Path(args.directory).expanduser().resolve(), output, not args.raw
    )
    print_perfetto_hint(merged)
    open_url(PERFETTO_URL)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AppleTrace utility CLI.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    merge_parser = subparsers.add_parser("merge", help="Merge .appletrace fragments into trace.json.")
    merge_parser.add_argument("directory", help="Directory containing .appletrace files.")
    merge_parser.add_argument("-o", "--output", help="Output JSON path.")
    merge_parser.add_argument(
        "--raw",
        action="store_true",
        help="Emit raw begin/end events instead of X complete events.",
    )
    merge_parser.set_defaults(func=cmd_merge)

    open_parser = subparsers.add_parser("open", help="Merge fragments and open the trace in Perfetto.")
    open_parser.add_argument("directory", help="Directory containing .appletrace files.")
    open_parser.add_argument("-o", "--output", help="Output JSON path.")
    open_parser.add_argument(
        "--raw",
        action="store_true",
        help="Emit raw begin/end events instead of X complete events.",
    )
    open_parser.set_defaults(func=cmd_open)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as exc:  # pragma: no cover - defensive CLI fallback
        print(f"error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
