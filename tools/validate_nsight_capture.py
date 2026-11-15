#!/usr/bin/env python3
"""Fail closed unless an application-bounded Nsight trace covers its workload."""

import csv
import json
from pathlib import Path
import re
import sys


def validate(directory: Path, token: str, max_duration_ms: int) -> dict:
    receipt = json.loads((directory / "workload-complete.json").read_text())
    if receipt.get("schema") != "lanius.nsight-workload.v1":
        raise ValueError("missing workload completion contract")
    if receipt.get("token") != token or receipt.get("complete") is not True:
        raise ValueError("missing or stale workload completion")
    if receipt.get("sdk_start") != 0 or receipt.get("sdk_stop") != 0:
        raise ValueError("SDK did not start and stop successfully")
    elapsed = receipt.get("capture_elapsed_ms")
    if not isinstance(elapsed, (int, float)) or not 0 < elapsed < max_duration_ms:
        raise ValueError("workload reached the capture duration limit")

    log = (directory / "nsight.log").read_text(errors="replace")
    if re.search(r"TARGET (?:WARNING|ERROR)|(?:timestamp|event|buffer) overflow|"
                 r"missing some data|(?:events|data|timestamps) (?:were )?dropped|"
                 r"trace truncated|buffer.*(?:too small|exhausted|is full)", log, re.I):
        raise ValueError("Nsight reported lost trace data; increase capacity and recapture")
    if "Succeeded to export data:" not in log:
        raise ValueError("Nsight did not finish exporting")
    exports = list(directory.glob("*/D3DPERF_EVENTS.xls"))
    if len(exports) != 1:
        raise ValueError("expected exactly one exported trace")
    with exports[0].with_name("REPRO_INFO.xls").open(newline="") as stream:
        info = {row[0].strip(): row[1].strip() for row in csv.reader(stream, delimiter="\t") if len(row) >= 2}
    if info.get("Start After") != "NGFX SDK Controlled" or info.get("Limited To") != "NGFX SDK Controlled":
        raise ValueError("export was not bounded by SDK start and stop")
    with exports[0].open(newline="") as stream:
        rows = list(csv.reader(stream, delimiter="\t"))[1:]
    names = [row[0].strip() for row in rows if row]
    begin, end = (f"lanius.capture.{token}.{part}" for part in ("begin", "end"))
    if names.count(begin) != 1 or names.count(end) != 1:
        raise ValueError("trace is missing unique workload begin/end GPU markers")
    first, last = names.index(begin), names.index(end)
    if first >= last:
        raise ValueError("workload markers are reversed")
    # Markers are isolated submissions on the workload queue. Extra labels
    # imply a second workload or warmup leaked into the selected capture.
    if first != 0 or last != len(names) - 1:
        raise ValueError("trace contains labeled work outside the workload boundary")
    if last == first + 1:
        raise ValueError("trace contains no labeled workload")
    return {
        "schema": "lanius.nsight-coverage.v1",
        "complete": True,
        "token": token,
        "capture_elapsed_ms": elapsed,
        "labeled_events": last - first - 1,
        "export": str(exports[0].parent),
        "workload": receipt,
    }


def main() -> int:
    directory, token, duration = sys.argv[1:]
    directory = Path(directory)
    coverage = directory / "coverage.json"
    coverage.unlink(missing_ok=True)
    try:
        result = validate(directory, token, int(duration))
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"INCOMPLETE Nsight capture: {error}", file=sys.stderr)
        return 1
    coverage.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Complete workload capture verified: {coverage}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
