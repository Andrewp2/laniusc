# csv-table

`sample_programs/library/csv_table.lani` reads CSV from stdin and prints a Unicode-aware terminal table. It composes `ext::cli`, `ext::csv`, `ext::table`, `ext::terminal`, `ext::progress`, and the checked stream APIs. Production parsing and rendering run in Lanius.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended sample_programs/library/csv_table.lani -o target/stdlib-work/csv-table
printf 'name,city\nAlice,東京\n' | target/stdlib-work/csv-table --progress
```

Stdout:

```text
+-------+------+
| name  | city |
| Alice | 東京 |
+-------+------+
```

Stderr with `--progress`:

```text
[####################] 2/2
```

`--bare` removes the border and separates columns with two spaces. `--right` aligns all columns right. `--wide` gives East Asian ambiguous characters two cells. `--progress` writes exactly one final deterministic progress record to stderr after successful table output; its count includes every CSV record. Empty input emits no table and a requested progress record reads `0/0`. `--help` or `-h` prints usage. There are no filename operands. Flags can appear in any order.

The CSV dialect follows `ext::csv`: UTF-8, comma fields, quoted fields with doubled quotes, LF or CRLF record endings, and equal field counts. The table has no special header semantics. Quoted multiline fields are valid CSV but fail table rendering because cells must be single-line. Tabs, terminal controls, ANSI escapes, and bidi controls are rejected. The width policy is documented in `extended-terminal.md`.

The input limit is 1,048,576 bytes. CSV limits are 1,024 records, 64 fields per record, 4,096 bytes per field, and 65,536 decoded bytes per record. Rendering allows 65,536 cells, 64 columns, 4,096 display columns per complete line, 1,048,576 output bytes, and 33,554,432 work units. Each cell also uses the default terminal work budget. These fixed limits bound memory, scanning, and output. Overlong fields and lines fail; the program does not truncate them.

The program collects and validates the input, parses CSV, builds borrowed field views, and renders the complete table before writing stdout. Invalid input and resource limits therefore emit no table prefix. Output I/O failure can leave a visible prefix. All owners are destroyed on success and on parsing, allocation, rendering, or I/O failure.

| Exit status | Meaning |
| --- | --- |
| 0 | Successful render or help |
| 2 | Invalid arguments, UTF-8, CSV, terminal cell, or resource limit |
| 3 | Input/output failure, including diagnostic or progress output |
| 4 | Allocation failure |

Failures emit one short diagnostic to stderr when it is writable. Checked stream operations retry interrupted I/O. Focused tests cover Unicode alignment, CSV quoting, flag combinations, malformed input, fixed resource boundaries, 65,536 cells, every allocation denial, I/O faults, and interrupted I/O retries. The table tests also compare generated logical tables against an independent layout model.
