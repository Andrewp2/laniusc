#!/usr/bin/env python3
"""Generate comparable, type-valid compiler scaling inputs."""

import argparse
import hashlib
import json
from pathlib import Path


LANGUAGES = ("rust", "c", "cpp", "zig", "lanius")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="target/lanius-compile-scaling/sources",
        help="directory for generated source sets",
    )
    parser.add_argument(
        "--sizes",
        default="100000,500000,1100000",
        help="comma-separated target Lanius source sizes in bytes",
    )
    parser.add_argument("--seed", type=int, default=19)
    parser.add_argument(
        "--functions",
        type=int,
        help="force the same function count across separately generated variants",
    )
    args = parser.parse_args()

    sizes = parse_sizes(parser, args.sizes)
    if args.functions is not None and args.functions <= 0:
        parser.error("--functions must be positive")
    repo = Path(__file__).resolve().parents[1]
    out = (repo / args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    source_sets = []
    for target_bytes in sizes:
        source_set = generate_source_set(out, target_bytes, args.seed, args.functions)
        source_sets.append(source_set)

    manifest = {
        "schema": "lanius.compile-scaling-sources.v1",
        "seed": args.seed,
        "source_sets": source_sets,
    }
    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
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
    out: Path, target_bytes: int, seed: int, function_count: int | None = None
) -> dict[str, object]:
    set_dir = out / str(target_bytes)
    set_dir.mkdir(parents=True, exist_ok=True)
    function_count = function_count or function_count_for_lanius_size(target_bytes, seed)
    expected = kernel_value(0, 7, seed)
    paths = {
        language: set_dir / source_name(language) for language in LANGUAGES
    }
    writers = {language: path.open("w") for language, path in paths.items()}
    try:
        for language, writer in writers.items():
            writer.write(header(language))
        for index in range(function_count):
            for language, writer in writers.items():
                writer.write(function(language, index, seed))
        pad_lanius_to_target(
            writers["lanius"], target_bytes, len(main_function("lanius").encode())
        )
        for language, writer in writers.items():
            writer.write(main_function(language))
    finally:
        for writer in writers.values():
            writer.close()

    return {
        "target_lanius_bytes": target_bytes,
        "function_count": function_count,
        "expected_stdout": f"{expected}\n",
        "sources": {
            language: {
                "path": str(path.relative_to(out)),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for language, path in paths.items()
        },
    }


def pad_lanius_to_target(writer, target_bytes: int, trailer_bytes: int) -> None:
    remaining = target_bytes - writer.tell() - trailer_bytes
    if remaining < 0:
        raise ValueError(
            "forced function count exceeds target Lanius byte size; increase --sizes"
        )
    if remaining == 0:
        return
    if remaining <= 2:
        writer.write("\n" * remaining)
        return
    writer.write("//")
    remaining -= 2
    chunk = "p" * min(remaining, 1 << 20)
    while remaining > 1:
        amount = min(remaining - 1, len(chunk))
        writer.write(chunk[:amount])
        remaining -= amount
    writer.write("\n")


def function_count_for_lanius_size(target_bytes: int, seed: int) -> int:
    base = len((header("lanius") + main_function("lanius")).encode())
    count = 0
    size = base
    while True:
        next_size = size + len(function("lanius", count, seed).encode())
        if next_size > target_bytes:
            break
        size = next_size
        count += 1
    return max(count, 1)


def source_name(language: str) -> str:
    return {
        "rust": "scaling.rs",
        "c": "scaling.c",
        "cpp": "scaling.cpp",
        "zig": "scaling.zig",
        "lanius": "scaling.lani",
    }[language]


def header(language: str) -> str:
    return {
        "rust": "#![allow(dead_code)]\n\n",
        "c": "#include <stdio.h>\n\n",
        "cpp": "#include <cstdio>\n\n",
        "zig": 'const c = @cImport({ @cInclude("stdio.h"); });\n\n',
        "lanius": "module bench::scaling;\n\nimport std::io;\n\n",
    }[language]


def function(language: str, index: int, seed: int) -> str:
    name = f"kernel_{index:07d}"
    threshold = (index * 13 + seed * 7) % 89
    bias = (index * 29 + seed * 11) % 101
    if language == "rust":
        return f"""pub fn {name}(x: i32) -> i32 {{
    let mixed = (x * 17 + {bias}) % 97;
    if mixed < {threshold} {{ mixed + x }} else {{ mixed - x }}
}}

"""
    if language == "c":
        return f"""int {name}(int x) {{
    int mixed = (x * 17 + {bias}) % 97;
    if (mixed < {threshold}) return mixed + x;
    return mixed - x;
}}

"""
    if language == "cpp":
        return f"""extern "C" int {name}(int x) {{
    int mixed = (x * 17 + {bias}) % 97;
    if (mixed < {threshold}) return mixed + x;
    return mixed - x;
}}

"""
    if language == "zig":
        return f"""export fn {name}(x: i32) i32 {{
    const mixed: i32 = @mod(x * 17 + {bias}, 97);
    if (mixed < {threshold}) return mixed + x;
    return mixed - x;
}}

"""
    return f"""pub fn {name}(x: i32) -> i32 {{
    let mixed: i32 = (x * 17 + {bias}) % 97;
    if (mixed < {threshold}) {{
        return mixed + x;
    }}
    return mixed - x;
}}

"""


def main_function(language: str) -> str:
    return {
        "rust": 'fn main() { println!("{}", kernel_0000000(7)); }\n',
        "c": 'int main(void) { printf("%d\\n", kernel_0000000(7)); return 0; }\n',
        "cpp": 'int main() { std::printf("%d\\n", kernel_0000000(7)); return 0; }\n',
        "zig": 'pub fn main() void { _ = c.printf("%d\\n", kernel_0000000(7)); }\n',
        "lanius": """fn main() -> i32 {
    std::io::print_i32(kernel_0000000(7));
    return 0;
}
""",
    }[language]


def kernel_value(index: int, x: int, seed: int) -> int:
    threshold = (index * 13 + seed * 7) % 89
    bias = (index * 29 + seed * 11) % 101
    mixed = (x * 17 + bias) % 97
    return mixed + x if mixed < threshold else mixed - x


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
