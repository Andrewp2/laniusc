#!/usr/bin/env python3
"""Report each kernel's measured per-thread local memory next to its declared arrays.

The NVIDIA driver reserves local (scratch) memory for the whole device: the
largest per-thread local memory of any created pipeline times the resident
threads. The reservation is sized when a pipeline is created and never
shrinks. `shader_dispatch_replay --memory-probe` creates each kernel on a
fresh device and records how much device memory the creation added, which
is that kernel's own reservation: its declared arrays plus register spills
and, in the DontInline test harness, call frames.

usage:
  tools/local_memory_report.py --run [--artifacts DIR] [--out REPORT.md]
      Runs the probe (GPU: run it through the heavy lock) and writes the report.
  tools/local_memory_report.py --probe PROBE.jsonl [--artifacts DIR] [--out REPORT.md]
      Writes the report from an earlier probe's output.

Per-thread bytes are estimated as (added MiB - baseline) / resident threads,
where the baseline is the median addition of kernels that declare no arrays
(pipeline code and bookkeeping) and resident threads default to an RTX 3070
laptop's 40 SMs x 1536 threads.
"""

import argparse
import json
import statistics
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ARTIFACTS = ROOT / "target/laniusc-shader-artifacts/release/shaders"
DEFAULT_OUT = ROOT / "target/claude-work/reports/local_memory_measured.md"
TARGET_BYTES = 1024
LIMIT_BYTES = 16 * 1024


