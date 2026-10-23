# Terminal tables

`ext::table::render(rows, alignments, options)` renders a rectangular table and returns `Result<alloc::vec::Vec<u8>, Error>`. `Row` contains a borrowed `View<Text>`; the arguments are `View<Row>` and `View<Alignment>`. Every row must contain exactly one cell per alignment. `Alignment` is `Left`, `Right`, or `Center`; center puts an odd extra padding space on the right.

The renderer uses `ext::terminal` policy 1 to determine column widths from all cells. It preserves each cell's UTF-8 bytes and adds ASCII spaces, borders, and LF record endings. `borders = true` produces `+---+` top and bottom rules and `| cell |` rows. `false` separates columns with two spaces. There is no special header row. Empty input produces no bytes. A nonempty table requires at least one column.

The API supports single-line cells. Newlines, tabs, ANSI escapes, other terminal controls, and bidi controls return `Cell(flat_index, terminal_error)`. Multiline rendering, wrapping, and truncation are unsupported. Cells are never cut in the middle of a UTF-8 scalar or grapheme; a width limit rejects the entire table.

## Limits

`options()` sets these limits:

| Field | Default | Meaning |
| --- | ---: | --- |
| `max_cells` | 65,536 | All cells across all rows |
| `max_columns` | 64 | Alignment entries, checked even for empty input |
| `max_width` | 4,096 | Display columns of a complete output line, including padding and borders, excluding LF |
| `max_output` | 1,048,576 | Output UTF-8 bytes, including all LF bytes |
| `max_work` | 16,777,216 | Total rendering work units |
| `width` | `terminal::options()` | Scalar/grapheme, ambiguous width, and per-cell work policy |

Limits must be nonnegative; `max_width` must be in `1..=2,147,483,646`. Negative terminal work limits are invalid. Integer metadata errors return `Bounds`, inconsistent row lengths return `Shape(row)`, and the corresponding cell, column, width, output, and work limits have distinct errors. A per-cell terminal work failure appears inside `Cell`.

The work budget uses abstract policy charges: two units per cell and one per column before allocation, six per input byte before width scanning, and two per output byte before output allocation. These charges do not count physical byte reads, decoder lookahead, property searches, or CPU instructions. The six-unit input charge matches `ext::terminal`; its per-cell budget is checked separately, and the inherited grapheme cursor has no additional work budget. The algorithm runs in O(cells + input bytes + output bytes) with fixed implementation factors. Scratch space is O(cells + columns); output space is O(output bytes).

## Ownership and failures

Rows, cell views, alignment views, and text bytes borrow caller storage. Keep every backing owner alive and unchanged until return. Integer checks cannot prove physical backing; an overstated view can trap. The renderer does not edit the caller's views or cells. Copies of `Vec` and nested owners are shallow in Lanius.

Success transfers one output `Vec<u8>` to the caller. Destroy it exactly once after using its borrowed views. Any failure returns no output and destroys all temporary allocations. The renderer creates column-width scratch, cell-width scratch, and the final output buffer, in that order; it cleans up both scratch buffers after success. Output becomes visible only when a complete render succeeds. A caller can then write it with `core::io::write_all`; I/O itself may publish a prefix before failing.

The `csv-table` program demonstrates borrowed cells backed by parsed CSV records. Focused tests compare generated Unicode tables to an independent Rust layout model, check center alignment and all resource categories, preserve borrowed inputs, and inject denial at every renderer allocation while checking that no allocations remain live.
