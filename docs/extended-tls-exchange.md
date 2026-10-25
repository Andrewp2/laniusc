# tls-exchange

[`sample_programs/library/tls_exchange.lani`](../sample_programs/library/tls_exchange.lani)
is a bounded binary TLS 1.3 client and a one-connection echo server. The
application, handshake, certificate verification, record encryption, and TCP
adapter run in Lanius. It composes
[`ext::tls_connection`](../extended/ext/tls_connection.lani) and
[`ext::tls_tcp`](../extended/ext/tls_tcp.lani).

**All four application group-migration gates passed** on x86_64 Linux:
**76 native CLI cases across four independently compiled strict ELFs**.
Source enables X25519
with secp256r1 fallback and independent OS scalar slots, following the
[shared group contract](tls-group-integration-plan.md). Current receipts and
the preceding 74-case X25519 checkpoint are recorded separately below.

## CLI and trust

```text
tls-exchange client NUMERIC_ENDPOINT dns|ip EXPECTED_IDENTITY ANCHOR_DER < message.bin
tls-exchange serve NUMERIC_ENDPOINT ED25519_SEED_FILE DER_CHAIN_FILE
```

The client has exactly five arguments and the server exactly four.
`NUMERIC_ENDPOINT` is an IPv4 or bracketed IPv6 socket address with port
1–65,535. There is no DNS resolution. Paths are raw, nonempty byte strings of
at most 4,095 bytes; they need not be UTF-8. All argument, endpoint, path,
mode, and reference checks finish before signal setup, clocks, file opens,
stdin reads, or networking. Argument storage uses `snapshot(1,5,8259)`.

The client reads one explicitly selected DER trust anchor. It does not use
an OS trust store, infer trust from a peer-supplied root, or offer a
verification bypass. `dns` requests an ASCII SAN DNS-ID, with case and one
optional trailing root dot normalized by `service_identity`. Numeric labels
are valid DNS syntax. `ip` parses an unscoped IPv4 or IPv6 literal and requests
the corresponding SAN IP-ID. There is no implicit DNS/IP crossover, CN
fallback, wildcard reference, IDNA conversion, or search-list expansion.

An ordinary DNS reference supplies normalized SNI. An IP reference supplies
no SNI; a numeric DNS reference recognized as an IP literal also supplies no
SNI while retaining its explicitly chosen DNS identity family.

The client takes exactly one charged host UTC sample after reading stdin.
It requires a representable timestamp in UTC years 1–9999 and uses its
seconds for certificate validity. Clock failure has no fallback date. This
is a host-clock policy, not a claim that network time is trusted. Monotonic
time separately controls I/O deadlines and reversal detection.

The server reads a raw, provisioned 32-byte Ed25519 seed and an ordered DER
chain, leaf first. The seed requires actual EOF after byte 32; short or
long files are rejected. Concatenated certificate DER lengths provide chain
framing, without PEM or added separators. The chain has 1–8 certificates.
The engine checks that the seed's public key matches the actual leaf SPKI
before emitting a handshake flight. Provisioning and protecting that seed
remain the caller's responsibility.

The supported connection profile is TLS 1.3 with X25519 or secp256r1 ECDHE, Ed25519 server
authentication, SHA-256, and AES-128-GCM or ChaCha20-Poly1305. The application
prefers ChaCha20-Poly1305, sets the ordered groups to X25519 then secp256r1,
sends an initial X25519 client share, requests no ALPN, and
uses the engine's bounded ordered Ed25519 certificate-path profile with
explicit trust and SAN identity checks. Unsupported algorithms or path
constraints fail. There is no certificate fetching, general PKIX policy,
revocation service, PSK, resumption, early data, or client certificate
authentication in this program. The server deliberately accepts anonymous
clients; its output does not identify a client principal.

## Compile and run

From the repository root, with an already built current compiler at
`target/stdlib-build/debug/laniusc`:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env RUST_MIN_STACK=16777216 \
  target/stdlib-build/debug/laniusc --emit x86_64 --stdlib-root stdlib \
  --source-root extended sample_programs/library/tls_exchange.lani \
  -o target/tls-exchange
