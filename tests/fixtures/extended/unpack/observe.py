"""One bounded native unpack runtime observation; compilation is external.

This tool measures one untraced child invocation, including startup, archive
input, extraction, file/directory sync, cleanup and report output. Archive
construction and independent content/tree validation are outside that interval.
It is not a compiler-speed, GPU-kernel, comparative or throughput benchmark.

CPU only:
    python3 -B observe.py controls
Native, run only by the root gate owner:
    python3 -B observe.py /absolute/accepted-unpack
"""
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("unpack_observation_helpers", HERE / "oracle.py")
ORACLE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ORACLE)

EXPECTED_ELF_SHA256 = "6599f840ce7030d80a1913c628329668e4c86f59f61366bfd08cf54d2838b22a"
SMALL_FILES = 256
SMALL_BYTES = 128
DIRECTORIES = 16
BULK_BYTES = 2 * 1024 * 1024
CHILD_SECONDS = 45
WHOLE_SECONDS = 60
CAPS = {
    "input-bytes": 1048576, "input-reads": 2048,
    "entries": 512, "nodes": 1024, "depth": 8,
    "path-bytes": 255, "component-bytes": 64, "path-storage-bytes": 262144,
    "entry-bytes": 2097152, "decoded-bytes": 4194304,
    "plan-work": 16777216, "zip-work": 16777216, "metadata-work": 16777216,
    "source-owned-bytes": 4194304, "run-owned-bytes": 16777216,
    "program-owned-bytes": 33554432,
    "host-calls": 131072, "cleanup-calls": 4096,
    "write-calls": 8192, "sync-calls": 4096, "entropy-calls": 2048,
    "name-attempts": 1024, "steps": 262144,
    "report-bytes": 1048576, "report-writes": 4096,
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def workload():
    entries = [ORACLE.member(f"group-{index:02d}/".encode(), directory=True)
               for index in range(DIRECTORIES)]
    for index in range(SMALL_FILES):
        data = bytes((index * 17 + offset * 29) & 255 for offset in range(SMALL_BYTES))
        name = f"group-{index % DIRECTORIES:02d}/small-{index:03d}.bin".encode()
        entries.append(ORACLE.member(name, data))
    block = b"unpack observation repeated binary block\n\0\xff"
    bulk = (block * ((BULK_BYTES + len(block) - 1) // len(block)))[:BULK_BYTES]
    entries.append(ORACLE.member(b"bulk.bin", bulk, method=8))
    data = ORACLE.archive(entries, "zip")
    assert len(entries) == DIRECTORIES + SMALL_FILES + 1
    assert len(data) <= CAPS["input-bytes"]
    assert sum(len(entry["data"]) for entry in entries) == SMALL_FILES * SMALL_BYTES + BULK_BYTES
    return entries, data


def check_archive(entries, data):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        assert len(archive.infolist()) == len(entries)
        assert archive.testzip() is None
        for expected, actual in zip(entries, archive.infolist()):
            assert actual.filename.encode("ascii") == expected["name"]
            assert archive.read(actual) == expected["data"]
        bulk = archive.getinfo("bulk.bin")
        assert bulk.compress_type == zipfile.ZIP_DEFLATED and bulk.file_size == BULK_BYTES
        assert bulk.compress_size < bulk.file_size // 20
    return ORACLE.expected(entries)


def validate(root, stdout, stderr, entries, expected):
    assert not stderr, stderr
    assert ORACLE.tree(root) == expected, "extracted namespace/content/modes differ"
    rows = ORACLE.report(stdout)
    result = dict(rows=rows)
    summary = ORACLE.one(result, "unpack")
    assert summary["code"] == "0" and summary["state"] == "2", summary
    assert int(summary["entries"]) == int(summary["entries_completed"]) == len(entries), summary
    assert int(summary["published_files"]) == SMALL_FILES + 1, summary
    assert int(summary["created_directories"]) == DIRECTORIES, summary
    assert int(summary["bytes"]) == SMALL_FILES * SMALL_BYTES + BULK_BYTES, summary
    assert summary["resources_remaining"] == summary["cleanup_errors"] == "0", summary
    assert ORACLE.one(result, "release") == {"destroyed": "1", "resources_remaining": "0"}
    nodes = [row for kind, row in rows if kind == "node"]
    assert len(nodes) == len(expected) and len({row["path_hex"] for row in nodes}) == len(nodes)
    assert {bytes.fromhex(row["path_hex"]) for row in nodes} == set(expected)
    for row in nodes:
        assert row["status_available"] == "1", row
        if row["kind"] == "1":
            assert row["published"] == row["file_synced"] == row["directory_synced"] == "1", row
            assert row["visibility"] == "1" and row["temporary_owned"] == row["retained"] == "0", row
    return summary


def controls():
    entries, data = workload()
    expected = check_archive(entries, data)
    assert len(expected) == len(entries)
    assert len([item for item in expected.values() if item[0] == "dir"]) == DIRECTORIES
    assert len([item for item in expected.values() if item[0] == "file"]) == SMALL_FILES + 1
    assert set(CAPS) == set(ORACLE.LIMIT_FLAGS), "all requested caps must be explicit"
    assert CAPS["input-bytes"] + 16384 + max(CAPS["source-owned-bytes"], CAPS["run-owned-bytes"]) < CAPS["program-owned-bytes"]
    assert len(data) < CAPS["input-bytes"] and BULK_BYTES == CAPS["entry-bytes"]
    print(f"PASS unpack observation CPU archive-entries={len(entries)} archive-bytes={len(data)} "
          f"small-files={SMALL_FILES} small-bytes={SMALL_BYTES} bulk-bytes={BULK_BYTES} "
          f"decoded-bytes={SMALL_FILES * SMALL_BYTES + BULK_BYTES} archive-sha256={sha256(data)}")


def main(executable):
    started = time.perf_counter()
    entries, data = workload()
    expected = check_archive(entries, data)
    executable = Path(executable).resolve()
    assert sha256(executable.read_bytes()) == EXPECTED_ELF_SHA256, "requires the retained accepted ELF"
    directory = Path(tempfile.mkdtemp(prefix="unpack-observation-"))
    root = directory / "out"
    root.mkdir(mode=0o700)
    (directory / "archive.zip").write_bytes(data)
    command = [str(executable), "--format", "zip", "--root", "out"]
    for name, value in CAPS.items():
        command += ["--" + name, str(value)]
    command += ["--", "archive.zip"]
    requested = [
        "scope=one untraced native invocation; compilation/build/validation excluded",
        f"executable={executable}", f"elf-sha256={EXPECTED_ELF_SHA256}",
        f"archive-entries={len(entries)}", f"archive-bytes={len(data)}",
        f"archive-sha256={sha256(data)}",
        f"directories={DIRECTORIES}", f"small-files={SMALL_FILES}", f"small-file-bytes={SMALL_BYTES}",
        f"bulk-deflated-bytes={BULK_BYTES}", f"bulk-sha256={sha256(entries[-1]['data'])}",
        f"total-decoded-bytes={SMALL_FILES * SMALL_BYTES + BULK_BYTES}",
        f"subprocess-timeout-seconds={CHILD_SECONDS}", f"tool-timeout-seconds={WHOLE_SECONDS}",
        "caps=" + " ".join(f"--{key} {value}" for key, value in CAPS.items()),
        "command=" + repr(command),
    ]
    (directory / "request.txt").write_text("\n".join(requested) + "\n")
    try:
        remaining = WHOLE_SECONDS - 5 - (time.perf_counter() - started)
        assert remaining > 0, "fixture preparation exhausted bounded observation"
        before = time.perf_counter_ns()
        process = subprocess.run(command, cwd=directory, input=b"", capture_output=True,
                                 timeout=min(CHILD_SECONDS, remaining))
        elapsed_ns = time.perf_counter_ns() - before
        (directory / "stdout").write_bytes(process.stdout)
        (directory / "stderr").write_bytes(process.stderr)
        (directory / "status").write_text(str(process.returncode))
        assert process.returncode == 0, (process.returncode, process.stdout, process.stderr)
        assert len(process.stdout) + len(process.stderr) <= CAPS["report-bytes"]
        summary = validate(root, process.stdout, process.stderr, entries, expected)
        assert time.perf_counter() - started < WHOLE_SECONDS, "whole observation exceeded its bound"
        result = requested + [
            f"elapsed-seconds={elapsed_ns / 1000000000:.6f}",
            "validation=exact tree, content, modes, NodeStatus and successful cleanup",
            "cli-stats=" + " ".join(f"{key}={summary[key]}" for key in (
                "entries_completed", "published_files", "created_directories", "bytes",
                "writes", "syncs", "input_reads", "host_charged", "cleanup_reserved",
                "cleanup_charged", "steps", "owned_bytes", "peak_fds")),
            "interpretation=one correctness/resource/runtime observation; no comparative or compiler-speed claim",
        ]
        (directory / "observation.txt").write_text("\n".join(result) + "\n")
        print("PASS unpack observation " + " ".join((
            f"entries={len(entries)}", f"small-files={SMALL_FILES}",
            f"bulk-bytes={BULK_BYTES}", f"archive-bytes={len(data)}",
            f"decoded-bytes={SMALL_FILES * SMALL_BYTES + BULK_BYTES}",
            f"elapsed-seconds={elapsed_ns / 1000000000:.6f}", f"evidence={directory}")))
    except BaseException as error:
        if isinstance(error, subprocess.TimeoutExpired):
            (directory / "stdout").write_bytes(error.stdout or b"")
            (directory / "stderr").write_bytes(error.stderr or b"")
        (directory / "failure.txt").write_text(repr(error))
        raise AssertionError(f"unpack runtime observation evidence retained at {directory}: {error!r}") from error


if __name__ == "__main__":
    assert len(sys.argv) == 2, __doc__
    if sys.argv[1] == "controls":
        controls()
    else:
        main(sys.argv[1])
