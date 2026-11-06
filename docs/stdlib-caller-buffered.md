# Caller-provided buffered streams

`core::buffered` separates byte buffering from storage allocation. Its reader
and writer borrow a caller-provided `View<u8>` and an endpoint. The allocating
`alloc::buffered` wrappers own a Vec and use the same core state machine.
The [frozen plan](library-caller-buffered-plan.md) defines this increment.
All selected library, model, resource, regression and application gates pass
on Linux x86_64 CPU output through the GPU compiler. Earlier buffering and
Seek receipts retain their original source and API scope.

## Factories and capabilities

```text
core::buffered::reader<R>(inner:&R, buffer:View<u8>) -> Result<Reader<R>,io::Error>
    where R:Read
core::buffered::writer<W>(inner:&W, buffer:View<u8>) -> Result<Writer<W>,io::Error>
    where W:Write
reader_from_parts<R>(parts:&Parts<R>) -> Result<Reader<R>,io::Error> where R:Read
writer_from_parts<W>(parts:&Parts<W>) -> Result<Writer<W>,io::Error> where W:Write
```

The restoration factories exist in both `core::buffered` and
`alloc::buffered`, using the Parts type from their own module. The existing
allocating factories still take a positive byte capacity instead of a View.
Read, Write, BufRead, Seek and their errors are the existing `core::io`
protocols; no storage trait or alternate protocol is introduced.

| Adapter | Protocol bounds | Additional methods |
| --- | --- | --- |
| Reader<R> | Read and BufRead under R:Read; Seek under R:Read+Seek | `buffered()` |
| Writer<W> | Write under W:Write; Seek under W:Write+Seek | `pending()`, `finish()` |
| Both | Metadata and lifecycle methods | `borrow()`, `capacity()`, `is_active()`, `is_faulted()`, `take_parts()`, `discard()` |
| Parts<I> | Handoff metadata | `borrow()`, `bytes()`, `discard()` |

Core constructors require positive View length, nonnegative start and an
i32-representable start+length. Invalid metadata returns `InvalidInput` before
backing access or an endpoint call. Valid construction neither initializes
the selected bytes nor allocates. The caller must supply physical backing
for the entire View and keep it live; logical metadata checks cannot establish
the source slice's physical length.

The buffer retains its original offset and signed byte stride. Adapter
start/end state is relative to the selected View. Provider calls and byte
copies include the original offset; an interior or descending View does not
become a packed byte array. Logical capacity is the selected element count,
not a claim about its physical stack or allocation extent.

## Handoff and consuming restoration

Core `Parts<I>` contains `inner:&I`, `buffer:View<u8>`, relative `start:i32`,
`length:i32` and `faulted:bool`. Allocating Parts retains its existing Vec
and the same range/fault meaning. The selected capacity remains available
even when the retained range is empty.

`take_parts()` requires an active adapter, makes no endpoint call and
inactivates its actual source. It transfers control over the buffer state;
allocating handoff also transfers the single Vec cleanup responsibility.
The endpoint always remains borrowed.

Restoration checks the buffer metadata and a nonnegative retained interval
fully within capacity. Failure returns `InvalidInput` with the actual Parts
unchanged, without backing access or endpoint calls. Success preserves the
exact backing, endpoint, interval and fault flag, then empties the actual
Parts. A second restoration rejects. Allocating restoration transfers the
Vec without allocation or release. Faulted Parts restore a faulted adapter;
restoration does not repair unknown provider effects.

Parts is layer-neutral. Restore the same reader or writer meaning that
produced it: unread input is not permission to send those bytes as output.
End all old views and aliases before restoration. A shallow record copy does
not create an independent controller or another cleanup owner.

For ordinary, nonfaulted state, reader Parts identifies exactly this layer's
unread input; writer Parts identifies its suffix not yet accepted by its
immediate inner writer. Process those bytes before resuming direct endpoint
access. A nested adapter may retain additional read-ahead or output. When
faulted, the retained writer suffix is only the range not confirmed accepted
before the invalid acknowledgement; replay could duplicate unknown effects.
Reader faults do not publish bytes from a malformed successful read.

## Shared I/O transitions

