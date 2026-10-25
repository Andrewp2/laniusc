# Incremental TLS wire framing

`ext::tls_framing` reassembles one TLS record or handshake frame at a time in caller storage. It copies fragments, reports the exact consumed input prefix, and keeps the completed frame available until the caller consumes or resets it. Production code allocates nothing and performs no IO. The implementation is [tls_framing.lani](../extended/ext/tls_framing.lani).

The framing definitions are the one-byte kind plus three-byte length in [RFC 8446 section 4](https://www.rfc-editor.org/rfc/rfc8446.html#section-4), and the record type, legacy version, and two-byte length in [sections 5.1 and 5.2](https://www.rfc-editor.org/rfc/rfc8446.html#section-5.1). This module retains unknown handshake kinds and opaque record type/version bytes. Typed codecs, record authentication, and the connection enforce their semantic legality.

## Constructors and frames

Here `View` and `Result` abbreviate `core::slice::View` and `core::result::Result`. Import those modules and `ext::tls_framing`.

```lanius
pub enum Error {
    Bounds, InvalidLimit, BufferTooSmall, Ready, NotReady, TooLarge, Poisoned
}
pub struct Progress { consumed: i32, ready: bool }
pub struct FeedFailure { cause: Error, consumed: i32 }
pub struct RecordFrame {
    wire: View<u8>, payload: View<u8>, content_type: u8, legacy_version: u16
}
pub struct HandshakeFrame { wire: View<u8>, body: View<u8>, kind: u8 }

pub fn record_decoder(storage: View<u8>, max_body: i32)
    -> Result<RecordDecoder, Error>;
pub fn handshake_decoder(storage: View<u8>, max_body: i32)
    -> Result<HandshakeDecoder, Error>;
```

Record body limits are `0..65535`; handshake body limits are `0..16777215`. Constructors require storage for the **header plus the entire configured maximum**: five bytes for a record, four for a handshake. A zero maximum still needs header storage. The limit is fixed for that decoder. Constructors check metadata, the limit domain and addition, then storage capacity, without writing any storage.

These are wire domains, not TLS acceptance limits. TLSPlaintext is limited to 16384 bytes and TLSCiphertext to 16640 bytes by the cited RFC sections; callers must configure and enforce their applicable profile. A handshake connection also needs practical message and certificate limits. Providing a larger raw framing buffer does not make an oversized TLS message acceptable.

`wire` includes the header; `payload`/`body` excludes it. The record version is decoded as a big endian `u16`; no version/type check occurs here. The returned views preserve the caller's backing and physical stride.

## Incremental state

Both decoder types expose the following methods; their `frame()` result has the distinct corresponding frame type above.

| Method | Contract |
| --- | --- |
| `borrow()` | Borrow the same decoder state |
| `buffered()` | Number of header/body bytes retained so far |
| `ready()` | A complete frame is available |
| `is_poisoned()` | An announced length exceeded the configured maximum |
| `feed(input) -> Result<Progress, FeedFailure>` | Copy only the prefix needed for the current frame |
| `frame() -> Result<RecordFrame / HandshakeFrame, Error>` | Borrow the complete frame; no mutation |
| `consume() -> Result<i32, Error>` | Require readiness, return complete wire length, and reset metadata |
| `reset() -> i32` | Discard any partial/ready/poisoned state and return its buffered byte count |

A valid empty feed on an incomplete decoder succeeds with `consumed=0, ready=false`. Header-only frames become ready as soon as the complete header arrives. A feed stops at the first complete frame, even if input contains several frames. Keep the unconsumed suffix and offer it after handling the frame and calling `consume()`. No tail is queued internally, and no automatic consume occurs.

While ready, every valid feed, including an empty feed, returns `Ready` with consumed zero. Repeated `frame()` calls borrow the same stable bytes. `frame()` and `consume()` return `NotReady` on incomplete state. They return `Poisoned` on poisoned state. These failures change neither metadata nor storage.

An oversized announcement is rejected immediately when the header completes. `TooLarge` reports only bytes consumed from **that call** to finish the header. Earlier header fragments remain counted in `buffered()`. No announced body or following frame byte is copied. The decoder retains the rejected header and becomes poisoned; subsequent valid feeds return `Poisoned`, consumed zero. An explicit `reset()` is needed to reuse its storage. Resetting is a caller-directed abandonment of framing state, not evidence that a live TLS stream has resynchronized.

Malformed logical input metadata returns `Bounds`, consumed zero, before checking ready/poisoned state. The decoder and its storage remain unchanged. Constructor metadata has the same priority over limit/capacity errors. Logical validity means nonnegative start/length with an `i32`-representable end; physical backing remains a caller precondition.

`consume()` and `reset()` only change metadata. Neither erases old bytes, and neither writes the storage tail. There is no end-of-stream operation: a transport caller must classify EOF with a buffered partial frame as truncation and apply connection policy.

## Storage and ownership

The decoder retains its caller-provided storage view. Keep that storage alive and exclusively available for decoder writes. Input fragments must remain valid and immutable during each feed. Input, writable storage, and the decoder object's own memory must be mutually disjoint and physically backed for their declared ranges. In-place or partial input/storage overlap is unsupported.

A complete frame borrows storage. Finish using all copies of its views before consume, reset, storage mutation, or storage destruction. Readiness prevents another feed from overwriting it; it does not prevent callers from violating these manual alias rules. Inputs may be changed or released after a feed returns because accepted bytes have been copied.

Decoder value copies duplicate scalar progress and alias the same backing. They are not independent writable streams or snapshots of bytes. Copies may inspect an unchanged completed frame, or transfer the sole writable authority to one copy while retiring the old copy. Keep only one active writer/reset authority for shared backing. The tests exercise read-only copies and that explicit handoff, not concurrent or divergent writers. Use checked constructors; implementation fields are not a serialized resume format.

Each accepted byte is copied once. Feed work is proportional to the consumed prefix; header decoding has fixed cost. Frame access, consume, and reset take constant work. Storage is `header + max_body` caller bytes plus fixed decoder metadata. There is no allocation, host service, secure erasure, transport read, or elapsed-time guarantee in the production module.

## Layer composition

Feed transport bytes to a record decoder, inspect the complete outer header, and pass the complete record to the appropriate plaintext or authenticated record layer. Only authenticated handshake content should advance the handshake decoder where encryption applies. Consume a record only after its borrowed contents are no longer needed. Feed the handshake decoder with successive handshake content fragments, retain unconsumed coalesced bytes, then pass complete `wire`/`body` to [typed handshake codecs](extended-tls-handshake.md) and the [transcript/schedule layers](extended-tls-schedule.md).

The connection still controls record size/version/type legality, authentication failure, handshake ordering, negotiated extensions, key epochs, fragmentation across key changes, interleaved content, alerts, transport EOF/partial IO, fairness/resource budgets, and certificate trust/identity policy. This module does not establish a TLS connection. The [authentication integration](extended-tls-auth-foundation.md) covers a separate fixed cryptographic flight.

## Accepted verification

All four focused gates passed on **Linux x86-64** using GPU-compiled native output. The driver is [extended_tls_framing_execution.rs](../tests/extended_tls_framing_execution.rs), with [three fixture sources](../tests/fixtures/extended/tls_framing/). Production and fixtures were unchanged from the independently reviewed snapshot.

| Gate | Accepted evidence | Elapsed |
| --- | --- | --- |
| `incremental_record_and_handshake_streams_match_independent_model` | 242 logical cases, 484 layout cases, 6992 actions: short-frame splits, deterministic partitions/coalescing, zero/exact limits, unknown metadata, full record u16 boundary, larger handshake body, packed/native-strided offsets | 10.32 s |
| `framing_error_priority_backpressure_and_alias_handoff_match_model` | 61 logical cases, 122 layout cases, 768 actions: constructor domains/capacity, malformed metadata priority, stable readiness/backpressure, header-only oversize poisoning, reset/truncation, copy read/handoff, exact progress and untouched bytes | 9.15 s |
| `ordinary_record_payload_to_handshake_consumer_executes` | Ordinary imports and record-to-handshake coalesced consumption without Error projections | 4.22 s |
| `full_u24_handshake_uses_one_explicit_owned_backing` | Full 16777215-byte body, every pattern byte checked, final coalesced tail unconsumed, consume/reset, max+1 constructor rejection, one exact allocation/release ledger | 5.43 s |

The stream oracle independently concatenates offered bytes and selects the next wire boundary; it does not reproduce the production copy loops. It checks every reported state field, consumed count, complete wire byte, storage-capacity byte, and offered input byte after each action. Native assertions check immediate three-byte guards on every action and the whole storage exterior after each case. Malformed input tests cover negative start/length and overflowing end in partial, ready, and poisoned states. The model gates can share one compiled protocol ELF through `OnceLock` within one driver invocation. The accepted gates were run in **four separate exact invocations**, so they compiled **four strict ELFs** and ran **four native processes**; the protocol fixture was compiled once in each model invocation.

The full u24 fixture deliberately allocates its caller storage with `alloc::vec::Vec<u8>`, using exactly 16777225 initialized bytes: three prefix guards, four header bytes, the full body, and three suffix guards. A reused 4096-byte input array feeds the body. Its last call consumes 4095 of 4096 offered bytes; no earlier call may report readiness. Every body byte must equal its index modulo 256, and an independently computed sum is compared by the host. The fixture reports actual capacity and stride, checks source/guard bytes, rejects limit 16777216, consumes the full frame, resets a truncated prefix, and reuses the decoder for a zero-body frame. All returned failure statuses pass through explicit owner destruction before exit.

The two model processes and the ordinary consumer had empty `mmap`, `munmap`, `mremap`, and `brk` traces. **The full u24 process intentionally had one allocation**: the driver verified one successful mapping and one matching address/size release, with an empty final live-owner ledger. Its allocation is separate from the production framing allocation-free contract. No zero-allocation claim applies to that process.

The shared build with the certificate-info driver completed in **1.39 s**, recorded in `target/stdlib-work/tls-auth-admission/build-certificate-framing.log`. The accepted executable was `target/stdlib-build/debug/deps/extended_tls_framing_execution-fee4a9f46e739fb3`. Runtime logs in the same admission directory are `framing-streams.log`, `framing-errors.log`, `framing-ordinary.log`, and `framing-full-u24.log`. These ignored local logs are evidence paths, not checked-in captures.

To rebuild only this driver, run:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test extended_tls_framing_execution --no-run
```

The accepted runtime runs used the following command separately for each exact gate in the table. Set `test_name` to that gate's full name; the example selects the stream model. Use the executable path reported by a fresh build if its basename differs.

```sh
test_name=incremental_record_and_handshake_streams_match_independent_model
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  LANIUS_DEBUG_STAGE_ERRORS=1 \
  target/stdlib-build/debug/deps/extended_tls_framing_execution-fee4a9f46e739fb3 \
  --exact "$test_name" --nocapture --test-threads=1
```

Each command has a 100-second outer guard, 35-second lock wait, and 60-second inner guard. GPU codegen has a 45-second guard; each native subprocess has a 30-second guard. These results establish the exercised framing, storage, and progress contracts on Linux x86-64. They do not establish live TLS interoperability, connection policy, throughput, or other-target behavior.
