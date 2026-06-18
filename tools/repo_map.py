#!/usr/bin/env python3
import argparse
import html
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


EXCLUDED_DIRS = {".git", ".cargo", ".vscode", ".VSCodeCounter", "target"}
MAIN_SHADER_ROOTS = {"lexer", "parser", "type_checker", "codegen"}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a current repo navigation map from code relationships."
    )
    parser.add_argument("--output", help="write Markdown output to this path")
    parser.add_argument("--svg", help="write Graphviz SVG image to this path")
    parser.add_argument("--png", help="write Graphviz PNG image to this path")
    parser.add_argument(
        "--edge-limit",
        type=int,
        default=80,
        help="maximum edges of each dependency kind to include in image output",
    )
    args = parser.parse_args()

    repo = repo_root()
    files = list_repo_files(repo)
    rust_modules = rust_top_modules(repo)
    rust_file_counts = count_rust_area_files(files)
    shader_files = shader_source_keys(files)
    shader_file_counts = count_shader_group_files(shader_files)
    shader_entrypoint_counts = count_shader_entrypoints(repo, shader_files)

    rust_edges = rust_module_edges(repo, files, rust_modules)
    rust_shader_edges = rust_owned_shader_edges(repo, files)
    shader_edges = shader_import_edges(repo, shader_files)
    test_edges = test_affinity_edges(files, rust_modules)
    largest_areas = largest_directory_areas(files)

    report = markdown_report(
        rust_edges=rust_edges,
        rust_shader_edges=rust_shader_edges,
        shader_edges=shader_edges,
        test_edges=test_edges,
        largest_areas=largest_areas,
        rust_file_counts=rust_file_counts,
        shader_file_counts=shader_file_counts,
        shader_entrypoint_counts=shader_entrypoint_counts,
    )

    if args.output:
        write_text(Path(args.output), report)
    elif not args.svg and not args.png:
        sys.stdout.write(report)

    if args.svg or args.png:
        dot = dot_graph(
            rust_edges=rust_edges,
            rust_shader_edges=rust_shader_edges,
            shader_edges=shader_edges,
            test_edges=test_edges,
            rust_file_counts=rust_file_counts,
            shader_file_counts=shader_file_counts,
            shader_entrypoint_counts=shader_entrypoint_counts,
            edge_limit=args.edge_limit,
        )
        render_dot(dot, svg=args.svg, png=args.png)

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
    files: list[Path] = []
    for root, dirs, names in os.walk(repo):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
        root_path = Path(root)
        for name in sorted(names):
            files.append(root_path.joinpath(name).relative_to(repo))
    return files


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def rust_top_modules(repo: Path) -> set[str]:
    lib = repo / "crates/laniusc-compiler/src/lib.rs"
    modules = set(re.findall(r"(?m)^\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;", read_text(lib)))
    src = repo / "crates/laniusc-compiler/src"
    if src.exists():
        for path in src.iterdir():
            if path.is_dir():
                modules.add(path.name)
            elif path.suffix == ".rs" and path.name != "lib.rs":
                modules.add(path.stem)
    return modules


def rust_area(path: Path) -> str | None:
    parts = path.parts
    if len(parts) < 4 or parts[:3] != ("crates", "laniusc-compiler", "src"):
        return None
    if parts[3] == "lib.rs":
        return None
    if parts[3].endswith(".rs"):
        return Path(parts[3]).stem
    return parts[3]