Both storage forms use the existing [buffering contract](stdlib-buffered.md).
The core engine preserves these transitions:

- Inactive returns `InvalidInput`, then faulted returns `InvalidCount`, before
  argument validation or zero-count success. Valid zero-count read/write
  calls make no endpoint call.
- Reader returns existing unread bytes, or makes at most one immediate read
  to fill an empty buffer. Empty is an EOF observation, not a permanent cache.
  `consume` never refills and rejects negative or excessive counts unchanged.
- Writer copies only a prefix fitting unused tail space. When full, it drains
  all old pending bytes before accepting any current source. An ordinary
  failure preserves the suffix after confirmed downstream progress and
  accepts none of the current source bytes. No compaction or large-I/O bypass
  is added.
- Interrupted, WouldBlock and other ordinary errors propagate without hidden
  retries. An ordinary `Err(InvalidCount)` does not itself fault this layer.
  Invalid successful read/write counts or nonzero successful flush results
  do fault it, before those counts can become indices or published ranges.
- Flush drains, then calls inner flush once, even when pending was already
  empty. An inner flush error leaves active, empty pending state for retry.
  Finish succeeds only after flush; no automatic drop or flush occurs.

Acceptance by a buffered writer is local to that layer. Empty outer pending
bytes do not establish delivery through an inner buffer, and flush is not
fsync, close or an atomic-publication guarantee.

## Seek, finish and discard

The conditional implementations preserve [shared Seek](stdlib-seek.md):

| Operation | Effect |
| --- | --- |
| Reader Start/End | One inner seek; successful Start must acknowledge the exact target; success clears unread publication |
| Reader Current(delta) | Query inner Current(0), subtract unread count, check signed arithmetic, then seek Start(target), including delta zero |
| Reader arithmetic rejection | Preserve unread bytes and active state; no repositioning request |
| Reader provider seek error or malformed position | Preserve the error, clear unread publication and fault the reader |
| Writer Seek | Drain and inner flush first, then one seek; flush failure makes no seek; ordinary seek error leaves active empty pending state; malformed Start faults |

Seeking invalidates published views. A successful finish inactivates the
writer; failure retains its state. Core finish/discard never free or clear
caller bytes. Allocating finish releases the Vec only on success; allocating
discard releases it on explicit abandonment. Adapter or Parts discard returns
the tracked retained byte count and empties metadata; repeated discard returns
zero. A faulted count is not a claim about actual delivery.

## Manual lifetimes and effects

Keep one exclusive active controller, its endpoint, selected scratch and all
referenced backing live. State storage, scratch, endpoint mutable backing and
read/write argument ranges must not interfere. Do not drive the endpoint,
edit scratch or reenter the adapter through another alias. Published buffer
and Parts views are read-only observations whose borrows end before the next
state mutation. Nested outer controllers must be settled before their inner
controller or backing is retired.

The core buffering engine performs no allocation or cleanup of caller storage.
Provider implementations keep their own effects, allocation and blocking
behavior. Allocating constructors reserve and initialize their Vec once;
subsequent I/O does not grow it. Each completed handoff has one cleanup
authority, with no implicit destruction or unwind recovery.

A read/fill makes at most one direct read attempt. A drain makes at most its
initial pending-byte count in direct write attempts: every continuing result
advances at least one byte. Flush adds one direct flush call; Writer Seek adds
one seek after successful flush, and Reader Current uses at most two seeks.
These bounds exclude provider-internal calls and give no wall-clock deadline
or throughput guarantee.

