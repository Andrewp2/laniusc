# Checked slice order-statistic selection

This increment fills the missing nth-element operation in the portable slice
family. It supplies two complete public functions in `core::slice`, focused
runtime/model/owner tests and a real signed-integer selection program. The full
standard and extended library roadmap remains open.

## Public contract

```text
select_nth_unstable_by<T,C>(values:View<T>, nth:i32, comparator:&C)
    -> Result<View<T>,ViewError> where C:Comparator<T,T>
select_nth_unstable<T>(values:View<T>, nth:i32)
    -> Result<View<T>,ViewError> where T:Ord<T>
```

The natural-order function constructs `Natural<T>` and calls the same engine.
Both accept a zero-based index relative to the supplied View. Success returns
one borrowed View with the original backing, `start = values.start + nth` and
length one. This view carries no independent cleanup authority. Callers can use
existing subview operations for the before/after partitions.

Before reading elements, mutating storage or calling comparison, revalidate
start and length as nonnegative with nonoverflowing start+length, then require
`0 <= nth < length`. Every rejection is `ViewError::Bounds` and preserves all
backing and comparator state. Empty views always reject. A valid singleton
requires no comparison. Physical backing, native slice bounds and lifetime
remain caller obligations, as for other checked View algorithms.

For a lawful total comparator, the element at nth has that rank in the sorted
input: no before element is Greater and no after element is Less. Both sides
remain internally unordered. Equivalent elements have no stable representative
or relative-order guarantee. A complete permutation of whole shallow values
remains in the original view, and backing outside the view remains unchanged.
The returned View aliases that exact stored nth element, rather than a detached
value copy. Repeated selection may reorder the view and invalidate an earlier
selected-position interpretation.

The comparator's order, source elements and borrowed lifetimes must stay valid
and unchanged through interfering aliases/reentrancy. Instrumentation may count
calls without changing order. No allocation, cloning, destruction, implicit
cleanup transfer or host service occurs. Comparator traps/divergence can follow
partial permutation; there is no rollback or recoverable callback-error API.
Inconsistent comparator answers give no rank/partition or linear-cost promise;
loops still make structural progress if callbacks return and preserve storage.

## Algorithm and explicit stack

Use deterministic groups-of-five median-of-medians selection. This is the
classical selection family documented by
[NIST](https://xlinux.nist.gov/dads/HTML/select.html),
[Blum et al.](https://people.csail.mit.edu/rivest/pubs/BFPRT73.pdf) and
[Chen and Dumitrescu, section 2](https://arxiv.org/pdf/1409.3600).
The selected variant uses swaps, handles duplicates through a three-way band,
and represents recursive median selection with a fixed explicit stack.

1. An active frame stores half-open relative low/high, an absolute relative-view
   target index, and a phase. Ranges of at most five use insertion sort.
2. Otherwise sort consecutive groups of at most five, swap each middle element
   into the active prefix and select that prefix's middle rank. Include a final
   short group, using its floor(length/2) middle.
3. Suspend the parent while selecting its median prefix. The child length is
   `1 + (n-1)/5`; push only for n>5. Four i32 arrays of sixteen slots suffice:
   median-only descent from i32::MAX reaches length<=5 within fourteen active
   frames. Tail selection of a parent partition reuses that parent's frame.
4. Move the selected pivot to the active end, outside the scan. Three-way
   partition the other elements with a monotone scan and Greater boundary,
   then insert the protected pivot into the equal band. The band contains at
   least that pivot even under inconsistent comparisons, guaranteeing that
   either selected next range strictly shrinks or the frame completes.
5. A completed child reports its stored target position to its suspended
   parent. The root completes with the original nth position.

Use subtraction-based arithmetic for group ends and child counts; validate the
outer View once before any access. Relative active endpoints never exceed the
admitted length. Guard child existence before frame/index increments.

For a lawful total order, group sorting and partition are linear in active n;
median selection has size ceil(n/5), and the selected partition has size at
most 7n/10+O(1). This gives worst-case O(n) comparisons and swaps. The published
PICK constant is not a claimed bound for this implementation. The fixed stack
uses no allocation or native recursion. It is a bounded representation of the
usual O(log n) pending median work over this i32-indexed API.

## Real program

`select_value INDEX` reads signed decimal i64 tokens from stdin and prints the
zero-based ascending order statistic as decimal plus newline. Whitespace is
only ASCII SP/HT/CR/LF; token parsing delegates to `core::decimal`. Leading zeros
and optional plus/minus signs follow that parser; malformed/overflowing values fail.
Sole `--help`/`-h` prints help before reading data. INDEX is strict unsigned ASCII
decimal in 0..65535, at most 64 bytes, with no extra arguments.

Bound input to 1 MiB, tokens to 64 bytes and values to 65536. Read through a
fixed byte scratch area with an actual-read attempt cap of 8192, including
Interrupted. Exact input-cap boundaries require a genuine EOF observation;
an additional byte fails. Empty input and nth beyond the final count fail.
Keep one explicitly owned pre-reserved Vec<i64> of capacity 65536; check the
value cap before append, preventing growth during input. Use the public natural
selection operation and copy its selected scalar. Release argument owners before
allocating the Vec, release the Vec after copying that scalar, then format the
complete output using the decimal API and publish it.
Ignore SIGPIPE before publication; output attempts are bounded to 64 and
diagnostic attempts to eight. Borrowed standard descriptors are not closed.

Statuses: 0 success/help; 2 CLI/input/limits/rank; 3 input host errors; 4 allocation;
5 output/signal-policy; 6 internal contract failure. Preserve primary failures
through manual cleanup. No output is published on pre-publication errors.

## Acceptance and ownership

- Direct native admission for both functions; normal/empty/singleton/invalid
  logical ranges and nth, complete surrounding storage and comparator counters.
- Independent sorted-reference model checks rank, both partitions and complete
  permutation (never a particular permutation), including signed/full-width
  records, all-equal/duplicate/order-adversarial inputs, all small ranks and
  representative large inputs. Check actual native byte strides and subviews.
- Generic record/zero-sized/nested-owner cases preserve whole-value identity;
  actual owned storage is released exactly once after use. Pure selection
  phases have no host calls. A missing Comparator or Ord bound rejects at the
  marked use. No assertion of stability or exact callback schedule is added.
- Count comparisons over adversarial size families to detect quadratic growth;
  this finite evidence supplements the algorithm argument rather than proving
  complexity for every input. Check the sixteen-frame i32-domain bound with
  independent integer arithmetic; do not allocate i32::MAX-sized arrays.
- The real program has independent functional/CLI/limit and selected reached
  allocation/read/output-error tests. Verify actual output and cleanup; do not
  fabricate successful transfer counts or claim unobserved partial output.
- Selected existing slice-ordering regressions cover changed shared source.
  Root serializes compiler/Cargo/native runs under the existing GPU lock. Every
  command is below two minutes; no unrelated GPU or performance reruns.

Production is Lanius. Rust/Python are test drivers only. No compiler, IR,
extractor, proof, ABI or host binding changes belong here; missing support gets
a reproduction/control and a scoped dependency record. Preserve human README,
AI_POLICY and CONTRIBUTING. Guides/inventories belong under docs and generated
reference metadata; the generator never writes the root README.
