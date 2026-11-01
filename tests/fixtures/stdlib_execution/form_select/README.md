# Form selection application evidence

Real program: `sample_programs/library/form_select.lani`.
Driver: `tests/stdlib_form_select_execution.rs`.
The driver requires actual ELF64/little-endian/x86-64 output and uses the
shared jump-displacement check when writing the executable. Each Rust test
process compiles the app once.

## Independent model and corpus

Python splits nonempty `&` segments at their first `=`, replaces original plus
bytes, and applies `urllib.parse.unquote_to_bytes`. Complete outputs use
`quote_from_bytes`, with its always-safe `~` escaped and `%20` converted to
`+` for the form policy. Keys and values stay bytes. The oracle preserves
duplicate matches and compares the entire canonical wire, not parsed equality.

| Group | Native cases / status | Scope |
| --- | ---: | --- |
| model | 32 accepted | Literal keys, empty segments/names/values, duplicates/order, all 256 value bytes, non-UTF-8/NUL values, Unicode, malformed percent, one-pass decoding and exact output lengths around 1,024/4,096 bytes |
| admission | 5 accepted | Missing/extra arguments and excessive ASCII/non-UTF-8 key sizes before allocation/input |
| limits | 10 accepted | Actual 1 MiB EOF/excess probes, 4,096-byte key, independently reachable selected output cap, unselected expansion, exact/excess 65,536 pairs and exact decoded/component cap |
| io | 39 accepted | One real baseline, 20 reached allocation failures and 18 I/O/signal/attempt cases |

`A = 20` is measured from the successful baseline, not an assumed mmap ordinal.
The baseline reaches two argv allocations, all 11 collector growth sizes,
both Form buffers and five selected-descriptor growth allocations. Every injected ENOMEM must
be reached and match the complete successful mmap argument prefix; no later
allocation is accepted. The baseline is counted once.

Decoding cannot expand input. Separate decoded/component excess is therefore
unreachable under this CLI's input cap, and no such rejection is invented.
The output cap is independently reachable: raw binary values expand to `%HH`.
Malformed percent input remains literal data and is not a syntax rejection.

## Resource and failure observations

Every mapping is tracked by full address and extent. The input buffer and
argv allocations are identified during collection. At EOF, independently
computed decoded sizes bind exact Form byte/span allocations; matching-pair
counts bind selected-descriptor growth. Every stdout attempt requires those
specific Form owners and the current selected descriptor buffer to remain
live, along with input and argv. This includes the interval before the first
write, which host negative controls deliberately violate. Legitimate old
selection buffers may retire during growth. No publication-phase allocation
or release followed by a later write is accepted. Input must retire after
Form/selection and before argv; all observed owners retire once.

The layout assertions are for current x86_64 output: PairSpan has three
eight-byte scalar slots; Pair has two five-word Views. Packed u8 storage stays
byte-sized. These checks match the direct form resource fixture and existing
slice-view layout evidence; they are not a portable ABI promise.

The trace observes `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`, `openat`,
`close` and `rt_sigaction`. It rejects descriptor closes/opens and extra
allocation services within that filtered scope. It does not observe every
possible host effect. All stdout bytes must be backed by confirmed successful
write counts; no positive write success is injected.

Faults cover EIO/EAGAIN/Interrupted, zero write, actual closed stdout,
directory stdin, quiet argument rejection with closed stderr, and failed
SIGPIPE setup with a real closed stderr pipe. No-match output with closed
stdout is separate. The finite read schedule reaches 16,384 calls. Supported
continuous write schedules `when=1+` and `when=2+` exercise the combined
131,072-provider-call budget: one encoding read plus 131,071 attempted writes,
or two reads plus 131,070 attempted writes with the first real 1,024-byte
prefix retained. Both return quiet status 2. No unsupported large finite
strace range is used.

## Host controls and native receipts

```sh
timeout 90s python3 -B tests/fixtures/stdlib_execution/form_select/oracle.py controls
```

Host-only controls pass `model=32 admission=5 limits=10 io=19+A`. They validate
literal expected wires, corpus construction and negative ownership traces.
They execute no Lanius programs and add no native case counts.

Three native groups passed on their first run: model 32, limits 10 and
admission 5, totaling 47 native process cases. All three shared one command
and one compilation: 10.08 seconds for the tests, with a separate 1.81-second
build, exit 0. These are combined timings, not per-group measurements. Log:
`target/stdlib-work/form-select-model-admission-limits.log`.

| Accepted group | Evidence directory |
| --- | --- |
| model | `/tmp/form-select-model-edis_gzd` |
| limits | `/tmp/form-select-limits-gohiwggj` |
| admission | `/tmp/form-select-admission-4v331i6v` |

The I/O selector
`form_select_reached_allocation_io_and_copy_call_failures_release_owners`
then passed 1/1 in 20.98 seconds, with a separate 0.20-second build. Its exact
summary was `cases=39 reached_allocations=20`, evidence directory
`/tmp/form-select-io-pa5d2g2f`, log
`target/stdlib-work/form-select-io.log`.

All four groups passed 86 native application cases: 32 + 5 + 10 + 39. The
20 reached application allocation denials are separate from the six library
resource denials. The successful allocation baseline is counted once; host
controls add no native executions. Source, oracle and driver stayed frozen.
Source SHA256:
`ba4ee6321df189f7f02e2fa48a1799d8a25c86cb2a2bd9f74a900f000d434556`.
Oracle SHA256:
`725fd3745e269b181900c7e7fa9008df2b3a9a0f9fc6c0f9f85482eb581b2896`.
Driver SHA256:
`62d3ee064da219c1cf4f23d5dbd287dac638b888436d410041369e66bbf854d6`.

The standalone CLI compile exited 0 with an empty
`target/stdlib-work/form-select-cli-build.log`. Both examples in
`docs/extended-form-select.md` then returned 0 with empty stderr and exact
30-byte/22-byte outputs; receipt:
`target/stdlib-work/form-select-cli-examples.log`. Those two example processes
are separate from the focused native counts.

Each native child is bounded to 60 seconds and each oracle to 85 seconds,
inside the root's outer command limit. Initial execution acceptance is Linux
x86_64 CPU output of the GPU compiler, not user-program device execution or
other hosts. Argument-capture host failure is not injected. Library-level
form contracts, models and resource tests retain separate scopes and counts.