def count_rust_area_files(files: list[Path]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for path in files:
        if path.suffix != ".rs":
            continue
        area = rust_area(path)
        if area:
            counts[area] += 1
    return counts


def rust_module_edges(repo: Path, files: list[Path], modules: set[str]) -> Counter[tuple[str, str]]:
    edges: Counter[tuple[str, str]] = Counter()
    crate_path = re.compile(r"\b\$?crate::([A-Za-z_][A-Za-z0-9_]*)")
    grouped_use = re.compile(r"\buse\s+crate::\{(.*?)\};", re.S)

    for rel_path in files:
        if rel_path.suffix != ".rs":
            continue
        source = rust_area(rel_path)
        if source is None:
            continue
        text = strip_rust_line_comments(read_text(repo / rel_path))
        targets = Counter()

        for target in crate_path.findall(text):
            if target in modules:
                targets[target] += 1

        for match in grouped_use.finditer(text):
            body = match.group(1)
            for target in modules:
                pattern = rf"(?<![A-Za-z0-9_]){re.escape(target)}\s*(?:::|,|\{{)"
                if re.search(pattern, body):
                    targets[target] += 1

        for target, count in targets.items():
            if target != source:
                edges[(source, target)] += count

    return edges


def strip_rust_line_comments(text: str) -> str:
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def shader_source_keys(files: list[Path]) -> set[str]:
    keys = set()
    for path in files:
        if len(path.parts) >= 2 and path.parts[0] == "shaders" and path.suffix == ".slang":
            keys.add(path.with_suffix("").as_posix().removeprefix("shaders/"))
    return keys


def shader_group(key: str) -> str:
    parts = key.split("/")
    if not parts:
        return key
    if parts[0] in MAIN_SHADER_ROOTS and len(parts) > 1:
        return "/".join(parts[:2])
    return parts[0]


def count_shader_group_files(shader_keys: set[str]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for key in shader_keys:
        counts[shader_group(key)] += 1
    return counts


def count_shader_entrypoints(repo: Path, shader_keys: set[str]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for key in shader_keys:
        text = read_text(repo / "shaders" / f"{key}.slang")
        if '[shader("compute")]' in text or "[shader('compute')]" in text:
            counts[shader_group(key)] += 1
    return counts


def rust_owned_shader_edges(repo: Path, files: list[Path]) -> Counter[tuple[str, str]]:
    edges: Counter[tuple[str, str]] = Counter()
    shader_literal = re.compile(r'shader:\s*"([^"]+)"')
    spv_literal = re.compile(r'"([^"]+)\.spv"')

    for rel_path in files:
        if rel_path.suffix != ".rs":
            continue
        source = rust_area(rel_path)
        if source is None:
            continue
        text = read_text(repo / rel_path)
        for shader in shader_literal.findall(text):
            if not real_shader_key(shader):
                continue
            edges[(source, shader_group(shader))] += 1
        for shader in spv_literal.findall(text):
            if not real_shader_key(shader):
                continue
            edges[(source, shader_group(shader))] += 1

    return edges


def real_shader_key(shader: str) -> bool:
    return "{" not in shader and "}" not in shader and "$" not in shader


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


def test_affinity_edges(files: list[Path], rust_modules: set[str]) -> Counter[tuple[str, str]]:
    candidates = set(rust_modules) | {"stdlib", "sample_programs", "package", "source_pack"}
    edges: Counter[tuple[str, str]] = Counter()
    for path in files:
        if len(path.parts) < 2 or path.parts[0] != "tests":
            continue
        if path.suffix != ".rs":
            continue
        if len(path.parts) > 2:
            test_group = path.parts[1]
        else:
            test_group = path.stem
        target = infer_named_area(test_group, candidates)
        edges[(test_group, target)] += 1
    return edges


def infer_named_area(name: str, candidates: set[str]) -> str:
    best = ""
    for candidate in candidates:
        if name == candidate or name.startswith(f"{candidate}_"):
            if len(candidate) > len(best):
                best = candidate
    if best:
        return best
    return name.split("_", 1)[0]


def largest_directory_areas(files: list[Path]) -> list[tuple[str, int]]:
    counts: Counter[str] = Counter()
    for path in files:
        parts = path.parts
        for depth in range(1, len(parts)):
            counts["/".join(parts[:depth])] += 1
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:20]


def markdown_report(
    *,
    rust_edges: Counter[tuple[str, str]],
    rust_shader_edges: Counter[tuple[str, str]],
    shader_edges: Counter[tuple[str, str]],
    test_edges: Counter[tuple[str, str]],
    largest_areas: list[tuple[str, int]],
    rust_file_counts: Counter[str],
    shader_file_counts: Counter[str],
    shader_entrypoint_counts: Counter[str],
) -> str:
    lines = [
        "# Repository Map",
        "",
        "Generated by `tools/repo_map.py` from current Rust references, shader imports, shader pass ownership, tests, and file layout.",
        "Regenerate this output instead of editing it by hand.",
        "",
        "## Rust Module Coupling",
    ]
    lines.extend(edge_table(("From", "To", "References"), rust_edges, limit=40))
    lines.extend(["", "## Rust-Owned Shader Groups"])
    lines.extend(edge_table(("Rust area", "Shader group", "Entrypoints loaded"), rust_shader_edges, limit=50))
    lines.extend(["", "## Shader Import Coupling"])
    lines.extend(edge_table(("From shader group", "To shader group", "Imports"), shader_edges, limit=50))
    lines.extend(["", "## Test Affinity"])
    lines.extend(edge_table(("Test group", "Inferred target", "Files"), test_edges, limit=50))
    lines.extend(["", "## Rust Areas"])
    lines.extend(count_table(("Area", "Rust files"), rust_file_counts, limit=30))
    lines.extend(["", "## Shader Groups"])
    lines.extend(shader_count_table(shader_file_counts, shader_entrypoint_counts, limit=40))
    lines.extend(["", "## Largest Directories"])
    lines.extend(simple_table(("Area", "Files"), [(area, str(count)) for area, count in largest_areas]))
    lines.append("")
    return "\n".join(lines)


def edge_table(headers: tuple[str, str, str], edges: Counter[tuple[str, str]], limit: int) -> list[str]:
    rows = [(left, right, str(count)) for left, right, count in sorted_counter(edges)[:limit]]
    return simple_table(headers, rows)


def count_table(headers: tuple[str, str], counts: Counter[str], limit: int) -> list[str]:
    rows = [(name, str(count)) for name, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:limit]]
    return simple_table(headers, rows)


def shader_count_table(
    file_counts: Counter[str],
    entrypoint_counts: Counter[str],
    limit: int,
) -> list[str]:
    rows = []
    for group, count in sorted(file_counts.items(), key=lambda item: (-item[1], item[0]))[:limit]:
        rows.append((group, str(count), str(entrypoint_counts[group])))
    return simple_table(("Shader group", "Files", "Entrypoints"), rows)


def simple_table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(f"`{cell}`" for cell in row) + " |")
    if not rows:
        lines.append("| " + " | ".join("`none`" for _ in headers) + " |")
    return lines


