# Allocation-backed stable slice sorting

The [fixed stable-sort contract](library-stable-sort-plan.md) adds two checked
View operations in [alloc::slice](../stdlib/alloc/slice.lani). All eight library
tests, all 123 migrated application cases and standalone build/examples pass
on the finite native Linux x86_64 profile. The existing [core slice ordering family](stdlib-slice-ordering.md)
keeps its allocation-free, unstable sort contracts; its earlier receipts do
not establish this new module. The full library goal remains open.

## API and comparison policy

```text
Error = Bounds | Storage(alloc::vec::Error)
sort<T>(values:core::slice::View<T>) -> Result<i32,Error>
    where T:core::cmp::Ord<T>
sort_by<T,C>(values:core::slice::View<T>,comparator:&C) -> Result<i32,Error>
    where C:core::ordering::Comparator<T,T>
```

Success returns the selected length. Equivalent items retain their order from
the original selected View, including for descending policies and strided
backing. Whole shallow values remain one permutation and outside-view values
remain unchanged. Stability refers to logical View order, not memory addresses.

Natural sort delegates to the same custom engine through canonical
core::ordering::Natural<T>. It may make two primitive lt calls per comparator
invocation. No Eq, PartialOrd, Clone or Destroy bound is implied. Native floats
need an explicit total policy or [total float keys](stdlib-comparison.md).
The comparator must provide a consistent total order and preserve operands.

