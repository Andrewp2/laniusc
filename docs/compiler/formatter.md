# Formatter Internals

This chapter documents the lexical formatter used by `laniusc fmt` and by the
LSP full-document formatting request.

The formatter is intentionally conservative for the current `unstable-alpha`
language slice. It does not parse, type check, resolve imports, load source
roots, create a GPU device, or rewrite semantics. Its contract is to preserve
the non-whitespace token text and token order while synthesizing whitespace,
newlines, and indentation around lexical boundaries.

## What This Chapter Owns

This chapter covers:

- `formatter::format_source`
- tokenizer categories used by the formatter
- whitespace, indentation, comments, braces, operators, and `where` handling
- CLI `laniusc fmt` file/stdin/check behavior
- LSP `textDocument/formatting` reuse
- formatter diagnostics and source labels
- no-run formatter metadata
- formatter test evidence

It does not cover:

- command routing or diagnostic-format parsing; see
  [CLI and tooling surface](cli.md)
- LSP framing and lifecycle; see [LSP surface internals](lsp.md)
- general diagnostic rendering; see [Diagnostics and status](diagnostics.md)
- language parsing/type checking; see [Parser and HIR](parser.md) and
  [Resident type checker](type-checker.md)

## Source Map

| Source | Responsibility |
| --- | --- |
| `formatter.rs` | Lexical tokenization, formatting state, whitespace rules, indentation, comments, operators, and public `format_source`. |
| `cli/fmt.rs` | `laniusc fmt` argument handling, stdin/file modes, check mode, file rewriting, stdout writing, and formatter diagnostics. |
| `cli/common/mod.rs` | Formatter policy metadata shared by diagnostics and LSP capability output. |
| `cli/lsp/document.rs` | LSP formatting request validation and full-document edit construction. |
| `tests/formatter.rs` | Direct formatter behavior, idempotence, token-preservation-sensitive cases, comments, literals, operators, and where clauses. |
| `tests/cli_formatter.rs` | Public CLI behavior for file/stdin/check modes and diagnostic rendering. |
| `tests/cli_lsp.rs` | LSP formatting request options and edit-shape behavior. |

The formatter core owns source-to-source formatting. CLI and LSP code own I/O,
request validation, and public diagnostics.

## Core Contract

`format_source` has these invariants:

- formatting is lexical
- formatting is full-document only
- non-whitespace token text is preserved
- token order is preserved
- string literal contents are preserved
- character literal contents are preserved
- comments are preserved
- line endings in formatted output are LF
- indentation uses four spaces
- formatted output ends with one trailing newline when nonempty
- empty or whitespace-only input formats to an empty string
- formatting should be idempotent for the supported alpha slice

This contract is deliberately smaller than a syntax-aware formatter. The
formatter may produce conservative layout for valid source shapes, but it must
not depend on host parsing or type checking to decide what a token means.

## Tokenization

The formatter tokenizes only enough source shape to make whitespace decisions:

| Token family | Examples |
| --- | --- |
| words | identifiers, keywords, and number-like alphanumeric runs |
| string-like tokens | quoted string and character literals, with escape handling |
| comments | `//` line comments and `/* ... */` block comments |
| delimiters | parentheses, brackets, and braces |
| punctuation | comma, semicolon, colon, path colon, dot, arrows, assignment |
| operators | spaced operators, `-`, and `!` |
| atoms | remaining single-character tokens |

Whitespace in the input is skipped. The formatter rebuilds whitespace from
token order, delimiter state, and local token context.

The tokenizer does not validate the language. Unterminated block comments or
quoted literals are copied through to the end of input because the formatter is
not the syntax owner. Syntax diagnostics still belong to parser/type-check
commands.

## Formatting State

The formatter keeps a small state machine:

| State | Meaning |
| --- | --- |
| `indent` | current brace indentation depth |
| `paren_depth` | current parenthesis nesting |
| `bracket_depth` | current bracket nesting |
| `line_start` | whether the next raw token should first write indentation |
| `compact_next_token` | whether a prefix operator should bind to the next token |
| `where_clause` | whether the current output is inside a `where` predicate layout |
| `where_angle_depth` | angle-bracket nesting while laying out `where` predicates |

This state is intentionally lexical. It uses token spelling and nearby token
families, not AST nodes.

## Layout Rules

Important layout rules:

- opening braces are written after a space when needed, then increase indent and
  force a newline
- closing braces decrease indent, move to a fresh line when necessary, and keep
  `else` on the same line when it follows
- semicolons trim trailing spaces and force a newline outside parens/brackets
- commas usually add a space, but can force newlines inside brace-delimited or
  `where` layouts
- line comments attach to the current line when needed and then force a newline
- standalone block comments stay on their own line
- inline block comments can stay inline with surrounding tokens
- `::` and `.` stay compact with surrounding tokens
- `:` is compact before and spaced after
- arrows, assignment, and binary/spaced operators receive spaces
- prefix `-` and `!` compact with the following token
- binary `-` receives surrounding spaces

