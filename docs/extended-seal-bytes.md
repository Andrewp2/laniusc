# seal-bytes

[`sample_programs/library/seal_bytes.lani`](../sample_programs/library/seal_bytes.lani)
seals and opens bounded binary messages with the real
[`ext::chacha20_poly1305`](../extended/ext/chacha20_poly1305.lani) primitive.
It reads a complete owned message before performing one AEAD operation. This
is a whole-message codec, with bounded chunked input and output; it is not a
resumable encryption stream. All application behavior is Lanius.

Runtime admission is **pending**. The intended gate compiles an x86_64 Linux
ELF through the GPU compiler and executes it natively. Source and focused
drivers are prepared; no runtime, target-support, or throughput acceptance is
claimed yet.

## CLI and key policy

```text
seal-bytes seal KEY_FILE NONCE_HEX AAD_HEX
seal-bytes open KEY_FILE AAD_HEX
```

`KEY_FILE` contains exactly **32 raw bytes**, without a newline or hex encoding.
The path accepts 1–4,095 raw bytes and need not be UTF-8. Nonce hex must contain
exactly 24 ASCII hex characters, decoding to 12 bytes. Caller AAD accepts
0–512 hex characters, decoding to at most 256 bytes; pass `''` for empty AAD.
Hex is case insensitive, must have even length, and permits no whitespace or
prefix. Unknown commands and missing/extra arguments return status 2.

Every seal under a key must use a **unique key/nonce pair**. The caller chooses
and tracks the nonce; the application does not generate randomness or track
prior uses. Open takes its nonce from the envelope and requires the same
decoded caller AAD used for sealing.

Arguments are snapshotted with `snapshot(1,4,4635)`, excluding argv[0]. The
4,635-byte budget is the sum of the largest seal command, path, nonce, and AAD
spellings, without terminating NULs. It imposes no executable-name limit.
Arity, path, and all hex validation finish before opening the key or reading
stdin. Allocation failure while snapshotting returns 4.

The key is opened read-only with no-follow, nonblocking, and close-on-exec
flags. Final-component symlinks are rejected; earlier path components follow
the OS path rules. Nonblocking open avoids waiting for a FIFO peer. There is
no separate regular-file restriction: the opened descriptor must supply
exactly the required bytes and EOF under the same bounded read contract.

The application reads exactly 32 bytes, then makes an actual one-byte EOF
probe. Short or excess keys return 2. Every successful key open gets exactly
one close attempt, before any stdin read, including after a key-read failure.
Close invalidates the owner before its host attempt and is never retried. A
close error returns 3 and overrides a prior key-format or call-budget error.
The key file is never modified.

With the compiler built, from the repository root:

```sh
mkdir -p target/stdlib-work/seal-bytes
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/seal_bytes.lani \
  -o target/stdlib-work/seal-bytes/seal-bytes
# Set NONCE_HEX to a fresh 24-character nonce for this key before sealing.
AAD_HEX=''
target/stdlib-work/seal-bytes/seal-bytes seal key.bin "$NONCE_HEX" "$AAD_HEX" \
  < plaintext.bin > message.lnc
target/stdlib-work/seal-bytes/seal-bytes open key.bin "$AAD_HEX" \
  < message.lnc > recovered.bin
```

## Envelope and authentication

The binary envelope is exactly:

| Offset | Bytes | Meaning |
| ---: | ---: | --- |
| 0 | 4 | ASCII magic `LNC1` |
| 4 | 12 | Nonce |
| 16 | Payload length | Ciphertext |
| Last 16 | 16 | Full authentication tag |

There is no length field, text encoding, or newline. The envelope's complete
byte length determines ciphertext length. Empty plaintext produces a 32-byte
envelope; opening that valid envelope produces empty stdout.

The primitive's associated data is **the complete 16-byte header followed by
the decoded caller AAD**. Its fixed header prefix makes this concatenation
unambiguous. A packed 272-byte stack region stages the combined AAD; nonce and
caller AAD are copied there before the AEAD operation. Seal writes exactly
that header into its output envelope. Open checks minimum length and magic,
then copies the received header into the authenticated AAD region.

Malformed length or magic returns 2 with no output. A modified valid-form
nonce, ciphertext, tag, caller AAD, or key fails authentication with status 5.
Open publishes no plaintext before the entire message authenticates. The
primitive authenticates before writing its private plaintext destination;
the application also publishes nothing on any primitive error.

## Input, work, and ownership bounds

Seal accepts at most **1,048,576 plaintext bytes**. Open accepts at most
**1,048,608 envelope bytes**, accommodating the same maximum payload and
32-byte framing. Each mode reserves its complete input cap in an owned
`alloc::io::Buffer` before reading stdin. Reads use packed 1,024-byte stack
scratch and request no more than the remaining budget. Success requires
actual EOF. At the cap, an actual one-byte probe distinguishes exact EOF from
excess input; a positive result consumes that one extra byte, stores none of
it, and returns 7 with empty stdout.

The application then allocates and initializes a separate checked output Vec:
payload plus framing for seal, or plaintext length for open. All AEAD input,
output, tag, key, and AAD views have the required backing and disjoint output
ranges. No allocation is performed by the primitive. No allocation occurs
after publication starts. Logical caps do not describe exact RSS or stack
usage; input and output owners coexist during the whole-message operation.

