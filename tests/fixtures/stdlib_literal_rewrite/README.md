# Literal rewrite application tests

The driver compiles `sample_programs/library/literal_rewrite.lani` to a strict
ELF64 x86-64 executable and applies the shared native jump check. Every process
reads a real input file through stdin. An independent Python Unicode model
compares the complete stdout bytes using literal, leftmost, nonoverlapping
replacement. Python count is bounded to the number of possible matches so the
model accepts the application's full u64 count range without a host signed-count
restriction. No production implementation or model is imported.

## Corpus

| Group | Native process cases | Main checks |
| --- | ---: | --- |
| `model` | 29 | Empty text/needle/replacement; no-match, deletion, unchanged and growth; overlap and no rescanning inserted text; literal metacharacters; NUL/line endings; multibyte/combining text without normalization; count zero/exact/past-end/u64 maximum; 1,023/1,024/1,025-byte transfer edges |
| `admission` | 30 | Missing/extra/unknown operands/options, decimal/count bounds and duplicates, UTF-8 argument bounds, sole help, intermixed `--count=N`, `--` literals, malformed complete input including count zero |
| `limits` | 7 | Actual 256 KiB EOF/excess probes; independently reachable exact/excess 1 MiB output; exact replacement-byte cap; restricted empty-needle expansion; shrinking full input to empty output |
| `io` | 28 = 16 + 12 | One measured baseline; every actual allocation denied; read/write retries and failures; confirmed prefix, WouldBlock and write-zero; SIGPIPE/help/diagnostic behavior; read and combined-copy call exhaustion |

The three non-I/O groups contain 66 cases. The I/O group measures A from its
baseline and denies
each actual mmap once; it does not guess ordinals. Its 16 ordinary cases count
the baseline once. Host controls, compilation and standalone examples are not
native process counts.

## Ownership and transfer evidence

The finite trace filter covers nine syscall names: `read`, `write`, `mmap`,
`munmap`, `mremap`, `brk`, `openat`, `close` and `rt_sigaction`. It does not claim
to observe every possible host effect. The application borrows standard streams;
no file opens/closes, mremap or brk are permitted. The first observed operation
sets SIGPIPE to Ignore.

The ledger tracks full-width addresses and exact allocation/release extents.
Argument owners are identified from the snapshot's descriptor allocation and
optional packed-byte allocation. Each input read requires those identities plus
exactly one current collector owner. Growth may allocate its replacement before
retiring the previous input mapping. The real EOF read identifies the final
input owner. A nonempty replacement result must allocate exactly its complete
byte length after EOF, while input and arguments are still live. Empty output
allocates nothing.

Before every stdout attempt, input and arguments must have retired and only the
exact staged result mapping may remain live. There is no allocation after input
retirement or during output. Output retirement precedes every ordinary
diagnostic; help also requires all owners retired. Successful no-match/count-zero
outputs therefore demonstrate independent storage after original owners retire.
Every observed successful mapping must receive one same-address/same-extent
release, including partial collection and reached allocation failures.

The input boundary checks require a real final one-byte request returning zero
or one after exactly 262,144 prior bytes. Invalid UTF-8 is rejected after full
input EOF, even with count zero. Output overflow rejects before result allocation
or stdout. For an independent output-cap witness, `b` followed by 209,715 `a`
bytes expands under `a` to `aaaaa` to exactly 1,048,576 bytes; one additional `a`
exceeds only the output cap, with input still below its own limit.

Each injected call must actually be reached and marked. Allocation failures
must match the baseline's complete allocation-argument prefix and stop further
allocation. Confirmed stdout and stderr byte totals must equal actual captured
bytes; no positive successful write count is fabricated. One write-zero result
is injected as a failure case and confirms no bytes.

