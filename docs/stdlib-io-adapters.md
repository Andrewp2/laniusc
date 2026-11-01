# Borrowed reader limits and concatenation

The [reader-adapter increment](library-io-adapters-plan.md) adds `Take` and
`Chain` to [core::io](../stdlib/core/io.lani). Take caps logical byte progress;
Chain reads the first source until it observes EOF, then uses the second.
Both compose with the existing Read and BufRead protocols. All seven library
tests and four application groups/115 cases pass on native Linux x86_64; earlier [stream](stdlib-streams.md), [buffered](stdlib-buffered.md)
and [delimiter](stdlib-delimited-io.md) receipts retain their original scopes.
The full standard/extended-library goal remains open.

The established [Take](https://doc.rust-lang.org/std/io/struct.Take.html) and
[Chain](https://doc.rust-lang.org/std/io/struct.Chain.html) interfaces motivate
the byte quota and concatenation operations. Their
[reference implementations](https://doc.rust-lang.org/src/alloc/io/util.rs.html)
use successful reads to spend quota and permanently hand off after first-reader
EOF. Lanius adds its own exact acknowledgements, explicit errors, independent
BufRead bound and borrowed lifetime contract. Excessive consumption rejects;
it is never silently clamped.

## Public surface

```text
take<R>(inner:&R, limit:u64) -> Take<R>
chain<A,B>(first:&A, second:&B) -> Chain<A,B>

Take<R>:
  borrow() -> &Take<R>
  limit() -> u64
  set_limit(limit:u64) -> Result<u64,Error>
  is_faulted() -> bool

Chain<A,B>:
  borrow() -> &Chain<A,B>
  is_first_done() -> bool
  is_faulted() -> bool
```

The factories and inherent methods require no Read or BufRead capability.
The conditional implementations are independent:

| Adapter capability | Required source capability |
| --- | --- |
| `Read for Take<R>` | `R: Read` |
| `BufRead for Take<R>` | `R: BufRead` |
| `Read for Chain<A,B>` | `A: Read, B: Read` |
| `BufRead for Chain<A,B>` | `A: BufRead, B: BufRead` |

Thus a BufRead-only provider can be limited or chained and passed to delimiter
consumers without gaining Read. Neither adapter implements Seek: limiting or
concatenating positions needs a separate position contract.

Construction stores references and scalar state without allocation or provider
calls. The adapters never own, close, destroy or automatically retire sources.
Keep source owners and adapters alive throughout use, with one active path to
each source's state. Do not operate copied adapters independently or mutate the
source through another alias. Returned buffered views are read-only borrows;
end them before the next mutation through the source or adapter. `set_limit`
also invalidates an earlier Take fill view. Physical backing and lifetimes
remain caller obligations; no compiler-enforced ownership is implied.

## Shared forwarding and fault behavior

A healthy read first checks the entire offset/count range with `valid_range`.
Negative or overflowing metadata returns `InvalidInput` before provider access,
including when the quota is zero. A valid zero-count read returns zero without
calling providers or changing chain selection. Providers receive the original
destination and offset with the admitted count. A short read returns at once;
the adapter does not fill the rest of the request.

Every ordinary provider `Err` propagates unchanged without an internal retry.
This includes Interrupted, WouldBlock and a provider's own `Err(InvalidCount)`.
These errors alone do not fault the outer adapter. Consumers separately bound
retry counts, host work and time.

Only an invalid *successful* provider result faults an adapter: a read count
outside `0..requested`, negative or overflowing fill View metadata, or a consume
acknowledgement unequal to the requested count. The adapter returns
`InvalidCount` and permanently rejects later Read/BufRead operations and
`set_limit` with that error before checking arguments or empty requests. No
later provider call occurs through that faulted adapter. State queries remain
usable. Confirmed prior progress stays committed; effects of a broken provider
cannot be rolled back or inferred from its invalid acknowledgement. Constructing
a fresh adapter does not prove that the source recovered.

Healthy `consume(n)` rejects negative `n` with `InvalidInput`; zero returns zero
without a provider call. Positive consume delegates exactly once to the selected
provider. It never fills or changes chain selection. The provider must reject
consumption beyond its actual unread buffer. A provider error acknowledges no
consumption and preserves adapter quota/selection; exact success commits its
accounting. There is no last-fill cache, copied buffered payload or implicit
clamping.

## Take quota and EOF

`limit()` is the remaining quota over the full `u64` domain, including
`u64::MAX`. Read success and exact consume success share and reduce that one
counter. `set_limit(n)` replaces the remainder with `n`, returns `Ok(n)` and
calls no provider. It can reopen an exhausted quota but cannot clear a fault.

A positive read forwards `min(requested, remaining quota)`. It narrows the
quota to i32 only when that comparison proves the value fits. A valid positive
count subtracts exactly that count; provider errors and underlying EOF preserve
the quota. Underlying EOF is observational: a subsequent call can see new bytes
from the same source.

With zero quota, read and fill return EOF without consulting the source. The
empty fill is a zero-length View over a null raw slice. It needs no live backing
and must never be dereferenced. At positive quota, fill calls the provider once
and validates the complete returned metadata before truncating only its length.
Start, backing and physical stride remain unchanged. Filling exposes bytes but
spends no quota. Positive consume beyond quota returns `InvalidInput` locally;
exact successful consumption spends that amount.

Quota bounds logical reads, exposed fill bytes and acknowledged consumption
through Take. A buffered provider inside Take may prefetch more into its own
storage. Those bytes remain available from that owner later; quota does not
bound arbitrary underlying effects or provider execution time.

## Chain selection and EOF

Read, fill and consume share the same first/second selection state. A nonempty
first read returning zero, or a successful valid empty first fill, permanently
sets `is_first_done()` and consults the second provider in the same call. These
read/fill operations make at most two direct provider calls. A positive short
first read returns immediately without touching the second source.

No error, zero-count read or consume causes handoff. Once first EOF is observed,
the transition stays committed even if the second call errors or returns an
invalid successful result. Chain never revisits the first source. Second EOF
is observational: later calls still consult the second provider. Buffered views
come from one provider at a time and never span both, while delimiter consumers
can continue across the boundary through successive calls.

This policy follows the source result rather than its underlying cause. A Take
whose quota reaches zero presents EOF to an outer Chain, so the Chain's handoff
remains permanent even if that Take could later receive a larger quota. An inner
adapter's `Err(InvalidCount)` still behaves as an ordinary provider error at the
outer layer; each adapter's fault flag records its own observation of malformed
success.

## Application, evidence and targets

The [concat_bytes program](stdlib-concat-bytes.md), invoked as
`concat_bytes --limit N FIRST SECOND`, composes borrowed File readers,
Chain, Take, the existing fixed-capacity buffered reader and bounded owned-input
collection. It stages up to N bytes in first/second order; early EOF succeeds.
The application profile limits N to 0..1,048,576, uses a 4,096-byte buffer,
16,384 collection calls and 4,096 output attempts. Zero limit still opens both
files but performs no data reads. Take sits beneath the buffer, so this
application's file-read requests remain within the remaining quota. Both files
close and the buffered input is released before output publication. Its
application guide owns exact CLI, failure and partial-stdout policy.

Production source `6d3a6046d72ee3e36249744660a48f6fd4800f9c89e7056ed77fd598a0f3b643`
passes all seven registered library tests: six native tests and one group of
six negative capability checks. This includes the independent model and both
real-owner resource tests. Application source
`26933ffcd7c4cdd1bc0d120d6fa1e32ab4f0b70d47df045dbacd9a920831bba3`
passes all four groups/115 process cases, its standalone build and both
documented examples. These are eleven registered tests across the separate
receipts below. Earlier stream/buffered/delimiter receipts retain their original
source/API scopes.

| Receipt under `target/stdlib-work` | Accepted scope |
| --- | --- |
| `io-adapters-admission-first.log` | 1 native test / 6.45s: mixed Read/BufRead and nested-adapter admission; separate Rust driver build 1.64s |
| `io-adapters-direct-first.log` | 3 registered tests / 8.31s: two native contract/preflight fixtures and one capability group with six marked LNC0008 rejections; separate Rust build 1.73s |
| `io-adapters-model-second.log` | 1 native model test / 8.02s: 1,576 cases / 14,544 actions, four compositions and eight layouts, seed `0x10ada0261106`; separate Rust build 0.27s |
| `io-adapters-resources-first.log` | 2 native tests / 9.97s: actual buffered-source ownership, delimiter composition, complete 327,692-byte collection/remainder output and four reached allocation denials with same-process recovery; separate Rust build 1.87s |
| `io-adapters-app-first.log` | 4 application tests / 10.13s: 115 process cases, model 29 + limits 12 + CLI 45 + I/O 29; separate Rust build 1.75s |
| `io-adapters-app-build-command.log` | The documented standalone compiler command exits 0 without output |
| `io-adapters-app-examples.log` | Both documented shell examples exit 0 with empty stderr and exact five-byte output: text `6162634445`, binary `0041ff420a` |

The [direct fixture guide](../tests/fixtures/stdlib_io_adapters/README.md) records
error/count/fault scenarios, full destination guards and actual descending
and +1 byte layouts. Full native traces contain no intervening host calls.
Capability rejections are separate from native execution. The
[independent model guide](../tests/fixtures/stdlib_io_adapters_model/README.md)
records complete state, ordered calls and bytes after every mixed action. Its
eight layouts combine actual -8 native and +1 packed byte strides across both
sources and destination. Nine host-only output-corruption controls add no
native cases. The first model attempt rejected unsupported negative match
patterns before execution; a fixture-only positive-discriminant spelling fixed
that syntax. Production and compiler sources did not change.

The [resource guide](../tests/fixtures/stdlib_io_adapters_resources/README.md) records
seven pure small-composition phases and seven exact allocations/releases. Its
large composition spends a 300,007-byte quota while preserving 1,309 prefetched
bytes in the caller's second buffer; all 327,692 output bytes match. The baseline
releases all 21 allocations. Four selected nested-buffer/consumer allocation
denials preserve prefixes of 0 / 0 / 7,172 / 261,280 bytes and recover using
the same adapter state, with 21 / 21 / 25 / 27 matched allocations/releases.
The adapters themselves introduce no allocation or source cleanup.

The [application fixture guide](../tests/fixtures/stdlib_execution/concat_bytes/README.md)
records exact byte/model, quota, CLI and I/O evidence, including five selected
reached allocation denials. Injected close errors prove one cleanup attempt and
error precedence; because substitution skips kernel close, they do not prove
successful kernel descriptor release. Attempt-ceiling summaries are separate
from full owner-ledger cases. Standalone examples overlap these groups and add
no distinct cases.

This increment is accepted on native Linux x86_64 CPU output from the GPU
compiler. The adapter layer introduces no host service, allocation or ownership
runtime, and needed no compiler repair.
Its sources retain their own platform, buffering and cleanup requirements.
Other targets, user-program GPU execution, automatic lifetimes and formal
verification require separate evidence. The full library goal remains open.
