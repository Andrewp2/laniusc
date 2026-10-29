# Selection ownership and comparison-growth fixtures

Both registered gates passed compiler/native acceptance: two tests in
14.53 seconds, recorded in
`target/stdlib-work/slice-selection-owner-scale-first.log`. Root performed all
executable commands. These fixtures test the two public checked selection functions in
the [selection contract](../../../../docs/library-slice-selection-plan.md).
They do not assert a particular unstable permutation or the identity of an
equivalent selected element.

The owned fixture observed all 57 actual mappings and exactly matching releases
across five pure phases. The scale fixture observed two mappings, 180 pure
phases and all 180 successful rank/partition/permutation observations. Full
syscall tracing accepted both lifecycles and observed no host service inside
any selection phase.

## Generic values, actual owners and returned aliases

`owners.lani` uses generic `Record<Bundle<Leaf>>` values. Fourteen records
include twelve selected elements and two untouched outside guards. Every
record owns two UTF-8 Strings and two Vec<u64> buffers; one outer record Vec
owns their slots. There are **57 actual allocation owners**: 56 distinct
nested buffers and the outer backing. Strings include NUL and multibyte UTF-8;
numeric payloads include values above 2^63 and near u64::MAX.

The fixture snapshots every nested allocation pointer and capacity, then
checks complete payload contents, lengths, capacities, serials and record IDs
after permutation. Both nested sides have independent actual storage. Cleanup
authority remains in the final record slots; temporary shallow comparator
arguments and selected Views never acquire independent cleanup authority.
No Clone or Destroy implementation is provided for these record types.

There are **five pure P/p phases**:

1. Zero-sized Unit selection through both public functions at every rank of
   a seven-element offset View; actual native stride is zero.
2. Ascending custom selection at rank zero.
3. Ascending custom selection at rank five.
4. Descending custom selection at rank six.
5. Natural ascending selection at rank eleven.

The owned selected range has three elements of each key 0..3, so literal
expectations check the selected rank independently of the returned layout.
Every owned-record phase checks both partitions and exact ID permutation. The selected
View has length one and original-relative start. Updating a scalar `edits`
field through that View must update the original nth slot, while all ownership
metadata and contents remain intact. Earlier selected Views are not reused
after another selection can rearrange slots.

The final slot traversal releases every nested String/Vec exactly once, then
releases the outer backing last. The host trace ledger independently matches
every actual mapping address and extent to one successful release. A D marker
is accepted only after no mapping remains. This is a finite fixture ledger,
not an automatic resource checker or general ownership proof.

## Adversarial sizes and comparison observations

`scale.lani` executes **180 selections**: sizes 257, 4096 and 65536; six input
families; five ranks; and both public functions. The six families are ascending,
descending, eight-way duplicates, organ pipe, sawtooth modulo 97, and a seeded
affine permutation `(index * 40503 + 17) mod size`. The selected size domains
are coprime with that multiplier. Ranks are 0, 1, size/2, size-2 and size-1.
Every selection starts from a newly populated original family, rather than
using a previous partition as the next adversarial input.

Two actual Vec backings are allocated once and reused: compound generic
records and ID flags. Selection uses an offset interior View. Every complete
record retains its ID-derived wide payload, and adjacent outside guards must
remain unchanged. Native assertions check both partitions, every exact ID
once, ID sum/sum-of-squares and returned-alias identity. The host separately
sorts the generated scalar key sequence and checks every reported rank.

Each 24-byte little-endian report supplies size, family, nth, API, observed
comparison count and selected key. All 180 tuples must be distinct and present.
Custom comparator calls have a ceiling of **100n**; the natural adapter's
instrumented `Ord.lt` calls have a ceiling of **200n**. Natural ordering may
make two lt calls for one comparison. These generous finite ceilings detect
large growth regressions without asserting an exact callback schedule.

A CPU-only independent recursive/list median-of-medians preflight checked
90 family/size/rank cases against sorted values. It sorts separate groups,
selects their median recursively and materializes less/equal/greater lists;
it does not model the production engine's in-place swaps or explicit stack.
Its maximum comparison counts per n by family were approximately 5.761,
5.735, 5.548, 5.621, 6.771 and 8.210. These observations informed the generous
ceilings; they are not native results or a proof that every input is linear.
No published PICK comparison constant or wall-clock throughput guarantee is
claimed.

The accepted native scale run observed a maximum of
**9.369766235351563 custom comparator calls per n** and
**12.4439697265625 natural-order lt calls per n**. These are distinct counters;
they are not interchangeable comparison metrics. All 180 cases stayed below
their respective finite ceilings. The combined test elapsed time includes
compilation, tracing, setup and cleanup and is not a throughput measurement.

## Executable boundaries

The driver first requires genuine x86_64 ELF and shared strict jump admission.
It traces all syscalls, rejects every host call inside P/p, matches all actual
mapping/release addresses and extents, and permits only process entry/exit,
explicit markers, scale reports and the expected allocation lifecycle outside
those phases. The owned fixture has five phases/57 owners; the scale fixture
has 180 phases/two owners. A 90-second whole-native lifecycle limit is a test
deadline, not a performance measurement.

Accepted executable scope is finite Linux x86_64 CPU output from the GPU
compiler. Huge i32-domain arrays, GPU-device execution, arbitrary lawful or
inconsistent callbacks, automatic ownership and formal verification are
unclaimed here. Smaller physical layouts, invalid metadata and the algorithm's
explicit-stack arithmetic have separate direct/model acceptance.

| Executed source | SHA-256 |
| --- | --- |
| `owners.lani` | `93788d287427ab16509fc20371296bd05651f9820770abd9f82ba908b8e80104` |
| `scale.lani` | `80d8ed56f886d256d9d562d6b8bf017f040f19139c2614041bb213fb0a90423b` |
| Rust driver, tested before formatting | `23cff3ebd87937e060e720690d6be9686e78fd88115d2ac6ddc9ea282d8e4a69` |

```text
cargo test --test stdlib_slice_selection_owner_execution generic_selection_preserves_nested_owners_zero_sizes_and_selected_aliases -- --exact
cargo test --test stdlib_slice_selection_owner_execution selection_adversarial_scale_preserves_rank_permutation_and_linear_comparison_ceiling -- --exact
```
