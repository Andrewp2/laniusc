# Allocation-backed stable sorting

## Scope and sources

Add a complete stable sort family in new `alloc::slice`, using existing
`core::slice::View`, `core::ordering::Comparator` and `Natural`, and a private
typed `alloc::vec::Vec` workspace. Core ordering remains allocation-free and
unstable under its existing contracts. Do not add a second ordering protocol,
compatibility aliases, raw byte copies or compiler/ABI/proof/protected-Vec
changes. The full standard/extended-library goal stays open.

The [Rust stable slice contract](https://doc.rust-lang.org/std/primitive.slice.html#method.sort_by)
preserves input order for equivalent elements and requires a consistent total
policy. The [Sedgewick/Wayne bottom-up merge reference](https://raw.githubusercontent.com/kevin-wayne/algs4/master/src/main/java/edu/princeton/cs/algs4/MergeBU.java)
describes iterative merging of growing runs with linear workspace. Lanius uses
its own typed buffers, alternating complete passes, checked endpoint arithmetic,
explicit allocation errors and manual owners. No adaptive-input or Rust
panic/unwind guarantee is inherited.

## Fixed API and admission

```text
module alloc::slice
Error = Bounds | Storage(alloc::vec::Error)
sort<T>(values:core::slice::View<T>) -> Result<i32,Error>
    where T:core::cmp::Ord<T>
sort_by<T,C>(values:core::slice::View<T>,comparator:&C) -> Result<i32,Error>
    where C:core::ordering::Comparator<T,T>
```

Natural sort delegates through the same custom engine and canonical Natural<T>.
No Eq, PartialOrd, Clone or Destroy bound is implied. Raw floats need an explicit
total policy/key; partial order alone does not satisfy natural sort.

1. Validate start >= 0, length >= 0 and start <= i32MAX-length before any
   payload read, callback, source mutation or allocation. Failure is Bounds.
   Physical backing/count/lifetime are separate caller obligations.
2. Admitted length zero or one returns Ok(length), with no payload read,
   comparator call or allocation. This precedes workspace capacity checks.
3. For length >= 2, reserve exactly length entries in a fresh private Vec<T>
   before reading input or calling the comparator. Preserve the Vec error as
   Storage(error); no source state or callback is touched on failure.
   Vec's existing cap is floor(2147483647/size_of<T>()) nonzero-sized entries,
   or i32MAX for zero-sized T. CapacityOverflow therefore precedes a host
   allocation attempt; AllocationFailed means an attempted reservation failed.
4. Nonzero-sized length >= 2 makes exactly one workspace allocation on success
   and releases it once before returning. No further allocation occurs during
   copying/merging. Zero-sized T reserves logical capacity without host memory;
   it still follows the normal comparator/merge engine for nontrivial lengths.

No presortedness scan occurs before reservation. Input metadata/storage and
every outside-view value remain unchanged on each returned Error. Impossible
failures of already-reserved internal pushes may assert the owner invariant;
they must not be silently ignored or converted to successful output.

## Engine and invariants

Initialize all workspace entries through typed reserved pushes before exposing
its initialized slice/view. These are shallow observations of original items,
not additional nested cleanup rights. Never access spare capacity as if it were
initialized. All transfers use typed indexes with the actual source/destination
descriptor, preserving native stride/layout; never memcpy T bytes or manufacture
a stride from an assumed record width.

Start with sorted runs of width one. Merge every adjacent pair into the other
complete buffer, alternating input/workspace roles between passes. Compare
(left,right), choose right only for Greater and choose left for Equal/Less.
Finish tails without comparisons. Each complete pass produces stable sorted
runs of doubled width; induction gives a stable final whole-value permutation.
If the final completed pass is in workspace, copy it back once before release.
All returned input items retain their original payload and cleanup identity.

Compute middle = low+min(width,n-low), high = middle+min(width,n-middle),
then advance low=high. After a pass, stop when width >= n-width; only otherwise
double width, proven smaller than n <= i32MAX. Do not form low+2*width or
unconditionally double a near-maximum signed width.

Helper comparison calls are at most n*ceil(log2(n)) for n >= 2; Natural may
perform two primitive lt checks per call. Copy/move work is O(n log n) and
workspace O(n*sizeof(T)), with constant control storage and no recursion.
No exact valid comparison trace, adaptive presorted speed or throughput ratio
is promised. Source/callback cost is separate and can be unbounded.

## Ownership and failure limits

The input owner keeps the sole nested cleanup authority. Workspace copies are
private borrowed observations and never cause nested Clone/Destroy calls.
Release only Vec backing. On success the selected input is one complete stable
permutation; all values outside it are unchanged. Ord/Comparator must describe
a consistent total order, preserve operands/backing and not reenter the sort or
mutate any source/workspace peer. Aliases stay inactive for the entire call.

Returned failures all precede source reads, comparator calls and mutation.
After preflight, comparator traps, invalid physical backing, concurrent/reentrant
mutation and process failure have no rollback or automatic workspace cleanup
guarantee. An intermediate input buffer need not be a complete permutation.
There is no automatic drop, move/lifetime checking or formal proof claim.

## Real application

Migrate only `sample_programs/library/sort_rows.lani`:

- Remove Row.ordinal and the comparator's source-position tie-breaker. Preserve
  the separate parsing ordinal used to recognize the first/header record.
- Use alloc::slice::sort_by over the same data View; Equal primary keys remain
  Equal in both directions, so the stable library supplies visible tie order.
- AllocationFailed -> status 4, CapacityOverflow -> 2, impossible Bounds or
  other internal storage contradictions -> 6. Verify successful count equals
  data-row count. All actual row owners retire once on every ordinary error.
- Preserve CLI/help/diagnostic, canonical CSV, complete output staging and the
  existing conservative comparison-work admission. The current factor
  4*N*(1+ceilLog2(N)) times numeric/text cost has spare headroom for merge sort;
  it does not imply the deleted ordinal comparison still runs.
- Preserve current argv lifetime policy rather than claiming a new empty-heap
  publication invariant. Scratch is released before output staging; Row Record
  owners still remain under Rows until its existing destruction boundary.

Reuse all four existing application groups (122 cases), then add a specifically
reached workspace ENOMEM case with status 4, no stdout, exact request binding
and matched observed cleanup. If calibration needs extra processes, report
those separately and update actual counts; do not conceal them as one run.
Identify the real workspace from source-bound size/lifetime evidence, never a
generic middle-map heuristic or a positive syscall return fabricated by a tool.

## Verification and work ownership

Root owns this plan, compiler/Cargo/native commands, reference generation and
commit/push. All commands stay below two minutes and native/compiler gates run
serially under the library lock. Authors own separate production, direct tests,
independent model, resources/scale, application, application tests, review and
documentation paths. They may run bounded CPU/static controls, not compiler,
Cargo or native executables. Admit a tiny both-form stable-record test first.

Require actual stable representative order and whole-value preservation for
natural and custom types; custom types need no Ord. Cover empty/singleton,
all-Equal, odd tails, duplicate-heavy/reverse/irregular lengths, successive
stable sorts, nonzero starts, actual native and packed layouts, zero-sized T,
invalid metadata/capacity admission, outside guards and reached reservation
failure before reads/callbacks/mutation. Capability rejections supplement runtime
behavior. Independently model stable output without reproducing merge passes.
Check manual nested owners, exactly one temporary backing allocation/release,
and large 257/4096/65536 workloads with finite comparison ceilings. App faults
and standalone documented examples have separate receipts.

Accepted target initially means native Linux x86_64 CPU output from the GPU
compiler. User-program GPU execution, other targets and formal verification
require separate support. Missing compiler support gets a minimal reproduction
and dependency report rather than a compiler repair in this increment.
