#!/usr/bin/env python3
"""Check maintained documentation freshness and basic Markdown hygiene."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


GENERATED_CHECKS = (
    ("tools/compiler_inventory.py", "--check", "docs/compiler/generated/reference.md"),
    (
        "tools/language_slice_summary.py",
        "--check",
        "docs/language/generated/unstable-alpha-slice.md",
    ),
    ("tools/diagnostic_index.py", "--check", "docs/diagnostics/generated/error-index.md"),
    ("tools/stdlib_inventory.py", "--check", "docs/stdlib/generated/reference.md"),
)

MAINTAINED_DOC_DIRS = (
    "docs/compiler",
    "docs/language",
    "docs/diagnostics",
    "docs/stdlib",
)

MAINTAINED_DOC_FILES = (
    "README.md",
    "docs/README.md",
    "docs/getting-started.md",
    "docs/invocation.md",
    "docs/packages.md",
    "docs/tooling.md",
    "docs/targets.md",
    "docs/DIAGNOSTICS.md",
    "docs/LANGUAGE_SLICE.md",
    "docs/PRODUCTION_READINESS.md",
    "docs/TESTING_STRATEGY.md",
    "stdlib/README.md",
    "stdlib/STANDARD_LIBRARY_SPEC.md",
    "stdlib/LANGUAGE_REQUIREMENTS.md",
    "stdlib/PLAN.md",
)

TOOL_FILES = (
    "tools/compiler_inventory.py",
    "tools/diagnostic_index.py",
    "tools/docs_check.py",
    "tools/language_slice_summary.py",
    "tools/repo_map.py",
    "tools/stdlib_inventory.py",
)

LINK_RE = re.compile(r"(?<!\\)!?\[[^\]]+\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
EXPLICIT_ANCHOR_RE = re.compile(
    r"<a\s+(?:[^>]*\s)?(?:id|name)=['\"]([^'\"]+)['\"]",
    re.IGNORECASE,
)
CUSTOM_ANCHOR_RE = re.compile(r"\{#([A-Za-z0-9_.:-]+)\}")
INLINE_HTML_RE = re.compile(r"<[^>]+>")
MARKDOWN_FORMAT_RE = re.compile(r"[`*_~]")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run maintained-doc freshness, Markdown link, ASCII, and whitespace checks."
    )
    parser.add_argument(
        "--skip-generated",
        action="store_true",
        help="skip generated-reference freshness checks",
    )
    args = parser.parse_args()

    repo = repo_root()
    failures: list[str] = []

    if not args.skip_generated:
        failures.extend(run_generated_checks(repo))

    markdown_files = maintained_markdown_files(repo)
    text_files = markdown_files + existing_paths(repo, TOOL_FILES)
    failures.extend(check_ascii(repo, text_files))
    failures.extend(check_trailing_whitespace(repo, text_files))
    failures.extend(check_markdown_links(repo, markdown_files))

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(
        f"docs_check: ok ({len(markdown_files)} maintained Markdown files, "
        f"{len(GENERATED_CHECKS) if not args.skip_generated else 0} generated checks)"
    )
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


def run_generated_checks(repo: Path) -> list[str]:
    failures: list[str] = []
    for command in GENERATED_CHECKS:
        result = subprocess.run(
            list(command),
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or "no output"
            failures.append(f"generated check failed: {' '.join(command)}\n{detail}")
    return failures


def maintained_markdown_files(repo: Path) -> list[Path]:
    files: set[Path] = set(existing_paths(repo, MAINTAINED_DOC_FILES))
    for directory in MAINTAINED_DOC_DIRS:
        root = repo / directory
        if not root.exists():
            continue
        for path in root.rglob("*.md"):
            files.add(path.relative_to(repo))
    return sorted(files)


def existing_paths(repo: Path, paths: tuple[str, ...]) -> list[Path]:
    out: list[Path] = []
    for path in paths:
        rel = Path(path)
        if (repo / rel).exists():
            out.append(rel)
    return out


def read_lines(repo: Path, path: Path) -> list[str]:
    return (repo / path).read_text(encoding="utf-8").splitlines()


def check_ascii(repo: Path, files: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in files:
        for line_no, line in enumerate(read_lines(repo, path), 1):
            for column, char in enumerate(line, 1):
                if ord(char) > 0x7F:
                    failures.append(f"{path}:{line_no}:{column}: non-ASCII character U+{ord(char):04X}")
                    break
    return failures


def check_trailing_whitespace(repo: Path, files: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in files:
        for line_no, line in enumerate(read_lines(repo, path), 1):
            if line.endswith((" ", "\t")):
                failures.append(f"{path}:{line_no}: trailing whitespace")
    return failures


def check_markdown_links(repo: Path, files: list[Path]) -> list[str]:
    failures: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}
    for path in files:
        text = (repo / path).read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), 1):
            for match in LINK_RE.finditer(line):
                target = markdown_link_target(match.group(1))
                if not target or external_link(target):
                    continue
                if target.startswith("file:"):
                    failures.append(f"{path}:{line_no}: file URI link is not portable: {target}")
                    continue
                path_part, anchor = split_link_target(target)
                if path_part:
                    target_path = unquote(path_part)
                    resolved = (repo / path.parent / target_path).resolve()
                else:
                    resolved = (repo / path).resolve()
                if not resolved.exists():
                    failures.append(f"{path}:{line_no}: missing local link target: {target}")
                    continue
                if anchor and resolved.suffix == ".md":
                    target_rel = relative_to_repo(repo, resolved)
                    if target_rel is None:
                        continue
                    anchors = anchor_cache.setdefault(target_rel, markdown_anchors(repo, target_rel))
                    decoded_anchor = unquote(anchor)
                    if decoded_anchor not in anchors:
                        failures.append(
                            f"{path}:{line_no}: missing Markdown anchor: {target}"
                        )
    return failures


def split_link_target(target: str) -> tuple[str, str]:
    if "#" not in target:
        return target, ""
    path_part, anchor = target.split("#", 1)
    return path_part, anchor


def relative_to_repo(repo: Path, path: Path) -> Path | None:
    try:
        return path.relative_to(repo.resolve())
    except ValueError:
        return None


def markdown_anchors(repo: Path, path: Path) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for line in read_lines(repo, path):
        for match in EXPLICIT_ANCHOR_RE.finditer(line):
            anchors.add(match.group(1))
        for match in CUSTOM_ANCHOR_RE.finditer(line):
            anchors.add(match.group(1))

        match = HEADING_RE.match(line)
        if not match:
            continue
        title = CUSTOM_ANCHOR_RE.sub("", match.group(2)).strip()
        base = github_heading_slug(title)
        if not base:
            continue
        count = counts.get(base, 0)
        anchor = base if count == 0 else f"{base}-{count}"
        counts[base] = count + 1
        anchors.add(anchor)
    return anchors


def github_heading_slug(text: str) -> str:
    text = INLINE_HTML_RE.sub("", text)
    text = MARKDOWN_FORMAT_RE.sub("", text)
    text = text.lower()
    out: list[str] = []
    last_dash = False
    for char in text:
        if char.isascii() and (char.isalnum() or char in "-_"):
            out.append(char)
            last_dash = char == "-"
        elif char.isspace():
            if out and not last_dash:
                out.append("-")
                last_dash = True
        else:
            continue
    while out and out[-1] == "-":
        out.pop()
    return "".join(out)


def markdown_link_target(raw: str) -> str:
    stripped = raw.strip()
    if stripped.startswith("<"):
        end = stripped.find(">")
        if end != -1:
            return stripped[1:end]
    return stripped.split()[0] if stripped else ""


def external_link(target: str) -> bool:
    return target.startswith(
        (
            "http://",
            "https://",
            "mailto:",
            "app://",
            "chrome://",
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