The output budget is **4,096 total direct Copier provider calls**, including
local SliceReader reads and actual stdout writes. A first stalled write permits
4,095 stdout attempts after one local read. A confirmed first 1,024-byte write
allows a second local read and then 4,094 total stdout attempts. Supported finite
EINTR schedules target exactly those attempts, allowing the next diagnostic
write to succeed. Both cases require status 2, the exact confirmed stdout prefix,
and an exact `written=0` or `written=1024` diagnostic. The input budget separately
reaches 4,096 read attempts. Broken diagnostic output preserves the primary
usage status; failed SIGPIPE setup is silent status 3. Empty successful output
works even with stdout connected to a closed pipe.

## Accepted execution

Host-only controls pass: independent literal/Unicode examples, corpus counts and
negative ownership/publication traces. They do not execute Lanius.

The final observer passed all **4 groups and 94 native process cases**:
29 model, 30 admission, 7 limits and 28 I/O cases, including **12 reached
allocation denials**. The groups ran together in 9.91 seconds after a separate
0.19-second Rust build. No isolated per-group timings are claimed. The final
receipt is `target/stdlib-work/text-replacement-app-final.log`.

| Group | Final evidence directory |
| --- | --- |
| `model` | `/tmp/literal-rewrite-model-0wrsiqdt` |
| `admission` | `/tmp/literal-rewrite-admission-lx91561q` |
| `limits` | `/tmp/literal-rewrite-limits-a0u6sr8k` |
| `io` | `/tmp/literal-rewrite-io-6xsigrj1` |

The initial native run passed the same 94 cases in four groups, 9.71 seconds
after a separate 1.05-second Rust build (`target/stdlib-work/text-replacement-app.log`).
It measured A = 12: two argument allocations, nine collector capacities and one
exact output allocation. Review then found that the old observer did not require
argument owners to remain live between EOF and output allocation. The application
was correctly ordered. The oracle now checks all argument identities and the
current input address/extent at every output allocation attempt; added host
negative controls reject retirement in that interval. The old oracle hash was
`f93a83d83ed16deb50d583f6261bca433c28eaa2923dfa3ca48b39287e239509`.
The final focused rerun replaces this weaker observation without adding duplicate
cases or changing the application/driver. The unique accepted count remains 94.

Standalone compilation passed separately with an empty
`target/stdlib-work/text-replacement-cli-build.log`. Two guide examples passed
in `text-replacement-cli-examples.log`: `ababa` replacing `aba` with `X` produced
three bytes `586261`; UTF-8 `é`, NUL and `x` with an empty needle and `|`
replacement produced eight bytes `7cc3a97c007c787c`. Neither adds to native case
counts.

The four selectors in `tests/stdlib_literal_rewrite_execution.rs` have an
85-second oracle deadline and a 60-second per-process deadline. Root alone ran
bounded compiler/native commands serially. The accepted target is Linux
x86-64 CPU execution of GPU-compiler output, not a device kernel.

Argument-capture host-read failure, defensive internal replacement errors,
isolated help/diagnostic attempt exhaustion, exhaustive error combinations,
other hosts and formal verification are not claimed as exercised paths. Literal
search retains the library's documented O(source bytes × needle bytes) worst
case; this fixture establishes behavior, not a throughput guarantee.

Tested application source SHA-256:
`e1a142eca57bc4266c0b28cca0e1f3a83db427c2e3cf041825d7f891c428e75d`.
Final whitespace checking removed only one extra trailing newline, yielding
`513c569e58a1a929313fccb7d1fb6221bd48472b3bde619e9823926455adf2b2`.
All other source bytes remain identical; native tests were not repeated for it.
Driver SHA-256:
`7cc56012816697eda0ced3ae7cd64d7712d6d9f00d04e3c19ce2097274f53424`.
Oracle SHA-256:
`2c0f7460c964db75744c48fbf2d85c0d9426ff62548d484f7da40b838c12b66c`.
Help is compared with the agreed 1,114-byte literal. Emitted diagnostics are
compared byte-for-byte, including confirmed written counts for output failures.
