#!/usr/bin/env python3
"""Merge AppleTrace raw trace fragments into a Chrome trace JSON array."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Iterable, List


TRACE_FILE_RE = re.compile(r"^trace(?:_(\d+))?\.appletrace$")


def list_trace_files(directory: Path) -> List[Path]:
    """Return trace fragments sorted by their numeric suffix."""
    trace_files = []
    for path in directory.iterdir():
        if not path.is_file():
            continue

        match = TRACE_FILE_RE.match(path.name)
        if not match:
            continue

        suffix = int(match.group(1) or 0)
        trace_files.append((suffix, path))

    return [path for _, path in sorted(trace_files, key=lambda item: item[0])]


def iter_events(trace_files: Iterable[Path]) -> Iterable[dict]:
    """Yield valid JSON events from AppleTrace fragment files."""
    for file_path in trace_files:
        print(file_path)
        with file_path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                raw_line = line.strip()
                if not raw_line:
                    continue

                if not raw_line.startswith("{"):
                    break

                try:
                    event = json.loads(raw_line)
                except json.JSONDecodeError as exc:
                    raise ValueError(
                        f"Invalid JSON in {file_path}:{line_number}: {exc.msg}"
                    ) from exc

                if not isinstance(event, dict):
                    raise ValueError(
                        f"Unexpected non-object event in {file_path}:{line_number}"
                    )

                yield event


def merge_trace_directory(directory: Path, output_path: Path | None = None) -> Path:
    """Merge all trace fragments under a directory into `trace.json`."""
    if not directory.exists():
        raise FileNotFoundError(f"Trace directory does not exist: {directory}")
    if not directory.is_dir():
        raise NotADirectoryError(f"Trace path is not a directory: {directory}")

    trace_files = list_trace_files(directory)
    if not trace_files:
        raise FileNotFoundError(f"No trace fragments found in {directory}")

    target = output_path or directory / "trace.json"
    with target.open("w", encoding="utf-8") as handle:
        handle.write("[")
        first = True
        for event in iter_events(trace_files):
            if not first:
                handle.write(",")
            handle.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
            first = False
        handle.write("]\n")

    return target


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Merge AppleTrace .appletrace fragments into trace.json."
    )
    parser.add_argument(
        "-d",
        "--dir",
        dest="directory",
        required=True,
        help="Directory containing trace.appletrace fragments.",
    )
    parser.add_argument(
        "-o",
        "--output",
        dest="output",
        help="Optional output JSON path. Defaults to <dir>/trace.json.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    directory = Path(args.directory).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve() if args.output else None

    try:
        merged_path = merge_trace_directory(directory, output_path)
    except (FileNotFoundError, NotADirectoryError, ValueError) as exc:
        print(f"error: {exc}")
        return 1

    print(f"Wrote merged trace to {merged_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
