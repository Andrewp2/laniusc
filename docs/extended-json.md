# JSON documents

`ext::json` parses, builds, queries and encodes owned JSON documents in Lanius.
Import it through the `extended` source root.

## Format policy

The grammar follows [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html).
The input is a valid UTF-8 String. Scalar roots are accepted. Comments, trailing
commas, trailing content, a leading BOM and non-JSON whitespace are rejected.
JSON escapes decode to Unicode scalars, including paired UTF-16 surrogates.
Unpaired surrogates are rejected deliberately: the String representation
requires scalar-valid UTF-8.

Numbers retain their exact source spelling. Parsing does not round through a
floating-point type or reject a large exponent such as `1e400`. Exact i64/u64
queries accept integral decimal/exponent forms and distinguish fractional
values from out-of-range integers. Floating-point conversion remains work.

Object traversal preserves order and duplicate keys. `member` returns the last
matching value. Set `reject_duplicate_keys` to reject duplicates after decoding
escapes; `"a"` and `"\u0061"` are the same key. There is no Unicode normalization.

Encoding emits compact JSON, preserves number spellings and member order,
escapes quotes/backslashes, and spells control scalars as lowercase `\u00xx`.
Other scalars remain UTF-8. Repeated encoding is deterministic; this is not
cryptographic JSON canonicalization.

## Ownership and representation

A Document owns a flat vector of nodes and each node's key/text allocations.
Parsing and encoding are iterative. Destruction walks the flat vector, so
deep nesting does not recurse through the native call stack.

`NodeId` is an integer belonging to one document. IDs stay valid across append
operations and expire when that document is destroyed. An in-range integer
from another document cannot be detected as foreign.

- Parsing borrows the input and copies strings and numbers.
- Builder operations copy keys and text; the caller retains those Strings.
- String, number and key getters return independent owned copies.
- The explicitly named `string_view`, `number_view` and `key_view` getters
  borrow text without allocating. They survive document appends and expire at
  destruction. Keep their backing unchanged, including keys; the compiler does
  not enforce read-only access.
- Failed insertion leaves the existing document unchanged. Failed parsing,
  encoding and copying release partial results and preserve their sources.
- `destroy()` frees all owned allocations and resets this handle. Repeating
  destruction on the reset handle is harmless.
- A plain Document copy aliases its allocations. Keep one active owner.
  Passing a handle by value to a helper that grows it transfers responsibility
  for the updated owner to that helper; the caller must abandon its old copy.
  Prefer `document.borrow()` and a `&Document` parameter for helpers that mutate
  the caller's document.

These are manual lifetime conventions. The compiler does not enforce unique
ownership or immutable String views.

## API

`Kind` is Null, Boolean, Number, Text, Array or Object.

| Operation | Result and behavior |
| --- | --- |
| `new()`, `with_options(options)` | Empty document; the latter returns Result and checks options |
| `parse(input, options)` | `Result<Document, Error>` |
| `encode(document)` | `Result<String, Error>`; an empty document is NoRoot |
| `borrow()` | Reference to this owner, for helper calls |
| `node_count()`, `root()` | Node count and `Option<NodeId>` |
| `kind(id)` | `Result<Kind, Error>` |
| `child_count(id)`, `first_child(id)` | Container count and optional first child |
| `next_sibling(id)` | Optional following sibling; root has none |
| `element(array, index)` | Optional child; past the end is None, negative index is Bounds |
| `member(object, key)` | Optional last matching member |
| `member_text(object, key: Text)` | Same lookup with a borrowed key and no temporary String allocation |
| `boolean(id)` | Boolean value |
| `copy_string(id)`, `copy_number(id)`, `copy_key(id)` | Independently owned String |
| `string_view(id)`, `number_view(id)`, `key_view(id)` | Borrowed Text with the same type requirements as the copying getters |
| `integer_i64(id)`, `integer_u64(id)` | Exact integer value, or WrongKind / NotInteger / NumberOutOfRange |
| `add_null(at)`, `add_bool(at, value)` | Append a leaf, returning `Result<NodeId, Error>` |
| `add_string(at, text)`, `add_number(at, text)` | Append copied text; number text must be one complete JSON number |
| `add_i32(at, value)` | Append an exact signed 32-bit integer |
| `add_array(at)`, `add_object(at)` | Append an empty container |
| `destroy()` | Free and reset this owner |

