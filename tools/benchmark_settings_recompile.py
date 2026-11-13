#!/usr/bin/env python3
"""Measure full native settings recompiles in one GPU-resident daemon.

Requires the settings source tree and its recorded resolver inventory (the
default is benchmark_artifacts/performance/ui-settings-main-20261113/imported-sources.tsv).
Inventory counts describe that recorded input list, not a fresh resolver audit.
All search-root files are hashed before and after the run. Frozen source trees
with .source-snapshot.json also have their archive manifest checked.

Every request clears compiled-unit and library-instance caches. GPU pipelines
and allocation capacity stay resident. The emitted ELF is checked but not run;
--edit-pairs changes only a disposable copy of the entry source. This workload
requires Linux x86-64 and its X11, Vulkan, font and accessibility libraries.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import signal
import statistics
import subprocess
import time


ENTRY = Path("sample_programs/library/ui_settings.lani")
SEARCH_ROOTS = ("stdlib", "extended", "sample_programs/library")
INVENTORY = Path("benchmark_artifacts/performance/ui-settings-main-20261113/imported-sources.tsv")
LIBRARIES = ["X11", "xcb", "harfbuzz", "freetype", "fontconfig", "pangoft2-1.0",
             "pango-1.0", "atk-1.0", "atk-bridge-2.0", "gobject-2.0", "glib-2.0",
             "dl", "pthread", "m"]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def manifest_digest(rows):
    return sha256(json.dumps(rows, sort_keys=True, separators=(",", ":")).encode())


def source_row(root, relative, lines=False):
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root) or Path(relative).is_absolute():
        raise ValueError(f"Source inventory path escapes --source-root: {relative}")
    data = path.read_bytes()
    row = dict(path=relative, bytes=len(data), sha256=sha256(data))
    if lines:
        row["physical_lines"] = len(data.splitlines())
    return row


def source_manifest(root, inventory=None):
    snapshot = root / ".source-snapshot.json"
    if snapshot.exists():
        metadata = json.loads(snapshot.read_text())
        files = [source_row(root, row["path"]) for row in metadata["files"]]
        paths = {p.relative_to(root).as_posix() for p in root.rglob("*")
                 if p.is_file() and p != snapshot}
        if files != metadata["files"] or paths != {row["path"] for row in files}:
            raise RuntimeError("Source snapshot differs from its archive manifest")
        if manifest_digest(files) != metadata["manifest_sha256"]:
            raise RuntimeError("Source snapshot manifest digest is inconsistent")
        used = [source_row(root, row["path"], lines=True)
                for row in metadata["used_source_files"]]
        if used != metadata["used_source_files"] or manifest_digest(used) != metadata["used_source_manifest_sha256"]:
            raise RuntimeError("Source snapshot differs from its recorded resolver inventory")
        commit = metadata.get("commit")
        authority = metadata.get("used_source_list_authority", str(snapshot))
    else:
        inventory = inventory or root / INVENTORY
        if not inventory.is_file():
            raise ValueError("No recorded resolver inventory; supply --source-inventory PATH")
        used = []
        for line in inventory.read_text().splitlines():
            byte_count, line_count, relative = line.split("\t", 2)
            row = source_row(root, relative, lines=True)
            if (row["bytes"], row["physical_lines"]) != (int(byte_count), int(line_count)):
                raise RuntimeError(f"Source differs from recorded inventory: {relative}")
            used.append(row)
        # Import resolution may change when a previously unused source changes.
        # Include every file under the search roots, not only the recorded imports.
        paths = {p.relative_to(root).as_posix() for directory in SEARCH_ROOTS
                 for p in (root / directory).rglob("*") if p.is_file()}
        files = [source_row(root, relative) for relative in sorted(paths)]
        commit = None
        if (root / ".git").exists():
            commit = subprocess.check_output(
                ["git", "-C", str(root), "rev-parse", "HEAD"], text=True, timeout=10).strip()
        authority = str(inventory)
    if not used or len({row["path"] for row in used}) != len(used):
        raise ValueError("Resolver inventory must contain distinct source paths")
    if ENTRY.as_posix() not in {row["path"] for row in used}:
        raise ValueError("Resolver inventory does not contain the settings entry")
    return dict(commit=commit, files=files, manifest_sha256=manifest_digest(files),
                used_source_files=used, used_source_manifest_sha256=manifest_digest(used),
                used_source_count=len(used), used_source_bytes=sum(row["bytes"] for row in used),
                used_source_physical_lines=sum(row["physical_lines"] for row in used),
                used_source_list_authority=authority)


def vulkan_library(override):
    if override:
        return override.resolve(strict=True)
    path = Path(subprocess.check_output(
        ["cc", "-print-file-name=libvulkan.so.1"], text=True, timeout=10).strip())
    if not path.is_file():
        raise ValueError("Cannot locate libvulkan.so.1; supply --vulkan-library PATH")
    return path.resolve()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--source-inventory", type=Path,
                        help="Recorded byte-count, line-count, relative-path TSV; snapshots use their manifest")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pipeline-cache-dir", type=Path,
                        help="Driver/pipeline cache only; defaults to OUT/../pipeline-cache")
    parser.add_argument("--shader-root", type=Path, help="Matching shader artifacts for a frozen binary")
    parser.add_argument("--vulkan-library", type=Path, help="libvulkan.so.1; otherwise located through cc")
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--startup-timeout", type=float, default=180)
    parser.add_argument("--edit-pairs", action="store_true")
    parser.add_argument("--profile", action="store_true",
                        help="Keep profiling/checking environment; these are diagnostic, not timing samples")
    args = parser.parse_args()
    if args.warmups < 0 or args.runs < 1:
        parser.error("warmups must be nonnegative and runs positive")
    if any(not math.isfinite(value) or value <= 0 for value in (args.timeout, args.startup_timeout)):
        parser.error("timeouts must be finite and positive")
    args.binary = args.binary.resolve(strict=True)
    args.source_root = args.source_root.resolve(strict=True)
    args.out = args.out.resolve()
    # An output inside a search root could become an input or mutate the snapshot.
    if args.out.is_relative_to(args.source_root):
        parser.error("--out must be outside --source-root")
    manifest = source_manifest(args.source_root, args.source_inventory)
    native_object = vulkan_library(args.vulkan_library)
    original_entry = args.source_root / ENTRY
    original = original_entry.read_bytes()
    if args.edit_pairs and original.count(b"code: 5,") != 1:
        raise ValueError("Expected exactly one settings return-code literal for --edit-pairs")
    args.out.mkdir(parents=True, exist_ok=True)
    entry = args.out / "ui_settings.lani" if args.edit_pairs else original_entry
    if args.edit_pairs:
        entry.write_bytes(original)
    env = dict(os.environ)
    for key in ["LANIUS_VULKAN_INCLUDE", "LANIUS_VULKAN_LOADER", "VK_LAYER_PATH", "LD_LIBRARY_PATH",
                "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "LANIUS_UI_TEST_DISPLAY", "LANIUS_SETTINGS_CAPTURE"]:
        env.pop(key, None)
    if not args.profile:
        for key in ["LANIUS_PERFETTO_TRACE", "LANIUS_REPORT", "LANIUS_TMP_SPANS", "LANIUS_TMP_STAMPS",
                    "LANIUS_CAPTURE", "LANIUS_CHECK", "LANIUS_TRACE", "LANIUS_EXPERIMENT"]:
            env.pop(key, None)
    env.pop("LANIUS_SHADER_ARTIFACT_ROOT", None)
    env["LANIUS_GPU_REQUIRE_HARDWARE"] = "1"
    cache = (args.pipeline_cache_dir or args.out.parent / "pipeline-cache").resolve()
    if cache.is_relative_to(args.source_root):
        parser.error("--pipeline-cache-dir must be outside --source-root")
    cache.mkdir(parents=True, exist_ok=True)
    env["LANIUS_PIPELINE_CACHE_DIR"] = str(cache)
    if args.shader_root:
        args.shader_root = args.shader_root.resolve(strict=True)
        env["LANIUS_SHADER_ARTIFACT_ROOT"] = str(args.shader_root)
    command = [str(args.binary), "daemon", "--stdio", "--backend", "x86_64",
               "--stdlib-root", str(args.source_root / "stdlib"), "--idle-buffer-timeout-ms", "0"]
    request = dict(command="compile", emit="x86_64", input=str(entry), output=str(args.out / "settings"),
                   stdlib_root=str(args.source_root / "stdlib"), native_link=True,
                   source_roots=[str(args.source_root / path) for path in SEARCH_ROOTS[1:]],
                   native_objects=[str(native_object)], native_libraries=LIBRARIES)
    receipt = dict(schema="lanius.settings-full-recompile.v1", command=command, request=request,
                   policy="Clear compiled-unit and library-instance caches before every compile; retain GPU pipelines and workspace.",
                   binary_sha256=sha256(args.binary.read_bytes()), original_source_sha256=sha256(original),
                   ui_source_commit=manifest["commit"], source_snapshot=str(args.source_root),
                   pipeline_cache_dir=str(cache), shader_root=str(args.shader_root) if args.shader_root else None,
                   source_manifest_sha256=manifest["manifest_sha256"],
                   profiled=args.profile, warmups=args.warmups, samples=[],
                   **{key: value for key, value in manifest.items() if key not in ("commit", "files", "used_source_files", "manifest_sha256")})
    if args.shader_root:
        receipt["shader_metadata"] = (args.shader_root / "artifacts.env").read_text()
    (args.out / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    def save():
        (args.out / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")

    save()
    stderr = (args.out / "daemon.stderr").open("wb")
    try:
        proc = subprocess.Popen(command, cwd=args.out, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=stderr, bufsize=0, start_new_session=True)
    except BaseException as error:
        receipt["error"] = str(error)
        save()
        stderr.close()
        raise
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    pending = bytearray()

    def read(timeout):
        deadline = time.monotonic() + timeout
        while b"\n" not in pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError("Timed out waiting for daemon response")
            part = os.read(proc.stdout.fileno(), 65536)
            if not part:
                raise RuntimeError(f"Daemon exited: {proc.poll()}; see daemon.stderr")
            pending.extend(part)
        line, _, rest = pending.partition(b"\n")
        pending[:] = rest
        return json.loads(line)

    def ask(req, timeout=None):
        started = time.perf_counter()
        proc.stdin.write((json.dumps(req) + "\n").encode())
        proc.stdin.flush()
        response = read(args.timeout if timeout is None else timeout)
        if response.get("id") != req["id"]:
            raise RuntimeError(f"Unexpected response id: {response}")
        return (time.perf_counter() - started) * 1000, response

    hashes_by_input = {}

    def run(kind, index):
        key = f"{kind}-{index}"
        _, cleared = ask(dict(id="clear-" + key, command="clear-compiled-unit-cache"))
        if not cleared.get("ok"):
            raise RuntimeError(f"Cache clear failed: {cleared}")
        wall_ms, response = ask(dict(request, id=key))
        sample = dict(kind=kind, index=index, wall_ms=wall_ms, response=response)
        receipt["samples"].append(sample)
        save()
        if not response.get("ok"):
            raise RuntimeError(f"Compilation failed: {response}")
        for cache_name in ("compiled_unit_cache", "library_instance_cache"):
            if response[cache_name]["hits_during_job"] != 0:
                raise RuntimeError(f"Full-recompile policy violated: {cache_name}={response[cache_name]}")
        elf = (args.out / "settings").read_bytes()
        if len(elf) < 64 or elf[:6] != b"\x7fELF\x02\x01" or elf[18:20] != b"\x3e\x00":
            raise RuntimeError("Compiler output is not an x86-64 little-endian ELF")
        sample.update(binary_sha256=sha256(elf), output_bytes=len(elf), input_sha256=sha256(entry.read_bytes()))
        expected = hashes_by_input.setdefault(sample["input_sha256"], sample["binary_sha256"])
        if expected != sample["binary_sha256"]:
            raise RuntimeError("Identical inputs produced different executables")
        prior = receipt["samples"][-2] if len(receipt["samples"]) > 1 else None
        if prior and prior["input_sha256"] != sample["input_sha256"] and prior["binary_sha256"] == sample["binary_sha256"]:
            raise RuntimeError("Edited source did not change the executable")
        save()
        print(json.dumps(dict(kind=kind, index=index, wall_ms=round(wall_ms, 3),
                              compile_ms=response["compile_ms"], load_ms=response["load_ms"],
                              dispatches=response.get("recorded_compute_dispatches_during_job"))), flush=True)

    try:
        receipt["ready"] = read(args.startup_timeout)
        if receipt["ready"].get("event") != "ready":
            raise RuntimeError(f"Daemon did not become ready: {receipt['ready']}")
        save()
        for i in range(args.warmups):
            run("warmup", i)
        for i in range(args.runs):
            if args.edit_pairs:
                entry.write_bytes(original)
            run("unchanged", i)
            if args.edit_pairs:
                entry.write_bytes(original.replace(b"code: 5,", f"code: {6+i},".encode()))
                run("edit", i)
        receipt["summary"] = {}
        for kind in ("unchanged", "edit"):
            samples = [sample for sample in receipt["samples"] if sample["kind"] == kind]
            if samples:
                wall = [sample["wall_ms"] for sample in samples]
                receipt["summary"][kind] = dict(samples=len(samples), median_wall_ms=statistics.median(wall),
                    min_wall_ms=min(wall), max_wall_ms=max(wall),
                    median_compile_ms=statistics.median(sample["response"]["compile_ms"] for sample in samples))
        receipt["verified_full_recompiles"] = True
        _, receipt["shutdown"] = ask(dict(id="shutdown", command="shutdown"), timeout=10)
        proc.wait(timeout=10)
        receipt["shutdown_exit_code"] = proc.returncode
        if proc.returncode != 0:
            raise RuntimeError(f"Daemon shutdown exited {proc.returncode}")
        print(json.dumps(receipt["summary"], indent=2), flush=True)
    except BaseException as error:
        receipt["error"] = str(error)
        raise
    finally:
        if proc.poll() is None and "shutdown" not in receipt:
            try:
                _, receipt["shutdown"] = ask(dict(id="shutdown", command="shutdown"), timeout=5)
                proc.wait(timeout=5)
            except Exception as error:
                receipt["cleanup_shutdown_error"] = str(error)
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=10)
        selector.close()
        stderr.close()
        if args.edit_pairs:
            entry.write_bytes(original)
        try:
            unchanged = source_manifest(args.source_root, args.source_inventory) == manifest
        except Exception as error:
            unchanged = False
            receipt["source_verification_error"] = str(error)
        receipt["all_snapshot_sources_unchanged"] = unchanged
        had_error = "error" in receipt
        if not unchanged:
            receipt.setdefault("error", "Source tree changed during benchmark")
        save()
        if not unchanged and not had_error:
            raise RuntimeError(receipt["error"])


if __name__ == "__main__":
    main()