The formatter distinguishes prefix and binary `-` using the previous token
family and selected keyword spellings such as `if`, `match`, `return`, and
`while`. This is still a lexical heuristic; do not expand it into semantic
analysis inside the formatter.

## Where Clauses

The formatter gives `where` clauses a special lexical layout:

- `where` starts on its own line
- predicates are indented one level past the current indentation
- commas between top-level predicates force newlines
- commas inside angle-bracketed type arguments stay inline
- a following `{` ends the `where` layout and starts the block
- a following `;` ends the `where` layout for declarations

`where_angle_depth` tracks `<` and `>` atoms only while `where_clause` is active.
This is not a general generic parser. It exists only to avoid splitting
predicate type arguments at every comma.

## CLI Behavior

`laniusc fmt` supports four main modes:

| Mode | Behavior |
| --- | --- |
| file inputs | Read each file, format it, and rewrite only files whose content changes. |
| `--check` with file inputs | Read all files, collect unformatted inputs, do not write files, and return one structured diagnostic if any differ. |
| `--stdin` or `-` | Read stdin, format it, and write formatted source to stdout. |
| `--check --stdin` | Compare stdin against formatted output and return one structured diagnostic on mismatch. |

Invalid flag combinations, missing inputs, unknown flags, read failures, write
failures, and check failures are routed through `CliError` and structured
diagnostics. The formatter should not print ad hoc diagnostics.

Successful file formatting is quiet. Successful stdin formatting writes the
formatted source to stdout. Check failures do not write formatted output or
rewrite files.

## LSP Formatting

The LSP server reuses the same `format_source` function for
`textDocument/formatting`.

LSP request requirements:

- the document must already be open
- `params.options` must be present and be an object
- `tabSize` must be `4`
- `insertSpaces` must be `true`

Additional options are ignored. Range formatting is not supported.

The LSP response is either:

- an empty edit list if formatting would not change the document
- one full-document replacement edit if formatting changes the document

The edit range ends at the document end in zero-based UTF-16 positions.
Formatting through LSP must not create a GPU device, scan source roots, or run
target codegen.

## Diagnostics

Formatter diagnostics use stable tooling codes:

| Code | Use |
| --- | --- |
| `LNC0019` | `--check` detected unformatted input. |
| `LNC0034` | rewriting a formatter output file failed. |
| `LNC0035` | writing formatted stdout failed. |
| `LNC0040` | reading formatter input failed. |

`LNC0019` labels the first byte where the original source differs from the
formatted output. When the formatted output is longer than the source, the label
falls back to the last source character or byte zero for empty input.

For multi-file check failures, the primary label points at the first
unformatted input and notes list all unformatted inputs. Already formatted files
must not appear in that note list.

Formatter diagnostics should render through the same text, JSON, and LSP JSON
paths as compiler diagnostics.

## Metadata

`formatter_policy_metadata` publishes the public formatter contract for no-run
metadata commands and LSP capabilities. It records:

- schema name and version
- `unstable-alpha` stability
- lexical formatter kind
- full-document scope
- no range formatting
- no syntax parsing
- no type checking
- no import resolution
- no semantic rewrites
- token-preservation policy
- LF line endings
- four-space indentation
- CLI command templates
- LSP request options
- diagnostic codes
- no-run guards

Keep this metadata in sync with CLI and LSP behavior. A changed formatter
contract should update metadata and tests together.

## Adding Formatter Behavior

Use this checklist when changing the formatter:

1. Decide whether the change belongs in lexical formatting, CLI I/O, LSP request
   handling, diagnostics, or metadata.
2. Keep semantic facts out of `formatter.rs`.
3. Preserve non-whitespace token text and token order unless the formatter
   contract is deliberately expanded.
4. Add the smallest direct `tests/formatter.rs` case for the formatting rule.
5. Add CLI coverage when file/stdin/check behavior or diagnostics change.
6. Add LSP coverage when request options or edit shape change.
7. Update `formatter_policy_metadata` if the public contract changes.
8. Update this chapter and [CLI and tooling surface](cli.md) when public command
   behavior changes.

If a formatting rule requires knowing parser HIR or type-check results, do not
add it to the lexical formatter. Either leave the formatting conservative or
design a separate syntax-aware formatter boundary.

## Test Evidence

Useful formatter evidence:

- direct `format_source` expected output for one small source
- idempotence for already formatted output
- token-preservation-sensitive cases for literals and comments
- operator spacing cases for prefix and binary operators
- `where` clause layout cases
- file rewrite tests proving successful formatting is quiet
- check-mode tests proving no writes happen on failure
- stdin tests proving stdout behavior
- JSON and LSP JSON diagnostic rendering for check failures
- LSP formatting option validation and full-document edit shape

Do not use a broad source corpus as the first proof for a local formatting
change. Start with the smallest source that exposes the lexical rule, then add
CLI or LSP coverage only when the public boundary changed.

For docs-only edits to this chapter, run:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

plus Markdown link, whitespace, and ASCII checks. Formatter tests are needed
when formatting rules, CLI behavior, LSP request handling, diagnostics, or
formatter metadata change.
