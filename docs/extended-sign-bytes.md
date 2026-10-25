# sign-bytes

[`sample_programs/library/sign_bytes.lani`](../sample_programs/library/sign_bytes.lani)
creates and verifies raw detached signatures using the real
[`ext::ed25519`](../extended/ext/ed25519.lani) implementation. It signs the
complete binary message supplied on stdin. All application behavior is
Lanius; the independent test oracle is outside the executable.

Runtime admission **passed on 2026-10-24** for x86_64 Linux ELF output from
the GPU compiler, executed natively on the CPU. Four separately selected
groups passed 128 native cases using four independently compiled strict
ELFs. These gates establish the tested target scope, without claiming other
targets or isolated signature throughput.

## CLI and byte formats

```text
sign-bytes sign SEED_FILE
sign-bytes verify PUBLIC_KEY_FILE SIGNATURE_FILE
```

`SEED_FILE` contains exactly **32 raw seed bytes**. It is not a hex string or
a 64-byte expanded secret key. `PUBLIC_KEY_FILE` contains exactly **32 raw
public-key bytes** and `SIGNATURE_FILE` exactly **64 raw detached signature
bytes**. No file includes a newline, length prefix, or envelope. The caller
supplies and trusts the intended public key. This application does not
generate keys or write a public-key file.

Sign writes exactly 64 raw signature bytes on success, without a newline or
the message. Verify always leaves stdout empty: status 0 means valid and
status 5 means invalid. Stderr is unused. Both commands accept arbitrary
binary message bytes, including empty input and NULs.

