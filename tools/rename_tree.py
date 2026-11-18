#!/usr/bin/env python3
"""Move shader and Rust source files by a map and rewrite every exact reference.

usage: tools/rename_tree.py MAP [--dry-run]

Each MAP line is one of:

    <old shader key> -> <new shader key>
    <old Rust file> -> <new Rust file>
    doc <Rust module dir>: <doc line for a new folder module>

A shader key is a path under shaders/ without `.slang`. A Rust file is a path
under crates/laniusc-compiler/src ending in `.rs`. `#` starts a comment.

The tool runs `git mv` for every entry, then rewrites:
  * shader keys, source paths and generated artifact paths in tracked text
    files, with only explicit shader source paths rewritten in docs/ and no
    edits to benchmark_artifacts/ or the root README;
  * Slang `import` and `#include` paths, resolved the way the shader build
    resolves them, and `module` names of moved files;
  * `X.slang` mentions in shaders that shared the moved file's old folder;
  * bare numbered shader names and path tails in source line comments;
  * Rust module paths in `use` trees and in code, and Rust file path strings;
  * `mod` declarations: dangling ones are removed, new children are declared,
    and declaration-only `mod.rs` files of emptied folders are deleted.
Emptied folders are removed. Rust files are not reformatted. The tool ends by
listing any old key or module path still present in the scanned files.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
)
SHADERS = REPO / "shaders"
# Must match the -I list in crates/laniusc-shaders/build.rs.
INCLUDE_ROOTS = ["", "lexer", "parser", "type_checker", "codegen"]
CRATE_SRC = REPO / "crates/laniusc-compiler/src"
CRATE_NAME = "laniusc_compiler"
RUSTFMT = ["rustfmt", "--edition", "2024", "--config", "skip_children=true"]
SKIPPED_PREFIXES = ("docs/", "benchmark_artifacts/", "target/")
SKIPPED_FILES = {"README.md"}

DRY_RUN = False


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout


def write(path: Path, text: str) -> None:
    if not DRY_RUN:
        path.write_text(text)


# ---------------------------------------------------------------- map file


def load_map(path: Path):
    shaders: dict[str, str] = {}
    rust: dict[str, str] = {}
    docs: dict[str, str] = {}
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("doc "):
            target, _, text = line[4:].partition(":")
            docs[target.strip().rstrip("/")] = text.strip()
            continue
        if "->" not in line:
            sys.exit(f"{path}:{number}: expected `old -> new`")
        old, new = (part.strip() for part in line.split("->", 1))
        table = rust if old.endswith(".rs") else shaders
        if old in table:
            sys.exit(f"{path}:{number}: `{old}` is mapped twice")
        if old != new:
            table[old] = new
    for name, table, root, suffix in (
        ("shader", shaders, SHADERS, ".slang"),
        ("Rust file", rust, CRATE_SRC, ""),
    ):
        targets = list(table.values())
        duplicates = {t for t in targets if targets.count(t) > 1}
        if duplicates:
            sys.exit(f"two {name}s map to {sorted(duplicates)}")
        for old, new in table.items():
            if not (root / f"{old}{suffix}").is_file():
                sys.exit(f"{name} `{old}` does not exist")
            if (root / f"{new}{suffix}").exists() and new not in table:
                sys.exit(f"{name} target `{new}` already exists")
    return shaders, rust, docs


# ---------------------------------------------------------------- shaders


def slang_files() -> list[str]:
    return [
        p[len("shaders/") : -len(".slang")]
        for p in git("ls-files", "shaders").split()
        if p.endswith(".slang")
    ]


def resolve(keys: set[str], importer: str, rel: str) -> tuple[str, str] | None:
    """Resolve a shader dependency to (key, root); root None means the importer's folder."""
    candidates = [(os.path.dirname(importer), None)] + [(r, r) for r in INCLUDE_ROOTS]
    for base, root in candidates:
        key = os.path.normpath(os.path.join(base, rel))
        if key in keys:
            return key, root
    return None


def import_form(key: str, root: str | None, importer_dir: str) -> str | None:
    base = importer_dir if root is None else root
    prefix = f"{base}/" if base else ""
    if not key.startswith(prefix):
        return None
    return key[len(prefix) :].replace("/", ".")


IMPORT_RE = re.compile(r"^(\s*(?:__exported\s+)?import\s+)([A-Za-z_][\w.]*)(\s*;.*)$")
INCLUDE_RE = re.compile(r'^(\s*#include\s+")([^"]+\.slang)(".*)$')
MODULE_RE = re.compile(r"^(\s*module\s+)(\w+)(\s*;.*)$")


