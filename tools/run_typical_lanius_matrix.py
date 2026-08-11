#!/usr/bin/env python3
"""Measure warm-daemon Lanius compilation across realistic project file counts."""

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path


SCHEMA = "lanius.typical-project-compiler-matrix.v1"


def parse_counts(raw: str) -> list[int]:
    counts = [int(value) for value in raw.split(",")]
    if (
        not counts
        or any(value <= 0 for value in counts)
        or len(set(counts)) != len(counts)
    ):
        raise ValueError("--file-counts must contain distinct positive integers")
    return counts


def median_mad(samples: list[float]) -> dict[str, float | int]:
    median = statistics.median(samples)
    return {
        "samples": len(samples),
        "median_ms": median,
        "mad_ms": statistics.median(abs(sample - median) for sample in samples),
        "min_ms": min(samples),
        "max_ms": max(samples),
    }


def source_facts(project: Path) -> dict[str, int]:
    paths = sorted((project / "lanius").rglob("*.lani"))
    sizes = [path.stat().st_size for path in paths]
    if not sizes:
        raise ValueError(f"{project} has no Lanius source files")
    return {
        "source_files": len(sizes),
        "source_bytes": sum(sizes),
        "largest_source_file_bytes": max(sizes),
    }


def benchmark_edit_variants(
    repo: Path, project: Path, count: int
) -> list[dict[str, str]]:
    if count <= 0:
        raise ValueError("benchmark edit variant count must be positive")
    candidates = sorted((project / "lanius").rglob("*.lani"))
    for path in candidates[len(candidates) // 2 :] + candidates[: len(candidates) // 2]:
        source = path.read_text()
        for line in source.splitlines():
            if source.count(line) != 1:
                continue
            for match in re.finditer(r"\b[1-9][0-9]{2,}\b", line):
                width = len(match.group(0))
                domain_start = 10 ** (width - 1)
                domain_size = 9 * domain_start
                if count >= domain_size:
                    continue
                original_value = int(match.group(0))
                variants = []
                previous = line
                for offset in range(1, count + 1):
                    replacement = str(
                        domain_start
                        + ((original_value - domain_start + offset) % domain_size)
                    )
                    changed = line[: match.start()] + replacement + line[match.end() :]
                    variants.append(
                        {
                            "path": str(path.relative_to(repo)),
                            "old": previous,
                            "new": changed,
                        }
                    )
                    previous = changed
                return variants
    raise ValueError(f"could not identify a stable benchmark edit in {project}")


def daemon_commands(repo: Path, project: Path, target: str, samples: int) -> dict:
    relative = project.relative_to(repo)
    suffix = "wasm" if target == "wasm" else ""
    output_name = "matrix-artifact" + (f".{suffix}" if suffix else "")
    edits = benchmark_edit_variants(repo, project, samples + 1)
    requests = [
        {
            "id": "cold-capacity",
            "command": "compile",
            "emit": target,
            "input": str(relative / "lanius" / "main.lani"),
            "source_root": str(relative / "lanius" / "src"),
            "output": str(relative / "lanius" / output_name),
        }
    ]
    requests.append(
        {
            "id": "edit-warmup",
            "command": "compile",
            "emit": target,
            "input": str(relative / "lanius" / "main.lani"),
            "source_root": str(relative / "lanius" / "src"),
            "output": str(relative / "lanius" / output_name),
            "benchmark_source_edit": edits[0],
        }
    )
    for index in range(samples):
        requests.append(
            {
                "id": f"edit-{index + 1:02d}",
                "command": "compile",
                "emit": target,
                "input": str(relative / "lanius" / "main.lani"),
                "source_root": str(relative / "lanius" / "src"),
                "output": str(relative / "lanius" / output_name),
                "benchmark_source_edit": edits[index + 1],
            }
        )
    requests.append(
        {
            "id": "restore-source",
            "command": "compile",
            "emit": target,
            "input": str(relative / "lanius" / "main.lani"),
            "source_root": str(relative / "lanius" / "src"),
            "output": str(relative / "lanius" / output_name),
            "benchmark_source_edit": {
                "path": edits[-1]["path"],
                "old": edits[-1]["new"],
                "new": edits[0]["old"],
            },
        }
    )
    requests.append({"id": "shutdown", "command": "shutdown"})
    return {
        "lanius": {
            "daemon_start": [
                "target/release/laniusc",
                "daemon",
                "--stdio",
                "--backend",
                target,
                "--stdlib-root",
                "stdlib",
                "--idle-buffer-timeout-ms",
                "0",
            ],
            "requests": requests,
        }
    }


def validate_artifact(project: Path, target: str, expected_stdout: str) -> None:
    if target == "x86_64":
        command = [str(project / "lanius" / "matrix-artifact")]
    else:
        node = shutil.which("node")
        if node is None:
            raise RuntimeError("Node.js is required to validate Lanius Wasm artifacts")
        script = r"""
const fs = require('fs');
(async () => {
  let instance = null;
  let stdout = '';
  let heapPtr = 1024;
  const cwd = '/lanius/test/cwd';
  const exitSignal = Symbol('lanius-exit');
  function alignUp(value, align) {
    const amount = Math.max(1, align >>> 0);
    return (value + amount - 1) & ~(amount - 1);
  }
  function allocate(size, align) {
    const start = alignUp(heapPtr, align);
    const end = start + (size >>> 0);
    if (end > instance.exports.memory.buffer.byteLength) return 0;
    heapPtr = end;
    return start | 0;
  }
  function writeBytes(ptr, len, value) {
    const bytes = Buffer.from(value, 'utf8');
    const count = Math.min(len >>> 0, bytes.length);
    new Uint8Array(instance.exports.memory.buffer, ptr >>> 0, count)
      .set(bytes.subarray(0, count));
    return count | 0;
  }
  const env = new Proxy({}, {
    get(_target, property) {
      const name = String(property);
      if (name === 'print_i64') {
        return value => { stdout += value.toString() + '\n'; };
      }
      if (name === 'write_stdout') {
        return (ptr, len) => {
          const bytes = new Uint8Array(instance.exports.memory.buffer, ptr >>> 0, len >>> 0);
          stdout += Buffer.from(bytes).toString('utf8');
          return len | 0;
        };
      }
      if (name === 'write_stderr') {
        return (_ptr, len) => len | 0;
      }
      if (name === 'argc') return () => 1;
      if (name === 'current_dir_len') return () => Buffer.byteLength(cwd, 'utf8');
      if (name === 'current_dir_read') return (ptr, len) => writeBytes(ptr, len, cwd);
      if (name === 'unix_seconds') return () => 1234567890;
      if (name === 'secure_u32') return () => 1234567;
      if (name === 'open_read_path') return () => 3;
      if (name === 'close') return () => 0;
      if (name === 'alloc') return allocate;
      if (name === 'realloc') {
        return (ptr, oldSize, newSize, align) => {
          const next = allocate(newSize, align);
          if (next === 0) return 0;
          const count = Math.min(oldSize >>> 0, newSize >>> 0);
          const source = new Uint8Array(instance.exports.memory.buffer, ptr >>> 0, count);
          new Uint8Array(instance.exports.memory.buffer, next >>> 0, count).set(source);
          return next | 0;
        };
      }
      if (name === 'alloc_failed') {
        return () => { throw { [exitSignal]: true, code: 1 }; };
      }
      if (name === 'dealloc') return () => {};
      if (name === 'exit') {
        return code => { throw { [exitSignal]: true, code: code | 0 }; };
      }
      return () => { throw new Error(`unexpected runtime import invoked: env.${name}`); };
    }
  });
  const loaded = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), { env });
  instance = loaded.instance;
  let status = 0;
  try {
    status = instance.exports.main();
  } catch (error) {
    if (error && error[exitSignal]) status = error.code;
    else throw error;
  }
  process.stdout.write(stdout);
  if ((status | 0) !== 0) process.exit(status | 0);
})().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
"""
        command = [node, "-e", script, str(project / "lanius" / "matrix-artifact.wasm")]
    completed = subprocess.run(
        command, cwd=project, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0 or completed.stdout != expected_stdout:
        raise RuntimeError(
            f"artifact validation failed for {project}: exit={completed.returncode}, "
            f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file-counts", default="1,10,100,1000,10000")
    parser.add_argument("--project-prefix", default="target/typical-project-")
    parser.add_argument("--samples", type=int, default=20, help="warm samples per cell")
    parser.add_argument("--target", choices=("x86_64", "wasm"), default="x86_64")
    parser.add_argument("--output", required=True)
    parser.add_argument("--startup-timeout", type=float, default=900.0)
    parser.add_argument("--job-timeout", type=float, default=900.0)
    args = parser.parse_args()
    if args.samples <= 0:
        parser.error("--samples must be positive")

    repo = Path(__file__).resolve().parents[1]
    output = (repo / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for file_count in parse_counts(args.file_counts):
        project = (repo / f"{args.project_prefix}{file_count}").resolve()
        manifest_path = project / "manifest.json"
        if not manifest_path.is_file():
            raise ValueError(f"missing generated project manifest {manifest_path}")
        manifest = json.loads(manifest_path.read_text())
        commands = daemon_commands(repo, project, args.target, args.samples)
        commands_path = output.parent / f"commands-{file_count}-{args.target}.json"
        transcript_path = output.parent / f"transcript-{file_count}-{args.target}.json"
        commands_path.write_text(json.dumps(commands, indent=2, sort_keys=True) + "\n")
        subprocess.run(
            [
                sys.executable,
                str(repo / "tools" / "run_daemon_benchmark.py"),
                "--commands",
                str(commands_path),
                "--output",
                str(transcript_path),
                "--startup-timeout",
                str(args.startup_timeout),
                "--job-timeout",
                str(args.job_timeout),
            ],
            cwd=repo,
            check=True,
        )
        transcript = json.loads(transcript_path.read_text())
        responses_by_id = {
            response["id"]: response
            for response in transcript["responses"]
            if "compile_ms" in response
        }
        cold = responses_by_id.get("cold-capacity")
        edit_warmup = responses_by_id.get("edit-warmup")
        warm = [
            responses_by_id.get(f"edit-{index + 1:02d}")
            for index in range(args.samples)
        ]
        if (
            cold is None
            or edit_warmup is None
            or any(response is None for response in warm)
        ):
            raise RuntimeError(
                f"{file_count}-file cell did not return every measured response"
            )
        expected_stdout = str(manifest["expected_stdout"])
        if not expected_stdout.endswith("\n"):
            expected_stdout += "\n"
        validate_artifact(project, args.target, expected_stdout)
        rows.append(
            {
                "file_count": file_count,
                **source_facts(project),
                "cold_capacity_job_ms": cold["compile_ms"],
                "edit_workspace_warmup_ms": edit_warmup["compile_ms"],
                "warm_compile": median_mad(
                    [response["compile_ms"] for response in warm]
                ),
                "warm_job": median_mad(
                    [response["elapsed_ms"] for response in warm]
                ),
                "warm_load": median_mad([response["load_ms"] for response in warm]),
                "warm_write": median_mad([response["write_ms"] for response in warm]),
                "warm_created_buffers": [
                    response["resources_created_during_job"]["buffers"]
                    for response in warm
                ],
                "warm_created_bind_groups": [
                    response["resources_created_during_job"]["bind_groups"]
                    for response in warm
                ],
                "transcript": str(transcript_path.relative_to(repo)),
                "validated_exit_code": int(manifest["expected_exit_code"]),
                "validated_stdout": expected_stdout,
            }
        )
        print(json.dumps(rows[-1], sort_keys=True), flush=True)

    output.write_text(
        json.dumps(
            {
                "schema": SCHEMA,
                "target": args.target,
                "warm_samples_per_cell": args.samples,
                "first_job_excluded_from_warm_statistics": True,
                "generator_schema": rows
                and json.loads(
                    (
                        (repo / f"{args.project_prefix}{rows[0]['file_count']}")
                        / "manifest.json"
                    ).read_text()
                )["schema"],
                "rows": rows,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"run_typical_lanius_matrix: {error}", file=sys.stderr)
        raise SystemExit(1)
