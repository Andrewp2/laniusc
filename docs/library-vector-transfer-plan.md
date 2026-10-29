# Vector ownership transfers

The full standard and extended library goal remains open. At `6c24e6dd`,
`alloc::vec` can copy a borrowed view, transfer single entries and hand its
allocation to an owning iterator. It cannot directly transfer a whole owner,
append another owner's entries, split a suffix or extract an owned range.
This increment fills that main-library gap and exercises it with owned CSV
records. It does not migrate the protected `std::vec` or change memory layout.

## Sources and choices

The reference semantics are Rust's [Vec append, split_off and drain](https://doc.rust-lang.org/std/vec/struct.Vec.html)
and [mem::take](https://doc.rust-lang.org/std/mem/fn.take.html), read on
2026-10-29. They establish ordered entry transfer, retained source capacity
for splitting, whole-owner replacement and range removal. Lanius uses signed
indices, recoverable allocation errors and explicit manual ownership. Its
range operation eagerly returns an independent Vec. A borrowed drain cursor
would add a suspended mutation/cleanup protocol that is unnecessary here.

Existing `Deque.try_split_off`, Vec's atomic `try_extend`, and its owning
iterator establish local precedents. Reuse those storage and failure rules.
There are no compatibility aliases, new collection types or new trait bounds.

## Public contract

Add four methods to `alloc::vec::Vec<T>`:

```text
take() -> Vec<T>
try_append(other: &Vec<T>) -> Result<i32, Error>
try_split_off(at: i32) -> Result<Vec<T>, Error>
try_extract_range(start: i32, end: i32) -> Result<Vec<T>, Error>
```

All methods operate on valid existing owners. Public field visibility does not
make forged metadata, expired backing or multiple active cleanup authorities
valid. Entries transfer shallowly without cloning or destroying nested values.
Transferred nested owners retain exactly one cleanup authority. Borrowed
pointers inside an entry retain their original backing/lifetime obligations.

- `take` transfers the allocation, capacity and all initialized entries in
  O(1), then resets the actual source descriptor to `(0,0,0)`. No allocation,
  element copying or destruction occurs. This includes reserved-empty owners.
- `try_append` appends every donor entry in order, returns the destination's
  new length, and sets donor length to zero. Donor backing and capacity remain
  unchanged. Empty donors leave both owners and views unchanged. Nonempty
  success invalidates prior views of both owners. A needed growth uses at most
  one allocation and geometric growth; sufficient capacity requires none.
- `try_extract_range` admits exactly `0 <= start <= end <= len`, returns the
  entries in `[start,end)` in order and compacts the retained suffix in order.
  Source capacity and backing remain unchanged, including full extraction.
  Empty ranges return `new()` without changing source state or views.
  Nonempty nonzero-sized results use one independent allocation; successful
  extraction invalidates prior source views.
- `try_split_off(at)` is extraction of `[at,len)`. The source retains its
  capacity even at zero. Splitting at length returns an empty zero-capacity
  result without allocation or source changes.

Append requires two distinct, exclusively active owner descriptors with
independent backing. Neither descriptor may live in storage that the operation
can relocate or overwrite. Self-append, shallow aliases and overlapping owners
violate this caller precondition; this API does not promise runtime alias
detection. Distinct empty and zero-sized owners are valid even though their
storage pointers are equal to zero. Pointer equality alone is not an alias
check. This is the existing manual-lifetime boundary, not a borrow checker.

Errors use the existing Error enum. Invalid extraction/split bounds return
`Bounds` before allocating or reading entries. Append checks combined capacity
before mutation and returns `CapacityOverflow` if needed. Allocation failure
returns `AllocationFailed`. Every error preserves all participating owner
descriptors, capacities, initialized values, nested resources and existing
views. No partial result or transfer escapes.

Zero-sized entries use descriptor-only operations after checking bounds/counts.
Positive reservation follows the existing `i32::MAX` capacity convention;
empty extraction/split results have zero capacity, while `take` preserves the
transferred capacity even for an empty owner. No entry loops or allocation occur for these
new operations on zero-sized T, including valid maximum-length owners.

## Implementation shape

Whole-owner transfer copies the three fields and resets the source. Nonzero
append reuses atomic `try_extend(other.as_view())`, then clears donor length
only after success. Zero-sized append uses checked reserve and count updates.

Range extraction validates, reserves the result, copies removed typed entries,
compacts the suffix forward by logical index, and commits lengths. Split calls
that same operation. Zero-sized extraction changes counts only. All typed
storage views use their actual owner's capacity: composite physical element
positions can depend on capacity, so raw-byte copy, offset allocation sharing
and raw realloc are unsuitable.

With constant-cost element assignment, append is O(donor length), plus the old
destination length if growth relocates; extraction is O(removed + suffix),
split is O(suffix), and take is O(1). Scratch is constant beyond a required
result/growth allocation. These are algorithmic contracts, not throughput
claims. No nested allocation/destruction or user callback runs during transfer.

## Real consumer

Add `move_rows START END BEFORE`: a bounded stdin-to-stdout UTF-8 CSV row mover.
All three indices denote boundaries in the original table, with a half-open
selection `[START,END)` and `0 <= START <= END <= rows`, `0 <= BEFORE <= rows`.
An empty selection or BEFORE within `[START,END]` leaves row order unchanged.
Otherwise remove the selection and insert it before the original BEFORE
boundary (subtract the removed count when BEFORE is after END). No header row
receives special treatment.

Reuse `ext::csv` parsing and canonical `ext::csv_write` serialization. Each
Record owns bytes and field spans. Take the table's row owner, extract the
selection, split the remainder at its adjusted destination and consume-append
the selection and suffix. Preserve field values, order and duplicates. Format
canonicalization is explicit even for order-preserving operations.

Parse complete input before table-relative bounds and transformation. Bound
input to 4 MiB, rows to 16,384, fields per row to 64, individual field bytes to
8,192 and record bytes to 65,536. Use the established uniform-width CSV dialect,
allowing LF and CRLF. Stage canonical output up to 8 MiB before stdout. Bound
input and payload-output attempts to 16,384 each; help and diagnostics allow
64 write attempts. Indices are ASCII decimal, at most 16,384, with at most
64 bytes per token. Only a sole `-h` or `--help` requests help. Bound argument
snapshots and document their actual token/byte limits.
Cleanup every record and outer owner before publication; retain only staged
output and any required argv owner. Prepublication failures produce no stdout;
I/O failures may retain only a confirmed output prefix. Diagnostics follow
cleanup. Define statuses consistently with the neighboring staged CSV program:
0 success, 2 arguments/data/bounds/limits, 3 I/O, 4 allocation, 6 invariant;
diagnostic failure selects 3. Adopt the established explicit SIGPIPE policy.

## Verification and ownership

Eight agents own implementation, consumer, direct tests, stateful model,
resource/scale tests, consumer tests, docs and independent review. Root owns
this plan, integration and release. Root alone runs compiler/Cargo/native
commands serially under `target/stdlib-work/library-gpu.lock`, with each outer
command capped at 100 seconds. First execute one tiny composite admission.

Direct tests cover empty/full/boundary cases, differing capacities, actual
packed/descending/composite types, nested owners, bounds/overflow and zero-sized
maximum lengths. The maximum-length Unit witness may construct a valid
zero-byte owner directly: every Unit is inhabited and owns no resource, so no
physical entries need allocation. This descriptor/arithmetic test does not
claim to have executed billions of pushes. Ordinary constructed zero-sized
cases remain separate. The independent model compares full states after reproducible
mixed operations and checks conservation without mirroring the algorithm.
Resource tests observe reached allocation denials, unchanged old views on
failure, same-process recovery, exact address/extent cleanup and nested-owner
conservation. Large typed cases check full order/values and linear range work.
Application gates cover semantic CSV relocation, arguments/limits, real EOF,
staging and reached allocation/I/O failures with an independent model.

Selected existing Vec/owning-iterator regressions check changed shared storage
behavior. No broad GPU or unrelated suite reruns. Initial acceptance is Linux
x86_64 CPU output from the GPU compiler; other hosts, device execution, enforced
ownership and formal proof need separate evidence. Preserve README, AI_POLICY,
CONTRIBUTING, tests/common, core/mem, std/vec and compiler/IR/ABI/extractor/proofs.
Report new compiler limitations with a small reproduction instead of absorbing
compiler work. Keep pending and accepted receipts distinct, generate reference
pages after source/docs freeze, exact-stage and push the accepted increment.

## Accepted increment

All eight new library groups and all four application groups pass on Linux
x86_64 CPU output from the GPU compiler. The vector implementation remains
`d1c9d25d` from the first tiny admission; the application is `9bb0cf06`.
No production library correction or compiler change was needed.

| Gate | Accepted result | Local receipt |
| --- | --- | --- |
| Tiny composite admission | 1/1 in 4.89 s; Rust build 37.16 s | `target/stdlib-work/vector-transfer-admission.log` |
| Ranges, capacities and bounds | 1 passing group in a mixed 3-group, 10.01 s command; build 1.91 s | `target/stdlib-work/vector-transfer-direct.log` |
| Generic/nested types and maximum ZST counts | Corrected fixtures pass 2/2 in 9.03 s; build 0.19 s | `target/stdlib-work/vector-transfer-direct-retry.log` |
| Independent operation model | 1/1 in 9.42 s; build 0.20 s | `target/stdlib-work/vector-transfer-model-final.log` |
| Nested ownership, failures/recovery and scale | 3/3 in 12.52 s; build 1.90 s | `target/stdlib-work/vector-transfer-resources.log` |
| CSV relocation model | 33 cases in 7.43 s; build 1.74 s | `target/stdlib-work/vector-transfer-tool-model.log` |
| CSV admission, limits and faults | 29 + 11 + 60 cases in one combined 18.08 s command; build 0.19 s | `target/stdlib-work/vector-transfer-tool-remaining.log` |
| Existing vector groups | 4/4 in 24.26 s; build 1.71 s | `target/stdlib-work/vector-transfer-existing-vec.log` |
| Existing owning-iterator handoffs | 1/1 in 7.00 s; build 1.81 s | `target/stdlib-work/vector-transfer-existing-owning.log` |

The direct groups cover actual packed, descending and compound layouts, nested
owners, empty/full/boundary ranges, unchanged rejected edits and valid maximum
zero-sized counts. The initial mixed direct command rejected two test fixtures
whose aggregate literals used integer zero where ptr was required. Typed null
bindings corrected those fixtures; only the two failed selectors were rerun.
The accepted range and tiny groups were unchanged. These were test authoring
errors, not newly discovered compiler bugs.

The independent model executes 56 cases and 3,584 actions across five shapes,
with seed `0x7ec7a0261114`. It creates 787 entries, including 170 nested owners,
moves 3,698 entries, performs 913 nonempty and 397 empty transfers, and checks
242 range errors plus 112 reserve-capacity errors. It examines 1,049 saved
views and 28,352 full snapshot entries. Twenty-seven host corruption controls
and two legal capacity policies establish separate oracle checks; they add no
native cases. The first model compile rejected test-only ptr-to-integer casts.
Replacing those casts with the established raw pointer-word storage pattern
preserved the full address/extent observations and unchanged oracle/corpus.
That failed 3.94-second test invocation is retained in
`target/stdlib-work/vector-transfer-model.log`, with a separate 1.70-second
Rust build; it is not native acceptance.

Resource tests preserve 34 nested allocation identities and complete payloads
across 17 entries, with 39 matched allocations/releases. Three reached
allocation denials separately target append growth, suffix splitting and
interior extraction. Each preserves existing owners and old views, then
recovers in the same process; each complete fault process has 109 successful
allocations and matching releases. These three library denials are separate
from the application's forty denials.

The scale gate checks all 532,480 values and 4,259,904 output bytes for 4,096-
and 262,144-entry packed-i32 and descending-record cases. All twelve mappings
are released. Its full traced native process takes 0.369045 seconds,
separately from 3.183870 seconds compiling that fixture. This includes setup,
checks and publication and is not isolated throughput or a comparison with
another implementation. The source algorithm supplies the stated linear work
bound; this finite run is supporting execution evidence.

The real CSV program passes 133 native process cases: 33 relocation-model,
29 admission, eleven limits and sixty fault cases, including forty reached
allocation denials. Actual 4 MiB input and 16,384-row boundaries are exercised.
Its appends retain sufficient original row capacity, so append-growth failure
belongs to the separate library resource gate. Output/staging ceilings that
cannot be reached under earlier admitted bounds are documented as defensive,
without invented rejection evidence. The application trace observes nine
specified syscalls and checks retirement before publication; it is not an
all-host-effect trace.

Standalone CLI compilation passes with exit zero and an empty success log in
`target/stdlib-work/vector-transfer-cli-build-final.log`. Its first compile
required whitespace between a generic type's closing `>` and initializer `=`;
that syntax correction changed no behavior. Both documented examples pass
exact canonical CSV comparisons with 25 and 58 output bytes, exit zero and
empty stderr, recorded in `target/stdlib-work/vector-transfer-cli-examples.log`.
These two runs are separate from the 133 application cases.

The [vector guide](stdlib-vec-transfer.md), [program guide](stdlib-move-rows.md)
and linked fixture records retain source hashes and precise receipt scopes.
Independent source, test and documentation reviews pass. Existing vector and
iterator receipts remain separate from new API counts. No new compiler/runtime
dependency was encountered. Protected-vector migration, enforced lifetimes,
other targets, formal proofs and the full library roadmap remain open.
