# hash-bytes

[`sample_programs/library/hash_bytes.lani`](../sample_programs/library/hash_bytes.lani)
hashes arbitrary binary stdin with a selected SHA-2 algorithm and writes one
lowercase hexadecimal digest followed by LF. It streams fixed-size chunks
through the real core hash state and uses no heap allocation or complete input
buffer. All application behavior is Lanius.

All nine groups were accepted on **2026-10-24** for x86_64 Linux native
execution of ELFs built through the GPU compiler: 136 native cases across
three driver invocations and three strict ELFs, with no allocation syscalls.
Each invocation shared its ELF across its selected groups. The program runs
on the CPU. No isolated hash-throughput result or support beyond the tested
target and fault model is claimed.

## Invocation and output

The command accepts zero or one algorithm argument. The default is `sha256`.
Accepted spellings are exact, case sensitive ASCII:

| Argument | Digest bytes | Output bytes including LF |
| --- | ---: | ---: |
| `sha224` | 28 | 57 |
| `sha256` | 32 | 65 |
| `sha384` | 48 | 97 |
| `sha512` | 64 | 129 |
| `sha512-224` | 28 | 57 |
| `sha512-256` | 32 | 65 |

The SHA-512 variants use their dedicated constructors. The program does not
implement them by truncating an ordinary SHA-512 result.

With the compiler binary built, from the repository root:

```sh
mkdir -p target/stdlib-work/hash-bytes
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/hash_bytes.lani \
  -o target/stdlib-work/hash-bytes/hash-bytes
printf 'abc' | target/stdlib-work/hash-bytes/hash-bytes
printf 'abc' | target/stdlib-work/hash-bytes/hash-bytes sha512-256
```

Every input byte participates in the digest, including NUL, invalid UTF-8,
and trailing newlines. Output contains only `0`–`9`, `a`–`f`, and the final LF;
there is no algorithm label or filename. Empty stdin produces that algorithm's
empty-message digest. Stderr is unused.

Arguments are read directly into a ten-byte packed stack buffer using
`std::process::arg_len` and `arg_read`. No argument snapshot or UTF-8 conversion
is allocated. Empty, unknown, differently cased, whitespace-padded, or extra
arguments return status 2 before stdin reads or signal setup. Host argument
service failure returns 3. An arbitrary non-UTF-8 argument is simply unknown.

## Input and call bounds

The total input limit is **16,777,216 bytes (16 MiB)**. The application reads
through `std::stream::Descriptor` and the real `core::io::Read` contract into
1,024 packed stack bytes. Requests never exceed the remaining byte budget.
Each successful chunk is passed as a `View<u8>` to the selected state, and the
application checks that `update` accepted its complete length.

Success requires an actual zero-byte read. At the exact byte limit, the next
request is an actual **one-byte EOF probe**. A zero-byte result permits final
hashing and output. A one-byte result consumes that single excess byte, hashes
none of it, and returns status 7 with empty stdout.

A shared **131,072-call budget** covers every direct stdin read and stdout
write attempt, including Interrupted errors, short transfers, and the EOF
probe. Signal setup and the fixed number of argument-service calls are outside
that budget. The counter is checked before every data I/O call. Interrupted
errors retry while budget remains; other host errors return 3. Read counts
outside the requested range, zero-progress writes, and invalid write counts
also return 3.

The call budget can reject input below the byte cap when a stream supplies
many very short reads or repeated interrupts. Exhaustion returns 7. Ordinary
full-chunk input at the byte cap needs 16,385 reads, leaving ample calls for
the digest line. A blocked host operation still has no elapsed-time bound;
the counter bounds attempted operations and retry loops.

## Hash state, publication, and failure

The program uses [`core::sha256`](../stdlib/core/sha256.lani) for SHA-224/256
and [`core::sha512`](../stdlib/core/sha512.lani) for the other four algorithms.
Only the selected state receives input. It finishes after actual EOF, and
the returned digest is consumed immediately. No later state update or finish
depends on a retained independent digest snapshot.

Digest encoding uses at most 129 packed stack bytes. Input scratch, state,
and output storage are fixed size; this does not claim a particular total
stack frame or process-memory size. The program imports no allocating owner,
performs no mmap/brk allocation, and needs no owner cleanup on any branch.

All input, hashing, and EOF validation finish before the first stdout attempt.
Thus usage, read, byte-limit, and prepublication call-limit failures publish
nothing. Output uses the `core::io::Write` contract directly: a short write
advances to the remaining suffix and Interrupted retries consume the shared
budget. An output error or budget exhaustion can leave a confirmed prefix,
including a line without LF. The program does not restart or repeat a digest.

After valid argument dispatch, main installs process-wide SIGPIPE Ignore.
This lets an actual closed stdout pipe return EPIPE as status 3. Stdin and
stdout remain borrowed descriptors; there is no flush, close, or durability
promise.

| Status | Meaning |
| --- | --- |
| 0 | Complete hexadecimal digest and LF written |
| 2 | Unknown, empty, or extra algorithm argument |
| 3 | Argument host service, signal setup, or input/output failure |
| 7 | Input byte limit, shared I/O-call budget, or hash update boundary failure |

## Focused driver and accepted evidence

[`tests/stdlib_hash_bytes_execution.rs`](../tests/stdlib_hash_bytes_execution.rs)
uses Python's independent `hashlib` implementation only to compute expected
digest bytes. Oracle input is a binary file, algorithm selection is an
ordinary argument, and output is the expected hexadecimal line. There is no
JSON transport or Python implementation behind the application.

The driver compiles the real production application through the stdlib root,
passes the unchanged shared strict ELF/jump checker, and stores the emitted
executable in a `OnceLock`. All selected groups in one driver process reuse
that one ELF. Separate exact-test invocations can each compile once, allowing
the root to keep individual serialized gates bounded.

