#!/usr/bin/env python3
"""Generate one corpus-calibrated project in C, C++, Rust, Zig, and Lanius."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from typical_project_model import LANGUAGES, build_project, render_project


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "target" / "typical-project")
    parser.add_argument(
        "--files", type=int, default=100, help="source files per language"
    )
    parser.add_argument("--seed", type=int, default=20260808)
    return parser.parse_args()


def write_files(root: Path, files: dict[str, str]) -> list[dict[str, object]]:
    records = []
    for relative, source in sorted(files.items()):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        if path.suffix in {".c", ".cpp", ".rs", ".zig", ".lani"}:
            records.append(
                {
                    "path": relative,
                    "bytes": len(source.encode()),
                    "lines": source.count("\n") + 1,
                    "sha256": hashlib.sha256(source.encode()).hexdigest(),
                }
            )
    return records


def write_ninja(root: Path, cpp: bool) -> None:
    extension = "cpp" if cpp else "c"
    compiler = "c++" if cpp else "cc"
    standard = "-std=c++20" if cpp else "-std=c17"
    sources = sorted((root / "src").glob(f"*.{extension}"))
    objects = [f"build/{source.stem}.o" for source in sources]
    lines = [
        f"compiler = {compiler}",
        f"cflags = {standard} -O0 -g0 -Iinclude",
        "rule compile",
        "  command = $compiler $cflags -MMD -MF $out.d -c $in -o $out",
        "  depfile = $out.d",
        "  deps = gcc",
        "rule link",
        "  command = $compiler $in -o $out",
        "",
    ]
    lines.extend(
        f"build {obj}: compile src/{source.name}"
        for obj, source in zip(objects, sources)
    )
    lines.extend(
        (
            f"build typical-project: link {' '.join(objects)}",
            "default typical-project",
            "",
        )
    )
    (root / "build.ninja").write_text("\n".join(lines))


def generate(out: Path, file_count: int, seed: int) -> dict[str, object]:
    project = build_project(seed, file_count)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    languages = {}
    for language in LANGUAGES:
        language_root = out / language
        records = write_files(language_root, render_project(language, project))
        if language == "lanius":
            # Keep the manifest's source-root contract valid for a one-file
            # project, where there are no imported module files to create it.
            (language_root / "src").mkdir(exist_ok=True)
        if language in {"c", "cpp"}:
            write_ninja(language_root, cpp=language == "cpp")
        languages[language] = {
            "source_file_count": len(records),
            "source_bytes": sum(record["bytes"] for record in records),
            "sources": records,
        }
    profile_path = Path(__file__).with_name("typical_project_profile.json")
    construct_profile_path = Path(__file__).with_name("typical_construct_profile.json")
    manifest = {
        "schema": "lanius.typical-project.v1",
        "classification": "corpus_calibrated_typical_project",
        "representative_workload": True,
        "workload_domain": "order_fulfillment_rule_engine",
        "seed": seed,
        "expected_stdout": f"{project.evaluate()}\n",
        "expected_exit_code": 0,
        "profile": {
            "path": str(profile_path.relative_to(ROOT)),
            "sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest(),
        },
        "construct_profile": {
            "path": str(construct_profile_path.relative_to(ROOT)),
            "sha256": hashlib.sha256(construct_profile_path.read_bytes()).hexdigest(),
        },
        "structure": project.structure(),
        "languages": languages,
        "commands": {
            "c": {"build": ["ninja", "-C", "c"], "run": ["c/typical-project"]},
            "cpp": {"build": ["ninja", "-C", "cpp"], "run": ["cpp/typical-project"]},
            "rust": {
                "build": ["cargo", "build", "--manifest-path", "rust/Cargo.toml"],
                "run": ["rust/target/debug/typical_project"],
            },
            "zig": {
                "build": [
                    "zig",
                    "build-exe",
                    "-lc",
                    "-O",
                    "Debug",
                    "-fstrip",
                    "zig/main.zig",
                    "-femit-bin=zig/typical-project",
                ],
                "run": ["zig/typical-project"],
            },
            "lanius": {
                "x86_64": {
                    "build": [
                        str(ROOT / "target" / "release" / "laniusc"),
                        "--emit",
                        "x86_64",
                        "--stdlib-root",
                        str(ROOT / "stdlib"),
                        "--source-root",
                        "lanius/src",
                        "-o",
                        "lanius/typical-project",
                        "lanius/main.lani",
                    ],
                    "post_build": ["chmod", "+x", "lanius/typical-project"],
                    "run": ["lanius/typical-project"],
                },
                "wasm": {
                    "build": [
                        str(ROOT / "target" / "release" / "laniusc"),
                        "--emit",
                        "wasm",
                        "--stdlib-root",
                        str(ROOT / "stdlib"),
                        "--source-root",
                        "lanius/src",
                        "-o",
                        "lanius/typical-project.wasm",
                        "lanius/main.lani",
                    ],
                    "run": ["wasmtime", "lanius/typical-project.wasm"],
                },
            },
        },
    }
    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    return manifest


def main() -> None:
    args = parse_args()
    manifest = generate(args.out.resolve(), args.files, args.seed)
    print(
        json.dumps(
            {
                "output": str(args.out.resolve()),
                "files_per_language": manifest["structure"]["source_file_count"],
                "expected_stdout": manifest["expected_stdout"].strip(),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
