#!/usr/bin/env python3
"""Generate a public diagnostic-code index from the compiler registry."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


DIAGNOSTICS_SOURCE = Path("crates/laniusc-compiler/src/compiler/diagnostics.rs")


@dataclass(frozen=True)
class DiagnosticCode:
    code: str
    title: str
    category: str
    primary_label_policy: str


@dataclass(frozen=True)
class UnsupportedFeature:
    code: str
    boundary: str
    summary: str
    next_step: str


@dataclass(frozen=True)
class CodegenBoundary:
    diagnostic_code: str
    boundary: str
    target: str
    stage: str
    partial_artifact_policy: str
    target_bytes_emitted: str
    diagnostics_only_command: str
    fallback_emit: str


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a public diagnostic-code index from DIAGNOSTIC_CODE_REGISTRY."
    )
    parser.add_argument(
        "--source",
        default=str(DIAGNOSTICS_SOURCE),
        help="Rust diagnostics source file",
    )
    parser.add_argument("--output", help="write Markdown output to this path")
    parser.add_argument(
        "--check",
        help="compare generated Markdown with this path and exit nonzero if stale",
    )
    args = parser.parse_args()

    repo = repo_root()
    source_path = Path(args.source)
    source = read_source(repo / source_path)
    codes = parse_diagnostic_codes(source)
    unsupported = parse_unsupported_features(source)
    codegen = parse_codegen_boundaries(source)
    validate_codes(codes)

    markdown = render_markdown(source_path, codes, unsupported, codegen)
    if args.check:
        target = Path(args.check)
        try:
            current = target.read_text(encoding="utf-8")
        except FileNotFoundError:
            sys.stderr.write(f"diagnostic_index: missing generated file {target}\n")
            return 1
        if current != markdown:
            sys.stderr.write(f"diagnostic_index: generated output is stale: {target}\n")
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


def read_source(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"diagnostic_index: missing source {path}")


def parse_diagnostic_codes(source: str) -> list[DiagnosticCode]:
    pattern = re.compile(
        r'(?ms)DiagnosticCodeInfo::error\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*DiagnosticPrimaryLabelPolicy::([A-Za-z_][A-Za-z0-9_]*)\s*,?\s*\)'
    )
    return [
        DiagnosticCode(
            code=match.group(1),
            title=match.group(2),
            category=match.group(3),
            primary_label_policy=match.group(4).lower(),
        )
        for match in pattern.finditer(source)
    ]


def parse_unsupported_features(source: str) -> list[UnsupportedFeature]:
    pattern = re.compile(
        r'(?ms)UnsupportedFeatureDiagnosticInfo\s*\{\s*code:\s*"([^"]+)"\s*,\s*boundary:\s*"([^"]+)"\s*,\s*summary:\s*"([^"]+)"\s*,\s*next_step:\s*"([^"]+)"\s*,?\s*\}'
    )
    return [
        UnsupportedFeature(
            code=match.group(1),
            boundary=match.group(2),
            summary=match.group(3),
            next_step=match.group(4),
        )
        for match in pattern.finditer(source)
    ]


def parse_codegen_boundaries(source: str) -> list[CodegenBoundary]:
    pattern = re.compile(
        r'(?ms)CodegenBoundaryDiagnosticInfo\s*\{\s*diagnostic_code:\s*"([^"]+)"\s*,\s*boundary:\s*"([^"]+)"\s*,\s*target:\s*"([^"]+)"\s*,\s*stage:\s*"([^"]+)"\s*,\s*partial_artifact_policy:\s*"([^"]+)"\s*,\s*target_bytes_emitted:\s*(true|false)\s*,\s*diagnostics_only_command:\s*"([^"]+)"\s*,\s*fallback_emit:\s*(Some\("([^"]+)"\)|None)\s*,?\s*\}'
    )
    return [
        CodegenBoundary(
            diagnostic_code=match.group(1),
            boundary=match.group(2),
            target=match.group(3),
            stage=match.group(4),
            partial_artifact_policy=match.group(5),
            target_bytes_emitted=match.group(6),
            diagnostics_only_command=match.group(7),
            fallback_emit=match.group(9) or "none",
        )
        for match in pattern.finditer(source)
    ]


def validate_codes(codes: list[DiagnosticCode]) -> None:
    if not codes:
        raise SystemExit("diagnostic_index: no diagnostic codes found")
    names = [code.code for code in codes]
    duplicates = sorted(name for name, count in Counter(names).items() if count > 1)
    if duplicates:
        joined = ", ".join(duplicates)
        raise SystemExit(f"diagnostic_index: duplicate diagnostic codes: {joined}")
    if names != sorted(names):
        raise SystemExit("diagnostic_index: diagnostic codes are not sorted")


def render_markdown(
    source_path: Path,
    codes: list[DiagnosticCode],
    unsupported: list[UnsupportedFeature],
    codegen: list[CodegenBoundary],
) -> str:
    category_counts = Counter(code.category for code in codes)
    label_counts = Counter(code.primary_label_policy for code in codes)
    lines: list[str] = [
        "# Generated Diagnostic Code Index",
        "",
        f"Generated by `tools/diagnostic_index.py` from `{source_path.as_posix()}`.",
        "Regenerate this file instead of editing it by hand.",
        "",
        "```bash",
        "tools/diagnostic_index.py --output docs/diagnostics/generated/error-index.md",
        "tools/diagnostic_index.py --check docs/diagnostics/generated/error-index.md",
        "```",
        "",
        "## Summary",
        "",
    ]
    lines.extend(
        table(
            ("Item", "Count"),
            [
                ("Diagnostic codes", str(len(codes))),
                ("Unsupported feature boundaries", str(len(unsupported))),
                ("Codegen fail-closed boundaries", str(len(codegen))),
                *[
                    (f"Primary label: {policy}", str(count))
                    for policy, count in sorted_counter(label_counts)
                ],
                *[
                    (f"Category: {category}", str(count))
                    for category, count in sorted_counter(category_counts)
                ],
            ],
        )
    )

    lines.extend(["", "## Codes", ""])
    lines.extend(
        table(
            ("Code", "Title", "Category", "Primary Label", "Explain Command"),
            [
                (
                    code.code,
                    code.title,
                    code.category,
                    code.primary_label_policy,
                    f"laniusc diagnostics explain {code.code}",
                )
                for code in codes
            ],
        )
    )

    lines.extend(["", "## Unsupported Feature Boundaries", ""])
    lines.extend(
        table(
            ("Code", "Boundary", "Summary", "Next Step"),
            [
                (entry.code, entry.boundary, entry.summary, entry.next_step)
                for entry in unsupported
            ],
        )
    )

    lines.extend(["", "## Codegen Fail-Closed Boundaries", ""])
    lines.extend(
        table(
            (
                "Code",
                "Boundary",
                "Target",
                "Stage",
                "Partial Artifact Policy",
                "Target Bytes Emitted",
                "Diagnostics Command",
                "Fallback Emit",
            ),
            [
                (
                    entry.diagnostic_code,
                    entry.boundary,
                    entry.target,
                    entry.stage,
                    entry.partial_artifact_policy,
                    entry.target_bytes_emitted,
                    entry.diagnostics_only_command,
                    entry.fallback_emit,
                )
                for entry in codegen
            ],
        )
    )
    lines.append("")
    return "\n".join(lines)


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