def rewrite_slang(shader_map: dict[str, str]) -> dict[str, str]:
    """Return new text for every shader whose dependency lines change, keyed by new key."""
    old_keys = set(slang_files())
    new_keys = {shader_map.get(k, k) for k in old_keys}
    moved_dirs = {os.path.dirname(old) for old in shader_map}
    out: dict[str, str] = {}
    for old_file in sorted(old_keys):
        new_file = shader_map.get(old_file, old_file)
        new_dir = os.path.dirname(new_file)
        text = (SHADERS / f"{old_file}.slang").read_text()
        lines = text.split("\n")
        changed = False
        for i, line in enumerate(lines):
            if m := IMPORT_RE.match(line):
                name = m.group(2)
                found = resolve(old_keys, old_file, name.replace(".", "/"))
                if not found:
                    continue
                key, root = found
                target = shader_map.get(key, key)
                again = resolve(new_keys, new_file, name.replace(".", "/"))
                if again and again[0] == target:
                    continue
                forms = [import_form(target, root, new_dir)] + [
                    import_form(target, r, new_dir) for r in INCLUDE_ROOTS
                ]
                for form in forms:
                    if form and (r := resolve(new_keys, new_file, form.replace(".", "/"))) and r[0] == target:
                        lines[i] = m.group(1) + form + m.group(3)
                        changed = True
                        break
                else:
                    sys.exit(f"cannot import {target} from {new_file}")
            elif m := INCLUDE_RE.match(line):
                found = resolve(old_keys, old_file, m.group(2)[: -len(".slang")])
                if not found:
                    continue
                key, root = found
                target = shader_map.get(key, key)
                again = resolve(new_keys, new_file, m.group(2)[: -len(".slang")])
                if again and again[0] == target:
                    continue
                form = os.path.relpath(target, new_dir) if root is None else None
                if form is None or resolve(new_keys, new_file, form)[0] != target:
                    form = import_form(target, root, new_dir)
                    form = form.replace(".", "/") if form else os.path.relpath(target, new_dir)
                lines[i] = m.group(1) + form + ".slang" + m.group(3)
                changed = True
            elif (m := MODULE_RE.match(line)) and old_file in shader_map:
                if m.group(2) == os.path.basename(old_file):
                    lines[i] = m.group(1) + os.path.basename(new_file) + m.group(3)
                    changed = True
            else:
                new_line = line
                if os.path.dirname(old_file) in moved_dirs and ".slang" in line:
                    new_line = SIBLING_RE.sub(
                        lambda s: sibling_mention(s, old_file, new_dir, shader_map), line
                    )
                if new_line.lstrip().startswith("//"):
                    new_line = NUMBERED_SIBLING_RE.sub(
                        lambda m: numbered_sibling(m, old_file, shader_map),
                        new_line,
                    )
                    new_line = DOTTED_IMPORT_RE.sub(
                        lambda m: comment_import(m, old_file, old_keys, shader_map),
                        new_line,
                    )
                if new_line != line:
                    lines[i] = new_line
                    changed = True
        if changed:
            out[new_file] = "\n".join(lines)
    return out


SIBLING_RE = re.compile(r"(?<![\w/.\-])(\w+)\.slang\b")
NUMBERED_SIBLING_RE = re.compile(
    r"(?<![\w/.\-])[0-9][0-9a-z]*_[a-z]\w*(?![\w/]|\.slang\b)"
)
DOTTED_IMPORT_RE = re.compile(r"(?<![\w/.\-])(?:[a-z_]\w*\.)+[a-z_]\w*\b")
LINE_COMMENT_RE = re.compile(r"(?m)^[ \t]*//[^\n]*")


def numbered_sibling(m: re.Match, old_file: str, shader_map: dict[str, str]) -> str:
    name = m.group(0)
    sibling = os.path.join(os.path.dirname(old_file), name)
    return os.path.basename(shader_map.get(sibling, name))


def comment_import(
    m: re.Match, old_file: str, keys: set[str], shader_map: dict[str, str]
) -> str:
    name = m.group(0)
    found = resolve(keys, old_file, name.replace(".", "/"))
    if found and found[0] in shader_map:
        return shader_map[found[0]].replace("/", ".")
    return name


def sibling_mention(m: re.Match, old_file: str, new_dir: str, shader_map: dict[str, str]) -> str:
    key = os.path.join(os.path.dirname(old_file), m.group(1))
    if key not in shader_map:
        return m.group(0)
    target = shader_map[key]
    if os.path.dirname(target) == new_dir:
        return os.path.basename(target) + ".slang"
    return target + ".slang"


