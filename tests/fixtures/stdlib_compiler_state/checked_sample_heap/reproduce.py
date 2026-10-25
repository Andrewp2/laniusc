"""Compile one preserved context against the exact pre-correction heap source."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CASES = {"minimal_heap_view", "minimal_view_builder", "minimal_vec_sort_control",
         "nested_view_builder", "typed_view_builder", "legacy_transfer_control",
         "heap_view_builder", "drain_builder_control"}
case = sys.argv[1] if len(sys.argv) == 2 else "minimal_heap_view"
if case not in CASES:
    raise SystemExit("unknown preserved context")
with tempfile.TemporaryDirectory(prefix="heap-view-history-", dir=ROOT / "target/stdlib-work") as folder:
    work = Path(folder)
    shutil.copytree(ROOT / "stdlib", work / "stdlib")
    shutil.copyfile(HERE / "binary_heap_before_view_correction.lani", work / "stdlib/alloc/binary_heap.lani")
    result = subprocess.run([
        "timeout", "--kill-after=2s", "100s", "flock", "-E", "75", "-w", "35",
        str(ROOT / "target/stdlib-work/library-gpu.lock"), "timeout", "--kill-after=2s", "60s",
        str(ROOT / "target/stdlib-build/debug/laniusc"), "--stdlib-root", str(work / "stdlib"),
        "--emit", "x86_64", str(HERE / (case + ".lani")), "-o", str(work / "case"),
    ], capture_output=True, timeout=103)
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    if result.returncode == 0:
        data = b"" if case.startswith("minimal_") else b"3\n-1\n42\n42\n7\n"
        executed = subprocess.run([str(work / "case")], input=data, capture_output=True, timeout=10)
        sys.stdout.buffer.write(executed.stdout)
        sys.stderr.buffer.write(executed.stderr)
        raise SystemExit(executed.returncode)
    raise SystemExit(result.returncode)
