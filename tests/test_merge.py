from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from merge import list_trace_files, merge_trace_directory


class MergeTraceDirectoryTests(unittest.TestCase):
    def test_trace_files_are_sorted_by_numeric_suffix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for name in ["trace_10.appletrace", "trace.appletrace", "trace_2.appletrace"]:
                (directory / name).write_text("", encoding="utf-8")

            files = list_trace_files(directory)
            self.assertEqual(
                [path.name for path in files],
                ["trace.appletrace", "trace_2.appletrace", "trace_10.appletrace"],
            )

    def test_merge_writes_valid_json_array(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "trace.appletrace").write_text(
                '\n'.join(
                    [
                        '{"name":"A","ph":"B","pid":1,"tid":0,"ts":1}',
                        '{"name":"A","ph":"E","pid":1,"tid":0,"ts":2}',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            (directory / "trace_1.appletrace").write_text(
                '{"name":"B","ph":"B","pid":1,"tid":1,"ts":3}\n',
                encoding="utf-8",
            )

            output = merge_trace_directory(directory)
            merged = json.loads(output.read_text(encoding="utf-8"))

            self.assertEqual([event["name"] for event in merged], ["A", "A", "B"])

    def test_merge_stops_on_non_json_tail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "trace.appletrace").write_text(
                '{"name":"A","ph":"B","pid":1,"tid":0,"ts":1}\ntrailer\n',
                encoding="utf-8",
            )

            output = merge_trace_directory(directory)
            merged = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(len(merged), 1)

    def test_merge_raises_on_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "trace.appletrace").write_text(
                '{"name":"A","ph":"B","pid":1,"tid":0,"ts":1\n',
                encoding="utf-8",
            )

            with self.assertRaises(ValueError):
                merge_trace_directory(directory)


if __name__ == "__main__":
    unittest.main()