A shared **131,072-call budget** counts every key read, key EOF probe, stdin
read, stdin EOF probe, and stdout write attempt, including Interrupted retries.
Open, close, signal setup, and fixed argument-service calls are outside that
counter. It is checked before each data I/O attempt. Other host errors,
invalid returned counts, and zero-progress writes return 3. The cap can reject
a stream below its byte limit if it supplies many tiny reads or interrupts.
It bounds attempted calls, not the duration of an individual blocked host
operation.

Each owned argument snapshot, input buffer, output buffer, and key descriptor
has explicit cleanup on every outcome. Authentication or allocation failure
discards the private output and releases all owners. Main installs SIGPIPE
Ignore before allocation, allowing a closed stdout pipe to report EPIPE and
reach cleanup. Stdin and stdout stay borrowed and are never closed.

After a successful seal/open, checked output handles short writes and bounded
Interrupted retries. A later write failure or call-budget exhaustion can leave
a confirmed ciphertext or authenticated-plaintext prefix. The application
does not resume, reseal, or replay an accepted prefix. It promises no temporary
file transaction, rename, durable flush, or explicit secret erasure. Stderr is
unused.

| Status | Meaning |
| --- | --- |
| 0 | Complete envelope or authenticated plaintext published |
| 2 | CLI/hex/path, key length, or envelope framing invalid |
| 3 | Signal, key open/read/close, or stdin/stdout failure |
| 4 | Argument, input, or output allocation failure |
| 5 | Authentication failed |
| 7 | Input/call limit or defensive primitive boundary failure |

Input-limit checks precede envelope interpretation. For example, an oversized
open input returns 7 even if its final bytes would also make authentication
fail. Allocation can fail before authentication and return 4. All failures
before publication leave stdout empty; later statuses 3 or 7 can leave a
prefix.

## Focused driver and pending evidence

[`tests/extended_seal_bytes_execution.rs`](../tests/extended_seal_bytes_execution.rs)
compiles the real application with the stdlib and extended roots, applies the
unchanged shared strict ELF/jump checker, and shares the resulting executable
through `OnceLock` within a driver process. Four exact test groups are prepared:

| Test | Prepared native cases |
| --- | ---: |
| `seal_bytes_envelopes_oracle_tamper_and_argument_policy` | 92 |
| `seal_bytes_owned_cleanup_and_io_faults` | 31 plus observed seal/open allocation positions |
| `seal_bytes_payload_boundaries_and_scale` | 4 |
| `seal_bytes_shared_call_budget_bounds_retries` | 2 |

The total is **129 plus both observed representative allocation counts**. No
physical View/Vec width or allocation count is hardcoded. Larger and budget
groups are separately selectable to keep root gates bounded. Ordinary cases
use five-second native timeouts and one-second termination grace; scale and
budget cases use 20 seconds plus the same grace.

The independent oracle loads libsodium through Python ctypes and calls its
IETF ChaCha20-Poly1305 implementation. It receives binary files and ordinary
arguments and returns binary envelopes/plaintext; there is no JSON transport
or Python implementation behind the application. It computes the complete
header-plus-caller-AAD framing independently. Oracle processes have a separate
five-second timeout.

Normal cases seal and open empty, binary, Poly1305 block-boundary, ChaCha20
block-boundary, and application chunk-boundary messages, including empty and
maximum caller AAD and both hex cases. A test uses the key, nonce, plaintext,
and known ciphertext from [RFC 8439 section 2.8.2](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.8.2).
The ciphertext remains that vector; authenticating the envelope header changes
the tag, which is checked against libsodium.

Tamper cases flip each of the 16 header bytes and each of the 16 tag bytes,
change ciphertext at its beginning/middle/end, change caller AAD, use the wrong
key, and truncate or extend framing. Every case must reject without any
stdout attempt. CLI/key cases check malformed hex/arity, raw non-UTF-8 paths,
short/long keys, a missing key, final symlink rejection, and a no-peer FIFO.
Invalid keys must be closed and must not read stdin.

The compact representative workload runs both modes and records every mmap
attempt. Each ordinal is independently denied with reached ENOMEM, requiring
status 4, empty output, and release of every successful mapping. The ledger
tracks generation, address, and requested length; it rejects leaks, duplicate
or wrong-length releases, mremap, and allocation during publication. The
descriptor ledger requires one close attempt per successful key open and
retirement before stdin, with no retry. Injected close errors suppress the real
host syscall: they test attempted close and logical invalidation, not actual
host descriptor release; process exit releases that injected survivor.

Faults cover key open/read/EOF/close, stdin before and after a chunk, invalid
read counts, Interrupted retry, would-block, zero/invalid writes, partial
publication, and real EPIPE. A synthetic one-byte short write suppresses the
first host write while reporting one byte; the test expects the actual
remaining suffix once. Persistent Interrupted tests reach exactly the shared
call cap on stdin and stdout. Scale cases seal/open a 1 MiB payload and reject
one-byte excess for each mode, checking actual final probe requests/results.

Build target: `cargo test --test extended_seal_bytes_execution --no-run`.
Select an exact named group from the freshly emitted driver with its positional
name and `--exact --nocapture --test-threads=1`, under the root's serialized
timeout and GPU lock. Record actual bounded commands, source checkpoint,
local logs, elapsed times, observed allocation counts, and reached native
counts after admission. Runtime verification remains pending.