The primary [Rust stable slice contract](https://doc.rust-lang.org/std/primitive.slice.html#method.sort_by)
supplies the stability/total-order model. The
[Sedgewick/Wayne bottom-up merge reference](https://raw.githubusercontent.com/kevin-wayne/algs4/master/src/main/java/edu/princeton/cs/algs4/MergeBU.java)
supplies iterative growing-run merging. The typed buffers, alternating passes,
checked arithmetic, allocation errors and manual owners below are Lanius's
variant; no adaptive-input or Rust unwind guarantee is inherited.

## Admission and returned failures

1. Revalidate start >= 0, length >= 0 and start <= i32MAX-length. Bounds wins
   before payload reads, comparator calls, allocation or mutation. Logical
   checks do not establish physical backing, initialized values or lifetimes.
2. A valid length zero or one returns Ok(length), with no payload read,
   comparison or allocation. This precedes workspace capacity admission.
3. For length >= 2, reserve exactly length entries in one fresh private Vec<T>
   before reading the input or calling the comparator. Preserve reservation
   errors as Storage(error), without touching source state or callback context.
4. A nonzero-sized successful reservation makes exactly one backing allocation;
   copying/merging makes no more, and releases that backing once before return.
   Zero-sized T reserves logical capacity without host memory, but still uses
   the normal comparator/merge engine for a nontrivial length.

The existing Vec cap is floor(2147483647/size_of<T>()) for nonzero-sized T and
i32MAX for zero-sized T. CapacityOverflow precedes a host allocation attempt;
AllocationFailed reports an attempted reservation failure. All returned Errors
preserve the entire input and its metadata, including values outside the View.
There is no presortedness scan before reservation. An impossible failure of an
already-reserved internal push asserts its owner invariant rather than being
ignored or converted to success.

## Typed workspace and stable passes

Initialize every workspace entry through typed reserved pushes before exposing
its initialized view. Never treat spare capacity as initialized. The source
and workspace may have different physical strides; every copy uses typed
indexes through the actual descriptors, without raw byte copying or an assumed
record layout.

Start with runs of width one. Each pass merges adjacent runs into the other
complete buffer, alternating workspace/input roles. Compare (left,right),
choose right only for Greater and choose left for Less or Equal. Copy tails
without comparisons. A completed pass yields stable runs of doubled width;
copy the final completed workspace back once if necessary, then release it.

For each pair, compute middle=low+min(width,n-low), then
high=middle+min(width,n-middle), and advance low=high. After the pass, stop when
width >= n-width; only otherwise double width. No low+2*width or overflowing
signed doubling is needed, even at the i32 domain boundary.

For n >= 2, helper comparator calls are at most n*ceil(log2(n)). Copy work is
O(n log n), workspace O(n*sizeof(T)), and control storage is constant with no
recursion. Source/comparator work can be unbounded. No exact valid comparison
trace, presorted-input speedup or throughput ratio is promised. Callback
allocation or host effects are separate from the helper's workspace counts.

## Owners and non-returning failures

The input owner keeps the sole nested cleanup authority. Workspace entries are
temporary shallow observations, not independent owners. No nested Clone or
Destroy runs; release only the private Vec backing. Keep original owners,
storage and comparison context alive, and keep all other aliases inactive
through the call. Reentry or concurrent source/workspace mutation is invalid.

All returned failures occur before source reads, callbacks and mutation. A
comparator trap, invalid physical backing, process failure or invalid alias
mutation after admission has no rollback or automatic workspace-cleanup
guarantee. During an incomplete merge pass the input need not be a complete
permutation. There is no automatic drop, move/lifetime checking or formal proof.

## Application and acceptance scope

The [sort_rows migration](stdlib-sort-rows.md) removes Row.ordinal and its
secondary tie comparison. Equal primary keys remain Equal in both directions;
the stable library supplies source-order ties. Parsing/header position remains
separate. Workspace AllocationFailed maps to status 4, CapacityOverflow to 2,
and impossible Bounds/storage contradictions to 6. Success must return the
actual data-row count. Existing CLI, CSV, output staging and conservative work
admission stay explicit in the application guide.

Scratch is released before output staging. Rows still owns each Record until
its existing destruction boundary, and the current argv lifetime policy is
preserved. This migration does not promise an empty heap at publication.
The older 122-case application receipt used ordinal tie emulation and remains
historical; it does not establish this source or workspace-allocation failure.
The migrated source 9fd332e4 passes all four application tests in 12.95s
(stable-sort-sort-rows-first.log): model37/CLI39/rejection33/I/O14, 123 cases.
This includes one specifically identified workspace ENOMEM case with exact
observed cleanup.
The documented standalone compile exits zero silently
(stable-sort-sort-rows-standalone.log). The header/numeric/reverse and text-tie
examples exit zero with empty stderr and exact 56/54-byte quoted CRLF outputs.
These examples overlap the 123-case corpus and add no distinct cases.

Current production alloc::slice is e56129df. Both-form native admission passes
one test in 7.35s (stable-sort-admission-first.log under target/stdlib-work;
separate Rust build 1.80s). The 17-record natural/custom fixture checks stable
IDs, whole payloads and outside guards, with two exact workspace allocations
and releases across its two calls. This is the first native attempt.

The remaining direct gates pass three tests in 14.68s, admission filtered
(stable-sort-direct-first.log). All four direct tests are accepted across the
two commands: three native tests and one capability group containing four
marked rejections. Negative compilation checks supplement runtime behavior.

The independent model passes its first attempt: one test in 8.43s
(stable-sort-model-first.log), with 5,946 cases / 9,942 actions, two families,
two backing forms and seed 0x57ab1e0261104, producer 7c9be6d8. Whole-record
stable-output and permutation expectations are checked against an independent
reference; production remains e56129df.
Model payload lengths are at most 65; large workloads have separate gates.
Eight serialized-output verifier corruptions are CPU controls, not production
mutants or native coverage counters.

The owner gate passes one test in 7.50s (stable-sort-owners-first.log), with
56 nested backings, one outer backing, four workspace allocations and five
pure phases: 61 successful mappings overall. The scale gate passes one test
in 8.11s (stable-sort-scale-first.log): 36 complete stable outputs at lengths
257/4096/65,536, six families and both APIs. It observes 36 scratch allocations
and a release ledger of 38 overall. Maximum observed custom comparison and
natural lt counts divided by n*ceil(log2(n)) are 0.9349460601806641 and
1.6900749206542969 respectively; these have different operation units and
respective ceilings of n*ceil(log2(n)) and twice that. These finite work counts
are not a throughput or compiler-speed benchmark.

The corrected guarded/failure gate passes one test in 8.79s
(stable-sort-workspace-failures-corrected.log): two reached workspace ENOMEM
failures and 24 guarded cases over six lengths/four layouts with two protected
pages. In the first 9.38s test attempt, the guarded native process failed a
fixture assertion before its sort: that fixture's native [i32;20] array stride
is +4, not negative. Changing only that expectation
fixed the fixture; production/compiler sources did not change. The three
resource tests establish five native lifecycles across separate commands.

All eight registered library tests are accepted: seven native tests and one
capability group with four marked rejections. Existing core sort and comparison
receipts retain their source/API scope. No compiler repair or new compiler
dependency is claimed. Future unsupported compositions require a narrow
reproduction and dependency report.
The [direct](../tests/fixtures/stdlib_foundation/stable_sort/README.md),
[model](../tests/fixtures/stdlib_foundation/stable_sort_model/README.md) and
[resource](../tests/fixtures/stdlib_foundation/stable_sort_resources/README.md)
fixture guides retain exact commands, tested identities and failure histories.

Accepted execution is native Linux x86_64 CPU output from the GPU compiler,
using the current typed Vec/allocator profile. Other targets, user-program GPU
execution, automatic ownership and formal verification need separate support.
