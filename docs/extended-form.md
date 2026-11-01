# Ordered form byte pairs

[`ext::form`](../extended/ext/form.lani) supplies borrowed parsing, component
conversion and streaming serialization for `application/x-www-form-urlencoded`
bytes. [`ext::form_owned`](../extended/ext/form_owned.lani)
adds independent packed storage, checked append and owned output. The
[form plan](library-form-plan.md) defines this increment. All nine library gates
and four application groups/86 native cases pass on the finite native Linux
x86_64 profile. Existing URI, percent and HTTP receipts
do not establish these APIs.

## Format profile

This is the lossless byte layer before the WHATWG form parser's UTF-8 string
conversion. It preserves arbitrary bytes, including NUL and invalid UTF-8.
Checked Text projections reject invalid UTF-8 instead of replacing bytes, and
retain a valid UTF-8 BOM as data. The profile follows the byte operations in the
[WHATWG form parser/serializer](https://url.spec.whatwg.org/#application/x-www-form-urlencoded)
and its [percent decoder](https://url.spec.whatwg.org/#percent-decode). The source
read for this increment is the URL Living Standard marked **19 October 2026**.

Parsing splits on raw `&`, discards empty segments and splits each remaining
segment at its first raw `=`. A missing `=` supplies an empty value. It converts
original `+` bytes to spaces and decodes valid `%HH` triplets once; malformed
percent bytes remain literal. Thus `%2B` becomes a plus byte, while `+` becomes
a space. Neither a decoded ampersand nor a decoded equals sign becomes a field
separator. Order and duplicate names survive.

Serialization emits every pair as `name=value`, joined with `&`. ASCII letters,
digits and `*-._` remain literal; space becomes `+`; every other byte becomes
an uppercase `%HH` escape. Zero pairs produce empty output, while one empty
name/value pair produces `=`. Parse then encode canonicalizes spelling and
separators; it does not reproduce the original wire.

| Encoded input | Decoded ordered pairs | Canonical output |
| --- | --- | --- |
| Empty, or `&&` | No pairs | Empty |
| `a&=x&a=%2b+` | `a`/empty, empty/`x`, `a`/plus then space | `a=&=x&a=%2B+` |
| `x=a=b` | `x`/`a=b` | `x=a%3Db` |
| `x=%2G` | `x`/literal `%2G` | `x=%252G` |
| `x=~*` | `x`/`~*` | `x=%7E*` |
| `x=%00%FF` | `x`/bytes `00 FF` | `x=%00%FF` |

The codec does not remove a leading `?`, split on semicolons, normalize
newlines or interpret `_charset`. Select a URI's query through
[ext::uri](extended-uri.md) before passing that view to this parser. An HTTP
body is already a byte sequence; Content-Type, transport and application
interpretation remain the caller's responsibilities. HTML control collection,
multipart uploads, other character encodings and URL normalization are outside
this module.

[ext::percent](extended-percent.md) keeps its strict RFC 3986 component
contract: literal plus stays plus, space encodes as `%20`, `~` stays literal,
and malformed escapes are errors. Choosing form semantics is explicit.

## Borrowed parsing and components

`ext::form` imports only core modules and allocates no output. Its public data
shapes distinguish decoded fields from encoded spans:

```text
Pair { name:View<u8>, value:View<u8> }
EncodedPair { name:View<u8>, value:View<u8> }
Limits { max_input_bytes:i32, max_pairs:i32,
         max_component_bytes:i32, max_decoded_bytes:i32 }
Parsed { input:View<u8>, pair_count:i32, decoded_bytes:i32 }
```

| API | Contract |
| --- | --- |
| `default_limits()` | 1 MiB input, 65,536 pairs, 1 MiB per decoded component and 1 MiB total decoded bytes |
| `parse(input, limits) -> Result<Parsed,Error>` | Complete admission before publishing borrowed metadata |
| `Parsed.pairs() -> Pairs` | Borrowed cursor yielding raw `EncodedPair` spans in input order |
| `Pairs.borrow()` | Reference to the actual cursor for generic helpers |
| `Iterator<EncodedPair>` | Fused forward traversal; copied cursors fork position over the same immutable input |
| `Pair.name_text()`, `Pair.value_text()` | Checked borrowed Text projections; return `core::text::Error` on invalid UTF-8 |
| `component_encoded_len(input) -> Result<u64,Error>` | Exact form-encoded byte count |
| `component_decoded_len(input) -> Result<i32,Error>` | Exact decoded byte count under the forgiving percent rule |
| `encode_component_into(input, output) -> Result<i32,Error>` | Encode into caller storage, returning bytes written |
| `decode_component_into(input, output) -> Result<i32,Error>` | Decode into caller storage, returning bytes written |

Parse first rejects negative limits, then invalid logical input metadata, then
excess encoded input length without reading bytes. It scans nonempty segments
in order. For each, it checks pair count, decoded name size, decoded value size
and cumulative decoded size, in that order. Empty segments do not consume pair
allowance. A present empty pair still consumes one pair even though it has no
decoded bytes. No partial Parsed value escapes on an error.

Logical starts and lengths must be nonnegative and their sum must fit i32.
These checks do not prove physical backing. Packed bytes, native arrays and
actual positive/negative byte strides retain their own indexing. Input must
remain alive and immutable while Parsed, its cursors or returned spans are used.
Copies of these values alias backing; they do not own it.

Component conversion checks both descriptors, measures the complete selected
input, then checks capacity before writing. Every returned error preserves the
entire destination. Successful conversion writes only its output prefix and
adds no terminator. Disjoint storage is supported. Same-start conversion is
also supported when both views start at the same physical element with the
same stride: encoding writes backward and decoding forward. This includes
positive and negative strides. Other overlap is outside the contract; end
immutable input borrows before in-place mutation.

## Whole-form sizing and streaming

```text
PairSpan { name_start:i32, name_length:i32, value_length:i32 }
PairSource { Views(View<Pair>), Packed(View<u8>,View<PairSpan>) }

encoded_len(source:PairSource) -> Result<u64,Error>
encoding(source:PairSource, max_output:u64) -> Result<Encoding,Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
Encoding: core::io::Read
```

A Packed span's offsets are relative to the selected packed byte view. Value
bytes immediately follow name bytes. The complete name-plus-value range must
fit within that selected byte view; a representable i32 sum alone is not enough.
Spans may select, reorder or share valid immutable ranges. Views uses ordinary
borrowed decoded Pair descriptors. Both
representations feed the same serializer; there is no new callback protocol.

Sizing validates all source and nested field/span metadata before reading
component bytes, then measures an exact u64 wire length with checked arithmetic.
`encoding` performs that complete sizing before checking `max_output`, so
invalid descriptors take precedence over an output quota. Admission allocates
no output storage.

The Read implementation validates destination offset/count before considering
zero requests or EOF. Invalid requests return `core::io::Error::InvalidInput`
and leave cursor and destination unchanged.
A zero request does not progress; a positive valid request returns
`min(request, remaining)` bytes. Exhaustion is permanent and returns zero.
Escape triplets can cross read boundaries. Copying Encoding forks all progress,
including any partial escape, while retaining borrowed source storage.

Keep source arrays, span descriptors and component bytes alive and immutable
through emission. Destination storage must be disjoint from every source and
from the cursor itself; cursor storage must also be disjoint from sources.
These are manual lifetime and aliasing obligations. Generic consumers such as
[resumable copy](stdlib-resumable-copy.md) supply their own provider-call budget;
the encoding cursor itself supplies exact byte progress.

## Errors and bounds

`ext::form::Error` has these variants:

| Error | Meaning |
| --- | --- |
| `InvalidLimits` | A negative configured format limit |
| `Bounds` | Invalid logical view, nested pair or packed-span metadata |
| `InputLimit` | Encoded input exceeds its configured cap |
| `PairLimit` | Too many nonempty field segments or appended pairs |
| `ComponentLimit` | A decoded name or value exceeds its cap |
| `DecodedLimit` | Total decoded name/value bytes exceed the cap |
| `SizeOverflow` | Checked size arithmetic cannot represent its result |
| `Capacity(required: u64)` | Caller destination is too short for the exact output |
| `OutputLimit` | Exact serialization exceeds the output allowance |

Malformed percent spelling is data, so it has no error variant. The byte codec
does not reject invalid UTF-8; only explicit Text projections do. Form limits
bound format bytes and counts, not caller memory outside the selected views,
allocator page rounding, or execution time.

## Owned packed storage

`ext::form_owned` depends on `ext::form` and existing allocation-backed
containers. Its Form keeps one packed byte Vec and one PairSpan Vec:

```text
Limits { max_pairs:i32, max_component_bytes:i32, max_decoded_bytes:i32 }
Error { Format(ext::form::Error), AllocationFailed, CapacityOverflow }
Form { bytes:Vec<u8>, spans:Vec<ext::form::PairSpan>, limits:Limits }
```

| API | Contract |
| --- | --- |
| `new(limits) -> Result<Form,Error>` | Checked empty owner without allocation |
| `parse(input, ext::form::Limits) -> Result<Form,Error>` | Complete borrowed admission, then independent decoded storage |
| `Form.borrow()` | Reference to the actual owner |
| `len()`, `byte_len()` | Pair count and total packed decoded byte count |
| `pair(index) -> Option<ext::form::Pair>` | Borrowed decoded pair, or None outside the logical range |
| `pairs() -> Pairs` | Borrowed decoded cursor implementing Iterator and ExactSizeIterator |
| `as_pairs() -> ext::form::PairSource` | Packed borrowed source for the canonical serializer |
| `try_append(pair) -> Result<i32,Error>` | Append one decoded pair after validation/reservation and return the resulting pair count |
| `clear()` | Discard logical contents and retain storage |
| `destroy()` | Retire both buffers and leave the actual owner reusable |
| `encoding(max_output:u64)` | Borrow the canonical form Encoding |
| `encode(max_output:i32)` | Return an independent ASCII String through the same Encoding |

Owned parse validates the complete input before allocation, reserves exact
decoded-byte and span counts, then decodes. Any failure retires partial owners;
input remains unchanged. Successful storage no longer borrows the encoded input.
Returned pairs and cursors borrow the Form, so keep it alive and stable.
The owned cursor is fused; copies fork position, and `remaining_count()` is the
exact number of pairs left while that backing stays unchanged. Its `borrow()`
method passes the actual cursor to generic helpers.

Append validates both inputs, pair/component/total caps and checked sizes
before reservation. Capped geometric growth supports repeated append. It
reserves bytes before spans, then publishes the new pair only after all
fallible work succeeds. An error preserves logical contents and counts, but
**may change capacities and backing addresses**. End every prior Form borrow,
pair view, cursor and encoding before **every append attempt**, including one
that later fails. Append inputs must not alias the Form's own storage.

Maintain one cleanup authority for both buffers. Shallow copies do not clone
their ownership. End every pair, cursor and encoder borrow before clear or
destroy. Both operations invalidate earlier borrowed contents;
destroy must target the actual owner when it will be reused. No automatic
destruction, lifetime checking or panic cleanup is added.

Owned encode rejects a negative output limit with `Format(InvalidLimits)` before
allocation and preflights
the exact admitted wire. It uses the borrowed Encoding through the existing
alloc::io collector with `ceil(length / 1024) + 1` direct calls, including a real
EOF read even for empty output, and destroys partial collector
failures. Source contents and cleanup authority survive failure. Successful
ASCII String storage is independent and has its own explicit cleanup owner.

## Costs and supported targets

Borrowed parse scans encoded input in linear time with constant auxiliary
storage. Component sizing/conversion is linear in input and emitted bytes;
conversion measures before writing. Whole-form sizing scans pair metadata and
component bytes, while streaming emission uses constant cursor storage and
work linear in emitted bytes. These are algorithmic bounds, not throughput or
wall-time measurements.

Owned parse adds packed decoded-byte and span storage. Appending copies the new
pair and may relocate existing bytes/spans when capped geometric growth reserves
more space. The span count must fit `i32::MAX / size_of<PairSpan>()`; exceeding
the storage limit returns `CapacityOverflow`. Owned encoding adds its separate
String storage and the existing collector's bounded scratch; it shares the
borrowed serializer.

The initial intended runtime target is Linux x86_64 CPU output from the GPU
compiler. Borrowed format operations need no allocator or host service; owned
forms and owned output use existing allocator bindings. Other hosts, GPU device
programs, compiler-enforced lifetimes and formal proofs remain separate.

## Verification status

The [form_select KEY consumer](extended-form-select.md) selects ordered
duplicate fields by an exact raw-byte name, then emits their canonical encoding through fixed copy
scratch. Its input, output and provider-call limits are independent.
Its standalone compiler command and two guide examples pass with exact 30/22
output bytes, status 0 and empty stderr; receipts are
`target/stdlib-work/form-select-cli-build.log` and
`target/stdlib-work/form-select-cli-examples.log`. These checks are separate
from application test cases. The model, admission and limits groups pass
32 + 5 + 10 = 47 native cases in one combined 10.08-second test run after a
1.81-second Rust build, recorded in
`target/stdlib-work/form-select-model-admission-limits.log`. No separate group
timing is inferred from that combined run. The I/O group passes 39 native cases
in 20.98 seconds after a 0.20-second build, recorded in
`target/stdlib-work/form-select-io.log`, including 20 reached allocation denials.
All four application groups therefore pass 86 native cases. The two standalone
examples and six library resource denials remain separate.

The [tiny generic admission](../tests/fixtures/extended_form/README.md) passed
one test in 7.03 seconds after a separate
1.87-second Rust build, recorded in `target/stdlib-work/form-admission.log`.
It executes borrowed parsing/component conversion, owned parse/append and
generic Read canonical output through actual EOF. The accepted source hashes
start `0b7ce72e` (borrowed) and `4b638c41` (owned), with fixture `3abd9f30`.
Both production sources passed independent contract review. The tiny gate
needed no compiler change or newly recorded compiler dependency.

The next direct run passed the ordered/binary/stride/alias contracts and
preflight/Read groups, but its owned fixture failed compilation with LNC0016
because five typed bindings used `Pair>=` instead of `Pair> =`. That mixed run
took 10.57 seconds after a 0.18-second build, recorded in
`target/stdlib-work/form-direct.log`. The correction changes fixture whitespace
only. Its focused retry passed one test in 8.49 seconds after a 0.20-second
build, recorded in `target/stdlib-work/form-owned-direct-revised.log`, at fixture
hash `eb0e8132`. All four direct groups are now accepted across separate runs.
Production sources and compiler are unchanged.

All four [resource gates](../tests/fixtures/extended_form_resources/README.md)
passed on their first native invocation in 15.47 seconds after a 2.06-second
Rust build, recorded in `target/stdlib-work/form-resources.log`. Four baselines
and six separate reached-denial processes check these selected lifecycles:

| Gate | Accepted observations |
| --- | --- |
| Borrowed backing | 256/16,384 pairs, 266,238 complete output bytes, eight matched setup allocations/releases; pure traversal/conversion/emission adds no host effects |
| Owned parse | Two reached buffer denials at mmap 3/4, partial cleanup and same-process recovery to 257 pairs |
| Append | Reached byte/span growth denials at mmap 6/7 preserve 257 logical pairs and recover to 258; a failed later reservation retains the earlier capacity change |
| Owned encode | Reached output denials at mmap 4/12 preserve three source owners and recover 262,143 exact output bytes in the same process |

Every denial reaches a selected site from its successful baseline. These are
finite allocation observations, not an exhaustive collector-allocation campaign.
The accepted production hashes remain unchanged.

The first independent-model attempt stopped during fixture compilation with
LNC0047 in a nested error-payload reporting match: zero passed, one failed in
4.62 seconds after a 1.83-second Rust build (`target/stdlib-work/form-model.log`).
No production runtime failure was observed. The revised producer factors that
match into an explicitly typed helper while retaining its corpus, oracle and
driver. A [confirmed reduction and control](../tests/fixtures/extended_form_model/compiler_dependency/README.md)
and exact reconstruction patch are preserved. The reduced original also fails
compilation with LNC0047 at line 7:77 (exit 1), recorded in
`target/stdlib-work/form-nested-original.log`. The typed-helper control compiles
and executes all six assertions with status 0 and empty output; receipts are
`form-nested-helper-build.log` and `form-nested-helper-runtime.log` under the
same directory. This scoped compiler-admission dependency remains open. It does
not establish a general nested-match limitation or compiler root cause, and is
distinct from the older nested Result/LNC0005 reproduction.

The revised [independent model](../tests/fixtures/extended_form_model/README.md)
passes one test in 9.02 seconds after a 0.22-second Rust build, recorded in
`target/stdlib-work/form-model-revised.log`. The producer changes only the
reporting helper; its corpus, oracle, complete expected bytes and Rust driver
remain unchanged. Seed `0xf04a0261112` produces 607 finite cases over two actual
byte layouts:

| Model observation | Count |
| --- | ---: |
| Parse admissions / rejections | 487 / 70 |
| Successful / rejected appends | 142 / 148 |
| Clears / destroys followed by reuse | 32 / 20 |
| Component conversions | 120 |
| Streaming exercises | 832 |
| Valid reads / invalid reads | 21,889 / 4,160 |
| Copy/reset operations | 3,328 |
| Observed complete pairs | 1,827 |

These observations are actions within the corpus, not additional native
process counts. Twenty host-only corruption controls remain separate from
runtime evidence. The model covers lossless arbitrary bytes, duplicate order,
complete wire output, strict Text projections, Views/Packed parity, cursor
copies and owned logical-state changes; the resource gates own allocation and
physical-lifetime observations.

Thus all nine library groups (four direct, one model, four resource) and four
application groups are accepted across separate runs. Historical percent, URI
and HTTP receipts retain their original scope; this increment does not claim
fresh execution of those old suites. Standalone examples and the minimal
compiler control remain separate from application/model case counts. The
selected form increment is complete; the whole library goal, additional targets,
compiler-enforced ownership and formal verification remain open.
