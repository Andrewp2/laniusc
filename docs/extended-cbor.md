# CBOR wire events

`ext::cbor` is an allocation-free Lanius codec for the complete generic CBOR
wire format. It handles all eight major types, full-width unsigned and negative
integer arguments, binary/text strings, arbitrary map keys, tags, simple values
and exact floating-point bit patterns. Definite and indefinite containers and
chunked strings are supported. Parsing uses a caller-owned stack and iterative
loops, with no recursive call growth.

Executable evidence covers **x86_64 Linux using the GPU compiler to produce
native executables**. GPU-kernel execution and other targets are unverified.
The [ZIP manifest application](extended-zip-manifest.md) uses the encoder in a
real program that verifies archives and preserves raw names in CBOR byte strings.

The wire reference is [RFC 8949 sections 3–5 and Appendices A and
F](https://www.rfc-editor.org/rfc/rfc8949.html). This codec checks wire structure
and strict UTF-8. Application map-key and tag semantics remain explicit caller
responsibilities, described below.

## Events

| Event | Meaning |
| --- | --- |
| `Unsigned(u64)` | Integer from 0 through 2^64−1 |
| `Negative(u64)` | Argument `n` denotes the exact integer −1−n, through −2^64 |
| `Bytes(View<u8>)` | Definite byte string; bytes are borrowed |
| `Text(View<u8>)` | Definite strictly valid UTF-8 text; bytes are borrowed |
| `Array(u64)` | Open a definite array with that many child items |
| `Map(u64)` | Open a definite map with that many key/value pairs |
| `Tag(u64)` | Open a tag with exactly one child item |
| `Simple(u8)` | Simple values 0–23 or 32–255; 20/21/22/23 mean false/true/null/undefined |
| `Float16(u32)` | Exact 16-bit IEEE representation; the argument must fit 16 bits |
| `Float32(u32)` | Exact 32-bit IEEE representation |
| `Float64(u64)` | Exact 64-bit IEEE representation |
| `BeginBytes`, `BeginText` | Open an indefinite string containing definite chunks of the same string type |
| `BeginArray`, `BeginMap` | Open an indefinite array or map |
| `End` | Close the most recent array, map, tag or indefinite string |

Every opened structure has an explicit `End` event, including definite arrays,
definite maps and tags. For those three forms `End` writes no byte. For an
indefinite form it writes the CBOR break byte. A definite array/map must have
exactly the declared number of items/pairs before its `End`; tags need one
complete child. Indefinite maps need an even number of child items.

For example, `{ "a": [1, true] }` is:

```text
Map(1), Text("a"), Array(2), Unsigned(1), Simple(21), End, End
```

Text in that notation means a caller-backed UTF-8 byte view. An indefinite
text string containing two chunks is:

```text
BeginText, Text("strea"), Text("ming"), End
```

Each text chunk must independently contain complete valid UTF-8 sequences.
A Unicode scalar cannot be split across chunks. Empty chunks are allowed;
nested indefinite strings and wrong-type chunks are rejected. The reader keeps
chunks separate, so callers can process or combine them without an implicit
allocation by the codec.

Floating-point events preserve width and every bit, including negative zero,
subnormals, infinities and NaN signs/payloads. They do not perform arithmetic or
claim native f64 support. `Negative(n)` likewise avoids narrowing values into
signed i64. Tags can carry larger numeric representations using their ordinary
child events; the codec does not silently convert them to a host numeric type.

## Reader

```lanius
pub fn default_limits() -> Limits;
pub fn empty_frame() -> Frame;
pub fn scratch_len(limits: Limits) -> Result<i32, Error>;
pub fn validate(input: View<u8>, frames: View<Frame>, limits: Limits)
    -> Result<i32, Error>;
pub fn reader(input: View<u8>, frames: View<Frame>, limits: Limits)
    -> Result<Reader, Error>;
// Methods:
Reader.next() -> Option<Event>;
Reader.position() -> i32;
```

The actual signatures use `core::slice::View`, `core::result::Result` and
`core::option::Option`. `scratch_len(limits)` returns `limits.max_depth` frame
elements after checking the limits. Initialize frame storage using
`empty_frame()` and provide a view with at least that many elements. Only that
prefix can be changed; extra frame elements are preserved. Previous frame
contents have no meaning, and no heap allocation is required.

`reader` validates one complete item, including nested structure and UTF-8,
before returning a cursor. It rejects trailing bytes and empty input. It
does not expose events from an invalid document. `validate` performs the same
checks and returns the consumed byte count, which equals the complete input
length on success.

`next()` then walks the validated bytes. It synthesizes `End` events for
definite structures and tags, and consumes physical breaks for indefinite
structures. `position()` reports bytes consumed relative to the selected input
view; a synthesized `End` need not advance it. Once exhausted, the cursor
returns `None` repeatedly. Its constructor guarantees that `next()` cannot
encounter a format error when its storage contracts are obeyed.

The input and frame backing must remain live and unchanged except for the
cursor's own scratch writes. **One active cursor owns the use of its scratch.**
Copies alias that backing and cannot be interleaved. Do not call another reader,
validation or encoder with the same frames while a cursor still needs them.
After exhausting or discarding the cursor, frames can be reused. Borrowed byte
and text event views remain usable as long as their input backing does.
Lanius does not enforce these lifetime and immutable-borrow conventions yet.

## Encoder

```lanius
pub fn encoded_len(events: View<Event>, frames: View<Frame>, limits: Limits)
    -> Result<i32, Error>;
pub fn encode_into(events: View<Event>, output: View<u8>,
                   frames: View<Frame>, limits: Limits) -> Result<i32, Error>;
```

An event sequence must contain exactly one complete root item and every
required `End`. `encoded_len` validates the entire sequence, text and limits,
and returns the exact encoded byte count. `encode_into` independently performs
that validation and size pass, checks actual output capacity, then emits the
bytes. It returns the exact number written at `output.start`; surplus output
capacity is preserved. **All returned errors preserve all output bytes.**
Scratch may change on either success or failure.

Events and all string payloads must stay live and unchanged during the call.
Output must be physically disjoint from the event array, string payloads and
scratch. Scratch must be disjoint from every input as well. Read-only string
payload views may overlap each other. Native strided arrays, packed storage
and nonzero view offsets work through ordinary slice indexing. Every view must
have physical storage for its claimed `start + length`; logical metadata checks
cannot establish backing size, lifetime or overlap.

Integer, string-length, array/map-count and tag arguments use their smallest
available header. The reader accepts longer well-formed representations of
those arguments. Floating-point width and bits, indefinite forms, chunk
boundaries and map order are preserved. The codec does not sort keys, collapse
indefinite forms, narrow floats or normalize NaNs. Consequently this is
**not a core-deterministic/canonical CBOR encoder**, nor a claim that every
float uses its preferred shortest representation.

## Map and tag policy

Maps are ordered sequences of key/value events. Keys may have any CBOR type,
including arrays, maps, tags and floats. Duplicate keys are preserved by both
reader and encoder; there is no implicit first-value/last-value policy or host
hash-map conversion. The caller must reject duplicates or define an explicit
application policy before treating an untrusted map as application data.
Duplicate-key maps can be well-formed but are not valid CBOR maps under the
RFC's semantic validity rules. This module supplies the wire events needed to
inspect them; it does not claim to certify their semantic validity.

Tag numbers and child events are preserved without registry lookup, conversion
or tag-specific validity checks. Unknown tags work the same way as known ones.
Applications that use dates, bignums, embedded CBOR or other tagged meanings
must check the tag's required content themselves. Unassigned simple values are
also preserved; reserved simple values 24–31 and their forbidden two-byte
representations are rejected.

## Limits and errors

`Limits` contains:

| Field | Default | Scope |
| --- | ---: | --- |
| `max_input: i32` | 67108864 | Selected encoded input bytes for reader/validation |
| `max_output: i32` | 67108864 | Encoded result bytes for encoder |
| `max_depth: i32` | 128 | Simultaneously open arrays/maps/tags/indefinite strings |
| `max_items: u64` | 1000000 | Item heads, including tags, indefinite starts and string chunks; excludes `End` |
| `max_string_bytes: i32` | 16777216 | One definite string or aggregate chunks of one indefinite string |
| `max_work: u64` | 134217728 | One unit per event, including `End`, plus one per byte/text payload byte |

Signed limits must be nonnegative. A depth limit of zero accepts plain scalar
items, including definite strings, but no open structure. Exactly sufficient
item, byte, work and output limits succeed. The work budget applies separately
to each pass: reader construction validates once and later iteration walks
again; encoding validates/counts then emits. A wire head has at most nine bytes,
so the charged event steps also bound header processing. There is no loop over
a declared array/map count when input or event data is absent; u64 counts do
not overflow by doubling map pairs.

`Error` contains `kind: ErrorKind` and `offset: i32`:

| Kind | Meaning |
| --- | --- |
| `Bounds` | Invalid view metadata or negative signed limit |
| `InputLimit`, `OutputLimit` | Input/result bound, or insufficient actual output capacity |
| `ScratchTooSmall`, `DepthLimit` | Insufficient scratch for configured maximum, or an input opening beyond that maximum |
| `ItemLimit`, `StringLimit`, `WorkLimit` | Respective configured resource bound |
| `UnexpectedEnd` | Incomplete head, payload, structure or event sequence |
| `InvalidHead`, `InvalidSimple` | Reserved or forbidden wire representation |
| `InvalidUtf8` | Invalid complete text string/chunk |
| `UnexpectedBreak`, `ChunkType`, `OddMap` | Invalid structural ending or chunk placement |
| `TrailingData` | Bytes/events after the completed root |
| `InvalidEvent` | Invalid encoder value or an extra child before a required `End` |

Reader errors normally identify the rejected item's head relative to the
selected byte view. Structural EOF errors identify the input end; work charged
to a synthesized `End` identifies the current byte position. UTF-8 errors
identify the text/chunk head, not an offset into its payload. Encoder errors
identify the event index; incomplete sequences and actual-capacity failures use
the event count. Initial metadata, scratch and input-limit failures use offset
zero. Limits may reject an oversized declared string before checking that its
entire payload is present. All parsing failures occur before a public reader
is returned; no partial validity guarantee is inferred from a prefix.

## Executable evidence

`tests/extended_cbor_execution.rs` executes compiled Lanius programs. Its
self-contained references require no downloaded Python packages or network.
Six focused groups exercise:

- All 81 RFC Appendix A examples and additional nonpreferred argument headers.
- 103 malformed cases from Appendix F plus UTF-8 and trailing-item failures,
  including selected exact error offsets.
- 830 generated/boundary trees with all types, arbitrary and duplicate map
  keys, definite/indefinite nesting, chunking, full u64 integers/tags and exact
  float32/64 corner cases. An independent Rust encoder supplies expected bytes;
  logical-event fingerprints also compare decoded values, preventing inverse
  decoder/encoder mistakes from cancelling in a byte round trip.
- Every one of the 65536 float16 bit patterns, preserving exact event values,
  widths and bytes.
- Depth boundaries through 256, rejected deeper nesting, full-u64 incomplete
  container heads and a batch of 100000 scalar items without recursive descent.
- Native strided arrays, selected view windows, output/scratch guards,
  malformed encoder structure/UTF-8, exact resource bounds, error atomicity and
  allocation-failure injection with no allocation or host calls in the pure
  contract program.

The independently generated references are test harnesses. The production codec
is implemented in Lanius and does not use a foreign serializer or a JSON bridge.
The final six-group run passed in 9.11 seconds. Run the focused suite from the
repository root:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_cbor_execution -- --nocapture
```

## Native measurements

Measured on 2026-10-23, AMD Ryzen 9 5950X, Linux x86_64, pinned to CPU 8,
using the existing compiler based on `441e66f9`. One warm run preceded five
measured runs, alternating case order. Parent CPU tests and benchmarks were
idle. Times include process startup, test framing/pipe transport, constructor
validation, event iteration and logical fingerprinting, event-vector growth,
sizing, encoding and final output. Input generation and result checking were
outside the timed interval; compiler startup is excluded.

| Input | Wire bytes | Median ms | Min–max ms |
| --- | ---: | ---: | ---: |
| Array of 100000 integers cycling 0–23 | 100005 | 250.100 | 225.583–288.169 |
| Array containing all 65536 float16 bit patterns | 196613 | 197.198 | 158.614–204.710 |
| Definite byte string with 262139 payload bytes | 262144 | 10.002 | 8.471–10.373 |

Each output exactly matched its input, including float widths and payloads.
These are complete harness measurements, not isolated codec throughput or
comparisons with another compiler/serializer. The harness uses owned vectors
for collected events and output; those allocations are outside the
allocation-free codec's API contract. The pure contract fixture separately
executes with allocation failure injection and records no allocation calls.

The batch fixture uses little-endian u32-length test records and a response
header carrying status, error/consumption offset, result length and logical
fingerprint. It limits individual test records to 256 KiB to bound fixture
storage. This framing is test-only; the public library directly consumes and
produces CBOR bytes, with the configured i32 byte limits above.
