#!/usr/bin/env python3
"""Convenience CLI for AppleTrace merge and HTML export workflows."""

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


def resolve_catapult(candidate: str | None) -> Path | None:
    if candidate:
        path = Path(candidate).expanduser().resolve()
        return path if path.exists() else None

    default_path = REPO_ROOT / "catapult" / "tracing" / "bin" / "trace2html"
    return default_path if default_path.exists() else None


def maybe_open(path: Path, should_open: bool) -> None:
    if not should_open:
        return
    if shutil.which("open") is None:
        return
    subprocess.run(["open", str(path)], check=False)


def cmd_merge(args: argparse.Namespace) -> int:
    output = Path(args.output).expanduser().resolve() if args.output else None
    merged = merge_trace_directory(Path(args.directory).expanduser().resolve(), output)
    print(merged)
    return 0


def cmd_html(args: argparse.Namespace) -> int:
    trace_json = Path(args.trace_json).expanduser().resolve()
    if not trace_json.exists():
        print(f"error: trace json does not exist: {trace_json}")
        return 1

    trace2html = resolve_catapult(args.catapult)
    if trace2html is None:
        print("error: trace2html not found. Run `sh get_catapult.sh` first.")
        return 1

    output = Path(args.output).expanduser().resolve() if args.output else trace_json.with_suffix(".html")
    command = [sys.executable, str(trace2html), str(trace_json), f"--output={output}"]
    print(" ".join(command))
    subprocess.run(command, check=True)
    print(output)
    maybe_open(output, args.open)
    return 0


def cmd_all(args: argparse.Namespace) -> int:
    directory = Path(args.directory).expanduser().resolve()
    merged = merge_trace_directory(directory)
    html_args = argparse.Namespace(
        trace_json=str(merged),
        output=args.output,
        catapult=args.catapult,
        open=args.open,
    )
    return cmd_html(html_args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AppleTrace utility CLI.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    merge_parser = subparsers.add_parser("merge", help="Merge .appletrace fragments.")
    merge_parser.add_argument("directory", help="Directory containing .appletrace files.")
    merge_parser.add_argument("-o", "--output", help="Output JSON path.")
    merge_parser.set_defaults(func=cmd_merge)

    html_parser = subparsers.add_parser("html", help="Generate HTML via Catapult trace2html.")
    html_parser.add_argument("trace_json", help="Path to trace.json.")
    html_parser.add_argument("-o", "--output", help="Output HTML path.")
    html_parser.add_argument("--catapult", help="Path to Catapult trace2html script.")
    html_parser.add_argument("--open", action="store_true", help="Open the generated HTML.")
    html_parser.set_defaults(func=cmd_html)

    all_parser = subparsers.add_parser("all", help="Merge traces and generate HTML.")
    all_parser.add_argument("directory", help="Directory containing .appletrace files.")
    all_parser.add_argument("-o", "--output", help="Output HTML path.")
    all_parser.add_argument("--catapult", help="Path to Catapult trace2html script.")
    all_parser.add_argument("--open", action="store_true", help="Open the generated HTML.")
    all_parser.set_defaults(func=cmd_all)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except subprocess.CalledProcessError as exc:
        print(f"error: command failed with exit code {exc.returncode}")
        return exc.returncode
    except Exception as exc:  # pragma: no cover - defensive CLI fallback
        print(f"error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
