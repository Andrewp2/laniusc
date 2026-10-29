# Borrowed JSON byte encoding

The [stream-encoding increment](library-stream-encoding-plan.md) adds an exact
encoded-length query and a borrowed `ext::json::Encoding` that implements
canonical `core::io::Read`. Owned `encode` uses the same byte generator and
the existing bounded String collector. All four JSON library gates and all
four normalizer groups/100 native cases pass. The standalone build and both
exact guide examples also pass. The [earlier JSON receipts](extended-json.md#execution-evidence)
retain their original source and application scope.

## API and preflight

```text
Document.encoded_len() -> Result<u64,Error>
Document.encoding() -> Result<Encoding,Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
Encoding: core::io::Read
encode(document:Document) -> Result<alloc::string::String,Error>
```

`encoded_len()` runs the byte generator through the configured output cap and
returns the exact admitted length. `encoding()` performs the same preflight,
then starts a fresh machine with that remaining count. Empty documents return
`NoRoot`; exceeding `max_output_bytes` returns `OutputLimit`. Both errors use
offset -1 and precede output allocation or provider effects.

The machine follows first-child, next-sibling and parent links, retaining only
structural phase, token position and small escape progress. It allocates no
depth stack and uses no native recursion. Every edge is visited a constant
number of times; each preflight or complete emission pass takes linear work
in nodes plus output bytes. It does not restart from the root for each read
or rescan previously emitted prefixes.

## Bytes and read boundaries

Encoding preserves the existing [JSON policy](extended-json.md): compact
bytes, exact source number spelling, member order and duplicate keys. Quotes
and backslashes are escaped; control scalars use lowercase `\u00xx`; other
scalars retain their UTF-8 bytes. No BOM or newline is added. There is no
normalization or cryptographic canonicalization.

JSON string escaping, UTF-8 interchange and generator conformance are defined
by [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259.html#section-7),
[§8.1](https://www.rfc-editor.org/rfc/rfc8259.html#section-8.1) and
[§10](https://www.rfc-editor.org/rfc/rfc8259.html#section-10). Number spelling,
duplicate retention and the selected escape spelling are this library's
documented policies.

Read first validates the complete logical destination range. Invalid
offset/count metadata returns `core::io::Error::InvalidInput` without changing
the destination or cursor. A valid zero request returns zero unchanged.
A positive request fills exactly `min(request, remaining)` bytes and advances
the stored machine. Escape sequences and multibyte UTF-8 may cross read
boundaries: individual chunks need not be complete JSON or valid UTF-8.
Concatenating all acknowledged chunks yields the admitted document bytes.
After exhaustion, subsequent reads return zero without regeneration.

The cursor provides Read only; there is no Iterator, BufRead, seek or inherent
`next` facade. A caller can use any existing Read consumer, including the
[resumable copier](stdlib-resumable-copy.md). `remaining()` reports bytes left
in this cursor; a consumer that requires EOF must still perform a real
positive-length read and observe zero.

## Borrowed lifetime and copies

Encoding borrows a stable, immutable Document. Keep its nodes, options, keys,
strings and numbers alive and unchanged until every cursor using them has
retired. The Read destination must be disjoint from both the Encoding cursor
itself and document backing; cursor storage must also be separate from that
backing. Appending nodes or changing a borrowed String through another alias
violates this contract even if some earlier borrowed queries survived append.

Copying Encoding forks the complete structural, token and escape position
while sharing the same immutable source. Each copy can be consumed separately,
but supplies no extra document ownership or cleanup right. Logical destination
checks do not prove physical capacity, and no automatic lifetime enforcement
is added.

Existing public Document and String invariants are preconditions. Encoding
does not validate forged or cyclic internal trees, invalid node links or
manually corrupted UTF-8. This is an output interface for valid documents.

## Owned encode uses the same generator

The existing `encode(document)` convenience performs admission through
Encoding, then calls [alloc::io::read_to_string](stdlib-owned-input.md) with:

```text
max_bytes = admitted encoded length
max_calls = ceil(length / 1024) + 1
```

The final allowance is for the collector's real EOF probe. The bounded reader
fills each ordinary request, so the formula covers all emitted bytes and that
probe. The collector reserves before reading and adopts its Vec backing as a
String after UTF-8 validation; it makes no second whole-output copy.

Allocation failure releases the partial output and leaves the source document
unchanged. NoRoot/OutputLimit admission happens before output allocation.
The retained failure owner is destroyed before returning an encoding error.
The source maps collector errors to existing JSON categories, all at offset -1:

| Collector failure | JSON error |
| --- | --- |
| I/O, Vec or String allocation failure | `AllocationFailed` |
| Byte/call limit, I/O LimitExceeded, Vec/String CapacityOverflow | `OutputLimit` |
| InvalidLimits | `InvalidOptions` |
| Invalid UTF-8 or scalar | `InvalidSurrogate` |
| Other unexpected metadata or I/O errors | `Bounds` |

Only allocation failure is reachable during collection of a valid admitted
Encoding with an unchanged document. Exact output admission and the call
formula exclude byte/call exhaustion; the complete output is valid UTF-8.
The other mappings handle violated internal expectations without reporting
success; they are not advertised as normal outcomes for valid inputs.

## Bounded normalizer

The [json_normalize application](extended-json-normalize.md) reads a bounded
UTF-8 input through the owned collector, parses it, then retires the input
before constructing Encoding. The Document stays alive through direct output
and is destroyed on ordinary terminal paths. There is no output String or
per-chunk owner.

The application guide owns the exact input/output, document and direct-call
limits. These are application policy; parser defaults remain unchanged. Only
ReadLimit continues automatically, and success requires observed Eof. The
application accepts no arguments, adds no newline and keeps errors quiet.
Parsing and output admission precede stdout; later failures can leave a
confirmed prefix. Signal setup, status mapping and ordinary cleanup are
documented with the program's own executable evidence.

## Evidence and remaining work

The reviewed source is `extended/ext/json.lani` at SHA-256
`f335f9f7a8dce1a8b2001dad52c48a10e188147479b854c00d21b58ce498266d`.
All four JSON library gates pass: direct byte/Read contracts, an independent
ordered-document model and two resource tests. The [direct fixture](../tests/fixtures/extended_json_streaming/README.md)
checks every initial cut from zero through 108 of a literal wire on two actual
layouts, forked copies, invalid/zero/EOF reads, generic Read compositions,
owned parity and preflight errors.

The independent model checks 978 ordered-AST cases: 672 admitted and 306
rejected. Across two layouts it observes 24,774 reads, 8,857 copies, 3,360
invalid requests, 3,155 zero requests and 7,056 positive-request EOF results.
The sum of admitted wire lengths is 32,940 bytes; it is not total traffic
because copies and owned encoding repeat output. Complete ordered wires,
remaining counts, destination guards and public node/link/key/value snapshots
are compared. Seed is `0x150a0261110`; sixteen host comparator corruption
controls are separate from native cases.

The [resource fixtures](../tests/fixtures/stdlib_stream_encoding/resources/README.md)
check borrowed output at 4,096/262,144-byte text sizes: 798,832 exact bytes,
fixed 4,093-byte output scratch, 24 matched allocations/releases and no output
allocation. The separate owned-output gate reaches two selected
allocation denials, at mmap ordinals 13 and 23 (output sites 0 and 10).
Each preserves the eight source owners, then recovers the exact 786,488-byte
output in the same process; the respective runs have 23/33 exact matched
allocations and releases. These are two focused output-growth failures, not
an exhaustive allocation-site campaign. The recovered owned String remains
valid after explicit source destruction and is checked again before release.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `stream-encoding-json-direct.log` | Direct contracts, 1/1 / 6.92s; separate Rust build 1.68s |
| `stream-encoding-json-model.log` | Ordered-AST model, 1/1 / 7.48s; exact 978-case corpus; separate Rust build 1.97s |
| `stream-encoding-resources.log` | Both JSON resource tests accepted in a 2-pass/1-compile-failure run / 11.61s; separate Rust build 1.77s. The copier fixture's visibility error and later passing retry are separately scoped in its guide |
| `stream-encoding-normalize-model.log` | Application model group, 25 native cases / 7.16s; separate Rust build 1.67s. This functional receipt alone makes no allocation claim |
| `stream-encoding-normalize-admission.log` | Application admission group, 15 cases / 7.72s; separate Rust build 0.17s |
| `stream-encoding-normalize-limits.log` | Application limit group, nine cases / 9.30s; separate Rust build 0.20s |
| `stream-encoding-normalize-io.log` | Application I/O group, 51 cases / 23.15s, including 33 reached allocation failures; separate Rust build 0.17s |
| `stream-encoding-regression-json.log` | One selected existing builder/query/limits/ownership regression / 6.98s; separate Rust build 1.91s, outside the new-gate counts |
| `stream-encoding-normalize-cli-build.log`, `stream-encoding-normalize-cli-examples.log` | Documented standalone build exits 0 with no diagnostics; both examples from that artifact exit 0 with exact 43/12 stdout bytes and empty stderr, separate from the 100 native test cases |

All four normalizer groups total 100 native cases. The model's saved traces
also passed a stricter ledger through a later host-only replay; this added no
native cases. The [application guide](extended-json-normalize.md) records that
oracle distinction, exact fault boundaries and cleanup observations.
Standalone build/examples pass without adding to the 100-case count. The
migrated source does not inherit historical normalizer receipts.

The initial runtime target is native Linux x86_64 CPU output from the GPU
compiler. User-program device execution, other hosts, enforced lifetimes and
formal verification remain separate. Streaming parsing, floating-point JSON
conversion, additional numeric builders, editing/removal and deep cloning
remain outside this increment. The whole library goal remains open.
