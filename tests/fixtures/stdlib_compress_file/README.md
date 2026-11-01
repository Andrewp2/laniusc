# Atomic compressor application tests

The driver compiles `sample_programs/library/compress_file.lani` into a strict
ELF64 x86-64 executable and applies the shared native jump check. Every process
uses real input/output files in a separate directory. Python zlib independently
decodes the complete published raw DEFLATE, zlib or gzip stream and compares every
decoded byte with the input. The decoder requires actual stream EOF and rejects
trailing bytes. The deterministic zlib/gzip headers are checked separately.

## Corpus

| Oracle group | Native process cases | Main checks |
| --- | ---: | --- |
| `model` | 17 | All three formats; empty/binary input; 32,767/32,768/32,769 byte block edges; repeated identical gzip wire; complete 8 MiB output with unchanged allocation schedule and peak |
| `input_kinds` | 9 | Missing/directory/symlink/FIFO inputs; symlink parent; existing output, identical input/output path, hard-link alias and destination symlink remain unchanged |
| `cli` | 39 | Required, duplicate, unknown and bounded arguments; validated help before opens; aliases/intermixed options; raw path bytes and `--`; broken help pipe, failed diagnostic, failed signal setup |
| `input_limits` | 2 | Exactly 64 MiB accepted; one extra byte rejected; actual final one-byte EOF/excess probes |
| `faults` | 32 = 23 + 9 | One measured baseline; every reached allocation denied; open/metadata/duplicate/entropy/read/write/close/sync/rename failures; directory-sync retry; retained compressed prefix; real read/write attempt exhaustion |

The first four groups contain 67 processes. The fault group measures A from its
successful baseline, injects ENOMEM at each actual mmap ordinal, and reports A.
The accepted run measured **A = 9**, for **99 native process cases** overall.
No allocation ordinal is guessed. Its 23 ordinary processes include the baseline
and a separate failed-write control that identifies the cleanup-unlink site;
each is counted once. Host controls, compiler invocations and standalone examples
are not native case counts.

## Ownership and publication evidence

The trace filter contains 15 syscall names: `openat`, `close`, `fcntl`, `statx`,
`read`, `write`, `fsync`, `renameat2`, `unlinkat`, `getrandom`, `mmap`, `munmap`,
`mremap`, `brk` and `rt_sigaction`. Claims below are limited to those observations
and these finite workloads, not every possible host effect.

The ledger pairs full-width mapping addresses with exact extents and follows
input, caller-parent, duplicated-directory and temporary-file descriptors. It
rejects missing/double releases and descriptor reuse while live. The five fixed
workspace owners are identified by the allocations immediately before the first
file open: 4,096 input bytes, 4,096 output bytes, 32,768 block bytes, 32,773 pending
bytes and 131,072 bytes of packed i32 scratch. Their exact identities remain live
through input and temporary writes and until file cleanup completes. No mmap,
munmap, mremap or brk is permitted during the streaming interval. Successful
empty, block-edge, repeated and 8 MiB gzip cases must have the same allocation
extents and peak live bytes. All owners are retired before help or diagnostics.

All cases retain read/write tracing. Large and cap cases bound captured strings
to 64 bytes per syscall; their full request/result counts remain visible. The cap
cases require 65,536 confirmed 1,024-byte reads followed by exactly one request
of one byte returning zero or one. The application has 131,072 read attempts,
leaving room for that actual EOF probe. No summary-only transfer trace is used.

Publication requires observed input EOF, successful input close, successful
file sync and temporary close before at most one `renameat2(RENAME_NOREPLACE)`.
Directory sync follows confirmed publication. Complete output is independently
decoded even for failures reported after publication. Before publication,
existing destination inode, contents and symlink target must remain unchanged;
the original source bytes are also checked. There is no unlink after confirmed
publication.

Every injected syscall must be reached and marked. Each allocation denial must
match the baseline's complete allocation-argument prefix, end further
allocation, and release prior owners. Synthetic close-error injection skips the
kernel close; these cases establish attempted cleanup, logical retirement and
status/publication behavior, **not** release by the skipped kernel call. Normal
paths require successful descriptor release.

