# Field-selection executable oracle

This fixture executes `sample_programs/library/select_field.lani` through
`tests/stdlib_select_field_execution.rs`. Source behavior is documented in
`docs/stdlib-select-field.md`. It targets Linux x86_64 CPU output from the
GPU compiler and requires Python 3, strace and the shared native-link ELF
inspection tools used by `native_c/source_allocations.py`.

## Groups

| Selector in `stdlib_select_field_execution` | Group | Cases |
| --- | --- | ---: |
| `select_field_matches_literal_unicode_fields_in_both_directions` | `model` | 44 |
| `select_field_validates_arguments_and_utf8_before_publication` | `admission` | 27 |
| `select_field_enforces_input_record_and_delimiter_limits` | `limits` | 8 |
| `select_field_reached_allocation_and_io_failures_release_owners` | `resources` | 13 + A |

A is the number of source allocations actually reached by the traced
baseline. The oracle injects ENOMEM at each one, requires that exact source
call to be reached, checks status 4 and empty stdout, and balances surviving
source owners. It never guesses allocation ordinals from a previous binary.

The independent output model uses complete regex partitions rather than
implementing the bounded Lanius cursors. Reverse matching reverses Unicode
scalars and the literal delimiter before partitioning. Seed `0xF1E1D2026`
fixes the generated corpus. Cases include empty/missing fields, overlapping
matches with different directional answers, scalar and multi-scalar
delimiters, CRLF, lone CR, NUL and enormous field positions.

Input byte, record-count and delimiter bounds have exact and excess cases.
Admission cases require empty stdout on bad arguments or malformed input,
including invalid UTF-8 after a previously valid record. Help bypasses
malformed stdin. The output cap exceeds all otherwise admitted output and
is not presented as an independently reached limit.

Resource observations classify every traced post-syscall IP through the
current verified native-link profile. The reused source-map ledger binds
mapping sizes, flags and release sizes to exact source sites. Native and
CRT bootstrap mapping traffic is permitted only under its separate verified
classification. Fault schedules use global syscall ordinals, and injection
outside source code is rejected. Source reads must precede EOF and output;
source allocations must precede output. Cleanup after publication is allowed.

Single faults cover early/late read and write EIO, zero writes, successful
EINTR retries and signal setup. Infinite suffix EINTR schedules exercise
read/write attempt limits, using syntax supported by strace 6.8. Closed
stdout is tested with nonempty and empty input. A late write fault must
leave exactly the first confirmed 1024 output bytes. The write-budget case
also interrupts every bounded stderr attempt, so it expects no diagnostic.

Each executable invocation has a 12-second timeout. The registered Rust
test gives its complete oracle group 85 seconds. Evidence remains in the
printed `/tmp/select-field-GROUP-*` directory, including input files,
native-link syscall traces and verified source-mapping traces.

## Host controls and native acceptance

```sh
timeout --kill-after=2s 100s python3 -I -B \
  tests/fixtures/stdlib_execution/select_field/oracle.py controls
```

Current result: `select-field-controls=15 model=44 admission=27 limits=8 resources=13+A`.
The controls check six exact model witnesses, two admitted trace shapes
(including terminal CRT cleanup), and seven rejected mutations: publication
before EOF, leaked or double-freed source ownership, an unknown executable
syscall site, allocation during publication, read after EOF and injection
into a native-library read.

All four selectors passed on native Linux x86_64 CPU output produced by the
GPU compiler: 102 executable cases, with A = 10 reached source allocations.
This is finite runtime acceptance for the listed cases, with no GPU-device
execution claim.

| Receipt in `target/stdlib-work/` | Accepted cases | Runtime | Registered result |
| --- | --- | ---: | --- |
| `select-field-model.log` | Model 44 | 8.14 s | 1 passed, 3 filtered |
| `select-field-boundaries-owners.log` | Limits 8, admission 27; earlier resources superseded below | 10.54 s | 3 passed, 1 filtered |
| `select-field-resources-final.log` | Resources 23, including 10 reached source allocations and exact retry budgets | 9.14 s | 1 passed, 3 filtered |

The corresponding evidence directories are
`/tmp/select-field-model-7m4q7n_n`, `/tmp/select-field-limits-i5nwq0lm`,
`/tmp/select-field-resources-sgoerbgb` and
`/tmp/select-field-admission-37cgo1ku`. The resource group includes individual
ENOMEM runs at each of the 10 reached source allocations; all passed the
status, publication and source-owner checks. The final resource receipt
supersedes the earlier combined resource run and additionally asserts exactly
16,384 read attempts, 8192 stdout-write attempts and eight diagnostic-write
attempts under the corresponding continuous-EINTR schedules.
