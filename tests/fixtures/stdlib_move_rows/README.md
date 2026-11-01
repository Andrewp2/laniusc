# CSV row movement application evidence

Driver: `tests/stdlib_move_rows_execution.rs`.
Program: `sample_programs/library/move_rows.lani`.
The driver requires actual ELF64/little-endian/x86-64 output and uses the
shared jump-displacement gate when writing the executable. Each Rust test
process compiles the application once.

## Independent output model

Python's strict CSV reader decodes the selected valid corpus. A blank CSV row
is normalized from Python's empty list to this library's one empty field.
Relocation is expressed directly in original-table coordinates with list
concatenation, independently of the production extract/split/append sequence.
Python's CSV writer then quotes every field and emits CRLF. Complete bytes
must match, including cases where unchanged row order still canonicalizes
formatting. Row zero receives no header treatment.

| Group | Native cases / status | Scope |
| --- | ---: | --- |
| model | 33 accepted | Empty/full selections, original destination boundaries, moves in both directions, no-ops, duplicates, blank records, quoting/multiline/Unicode/BOM data, six seeded mixtures and output sizes around 1,024 bytes |
| admission | 29 accepted | Numeric/token/count rejection before input, exact help aliases, leading zeros, table-relative bounds after EOF and representative late CSV/UTF-8 failures |
| limits | 11 accepted | Actual 4 MiB EOF/excess probes, 16,384 rows, 64 fields, 8,192 field bytes, 65,536 record bytes and finite canonical empty-field expansion |
| io | 60 accepted | One successful baseline, 40 reached allocation denials and 19 input/output/signal/diagnostic/attempt cases |

The CSV checks exercise the new consumer composition without repeating the
existing parser's full grammar campaign. Invalid CSV and table-bound errors
must follow complete source collection, including observed EOF. Invalid
arguments perform no stdin reads. Argument storage is retired before help or
input collection.

## Reachable limits

The exact input-cap case has 64 records of eight 8,191-byte fields plus commas
and LF, totaling exactly 4 MiB. Traces require a real final one-byte request
returning zero, or returning one for the excess-byte case. Separate cases reach
each CSV limit and its first rejected value.

The 8 MiB output limit is defensive under this CLI's other bounds. If `F` is
the total field count and `R` the row count, canonical output is at most
`input + 2F + R + 1`: field quoting adds at most two bytes per field, line
ending normalization at most one per row plus one for an unterminated final
row. With `F <= 64 * 16,384`, this is at most 6,307,841 bytes, below 8 MiB.
No unreachable output-limit rejection is invented.

Staging uses an exactly reserved in-memory sink, so each 1,024-byte chunk is
accepted completely. Its 65,536-call ceiling is also defensive: at most
`ceil(total_output / 1024) + R <= 22,545` staging calls are needed. Invariant
status 6 and argument-capture host failure are not injected.

## Ownership and fault observations

The six-row fault baseline includes long, quoted, multiline and Unicode fields
and moves `[1,3)` before original boundary 5. Its complete successful mmap
schedule measured `A = 40`; no allocation ordinal is guessed. Each individual
ENOMEM must be reached, match the successful mmap argument prefix, emit the
exact allocation diagnostic, publish nothing and retire all earlier owners.
No later allocation is accepted after denial. The baseline is counted once.

After input retirement, this workload requires exactly three allocations:
two Record descriptors for extraction, one for the suffix split, and the
complete canonical output buffer. A Record contains two Vec descriptors,
six native words (48 bytes on this target). The first two observed extents
are therefore 96 and 48 bytes, followed by the independently computed output
length. Both consuming appends fit the original retained row capacity;
append-growth denial belongs to the direct library resource tests and is not
claimed here. `take` transfers the original row storage without allocating.

