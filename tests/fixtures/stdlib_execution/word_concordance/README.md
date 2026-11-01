# Word concordance application evidence

Real program: `sample_programs/library/word_concordance.lani`.
Driver: `tests/stdlib_word_concordance_execution.rs`.
The driver admits only actual ELF64/little-endian/x86-64 output and uses the
shared jump-displacement check when writing the executable. One test process
compiles the app once.

## Corpus and independent model

Python validates UTF-8, finds byte runs outside the six ASCII whitespace bytes,
groups their `match.start()` offsets and sorts complete keys as bytes. It does
not use Unicode whitespace splitting or decode byte offsets into scalar
positions. Full output bytes are compared, including controls/NUL, combining
sequences, case, punctuation and Unicode whitespace retained inside words.

| Group | Accepted native cases | Scope |
| --- | ---: | --- |
| model | 28 | Literal and six seeded mixtures, Unicode byte positions, sorted/repeated/prefix keys, all separators, and exact output lengths around 1,024/4,096 bytes |
| admission | 12 | Eight no-argument rejections before allocation/input and four invalid UTF-8 inputs rejected after complete collection |
| limits | 6 | True 1 MiB EOF/excess probes, empty output at the cap, a position list larger than 3 MiB, and 65,536/65,537 distinct words |
| io | 57 | One real allocation baseline, 38 individually reached allocation failures, and 18 I/O/signal/attempt cases |

`A = 38` is the actual successful baseline's mmap count: 11 input growth
allocations and 27 indexing allocations for map/node storage and repeated
position-vector growth. Every ordinal is derived from that baseline, must be reached, and must
match the full mmap argument prefix before its injected ENOMEM. The baseline
is counted once. No allocation is permitted after the reached failure.

The 8 MiB output cap is defensive and unreachable under the CLI's 1 MiB input
cap: a loose bound is 6 MiB. There is no invented rejection case for that cap;
the guide documents the derivation. The distinct-word tests allocate genuine
position vectors for all actual entries.

## Resource and fault evidence

The ledger uses complete mapping addresses and extents, detects leaks/double
releases, and identifies the input owner during actual reads. At observed EOF
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

Host-only controls pass: `model=28 admission=12 limits=6 io=19+A`. They check
literal byte-offset outputs, corpus construction and deliberately invalid
ownership traces. They are not Lanius execution evidence.

All four selectors passed, totaling 103 native process cases. Each row is
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