# ---------------------------------------------------------------- Rust modules


def module_of(src_rel: str) -> list[str]:
    parts = src_rel[: -len(".rs")].split("/")
    if parts[-1] == "mod" or (len(parts) == 1 and parts[0] in ("lib", "main")):
        parts = parts[:-1]
    return ["crate", *parts]


def module_dir(src_rel: str) -> str:
    """Folder that holds the child modules a file declares."""
    stem = src_rel[: -len(".rs")]
    if os.path.basename(stem) == "mod" or stem in ("lib", "main"):
        return os.path.dirname(stem)
    return stem


def rust_files() -> list[str]:
    prefix = "crates/laniusc-compiler/src/"
    return [
        p[len(prefix) :]
        for p in git("ls-files", prefix).split()
        if p.endswith(".rs") and (REPO / p).is_file()
    ]


PATH_RE = re.compile(r"(?<![\w:])(?:[A-Za-z_]\w*::)+[A-Za-z_]\w*")
USE_RE = re.compile(r"(?m)^([ \t]*(?:pub(?:\([^)]*\))?\s+)?use\s+)([^;]*);")
PATH_ATTR_RE = re.compile(r'(#\[path\s*=\s*")([^"]+)("\])')
PATH_MOD_RE = re.compile(PATH_ATTR_RE.pattern + r"\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;")


def path_modules(files: list[str]) -> dict[str, tuple[str, str]]:
    """Map each file loaded by a path attribute to its declaring file and module name."""
    modules = {}
    for owner in files:
        for m in PATH_MOD_RE.finditer((CRATE_SRC / owner).read_text()):
            target = os.path.normpath(os.path.join(os.path.dirname(owner), m.group(2)))
            modules[target] = (owner, m.group(4))
    return modules