The ledger records full mapping addresses and extents, allowing address reuse
only after release. During collection exactly one input owner may remain.
After EOF, CSV parsing may allocate and release nested owners. The original
input must retire before stdout, and every payload write requires exactly one
live mapping, the final staged-output owner. All Record, outer-vector and argv
owners must already be retired. No publication-phase allocation is permitted;
all mappings retire once, and every diagnostic requires no live mappings.
Host negative controls retain a nested owner or argv through publication,
retire output early, leak an owner or use a wrong extent and must fail.

These are observations of nine filtered syscalls: `read`, `write`, `mmap`,
`munmap`, `mremap`, `brk`, `openat`, `close` and `rt_sigaction`. They do not
establish absence of every possible host effect. No descriptor opens/closes
are expected from this stdin/stdout consumer.

I/O faults include read/write EIO and EAGAIN, Interrupted, zero write, real
closed stdout, silent failed SIGPIPE setup with a real closed stderr pipe,
and failed diagnostics. Empty output with closed stdout is separate. A write
failure after one successful write must retain exactly the real first
1,024-byte output prefix. Captured stdout/stderr lengths must equal confirmed
successful write counts; positive successful transfers are never injected.

Finite strace schedules reach exactly 16,384 read or payload-write attempts,
within the installed tool's supported range. Both empty-prefix and confirmed
prefix write exhaustion produce the exact output-call-limit diagnostic and
status 2 after cleanup. A separate 64-attempt diagnostic exhaustion produces
status 3 and no diagnostic bytes. The baseline-derived allocation sweep and
these process cases do not claim same-process application retry; direct
library fixtures cover owner-preserving failure and recovery separately.

## Controls and receipts

```sh
timeout 90s python3 -B tests/fixtures/stdlib_move_rows/oracle.py controls
```

Host controls pass `model=33 admission=29 limits=11 io=20+A`. They check
literal moves, complete canonical CSV, record conservation, corpus generation
and negative ledger traces. They execute no Lanius program and contribute no
native case counts.

The model selector passed 1/1 with 33 native cases in 7.43 seconds, with a
separate 1.74-second build. Log:
`target/stdlib-work/vector-transfer-tool-model.log`; evidence directory:
`/tmp/move-rows-model-xcu8cuvz`.

Admission, limits and I/O then passed together, 3/3 in 18.08 seconds, with a
separate 0.19-second build and exit 0. They shared one command and compilation;
these are combined timings, not per-group measurements. Log:
`target/stdlib-work/vector-transfer-tool-remaining.log`.

| Accepted group | Native cases | Evidence directory |
| --- | ---: | --- |
| admission | 29 | `/tmp/move-rows-admission-he7j1zga` |
| limits | 11 | `/tmp/move-rows-limits-hw0op3no` |
| io | 60 | `/tmp/move-rows-io-vbupctjy` |

All four new application groups passed 133 native cases: 33 + 29 + 11 + 60.
The I/O summary was `cases=60 reached_allocations=40`; all 40 application
allocation denials were reached. The successful baseline is counted once.
Host controls, direct library fixtures and standalone examples add no cases
to this total. Source, driver and oracle stayed frozen at the hashes below.

Frozen consumer source SHA256:
`9bb0cf068dcb9327926e6b00b22afa9fa3c648fca10b4a92a90a5007f9584215`.
Driver SHA256:
`72465026d335b59adb4590a76fe2fbd5ed298ec5dd2e295a464a100ab1994f54`.
Oracle SHA256:
`bc5f2917adf81a01c2c44bb005ac4315ebfd57e437abc20e0c0fc4efc6652c94`.

Each native child is bounded to 60 seconds and each oracle to 85 seconds.
Root runs compiler/native commands serially under the repository lock and a
100-second outer bound. Initial execution acceptance is Linux x86_64 CPU
output from the GPU compiler, not user-program GPU execution, other hosts,
enforced ownership or formal proof. Existing CSV suites, direct vector tests,
library resource cases and standalone examples retain separate receipts.
