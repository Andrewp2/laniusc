# Word concordance application evidence

Real program: `sample_programs/library/word_concordance.lani`.
Driver: `tests/stdlib_word_concordance_execution.rs`.
The driver admits only actual ELF64/little-endian/x86-64 output and uses the
shared jump-displacement check when writing the executable. It now links the
system CRT to retain sized source symbols for the current runtime authority
verifier; no additional native library is requested. One test process compiles
the app once.

The current program uses `TreeMap.try_update_or_insert`. A lazy producer checks
its previously captured distinct-word allowance and constructs one positions
vector only for a missing key. Existing words still append at the distinct-word
limit. A returned candidate is explicitly released on map-storage or key-match
failure. All four current selectors pass with the current verifier adaptation;
the earlier accepted receipts below retain their historical source scope.

## Corpus and independent model

Python validates UTF-8, finds byte runs outside the six ASCII whitespace bytes,
groups their `match.start()` offsets and sorts complete keys as bytes. It does
not use Unicode whitespace splitting or decode byte offsets into scalar
positions. Full output bytes are compared, including controls/NUL, combining
sequences, case, punctuation and Unicode whitespace retained inside words.

| Group | Current case structure | Scope |
| --- | ---: | --- |
| model | 28 | Literal and six seeded mixtures, Unicode byte positions, sorted/repeated/prefix keys, all separators, and exact output lengths around 1,024/4,096 bytes |
| admission | 12 | Eight no-argument rejections before allocation/input and four invalid UTF-8 inputs rejected after complete collection |
| limits | 7 | True 1 MiB EOF/excess probes, empty output at the cap, a position list larger than 3 MiB, 65,536/65,537 distinct words, and existing-word updates at the distinct-word cap |
| io | 19 + A | One real allocation baseline, A individually reached source allocation failures, and 18 I/O/signal/attempt cases |

Both the historical receipt and the current run reach `A = 38`: 11 input growth
allocations and 27 indexing allocations for map/node storage and repeated
position-vector growth. The current run derives A independently. Every global syscall
ordinal is derived from that run's baseline, must be reached, and must
match the full mmap argument prefix before its injected ENOMEM. The baseline
is counted once. No allocation is permitted after the reached failure.

The 8 MiB output cap is defensive and unreachable under the CLI's 1 MiB input
cap: a loose bound is 6 MiB. There is no invented rejection case for that cap;
the guide documents the derivation. The distinct-word tests allocate genuine
position vectors for all actual entries.

## Resource and fault evidence

The ledger first classifies every observed syscall post-IP with the exact
current source/runtime verifier in `native_c/source_allocations.py`. It rejects
unknown executable-image sites and excludes only classified native and CRT
activity from the application claims. The unchanged shared source-mapping
ledger additionally checks exact allocation/release sites, flags, full-width
addresses and byte extents. `LANIUS_ALLOC=mmap` selects explicit allocation
events. Global syscall ordinals include loader activity, so fault injections
still target the observed source call rather than assuming a startup offset.

The application ledger detects leaks/double releases and identifies the input
owner during actual source reads. At observed EOF
that owner must remain live; it must be the final mapping released. Output
requires completed input, that original live input mapping, at least two other
live mappings and no prior publication-phase release. New allocations after
the first write are rejected. Before the first write, indexing legitimately
allocates/releases storage; the ledger cannot independently identify each
nested owner in that phase. The scope is nine filtered syscalls: `read`, `write`, `mmap`,
`munmap`, `mremap`, `brk`, `openat`, `close`, and `rt_sigaction`.

The I/O group reaches EIO/EAGAIN/Interrupted, a zero write, true closed stdout,
directory stdin, invalid input with closed stderr, and failed SIGPIPE setup
with a real closed stderr pipe. Empty successful output with closed stdout is
separate. Confirmed successful write lengths must equal the actual captured
stdout; error-prefix cases compare those bytes against the full independent
model. No positive successful transfer is faked.

The finite read fault reaches 16,384 attempts. Persistent write faults use
supported strace schedules `when=1+` and `when=2+`; both reach exactly 131,072
direct stdout attempts and quiet status 2. The latter leaves the actual first
1,024-byte prefix. No unsupported finite range above strace's 65,534 LAST
bound is requested. This app budgets writes only; the JSON copier's combined
read/write budget is a separate contract.