The scheme is **pure Ed25519**, as defined in
[RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html#section-5.1).
There is no context or prehash option. Chunked reading does not change the
message being signed; this is a bounded whole-message application.

Arguments are snapshotted with `snapshot(1,3,8196)`, excluding argv[0]. The
8,196-byte total budget accommodates `verify` and two 4,095-byte paths, without
terminating NULs. It imposes no executable-name limit. Commands require exact
arity, and each path must contain 1–4,095 raw bytes. Paths need not be UTF-8.
All command, arity, and path checks finish before any file open or stdin read.
There are no aliases, default command, or options.

With the compiler built, from the repository root:

```sh
mkdir -p target/stdlib-work/sign-bytes
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/sign_bytes.lani \
  -o target/stdlib-work/sign-bytes/sign-bytes
target/stdlib-work/sign-bytes/sign-bytes sign seed.bin \
  < message.bin > signature.bin
target/stdlib-work/sign-bytes/sign-bytes verify public.bin signature.bin \
  < message.bin
```

These are usage commands; accepted execution evidence is recorded below.

## Fixed-file reads and ownership

Every seed, public-key, or signature file opens read-only with no-follow,
nonblocking, and close-on-exec flags. Final-component symlinks fail to open;
earlier path components follow OS rules. Nonblocking open avoids waiting for
a FIFO peer. There is no separate regular-file restriction: the descriptor
must supply its exact required bytes and EOF under the bounded read contract.
A no-peer FIFO supplies early EOF and fails the length check.

The app reads the required 32 or 64 bytes into packed stack backing, then
makes an actual one-byte EOF probe. Early EOF or a positive probe returns 2.
Every successful open receives exactly one invalidating close attempt,
including after a failed read or length check. Close errors return 3 and
override an earlier format or call-budget failure; close is never retried.
Verify closes the public-key owner before opening the signature file and
closes the signature owner before reading stdin. Any fixed-file failure
prevents stdin consumption. Files are never modified.

After file validation, the app reserves an owned `alloc::io::Buffer` for the
complete message. Its argument snapshot and message buffer are explicitly
released on every outcome. Key/signature storage and returned `Signature64`
are inline values with no allocation or destroy obligation. The signature
value stays alive through output. The primitive allocates no memory, and the
app allocates nothing during publication. Stdin and stdout remain borrowed
and are never closed.

Views retain their actual stack or owned-buffer backing throughout each
call. The logical byte caps do not specify physical View width, exact RSS,
or total stack usage.

Main installs SIGPIPE Ignore before allocation, so a broken output pipe can
return EPIPE and reach cleanup. This setup also runs for verify even though
verify makes no stdout calls. No explicit secret erasure is promised.

## Input, work, and publication bounds

Each command accepts at most **1,048,576 message bytes**. The input buffer
reserves that cap before reading. Reads use packed 1,024-byte scratch and
request no more than the remaining space. Success requires actual EOF. At
the cap, an actual one-byte probe distinguishes exact EOF from excess input.
A positive probe consumes that extra byte, stores none of it, and returns 7.

The app performs no signature operation or publication until the complete
message has been read successfully. Verify evaluates the signature only after
EOF, including when the supplied signature will be invalid. Thus an oversized
message returns 7 before cryptographic rejection. Sign publishes only after
the primitive returns its completed signature.

A shared **131,072-attempt budget** counts fixed-file reads and EOF probes,
stdin reads and its EOF probe, and stdout writes, including Interrupted
retries. Open, close, signal setup, and argument-service calls are outside
this counter. The app charges before each data I/O attempt. Other host
errors, invalid returned counts, or a zero-progress write return 3. Tiny reads
or repeated interruptions can exhaust the call budget below the byte cap.
This bounds attempted calls, not the duration of a blocked host operation or
an isolated cipher/signature benchmark.

Signing handles partial writes and resumes at the acknowledged byte offset.
A later host failure or exhausted budget can leave a signature prefix. It
does not replay completed bytes or promise a transaction, durable flush, or
resumable signing operation. Verify never publishes bytes on any path.

| Status | Meaning |
| --- | --- |
| 0 | Signature fully written, or detached signature valid |
| 2 | CLI/path or seed/public/signature file length invalid |
| 3 | Signal, open/read/close, stdin, or stdout failure |
| 4 | Argument or message-buffer allocation failed |
| 5 | Well-sized public key/signature does not verify |
| 7 | Input/call limit or defensive primitive bounds/length failure |

The primitive reports malformed/noncanonical encodings, weak public keys,
invalid scalars, and failed equations as `false`, which maps to 5. Its view
metadata and exact-length errors map to defensive status 7 after the app's
own preflight. Verification follows the library's canonical subgroup policy;
it is not a promise that every adversarial encoding has the same acceptance
set as another implementation.

## Focused driver

[`tests/extended_sign_bytes_execution.rs`](../tests/extended_sign_bytes_execution.rs)
compiles the real app with stdlib and extended roots and uses the unchanged
shared strict ELF/jump checker. A `OnceLock` shares one emitted executable
among groups selected within the same driver process. Separate invocations
compile one executable each, allowing the root to serialize bounded gates.
The accepted run used four separate exact invocations, rather than one
whole-target invocation.

| Exact test | Accepted native cases |
| --- | ---: |
| `sign_bytes_vectors_tamper_and_fixed_file_policy` | 80 |
| `sign_bytes_owned_cleanup_and_io_faults` | 41: 35 fixed plus three sign and three verify allocation denials |
| `sign_bytes_message_boundaries_and_scale` | 4 |
| `sign_bytes_shared_call_budget_and_close_precedence` | 3 |

The accepted total was **128 native cases**. Each representative mode
discovered and reached all three allocation-denial positions. No physical
View width or allocation count is hardcoded. Ordinary cases have five-second
native timeouts plus one-second termination grace; scale and budget cases
have 20 seconds plus the same grace.

The independent oracle loads libsodium through Python ctypes and directly
calls its seed-keypair, detached-sign, and detached-verify functions. It
passes binary files and ordinary arguments, with no JSON transport or Python
implementation behind the app. Oracle processes have a separate five-second
timeout. The oracle uses the
[single-part Ed25519 APIs](https://doc.libsodium.org/public-key_cryptography/public-key_signatures#detached-mode),
with a seed-derived public key and complete 64-byte signatures.

Ordinary cases compare complete signatures and verify results for empty,
binary, SHA-512 block-boundary, and application chunk-boundary messages. The
first three [RFC 8032 section 7.1 vectors](https://www.rfc-editor.org/rfc/rfc8032.html#section-7.1)
check independently published seed/public/message/signature bytes as well as
libsodium. Tampering covers both halves of the signature, public-key and
message positions, malformed/weak points, and out-of-range scalars. These
chosen invalid controls must reject in both implementations; they do not
assert identical policies for every possible point encoding.

CLI and fixed-file cases cover invalid arity/commands, empty/long paths,
snapshot overflow, raw non-UTF-8 paths, short/long seed/public/signature
files, missing files, final symlinks, a symlink in an earlier path component,
and no-peer FIFOs. The driver checks regular input files remain unchanged.
Invalid CLI must open nothing; invalid files must close every owner without
reading stdin. Every verify path requires no stdout attempt.

The compact representative workload runs sign and verify, discovers all
mmap attempts, and denies each ordinal with reached ENOMEM. Every successful
mapping must be released once with its exact address and requested length.
The ledger tracks allocation generation as well as address, rejects leaks,
unknown/double/wrong-length releases and mremap, and forbids allocation after
publication starts. The descriptor ledger checks read-only open flags,
sequential ownership, one close attempt per successful open, and retirement
before stdin. Injected close errors suppress the real host syscall: these
cases check attempt and logical invalidation; process exit releases any
injected survivor.

Faults reach first/second open and close failures, fixed-file read and EOF
failures, invalid counts, Interrupted retries, stdin before/after a chunk,
would-block, zero/invalid writes, and real EPIPE. A synthetic one-byte short
write suppresses the host write while reporting one byte, so the expected
actual output is the remaining 63-byte suffix. Close failures override file
length errors. Persistent interruptions reach the shared attempt cap on
stdin/stdout and fixed-file reads; a failed final close also overrides that
exhausted fixed-file budget.

Scale cases sign/verify a 1 MiB message and reject one-byte excess in both
modes, checking actual final probe requests/results. Timers around the two
successful native `run()` calls report observed case wall milliseconds,
including setup, strace, process startup, and trace parsing. They exclude
compiler/oracle time and do not measure isolated signature throughput.

## Accepted execution evidence

The accepted source checkpoint was
`bad37f721a7fbcb6dac919d92c219b3924eceaf8`. The app body and driver were
unchanged from that checkpoint through all four gates; this acceptance update
changes only the guide. Independent source review was clean.

The fresh joint resume driver build took **0.20 s**, recorded in the ignored
local log `target/stdlib-work/tls-auth-admission/build-resume-foundations.log`.
It included other foundation drivers and is not an isolated application
compile measurement. The focused build target is
`cargo test --test extended_sign_bytes_execution --no-run`.

Each exact group passed with zero failures:

| Group | Native cases | Gate elapsed | Ignored local log |
| --- | ---: | ---: | --- |
| Vectors/tamper/fixed-file policy | 80 | 10.31 s | `target/stdlib-work/tls-auth-admission/sign-ordinary.log` |
| Ownership/allocation/I/O faults | 41 | 7.18 s | `target/stdlib-work/tls-auth-admission/sign-cleanup.log` |
| 1 MiB scale and exact/excess bounds | 4 | 7.33 s | `target/stdlib-work/tls-auth-admission/sign-scale.log` |
| Attempt budget and close precedence | 3 | 19.29 s | `target/stdlib-work/tls-auth-admission/sign-budget.log` |

The last group reached the shared **131,072-attempt** cap for interrupted
stdin, stdout, and fixed-file reads. It also confirmed that a failed close
overrides an exhausted fixed-file budget. Allocation and descriptor cleanup
passed under the exact ledgers and injected-close model described above.

The successful 1 MiB sign and verify cases observed **251.021 ms** and
**222.686 ms**, respectively. These are case wall measurements including
setup, strace, native startup, and trace parsing, excluding compiler and
oracle time. They are not isolated signature throughput.

The exact accepted runtime commands, from the repository root, were:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_sign_bytes_execution-41354c6f8b14ce4d \
  --exact sign_bytes_vectors_tamper_and_fixed_file_policy \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/sign-ordinary.log 2>&1
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_sign_bytes_execution-41354c6f8b14ce4d \
  --exact sign_bytes_owned_cleanup_and_io_faults \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/sign-cleanup.log 2>&1
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_sign_bytes_execution-41354c6f8b14ce4d \
  --exact sign_bytes_message_boundaries_and_scale \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/sign-scale.log 2>&1
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/extended_sign_bytes_execution-41354c6f8b14ce4d \
  --exact sign_bytes_shared_call_budget_and_close_precedence \
  --nocapture --test-threads=1 \
  > target/stdlib-work/tls-auth-admission/sign-budget.log 2>&1
```
