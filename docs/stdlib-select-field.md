# Select a UTF-8 field from either end

`sample_programs/library/select_field.lani` selects one literal-delimited field
from every stdin record. It combines public argument parsing, decimal parsing,
owned UTF-8 input, borrowed text cursors and staged output. Its implementation
uses `Text.splitn` and `Text.rsplitn`; it does not maintain a second delimiter
scanner. The byte-oriented GNU-compatible `text_cut` program remains separate.

All four executable test groups pass: 102 cases on native Linux x86_64 CPU
output produced by the GPU compiler. Fifteen host oracle controls also pass.
This acceptance covers the finite cases described below; it does not claim
GPU-device execution of the host-service program.

## Interface

```text
select_field --delimiter TEXT --field N [--from-right]
select_field --help
```

| Option | Meaning |
| --- | --- |
| `--delimiter TEXT`, `-d TEXT` | Literal UTF-8 separator; may contain several scalars or be empty |
| `--field N`, `-f N` | Positive one-based field number |
| `--from-right`, `-r` | Count fields from the right |
| `--help`, `-h` | Show help, only when supplied as the sole argument |

Both delimiter and field are required exactly once. Duplicate options,
unknown options and operands fail. The shared CLI parser also accepts
attached values such as `--delimiter=::`, `--field=2` and `-f2`, exact long
names, short groups and a `--` terminator. A terminator does not admit operands.

N contains 1..64 ASCII decimal digits and must fit a positive `u64`. Leading
zeros are allowed; signs, whitespace, prefixes, non-ASCII digits and overflow
fail. The delimiter must be valid UTF-8, contain no LF and fit 1024 bytes.
It may contain CR, which remains ordinary delimiter data. Process argument
transport cannot represent an embedded NUL; stdin records can contain NUL.

Records end at LF. One CR immediately before LF is part of the line ending
and is removed. A lone CR, including one at unterminated EOF, remains data.
The final nonempty unterminated record is included. A terminal LF adds no
phantom record, and empty stdin produces empty stdout. No BOM removal,
Unicode normalization, whitespace trimming or grapheme segmentation occurs.

Nonempty delimiters match literally and without overlap. Left selection
uses leftmost matches; right selection uses rightmost matches. For example,
field 2 of `ababa` with delimiter `aba` is `ba` from the left and `ab` from
the right. Leading, adjacent and trailing delimiters preserve empty fields.
An empty delimiter produces an empty field at each endpoint and one field
per Unicode scalar between them. Field 2 of `Aé界` is `A` from the left or
`界` from the right. Missing fields produce empty output lines.

Every actual input record produces one output record ending in LF. For an
executable built from the source, these examples have the stated expected
output; they are also covered by the runtime oracle:

```sh
printf 'left::middle::right\nx::y::z' | ./select_field -d :: -f 2
# middle
# y
printf 'Aé界\r\n' | ./select_field -d '' -f 2 -r
# 界
```

## Bounds, ownership and publication

The entire input must reach EOF, fit the input limit and validate as UTF-8
before any records are selected. Each record uses a cursor with quota `N+1`:
the extra slot prevents the Nth result from becoming the unsplit remainder.
The quota saturates at `u64::MAX` without overflow. Selection stops at cursor
exhaustion, so a huge missing position does not cause an N-iteration loop.

Fields borrow the input `String`; the delimiter borrows the argument
snapshot. These owners remain live through selection. The complete output
is staged in `alloc::io::Buffer` before the first stdout attempt. All three
owners are explicitly destroyed on success or failure, including retained
input failure owners. Stdin, stdout and stderr remain borrowed descriptors.

| Resource | Bound |
| --- | ---: |
| Captured arguments, excluding executable | 8 |
| Captured argument bytes | 4096 |
| Delimiter bytes | 1024 |
| Field-number token bytes | 64 |
| Input bytes | 1048576 |
| Input read attempts, including EOF and Interrupted | 16384 |
| Input records | 65536 |
| Staged output bytes | 2097152 |
| Data stdout write attempts | 8192 |
| Help stdout write attempts | 64 |
| Diagnostic stderr write attempts | 8 |
| Bytes requested per host read or write | 1024 |

