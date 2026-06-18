#!/usr/bin/env python3
"""Generate compiler-internals reference tables from the current repo."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


EXCLUDED_DIRS = {
    ".git",
    ".cargo",
    ".vscode",
    ".VSCodeCounter",
    "__pycache__",
    "target",
}

MAIN_SHADER_ROOTS = {"lexer", "parser", "type_checker", "codegen"}


@dataclass(frozen=True)
class ShaderUse:
    owner: str
    kind: str
    name: str
    label: str
    shader: str
    file: Path
    line: int


@dataclass(frozen=True)
class PublicFn:
    name: str
    visibility: str
    asyncness: str
    file: Path
    line: int
    signature: str


@dataclass(frozen=True)
class BufferStruct:
    name: str
    file: Path
    line: int
    fields: int
    lanius_buffers: int
    owned_wgpu_buffers: int
    borrowed_wgpu_buffers: int
    option_borrowed_wgpu_buffers: int


@dataclass(frozen=True)
class TypeCheckRecordSite:
    order: int
    pass_name: str
    file: Path
    line: int
    call: str


@dataclass(frozen=True)
class RustDocItem:
    kind: str
    name: str
    visibility: str
    documented: bool
    file: Path
    line: int


@dataclass(frozen=True)
class DiagnosticCode:
    code: str
    title: str
    category: str
    primary_label_policy: str
    file: Path
    line: int


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate compiler reference tables from Rust and shader sources."
    )
    parser.add_argument("--output", help="write Markdown output to this path")
    parser.add_argument(
        "--check",
        help="compare generated Markdown with this path and exit nonzero if stale",
    )
    args = parser.parse_args()

    repo = repo_root()
    files = list_repo_files(repo)
    markdown = render_inventory(repo, files)

    if args.check:
        target = Path(args.check)
        try:
            current = target.read_text(encoding="utf-8")
        except FileNotFoundError:
            sys.stderr.write(f"compiler_inventory: missing generated file {target}\n")
            return 1
        if current != markdown:
            sys.stderr.write(f"compiler_inventory: generated output is stale: {target}\n")
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


def list_repo_files(repo: Path) -> list[Path]:
    paths: list[Path] = []
    for root, dirs, names in os.walk(repo):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
        root_path = Path(root)
        for name in sorted(names):
            paths.append(root_path.joinpath(name).relative_to(repo))
    return paths


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def render_inventory(repo: Path, files: list[Path]) -> str:
    rust_files = [path for path in files if path.suffix == ".rs"]
    shader_keys = shader_source_keys(files)
    shader_entrypoints = shader_compute_entrypoints(repo, shader_keys)
    shader_imports = shader_import_edges(repo, shader_keys)
    shader_uses = rust_shader_uses(repo, rust_files)
    typecheck_loads = [use for use in shader_uses if use.kind == "type-check loader"]
    typecheck_load_by_name = {use.name: use for use in typecheck_loads}
    record_sites = typecheck_record_sites(repo, rust_files)
    public_fns = public_compiler_functions(repo, rust_files)
    buffer_structs = buffer_carrier_structs(repo, rust_files)
    large_structs = large_struct_inventory(repo, rust_files)
    rustdoc_items = rustdoc_public_items(repo, rust_files)
    undocumented_rustdoc_items = [item for item in rustdoc_items if not item.documented]
    rustdoc_area_rows = rustdoc_coverage_by_area(rustdoc_items)
    documented_rustdoc_locations = {
        (item.file, item.line, item.kind, item.name)
        for item in rustdoc_items
        if item.documented
    }
    undocumented_public_fns = [
        fn
        for fn in public_fns
        if (fn.file, fn.line, "fn", fn.name) not in documented_rustdoc_locations
    ]
    typecheck_codes = gpu_typecheck_codes(repo)
    x86_status_codes = x86_error_constants(repo)
    parser_status_words = parser_status_layout(repo)
    diagnostic_codes = stable_diagnostic_codes(repo)

    referenced_shader_keys = {use.shader for use in shader_uses}
    missing_shader_refs = sorted(key for key in referenced_shader_keys if key not in shader_keys)
    unreferenced_entrypoints = sorted(
        key for key in shader_entrypoints if key not in referenced_shader_keys
    )

    lines: list[str] = [
        "# Generated Compiler Reference",
        "",
        "Generated by `tools/compiler_inventory.py` from current Rust and Slang sources.",
        "Regenerate this file instead of editing it by hand.",
        "",
        "```bash",
        "tools/compiler_inventory.py --output docs/compiler/generated/reference.md",
        "tools/compiler_inventory.py --check docs/compiler/generated/reference.md",
        "```",
        "",
        "## Inventory Summary",
        "",
    ]
    lines.extend(
        table(
            ("Item", "Count"),
            [
                ("Rust files scanned", str(len(rust_files))),
                ("Shader source files", str(len(shader_keys))),
                ("Compute shader entrypoints", str(len(shader_entrypoints))),
                ("Rust shader load sites", str(len(shader_uses))),
                ("Type-check pass loader entries", str(len(typecheck_loads))),
                ("Type-check record sites", str(len(record_sites))),
                ("Public compiler functions", str(len(public_fns))),
                ("Rustdoc-visible Rust items", str(len(rustdoc_items))),
                ("Undocumented Rustdoc-visible Rust items", str(len(undocumented_rustdoc_items))),
                ("Undocumented public compiler functions", str(len(undocumented_public_fns))),
                ("Buffer carrier structs", str(len(buffer_structs))),
                ("Structs with more than 20 fields", str(len(large_structs))),
                ("Stable diagnostic codes", str(len(diagnostic_codes))),
                ("GPU type-check status codes", str(len(typecheck_codes))),
                ("x86 backend status constants", str(len(x86_status_codes))),
            ],
        )
    )

    lines.extend(["", "## Public Compiler Entry Points", ""])
    lines.extend(
        table(
            ("Function", "Visibility", "File", "Signature"),
            [
                (
                    fn.name,
                    " ".join(part for part in (fn.visibility, fn.asyncness) if part),
                    location(fn.file, fn.line),
                    fn.signature,
                )
                for fn in public_fns
            ],
        )
    )

    lines.extend(["", "## Rustdoc Coverage", ""])
    lines.append(
        "This is a heuristic over public, crate-public, and scoped-public Rust items in `crates/laniusc-compiler/src`. It tracks where `cargo doc -p laniusc-compiler --no-deps --document-private-items` is likely to show signatures without nearby explanatory comments."
    )
    lines.append("")
    lines.extend(
        table(
            ("Area", "Items", "Documented", "Undocumented", "Coverage"),
            rustdoc_area_rows,
        )
    )

    lines.extend(["", "### Undocumented Public Compiler Functions", ""])
    lines.extend(
        table(
            ("Function", "File", "Signature"),
            [
                (fn.name, location(fn.file, fn.line), fn.signature)
                for fn in undocumented_public_fns
            ],
        )
    )

    lines.extend(["", "## Shader Groups", ""])
    shader_group_rows = []
    file_counts = Counter(shader_group(key) for key in shader_keys)
    entry_counts = Counter(shader_group(key) for key in shader_entrypoints)
    for group, count in sorted(file_counts.items(), key=lambda item: (-item[1], item[0])):
        shader_group_rows.append((group, str(count), str(entry_counts[group])))
    lines.extend(table(("Shader group", "Files", "Compute entrypoints"), shader_group_rows))

    lines.extend(["", "## Shader Import Coupling", ""])
    lines.extend(
        table(
            ("From shader group", "To shader group", "Imports"),
            [
                (left, right, str(count))
                for (left, right), count in sorted(
                    shader_imports.items(), key=lambda item: (-item[1], item[0][0], item[0][1])
                )
            ],
        )
    )

    lines.extend(["", "## Rust Shader Load Sites", ""])
    lines.extend(
        table(
            ("Owner", "Kind", "Name", "Shader", "File"),
            [
                (
                    use.owner,
                    use.kind,
                    use.name or use.label,
                    shader_cell(use.shader, shader_keys, shader_entrypoints),
                    location(use.file, use.line),
                )
                for use in sorted(
                    shader_uses,
                    key=lambda use: (use.owner, use.kind, use.file.as_posix(), use.line, use.name),
                )
            ],
        )
    )

    lines.extend(["", "## Type-Check Pass Loader Catalog", ""])
    lines.extend(
        table(
            ("Field", "Label", "Shader", "File"),
            [
                (
                    use.name,
                    use.label,
                    shader_cell(use.shader, shader_keys, shader_entrypoints),
                    location(use.file, use.line),
                )
                for use in sorted(typecheck_loads, key=lambda use: use.name)
            ],
        )
    )

    lines.extend(["", "## Type-Check Record Sites", ""])
    lines.append(
        "This is source-order extraction from `type_checker/resident.rs` and `type_checker/record/*.rs`; use it to find recorders, not as a complete interprocedural execution trace."
    )
    lines.append("")
    record_rows = []
    for site in record_sites:
        loaded = typecheck_load_by_name.get(site.pass_name)
        shader = shader_cell(loaded.shader, shader_keys, shader_entrypoints) if loaded else "not found"
        record_rows.append(
            (
                str(site.order),
                site.pass_name,
                site.call,
                shader,
                location(site.file, site.line),
            )
        )
    lines.extend(table(("Source order", "Pass field", "Call", "Shader", "File"), record_rows))

    lines.extend(["", "## Buffer Carrier Structs", ""])
    lines.extend(
        table(
            (
                "Struct",
                "Fields",
                "LaniusBuffer",
                "owned wgpu::Buffer",
                "borrowed wgpu::Buffer",
                "Option borrowed",
                "File",
            ),
            [
                (
                    item.name,
                    str(item.fields),
                    str(item.lanius_buffers),
                    str(item.owned_wgpu_buffers),
                    str(item.borrowed_wgpu_buffers),
                    str(item.option_borrowed_wgpu_buffers),
                    location(item.file, item.line),
                )
                for item in buffer_structs
            ],
        )
    )

    lines.extend(["", "## Large Structs", ""])
    lines.append("Structs with more than 20 fields are listed because they are high-friction edit surfaces.")
    lines.append("")
    lines.extend(
        table(
            ("Struct", "Fields", "File"),
            [(name, str(count), location(path, line)) for name, count, path, line in large_structs],
        )
    )

    lines.extend(["", "## Stable Diagnostic Codes", ""])
    lines.append(
        "Extracted from `DIAGNOSTIC_CODE_REGISTRY`; use this as the docs-side analogue of a rustc error-code index. For full JSON metadata, use `laniusc diagnostics codes` or `laniusc diagnostics explain CODE`."
    )
    lines.append("")
    lines.extend(
        table(
            ("Code", "Title", "Category", "Primary label", "File"),
            [
                (
                    code.code,
                    code.title,
                    code.category,
                    code.primary_label_policy,
                    location(code.file, code.line),
                )
                for code in diagnostic_codes
            ],
        )
    )

    lines.extend(["", "## GPU Type-Check Status Codes", ""])
    lines.extend(table(("Code", "Name"), [(str(code), name) for code, name in typecheck_codes]))

    lines.extend(["", "## Parser LL Status Words", ""])
    lines.extend(
        table(
            ("Word", "Field", "Meaning"),
            [(str(index), field, meaning) for index, field, meaning in parser_status_words],
        )
    )

    lines.extend(["", "## x86 Backend Status Constants", ""])
    lines.extend(table(("Code", "Name"), [(str(code), name) for code, name in x86_status_codes]))

    lines.extend(["", "## Reference Health Checks", ""])
    lines.extend(
        table(
            ("Check", "Result"),
            [
                ("Rust shader references missing a shader source", comma_list(missing_shader_refs)),
                (
                    "Compute shader entrypoints not found by recognized Rust literal patterns",
                    comma_list(unreferenced_entrypoints),
                ),
            ],
        )
    )

    lines.append("")
    return "\n".join(lines)


def shader_source_keys(files: list[Path]) -> set[str]:
    keys = set()
    for path in files:
        if len(path.parts) >= 2 and path.parts[0] == "shaders" and path.suffix == ".slang":
            keys.add(path.with_suffix("").as_posix().removeprefix("shaders/"))
    return keys


def shader_compute_entrypoints(repo: Path, shader_keys: set[str]) -> set[str]:
    entrypoints = set()
    for key in shader_keys:
        text = read_text(repo / "shaders" / f"{key}.slang")
        if '[shader("compute")]' in text or "[shader('compute')]" in text:
            entrypoints.add(key)
    return entrypoints


def shader_group(key: str) -> str:
    parts = key.split("/")
    if not parts:
        return key
    if parts[0] in MAIN_SHADER_ROOTS and len(parts) > 1:
        return "/".join(parts[:2])
    return parts[0]


def shader_import_edges(repo: Path, shader_keys: set[str]) -> Counter[tuple[str, str]]:
    edges: Counter[tuple[str, str]] = Counter()
    import_line = re.compile(r"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)\s*;")
    for key in sorted(shader_keys):
        source_group = shader_group(key)
        text = read_text(repo / "shaders" / f"{key}.slang")
        for import_name in import_line.findall(text):
            target_key = resolve_shader_import(import_name, key, shader_keys)
            target_group = shader_group(target_key)
            if target_group != source_group:
                edges[(source_group, target_group)] += 1
    return edges


def resolve_shader_import(import_name: str, source_key: str, shader_keys: set[str]) -> str:
    import_key = import_name.replace(".", "/")
    source_top = source_key.split("/", 1)[0]
    candidates = [
        import_key,
        f"{source_top}/{import_key}",
        f"lexer/{import_key}",
        f"parser/{import_key}",
        f"type_checker/{import_key}",
        f"codegen/{import_key}",
    ]
    for candidate in candidates:
        if candidate in shader_keys:
            return candidate
    return import_key


def rust_area(path: Path) -> str:
    parts = path.parts
    if len(parts) < 4 or parts[:3] != ("crates", "laniusc-compiler", "src"):
        return "other"
    if parts[3].endswith(".rs"):
        return Path(parts[3]).stem
    return parts[3]


def rust_shader_uses(repo: Path, rust_files: list[Path]) -> list[ShaderUse]:
    uses: list[ShaderUse] = []
    patterns = [
        (
            "type-check loader",
            re.compile(
                r"(?ms)([A-Za-z_][A-Za-z0-9_]*)\s*:\s*pass!\(\s*\"([^\"]+)\"\s*,\s*\"([^\"]+)\"\s*\)"
            ),
            lambda match: (match.group(1), match.group(2), match.group(3)),
        ),
        (
            "static pass",
            re.compile(
                r"(?ms)impl_static_shader_pass!\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*label:\s*\"([^\"]+)\".*?shader:\s*\"([^\"]+)\""
            ),
            lambda match: (match.group(1), match.group(2), match.group(3)),
        ),
        (
            "main pass",
            re.compile(
                r"(?ms)make_main_pass!\(\s*[^,]+,\s*\"([^\"]+)\"\s*,\s*shader:\s*\"([^\"]+)\""
            ),
            lambda match: ("", match.group(1), match.group(2)),
        ),
        (
            "artifact literal",
            re.compile(r"\"([A-Za-z0-9_./-]+)\.spv\""),
            lambda match: ("", "", match.group(1)),
        ),
    ]
    seen = set()
    for path in rust_files:
        text = read_text(repo / path)
        for kind, pattern, unpack in patterns:
            for match in pattern.finditer(text):
                name, label, shader = unpack(match)
                if not real_shader_key(shader):
                    continue
                key = (path, match.start(), kind, name, label, shader)
                if key in seen:
                    continue
                seen.add(key)
                uses.append(
                    ShaderUse(
                        owner=rust_area(path),
                        kind=kind,
                        name=name,
                        label=label,
                        shader=shader,
                        file=path,
                        line=line_for_offset(text, match.start()),
                    )
                )
    return uses


def real_shader_key(shader: str) -> bool:
    return "{" not in shader and "}" not in shader and "$" not in shader


def typecheck_record_sites(repo: Path, rust_files: list[Path]) -> list[TypeCheckRecordSite]:
    interesting = [
        path
        for path in rust_files
        if path.as_posix() == "crates/laniusc-compiler/src/type_checker/resident.rs"
        or path.as_posix().startswith("crates/laniusc-compiler/src/type_checker/record/")
    ]
    pattern = re.compile(
        r"(?ms)(record_compute(?:_indirect(?:_offset)?)?)\s*\([^;]*?&(?:self\.)?passes\.([A-Za-z_][A-Za-z0-9_]*)"
    )
    sites: list[TypeCheckRecordSite] = []
    order = 1
    for path in sorted(interesting):
        text = read_text(repo / path)
        for match in pattern.finditer(text):
            sites.append(
                TypeCheckRecordSite(
                    order=order,
                    pass_name=match.group(2),
                    file=path,
                    line=line_for_offset(text, match.start()),
                    call=match.group(1),
                )
            )
            order += 1
    return sites


def public_compiler_functions(repo: Path, rust_files: list[Path]) -> list[PublicFn]:
    exact_files = {
        "crates/laniusc-compiler/src/compiler/gpu_compiler.rs",
        "crates/laniusc-compiler/src/compiler/gpu_compiler/benchmarks.rs",
        "crates/laniusc-compiler/src/compiler/gpu_compiler/descriptor_work_queue.rs",
        "crates/laniusc-compiler/src/compiler/gpu_compiler/typecheck.rs",
        "crates/laniusc-compiler/src/compiler/gpu_compiler/wasm_codegen.rs",
        "crates/laniusc-compiler/src/compiler/gpu_compiler/x86_codegen.rs",
        "crates/laniusc-compiler/src/compiler/gpu_public_api.rs",
        "crates/laniusc-compiler/src/compiler/public_execution_api.rs",
        "crates/laniusc-compiler/src/compiler/public_planning_api.rs",
    }
    prefixes = (
        "crates/laniusc-compiler/src/compiler/public_execution_api/",
        "crates/laniusc-compiler/src/compiler/public_planning_api/",
    )
    relevant = [
        path
        for path in rust_files
        if path.as_posix() in exact_files
        or any(path.as_posix().startswith(prefix) for prefix in prefixes)
    ]
    pattern = re.compile(
        r"(?ms)^\s*(pub(?:\([^)]*\))?)\s+(async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)(\s*<[^({;]*>)?\s*\((.*?)\)\s*(?:->\s*([^\{\;]+))?"
    )
    result: list[PublicFn] = []
    for path in sorted(relevant):
        text = read_text(repo / path)
        for match in pattern.finditer(text):
            if match.group(1) != "pub":
                continue
            generics = compact_ws(match.group(4) or "")
            args = compact_ws(match.group(5))
            ret = compact_ws(match.group(6) or "")
            signature = f"{match.group(3)}{generics}({args})"
            if ret:
                signature += f" -> {ret}"
            result.append(
                PublicFn(
                    name=match.group(3),
                    visibility=match.group(1),
                    asyncness=(match.group(2) or "").strip(),
                    file=path,
                    line=line_for_offset(text, match.start()),
                    signature=signature,
                )
            )
    return sorted(result, key=lambda fn: (fn.file.as_posix(), fn.line, fn.name))


def rustdoc_public_items(repo: Path, rust_files: list[Path]) -> list[RustDocItem]:
    result: list[RustDocItem] = []
    pattern = re.compile(
        r"(?m)^\s*(pub(?:\([^)]*\))?)\s+(?:async\s+)?(struct|enum|trait|fn|mod|type|const|static)\s+([A-Za-z_][A-Za-z0-9_]*)"
    )
    for path in sorted(rust_files):
        parts = path.parts
        if len(parts) < 4 or parts[:3] != ("crates", "laniusc-compiler", "src"):
            continue
        if len(parts) > 3 and parts[3] == "bin":
            continue
        text = read_text(repo / path)
        for match in pattern.finditer(text):
            result.append(
                RustDocItem(
                    kind=match.group(2),
                    name=match.group(3),
                    visibility=match.group(1),
                    documented=has_rustdoc_comment(text, match.start()),
                    file=path,
                    line=line_for_offset(text, match.start()),
                )
            )
    return result


def rustdoc_coverage_by_area(items: list[RustDocItem]) -> list[tuple[str, str, str, str, str]]:
    totals: Counter[str] = Counter()
    documented: Counter[str] = Counter()
    for item in items:
        area = rust_area(item.file)
        totals[area] += 1
        if item.documented:
            documented[area] += 1
    rows = []
    for area, total in sorted(totals.items(), key=lambda item: (-item[1], item[0])):
        doc_count = documented[area]
        undoc_count = total - doc_count
        rows.append(
            (
                area,
                str(total),
                str(doc_count),
                str(undoc_count),
                percent(doc_count, total),
            )
        )
    return rows


def percent(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "n/a"
    return f"{(numerator / denominator) * 100:.1f}%"


def has_rustdoc_comment(text: str, start: int) -> bool:
    lines = text[:start].splitlines()
    index = len(lines) - 1
    while index >= 0:
        stripped = lines[index].strip()
        if not stripped or stripped.startswith("#[") or stripped.startswith("#!"):
            index -= 1
            continue
        return stripped.startswith("///") or stripped.startswith("/**")
    return False


def buffer_carrier_structs(repo: Path, rust_files: list[Path]) -> list[BufferStruct]:
    structs: list[BufferStruct] = []
    for path in rust_files:
        text = read_text(repo / path)
        for name, line, body in struct_bodies(text):
            field_types = struct_field_types(body)
            lanius = sum("LaniusBuffer<" in ty for ty in field_types)
            owned_wgpu = sum("wgpu::Buffer" in ty and "&" not in ty for ty in field_types)
            borrowed_wgpu = sum("wgpu::Buffer" in ty and "&" in ty for ty in field_types)
            option_borrowed = sum("Option<" in ty and "&" in ty and "wgpu::Buffer" in ty for ty in field_types)
            if lanius or owned_wgpu or borrowed_wgpu:
                structs.append(
                    BufferStruct(
                        name=name,
                        file=path,
                        line=line,
                        fields=len(field_types),
                        lanius_buffers=lanius,
                        owned_wgpu_buffers=owned_wgpu,
                        borrowed_wgpu_buffers=borrowed_wgpu,
                        option_borrowed_wgpu_buffers=option_borrowed,
                    )
                )
    return sorted(
        structs,
        key=lambda item: (-item.fields, item.file.as_posix(), item.line, item.name),
    )


def large_struct_inventory(repo: Path, rust_files: list[Path]) -> list[tuple[str, int, Path, int]]:
    large: list[tuple[str, int, Path, int]] = []
    for path in rust_files:
        text = read_text(repo / path)
        for name, line, body in struct_bodies(text):
            field_count = len(struct_field_types(body))
            if field_count > 20:
                large.append((name, field_count, path, line))
    return sorted(large, key=lambda item: (-item[1], item[2].as_posix(), item[3], item[0]))


def struct_bodies(text: str) -> list[tuple[str, int, str]]:
    pattern = re.compile(
        r"(?ms)^\s*(?:#\[[^\]]+\]\s*)*(?:pub(?:\([^)]*\))?\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)(?:<[^>{}]*>)?\s*\{(.*?)^\s*\}"
    )
    return [
        (match.group(1), line_for_offset(text, match.start()), match.group(2))
        for match in pattern.finditer(text)
    ]


def struct_field_types(body: str) -> list[str]:
    fields: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or ":" not in stripped:
            continue
        if stripped.startswith("#["):
            continue
        match = re.match(
            r"(?:pub(?:\([^)]*\))?\s+)?[A-Za-z_][A-Za-z0-9_]*\s*:\s*(.+?),?\s*$",
            stripped,
        )
        if match:
            fields.append(match.group(1).rstrip(","))
    return fields


def gpu_typecheck_codes(repo: Path) -> list[tuple[int, str]]:
    text = read_text(repo / "crates/laniusc-compiler/src/type_checker/mod.rs")
    matches = re.findall(r"(\d+)\s*=>\s*Self::([A-Za-z_][A-Za-z0-9_]*)", text)
    return sorted((int(code), name) for code, name in matches)


def x86_error_constants(repo: Path) -> list[tuple[int, str]]:
    text = read_text(repo / "crates/laniusc-compiler/src/codegen/x86.rs")
    matches = re.findall(r"const\s+(X86_ERR_[A-Za-z0-9_]+)\s*:\s*u32\s*=\s*(\d+)\s*;", text)
    return sorted((int(code), name) for name, code in matches)


def parser_status_layout(repo: Path) -> list[tuple[int, str, str]]:
    text = read_text(repo / "crates/laniusc-compiler/src/parser/driver/results.rs")
    field_matches = re.findall(
        r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*words\[(\d+)\](?:\s*!=\s*0)?",
        text,
    )
    meanings = {
        "accepted": "nonzero when LL/HIR construction accepted the stream",
        "error_pos": "token position used as the primary syntax-error location",
        "error_code": "parser status code emitted by shader/table logic",
        "detail": "status-specific detail word",
        "steps": "LL/action step count",
        "emit_len": "production/HIR emission length used for active capacity",
    }
    rows = []
    for field, index in field_matches:
        rows.append((int(index), field, meanings.get(field, "")))
    return sorted(rows)


def stable_diagnostic_codes(repo: Path) -> list[DiagnosticCode]:
    path = Path("crates/laniusc-compiler/src/compiler/diagnostics.rs")
    text = read_text(repo / path)
    pattern = re.compile(
        r'(?ms)DiagnosticCodeInfo::error\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*DiagnosticPrimaryLabelPolicy::([A-Za-z_][A-Za-z0-9_]*)\s*,?\s*\)'
    )
    rows = []
    for match in pattern.finditer(text):
        rows.append(
            DiagnosticCode(
                code=match.group(1),
                title=match.group(2),
                category=match.group(3),
                primary_label_policy=match.group(4),
                file=path,
                line=line_for_offset(text, match.start()),
            )
        )
    return sorted(rows, key=lambda row: row.code)


def shader_cell(shader: str, shader_keys: set[str], shader_entrypoints: set[str]) -> str:
    if shader not in shader_keys:
        return f"{shader} (missing source)"
    if shader not in shader_entrypoints:
        return f"{shader} (no compute entrypoint)"
    return shader


def line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def compact_ws(value: str) -> str:
    return " ".join(value.split())


def location(path: Path, line: int) -> str:
    return f"{path.as_posix()}:{line}"


def comma_list(values: list[str]) -> str:
    if not values:
        return "none"
    return ", ".join(values)


def table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    if not rows:
        lines.append("| " + " | ".join("`none`" for _ in headers) + " |")
        return lines
    for row in rows:
        lines.append("| " + " | ".join(md_code(cell) for cell in row) + " |")
    return lines


def md_code(value: str) -> str:
    return "`" + value.replace("`", "'").replace("|", "\\|") + "`"


if __name__ == "__main__":
    raise SystemExit(main())
