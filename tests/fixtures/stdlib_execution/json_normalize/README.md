# Streaming JSON normalizer application evidence

The real program is `sample_programs/json_normalize.lani`; the driver is
`tests/stdlib_json_normalize_execution.rs`. The Rust driver checks actual
ELF64/little-endian/x86-64 output and uses the shared jump-displacement gate
when writing the executable. It compiles once per test process.

## Independent oracle

Python's JSON parser supplies ordered member pairs and unrounded number-token
strings. A separate renderer spells the exact compact UTF-8 output, preserving
duplicates/order and all number spellings and using lowercase control escapes.
Full stdout bytes are compared. Literal controls guard the reference behavior.

| Group | Accepted native process cases | Scope |
| --- | ---: | --- |
| model | 25 | Scalar/aggregate values, duplicate keys, Unicode/control escaping and exact output lengths around 1,024/4,096-byte boundaries |
| admission | 15 | Eight allocation-free no-argument rejections and seven malformed/invalid UTF-8 inputs with quiet status 2 before stdout |
| limits | 9 | Actual cap EOF/excess probes, exact 1 MiB number/output, independent expanded-output admission, depth 128/129 and node count 65,536/65,537 |
| io | 51 | One successful allocation baseline, 33 baseline-derived reached ENOMEM cases, and 17 I/O/signal/attempt-limit cases |

`A = 33` is the successful baseline's actual allocation count: 11 input growth
allocations and 22 parse allocations. Every baseline allocation is failed
individually, including input growth and parse ownership.
No guessed mmap ordinal or duplicate calibration count is used. The baseline
is itself one native process case. Its exact mmap argument prefix must match
each reached injection, and no later allocation is accepted after ENOMEM.

The trace ledger checks full mapping addresses and extents, rejects unpaired
releases and leaked owners, and identifies the input mapping from real reads.
At stdin EOF that owner must still be live. It must retire before stdout, and
there may be no allocation after its retirement, including output preflight
and streaming. Document retirement must follow the final attempted write.
The scope is the nine filtered syscalls `read`, `write`, `mmap`, `munmap`,
`mremap`, `brk`, `openat`, `close`, and `rt_sigaction`.

Input/output faults include reached EIO, EAGAIN, Interrupted, a zero write,
real closed-pipe stdout, a directory as stdin, and silent signal-setup failure
with an actual closed stderr pipe. Successful native writes are summed and
must equal the exact captured stdout prefix. No positive write result is
forged. Quiet invalid input also succeeds in reporting status 2 with closed
stderr because it issues no diagnostic.

Call-limit tests use a supported finite 16,384-read injection and continuous
`write:...:when=1+`/`2+` schedules. Installed strace rejects finite LAST values
above 65,534; the corpus never requests them. With a first stalled output,
one encoder read leaves 131,071 stdout attempts. After the first confirmed
1,024-byte write, two encoder reads leave 131,070 stdout attempts. Both exhaust
the same 131,072 total-provider-call budget and return quiet status 2; the
latter retains exactly the real first-write prefix. In-memory encoder reads
are inferred from the frozen copier scheduling contract and checked by direct
library tests, not represented as host read syscalls.

## Controls and accepted runtime receipts

```sh
timeout 90s python3 -B tests/fixtures/stdlib_execution/json_normalize/oracle.py controls
```

This passes host-only corpus construction/reference controls and deliberate
negative ownership-ledger controls. It reports `model=25 admission=15 limits=9
io=18+A`. These controls are not Lanius execution evidence.

The model selector passed one test / 25 native process cases in 7.16 seconds,
with a separate 1.67-second Rust build. Its log is
`target/stdlib-work/stream-encoding-normalize-model.log`, and retained process
evidence is `/tmp/json-normalize-model-t8awlx3c`. This gate ran oracle
`5f581237e91f8c1c39bccb3abc67d718d2a2921f77e940f2f06957e0dbe76c0e`.

Review strengthened the lifetime ledger to reject any document-owner release
after input retirement and before a later stdout write, including a release
before the first write. A host-only negative control leaves a second document
mapping live so the check cannot pass vacuously. All 25 saved native traces
passed host-only re-evaluation with the new ledger. This replay is not a new
native execution and adds no case count.

The admission selector passed one test / 15 native process cases in 7.72
seconds, with a 0.17-second build. Its log is
`target/stdlib-work/stream-encoding-normalize-admission.log`, with evidence at
`/tmp/json-normalize-admission-cdn5oinu`. It used the strengthened frozen
oracle below.

The limits selector passed one test / 9 native process cases in 9.30 seconds,
with a 0.20-second build. Its log is
`target/stdlib-work/stream-encoding-normalize-limits.log`, with evidence at
`/tmp/json-normalize-limits-yhnt65iq`.

The I/O selector passed one test / 51 native process cases in 23.15 seconds,
with a 0.17-second build. It reached all 33 baseline-derived allocation
failures. Its log is `target/stdlib-work/stream-encoding-normalize-io.log`, with
evidence at `/tmp/json-normalize-io-j3s7m3sr`.

All four selectors therefore passed 100 native process cases. Each actual
baseline is counted once; the host-only model replay adds zero. The admission,
limits and I/O selectors all used the strengthened oracle below.

Frozen source:
`45ae33e8f21f154d6513f14644257f6c05b5a97a5af8e2c8801f1975635d71c3`.
Frozen oracle:
`6870ca4ad237ec9c85499342f0f7f5f95b41d79bd15d5299a352f566321fcd69`.
Frozen driver:
`f3a3c2ca3b7fa830bda3b0eb66996aca0df2dca4468acdaad436030ee6e37207`.

Each native child has a 60-second timeout; each oracle has an 85-second timeout,
inside the root's separate outer command bound. Accepted execution is Linux
x86_64 CPU output from the GPU compiler; it does not establish device execution
or support for other targets.

The separate standalone compiler command in `docs/extended-json-normalize.md`
exited 0 with an empty build log at
`target/stdlib-work/stream-encoding-normalize-cli-build.log`. Both examples ran
from that artifact, returned 0, left stderr empty and produced exact 43-byte
and 12-byte outputs. Their receipt is
`target/stdlib-work/stream-encoding-normalize-cli-examples.log`. These two
standalone executions are not counted in the 100 focused test cases. Production
source hashes were unchanged throughout the accepted runs.

Existing `tests/extended_json_execution.rs` retains its grammar, 96 generated
trees, library API/ownership and malformed-cleanup scopes. It is not included
in this suite's case count. Argument-capture host failure is not injected;
empty argv admission has no allocation and therefore no argv OOM claim.