class RustRewriter:
    def __init__(self, rust_map: dict[str, str]):
        self.files = rust_files()
        self.rust_map = rust_map
        self.path_modules = path_modules(self.files) if rust_map else {}
        self.old_modules = {"::".join(self.module(f)) for f in self.files}
        self.module_map = {
            "::".join(self.module(old)): "::".join(self.module(old, moved=True))
            for old in rust_map.keys() | self.path_modules.keys()
            if self.module(old) != self.module(old, moved=True)
        }
        self.parent_globs: dict[tuple[str, ...], set[tuple[str, ...]]] = {}
        if rust_map:
            for f in self.files:
                text = (CRATE_SRC / f).read_text()
                if "super::" not in text:
                    continue
                base = self.module(f)
                spans = self.inline_modules(text)
                for m in USE_RE.finditer(text):
                    scope = tuple(self.module_at(base, spans, m.start()))
                    for segs, _ in parse_use_tree(m.group(2)) or []:
                        levels = len(segs) - 1
                        if 0 < levels < len(scope) and segs == ["super"] * levels + ["*"]:
                            self.parent_globs.setdefault(scope, set()).add(scope[:-levels])

    def module(self, file: str, moved: bool = False) -> list[str]:
        if file in self.path_modules:
            owner, name = self.path_modules[file]
            return self.module(owner, moved) + [name]
        return module_of(self.rust_map.get(file, file) if moved else file)

    def map_path(self, segs: list[str]) -> list[str]:
        for n in range(len(segs), 1, -1):
            new = self.module_map.get("::".join(segs[:n]))
            if new is not None:
                return new.split("::") + segs[n:]
        return segs

    def absolute(self, segs: list[str], module: list[str], bindings: dict) -> tuple[list[str], str] | None:
        """Resolve a path in `module`; return (absolute segments, style)."""
        head = segs[0]
        if head == "crate":
            return segs, "crate"
        if head == CRATE_NAME:
            return ["crate", *segs[1:]], "extern"
        if head in ("self", "super"):
            base = list(module)
            rest = list(segs)
            while rest and rest[0] in ("self", "super"):
                if rest.pop(0) == "super":
                    base.pop()
            return base + rest, "relative"
        if "::".join(module + [head]) in self.old_modules:
            return module + segs, "relative"
        if head in bindings:
            return bindings[head] + segs[1:], "binding"
        # A parent glob can expose the parent's module names, including
        # names the parent itself imported through another parent glob.
        pending = list(self.parent_globs.get(tuple(module), ()))
        candidates = set()
        while pending:
            parent = pending.pop()
            if "::".join((*parent, head)) in self.old_modules:
                candidates.add(parent)
            else:
                pending.extend(self.parent_globs.get(parent, ()))
        if len(candidates) == 1:
            (parent,) = candidates
            return [*parent, *segs], "glob"
        return None

    def emit(self, new: list[str], style: str, new_module: list[str]) -> str:
        if style == "extern":
            return "::".join([CRATE_NAME, *new[1:]])
        if style == "relative":
            if new[: len(new_module)] == new_module and len(new) > len(new_module):
                return "::".join(new[len(new_module) :])
            parent = new_module[:-1]
            if parent and new[: len(parent)] == parent and len(new) > len(parent):
                return "::".join(["super", *new[len(parent) :]])
        return "::".join(new)

    def inline_modules(self, text: str) -> list[tuple[int, int, str]]:
        spans = []
        for m in re.finditer(r"\bmod\s+(\w+)\s*\{", text):
            depth, i = 1, m.end()
            while depth and i < len(text):
                depth += {"{": 1, "}": -1}.get(text[i], 0)
                i += 1
            spans.append((m.start(), i, m.group(1)))
        return spans

    def module_at(self, base: list[str], spans, offset: int) -> list[str]:
        return base + [name for start, end, name in spans if start <= offset < end]

    def rewrite(self, old_file: str, text: str, external: bool = False) -> str:
        """Rewrite module paths; `external` files (tests) see the crate by name only."""
        new_file = self.rust_map.get(old_file, old_file)
        old_mod = ["<external>"] if external else self.module(old_file)
        new_mod = ["<external>"] if external else self.module(old_file, moved=True)
        spans = self.inline_modules(text)
        bindings: dict[str, list[str]] = {}
        renamed_bindings: dict[str, str] = {}
        uses = []
        for m in USE_RE.finditer(text):
            module = self.module_at(old_mod, spans, m.start())
            leaves = parse_use_tree(m.group(2))
            if leaves is None:
                continue
            resolved = []
            for segs, alias in leaves:
                path = segs[:-1] if segs[-1] == "self" else segs
                found = self.absolute(path, module, bindings) if segs != ["*"] else None
                if found and path[-1] != "*":
                    bindings[alias or path[-1]] = found[0]
                resolved.append((segs, alias, path, found))
            uses.append((m, module, resolved))
        pieces, last = [], 0
        for m, module, resolved in uses:
            target_module = new_mod + module[len(old_mod) :]
            out_leaves, changed = [], False
            for segs, alias, path, found in resolved:
                if not found:
                    out_leaves.append(("::".join(segs), alias))
                    continue
                abs_segs, style = found
                new_segs = self.map_path(abs_segs)
                if new_segs == abs_segs and target_module == module:
                    out_leaves.append(("::".join(segs), alias))
                    continue
                if new_segs != abs_segs:
                    changed = True
                    if not alias and new_segs[-1] != abs_segs[-1]:
                        renamed_bindings[abs_segs[-1]] = new_segs[-1]
                elif style == "relative":
                    changed = True
                out_leaves.append((self.emit(new_segs, style, target_module), alias))
                if segs[-1] == "self":
                    out_leaves[-1] = (out_leaves[-1][0] + "::self", alias)
            if changed:
                pieces.append(text[last : m.start()])
                indent = re.match(r"[ \t]*", m.group(1)).group(0)
                pieces.append(m.group(1) + format_use_tree(out_leaves, indent) + ";")
                last = m.end()
        pieces.append(text[last:])
        text = "".join(pieces)
        use_spans = [(m.start(), m.end()) for m in USE_RE.finditer(text)]
        spans = self.inline_modules(text)

        def path_sub(m: re.Match) -> str:
            if any(s <= m.start() < e for s, e in use_spans):
                return m.group(0)
            segs = m.group(0).split("::")
            module = self.module_at(old_mod, spans, m.start())
            found = self.absolute(segs, module, bindings)
            if not found:
                line_start = text.rfind("\n", 0, m.start()) + 1
                if text[line_start:m.start()].lstrip().startswith("//"):
                    # Documentation can refer to a module by its crate-relative
                    # path without the explicit `crate::` used in code.
                    return "::".join(self.map_path(["crate", *segs])[1:])
                return m.group(0)
            abs_segs, style = found
            new_segs = self.map_path(abs_segs)
            target_module = new_mod + module[len(old_mod) :]
            if new_segs == abs_segs and (style != "relative" or target_module == module):
                return m.group(0)
            if style == "binding":
                head = renamed_bindings.get(segs[0], segs[0])
                bound = self.map_path(bindings[segs[0]])
                if new_segs[: len(bound)] == bound:
                    return "::".join([head, *new_segs[len(bound) :]])
                style = "crate"
            return self.emit(new_segs, style, target_module)

        text = PATH_RE.sub(path_sub, text)
        if external:
            return text

        def path_attr_sub(m: re.Match) -> str:
            old_target = os.path.normpath(os.path.join(os.path.dirname(old_file), m.group(2)))
            new_target = self.rust_map.get(old_target, old_target)
            if old_file == new_file and old_target == new_target:
                return m.group(0)
            new_rel = os.path.relpath(new_target, os.path.dirname(new_file))
            return m.group(1) + new_rel + m.group(3)

        return PATH_ATTR_RE.sub(path_attr_sub, text)


