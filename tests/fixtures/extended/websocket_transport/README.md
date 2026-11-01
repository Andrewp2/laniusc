# Borrowed WebSocket transport contracts

`contracts.lani` exercises the public generic `websocket_upgrade::Client<T>`
and `websocket_stream::Stream<T>` APIs using one deterministic Lanius transport.
Its input, output and short I/O scripts belong to the tests. It uses no sockets,
clocks, OpenSSL, random generator, C shim or Python implementation.

The Rust registration compiles the producer with the standard and extended
source roots, emits a raw x86_64 executable without native linking, then runs
that executable and requires exit zero with empty output. Compilation alone is
not acceptance.

## Executable acceptance

On Linux x86_64, the full producer compiled successfully and ran to exit zero
with empty stdout/stderr. All **11 top-level scenario functions** ran in one
process, including their finite fault/quota loops. These are direct executable
receipts, not 11 separate process runs or a Rust libtest runtime result.

Local logs are under `target/stdlib-work/`:

- `websocket-transport-contracts-compile-quota-correction.log`: compile exit 0.
- `websocket-transport-contracts-native-quota-correction.log`: executable exit 0.
- `websocket-transport-driver-build-first.log`: both new Rust integration
  drivers built successfully with `--no-run` in 2.00 seconds. This build checks
  registration and types; no Rust libtest runtime was executed.

Accepted artifact SHA256 values:

| Artifact | SHA256 |
| --- | --- |
| `contracts.lani` | `da71889b32722418e4eaeab834a5faebb882f4284d75a33bafc8febbbd4bfefe` |
| `websocket_stream.lani` | `be16005d53ce0b808b0a5a807a434aac31e7399bcaf30518dbad23c64d28d55b` |
| `websocket_upgrade.lani` | `c8f4a42d44cab9fae66bbdcec92e6f6924984dc36890e06b6592147179ea5262` |
| Raw executable | `6d7a17ee3fd32438343cbc058df5ae6f598d0c5f5390923bdbf93d4465dc5591` |

The first admission rejected a fixture spelling where `View<u8>=` became the
`>=` token; whitespace corrected it. An earlier executable trapped on a stale
fixture expectation that a handshake byte-cap failure reports completed bytes.
The documented contract reports zero for that admission failure and preserves
the 158 consumed bytes in `stats.read_bytes`. Correcting that expectation and
tightening the one-byte handshake cursor budget to 512 produced the accepted
run above; these corrections did not change either library module.

## Covered state space

Covered scenarios in the producer:

- Construction and memory-only destruction with a transport implementing no
  I/O traits; typed bounds/limits/request validation and inactive owner errors.
- Handshake request and expected-accept copies survive source mutation.
- Exact request bytes, short writes, Interrupted and WouldBlock preserve offsets.
  Every handshake step performs at most one inner call; flush completes before
  the first read. One-byte response reads remain under a finite work budget.
- Ready steps are idempotent without I/O. Protocol selection and coalesced frame
  bytes survive conversion; failed stream-limit admission leaves Ready usable.
- Prefetched bytes are copied and consumed once without an inner read; split
  UTF-8 text and interleaved Ping preserve message assembly.
- Peer Close is explicit; another receive returns Closed without another read.
  Local Close becomes sent/closed only after both bytes and inner flush finish.
- Partial reads retain input across WouldBlock. None means actual WouldBlock;
  nonfinal frames return Some(Pending). EOF without Close remains a typed error.
- Queue admission performs no I/O, rejects a second pending frame, and copies
  payloads. Short writes and flush-phase WouldBlock never replay accepted bytes.
  Idle flush performs no inner call; queued destruction discards memory only.
- Invalid positive/negative read, write and flush counts, WriteZero and injected
  Host(55) errors preserve the first terminal failure and its counters. Replaying
  send/receive/flush or handshake methods performs no more transport calls.
- Partial-frame EOF, fragmented-message EOF, malformed frames and invalid UTF-8
  remain distinct. A poisoned wire connection permits one valid error Close,
  while rejecting further data.
- Zero/one-call and zero/one-byte receive quotas, a full partial-frame buffer and
  a partial-write quota retain exact completed counts and unsent bytes.
- Exact encoded-size admission rejects oversized fragmented sends and Close
  before mutating wire state. A smaller frame still works afterward. The server
  role accepts masked input and emits unmasked output.
- Handshake write/flush/read failures and I/O-call quota failures retain
  partial-request, full-request or partial-response counts as appropriate.
  Local read-byte admission returns completed zero while keeping read progress
  in stats. Bad Accept, malformed HTTP, truncated headers, read limits and HTTP
  work limits remain sticky.

No allocation-failure injection, connected transport, user-program GPU support
or formal ownership proof is claimed by this fixture.