```

The option syntax is checked against the local
[`CLI argument parser`](../crates/laniusc-compiler/src/cli/args/parse.rs) and
[`entry compiler`](../crates/laniusc-compiler/src/cli/compile/entry.rs).
The CLI marks emitted native output executable on Unix. This usage command
is distinct from the admitted driver invocations below; it was not run as
another gate.

Given a provisioned seed, its matching ordered DER chain, an independently
chosen trust anchor, and a binary message, start the server and then promptly
start the client in another terminal:

```sh
timeout --kill-after=1s 10s target/tls-exchange serve 127.0.0.1:8443 \
  server-seed.bin server-chain.der > server-received.bin
```

```sh
timeout --kill-after=1s 10s target/tls-exchange client 127.0.0.1:8443 \
  dns path.example trusted-root.der < message.bin > client-received.bin
```

Each role retains its original five-second operation deadline. Check both
exit statuses. The server's certificate must match `path.example` under the
chosen anchor; the numeric transport address does not replace that identity.

## Exchange and output

The client first spools a complete binary stdin message of at most
1,048,576 bytes. It then connects, completes authentication, sends the
message, and writes authenticated peer application bytes to stdout. It
queues only accepted prefixes and drives send and receive together rather
than waiting to send the entire message before receiving a response.

The server accepts one connection, ignores stdin, and writes each
authenticated received application chunk to stdout while echoing it over
TLS. A chunk remains live until its complete echo has been accepted. It
does not accept a second connection after the first finishes or fails.

Stdout contains only received application bytes. No TLS framing, certificate
report, status text, or diagnostics are mixed into that stream. The adapter
does not expose application data before establishment and the client's
Finished has actually been sent. Each plaintext read checks the original
deadline immediately before copying, and publication checks it again.
Once expiry or another failure has been observed, the app publishes no
further plaintext.

Both roles limit total received application data to 1 MiB. At the cap, one
additional authenticated-byte read distinguishes clean close from excess;
an excess byte is consumed without publication and returns 7. Success
requires the peer's authenticated `close_notify`, the local close record
fully sent, the local write shutdown, and no pending input, output, or
plaintext. A TCP EOF without `close_notify` is a truncation failure.

Output is streaming. A later authentication, truncation, deadline, cleanup,
or host-write failure can leave an earlier authenticated plaintext prefix
on stdout. A nonzero status must therefore be checked even when bytes were
received. Successful writes mean immediate host acceptance, not durable
storage or an atomic output transaction.

## Storage, attempts, and deadline

Each credential file is limited to 1 MiB. The client message and each
direction's received application stream have separate 1 MiB limits; these
are not one cumulative file/message allowance. The certificate path layer
also applies its own shared chain/input/work/signature limits. Credential
files and client stdin require actual EOF. At a byte cap, a real one-byte
probe distinguishes EOF from excess input. Reads request at most 1,024
bytes, except that the fixed seed reader requests its remaining bytes.
The application reserves each owned file/message buffer before filling it
and keeps borrowed credential, argument, and message backing alive through
connection cleanup.

Files open read-only, no-follow, nonblocking, and close-on-exec. No-follow
applies to the final path component under OS path rules. Files need not be
regular files, but must supply complete bounded contents and EOF. Each
opened file receives one invalidating close attempt before networking;
the server closes its listener after its single accept. Sockets use
nonblocking and close-on-exec flags. Inherited stdin, stdout, and stderr are
borrowed and never closed by the application.

One original **5-second monotonic deadline** starts after CLI validation.
File reads, client stdin spooling, connect/accept, the handshake, duplex
exchange, and stdout publication share it. Retries never extend it. A
shared **131,072-credit HostBudget** covers actual host attempts and
conservative reservations for argument storage, allocation, cleanup, and
diagnostics. Clocks, signal setup, files, socket setup, polls, entropy,
transport, and stdio all draw from that budget. Interrupted retries count;
unused prepaid worst-case credits are not refunded or replenished.

**Inherited stdio is blocking.** Checks before and after stdin/stdout calls
cannot interrupt an idle stdin pipe or a full stdout pipe. The deadline is
observed around those calls, not a hard end-to-end wall-time bound for
arbitrary inherited descriptors. Socket operations are nonblocking and use
the same original deadline. The focused driver adds an independent outer
process timeout.

The TCP adapter obtains fresh ephemeral material from OS nonblocking
entropy after allocating its connection storage; there is no deterministic
production fallback. The provisioned server signing seed is separate from
that fresh ephemeral entropy. Its dual policy requests the engine's canonical
96-byte layout: 32 bytes each for ClientHello random, X25519 scalar and
P-256 scalar. Only a checked invalid P-256 scalar permits the adapter to
refill that slot, with eight candidates total under the same original
deadline and shared host budget. No clamping, reduction or group fallback
repairs a rejected scalar. The app does not copy an active connection
owner or treat copied key/state handles as independent cleanup authority.

Cleanup credits are reserved before acquisition, so expiry or an exhausted
operation budget still permits bounded retirement. The application closes
files/sockets and releases owned buffers on every exit. Connection teardown
precedes destruction of its borrowed backing. Argument storage is destroyed
after processing. These owners can remain live during streaming stdout
publication; publication does not wait for all owners to retire.

## Status and diagnostics

| Status | Meaning |
| --- | --- |
| 0 | The bounded exchange and authenticated bidirectional close completed |
| 2 | Invalid CLI, endpoint, path/reference syntax, or seed file length |
| 3 | Host argument access, signal, clock, entropy, file/socket/poll/I/O, returned-count, or cleanup failure |
| 4 | Argument, input, or connection storage allocation failed |
| 5 | Credential, TLS protocol, certificate/path/identity/time, bad peer, or truncation rejection |
| 7 | Byte/chain/work/record/control, host-attempt, or deadline limit |

After SIGPIPE Ignore is installed, failures get a bounded best-effort stderr
line containing the saved primary status, stage, cause class, and separate
cleanup error. A cleanup host error determines exit status 3 without erasing
the saved primary evidence. For example, a certificate rejection followed by
a failed close still reports primary 5 and the close errno. Stderr reporting
has eight prepaid attempts and does not recurse on reporting failure.
Early CLI, argument-service, or signal-setup failures may be quiet.

Stage numbers are 0 CLI, 1 signal setup, 2 files/stdin/storage, 3 clocks,
4 socket setup, 5 TLS attachment, 6 transport/cleanup, 7 exchange, and
8 stdout. Diagnostics contain fixed labels and numeric codes, not peer text
or key bytes. They are evidence of observed failures, not an exhaustive
serialization of nested engine errors.

## Focused executable driver

[`tests/extended_tls_exchange_execution.rs`](../tests/extended_tls_exchange_execution.rs)
compiles the actual application with stdlib and extended roots, applies the
unchanged strict ELF/jump checker, and runs it on x86_64 Linux. A `OnceLock`
shares the compiled ELF within one driver process; separate exact selections
each compile one independent app ELF.

The test-only
[`peer.py`](../tests/fixtures/extended/tls_exchange/peer.py) uses Python
[`ssl`, backed by OpenSSL](https://docs.python.org/3/library/ssl.html), as an
independent loopback peer in both directions. It fixes TLS 1.3 and X25519
for the retained cases; the new P-256 selection pins `prime256v1` instead,
uses an Ed25519 certificate chain, disables server tickets, and records the
actual OpenSSL version, TLS version, selected cipher, session reuse, received
bytes, and clean `unwrap` outcome. Its client requires certificate validation,
hostname checks, and one explicit CA file without loading default trust.
Its server deliberately follows the same anonymous-client policy as the
application server. Shared signed certificate fixtures come from
[`tls_tcp/peers.py`](../tests/fixtures/extended/tls_tcp/peers.py); their public
deterministic test seeds are not production entropy.

The exact selection
`tls_exchange_dual_policy_interoperates_with_p256_only_openssl_peers` adds
two binary 1,025-byte application cases, one in each role. Restricting each
independent peer to P-256 requires the application's real dual-group path;
the native client must handle the requested-group retry from its initial
X share. Both cases retain explicit trust/identity checks, exact authenticated
output, clean closure and descriptor/allocation ledgers, and assert an
initial 96-byte OS entropy request. Together with the retained 74 cases,
the four accepted selections total **76 native cases** at the migrated
source.

Rust and Python exchange a bounded binary request and receipt: fixed scalar
fields plus length-prefixed raw paths, payloads, and metadata. There is no
JSON transport or compatibility path. Python/OpenSSL orchestration and Rust
trace checking are test-only; neither implements a production TLS backend.

The three retained focused selections are:

- `tls_exchange_cli_interoperates_with_openssl_in_both_directions`: binary,
  empty, and 1 MiB exchanges, DNS/IP identity, wrong trust/name, raw bad peers,
  and an authenticated prefix followed by missing `close_notify`.
- `tls_exchange_cli_preflight_files_caps_and_io_failures`: CLI-before-host
  ordering, seed/chain/input caps and EOF probes, file errors, Interrupted
  retries, output progress, and genuine closed-pipe EPIPE.
- `tls_exchange_cli_releases_owners_preserves_errors_and_bounds_host_attempts`:
  every reached allocation denial for both roles, exact address/size and fd
  retirement, wall-clock/entropy/socket errors, certificate-time rejection,
  primary-plus-cleanup errors, and shared call-budget exhaustion.

Trace assertions pair every successful mmap with its exact successful
munmap address/size, reject brk/mremap, and require one invalidating close
attempt per acquired fd. An injected close failure proves the attempt and
owner disarm, not a successful kernel close. The tests preserve all input
and credential bytes and forbid connection allocations after entropy starts.
They check actual call reachability rather than assuming fault ordinals.

An injected successful write return of 1 is a **synthetic reported-progress**
case: strace suppresses that host write, so the captured output intentionally
omits that byte. It is not evidence that the kernel delivered one byte.
Interrupted and invalid-count injections likewise exercise returned results;
ordinary loopback transfers, EOF probes, and closed-pipe EPIPE use real host
behavior. The reusable TCP suite owns the broader transport/protocol matrix.

## Current group-migration admission

All four exact selections passed on the unchanged migrated sources. Each
invocation compiled one strict ELF with the GPU compiler and reused it for
that selection's native application processes: **four strict ELFs and 76
native processes total**. Application and TLS execution were native x86_64
Linux, not GPU kernels. Source versions were application `41e04c7f`, Rust
driver `1165d6af`, peer helper `34a700bd`, adapter `b5125b31`, portable
engine `eaf51c4c` and negotiation `3f089664`.

Receipts are under `target/stdlib-work/tls-connection-admission/`:

| Exact selection | Native cases | Elapsed | Receipt |
| --- | ---: | ---: | --- |
| `tls_exchange_dual_policy_interoperates_with_p256_only_openssl_peers` | 2 | 28.51 s | `group-app-p256-first.log` |
| `tls_exchange_cli_interoperates_with_openssl_in_both_directions` | 11 | 35.08 s | `group-app-interop-first.log` |
| `tls_exchange_cli_preflight_files_caps_and_io_failures` | 26 | 29.71 s | `group-app-preflight-first.log` |
| `tls_exchange_cli_releases_owners_preserves_errors_and_bounds_host_attempts` | 37 | 34.63 s | `group-app-owners-first.log` |

The joint Rust build of four targets took **1.75 s**
(`group-build-frozen.log`), separately from GPU compilation and native
execution inside those gates. No application, library, fixture or driver
changes, and no additional failures, occurred during this admission. The
96-byte initial entropy layout and eight-candidate maximum remain part of
the documented adapter contract; passing these gates does not add a scalar
fallback, repair or fresh operation budget. Historical parser and harness
failures below remain excluded from these accepted counts.

## Pre-admission source corrections

The first exact interoperability selection failed before ELF emission in
4.32 seconds. Its parser stack-effect error was followed by a misleading
source-text fallback diagnostic pointing at the imported handshake cursor's
nested `Iterator<View<u8>>` implementation. The same public implementation
was already admitted in other controls and remains unchanged.

Ignored diagnostic probes narrowed the failure to application match-arm
blocks. The language's current
[`match_arm` grammar](../grammar/lanius.bnf) requires an expression after the
arrow; it has no block-expression alternative. A tiny source without TLS
imports reproduced rejection with one block arm in 2.36 seconds. Replacing
that arm with a typed helper call compiled and returned native exit 0 twice
in a 2.44-second harness invocation. Those are diagnostic executions, not
application interoperability or performance results. A separate scaffold
probe parsed successfully and exposed an i32-to-i64 assignment requiring an
explicit cast in diagnostic decimal formatting.

The app now uses ordinary typed helpers for the arm bodies, terminates
standalone match expressions, and performs that explicit cast. Status
mapping, diagnostic bytes, I/O allowances, cleanup, and the library's public
iterator contracts are preserved. No compiler or library workaround was
introduced. The original probes and logs remain under ignored
`target/stdlib-work/tls-connection-admission/app-parser-probes/`; the first
failure is retained as `exchange-interop-first.log` in its parent directory.
They are not checked in. The corrected application has since passed all
three real executable gates below.

## Admission evidence and commands for the preceding X25519 checkpoint

The exact selection
`tls_exchange_cli_interoperates_with_openssl_in_both_directions` passed in
**28.90 seconds**, compiling **one strict ELF** and executing **11 native
CLI cases**. It covers client and server exchanges with binary, empty, and
1 MiB payloads, explicit DNS/IP identity, wrong anchor and name rejection,
a raw bad peer, and an authenticated output prefix followed by truncation.
Successful peer receipts check the actual OpenSSL version, TLS 1.3 cipher,
fresh session, exact duplex bytes, and clean `unwrap`.

The accepted source hashes begin `737a6952` (application), `bf9bf55a`
(driver), and `ed919ef6` (peer). The ignored log is
`target/stdlib-work/tls-connection-admission/exchange-interop-match-helpers.log`.
The initial parser rejection is excluded from accepted ELF/native counts.

The separate exact selection
`tls_exchange_cli_preflight_files_caps_and_io_failures` passed **26 native
cases in 27.62 seconds** using **one independently compiled strict ELF** and
the same frozen source hashes. It checks CLI rejection before host activity,
seed/chain shapes, actual EOF/excess probes and 1 MiB caps, file and cleanup
errors, Interrupted retries, the explicitly synthetic reported-short-write
control, and real closed-pipe EPIPE. Its ignored log is
`target/stdlib-work/tls-connection-admission/exchange-preflight-first.log`.

The final exact selection
`tls_exchange_cli_releases_owners_preserves_errors_and_bounds_host_attempts`
passed **37 native cases in 29.86 seconds** with **one independently compiled
strict ELF**. It denies every setup allocation reached in successful client
and server baselines, checks exact memory and fd retirement, requires one
actual realtime sample, exercises clock/entropy/socket faults, preserves
primary TLS rejection alongside cleanup failure, and exhausts the shared
131,072 host credits. Its ignored log is
`target/stdlib-work/tls-connection-admission/exchange-owners-first.log`.

Together the three accepted exact selections account for **74 native cases
and three independently compiled strict ELFs**. The source hashes are
unchanged across all three. The test driver binary used was
`target/stdlib-build/debug/deps/extended_tls_exchange_execution-fddc1c0b16b27aa4`.

The parent serializes these bounded application commands. The app author ran
only the explicitly authorized diagnostic probes described above. Logs and
emitted artifacts belong in ignored `target/stdlib-work/` storage and are not
checked in. The commands below reproduce the selections; they do not request
a repeat of the accepted gates.

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test extended_tls_exchange_execution --no-run
```

After a fresh build, use its actual emitted test-binary path. The accepted
binary and separate bounded selections were:

```sh
TLS_EXCHANGE_TEST=target/stdlib-build/debug/deps/extended_tls_exchange_execution-fddc1c0b16b27aa4

tls_exchange_gate() {
  timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s env RUST_MIN_STACK=16777216 \
    LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 "$TLS_EXCHANGE_TEST" \
    --exact "$1" --nocapture --test-threads=1
}

tls_exchange_gate tls_exchange_cli_interoperates_with_openssl_in_both_directions
tls_exchange_gate tls_exchange_cli_preflight_files_caps_and_io_failures
tls_exchange_gate tls_exchange_cli_releases_owners_preserves_errors_and_bounds_host_attempts
```

These gates concern the stated bounded application and Linux native target.
They do not establish general TLS/PKIX coverage, revocation, mutual client
authentication, network availability, secure provisioning, physical
side-channel resistance, or portability. TLS protocol semantics follow
[RFC 8446](https://www.rfc-editor.org/rfc/rfc8446.html); the engine and adapter
guides state their precise supported policies and resource contracts.