def sorted_counter(counter: Counter[tuple[str, str]]) -> list[tuple[str, str, int]]:
    return [
        (left, right, count)
        for (left, right), count in sorted(counter.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
    ]


def dot_graph(
    *,
    rust_edges: Counter[tuple[str, str]],
    rust_shader_edges: Counter[tuple[str, str]],
    shader_edges: Counter[tuple[str, str]],
    test_edges: Counter[tuple[str, str]],
    rust_file_counts: Counter[str],
    shader_file_counts: Counter[str],
    shader_entrypoint_counts: Counter[str],
    edge_limit: int,
) -> str:
    image_shader_file_counts = aggregate_shader_counts(shader_file_counts)
    image_shader_entrypoint_counts = aggregate_shader_counts(shader_entrypoint_counts)
    image_rust_shader_edges = aggregate_edges(
        rust_shader_edges,
        left_fn=lambda value: value,
        right_fn=image_shader_group,
    )
    image_shader_edges = aggregate_edges(
        shader_edges,
        left_fn=image_shader_group,
        right_fn=image_shader_group,
        drop_self=True,
    )
    image_test_edges = aggregate_test_edges_for_image(test_edges)

    rust_nodes = set(rust_file_counts)
    shader_nodes = set(image_shader_file_counts)
    test_nodes = {source for source, _ in image_test_edges}

    lines = [
        "digraph repo_map {",
        '  graph [rankdir=LR, bgcolor="white", pad="0.35", nodesep="0.45", ranksep="0.9", splines=true, overlap=false];',
        '  node [shape=box, style="rounded,filled", color="#64748b", fontname="Arial", fontsize=11, margin="0.14,0.08"];',
        '  edge [color="#94a3b8", fontname="Arial", fontsize=9, arrowsize=0.65];',
        "",
        "  subgraph cluster_rust {",
        '    label="Rust compiler areas";',
        '    color="#bbf7d0";',
        '    style="rounded";',
    ]
    for node in sorted(rust_nodes):
        lines.append(dot_node(rust_node(node), f"{node}\\n{rust_file_counts[node]} rs", "#dcfce7"))
    lines.extend(["  }", "", "  subgraph cluster_shaders {", '    label="Shader groups";', '    color="#fde68a";', '    style="rounded";'])
    for node in sorted(shader_nodes):
        entrypoints = image_shader_entrypoint_counts[node]
        suffix = f"\\n{image_shader_file_counts[node]} files"
        if entrypoints:
            suffix += f", {entrypoints} ep"
        lines.append(dot_node(shader_node(node), f"{image_shader_label(node)}{suffix}", "#fef3c7"))
    lines.extend(["  }", "", "  subgraph cluster_tests {", '    label="Tests";', '    color="#ddd6fe";', '    style="rounded";'])
    for node in sorted(test_nodes):
        lines.append(dot_node(test_node(node), node, "#ede9fe"))
    lines.extend(["  }", ""])

    for left, right, count in sorted_counter(rust_edges)[:edge_limit]:
        if left in rust_nodes and right in rust_nodes:
            lines.append(dot_edge(rust_node(left), rust_node(right), count, "#2563eb", "solid"))

    for left, right, count in sorted_counter(image_rust_shader_edges)[:edge_limit]:
        if left in rust_nodes and right in shader_nodes:
            lines.append(dot_edge(rust_node(left), shader_node(right), count, "#16a34a", "dashed"))

    for left, right, count in sorted_counter(image_shader_edges)[:edge_limit]:
        if left in shader_nodes and right in shader_nodes:
            lines.append(dot_edge(shader_node(left), shader_node(right), count, "#d97706", "solid"))

    for left, right, count in sorted_counter(image_test_edges)[:edge_limit]:
        if right in rust_nodes:
            target = rust_node(right)
        elif right in shader_nodes:
            target = shader_node(right)
        else:
            continue
        lines.append(dot_edge(test_node(left), target, count, "#7c3aed", "dotted"))

    lines.append("}")
    return "\n".join(lines)


def aggregate_edges(
    edges: Counter[tuple[str, str]],
    *,
    left_fn,
    right_fn,
    drop_self: bool = False,
) -> Counter[tuple[str, str]]:
    result: Counter[tuple[str, str]] = Counter()
    for (left, right), count in edges.items():
        aggregate_left = left_fn(left)
        aggregate_right = right_fn(right)
        if drop_self and aggregate_left == aggregate_right:
            continue
        result[(aggregate_left, aggregate_right)] += count
    return result


def aggregate_shader_counts(counts: Counter[str]) -> Counter[str]:
    result: Counter[str] = Counter()
    for group, count in counts.items():
        result[image_shader_group(group)] += count
    return result


def aggregate_test_edges_for_image(edges: Counter[tuple[str, str]]) -> Counter[tuple[str, str]]:
    result: Counter[tuple[str, str]] = Counter()
    for (_, target), count in edges.items():
        result[(f"tests/{target}", target)] += count
    return result


def image_shader_group(group: str) -> str:
    root = group.split("/", 1)[0]
    if root in MAIN_SHADER_ROOTS:
        return root
    return f"helper/{root}"


def image_shader_label(group: str) -> str:
    if group.startswith("helper/"):
        return f"helper: {group.removeprefix('helper/')}"
    return group


def rust_node(name: str) -> str:
    return f"rust_{identifier(name)}"


def shader_node(name: str) -> str:
    return f"shader_{identifier(name)}"


def test_node(name: str) -> str:
    return f"test_{identifier(name)}"


def identifier(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def dot_node(identifier_: str, label: str, fill: str) -> str:
    return f'    {identifier_} [label="{dot_escape(label)}", fillcolor="{fill}"];'


def dot_edge(source: str, target: str, count: int, color: str, style: str) -> str:
    label = f' [label="{count}", color="{color}", fontcolor="{color}", style="{style}"]'
    return f"  {source} -> {target}{label};"


def dot_escape(value: str) -> str:
    return html.escape(value, quote=True).replace("\\", "\\\\")


def render_dot(dot: str, *, svg: str | None, png: str | None) -> None:
    if not shutil_which("dot"):
        raise SystemExit("repo_map: image output requires graphviz `dot` on PATH")
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".dot", delete=False) as dot_file:
        dot_file.write(dot)
        dot_path = Path(dot_file.name)
    try:
        if svg:
            render_dot_format(dot_path, Path(svg), "svg")
        if png:
            render_dot_format(dot_path, Path(png), "png")
    finally:
        dot_path.unlink(missing_ok=True)


def shutil_which(command: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def render_dot_format(dot_path: Path, output: Path, fmt: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["dot", f"-T{fmt}", str(dot_path), "-o", str(output)], check=True)


if __name__ == "__main__":
    raise SystemExit(main())