The recovery case confirms the first actual temporary-file write, injects EIO at
the next baseline-selected write and at cleanup unlink, and compares the kept
file with exactly that confirmed prefix of the baseline compressed wire. The
reported hexadecimal parent/name must identify the actual file; no backing owner
may remain retained. Initial directory-sync failure remains status 6 after a
successful retry; rename EIO is reported as unconfirmed. Diagnostic failure
preserves the primary status.

Continuous `read` EINTR must reach exactly 131,072 input attempts and report
status 2 at `input-read`. Continuous `write` EINTR must reach exactly 131,072
temporary-file attempts, followed by 64 failed diagnostic attempts. Those
requests must contain the complete `code=2 phase=write` diagnostic; final status
remains 2 despite diagnostic failure. This directly observes selection of the
write-limit branch, but does not test successful delivery of that particular
limit diagnostic. No unsupported finite strace range above 65,534 is used.

## Bounds that are not independent rejection cases

The 65 MiB output cap is defensive for admitted 64 MiB input: the encoder can
choose stored blocks, giving at most input bytes plus five bytes per 32 KiB
block, one final empty block when needed, and the small container wrapper. That
bound is below 65 MiB. These tests do not invent an output-cap rejection. The
262,144 encoder-step bound, help/diagnostic attempt limits in isolation, argument
capture host-read failure and same-process application retry are not separately
claimed as executed paths. Library fixtures cover the borrowed encoder's lower
limits and caller-controlled resumptions.

## Accepted execution

Host-only controls pass. They check independent decoder rejection of truncated
and trailing streams, diagnostic parsing, corpus counts, and rejection of
corrupted ownership/publication traces: missing/wrong-extent release, allocation
during streaming, workspace retirement before the first temporary write, missing
EOF, input close or file sync. These controls do not execute Lanius.

The root runner accepted all **5 tests and 99 native process cases** without
changing the frozen application, driver or oracle. The model group passed in
11.07 seconds (separate Rust build 1.14 seconds). CLI and input-kind groups passed
together in 8.58 seconds (build 0.21 seconds); no isolated timing is claimed for
either group. The exact input-cap group passed in 36.15 seconds (build 0.18
seconds), and the fault group in 17.27 seconds (build 0.19 seconds).

| Group | Log under `target/stdlib-work/` | Evidence directory |
| --- | --- | --- |
| `model` | `streaming-deflate-tool-model.log` | `/tmp/compress-file-model-xn30n772` |
| `cli` | `streaming-deflate-tool-admission.log` | `/tmp/compress-file-cli-cb0dr__n` |
| `input_kinds` | same admission log | `/tmp/compress-file-input_kinds-uu64hftq` |
| `input_limits` | `streaming-deflate-tool-limits.log` | `/tmp/compress-file-input_limits-k_sefuzj` |
| `faults` | `streaming-deflate-tool-faults.log` | `/tmp/compress-file-faults-n4ty7t_a` |

The standalone CLI build also succeeded with an empty
`streaming-deflate-cli-build.log`. Two documented examples passed separately:
three input bytes produced five raw-DEFLATE bytes, and five input bytes produced
25 gzip bytes; both returned zero with empty stdout/stderr. Their receipt is
`streaming-deflate-cli-examples.log`. These examples do not increase the 99-case
count.

Each of the five selectors in `tests/stdlib_compress_file_execution.rs` uses an
85-second oracle timeout and a 65-second native-process timeout. The root ran
bounded commands serially. Target scope is Linux x86-64 CPU execution of
GPU-compiler output; this host-file application is not a GPU-kernel program.

Frozen application source SHA-256:
`671688abd9e4d5dce68ca0f7500414f158ad9f23358f9d39ea382d0a35381c7d`.
Driver SHA-256:
`12d144c7151e7846f5494cb0f2a7396b5ddd27bee0dc758e454be8a2c1656c9f`.
Oracle SHA-256:
`5efc3969d8b6df60088c5386d22a8d66e38ac9b63329f2bebdb285093c9aaa24`.
The agreed help literal is exactly 1,188 bytes. Diagnostics are checked by status,
phase, visibility, sync/cleanup fields and recovery ownership.
