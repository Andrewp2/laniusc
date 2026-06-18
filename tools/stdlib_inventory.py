#!/usr/bin/env python3
"""Generate a source-level stdlib reference from checked-in `.lani` files."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


STDLIB_ROOT = Path("stdlib")
PUBLIC_KINDS = ("const", "type", "fn", "extern fn", "enum", "struct", "trait", "impl")


@dataclass(frozen=True)
class PublicItem:
    kind: str
    name: str
    signature: str
    line: int


@dataclass(frozen=True)
class StdlibFile:
    path: Path
    layer: str
    module: str
    imports: tuple[str, ...]
    items: tuple[PublicItem, ...]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate standard-library reference tables from stdlib/*.lani sources."
    )
    parser.add_argument(
        "--stdlib-root",
        default=str(STDLIB_ROOT),
        help="stdlib source root to scan",
    )
    parser.add_argument("--output", help="write Markdown output to this path")
    parser.add_argument(
        "--check",
        help="compare generated Markdown with this path and exit nonzero if stale",
    )
    args = parser.parse_args()

    repo = repo_root()
    stdlib_root = Path(args.stdlib_root)
    files = parse_stdlib(repo / stdlib_root, stdlib_root)
    markdown = render_markdown(stdlib_root, files)

    if args.check:
        target = Path(args.check)
        try:
            current = target.read_text(encoding="utf-8")
        except FileNotFoundError:
            sys.stderr.write(f"stdlib_inventory: missing generated file {target}\n")
            return 1
        if current != markdown:
            sys.stderr.write(f"stdlib_inventory: generated output is stale: {target}\n")
            return 1
        return 0

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(markdown, encoding="utf-8")
    else:
        sys.stdout.write(markdown)
    return 0


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        return Path(result.stdout.strip())
    return Path.cwd()


def parse_stdlib(root: Path, display_root: Path) -> list[StdlibFile]:
    if not root.exists():
        raise SystemExit(f"stdlib_inventory: missing stdlib root {root}")

    files: list[StdlibFile] = []
    for path in sorted(root.rglob("*.lani")):
        rel = display_root / path.relative_to(root)
        files.append(parse_stdlib_file(path, rel))
    return files


def parse_stdlib_file(path: Path, rel: Path) -> StdlibFile:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    module = parse_module(lines)
    imports = tuple(parse_imports(lines))
    items = tuple(parse_public_items(lines))
    return StdlibFile(
        path=rel,
        layer=stdlib_layer(rel),
        module=module or flat_module_name(rel),
        imports=imports,
        items=items,
    )


def parse_module(lines: list[str]) -> str | None:
    pattern = re.compile(r"^\s*module\s+([^;]+);")
    for line in lines:
        match = pattern.match(line)
        if match:
            return match.group(1).strip()
    return None


def parse_imports(lines: list[str]) -> list[str]:
    pattern = re.compile(r"^\s*import\s+([^;]+);")
    return [match.group(1).strip() for line in lines if (match := pattern.match(line))]


def parse_public_items(lines: list[str]) -> list[PublicItem]:
    items: list[PublicItem] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("pub "):
            continue
        signature = collect_signature(lines, index)
        kind, name = classify_public_item(signature)
        if kind is None or name is None:
            continue
        items.append(PublicItem(kind=kind, name=name, signature=signature, line=index + 1))
    return items


def collect_signature(lines: list[str], start: int) -> str:
    parts: list[str] = []
    for line in lines[start:]:
        stripped = line.strip()
        parts.append(stripped)
        if "{" in stripped or ";" in stripped:
            break
    signature = " ".join(part for part in parts if part)
    if "{" in signature:
        signature = signature.split("{", 1)[0].strip()
    elif signature.endswith(";"):
        signature = signature[:-1].strip() + ";"
    return re.sub(r"\s+", " ", signature)


def classify_public_item(signature: str) -> tuple[str | None, str | None]:
    patterns = (
        ("extern fn", r'^pub\s+extern\s+"[^"]+"\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)'),
        ("fn", r"^pub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("const", r"^pub\s+const\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("type", r"^pub\s+type\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("enum", r"^pub\s+enum\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("struct", r"^pub\s+struct\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("trait", r"^pub\s+trait\s+([A-Za-z_][A-Za-z0-9_]*)"),
        ("impl", r"^pub\s+impl\s+(.+)$"),
    )
    for kind, pattern in patterns:
        match = re.match(pattern, signature)
        if not match:
            continue
        name = match.group(1).strip()
        return kind, name
    return None, None


def stdlib_layer(path: Path) -> str:
    parts = path.parts
    if len(parts) < 3:
        return "legacy-flat"
    return parts[1]


def flat_module_name(path: Path) -> str:
    return f"(flat) {path.as_posix()}"


def render_markdown(stdlib_root: Path, files: list[StdlibFile]) -> str:
    item_counts = Counter(item.kind for file in files for item in file.items)
    layer_counts = Counter(file.layer for file in files)
    lines: list[str] = [
        "# Generated Standard Library Reference",
        "",
        f"Generated by `tools/stdlib_inventory.py` from `{stdlib_root.as_posix()}`.",
        "Regenerate this file instead of editing it by hand.",
        "",
        "```bash",
        "tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md",
        "tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md",
        "```",
        "",
        "## Summary",
        "",
    ]
    lines.extend(
        table(
            ("Item", "Count"),
            [
                ("Source files", str(len(files))),
                ("Module files", str(sum(1 for file in files if not file.module.startswith("(flat)")))),
                ("Legacy flat files", str(sum(1 for file in files if file.module.startswith("(flat)")))),
                ("Imports", str(sum(len(file.imports) for file in files))),
                ("Public declarations", str(sum(len(file.items) for file in files))),
                *[(f"Layer: {layer}", str(count)) for layer, count in sorted_counter(layer_counts)],
                *[(f"Declaration: {kind}", str(item_counts[kind])) for kind in PUBLIC_KINDS],
            ],
        )
    )

    lines.extend(["", "## Module Index", ""])
    lines.extend(
        table(
            (
                "Layer",
                "Module",
                "File",
                "Imports",
                "Public Items",
                "Consts",
                "Types",
                "Fns",
                "Extern Fns",
                "Enums",
                "Structs",
                "Traits",
                "Impls",
                "Runtime Flags",
            ),
            [module_index_row(file) for file in files],
        )
    )

    lines.extend(["", "## Public Declarations By Module", ""])
    for file in files:
        lines.extend(["", f"### {file.module}", ""])
        lines.append(f"File: `{file.path.as_posix()}`")
        lines.append("")
        if file.imports:
            lines.append("Imports: " + ", ".join(f"`{name}`" for name in file.imports))
            lines.append("")
        lines.extend(
            table(
                ("Kind", "Name", "Signature", "Line"),
                [
                    (item.kind, item.name, item.signature, str(item.line))
                    for item in file.items
                ],
            )
        )

    lines.append("")
    return "\n".join(lines)


def module_index_row(file: StdlibFile) -> tuple[str, ...]:
    counts = Counter(item.kind for item in file.items)
    runtime_flags = [
        item.name
        for item in file.items
        if item.kind == "const" and ("HAS_" in item.name or item.name.endswith("_API_AVAILABLE"))
    ]
    return (
        file.layer,
        file.module,
        file.path.as_posix(),
        str(len(file.imports)),
        str(len(file.items)),
        str(counts["const"]),
        str(counts["type"]),
        str(counts["fn"]),
        str(counts["extern fn"]),
        str(counts["enum"]),
        str(counts["struct"]),
        str(counts["trait"]),
        str(counts["impl"]),
        ", ".join(runtime_flags) if runtime_flags else "-",
    )


def sorted_counter(counter: Counter[str]) -> list[tuple[str, int]]:
    return sorted(counter.items(), key=lambda item: (-item[1], item[0]))


def table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    lines = [
        "| " + " | ".join(escape_cell(header) for header in headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    if not rows:
        lines.append("| " + " | ".join("none" for _ in headers) + " |")
        return lines
    for row in rows:
        lines.append("| " + " | ".join(escape_cell(cell) for cell in row) + " |")
    return lines


def escape_cell(value: str) -> str:
    return value.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").strip()


if __name__ == "__main__":
    raise SystemExit(main())
