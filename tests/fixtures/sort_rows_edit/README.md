# Owned row editing application fixture

This focused fixture executes the existing `sort_rows` program with its new
`--drop-empty`, `--unique` and `--limit` options. The independent Python model
validates every numeric key, selects nonempty keys, applies Python's stable
sort, keeps the first representative using a set, then slices the data-row
list. Header handling is separate. It does not reproduce vector compaction,
adjacent deduplication or truncation internals.

The fixture imports the existing CSV writer, strict decimal reference and
exact help bytes from `stdlib_execution/sort_rows/oracle.py`. Import has no
native or corpus side effects. Complete output is compared against quoted
CRLF CSV, preserving original numeric spellings and all retained fields.

| Group | Native process identities | Scope |
| --- | ---: | --- |
| model | 22 | All text editing/direction combinations; numeric equality and stable first representatives in both directions; header exclusion; selected columns; quoted commas/quotes/newlines, Unicode distinctions; empty input/keys, whitespace keys, zero limits and unterminated final record |
| admission | 17 | Full CSV/UTF-8/control/field/column/numeric validation despite limit zero; invalid empty numeric keys despite filtering; exact 16,384 data rows and excess rejection; unique-key work admission; actual 4 MiB EOF and one-byte excess probes |
| cli | 26 | Duplicate/value/new-alias rejection before any input read, help validation, leading zeros, maximum and zero limits, end-of-options |
| io | 67 = 10 + 57 | One shared successful baseline, every baseline allocation denied once, selected real read/write faults, confirmed first-write prefix, output-call exhaustion, actual closed pipe, signal setup and diagnostic failure |

`A` is the successful baseline's observed allocation count, not a guessed
ordinal or an extra calibration process. The baseline contains a header,
empty rows, duplicate rows, a truncated row and two retained rows whose
output exceeds 1,024 bytes. It therefore exercises all three editing phases
and nested Record cleanup. Each ENOMEM process must reach the selected mmap,
match every baseline mmap argument through that request, return 4, publish
nothing and make no later allocation. The final exact count is printed and
checked as `10 + A` inside the oracle.

All native processes use the same finite nine-syscall trace filter: `read`,
`write`, `mmap`, `munmap`, `mremap`, `brk`, `openat`, `close`, `rt_sigaction`.
The ledger tracks exact full-width addresses, extents and allocation
generations, accepting later address reuse. At every payload write, the only
live owners may be the original argv mappings and the final staged-output
mapping. Original input and all Record/Row owners must have retired. No
allocation may occur during output. At ordinary diagnostics, only argv
mappings may remain; those retire before process exit. Every observed mapping
must have one matching successful release. Unexpected descriptor or alternate
allocation services fail the observation.

The second-write EIO case compares actual stdout to the first successful
baseline write. The write-budget case performs one real 1,024-byte write,
then injects EINTR into writes 2..16,384. The bounded diagnostic is delivered
after those failures, and final status is 5 with the exact confirmed prefix.
This finite strace range is supported by the installed tracer. No positive
read/write count is fabricated. Diagnostic failure preserves primary status 2.

Host controls check every successful input/output CSV reference, operation
ordering, numeric validation before selection, group counts, and reject six
corrupt lifetime/extent traces. They are separate from native acceptance.
The Rust driver compiles once per process, requires a real x86_64 ELF, and
uses the shared direct-jump check through `TempArtifact.write_bytes`.
Each Python child has a 30-second bound; each registered group has an
85-second bound. Root runs each command under its outer 100-second limit.

```sh
python3 -B tests/fixtures/sort_rows_edit/oracle.py controls
python3 -B tests/fixtures/sort_rows_edit/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/sort_rows_edit/oracle.py admission PATH_TO_ELF
python3 -B tests/fixtures/sort_rows_edit/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/sort_rows_edit/oracle.py io PATH_TO_ELF
```

## Accepted native application gates

All four new registered gates passed on the frozen source and observer:
**132 native Linux x86_64 process cases**, comprising 22 model, 17 admission,
26 CLI and 67 I/O cases. The I/O group includes **57 reached allocation
denials**, one for every allocation in its single shared successful baseline.
No separate calibration process is added to those counts.

| Group | Cases | Test duration | Log under `target/stdlib-work/` | Retained evidence |
| --- | ---: | ---: | --- | --- |
| Model | 22 | 7.42 s | `vec-edit-app-model.log` | `/tmp/sort-rows-edit-model-kzbkcdj9` |
| Admission | 17 | 14.49 s | `vec-edit-app-admission.log` | `/tmp/sort-rows-edit-admission-n8edru9l` |
| CLI | 26 | 6.98 s | `vec-edit-app-cli.log` | `/tmp/sort-rows-edit-cli-qm72lm0g` |
| I/O | 67 | 7.87 s | `vec-edit-app-io.log` | `/tmp/sort-rows-edit-io-gdhdl8ur` |

Each log records one passing Rust test. These are separate test durations,
including the group's GPU compilation and native processes; they do not
represent a combined run or a separate Rust build time. The executable passed
strict ELF and shared direct-jump checks before native CPU execution.
Host controls and independent source/oracle review are separate evidence.

Executed source SHA-256:
`7c0eec2c872ae505cb513fc40b13098b1c7922805701cd9b8d5a51e41c5796ab`.
Driver SHA-256:
`b4ec4f4d10e1feccafe61e2057913f1b440c11a731456a18c01ef30bcc3fa3aa`.
New oracle SHA-256:
`95c3bb0be1524d60453012b90b75ddcb89236dc0272d653059866e251252a518`.
Imported CSV/decimal/help reference SHA-256:
`c13f31437381a8c10bc03a0c147dbeb442626104a858c9c412a9b545102c9140`.

The selected existing CLI, rejection and model groups also passed:
**109 regression cases** (39 + 33 + 37), separate from the 132 new cases.
`target/stdlib-work/vec-edit-app-regressions.log` records three passing tests
in **10.83 seconds combined**, with one test filtered. This does not assign
individual group timings. Retained evidence is
`/tmp/sort-rows-cli-0kpcbv45`, `/tmp/sort-rows-rejection-dfs8jqf9` and
`/tmp/sort-rows-model-avl9o3v3`, respectively.
Only the existing oracle's help expectation and length control change for
the intended new CLI; historical receipts retain their earlier scope.
The older 14-case I/O group was filtered because the new 67-case failure
group directly exercises the changed edit paths and cleanup with all 57
baseline allocations denied. No rerun of that older I/O group is claimed.

This finite application ledger is not formal verification or a proof of
arbitrary ownership safety. It does not identify each individual Record's
destruction order before publication, measure comparator/callback counts, or
prove allocation-free library editing; those belong to direct library gates.
No new exhaustive parser campaign, output-cap rejection, staging-call-limit,
argument host-read failure or status-6 invariant failure is claimed. The
existing 8 MiB output and staging bounds remain defensive for admitted input;
filtering, deduplication and limiting cannot expand the output. GPU compilation
to native Linux x86_64 is distinct from executing user code on a GPU.