## Controls and accepted native receipts

```sh
timeout 90s python3 -B tests/fixtures/stdlib_execution/word_concordance/oracle.py controls
```

Host-only controls pass: `model=28 admission=12 limits=7 io=19+A`. They check
literal byte-offset outputs, corpus construction and deliberately invalid
ownership traces. Native/CRT prefixes preserve the global fault ordinals;
unknown image sites, wrong release authority, wrong allocation flags and
injected native activity are rejected. These are not Lanius execution evidence.

## Current native receipts

All four selectors pass: 104 native process cases, including 38 individually
reached source allocation failures. The application Rust build took 9.82 s in
`target/stdlib-work/lazy-map-concordance-build.log`. Current execution logs share
the directory and prefix `lazy-map-concordance-`:

| Receipt suffix | Rust tests | Native cases | Test time | Evidence directories |
| --- | ---: | ---: | ---: | --- |
| `model.log` | 1 | 28 | 9.00 s | `/tmp/word-concordance-model-50frlucq` |
| `limits.log` | 2 | 7 limit + 12 admission | 47.68 s combined | `/tmp/word-concordance-limits-kb327ibq`, `/tmp/word-concordance-admission-iyht9wac` |
| `failures.log` | 1 | 57 | 22.05 s | `/tmp/word-concordance-io-sacvb2w2` |

The current limit corpus adds an update at the full distinct-word limit. The
I/O baseline is counted once; its 38 ENOMEM cases are separately reached and
preserve cleanup/no-output contracts. Host controls add no native cases.

Current source SHA256:
`ce47c35c5dbce4f5f5ea2826b4852e251d88cb1fe5ff8cc838d2116b9df7f28e`.
Current oracle SHA256:
`0dbd95c24c9892205fc632705b51c6ef1bf1fe2256461b5225e82695a349bb2f`.
Current driver SHA256:
`c8b6251721ec9c34f26ff975db814e416c84348b8eb48a57fdb3675ebc87d305`.

## Historical native receipts

Before the lazy insertion and current-runtime verifier migration, all four
selectors passed, totaling 103 native process cases. Each row is
one Rust test, with build time separate:

| Group | Native cases | Test time | Build time | Evidence directory |
| --- | ---: | ---: | ---: | --- |
| model | 28 | 7.12 s | 1.68 s | `/tmp/word-concordance-model-un3zqspt` |
| admission | 12 | 7.50 s | 0.19 s | `/tmp/word-concordance-admission-dg30f85k` |
| limits | 6 | 42.56 s | 0.19 s | `/tmp/word-concordance-limits-3jehx7__` |
| io | 57 | 23.11 s | 0.19 s | `/tmp/word-concordance-io-suq3xxxl` |

Logs are `target/stdlib-work/map-update-concordance-{model,admission,limits,io}.log`.
All 38 baseline-derived ENOMEM cases were reached. The baseline is counted
once; host-only controls add no native cases. Source, oracle and driver stayed
unchanged across these accepted runs.

Source SHA256:
`5013630d9b55455cb75bb24e20934f41e2f66d9a2fac9ca0299d5a86676ad2d2`.
Oracle SHA256:
`55419dc1866f07aec8cc16fb5d7c74d80e453bb753b464032b04c9110013f102`.
Driver SHA256:
`5f5fe3e47589fc2af86e07a5fec462bbbfb5a5c8c928d5457d51dc8175006f65`.

The standalone CLI compile already exited 0 with an empty
`target/stdlib-work/map-update-concordance-cli-build.log`. Both examples in
`docs/stdlib-word-concordance.md` then returned 0 with empty stderr and exact
18-byte/21-byte outputs; receipt:
`target/stdlib-work/map-update-concordance-cli-examples.log`. These two native
example processes are separate from the focused test counts.

Each native child has a 60-second bound and each oracle an 85-second bound,
inside the root's outer command limit. Initial acceptance is Linux x86_64 CPU
execution of GPU-compiled output, not device execution or other hosts. The
allocation-free argument path has no argv OOM claim; argument-capture host
failure is not injected. Direct map contracts/models/resources retain their
separate scopes and counts.