Rust's [BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html) and
[BufWriter](https://doc.rust-lang.org/std/io/struct.BufWriter.html) document the
importance of preserving read-ahead and observing flush errors. Lanius keeps
explicit finish, handoff and discard; Rust's Drop behavior, optimized position
queries and internal buffer choices are not part of this contract.

## Consumers, evidence and dependencies

[select_records](stdlib-select-records.md) uses a caller-backed 4,096-element
reader; [format_report](stdlib-format-report.md) uses a caller-backed
17-element writer alongside its seven-byte formatting scratch. Their grammar,
limits, complete-input/preflight admission, output and remaining owned
resources stay the same. Removed buffer allocations and their former failure
sites intentionally disappear. `buffered_copy` stays an allocating-wrapper
regression with separately scoped evidence.

The increment is accepted for the selected direct, model, resource,
regression and application gates below. The target is Linux x86_64 CPU output
from the GPU compiler. Portable source does not establish GPU-device or other-target
execution. Physical backing, lifetime enforcement and formal verification
remain separate dependencies; the full library goal remains open.

The runtime allocator pools ordinary allocations by default. Exact
mapping/release and allocation-denial gates select `LANIUS_ALLOC=mmap` to
observe each allocation boundary. Their mapping counts describe that explicit
test mode, not ordinary pooled processes. Core buffering remains allocation
free in either mode; an endpoint may have its own allocation effects.

### Current native receipts

These runs use the compiler rebuilt from the rebased source
`cc8cfec224b7537ccbb3b24c1fe4df7e8367b371`, producing Linux x86_64 CPU
executables through the GPU compiler. They are finite functional checks, not
throughput measurements or evidence for another target. Log names below are
relative to `target/stdlib-work/`.

| Gate | Result | Receipt |
| --- | --- | --- |
| Tiny core/owning/Seek/Parts admission | One test passed in 46.01s with cold shader setup; the final original chained-call source passed separately in 5.93s. | `caller-buffered-lang-admission-current-kernels.log`, `caller-buffered-lang-admission-final.log` |
| Direct behavior and capabilities | Six tests passed in 11.53s: three native contract fixtures plus three groups covering 12 marked missing-capability rejections. Admission was filtered; three temporary dependency probes were ignored in this command. | `caller-buffered-lang-direct.log` |
| Temporary import/generic-result controls | All three explicitly selected probes passed in 5.98s. They were removed after resolving the artifact-path setup issue; these are diagnostic controls, not permanent library gates. | `caller-buffered-lang-generic-probes.log` |
| Independent native model | One test passed in 6.13s: 144 cases, 1,455 actions and 753 provider calls across native descending, packed interior and owning routes. | `caller-buffered-lang-model-retry.log` |
| Model host controls | One host-control test passed with two positive scratch patterns and 22 rejected corruptions. The same initial command's native test failed on fixture syntax/setup, so that command was not wholly green. | `caller-buffered-lang-model.log` |
| Existing allocating buffering | All five tests passed in 12.23s, including the actual binary-copy sample, reader/writer contracts, nesting and four reached constructor denials. | `caller-buffered-lang-existing-buffered.log` |
| Existing buffered Seek | All three tests passed in 9.51s, including reader/writer state and nested handoff/restoration with constructor denials. | `caller-buffered-lang-existing-seek.log` |
| Record selector | All four tests passed in 9.06s: model33, limits8, CLI33 and I/O18, totaling 92 native cases. I/O includes all five observed allocation denials in direct-allocation mode. | `caller-buffered-lang-select-records.log` |
| Owner/resource gates | All four tests passed in 15.08s: real heap backing, actual negative stride, both mixed nesting orientations at 4,096 and 262,144 bytes, reached owning-constructor denial with retry, and exact address/extent release accounting. | `caller-buffered-lang-resources-final.log` |
| Format report | One test passed in 10.21s: one strict ELF and 69 native cases, including all 11 observed representative allocation denials. | `caller-buffered-lang-format-report.log` |

The initial LNC0047 admission failure loaded old kernels through a relative
artifact path. Supplying the supported absolute `LANIUS_SHADER_ARTIFACT_ROOT`
admitted the current compiler output. The three import/generic-result controls
then passed, and the final tiny check passed with the original natural chained
Read/Seek calls. These fixtures establish no current generic compiler
dependency. This was build setup, not a reproduced compiler-source defect or
a compiler repair. Static inspection supplied the model's explicit fixture
source root before its first native invocation. That invocation rejected only
unsupported fixture `else if` syntax; the corrected retry retained the
histories, oracle and expected bytes.
The [model guide](../tests/fixtures/stdlib_caller_buffered/model/README.md)
records its full comparison scope and accepted source hashes.

Earlier resource attempts failed on fixture byte-length/enum-name spellings
and the Rust trace parser's handling of alignment whitespace. The accepted
retry corrects a `usize` length, qualified enum names and trace parsing;
neither production buffering nor compiler source changed for these failures.

### Source manifest

These SHA-256 values identify the current production sources and principal
drivers for the receipts above. The direct driver excludes the resolved
temporary probes, and the final tiny receipt uses the original chained calls.

| Source, relative to the repository root | SHA-256 |
| --- | --- |
| `stdlib/core/buffered.lani` | `d21dfc851783d4f69f77834c4e44080662bb07eb090af0990ade4c91adb2150a` |
| `stdlib/alloc/buffered.lani` | `e034d16035b015934df9bb20980bdc1344472c9ea3956f45d4bea4f1fa323eb5` |
| `stdlib/core/io.lani` | `20989eca5ce3860a7dd0dee89f31ec5df8ba4dd7bdddaaf1b9067a7a36fb70ab` |
| `stdlib/core/slice.lani` | `c67c47cad01117fd2d9f733ad8b736d7116b4efde51cc214ae2be03632e38b62` |
| `sample_programs/library/select_records.lani` | `f8039e5656cbaf8c3d338231a822a68c50c218d8b6fca8ed5f87bbb5134bd321` |
| `sample_programs/library/format_report.lani` | `0bd263f0862fa797e5e5079990e5a04b04d5b0846c5df8676aae43e7d65706d6` |
| `sample_programs/library/buffered_copy.lani` | `e698aef5ead468f7dd928cb8391e68da7e43dc676774db62b62e6d56a878b238` |
| `tests/stdlib_caller_buffered_execution.rs` | `cde019eee0fcd182c6acd1ebf493ddb763672327853710239aedca22dba65ac3` |
| `tests/fixtures/stdlib_caller_buffered/direct/admission.lani` | `ce2cefe016a2eaa90b5f2e61049510c2fa536e020e30849c590f137b46ccd9f6` |
| `tests/stdlib_caller_buffered_model_execution.rs` | `a59f8c5c4c2847d27b96a7c45115aa168d972b60d1f3e49882ebcb0ffdaa0668` |
| `tests/stdlib_caller_buffered_resources_execution.rs` | `8471bd71ddcf76f0353be3f15c30c8f76b155b6da8812c9dbcf06fa4f43905c0` |
| `tests/fixtures/stdlib_caller_buffered/resources/heap_lifecycle.lani` | `168a187c06da31dd9adf1057e891b94af5855a745f86efc8db1ae8ab7175d465` |
| `tests/fixtures/stdlib_caller_buffered/resources/mixed_core_outer.lani` | `1a810af69071ea0508b9a29f0ab50b5309d87ea02ec628bb96cccfa623a46775` |
| `tests/fixtures/stdlib_caller_buffered/resources/mixed_alloc_outer.lani` | `c84835eb312c293a3af6fd88c330ad10b73e067079b3a2999714c634aa501c2b` |
| `tests/fixtures/stdlib_caller_buffered/resources/constructor_retry.lani` | `7e2d78a665be593523aabd15aed3ba3950e1abfde473d7745481d1980dcd375d` |
| `tests/fixtures/stdlib_caller_buffered/resources/fixture/resource.lani` | `ef81ca27e3a922a8e9ec7006add676652adb08cea5392b70a30345725dbaebd5` |
| `tests/stdlib_select_records_execution.rs` | `0fd867e851b34e770a668652e46eed3dc72d321268509d3a16267b1870ff4ffc` |
| `tests/stdlib_format_report_execution.rs` | `c21e9d94f80309a9d413b3e05f601478e5f03d6cb09853bd530bbae426632fed` |
| `tests/fixtures/stdlib_foundation/buffered_seek/nesting.lani` | `1730894b791faae0e149871ccb4d2f6c6e122e0c2bd39aeaf0b4550927dedcd8` |

The 18 current direct `.lani` fixtures have aggregate digest
`db62d43398afa40966cbe4d388200f1c49287a83ec632715c9e255dee2e11c04`.
It is SHA-256 over UTF-8 lines of `SHA256  repository/relative/path\n`, sorted
by path, for all `.lani` files beneath
`tests/fixtures/stdlib_caller_buffered/direct/`. This identifies that fixture
set without claiming a complete transitive source closure.