def parse_use_tree(body: str):
    tokens = re.findall(r"::|[{},*]|\bas\b|[A-Za-z_]\w*|\S", body)
    pos = 0

    def tree(prefix):
        nonlocal pos
        if tokens[pos] == "{":
            pos += 1
            out = []
            while tokens[pos] != "}":
                out += tree(prefix)
                if tokens[pos] == ",":
                    pos += 1
            pos += 1
            return out
        if tokens[pos] == "*":
            pos += 1
            return [(prefix + ["*"], None)]
        segs = list(prefix)
        while True:
            segs.append(tokens[pos])
            pos += 1
            if pos < len(tokens) and tokens[pos] == "::":
                pos += 1
                if tokens[pos] in ("{", "*"):
                    return tree(segs)
                continue
            break
        alias = None
        if pos < len(tokens) and tokens[pos] == "as":
            alias = tokens[pos + 1]
            pos += 2
        return [(segs, alias)]

    try:
        leaves = tree([])
    except IndexError:
        return None
    if pos != len(tokens) or any(not re.fullmatch(r"\w+|\*", s) for segs, _ in leaves for s in segs):
        return None
    return leaves


def format_use_tree(leaves: list[tuple[str, str | None]], indent: str) -> str:
    root: dict = {}
    for path, alias in leaves:
        node = root
        segs = path.split("::")
        for seg in segs[:-1]:
            node = node.setdefault(seg, {})
        key = segs[-1] + (f" as {alias}" if alias else "")
        node.setdefault(key, {})

    def render(name: str, node: dict, depth: int) -> str:
        if not node:
            return name
        if len(node) == 1:
            child, sub = next(iter(node.items()))
            return f"{name}::{render(child, sub, depth)}"
        items = [render(k, v, depth + 1) for k, v in sorted(node.items(), key=use_order)]
        flat = f"{name}::{{{', '.join(items)}}}"
        if len(indent) + 4 * depth + len(flat) < 90 and "\n" not in flat:
            return flat
        pad = indent + "    " * (depth + 1)
        body = "".join(f"\n{pad}{item}," for item in items)
        return f"{name}::{{{body}\n{indent}{'    ' * depth}}}"

    if len(root) == 1:
        name, node = next(iter(root.items()))
        return render(name, node, 0)
    items = [render(k, v, 1) for k, v in sorted(root.items(), key=use_order)]
    return "{" + ", ".join(items) + "}"


def use_order(item):
    name = item[0]
    return (name != "self", name)


# ---------------------------------------------------------------- mod declarations

DECL_RE = re.compile(
    r"(?m)^((?:[ \t]*(?:///|#\[).*\n)*)([ \t]*)((?:pub(?:\([^)]*\))?\s+)?)mod\s+(\w+)\s*;[ \t]*\n"
)
MARK = "// rename_tree: declarations\n"


def declarations() -> dict[str, tuple[str, str]]:
    """Map every declared module path to its (doc and attribute lines, visibility)."""
    out = {}
    for f in rust_files():
        text = (CRATE_SRC / f).read_text()
        base = module_of(f)
        for m in DECL_RE.finditer(text):
            out["::".join(base + [m.group(4)])] = (m.group(1), m.group(3))
    return out


def child_exists(owner: str, name: str) -> bool:
    folder = CRATE_SRC / module_dir(owner)
    return (folder / f"{name}.rs").is_file() or (folder / name / "mod.rs").is_file()


def owner_of(folder: str) -> str | None:
    for candidate in (f"{folder}/mod.rs", f"{folder}.rs") if folder else ("lib.rs", "main.rs"):
        if (CRATE_SRC / candidate).is_file():
            return candidate
    return None


def has_rust(folder: Path) -> bool:
    return any(p.suffix == ".rs" for p in folder.rglob("*.rs"))


def ancestors(folder: str) -> set[str]:
    out = set()
    while folder:
        out.add(folder)
        folder = os.path.dirname(folder)
    return out


