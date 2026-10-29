# Ordered form byte pairs

The full standard/extended-library goal remains open. At `b6ab0b12`, URI
queries and HTTP bodies are opaque encoded bytes. `ext::percent` deliberately
implements strict RFC 3986 component escaping; it cannot express form parsing
or ordered duplicate fields. This increment adds that missing format layer.

## Format and scope

Use the byte-processing rules of the WHATWG URL Standard
[form parser and serializer](https://url.spec.whatwg.org/#application/x-www-form-urlencoded)
and [percent decoder](https://url.spec.whatwg.org/#percent-decode).
Split on raw `&`, discard empty segments, and split each remaining segment at
its first raw `=`. Missing `=` means an empty value. Decode original `+` bytes
as spaces and valid percent triplets once; malformed percent bytes remain
literal. Preserve pair order, duplicates, empty names/values and arbitrary
decoded bytes. Do not strip a leading `?`, split on semicolons, normalize
newlines or interpret `_charset`.

Serialize every pair as name, `=`, value, with `&` between pairs. Literal bytes
are ASCII alphanumerics and `*-._`; space becomes `+`, and other bytes use
uppercase `%HH`. Zero pairs encode to empty output; one empty pair encodes to
`=`. Parsing then encoding canonicalizes spelling; it does not preserve the
original separators or escapes.

This is the lossless byte layer before WHATWG's UTF-8 replacement conversion.
Checked Text projections reject invalid UTF-8 without replacing bytes or
stripping a BOM. HTML control collection, multipart/file uploads, other
charsets, URL normalization and HTTP transport remain separate responsibilities.

## Borrowed format module

`extended/ext/form.lani` imports only core modules. Public shapes:

```text
Pair { name:View<u8>, value:View<u8> }                // decoded bytes
EncodedPair { name:View<u8>, value:View<u8> }         // raw encoded spans
PairSpan { name_start:i32, name_length:i32, value_length:i32 }
PairSource { Views(View<Pair>), Packed(View<u8>,View<PairSpan>) }
Limits { max_input_bytes:i32, max_pairs:i32,
         max_component_bytes:i32, max_decoded_bytes:i32 }
Error { InvalidLimits, Bounds, InputLimit, PairLimit, ComponentLimit,
        DecodedLimit, SizeOverflow, Capacity(u64), OutputLimit }
```

PairSpan offsets are relative to the selected packed byte view; value bytes
immediately follow name bytes. Packed spans may select, reorder and share
valid immutable ranges. Each complete name/value span must fit inside the
selected packed byte view, not merely have a representable endpoint.
PairSource is a concrete borrowed representation;
there is no new callback protocol or second encoder implementation.

```text
default_limits() -> Limits
parse(input:View<u8>, limits:Limits) -> Result<Parsed,Error>
Parsed { input:View<u8>, pair_count:i32, decoded_bytes:i32 }
Parsed.pairs() -> Pairs
Pairs.borrow() -> &Pairs
Pairs: Iterator<EncodedPair>
Pair.name_text() / Pair.value_text() -> Result<Text,core::text::Error>
component_encoded_len(input:View<u8>) -> Result<u64,Error>
component_decoded_len(input:View<u8>) -> Result<i32,Error>
encode_component_into(input:View<u8>, output:View<u8>) -> Result<i32,Error>
decode_component_into(input:View<u8>, output:View<u8>) -> Result<i32,Error>
encoded_len(source:PairSource) -> Result<u64,Error>
encoding(source:PairSource, max_output:u64) -> Result<Encoding,Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
Encoding: core::io::Read
```

Defaults are 1 MiB input, 65,536 pairs, 1 MiB per decoded component and
1 MiB total decoded bytes. Parse first rejects negative limits, then invalid
logical View metadata, then excess encoded input without reading its bytes.
It scans nonempty segments in order: pair count, decoded name limit, decoded
value limit, then cumulative decoded limit. Complete preflight precedes
publication of Parsed; its cursor is fused and copies fork position while
borrowing the same immutable input. Empty segments do not count as pairs.
Offsets and lengths must be nonnegative and have a representable i32 sum.
As with existing View APIs, these checks do not prove physical backing.

Component output validates both descriptors, measures the entire selected
input, then checks capacity before any write. Every error leaves output
unchanged. Backward encoding and forward decoding support identical physical
start with identical stride, plus disjoint storage; other overlaps are outside
the contract. Same-start support applies to actual positive and negative byte
strides. End existing immutable input borrows before in-place mutation.

Whole-form sizing validates all source and field/span metadata before reading
component bytes, then measures the exact u64 length with checked arithmetic.
Encoding performs that full sizing before applying max_output. One private
component byte generator supplies form emission; no output allocation occurs.
Read validates offset/count before zero/EOF, leaves cursor/destination unchanged
on invalid requests, returns min(request,remaining) for positive requests and
returns permanent zero at exhaustion. Escape fragments may cross reads. Copies
fork all progress. Source arrays, spans and bytes must remain alive/immutable;
destination and cursor storage must be disjoint from them and each other.

## Owned storage module

`extended/ext/form_owned.lani` imports ext::form and existing alloc modules:

```text
Limits { max_pairs:i32, max_component_bytes:i32, max_decoded_bytes:i32 }
Error { Format(ext::form::Error), AllocationFailed, CapacityOverflow }
Form { bytes:Vec<u8>, spans:Vec<ext::form::PairSpan>, limits:Limits }
new(limits:Limits) -> Result<Form,Error>
parse(input:View<u8>, limits:ext::form::Limits) -> Result<Form,Error>
Form.borrow(), len(), byte_len(), pair(index)->Option<ext::form::Pair>
Form.pairs() -> Pairs
Pairs.borrow(), Iterator<ext::form::Pair>, ExactSizeIterator<ext::form::Pair>
Form.as_pairs() -> ext::form::PairSource
Form.try_append(pair:ext::form::Pair) -> Result<i32,Error>
Form.clear(), Form.destroy()
Form.encoding(max_output:u64) -> Result<ext::form::Encoding,ext::form::Error>
Form.encode(max_output:i32) -> Result<alloc::string::String,Error>
```

Owned parse completes borrowed admission before allocating, reserves exact
decoded-byte and span counts, then decodes into independent packed storage.
Any error destroys partial owners; source remains unchanged. Append validates
both inputs, pair/component/total limits and checked sizes before reserving.
Use capped geometric growth for repeated append. Reserve bytes then spans,
then publish the pair only after all fallible work succeeds. On error, logical
contents/counts remain unchanged; capacities/backing may change. End all prior
borrows before every append attempt; success returns the resulting pair count.
Append inputs must not borrow this Form's
own storage. Parsed bytes and spans have one cleanup owner; shallow copies
create no new cleanup authority. Clear retains storage; destroy retires both
buffers and leaves the original owner reusable. No automatic lifetime or panic
cleanup is added. End every borrowed pair, cursor and encoder before clear or
destroy as well as before append.

Owned encode uses the canonical borrowed Encoding and alloc::io collector,
with exact admitted bytes and enough direct reads for full chunks plus real
EOF. Reject negative owned-output limits before allocation. Destroy partial
collector failures, preserve the source on failure, and return independent
ASCII String storage on success. Do not duplicate the wire serializer.

## Real consumer and verification

`form_select KEY` accepts exactly one raw argv key, at most 4,096 bytes; empty
and non-UTF8 keys are valid, option-looking keys are literal, and argv cannot
represent NUL. Read at most 1 MiB raw stdin with 16,384 actual read attempts.
Parse the complete input with 65,536 pairs and 1 MiB component/decoded limits.
Build one Vec<Pair> of matching borrowed decoded fields, preserving order and
duplicates, then use PairSource::Views and one Encoding/Copier. This keeps one
global copy budget without per-field streams or an output String.

Preflight selected canonical output to an independently reachable 1 MiB cap
before stdout. No matches succeed with empty output. No final newline is added.
Use fixed 1,024-byte copy scratch, a global 131,072 provider-call allowance,
real EOF and explicit SIGPIPE ignore. Retry Interrupted within the budget;
other I/O failures preserve confirmed prefixes. Quiet statuses: 0 success,
2 arguments/limits, 3 I/O/setup, 4 allocation. Keep parsed storage and matching
views alive through output; retire selected descriptors, Form, input and argv
owners exactly once on ordinary terminal paths. No URI CLI mode is needed;
a direct library test composes an existing URI query view with form parsing.

Eight owners cover borrowed implementation, owned implementation, direct
tests, independent model, resource/fault tests, real program/tests, docs and
independent review. Direct gates include actual byte strides, permitted aliases,
unchanged failed outputs, malformed percent, all byte values and Read state.
The independent oracle uses distinct byte split/unquote/quote operations and
complete expected wires; resource gates test real owners, selected reached OOMs
and same-process recovery. Application cases cover exact bytes, reachable caps,
I/O progress, allocation failures and cleanup. Start with one tiny executable
admission before expanding verification.

Root alone runs compiler/Cargo/native commands serially under
`target/stdlib-work/library-gpu.lock`, with each outer command limited to
100 seconds. No broad GPU/performance reruns. Preserve root README, AI_POLICY,
CONTRIBUTING, protected std::vec/core::mem and tests/common. Compiler/IR/ABI/
extractor/proof changes are outside this increment; missing support gets a
minimal reproduction. Initial runtime evidence is Linux x86_64 CPU output
from the GPU compiler, not user-program device execution or formal verification.

## Accepted increment

The two form modules and `form_select` now execute on Linux x86_64 CPU output
from the GPU compiler. Nine library test groups and four application groups
passed. The production sources stayed unchanged through these final runs.

| Gate | Accepted result | Local receipt |
| --- | --- | --- |
| Tiny admission | 1 test, 7.03 s; separate Rust build 1.87 s | `target/stdlib-work/form-admission.log` |
| Borrowed contracts and preflight | 2 tests passed in the initial direct run; its third fixture failed compilation | `target/stdlib-work/form-direct.log` |
| Owned direct composition | Corrected fixture passed, 8.49 s; build 0.20 s | `target/stdlib-work/form-owned-direct-revised.log` |
| Independent operation model | 607 cases, 9.02 s; build 0.22 s | `target/stdlib-work/form-model-revised.log` |
| Allocation and resource contracts | 4 groups, 4 baselines and 6 selected reached denial/recovery executions, 15.47 s; build 2.06 s | `target/stdlib-work/form-resources.log` |
| Selector model, admission and limits | 47 cases in one combined 10.08 s run; build 1.81 s | `target/stdlib-work/form-select-model-admission-limits.log` |
| Selector I/O and allocation faults | 39 cases including 20 reached allocation denials, 20.98 s; build 0.20 s | `target/stdlib-work/form-select-io.log` |

The independent model compares complete ordered pairs and canonical wires,
including 142 successful and 148 rejected appends, 32 clears, 20 destroys,
120 component calls, 832 streams, 21,889 valid reads, 3,328 cursor copies/resets
and 4,160 invalid reads. Its fixed seed is `0xf04a0261112`; the oracle's 20
corruption/semantic mutation controls are host checks, separate from native
cases. Direct tests cover actual positive and negative strides, permitted
same-start aliases, unchanged output on errors, checked Text and URI
composition. Resource tests verify full allocation identities/extents, partial
cleanup, retained logical contents and same-process recovery at selected
reached failures; they do not claim exhaustive allocation failure coverage.

All 86 application cases use the real selector. Two standalone CLI examples
also passed with exact 30- and 22-byte outputs, exit 0 and empty stderr, in
`target/stdlib-work/form-select-cli-build.log` and
`target/stdlib-work/form-select-cli-examples.log`. These examples are separate
from the application case count. See the
[module guide](extended-form.md), [consumer guide](extended-form-select.md)
and linked fixture receipts for the commands and precise coverage.

Two initial failures remain documented. A direct fixture needed five spaces
between generic closing brackets and `=` so they did not form `>=`; that was
a fixture syntax correction. The original model's nested match over imported
error enums failed compiler admission with `LNC0047`. The
[small reproduction and typed-helper control](../tests/fixtures/extended_form_model/compiler_dependency/README.md)
confirm the rejection and an equivalent executable helper. The revised model
preserves the corpus and full-width payload checks. This is a remaining compiler
dependency, not an accepted negative test requiring rejection of valid source.
No compiler source changed.

The broader standard-library goal remains open. Other runtime targets, GPU
device execution, compiler-enforced ownership and formal proofs are not
established by this increment. Existing human-maintained root documents and
the protected implementation/test files remain unchanged.
