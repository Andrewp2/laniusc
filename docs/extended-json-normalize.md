# Bounded JSON normalization

`sample_programs/json_normalize.lani` reads one UTF-8 JSON document from stdin
and writes its compact representation to stdout. It takes no arguments and
adds no newline. Every failure is quiet; inspect the exit status.

## Build and examples

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/json_normalize.lani \
  -o target/stdlib-work/json_normalize
```

These flags are supported by the current compiler argument parser. The explicit
source roots discover `core`/`alloc`/`std` and `ext` modules; `--emit x86_64`
selects a Linux x86_64 executable. The CLI makes the output executable. No
native-link or external-library flags are needed.

```sh
printf '%s' ' {"count":1.2300e+05,"label":"\u0061","count":-0} ' | \
  timeout --kill-after=2s 10s target/stdlib-work/json_normalize
```

The exact output is 43 bytes, without a final newline:

```json
{"count":1.2300e+05,"label":"a","count":-0}
```

An escaped surrogate pair becomes UTF-8 while a newline becomes its compact
control escape:

```sh
printf '%s' '"\uD83D\uDE42\n"' | \
  timeout --kill-after=2s 10s target/stdlib-work/json_normalize
```

The exact output is 12 bytes, without a final newline: `"🙂\u000a"`.
The standalone compiler command succeeded. Both examples returned 0, left
stderr empty and produced those exact bytes. Their separate receipts are
recorded below.

Number tokens retain their spelling; object members retain their order and
duplicate keys. Quotes and backslashes are escaped, control characters use
lowercase `\u00xx`, and other Unicode scalars remain UTF-8. Scalar roots and
empty arrays/objects are supported. This follows the existing
[JSON format policy](extended-json.md); it does not canonicalize JSON for
cryptographic use.

## Limits and status

| Bound | Value |
| --- | ---: |
| Input bytes | 1,048,576 |
| Direct stdin read attempts | 16,384 |
| Container depth | 128 |
| Nodes, including the root | 65,536 |
| Decoded UTF-8 bytes per key/string | 1,048,576 |
| Source bytes per number | 1,048,576 |
| Encoded output bytes | 1,048,576 |
| Total transfer-provider attempts | 131,072 |
| Transfer scratch | 1,024 bytes |
| New bytes per copy step | 4,096 |

These are application limits; `ext::json::default_options()` is unchanged.
Input at the byte cap receives a real one-byte EOF/excess probe. Stdin attempts
include that probe, EOF and Interrupted. Complete text validation, JSON parsing
and exact output-length admission all finish before the first stdout write.
Escaped control characters can expand the output beyond the input size and
therefore fail output admission independently.

The transfer budget counts both direct calls to the in-memory JSON reader and
calls to the stdout writer, including Interrupted and EOF. It persists across
copy steps. A step's new-read quota only pauses the transfer; the application
continues with a fresh quota and succeeds only after the copier observes EOF.
Provider-internal work and blocking duration are not bounded by call quotas.

| Status | Meaning |
| --- | --- |
| 0 | Complete admitted compact output |
| 2 | Arguments, invalid UTF-8/JSON, document/output limits, or an exhausted input/transfer call budget |
| 3 | I/O failure, WouldBlock, invalid provider progress, or failed SIGPIPE setup |
| 4 | Allocation failure |

Every supplied argument is rejected before input collection, including `--`,
`-h` and `--help`. The empty argument snapshot needs no heap allocation.
SIGPIPE is ignored before argument processing so a closed stdout pipe returns
status 3. Failed signal setup also returns silent status 3.

Errors found before publication leave stdout empty. A later write failure or
transfer-budget exhaustion can leave a confirmed output prefix; stdout is not
transactional. There are no stderr diagnostics, even if stderr is a closed
pipe. The program borrows standard descriptors and does not close them.

## Storage and ownership

The bounded `alloc::io::read_to_string` collector grows one byte owner, validates
UTF-8 after EOF, and adopts the same allocation as a String. Parsing copies the
document's retained token text. The program then destroys the input String
before calling `Document.encoding()` for complete length preflight.

The borrowed `Encoding` implements the usual `core::io::Read` protocol.
`core::io::Copier` connects it to stdout using fixed scratch and retains pending
bytes across quota pauses. No whole-output String or per-chunk heap owner is
created. The document remains unchanged and live throughout preflight and
transfer. All encoder/copier use ends before document destruction, on success
and ordinary failure paths.

## Verification

The focused driver is `tests/stdlib_json_normalize_execution.rs`, with an
independent ordered JSON model and syscall ledger under
`tests/fixtures/stdlib_execution/json_normalize/`. It checks full output bytes,
real byte-cap probes, document/output admission, reached allocation failures,
I/O failures, confirmed output prefixes, and the global transfer budget.

The ledger identifies the final input mapping at the observed stdin EOF,
requires its retirement before stdout, rejects new allocations after that
retirement, and accounts for every observed mapping address and full extent.
It observes `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`, `openat`, `close`
and `rt_sigaction`; it does not claim visibility into every host effect.
Direct library resource tests separately check borrowed encoding/copy scopes.

All four focused gates passed: 100 native process cases, including 33 reached
allocation failures. Each row is one Rust test; build time is separate.

| Gate | Native cases | Test time | Build time |
| --- | ---: | ---: | ---: |
| Exact compact output | 25 | 7.16 s | 1.67 s |
| Argument/document admission | 15 | 7.72 s | 0.17 s |
| Byte/document/output limits | 9 | 9.30 s | 0.20 s |
| Allocation/I/O/attempt failures | 51 | 23.15 s | 0.17 s |

Logs are `target/stdlib-work/stream-encoding-normalize-{model,admission,limits,io}.log`.
The model gate ran before the lifetime-ledger strengthening. The stricter
ledger subsequently accepted all 25 saved syscall traces through host-only
re-evaluation; that replay adds no native executions. The other three gates
used the strengthened ledger. Host-only corpus controls also pass.

Exact source/oracle hashes, retained evidence directories and receipt scopes
are tracked in the fixture README. Existing JSON grammar and generated-tree
regressions remain in `tests/extended_json_execution.rs`; this suite does not
repeat that campaign or include its counts.

Accepted application execution is Linux x86_64 CPU output from the GPU
compiler. GPU compilation does not establish user-program GPU execution.
Other execution targets have no acceptance claim here. The separate standalone
CLI build above exited 0 with an empty
`target/stdlib-work/stream-encoding-normalize-cli-build.log`. Both examples ran
from that artifact and matched their exact 43-byte and 12-byte outputs, with
status 0 and empty stderr; the receipt is
`target/stdlib-work/stream-encoding-normalize-cli-examples.log`. These two
standalone executions are separate from the 100 focused test cases.