def fix_declarations(old_decls, reverse_modules, docs, rust_map, existed: set[str]):
    """Remove dangling declarations near moved files and declare their new neighbours."""
    clean = set()
    for f in [*rust_map, *rust_map.values()]:
        clean |= ancestors(os.path.dirname(f))
    declare = set()
    for f in rust_map.values():
        folder = os.path.dirname(f)
        declare.add(folder)
        for a in ancestors(folder) - existed:
            declare |= {a, os.path.dirname(a)}
    changed = True
    while changed:
        changed = False
        for f in rust_files():
            if os.path.dirname(f) not in clean:
                continue
            path = CRATE_SRC / f
            text = path.read_text()
            marked = MARK in text

            def drop(m: re.Match) -> str:
                nonlocal marked
                if "#[path" in m.group(1) or child_exists(f, m.group(4)):
                    return m.group(0)
                if marked:
                    return ""
                marked = True
                return MARK

            new = DECL_RE.sub(drop, text)
            if new != text:
                write(path, new)
                changed = True
        for folder in sorted({os.path.dirname(f) for f in rust_files()}, key=len, reverse=True):
            mod = CRATE_SRC / folder / "mod.rs"
            if folder not in clean or not mod.is_file():
                continue
            others = [p for p in mod.parent.iterdir() if p != mod and (p.suffix == ".rs" or (p.is_dir() and has_rust(p)))]
            body = re.sub(r"(?m)^\s*(//!.*|// rename_tree: declarations)?\n?", "", mod.read_text())
            if not others and not body.strip():
                git("rm", "-q", "-f", str(mod.relative_to(REPO)))
                changed = True
    attribute_targets = path_modules(rust_files()) if declare else {}
    for folder in sorted(declare):
        if not (CRATE_SRC / folder).is_dir():
            continue
        here = CRATE_SRC / folder
        children = sorted(
            {
                p.stem for p in here.glob("*.rs")
                if p.stem != "mod" and str(p.relative_to(CRATE_SRC)) not in attribute_targets
            }
            | {p.name for p in here.iterdir() if p.is_dir() and has_rust(p)}
        )
        owner = owner_of(folder)
        if owner is None:
            if not children:
                continue
            owner = f"{folder}/mod.rs"
            write(CRATE_SRC / owner, MARK)
            git("add", str((CRATE_SRC / owner).relative_to(REPO)))
        text = (CRATE_SRC / owner).read_text()
        declared = {m.group(4) for m in DECL_RE.finditer(text)}
        base = module_of(owner)
        lines = []
        for child in children:
            if child in declared:
                continue
            new_path = "::".join(base + [child])
            old_path = reverse_modules.get(new_path, new_path)
            doc, vis = old_decls.get(old_path, ("", "pub "))
            note = docs.get(f"{folder}/{child}".lstrip("/"))
            if note:
                doc = f"/// {note}\n"
            lines.append(f"{doc}{vis}mod {child};\n")
        if lines:
            block = "".join(lines)
            if MARK in text:
                text = text.replace(MARK, block + MARK, 1)
            else:
                decls = list(DECL_RE.finditer(text))
                at = decls[-1].end() if decls else len(re.match(r"(?:\s*(?://!|#!\[).*\n)*\n?", text).group(0))
                text = text[:at] + block + text[at:]
            write(CRATE_SRC / owner, text)
    for f in rust_files():
        path = CRATE_SRC / f
        text = path.read_text()
        if MARK in text:
            text = text.replace(MARK, "")
            if not text.strip():
                sys.exit(f"{f} would be empty")
            write(path, text)


# ---------------------------------------------------------------- text references


def scanned_files() -> list[Path]:
    out = []
    for rel in git("ls-files").splitlines():
        if rel.startswith(SKIPPED_PREFIXES) or rel in SKIPPED_FILES:
            continue
        path = REPO / rel
        if path.is_file() and not path.is_symlink():
            out.append(path)
    return out