| Exact test | Accepted native cases |
| --- | ---: |
| `hash_bytes_algorithms_vectors_and_io_failures` | 126 |
| `hash_bytes_global_call_budget_bounds_interrupted_io` | 2 |
| `hash_bytes_exact_input_limit_and_one_byte_excess` | 2 |
| `hash_bytes_one_mebibyte_sha224` | 1 |
| `hash_bytes_one_mebibyte_sha256` | 1 |
| `hash_bytes_one_mebibyte_sha384` | 1 |
| `hash_bytes_one_mebibyte_sha512` | 1 |
| `hash_bytes_one_mebibyte_sha512_224` | 1 |
| `hash_bytes_one_mebibyte_sha512_256` | 1 |
| Total across nine groups | 136 |

The ordinary group compares every algorithm with hashlib for 17 inputs: empty,
`abc`, all byte values, and deterministic binary lengths 55, 56, 63, 64, 65,
111, 112, 127, 128, 129, 1,023, 1,024, 1,025, and 4,097. These cross both SHA
padding boundaries and application chunk boundaries. The remaining cases
check default dispatch, raw invalid arguments, host errors, invalid returned
counts, Interrupted retry, zero progress, a synthetic short write, real EPIPE,
and signal setup failure.

The budget group repeatedly injects Interrupted until exactly 131,072 reads,
or two successful reads plus 131,070 interrupted writes, exhaust the shared
counter. The boundary group compares the complete 16 MiB digest against
hashlib, then checks one-byte excess rejection, final request length one, and
the actual EOF/non-EOF result. Six separate scale groups each compare a 1 MiB
binary message for their algorithm.

Every native case is traced and must contain no `mmap`, `mremap`, `munmap`, or
`brk` calls. Traces also require actual EOF before publication, stdin/stdout
descriptor use, bounded requested counts, the shared call cap, and reached
fault injections. The synthetic one-byte short write suppresses the first
host write while reporting one byte; the test expects the actual remaining
suffix once. The closed-pipe case uses real EPIPE under Ignore.

Ordinary native cases have a five-second timeout plus one-second forced-exit
grace. Budget, 1 MiB scale, and 16 MiB boundary cases use 20 seconds plus the
same grace. Hashlib oracle processes have a separate five-second bound. These
are test harness guards, not program elapsed-time guarantees. Root gates
should select exact groups to avoid combining all large cases in one short
outer timeout.

Build target: `cargo test --test stdlib_hash_bytes_execution --no-run`. After a
fresh build, select a named test from the emitted driver with its positional
name followed by `--exact --nocapture --test-threads=1`, under the root's
serialized timeout and GPU lock. The accepted groups and their local evidence
are recorded below. No isolated throughput acceptance is claimed.

### Accepted groups

| Group | Evidence |
| --- | --- |
| Ordinary vectors and I/O failures | Accepted: one strict ELF, 126 native cases, no allocation syscalls, one Rust test passed in 7.57 s |
| Six 1 MiB algorithm cases | Accepted: one shared strict ELF, six native cases, six Rust tests passed together in 6.82 s |
| 16 MiB exact input bound and one-byte excess | Accepted: two native cases, including actual one-byte EOF/non-EOF probe |
| Shared call-budget exhaustion | Accepted: two native cases reaching 131,072 read/write attempts under persistent Interrupted |

The fresh joint Rust build with `stdlib_sha256_execution` took 1.26 s; this is
not an isolated application-driver build. The accepted application driver was
`target/stdlib-build/debug/deps/stdlib_hash_bytes_execution-2312e16d3a773f5f`,
selecting `hash_bytes_algorithms_vectors_and_io_failures`. Its runtime log is
`target/stdlib-work/sha2-admission/hash-bytes-ordinary.log`, an ignored local
artifact. That result covers the ordinary group only.

The six scale groups passed after a timer-only driver update and a fresh joint
application-driver build in 1.26 s, recorded in
`target/stdlib-work/sha2-admission/build-apps-final.log`. Their runtime log is
`target/stdlib-work/sha2-admission/hash-bytes-scale.log`. All expected 1 MiB
digests matched hashlib and the no-allocation checks passed.

| Algorithm | Observed case wall (ms) |
| --- | ---: |
| `sha224` | 201.502 |
| `sha256` | 189.622 |
| `sha384` | 89.378 |
| `sha512` | 98.241 |
| `sha512-224` | 121.628 |
| `sha512-256` | 104.298 |

Each timer surrounds `run()` and includes input-file setup, strace, process
startup, and trace parsing. It excludes compilation and the hashlib oracle.
These are individual observed case wall times, not isolated hash-throughput
measurements or repeated benchmark statistics. The application stayed frozen;
the driver changed only to add this timer.

The final two groups passed together in **20.25 s**, with one shared strict
ELF and four native cases. Their log is
`target/stdlib-work/sha2-admission/hash-bytes-limits.log`. Both the exact 16 MiB
digest and one-byte excess rejection passed, as did persistent Interrupted
read/write failures exhausting the shared call budget. A bounded replay using
the same fresh driver and exact accepted final test filters is:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/stdlib_hash_bytes_execution-2312e16d3a773f5f \
  hash_bytes_ \
  --skip hash_bytes_algorithms_vectors_and_io_failures \
  --skip hash_bytes_one_mebibyte \
  --nocapture --test-threads=1
```

Across the ordinary, scale, and final-limit invocations, all nine Rust test
groups and all 136 native cases passed. Each of the three driver processes
compiled one strict ELF; `OnceLock` shared it across selected groups within
that process. The application body stayed frozen, and the driver assertions
were unchanged after ordinary acceptance. Final evidence edits affect this
guide and the application header comment only; no reruns were needed.