All query rows except count/root/borrow return Result. Incorrect node types
produce WrongKind and out-of-range IDs produce Bounds. `copy_key` requires
an object member. Placement is `At::Root`, `At::Element(array)` or
`At::Member(object, key)`. A second root or a mismatched parent is
InvalidPlacement. Nodes are appended, so the public builder cannot create cycles.

Indexed array lookup and object lookup scan siblings. Parsing/encoding otherwise
take time proportional to nodes and text bytes. Duplicate rejection scans
earlier members and can take quadratic time for a large object.

## Limits and errors

| Option | Default |
| --- | ---: |
| `max_depth` | 128 |
| `max_nodes` | 1,000,000 |
| `max_string_bytes` | 16,777,216 |
| `max_number_bytes` | 1,048,576 |
| `max_output_bytes` | 67,108,864 |
| `reject_duplicate_keys` | false |

All numeric limits may be zero; negatives are InvalidOptions. Depth counts
containers: a scalar root has depth zero, a root array/object has depth one.
String limits count decoded UTF-8 bytes per key or value. Number limits count
source bytes. Output limits apply during encoding. These limits do not cap the
input allocation or total process memory.

`Error { kind, offset }` identifies syntax errors (UnexpectedEnd, UnexpectedByte,
InvalidEscape, InvalidSurrogate, InvalidNumber, TrailingInput), configured limits
(DepthLimit, NodeLimit, StringLimit, NumberLimit, OutputLimit), DuplicateKey,
AllocationFailed, and the API errors described above.

Parse offsets are zero-based bytes. InvalidNumber identifies the token's start;
InvalidSurrogate identifies the first escape's backslash. DuplicateKey identifies
the duplicate member's value start. EOF errors can equal input length.
Builder/query/encoder errors and invalid options use offset -1. Error priority
when several conditions apply is not specified.

## Execution evidence

On 2026-10-22, all three focused test groups passed on x86_64 Linux with the
GPU compiler built from `441e66f9` and this branch's library changes:

- API construction/query, copies surviving destruction, borrowed mutation
  through growth, exact error offsets, limits and 512 nested containers.
- Normalizer grammar and Unicode cases, 96 deterministic generated trees checked
  against serde_json, large text, numeric spelling, duplicates and idempotence.
- Every allocation after input construction failed in turn in a parse/encode/
  copy/build workload. Syscall traces verify that all successful allocations
  are released. Eight malformed-input paths also check complete cleanup.

The tests execute native Lanius binaries. Rust supplies a reference model and
fault-injection harness. GPU compilation is not evidence of GPU execution of
the resulting program. Other execution targets remain unverified.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_json_execution -- --nocapture

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/json_normalize.lani --stdlib-root stdlib \
  --source-root extended -o /tmp/json-normalize
```

The normalizer reads stdin and writes stdout. Exit status is 0 for success,
2 for invalid text/JSON or document limits, 3 for stream failure, and 4 for
allocation failure. It produces no diagnostic text. A write failure can leave
an output prefix.

Borrowed queries and exact integer conversion have additional execution
evidence in [configuration](extended-config.md), including 64-bit boundaries,
large exponents, allocation-free queries and views surviving node growth.
Conversion accepts `1.25e2` as 125, rejects `1.25` as NotInteger, checks the
destination range and treats negative zero as zero. It does not allocate or
round through floating point; conversion errors have offset -1.

Streaming parsing/encoding, floating-point conversion, further numeric builder
helpers, editing/removal, deep cloning, schema validation and other targets
remain work.
