# Borrowed DER framing and values

[`ext::der`](../extended/ext/der.lani) reads and writes ASN.1 DER framing in
caller storage. It returns borrowed views, allocates nothing and performs no
host I/O. Its purpose is to supply byte boundaries and selected value codecs
for certificate and protocol code.

This module is not a complete DER or X.509 schema validator. A parsed outer
TLV says nothing about the validity of its nested encodings or unknown value
semantics. Callers select typed accessors and explicitly traverse constructed
content. They must enforce schema tags, field order, cardinality, omitted
defaults, SET/SET OF ordering, named-bit rules, algorithm parameters and
certificate policy. Signature verification, name matching, validity/trust
decisions and certificate-path processing belong to the certificate layer.

## Sources and supported domain

The framing/value rules follow [ITU-T X.690 (02/2021)](https://www.itu.int/rec/T-REC-X.690-202102-I/en),
particularly sections 8.1.2, 8.1.3, 8.3, 8.6, 8.19, 10 and 11. The time
helper selects the second-precision forms described in
[RFC 5280 section 4.1.2.5](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.1.2.5),
with the explicit limits below. The implementation is original Lanius.

Tags have a class, a constructed bit and a `u32` number. Canonical headers
use at most eleven octets. Content and total extents use nonnegative `i32`;
arithmetic overflow is an error. Generic framing rejects end-of-contents,
indefinite/reserved lengths, nonminimal headers and truncated values. A high
tag number must fit `u32`; larger ASN.1 tags are outside this API's domain.

There is no implicit recursion or tree walk. One reader step inspects a
bounded header and skips its content by the checked length. Typed scans and
TLV writes take linear work in their supplied views. Certificate callers
must bound input size, nesting and aggregate work for their own traversal.

## Framing API

```lanius
enum Class { Universal, Application, Context, Private }
struct Tag { class: Class, constructed: bool, number: u32 }
struct Element { tag: Tag, encoded: View<u8>, content: View<u8> }

reader(input: View<u8>) -> Result<Reader, Error>
parse_one(input: View<u8>) -> Result<Element, Error>

Reader.borrow() -> &Reader
Reader.position() -> i32
Reader.remaining() -> i32
Reader.next() -> Result<Option<Element>, Error>
Reader.finish() -> Result<i32, Error>

Tag.matches(class: Class, constructed: bool, number: u32) -> bool
Element.children() -> Result<Reader, Error>
Element.as_sequence() -> Result<Reader, Error>
Element.as_set() -> Result<Reader, Error>
```

`reader` validates view metadata; it does not preparse the input. Each
successful `next` consumes one complete TLV and returns its exact encoding
and content as views into the original backing. A failed step leaves the
position unchanged; repeating it returns the same error if backing and state
remain unchanged. Actual end of input returns `Ok(None)` repeatedly.
`finish` succeeds only at that end, returning the consumed length; remaining
bytes yield `TrailingData`. It neither parses nor consumes them.

`parse_one` requires exactly one complete outer TLV. Empty input fails and
trailing bytes fail, even if those bytes form another valid TLV. A reader
instead permits a sequence of adjacent TLVs. `children` requires a constructed
tag; `as_sequence` and `as_set` additionally require the corresponding
universal tag. None of these calls validates child encodings, ordering or
field semantics before the returned cursor is used.

## Borrowing, layout and errors

All views use logical `u8` indices. Packed and strided slices and nonzero
starts have the same wire meaning. Metadata must have nonnegative start and
length and a nonoverflowing sum. The caller must provide physical backing
for the claimed extent; a slice descriptor cannot prove that storage exists.

Keep backing alive while any element, reader, OID, bit string or returned
Text refers to it. No owner is retained or released. Copying a reader or OID
arc cursor copies its position and state; their future progress is independent
while their bytes remain shared. Copying an element copies borrowed views.
Caller mutation between operations is visible through those views and can
invalidate earlier validation; mutation during an operation is unsupported.
Returned `Text` retains the existing `core::text` immutable-backing contract.
Create cursors through factories and preserve their state invariants rather
than editing their fields.

`Error` contains `kind: ErrorKind` and `offset: i32`:

| Operation | Offset origin |
| --- | --- |
| Reader construction and view-metadata failures | Zero |
| `parse_one`, `Reader.next`, `Reader.finish` | The beginning of that reader's logical input |
| Typed `Element` accessors, including child-factory errors | The beginning of `Element.content` |
| `Oid.arcs`, `OidArcs.next` | The beginning of the OID content |
| Writers | The beginning of value input; zero for metadata, tag, size and capacity errors |

Nested readers start at zero in their own content. To locate a nested error
in a retained root view sharing the same backing, add
`nested_input.start - root_input.start` to its offset. For a typed accessor,
add `element.content.start - root_input.start`. These differences count
logical elements, not physical addresses or a guessed native byte stride.

Error kinds are `Bounds`, `UnexpectedEnd`, `InvalidTag`, `TagOverflow`,
`InvalidLength`, `LengthOverflow`, `IndefiniteLength`, `NonCanonical`,
`TrailingData`, `UnexpectedTag`, `InvalidValue`, `IntegerOverflow`,
`ArcOverflow` and `OutputTooSmall`. Truncation points at the available input
end. Header/value failures otherwise identify the offending octet or the
start of a value whose whole shape is invalid. Metadata is checked before
reading; typed helpers then check the requested tag before its value rules.

## Typed values

| Accessor | Result and contract |
| --- | --- |
| `as_boolean()` | `Result<bool, Error>`; one canonical false/true octet |
| `as_integer()` | `Result<View<u8>, Error>`; arbitrary-length minimal signed two's-complement bytes, including negative values |
| `as_i64()`, `as_u64()` | Checked mathematical conversion of that integer; a negative unsigned conversion or out-of-range magnitude yields `IntegerOverflow` |
| `as_bit_string()` | `Result<BitString, Error>` with borrowed `bytes` excluding its unused-bit count, and `unused_bits: u8`; validates count, empty form and zero padding |
| `as_octets()` | `Result<View<u8>, Error>` |
| `as_null()` | `Result<i32, Error>` returning zero for empty content |
| `as_oid()` | `Result<Oid, Error>` with borrowed `bytes`; validates nonempty minimal, terminated base-128 groups |
| `as_utf8()` | `Result<core::text::Text, Error>` with strict UTF-8 validation |
| `as_printable()` | `Result<View<u8>, Error>` restricted to the PrintableString alphabet |
| `as_ia5()` | `Result<View<u8>, Error>` accepting all 7-bit codes, including NUL; application text policy is separate |
| `as_x509_time()` | `Result<X509Time, Error>`; fields `year`, `month`, `day`, `hour`, `minute`, `second` |

These accessors require their universal primitive tag. Constructed string
forms fail the typed accessor even when generic framing succeeds. BIT STRING
validation does not infer a schema's named-bit length or remove trailing
zero-valued bits.

`Oid.arcs() -> Result<OidArcs, Error>` creates an arc cursor with `borrow`,
`position` and `next() -> Result<Option<u64>, Error>`. OID validation permits
arbitrarily large minimal subidentifiers; `next` reports `ArcOverflow` only
when a requested mathematical arc cannot fit `u64`. It leaves its state
unchanged on that error. The first two arcs are unpacked without restricting
their combined encoding to `u64`: `2.u64MAX` is supported despite its combined
subidentifier exceeding that range by 80. The first step consumes that group
and returns the root arc; the second returns the pending second arc without
moving its byte position. EOF is fused, and copies preserve pending state.

`as_x509_time` accepts exactly `YYMMDDHHMMSSZ` or `YYYYMMDDHHMMSSZ`, validates
Gregorian dates and returns years 1 through 9999, hours 00 through 23 and
minutes/seconds 00 through 59. UTCTime maps 50..99 to 1950..1999 and 00..49 to
2000..2049. Leap-second forms require separate caller policy and fail this
helper. It does not enforce a certificate issuer's choice of time tag by
year, compare times or consult a clock. Canonical fractional GeneralizedTime
can be valid DER while outside this helper's selected profile; raw content
remains available for a different decoder.

## Canonical writers

```lanius
header_len(tag: Tag, length: i32) -> Result<i32, Error>
encoded_len(tag: Tag, length: i32) -> Result<i32, Error>
write_header(tag: Tag, length: i32, output: View<u8>) -> Result<i32, Error>
write_tlv(tag: Tag, content: View<u8>, output: View<u8>) -> Result<i32, Error>
write_boolean(value: bool, output: View<u8>) -> Result<i32, Error>
write_integer(content: View<u8>, output: View<u8>) -> Result<i32, Error>
write_i64(value: i64, output: View<u8>) -> Result<i32, Error>
write_u64(value: u64, output: View<u8>) -> Result<i32, Error>
```

`header_len` measures only the header, even when header plus content would
exceed `i32`. `encoded_len` checks that total. `write_header` writes just the
header; `write_tlv` writes header and content and returns their total length.
Generic writers canonicalize framing, with value/schema validity left to the
caller. Integer and boolean writers additionally validate or construct their
canonical primitive value encodings. The arbitrary-integer writer accepts
the same borrowed signed representation returned by `as_integer`.

Every writer checks metadata, its value rules, arithmetic and destination
capacity before its first destination store. On any error the complete
destination backing is unchanged. On success only the returned prefix is
written; the rest remains unchanged. Output backing must be disjoint from
all supplied value/input backing, including logically separate views into
one physical allocation. Aliasing is a caller precondition, not a runtime
overlap detector. No writer allocates temporary heap storage or retains its
arguments.

## Verification status

Source and public signatures are frozen for admission. Native execution has
not yet been accepted for this module. Root owns GPU compilation and runtime
gates; this guide makes no current target-support or performance claim.

[`extended_der_execution.rs`](../tests/extended_der_execution.rs) prepares
three focused tests:

- An isolated ordinary consumer unwraps canonical integer writes and borrowed
  cursor reads without projecting either error type.
- A fixed binary protocol compares framing, checked integers/OID arcs, typed
  values and complete writer bytes against independent Python integers,
  codecs and calendar checks. It exercises packed/strided views, nonzero
  starts, surrounding guards, immutable sources, unchanged output on error,
  repeated cursor failures, EOF, nested relative offsets and retained copies.
  Boundary coverage includes `u32MAX` tags, `i32MAX` header lengths,
  `2.u64MAX` OIDs, larger borrowed integers/arcs and nonminimal encodings.
- OpenSSL generates and signs an actual Ed25519 certificate using the public
  RFC 8032 test-1 seed in a test-only PKCS#8 key. A separate structural oracle
  checks version, serial 128, algorithm OIDs, fixed public key, names and
  signature lengths, then supplies actual complete certificate encodings and
  nested values to the same Lanius fixture. This does not claim certificate
  validation by `ext::der`.

The driver checks strict x86_64 ELF output, bounds every process, and traces
native allocation syscalls. The OpenSSL/Python setup itself is outside that
allocation trace. No production Python, OpenSSL backend, JSON transport or
new package dependency is involved. Fixture sources live under
[`tests/fixtures/extended/der`](../tests/fixtures/extended/der/).
