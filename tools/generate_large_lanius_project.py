#!/usr/bin/env python3
"""Generate a reachable Lanius workload split across bounded source files."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from compile_workload_model import (
    Workload,
    build_workload,
    evaluate,
    render_leaf,
    render_reducer,
)


DEFAULT_MAX_MODULE_BYTES = 1_750_000


@dataclass(frozen=True)
class FunctionSource:
    name: str
    source: str
    dependencies: tuple[str, ...]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--target-bytes", type=int, required=True)
    parser.add_argument("--seed", type=int, default=20)
    parser.add_argument(
        "--max-module-bytes", type=int, default=DEFAULT_MAX_MODULE_BYTES
    )
    args = parser.parse_args()
    if args.target_bytes <= 0:
        parser.error("--target-bytes must be positive")
    if args.max_module_bytes <= 0:
        parser.error("--max-module-bytes must be positive")

    repo = Path(__file__).resolve().parents[1]
    out = (repo / args.out).resolve()
    leaf_count = largest_project_that_fits(
        args.seed, args.target_bytes, args.max_module_bytes
    )
    workload = build_workload(args.seed, leaf_count)
    files = render_project(workload, args.max_module_bytes)
    unpadded_bytes = sum(len(source.encode()) for source in files.values())
    padding_bytes = args.target_bytes - unpadded_bytes
    if padding_bytes < 0:
        raise AssertionError("selected workload exceeds target project size")
    # Keep the entry outside the source root. The bounded entry loader treats
    # imported source-root modules as dependency inputs and schedules the entry
    # after their interfaces, matching normal project layout.
    entry_path = "main.lani"
    files[entry_path] = add_padding(files[entry_path], padding_bytes)

    for relative, source in files.items():
        path = out / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
    descriptor_manifest = write_descriptor_inputs(out, repo, files)
    source_records = []
    total_bytes = 0
    for relative in sorted(files):
        path = out / relative
        byte_count = path.stat().st_size
        total_bytes += byte_count
        source_records.append(
            {
                "path": relative,
                "bytes": byte_count,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    if total_bytes != args.target_bytes:
        raise AssertionError(
            f"project has {total_bytes} source bytes, expected {args.target_bytes}"
        )
    manifest = {
        "schema": "lanius.large-scaling-project.v1",
        "seed": args.seed,
        "target_source_bytes": args.target_bytes,
        "expected_exit_code": evaluate(workload) & 255,
        "max_module_bytes": args.max_module_bytes,
        "workload": workload.structure(),
        "sources": source_records,
        "compile_args": [
            "--source-root",
            str((out / "src").resolve()),
            str((out / entry_path).resolve()),
        ],
        "descriptor_library_manifest": str(descriptor_manifest),
    }
    (out / "scaling-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    return 0


def largest_project_that_fits(seed: int, target_bytes: int, limit: int) -> int:
    low = 1
    high = 2
    while project_size(build_workload(seed, high), limit) <= target_bytes:
        low = high
        high *= 2
    while low + 1 < high:
        middle = (low + high) // 2
        if project_size(build_workload(seed, middle), limit) <= target_bytes:
            low = middle
        else:
            high = middle
    return low


def project_size(workload: Workload, limit: int) -> int:
    return sum(len(source.encode()) for source in render_project(workload, limit).values())


def render_project(workload: Workload, limit: int) -> dict[str, str]:
    arguments = specialized_arguments(workload)
    functions = [
        FunctionSource(
            leaf.name,
            specialize_argument(public(render_leaf("lanius", leaf)), leaf.name, arguments),
            (),
        )
        for leaf in workload.leaves
    ]
    functions.extend(
        FunctionSource(
            reducer.name,
            specialize_argument(
                public(render_reducer("lanius", reducer)), reducer.name, arguments
            ),
            (reducer.left, reducer.right),
        )
        for reducer in workload.reducers
    )

    shards: list[list[FunctionSource]] = []
    current: list[FunctionSource] = []
    current_bytes = 0
    header_reserve = 32_768
    for function in functions:
        function_bytes = len(function.source.encode())
        if current and current_bytes + function_bytes + header_reserve > limit:
            shards.append(current)
            current = []
            current_bytes = 0
        current.append(function)
        current_bytes += function_bytes
    if current:
        shards.append(current)

    owner = {
        function.name: shard_index
        for shard_index, shard in enumerate(shards)
        for function in shard
    }
    files: dict[str, str] = {}
    for shard_index, shard in enumerate(shards):
        dependencies = sorted(
            {
                owner[dependency]
                for function in shard
                for dependency in function.dependencies
                if owner[dependency] != shard_index
            }
        )
        imports = "".join(
            f"import bench::shard_{dependency:05d};\n"
            for dependency in dependencies
        )
        header = (
            f"module bench::shard_{shard_index:05d};\n\n"
            f"{imports}\n"
        )
        source = header + "".join(
            without_pair_structs(function.source) for function in shard
        )
        if len(source.encode()) > limit:
            raise ValueError(
                f"module {shard_index} exceeds --max-module-bytes: "
                f"{len(source.encode())} > {limit}"
            )
        files[f"src/bench/shard_{shard_index:05d}.lani"] = source

    root_shard = owner[workload.root]
    entry_imports = f"import bench::shard_{root_shard:05d};\n"
    files["main.lani"] = (
        "module bench::main;\n\n"
        f"{entry_imports}\n"
        "fn main() -> i32 {\n"
        f"    return {workload.root}() & 255;\n"
        "}\n"
    )
    return files


def public(source: str) -> str:
    if not source.startswith("fn "):
        raise AssertionError("expected a top-level Lanius function")
    return "pub " + source


def without_pair_structs(source: str) -> str:
    pattern = re.compile(
        r"    let pair: Pair = Pair \{ left: (?P<left>.+), right: (?P<right>.+) \};\n"
        r"    value = \(pair\.left \* 3 \+ pair\.right \* 7 \+ (?P<bias>\d+)\) & 4095;"
    )
    return pattern.sub(
        lambda match: (
            f"    let pair_left: i32 = {match.group('left')};\n"
            f"    let pair_right: i32 = {match.group('right')};\n"
            "    value = (pair_left * 3 + pair_right * 7 + "
            f"{match.group('bias')}) & 4095;"
        ),
        source,
    )


def specialized_arguments(workload: Workload) -> dict[str, int]:
    reducers = {reducer.name: reducer for reducer in workload.reducers}
    arguments = {}

    def visit(name: str, argument: int) -> None:
        if name in arguments:
            if arguments[name] != argument:
                raise AssertionError("workload node has multiple specialized arguments")
            return
        arguments[name] = argument
        reducer = reducers.get(name)
        if reducer is not None:
            visit(reducer.left, (argument + reducer.left_salt) & 4095)
            visit(reducer.right, (argument + reducer.right_salt) & 4095)

    visit(workload.root, 7)
    if len(arguments) != workload.function_count:
        raise AssertionError("specialization did not reach every workload function")
    return arguments


def specialize_argument(
    source: str, name: str, arguments: dict[str, int]
) -> str:
    signature = f"pub fn {name}(x: i32) -> i32 {{"
    if signature not in source:
        raise AssertionError(f"missing function signature for {name}")
    source = source.replace(
        signature,
        f"pub fn {name}() -> i32 {{\n    let x: i32 = {arguments[name]};",
        1,
    )
    return re.sub(
        r"((?:leaf|reduce)_[0-9_]+)\(\(x \+ \d+\) & 4095\)",
        r"\1()",
        source,
    )


def add_padding(entry: str, byte_count: int) -> str:
    if byte_count == 0:
        return entry
    if byte_count < 4:
        return entry + (" " * byte_count)
    return entry + "/*" + ("p" * (byte_count - 4)) + "*/"


def write_descriptor_inputs(
    out: Path, repo: Path, files: dict[str, str]
) -> Path:
    descriptor = out / "descriptor"
    descriptor.mkdir(parents=True, exist_ok=True)
    # The shards are source files in one benchmark library, not hundreds of
    # artificial libraries.  Library boundaries are semantic and scheduling
    # boundaries in the compiler; assigning one per file would force every
    # shard through a separate frontend and codegen job even when a GPU can
    # process a much larger unit.
    module_library_ids = {
        module_declaration(source): 100
        for relative, source in files.items()
        if relative.startswith("src/")
    }
    module_library_ids["bench::main"] = 1_000_000

    library_paths = [
        (out / relative).resolve()
        for relative in sorted(files)
        if relative.startswith("src/")
    ]
    entry_source = files["main.lani"]
    records = [
        library_record(descriptor, 100, library_paths, []),
        library_record(
            descriptor,
            1_000_000,
            [(out / "main.lani").resolve()],
            imported_library_ids(
                entry_source, 1_000_000, module_library_ids
            ),
        ),
    ]
    records = topological_records(records)
    manifest = descriptor / "libraries.jsonl"
    manifest.write_text("".join(json.dumps(record) + "\n" for record in records))
    return manifest.resolve()


def module_declaration(source: str) -> str:
    match = re.search(r"^module ([A-Za-z0-9_:]+);$", source, re.MULTILINE)
    if not match:
        raise AssertionError("generated source lacks a leading module declaration")
    return match.group(1)


def imported_library_ids(
    source: str, library_id: int, module_library_ids: dict[str, int]
) -> list[int]:
    dependencies = {
        module_library_ids[imported]
        for imported in re.findall(
            r"^import ([A-Za-z0-9_:]+);$", source, re.MULTILINE
        )
        if imported in module_library_ids
        and module_library_ids[imported] != library_id
    }
    return sorted(dependencies)


def topological_records(records: list[dict[str, object]]) -> list[dict[str, object]]:
    remaining = {int(record["library_id"]): record for record in records}
    emitted = set()
    ordered = []
    while remaining:
        ready = sorted(
            library_id
            for library_id, record in remaining.items()
            if set(record["dependency_library_ids"]).issubset(emitted)
        )
        if not ready:
            raise ValueError(
                f"generated library dependency graph contains a cycle: {sorted(remaining)}"
            )
        for library_id in ready:
            ordered.append(remaining.pop(library_id))
            emitted.add(library_id)
    return ordered


def library_record(
    descriptor: Path,
    library_id: int,
    paths: list[Path],
    dependencies: list[int],
) -> dict[str, object]:
    path_list = descriptor / f"library-{library_id}.paths"
    path_list.write_text("".join(str(path.resolve()) + "\n" for path in paths))
    return {
        "library_id": library_id,
        "source_file_count": len(paths),
        "path_list": str(path_list.resolve()),
        "dependency_library_ids": dependencies,
    }


if __name__ == "__main__":
    raise SystemExit(main())
