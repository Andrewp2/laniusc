# Resumable TOML serialization

The [streaming increment](library-toml-streaming-plan.md) gives `ext::toml` a
borrowed byte reader and one shared serializer for sizing, owned output and
caller-buffer output. It also migrates the existing
[normalizer](extended-toml-normalize.md) to fixed output scratch. All five
library groups and all four normalizer groups/64 native cases pass on Linux
x86_64 CPU output from the GPU compiler.

## API and bytes

```text
Document.encoded_len() -> Result<u64, Error>
Document.encoding() -> Result<Encoding, Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
Encoding: core::io::Read
encode(document:Document) -> Result<alloc::string::String, Error>
encode_into(document:Document, output:View<u8>) -> Result<i32, Error>
```

`Document.encoded_len()` replaces the former free `measure` function. It returns
the exact admitted output length without allocation. `encoding()` preflights
the same bytes and reserves the work for a fresh emission pass before returning
the reader. A live empty document has zero output; a destroyed document rejects
with `Bounds` at admission. The configured i32 output cap still bounds the u64
length. Serializer errors use offset -1; output and work admission report
`OutputLimit` and `WorkLimit` according to the ordering below.

All paths preserve the [existing TOML normal form](extended-toml.md#encoding):
quoted root keys, `=`, values and LF; nested inline containers; insertion order;
canonical stored numbers and signed zero. Temporal spelling uses uppercase
`T`/`Z`, inserts omitted seconds, trims fractional trailing zeros without
rounding, maps known `+00:00` to `Z` and preserves unknown `-00:00`. Strings
retain Unicode scalar content through the existing escaping policy. Source
comments, spacing and delimiter/header choices are not retained.

The [TOML 1.1 specification](https://toml.io/en/v1.1.0) defines the format and
value types. This library's deterministic spelling and ordering policy remains
distinct from a semantic-equivalence or cryptographic canonicalization API.

## Work accounting

One serializer traversal costs:

```text
W = emitted bytes + nonroot node visits
    + scanned fraction digits + trimmed trailing-zero digits
```

The byte machine follows the document's parent/first-child/next-sibling links.
It retains structural, escape, UTF-8 and temporal progress in constant storage,
without a depth stack or native recursion. A temporal fraction is scanned and
trimmed once per traversal. Small reads never regenerate earlier output.

| Operation | Admission against `max_work` |
| --- | --- |
| `Document.encoded_len()` | `W` |
| `Document.encoding()` | `2W`, covering preflight and emission |
| Owned `encode` | `2W` |
| Caller-buffer `encode_into` | `2W` |

This deliberately changes the earlier policy at `e9d1c8df`: owned `encode`
admitted `W`, while `encode_into` admitted `2W + output_bytes`. The new direct
fill removes that final whole-output copy. The measurement query remains one
pass. Callers with tight budgets must account for these new thresholds.

Within preflight, the first exhausted bound in generator order wins. Each
emitted byte checks its output cap before charging byte work; node and fraction
work is charged where encountered. If both caps are insufficient, the selected
error can differ from the earlier scalar/raw-chunk checks. There is no
whole-pass output-cap precedence over work exhaustion.

The bound counts serializer work, not allocator/collector operations, provider
calls or elapsed time. Parsing retains its own separate budget. One small
read can trigger a complete bounded fraction scan, so `max_work` is not a
per-read latency promise. Each independently constructed or copied reader has
its own progress and replay allowance; copies do not share a cumulative work
meter. The budget is not a process-wide allowance across cursors.

## Read contract and borrowing

Read checks the complete logical destination range before zero-count or EOF
handling. Negative or overflowing offset/count returns
`core::io::Error::InvalidInput` without changing state or destination. A valid
zero request is inert. A positive request returns exactly
`min(request, remaining)` bytes. EOF is fused and returns zero thereafter.

Escapes and multibyte UTF-8 may cross read boundaries; an individual chunk need
not be valid TOML or UTF-8. Concatenating acknowledged chunks gives the admitted
normal form. After admission, emission has no TOML, output-cap or work-limit
failure. It allocates nothing. Consumers requiring EOF must make a real
positive request and observe zero, even after `remaining()` reaches zero.

Copies fork the complete cursor position, including partial tokens, while
sharing one immutable Document. Keep the Document owner, nodes, options and
every key/value backing alive and unchanged until all copies finish. Destinations
must be disjoint from both the cursor and document backing; cursor storage must
also be separate from document backing. These are manual lifetime/alias rules.
Logical checks do not prove physical storage, and valid Document/String
invariants remain preconditions. No forged-tree or cyclic-link validator is
introduced.

## Caller-buffer and owned output

`encode_into` uses this order:

1. Validate logical output metadata.
2. Run semantic/output preflight and measure the complete wire bytes and work.
3. Check caller capacity; insufficient space returns `OutputLimit`.
4. Reserve replay work within the same `max_work` bound.
5. Fill the admitted prefix directly, with no temporary output allocation.

Every returned error leaves the complete destination unchanged. Success changes
only the returned prefix. Destination backing must satisfy the same disjointness
and lifetime obligations as a reader destination. This is caller-memory
atomicity; a stream writer can publish a prefix before a later host failure.

Owned `encode` admits the same reader and collects it through
[`alloc::io::read_to_string`](stdlib-owned-input.md), using the exact length
and `ceil(length / 1024) + 1` calls. The final call permits the collector's EOF
probe. The collector adopts its Vec as String, avoiding a second whole-output
copy. Empty output allocates nothing. Allocation failure destroys any retained
partial output and leaves all source owners unchanged; a successful String
has one independent cleanup authority. For a valid admitted reader over an
unchanged document, allocation failure is the only later collector failure;
the exact byte/call limits admit the complete stream and its EOF probe.

## Status and dependencies

The first native admission passes: one test in 7.27 seconds after a separate
1.16-second Rust build, recorded in
`target/stdlib-work/toml-streaming-admission.log`. On TOML source `42c8aa81…`,
it verifies the exact 34-byte output and 11 matched allocations/releases, then
checks the independent owned output after Document destruction. Compilation
takes 7.251007 seconds and the traced native process takes 0.013950 seconds;
these are separate observations, not isolated serialization benchmarks.

The other four library groups pass on that unchanged source:

| Group | Executable evidence | Test time / separate Rust build |
| --- | --- | --- |
| Reader/caller-buffer contracts | Nine owner cycles, ten pure phases, exact cursor/range/work/capacity behavior and 54 matched allocations/releases | 7.67 s / 0.19 s |
| Borrowed resources | 4 KiB and 256 KiB payloads; all 765,644 output bytes compared; 99 pure phases without host effects; 54 matched allocations/releases | 8.00 s / 0.21 s |
| Owned collection | One baseline plus two reached output-allocation denials, preserving eight Document owners and recovering all 376,883 bytes in the same process | 9.61 s / 0.18 s |
| Independent state model | 280 cases across two layouts; 8,527 reads, 2,894 cursor copies, 1,275 invalid requests, 975 zero requests and 1,733 EOF observations | 7.49 s / 1.07 s |

The logs are `toml-streaming-contracts-rerun.log`,
`toml-streaming-borrowed.log` and `toml-streaming-owned.log` under
`target/stdlib-work`. Owned denials at mmap 29/site 0 and mmap 38/site 9
observe 38 and 47 successful allocations with exact releases; the baseline
has 38. These are selected initial/final collector reservations, not a
parser-wide allocation campaign. The
[fixture guide](../tests/fixtures/extended_library/toml_streaming/README.md)
records source hashes, complete ledgers and separate native/compilation timings.
The [independent model](../tests/fixtures/toml_streaming_model/README.md) records
263 successful measurements, 255 admitted readers, 13 output-limit and 12
work-limit rejections, and 16,410 admitted wire bytes at seed `0x70a10261117`.
Its log is `target/stdlib-work/toml-streaming-model.log`. Nineteen host-only
observer corruption controls are separate from those native cases.

The first direct-contract attempt failed compilation with LNC0027 in a generic
chained `read(...).unwrap()` helper. An explicit Result import and typed
intermediate admitted the same assertions; these two changes do not isolate
the cause. This remains an inference/import dependency in the fixture helper,
without a demonstrated serializer runtime defect or compiler repair. Its
[failure record](../tests/fixtures/extended_library/toml_streaming/README.md#initial-contract-compile-failure)
preserves that scope.

The migrated [normalizer](extended-toml-normalize.md#current-execution-status)
passes four groups/64 native cases: 14 exact-wire/storage, eight limits,
40 I/O cases including 25 reached allocation denials, and two call-budget
cases. Those application denials are separate from the two owned-collector
denials above. The selectors compile and execute the real program; the guide's
shell examples have expected output but no separate execution receipt.

Three selected existing regressions pass separately: public TOML query/
ownership/atomic-output contracts in 6.80 seconds (Rust build 0.19 seconds),
normalizer configurations/TOML 1.1/types/idempotence in 7.31 seconds (build
1.13 seconds), and malformed/resource-before-output behavior in 7.01 seconds
(build 0.18 seconds). Their logs are `toml-streaming-old-contracts-rerun.log`,
`toml-streaming-app-regression.log` and `toml-streaming-app-errors.log`.
The first old-contract attempt rejected an unsupported fixture `else if`
before execution (3.55 seconds, build 1.28 seconds); nesting ordinary `else`
blocks admitted the retry. Production was unchanged.
Historical TOML parser/encoder and consumer receipts keep their original source
and operation scope. The initial target is Linux x86_64 CPU output from the GPU
compiler, with no user-program GPU claim.

The implementation uses existing document links, String/Vec ownership, Read,
collector and Copier contracts. Borrowed serialization needs no host codec or
new allocator service. Enforced lifetimes, other targets and whole-library
formal verification remain separate; the broader library goal stays open.
