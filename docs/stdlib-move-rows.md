# Moving owned CSV rows

`sample_programs/library/move_rows.lani` moves a selected block of CSV records
without cloning their owned fields. It uses the four
[direct Vec transfers](stdlib-vec-transfer.md), parses complete input and stages
complete canonical output before writing stdout. All four application groups
pass: 133 native cases, including 40 reached allocation denials. Standalone
compilation and both exact examples below pass separately.

## Build and examples

With the compiler binary built, run from the repository root:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/move_rows.lani \
  -o target/stdlib-work/move_rows
printf 'a\nb\nc\nd\ne\n' | target/stdlib-work/move_rows 1 3 5
```

Expected output is 25 bytes, with literal CRLF after each row:

```csv
"a"
"d"
"e"
"b"
"c"
```

A row that resembles a header receives no special treatment:

```sh
printf 'name,value\n"two,2","quoted ""word"""\nlast,tail\n' | \
  target/stdlib-work/move_rows 2 3 0
```

Expected output is 58 bytes, again with literal CRLF:

```csv
"last","tail"
"name","value"
"two,2","quoted ""word"""
```

Both exact examples passed from the standalone CLI artifact: status 0, empty
stderr and the full 25/58 bytes including literal CRLF. They are separate smoke
receipts, not additional application test cases.

## Original-table boundaries

The invocation is exactly `move_rows START END BEFORE`. Each token contains
1 through 64 ASCII decimal digits, with no signs or whitespace; leading zeros
are allowed. Values range from 0 through 16,384. The program captures at most
three arguments and 192 argument bytes with `snapshot(1,3,192)`. A sole `-h` or
`--help` writes the 743-byte help text without reading stdin. No other flag,
alias, combined help invocation or positional count is accepted.

`START <= END` is checked before stdin. After complete UTF-8 CSV parsing,
the table-relative bounds must satisfy:

```text
0 <= START <= END <= row_count
0 <= BEFORE <= row_count
```

All indices refer to boundaries in the original table. The selection is the
half-open range `[START,END)`. An empty selection, or `BEFORE` anywhere in the
closed interval `[START,END]`, preserves row order. Otherwise the selected
block moves before the original `BEFORE` boundary. When that boundary follows
`END`, subtract the removed count to locate it in the remaining table. For
example, moving `[1,3)` before 5 changes `a,b,c,d,e` to `a,d,e,b,c`.

This policy preserves order within the moved block and within the remainder.
Every row is ordinary data, including row zero. Empty input with boundaries
`0 0 0` succeeds with empty output. A row boundary error follows full input
validation, so malformed CSV is not bypassed by an out-of-range selection.

## CSV values and output

The program uses the existing [CSV dialect](extended-csv.md): complete valid
UTF-8, uniform field count, comma delimiters, LF or CRLF record endings and
quoted CR/LF as field content. Spaces are data. Quotes may begin only at a
field boundary; doubled quotes decode to one quote. Bare unquoted CR and
unsupported ASCII controls, including TAB, NUL and DEL, are rejected. BOM and
Unicode noncharacters remain ordinary valid text; there is no normalization,
locale behavior or BOM removal.

Empty input has no records; a blank record contains one empty field. A trailing
comma adds an empty field, while a terminal record separator adds no extra row.
The [canonical writer](extended-csv-write.md) quotes every field, doubles quotes
and emits CRLF after each record. Field values and duplicates are preserved;
input spelling and line endings need not be. Even an operation that preserves
row order produces canonical output.

## Limits and failure order

| Resource | Limit |
| --- | ---: |
| Captured arguments / total argument bytes | 3 / 192 |
| Bytes per numeric token / largest boundary | 64 / 16,384 |
| Input bytes | 4,194,304 |
| Records / fields per record | 16,384 / 64 |
| Decoded bytes per field / record | 8,192 / 65,536 |
| Staged canonical output bytes | 8,388,608 |
| Input provider calls, including EOF/probes/Interrupted attempts | 16,384 |
| Payload stdout attempts | 16,384 |
| Shared staging writer calls | 65,536 |
| Help attempts / diagnostic attempts | 64 / 64 |

Each direct stdout/stderr request contains at most 1,024 bytes. Interrupted
attempts consume call budget and retry; ordinary errors, zero progress or
successful counts larger than the request fail. Counts represent direct
provider attempts, not an elapsed-time bound.

The order is signal setup, argument capture/validation, bounded input through
EOF, full CSV validation, row-relative bounds, transfers, complete output
measurement, staging allocation/serialization, owner cleanup and publication.
The 8 MiB output cap and 65,536 staging-call cap are defensive under the other
admitted bounds; they do not establish independently reachable rejection
cases. With F fields and R records, canonical output is at most
`input + 2F + R + 1`, hence at most 6,307,841 bytes. The exactly reserved
in-memory sink accepts complete chunks, requiring at most
`ceil(output / 1024) + R <= 22,545` staging calls.
Payload-call exhaustion can be reached through interrupted or very
short writes. The transfer algorithm retains the original row capacity, so
its two appends require no growth in this consumer. Direct library resource
tests separately cover append growth failure.

## Ownership and publication

Each parsed Record owns its decoded bytes and field spans; the Table owns the
row Vec. `table.rows.take()` resets the actual table descriptor before the
empty Table is destroyed. Nontrivial moves extract the selected block, split
the remainder at the adjusted destination, append the block and append the
suffix. Successful appends leave donor reservations with no active entries;
those reservations are explicitly destroyed. Every failure path retires only
the entries still owned by each participating logical range. Spare copied
descriptor slots are inactive aliases.

Argument owners are retired before help or input; raw input is retired after
parsing. Every record and outer row owner is retired after staging and before
stdout. Publication retains only the staged output owner, which is destroyed
before returning or reporting an error. The source does not clone nested
owners, use a borrowed alias as a second owner or rely on implicit destructors.

Prepublication failure leaves stdout empty. Once publication starts, output
errors or payload-call exhaustion may leave a confirmed prefix. Complete
staging does not make writes to a pipe or file atomic. Diagnostics are attempted
after explicit cleanup. These manual rules do not provide a borrow checker,
automatic destruction or recovery from process termination.

## Status and diagnostics

| Exit | Meaning |
| ---: | --- |
| 0 | Moved/canonical CSV, empty output or help completed |
| 2 | Invalid arguments/CSV/boundaries or byte/count/call limits |
| 3 | Argument, input or output I/O failure; failed diagnostic; SIGPIPE setup failure |
| 4 | Reported allocation failure |
| 6 | Internal ownership, storage or provider invariant failure |

SIGPIPE is ignored before argument I/O. Failure to install that disposition
returns 3 without output or a diagnostic. Other failures select one exact
phase diagnostic below, followed by LF, and use the primary status unless
diagnostic writing fails, which selects 3. Help/payload write-call exhaustion
selects 2 subject to that diagnostic override.

```text
move_rows: invalid arguments
move_rows: argument I/O failure
move_rows: input byte limit
move_rows: input read-call limit
move_rows: input I/O failure
move_rows: invalid CSV
move_rows: CSV resource limit
move_rows: row boundary out of range
move_rows: allocation failed
move_rows: output byte limit
move_rows: output write-call limit
move_rows: output I/O failure
move_rows: ownership or provider invariant failure
```

## Target and evidence

Source is frozen at
`9bb0cf068dcb9327926e6b00b22afa9fa3c648fca10b4a92a90a5007f9584215`.
All four native application groups pass on that source:

| Group | Native cases | Scope |
| --- | ---: | --- |
| Independent model | 33 | Exact complete canonical output and original-coordinate movement, including unchanged order, Unicode and multiline fields |
| Admission | 29 | Tokens/help, pre-input argument rejection and full-parse table bounds |
| Limits | 11 | Input EOF/excess probes, row/field/record boundaries and actual output expansion |
| I/O | 60 | One baseline, 40 reached allocation denials and 19 input/output/signal/diagnostic/call-limit cases |

The model passed in 7.43 seconds after a separate 1.74-second Rust build,
`target/stdlib-work/vector-transfer-tool-model.log`. The other three groups
passed together in 18.08 seconds after a 0.19-second build,
`target/stdlib-work/vector-transfer-tool-remaining.log`; no individual timing
is claimed for those groups. The oracle is `bc5f2917` and driver `72465026`.
Every denial was reached from the successful allocation schedule; no partial
publication occurred, and exact address/extent cleanup passed. Publication
checks require only the staged output mapping to remain live, and diagnostics
require all owners to have retired. Successful writes, Interrupted retries,
real closed stdout, empty output and exact 1,024-byte confirmed prefixes are
observed. Payload-call exhaustion reaches exactly 16,384 attempts and reports
status 2; separate 64-attempt diagnostic exhaustion selects 3.

Standalone compilation passed with
exit 0 and no diagnostics in `target/stdlib-work/vector-transfer-cli-build-final.log`;
both exact examples passed in `target/stdlib-work/vector-transfer-cli-examples.log`.
The first standalone compile failed because typed initializers used `>=`
rather than the separate `> =` tokens. Eight occurrences were corrected using
only whitespace; no runtime ran and no compiler repair is claimed.
The [application fixture guide](../tests/fixtures/stdlib_move_rows/README.md)
defines the independent original-coordinate CSV model and the finite
nine-syscall ownership ledger. It observes read, write, mmap, munmap, mremap,
brk, openat, close and rt_sigaction; it does not prove absence of every other
host effect. Host controls contribute no native cases. Invariant status 6 and
argument-capture host-read failure were not injected. This application sweep
does not claim same-process retry; direct library failure recovery has its own
scope. Standalone examples contribute no cases to the 133 above.
The accepted initial target is Linux x86_64 CPU code emitted by the
GPU compiler, using native stdin/stdout. Separate library admission does not
establish this application's behavior. No user-program GPU execution,
other-host support, automatic ownership or formal proof is claimed. See the
[vector-transfer plan](library-vector-transfer-plan.md) for the coordinated
scope; the broader library goal remains open.
