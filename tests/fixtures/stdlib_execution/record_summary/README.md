# Binary record-summary application tests

The independent oracle checks every byte emitted by the real `record_summary`
program. Its reference uses binary LF splitting, removes only the terminal LF,
uses comma splitting with retained empty fields, and groups equal consecutive
bytes to find the longest run. CR, NUL, quotes and invalid UTF-8 remain ordinary
content. Runs are counted across the entire record, including consecutive commas.
Empty input has no records; an empty record has one empty field and no run.

## Accepted corpus

Host-only model/ledger controls and all four native gates pass.

| Group | Accepted native cases | Contract |
| --- | ---: | --- |
| `model` | 48 | Full TSV for empty/leading/repeated/trailing LF, CRLF retaining CR, all 256 byte values, invalid UTF-8, NUL, ordinary quotes, empty fields, runs at each position, read boundaries, realistic records and 16 seeded binary inputs |
| `admission` | 8 | Every supplied argument rejected before allocation or stdin reads, including help-like tokens, empty/non-UTF-8 arguments and oversized argument sets |
| `limits` | 8 | Exact 1 MiB ASCII/binary/final-LF inputs, one excess byte, exact/excess 65,536 records and an excess final unterminated record |
| `io` | 30 = 19 + 11 | One allocation baseline, all 11 reached input-growth OOMs, read/write/diagnostic failures, real I/O errors, confirmed output prefixes, signal failure and attempt budgets |

A was measured as **11** from the real 1 MiB baseline. The 64 fixed cases and
19 ordinary I/O cases include their baselines exactly once. Compiler calls and Python
controls are not native process cases. The `snapshot(1,0,0)` argv check is
allocation-free; admission tests assert no mapping or read instead of claiming
a nonexistent argv OOM site.

## Bounds and resource observations

The driver requires strict little-endian ELF64 x86-64 output and applies the
shared native jump validator. Traces select `read`, `write`, `mmap`, `munmap`,
`mremap`, `brk`, `openat`, `close` and `rt_sigaction`. They do not claim to observe
every possible host effect. The ledger pairs complete allocation addresses and
exact extents, rejects unaccounted allocation/file services, and requires every
mapping to be released. Standard descriptors are borrowed and must not be closed.

Each source request respects the remaining byte quota, with a real one-byte
probe at the cap. The three valid exact-cap inputs require an EOF result after
exactly 1 MiB of confirmed reads; the excess case requires that probe to return
one byte. Both record-limit rejection cases must first consume the full input
and observe EOF, while emitting no header. Exact-limit outputs are compared in
full, including all 65,536 rows.

Any stdout write requires observed EOF and exactly one live input owner. No new
allocation may occur after publication begins. Diagnostic writes require every
mapping to be retired. OOM injection selects baseline-observed ordinals, matches
their complete allocation-argument prefix, verifies the injected call was
reached, and requires no later allocation. Every injected syscall must be marked
as injected. The later-write failure case compares the complete output to the
prefix actually confirmed by the first baseline stdout write. All confirmed
stdout/stderr counts must equal the captured byte lengths. Synthetic zero-write
results test rejection only; they do not stand in for actual transfers. Closed
stdout and directory stdin exercise actual kernel I/O failures.

## Attempt budgets and diagnostic behavior

Full traces exercise 16,384 interrupted reads and 64 interrupted diagnostic
writes. Installed strace permits finite injection endpoints only through 65,534.
The two payload-budget cases therefore use continuous `1+`/`2+` injection and
require exactly 131,072 stdout attempts followed by 64 failed diagnostic attempts.
Every diagnostic request must be the complete 45-byte output-attempt-limit
message. These combined failures truthfully return 3 with no stderr; they do not
establish successful status-2 reporting for the output budget. The separate read
budget test does establish status 2 with a successful diagnostic.

The `2+` case first publishes the actual header; its complete stdout must remain
exactly that header after budget exhaustion. No rollback is claimed. Other
diagnostic failures override argument/allocation errors with status 3. Failed
SIGPIPE-ignore setup is silent status 3 before argv/input, including when stderr
is a real closed pipe. Observed phase diagnostics are checked exactly; the
argument-snapshot host-read failure has no injected execution case here.

## Native receipts

The root runner accepted **4 tests and 94 native process cases**:

| Group | Result | Rust build | Log under `target/stdlib-work/` | Evidence directory |
| --- | --- | --- | --- | --- |
| `model` | 48 cases, 1 test, 7.44 s | 1.77 s | `slice-record-summary-model.log` | `/tmp/record-summary-model-s4i8xjyn` |
| `admission` | 8 cases, 1 test, 7.23 s | 0.18 s | `slice-record-summary-admission.log` | `/tmp/record-summary-admission-5hg9vyhf` |
| `limits` | 8 cases, 1 test, 13.80 s | 0.19 s | `slice-record-summary-limits.log` | `/tmp/record-summary-limits-78eljkn5` |
| `io` | 30 cases, 1 test, 18.49 s | 0.20 s | `slice-record-summary-io.log` | `/tmp/record-summary-io-03kvpegw` |

All groups used the same accepted application source SHA-256
`c9f83694dc11e4314eacd9349465925331cbcad4d77b5a516bdde9dadf1bd2d3`
and oracle SHA-256
`27dc66f4b563901e39a9e77c2d35ae1498a3e4db5cd10d6d731247db21e92b62`.
No earlier or partial process attempts are added to these accepted counts.

## Running

`python3 -B oracle.py controls` runs only the host model and negative controls
for missing EOF, missing release and incorrect release extent. The four Rust
selectors are in `tests/stdlib_record_summary_execution.rs`; their suffixes name
the model, admission, limits and reached-failure groups. Each native subprocess
is bounded at 60 seconds and each oracle group at 85 seconds. Root alone runs
compiler/native commands serially under the outer command deadline.

Evidence is scoped to Linux x86-64 host execution of GPU-compiler output;
GPU-device execution, formal verification and forged-view memory safety remain
outside these application tests.