def text_of(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode()
    except UnicodeDecodeError:
        return None


def reference_pattern(table: dict[str, str], suffix_ok: str) -> re.Pattern | None:
    if not table:
        return None
    keys = sorted(table, key=len, reverse=True)
    return re.compile(
        r"(?:(?<![\w.\-/])|(?<=shaders/)|(?<=src/))("
        + "|".join(map(re.escape, keys))
        + r")(?![\w/\-])"
        + suffix_ok
    )


def unique_basenames(shader_map: dict[str, str]) -> dict[str, str]:
    """Old -> new file name for moved shaders whose old name is unique in the tree."""
    counts: dict[str, int] = {}
    for key in slang_files():
        counts[os.path.basename(key)] = counts.get(os.path.basename(key), 0) + 1
    return {
        os.path.basename(old): os.path.basename(new)
        for old, new in shader_map.items()
        if counts[os.path.basename(old)] == 1
    }


def partial_paths(shader_map: dict[str, str]) -> dict[str, str]:
    """Old -> new name for mentions like `semantic_end_heaps.slang` that end a moved key.

    A tail is used only when one shader key in the tree ends with it. It is
    replaced by the new file name, or by the new key when that name is shared.
    """
    keys = slang_files()
    owners: dict[str, list[str]] = {}
    for key in keys:
        parts = key.split("/")
        for n in range(2, len(parts)):
            owners.setdefault("/".join(parts[-n:]), []).append(key)
    new_names: dict[str, int] = {}
    for key in keys:
        name = os.path.basename(shader_map.get(key, key))
        new_names[name] = new_names.get(name, 0) + 1
    out = {}
    for tail, found in owners.items():
        if len(found) == 1 and found[0] in shader_map:
            new = shader_map[found[0]]
            out[tail] = os.path.basename(new) if new_names[os.path.basename(new)] == 1 else new
    return out


def replace_references(shader_map, rust_map, basenames: dict[str, str], tails: dict[str, str]) -> int:
    # Root modules have names such as `status` and `scatter`. A bare
    # occurrence can be a buffer name or label rather than a shader key.
    shader_re = reference_pattern(
        {k: v for k, v in shader_map.items() if "/" in k},
        r"(?!\.(?!(?:slang|spv|reflect\.json)\b))",
    )
    explicit_shader_re = (
        re.compile(
            r"(?<=shaders/)("
            + "|".join(map(re.escape, sorted(shader_map, key=len, reverse=True)))
            + r")(?=\.slang\b)"
        )
        if shader_map else None
    )
    rust_re = reference_pattern(rust_map, "")
    name_re = None
    if basenames:
        names = sorted(basenames, key=len, reverse=True)
        name_re = re.compile(r"(?<![\w/.\-])(" + "|".join(map(re.escape, names)) + r")\.slang\b")
    tail_re = None
    if tails:
        names = sorted(tails, key=len, reverse=True)
        tail_re = re.compile(r"(?<![\w/.\-])(" + "|".join(map(re.escape, names)) + r")\.slang\b")
    comment_names = {
        **{old: new for old, new in basenames.items() if old[0].isdigit()},
        **tails,
    }
    comment_re = reference_pattern(comment_names, r"(?!\.[a-zA-Z])")
    count = 0
    for path in scanned_files():
        text = text_of(path)
        if text is None:
            continue
        new = text
        if shader_re:
            new = shader_re.sub(lambda m: shader_map[m.group(1)], new)
        if explicit_shader_re:
            new = explicit_shader_re.sub(lambda m: shader_map[m.group(1)], new)
        if rust_re:
            new = rust_re.sub(lambda m: rust_map[m.group(1)], new)
        if tail_re:
            new = tail_re.sub(lambda m: tails[m.group(1)] + ".slang", new)
        if name_re:
            new = name_re.sub(lambda m: basenames[m.group(1)] + ".slang", new)
        if comment_re and path.suffix in {".rs", ".slang"}:
            new = LINE_COMMENT_RE.sub(
                lambda line: comment_re.sub(lambda m: comment_names[m.group(1)], line.group(0)),
                new,
            )
        if new != text:
            write(path, new)
            count += 1
    if explicit_shader_re:
        for rel in git("ls-files", "docs").splitlines():
            path = REPO / rel
            text = text_of(path)
            if text is None:
                continue
            new = explicit_shader_re.sub(lambda m: shader_map[m.group(1)], text)
            if new != text:
                write(path, new)
                count += 1
    return count


def module_exists(path: str) -> bool:
    rel = CRATE_SRC / "/".join(path.split("::")[1:])
    return rel.with_suffix(".rs").is_file() or (rel / "mod.rs").is_file()


def leftovers(shader_map, rust_map, module_map) -> list[str]:
    def alternation(words):
        return "|".join(map(re.escape, sorted(words, key=len, reverse=True))) or "(?!)"

    remaining = {os.path.basename(k) for k in slang_files()}
    gone = {os.path.basename(k) for k in shader_map} - remaining
    modules = [k[len("crate::") :] for k in module_map if not module_exists(k)]
    needle = re.compile(
        r"(?:(?<![\w.\-/])|(?<=shaders/))(?:" + alternation(k for k in shader_map if "/" in k) + r")(?![\w/\-])"
        + r"|(?<=shaders/)(?:" + alternation(k for k in shader_map if "/" not in k) + r")(?=\.slang\b)"
        + r"|(?:" + alternation(modules) + r")\b"
        + r"|" + alternation(rust_map)
        + r"|(?<![\w.\-])(?:" + alternation(gone) + r")\.slang\b"
    )
    found = []
    for path in scanned_files():
        text = text_of(path)
        if text is None:
            continue
        for m in needle.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            found.append(f"{path.relative_to(REPO)}:{line}: {m.group(0)}")
    return found


# ---------------------------------------------------------------- main


def remove_empty_dirs(root: Path) -> None:
    for folder in sorted((p for p in root.rglob("*") if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
        if not any(folder.iterdir()):
            folder.rmdir()


def rustfmt_clean(paths: list[Path]) -> set[Path]:
    return {
        p for p in paths
        if subprocess.run([*RUSTFMT, "--check", str(p)], capture_output=True).returncode == 0
    }


def main() -> None:
    global DRY_RUN
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("map", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="print the moves and change nothing")
    args = parser.parse_args()
    DRY_RUN = args.dry_run
    shader_map, rust_map, docs = load_map(args.map)
    for old, new in [*shader_map.items(), *rust_map.items()]:
        print(f"{old} -> {new}")
    if DRY_RUN:
        return

    basenames = unique_basenames(shader_map)
    tails = partial_paths(shader_map)
    slang_text = rewrite_slang(shader_map)
    rewriter = RustRewriter(rust_map)
    rust_text = {}
    for f in rewriter.files:
        text = (CRATE_SRC / f).read_text()
        new = rewriter.rewrite(f, text)
        if new != text or f in rust_map:
            rust_text[rust_map.get(f, f)] = new
    outside = {}
    for rel in git("ls-files", "*.rs").split():
        path = REPO / rel
        if rel.startswith(("crates/laniusc-compiler/src/", *SKIPPED_PREFIXES)) or not path.is_file():
            continue
        text = path.read_text()
        if f"{CRATE_NAME}::" in text:
            new = rewriter.rewrite(rel, text, external=True)
            if new != text:
                outside[path] = new
    old_decls = declarations()
    edited = {f for f in rewriter.files if rust_map.get(f, f) in rust_text}
    for f in [*rust_map, *rust_map.values()]:
        for folder in ancestors(os.path.dirname(f)):
            edited |= {o for o in (f"{folder}/mod.rs", f"{folder}.rs") if o in rewriter.files}
    tidy = {rust_map.get(f, f) for f in edited if rustfmt_clean([CRATE_SRC / f])}
    existed = set()
    for f in rewriter.files:
        existed |= ancestors(os.path.dirname(f))

    for old, new in shader_map.items():
        (SHADERS / new).parent.mkdir(parents=True, exist_ok=True)
        git("mv", f"shaders/{old}.slang", f"shaders/{new}.slang")
    for old, new in rust_map.items():
        (CRATE_SRC / new).parent.mkdir(parents=True, exist_ok=True)
        git("mv", str((CRATE_SRC / old).relative_to(REPO)), str((CRATE_SRC / new).relative_to(REPO)))
    for key, text in slang_text.items():
        write(SHADERS / f"{key}.slang", text)
    for f, text in rust_text.items():
        write(CRATE_SRC / f, text)
    outside_tidy = rustfmt_clean(list(outside))
    for path, text in outside.items():
        write(path, text)

    files = replace_references(shader_map, rust_map, basenames, tails)
    reverse = {v: k for k, v in rewriter.module_map.items()}
    fix_declarations(old_decls, reverse, docs, rust_map, existed)
    remove_empty_dirs(SHADERS)
    remove_empty_dirs(CRATE_SRC)
    # Reformat only files that were rustfmt-clean before and changed now.
    changed = git("diff", "--name-only", "HEAD", "--", "crates/laniusc-compiler/src").split()
    changed += git("ls-files", "--others", "--exclude-standard", "crates/laniusc-compiler/src").split()
    prefix = "crates/laniusc-compiler/src/"
    for rel in changed:
        f = rel[len(prefix):]
        if f in tidy and (REPO / rel).is_file():
            subprocess.run([*RUSTFMT, str(REPO / rel)], check=True)
    for path in outside_tidy:
        subprocess.run([*RUSTFMT, str(path)], check=True)
    print(f"moved {len(shader_map)} shaders and {len(rust_map)} Rust files; "
          f"{len(slang_text)} shader dependency edits, {len(rust_text)} Rust module edits, "
          f"{files} files with path references")
    rest = leftovers(shader_map, rust_map, rewriter.module_map)
    if rest:
        print("old names still present:")
        print("\n".join(rest))


if __name__ == "__main__":
    main()
