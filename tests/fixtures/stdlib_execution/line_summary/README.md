# Line-summary application evidence

This oracle checks the real `line_summary` stdin-to-TSV program. Python models
the complete output independently: split only at LF, remove CR only immediately
before that LF, suppress only the final phantom line, and use exactly HT, LF,
VT, FF, CR and space as word separators. It counts bytes before decoding each
line's final Unicode scalar. Python `splitlines` and Unicode whitespace splitting
are deliberately not used.

The Rust driver requires a little-endian ELF64 x86-64 executable, applies the
shared native jump validator, and executes each group separately. Native
acceptance and CPU generator/ledger controls have passed.

## Corpus

| Group | Accepted native cases | Contract exercised |
| --- | ---: | --- |
| `model` | 44 | Complete TSV for empty input, LF/CRLF/lone CR, leading/repeated/trailing terminators, NUL, six ASCII separators, Unicode spaces/separators, every UTF-8 width, combining marks, noncharacters, read boundaries, a realistic report, and 16 reproducible generated inputs |
| `admission` | 20 | Eight argument rejections before allocation/reads and twelve invalid UTF-8 forms before any header |
| `limits` | 8 | 1 MiB ASCII/Unicode and invalid final byte, actual extra-byte probe, exactly/excess 65,536 lines with empty and unterminated final records |
| `io` | 30 = 19 + 11 | One successful 1 MiB baseline; all 11 reached input allocations; read/write failures and retry, actual read/output errors, confirmed stdout prefix, signal/diagnostic failures, all three attempt budgets |

The 72 fixed cases and 19 ordinary I/O cases are counted once each. The I/O
baseline measured **A = 11** reached allocations, rather than guessing their
ordinals. Compiler invocations and
Python controls are not native process cases. The `snapshot(1,0,0)` argv check
allocates nothing, including when it rejects an argument. There is no argv OOM
site; the admission oracle requires no mapping or read instead of manufacturing
one. Input OOM tests use every real allocation observed in the 1 MiB baseline.

## Observable ownership and publication

The syscall ledger traces `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`,
`openat`, `close`, and `rt_sigaction`. Mappings use complete addresses and exact
requested extents; every successful mapping must have a matching release.
Unaccounted allocation services and file opens/closes are rejected. Standard
descriptors are borrowed, so the application must not close them.

Every observed source request is bounded by the remaining input budget, with
a one-byte request at the cap. The two valid cap cases require a final one-byte
EOF read after exactly 1 MiB; the excess case requires that request to return
one byte. Output cannot start before observed EOF. Exactly one input mapping
is live while rows are written, and no new allocation may occur after output
starts. Diagnostics require all mappings to be retired first. Exact final
stdout comparisons catch publication before UTF-8 or line-count admission.

Every injected syscall must be reached and marked as injected. OOM runs match
the complete allocation-argument prefix of the baseline and must allocate no
further owner. The output-failure witness selects the second real stdout write
from the baseline and compares the entire actual output to the prefix confirmed
by the first write. All confirmed stdout/stderr write counts must equal the
captured byte counts. A synthetic zero write tests failure handling only; it
does not claim a real transfer. Closed stdout and directory stdin exercise
actual kernel I/O failures.

The read and isolated diagnostic budgets use full traces of 16,384 and 64
reached EINTR injections respectively. Installed strace restricts finite
injection endpoints to 65,534, so the payload-budget cases use continuous
`1+`/`2+` injection. They require exactly 131,072 stdout attempts, followed by
64 failed diagnostic attempts, and honestly expect final status 3 with empty
stderr. Every diagnostic request must contain the complete 43-byte write-limit
message, establishing selection of the output-limit branch despite its failed
reporting. One case first publishes the header before the remaining 131,071
stdout attempts fail; its complete stdout must remain exactly that header.
Successful output-limit diagnostic/status-2 reporting is not directly exercised
by these combined failures. The independent read-limit case does establish
status 2 with its successful diagnostic. Failed writes spend attempts.
Failed SIGPIPE setup exits silently with status 3 before argv,
input or diagnostic operations, including when stderr is a closed pipe.
Phase-specific diagnostic literals are agreed with the app
author; diagnostic failure changes the exit status to 3, including after a
primary argument or allocation failure. No rollback is claimed once stdout
has a confirmed prefix.

## Accepted execution

The root runner accepted **4 tests and 102 native process cases**:

| Group | Test result | Log under `target/stdlib-work/` | Evidence directory |
| --- | --- | --- | --- |
| `model` | 1 passed, 44 cases, 7.73 s | `text-line-summary-model.log` | `/tmp/line-summary-model-vd9gdexv` |
| `admission` | 1 passed, 20 cases, 7.27 s | `text-line-summary-admission.log` | `/tmp/line-summary-admission-5_683euw` |
| `limits` | 1 passed, 8 cases, 11.84 s | `text-line-summary-limits.log` | `/tmp/line-summary-limits-albvnkx0` |
| `io` | 1 passed, 30 cases, 17.11 s | `text-line-summary-io-revised.log` | `/tmp/line-summary-io-fs9rympm` |

The earlier I/O attempt in `text-line-summary-io.log` stopped at harness setup:
installed strace rejected the finite `1..131072` injection expression before
that case executed. It was not an application failure. Its partial processes
are excluded from accepted counts; the complete revised I/O group above is the
accepted receipt. No production budget was reduced. The model, admission and
limit group behavior and trace commands were unchanged by that I/O-only repair.

Accepted application source SHA-256:
`ebbf42590aae82d90ed8d4c58d2b36d64c736f082509a32f934d4a7f4b64d5a2`.
Final oracle SHA-256:
`9d4da56fe2b8367a0c498f2ed6dcb6df0ee69d33bcd5d27e53bee80cb4197db0`.
The first three groups ran before the I/O-only repair, with oracle SHA-256
`53439150d6f4bd1b2f6fdbf33ac2a24c7d22875e99a28975d38f46ba5cc9b9e3`.

## Running and evidence scope

`python3 -B oracle.py controls` runs only host-side independent model and
deliberately broken ledger controls. Native selectors in
`tests/stdlib_line_summary_execution.rs` are:

- `line_summary_matches_independent_complete_tsv_for_text_partitions`
- `line_summary_rejects_arguments_and_invalid_utf8_before_publication`
- `line_summary_exact_byte_probe_and_line_limits_execute`
- `line_summary_reached_allocation_io_and_attempt_failures_release_owners`

Each native process has a 60-second timeout and each group has an 85-second
timeout. Root runs the compiler/native commands serially under the outer command
deadline. These tests establish Linux x86-64 host behavior, not GPU-device
execution, formal verification, or validity of arbitrary forged borrowed views.
