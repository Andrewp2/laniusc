#!/usr/bin/env python3
"""Generate controlled synthetic compiler stress inputs."""

import argparse
import hashlib
import json
from pathlib import Path

from compiler_stress_bounded_project import (
    DEFAULT_MAX_MODULE_BYTES,
    generate_bounded_project,
)
from compiler_stress_model import (
    LANGUAGES,
    WORKLOAD_PROFILES,
    build_workload,
    evaluate,
    render,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="target/lanius-compiler-stress/sources",
        help="directory for generated source sets",
    )
    parser.add_argument(
        "--layout",
        choices=("comparative-single-file", "bounded-project"),
        default="comparative-single-file",
    )
    parser.add_argument(
        "--sizes",
        default="100000,500000,1100000",
        help="comma-separated target Lanius source sizes in bytes",
    )
    parser.add_argument("--seed", type=int, default=19)
    parser.add_argument(
        "--profile",
        choices=tuple(WORKLOAD_PROFILES),
        default="mixed-function-sizes",
        help="function-size distribution to generate",
    )
    parser.add_argument(
        "--functions",
        type=int,
        help="force the number of reachable leaf functions",
    )
    parser.add_argument(
        "--target-bytes",
        type=int,
        help="exact bounded-project source bytes",
    )
    parser.add_argument(
        "--max-module-bytes",
        type=int,
        default=DEFAULT_MAX_MODULE_BYTES,
    )
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    out = (repo / args.out).resolve()
    if args.layout == "bounded-project":
        if args.target_bytes is None or args.target_bytes <= 0:
            parser.error("--layout bounded-project requires positive --target-bytes")
        if args.max_module_bytes <= 0:
            parser.error("--max-module-bytes must be positive")
        generate_bounded_project(
            out,
            args.target_bytes,
            args.seed,
            args.max_module_bytes,
        )
        return 0

    sizes = parse_sizes(parser, args.sizes)
    if args.functions is not None and args.functions <= 0:
        parser.error("--functions must be positive")
    out.mkdir(parents=True, exist_ok=True)

    source_sets = [
        generate_source_set(out, target_bytes, args.seed, args.functions, args.profile)
        for target_bytes in sizes
    ]
    manifest = {
        "schema": "lanius.compiler-stress-sources.v1",
        "classification": "synthetic_stress",
        "representative_workload": False,
        "layout": args.layout,
        "seed": args.seed,
        "profile": args.profile,
        "profile_description": WORKLOAD_PROFILES[args.profile].description,
        "source_sets": source_sets,
    }
    write_json(out / "manifest.json", manifest)
    return 0


def parse_sizes(parser: argparse.ArgumentParser, raw: str) -> list[int]:
    try:
        sizes = [int(part.strip()) for part in raw.split(",") if part.strip()]
    except ValueError:
        parser.error("--sizes must contain comma-separated integers")
    if not sizes or any(size <= 0 for size in sizes):
        parser.error("--sizes must contain positive byte counts")
    if len(set(sizes)) != len(sizes):
        parser.error("--sizes must not contain duplicates")
    return sizes


def generate_source_set(
    out: Path,
    target_bytes: int,
    seed: int,
    leaf_count: int | None,
    profile: str,
) -> dict[str, object]:
    leaf_count = leaf_count or largest_workload_that_fits(seed, target_bytes, profile)
    workload = build_workload(seed, leaf_count, profile)
    natural_lanius_bytes = len(render("lanius", workload).encode())
    lanius_source = render("lanius", workload, target_bytes)
    sources = {
        language: (
            lanius_source if language == "lanius" else render(language, workload)
        )
        for language in LANGUAGES
    }
    set_dir = out / str(target_bytes)
    set_dir.mkdir(parents=True, exist_ok=True)
    paths = {language: set_dir / source_name(language) for language in LANGUAGES}
    for language, path in paths.items():
        path.write_text(sources[language])

    expected = evaluate(workload)
    structure = workload.structure()
    if structure["reachable_function_count"] != workload.function_count:
        raise AssertionError("workload contains unreachable functions")
    return {
        "target_lanius_bytes": target_bytes,
        "seed": seed,
        "profile": profile,
        "expected_stdout": f"{expected}\n",
        "workload": structure,
        "natural_lanius_bytes": natural_lanius_bytes,
        "padding_bytes": target_bytes - natural_lanius_bytes,
        "sources": {
            language: {
                "path": str(path.relative_to(out)),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for language, path in paths.items()
        },
    }


def largest_workload_that_fits(seed: int, target_bytes: int, profile: str) -> int:
    low = 1
    high = 2
    while source_size(seed, high, profile) <= target_bytes:
        low = high
        high *= 2
    while low + 1 < high:
        middle = (low + high) // 2
        if source_size(seed, middle, profile) <= target_bytes:
            low = middle
        else:
            high = middle
    return low


def source_size(seed: int, leaf_count: int, profile: str) -> int:
    return len(render("lanius", build_workload(seed, leaf_count, profile)).encode())


def source_name(language: str) -> str:
    return {
        "rust": "scaling.rs",
        "c": "scaling.c",
        "cpp": "scaling.cpp",
        "zig": "scaling.zig",
        "lanius": "scaling.lani",
    }[language]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