Input may consume one extra byte to establish a byte-limit failure. The
output cap is conservative: selecting at most the input bytes plus one LF
per record fits within it. There is no separate claim of reaching that cap
with otherwise admitted input. Attempt budgets bound retries, not wall time;
one blocking host call can still wait indefinitely.

Argument, input, UTF-8, record-limit, allocation and staging failures produce
no data stdout. This admission guarantee is not atomic output: once the
accepted result starts publishing, an output error may leave a confirmed
prefix. Writes advance only by positive valid counts. Interrupted retries
spend attempts; zero, invalid counts, other errors or exhaustion stop output.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete data or help output |
| 2 | Invalid arguments or UTF-8; input, record, call or staging limit |
| 3 | Input, argument-capture or signal-policy failure; invalid input/storage count |
| 4 | Argument, input or output allocation failure |
| 5 | Data or help stdout failure |

SIGPIPE is ignored before argument capture. Failure attempts the fixed
31-byte diagnostic `select_field: operation failed\n` after owned cleanup.
Diagnostic failure preserves the primary exit status. Successful runs have
empty stderr.

## Focused acceptance

The four tests in `tests/stdlib_select_field_execution.rs` compile the actual
entrypoint once per test process with the native linker and execute the
resulting binary:

| Group | Accepted runtime cases |
| --- | ---: |
| Independent directional Unicode model | 44 |
| Argument and UTF-8 admission | 27 |
| Input, record and delimiter boundaries | 8 |
| Resource/publication failures | 23, including all 10 reached source allocations |

All 102 cases pass across the current receipts below. The final resource run
supersedes the resource portion of the earlier combined command:

| Receipt in `target/stdlib-work/` | Accepted scope | Runtime | Registered result |
| --- | --- | ---: | --- |
| `select-field-model.log` | Model: 44 cases | 8.14 s | 1 passed, 3 filtered |
| `select-field-boundaries-owners.log` | Limits: 8; admission: 27; earlier resources superseded below | 10.54 s | 3 passed, 1 filtered |
| `select-field-resources-final.log` | Resources: 23, including 10 reached allocation failures and exact retry budgets | 9.14 s | 1 passed, 3 filtered |

Retained evidence is in `/tmp/select-field-model-7m4q7n_n`,
`/tmp/select-field-limits-i5nwq0lm`, `/tmp/select-field-resources-sgoerbgb`
and `/tmp/select-field-admission-37cgo1ku`. The resource baseline reached
10 source allocations, and each allocation failed individually in a separate
accepted execution. The final gate also checks exactly 16,384 read attempts,
8192 stdout-write attempts and eight diagnostic-write attempts under their
respective continuous-EINTR schedules.

The model uses complete regular-expression partitions over Unicode scalars,
including reversed scalar strings for rightmost matching. It is independent
of the Lanius bounded lazy cursors. The fixed and seeded corpus covers
multi-scalar separators, overlap direction, empty endpoints, CRLF/lone CR,
NUL, combining scalars, missing fields and `u64::MAX`.

Resource tests verify executable syscall sites with the shared native-link
`source_allocations.py` verifier before fault injection. Global syscall
ordinals choose injections, while exact source sites determine ownership.
Every reached source allocation is failed individually; read, signal,
stdout, retry-budget and closed-pipe failures also execute. Each trace checks
source allocation/release balance, no publication before EOF, no source
allocation after publication and bounded source I/O. Native-library and
verified CRT bootstrap traffic are classified separately.

Fifteen host-only controls currently pass: six reference witnesses, two
valid native-link trace shapes and seven deliberately corrupted observations.
Run them without compiling or launching Lanius code:

```sh
timeout --kill-after=2s 100s python3 -I -B \
  tests/fixtures/stdlib_execution/select_field/oracle.py controls
```

Runtime tests use the project's serialized GPU compiler lane. Each oracle
group has an 85-second outer process bound and each child execution has a
12-second bound. The fixture README lists the exact selectors. Runtime
receipts and host controls are separate evidence.