def declared_array_bytes(path):
    """Bytes of Function/Private-storage variables with array-containing types."""
    data = path.read_bytes()
    words = struct.unpack("<%dI" % (len(data) // 4), data)
    if not words or words[0] != 0x07230203:
        return 0
    consts, sizes, has_array, pointers = {}, {}, {}, {}
    total = 0
    at = 5
    while at < len(words):
        count, op = words[at] >> 16, words[at] & 0xFFFF
        ops = words[at + 1 : at + count]
        if op in (21, 22):  # OpTypeInt, OpTypeFloat
            sizes[ops[0]] = ops[1] // 8
        elif op == 20:  # OpTypeBool
            sizes[ops[0]] = 4
        elif op == 23:  # OpTypeVector
            sizes[ops[0]] = sizes.get(ops[1], 4) * ops[2]
        elif op == 43:  # OpConstant
            consts[ops[1]] = ops[2]
        elif op == 28:  # OpTypeArray
            sizes[ops[0]] = sizes.get(ops[1], 4) * consts.get(ops[2], 0)
            has_array[ops[0]] = True
        elif op == 30:  # OpTypeStruct
            sizes[ops[0]] = sum(sizes.get(member, 4) for member in ops[1:])
            has_array[ops[0]] = any(has_array.get(member, False) for member in ops[1:])
        elif op == 32:  # OpTypePointer
            pointers[ops[0]] = (ops[1], ops[2])
        elif op == 59:  # OpVariable
            storage, pointee = pointers.get(ops[0], (None, None))
            if storage in (6, 7) and has_array.get(pointee, False):
                total += sizes.get(pointee, 0)
        at += max(count, 1)
    return total


def inlined_sizes(artifacts):
    """Fully inlined instruction counts from the build's report, by kernel."""
    report = artifacts.parent / "inlined_sizes.txt"
    sizes = {}
    if report.exists():
        for line in report.read_text().splitlines():
            parts = line.split()
            if len(parts) == 4 and parts[0].isdigit():
                sizes[parts[3]] = int(parts[0])
    return sizes


def run_probe(artifacts, output):
    binary = ROOT / "target/release/shader_dispatch_replay"
    with output.open("w") as sink:
        subprocess.run([str(binary), "--memory-probe", str(artifacts)], stdout=sink, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--run", action="store_true", help="run the GPU probe first")
    source.add_argument("--probe", type=Path, help="probe output (JSON lines)")
    parser.add_argument("--artifacts", type=Path, default=DEFAULT_ARTIFACTS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--resident-threads", type=int, default=40 * 1536)
    parser.add_argument("--noinline-min", type=int, default=100_000,
                        help="fully inlined size from which the test harness marks DontInline")
    args = parser.parse_args()

    probe = args.probe
    if args.run:
        probe = args.out.with_suffix(".jsonl")
        probe.parent.mkdir(parents=True, exist_ok=True)
        run_probe(args.artifacts, probe)
    header, rows = {}, []
    for line in probe.read_text().splitlines():
        record = json.loads(line)
        if "kernel" in record:
            rows.append(record)
        else:
            header = record
    if header.get("shared_device"):
        sys.exit("the probe ran on one shared device; per-kernel figures need fresh devices")

    sizes = inlined_sizes(args.artifacts)
    for row in rows:
        row["declared"] = declared_array_bytes(args.artifacts / f"{row['kernel']}.spv")
        row["inlined"] = sizes.get(row["kernel"])
    plain = [row["added_mib"] for row in rows if row["created"] and row["declared"] == 0]
    baseline = statistics.median(plain) if plain else 0
    for row in rows:
        excess = max(0, row["added_mib"] - baseline)
        row["per_thread"] = excess * (1 << 20) // args.resident_threads

    rows.sort(key=lambda row: (-row["per_thread"], row["kernel"]))
    measured = [row for row in rows if row["created"]]
    worst = measured[0] if measured else None
    over_target = [row for row in measured if row["per_thread"] > TARGET_BYTES]
    over_limit = [row for row in measured if row["per_thread"] > LIMIT_BYTES]
    lines = [
        "# Measured per-thread local memory",
        "",
        f"Generated by `tools/local_memory_report.py` from `{probe}` for `{args.artifacts}`.",
        "",
        "The driver reserves local memory for the whole process: the largest per-thread",
        "figure below times the resident threads. The reservation is sized at pipeline",
        "creation and never shrinks. *Measured* is the driver's figure for that kernel",
        "(declared arrays + register spills + DontInline call frames), estimated as",
        f"(added MiB - {baseline} MiB baseline) / {args.resident_threads} resident threads.",
        "*Declared* sums the kernel's Function/Private-storage array variables over",
        "all of its SPIR-V functions. *DontInline* marks kernels the test harness",
        f"builds with out-of-line calls (fully inlined size >= {args.noinline_min:,}).",
        "",
        f"- kernels probed: {len(measured)}",
        f"- reservation implied by the worst kernel: "
        + (f"{worst['added_mib']} MiB (`{worst['kernel']}`)" if worst else "n/a"),
        f"- over the {TARGET_BYTES} B target: {len(over_target)}; over the {LIMIT_BYTES // 1024} KB limit: {len(over_limit)}",
        "",
        "| measured B/thread | added MiB | declared B | DontInline | inlined | kernel |",
        "|---:|---:|---:|:---:|---:|---|",
    ]
    for row in measured:
        if row["per_thread"] <= 0 and row["declared"] == 0:
            continue
        inlined = row["inlined"]
        dont_inline = "yes" if inlined is not None and inlined >= args.noinline_min else ""
        inlined_text = f"{inlined:,}" if inlined is not None else "?"
        lines.append(
            f"| {row['per_thread']:,} | {row['added_mib']} | {row['declared']:,} | {dont_inline} | "
            f"{inlined_text} | `{row['kernel']}` |"
        )
    zero = sum(1 for row in measured if row["per_thread"] <= 0 and row["declared"] == 0)
    lines += ["", f"{zero} kernels declare no arrays and measure no local memory above the baseline (not listed)."]
    failed = [row["kernel"] for row in rows if not row["created"]]
    if failed:
        lines += ["", "Not created (no compute entry): " + ", ".join(f"`{k}`" for k in failed)]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n")
    print(f"wrote {args.out}: {len(measured)} kernels, worst {worst['per_thread'] if worst else 0} B/thread, "
          f"{len(over_target)} over {TARGET_BYTES} B")


if __name__ == "__main__":
    main()
