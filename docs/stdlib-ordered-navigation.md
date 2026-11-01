# Ordered navigation and bounded ranges

TreeMap and TreeSet answer predecessor queries, accept heterogeneous queries
for every ordered bound, traverse intervals whose ends can each be included,
excluded or absent, and remove, extract or split off such intervals. Sixteen
navigation methods, ten interval edit methods and one value type,
`core::range::Bound<T>`, make up this work. It completes the
"heterogeneous ordered bounds and ranges" item that the
[borrowed point-lookup guide](stdlib-borrowed-lookup.md) left separate.
All searches reuse the existing AVL storage and cursors and allocate nothing;
only a nonempty extraction allocates, once.

## Methods

`K` is the map key type, `Q` a query type and `P` its policy. Sets use the
element type `T` in place of `K` and return `Option<T>` or `Cursor<T>`
instead of entries.

| Owner | Method | Result |
| --- | --- | --- |
| TreeMap and TreeSet | `last_at_most(key)` | Greatest stored key `<= key` |
| TreeMap and TreeSet | `last_below(key)` | Greatest stored key `< key` |
| TreeMap and TreeSet | `lower_bound_by<Q,P>(query, policy)` | First stored key not Less than the query |
| TreeMap and TreeSet | `upper_bound_by<Q,P>(query, policy)` | First stored key Greater than the query |
| TreeMap and TreeSet | `last_at_most_by<Q,P>(query, policy)` | Last stored key not Greater than the query |
| TreeMap and TreeSet | `last_below_by<Q,P>(query, policy)` | Last stored key Less than the query |
| TreeMap and TreeSet | `range_bounds(lower: Bound<K>, upper: Bound<K>)` | `Result<Cursor, Error>` |
| TreeMap and TreeSet | `range_bounds_by<Q,P>(lower: Bound<Q>, upper: Bound<Q>, policy)` | `Cursor` |

The same-key methods require `K: core::cmp::Ord<K>`. The `_by` methods
require `P: core::ordering::Comparator<K,Q>`, called with the **stored key
first, query second**, and add no K or Q comparison bound. Every bound
applies even to an empty collection. The existing `lower_bound`,
`upper_bound`, `range` and point lookups keep their signatures, calls and
receipts.

```lani
import core::range;

let lower: core::range::Bound<i32> = core::range::Bound::Included(10);
let upper: core::range::Bound<i32> = core::range::Bound::Included(2147483647);
let tail: alloc::tree_map::Cursor<i32, u64> = map.range_bounds(lower, upper).unwrap();
let before: core::option::Option<alloc::tree_map::Entry<i32, u64>> = map.last_below(10);
```

`Bound<T>` has the variants `Included(T)`, `Excluded(T)` and `Unbounded`. It
stores its value shallowly and compares nothing itself. A half-open
`range(lower, upper)` cannot include `i32::MAX`; `Included(MAX)` can.

## Query order

A navigation policy must order the stored keys as a run of Less, then a run
of Equal, then a run of Greater, consistently with the stored-key order.
Unlike point lookup, the Equal run may contain **several** keys: a query can
denote a contiguous family such as every String with a given prefix, or
every key inside a band of values. The four searches then select the ends of
those runs:

| Search | Selected entry |
| --- | --- |
| `lower_bound_by` | First key of the Equal run, else the first Greater key |
| `upper_bound_by` | First Greater key |
| `last_at_most_by` | Last key of the Equal run, else the last Less key |
| `last_below_by` | Last Less key |

Interval bounds use the same runs. `Included(q)` as a lower bound starts at
the first key that is not Less than q; `Excluded(q)` starts after the whole
Equal run. As an upper bound, `Included(q)` ends with the last key that is not
Greater than q and `Excluded(q)` ends before the Equal run. Thus
`range_bounds_by(Included(p), Included(p), policy)` traverses exactly the
Equal run of p.

These are caller preconditions; the collection does not check them. With a
policy that is not monotone over the stored order, selections and range
contents are unspecified. Each descent still ends after at most the tree
height, and a cursor still yields only stored entries and terminates.

## Exact calls

Each search is one root-to-empty-child descent. The policy runs once per
visited node, so a search makes at most the AVL height (about
1.44 log2(n + 2)) calls. An empty collection calls nothing.

`range_bounds_by` calls in this order:

1. The lower descent, unless the lower bound is Unbounded (the front is then
   the first stored key).
2. Nothing more if no front key exists, or if the upper bound is Unbounded
   (the back is then the last stored key).
3. One check of the front key against the upper bound. If the front lies
   above the upper bound, the cursor is empty and no further call occurs.
4. Otherwise the upper descent, which finds the back key.

Bounds that admit no common key give an empty cursor. Reversed
heterogeneous bounds are not detected separately: the policy cannot compare
two queries, so they are just another empty interval.

`range_bounds` compares the two bound values with `K::lt` when both are
present. It returns `Err(InvalidRange)` only when upper is strictly less than
lower. Equal values with either bound excluded give an empty cursor; equal
included values give at most one entry. It then follows the same sequence
through the natural order, which calls `lt(query, stored)` and, when needed,
`lt(stored, query)` per visited node.

## Cursors, ownership and work

The returned cursors are the existing `Cursor<K,V>` and `Cursor<T>`. They
borrow the collection, consume one shared non-crossing remainder from either
end and return None repeatedly from both ends after exhaustion. Successful
edits invalidate them. Bound values and queries are read only while the cursor
is constructed and are not retained.

Navigation returns shallow copies of stored entries or representatives, as
the existing getters do; nested key or value backing stays borrowed and must
outlive later use. No method mutates the collection, transfers ownership,
allocates, frees or makes a host call. Policies observe their operands for the
duration of one call, must not reenter or mutate the collection and must not
retain operand descriptors. Their own instrumentation is theirs.

## Prefix families of owned Strings

`alloc::string::TextPrefix {}` is a zero-sized `Comparator<String,Text>`:
a stored String that begins with the query bytes is Equal, and any other is
ordered against the query by unsigned bytes. Prefix families are contiguous
in byte order, so this policy satisfies the navigation law above:

```lani
let prefix: alloc::string::TextPrefix = alloc::string::TextPrefix {};
let family: alloc::tree_set::Cursor<alloc::string::String> =
    words.range_bounds_by<core::text::Text, alloc::string::TextPrefix>(
        core::range::Bound::Included(query), core::range::Bound::Included(query), prefix.borrow());
let before: core::option::Option<alloc::string::String> =
    words.last_below_by<core::text::Text, alloc::string::TextPrefix>(query, prefix.borrow());
```

The empty prefix makes every String Equal. `core::text::TextPrefix` is the
same policy for stored `Text` keys (`Comparator<Text,Text>`); the
[sorted word lookup](stdlib-look-words.md) application uses it over borrowed
input words. TextPrefix is not a point-lookup
policy, because one prefix can match several keys; use `TextKey` with
`get_by` and the other point methods. Matching is exact bytes, with no case
folding, normalization or locale collation.

## Range removal, extraction and split_off

| Owner | Method | Result |
| --- | --- | --- |
| TreeMap and TreeSet | `remove_range(lower: Bound<K>, upper: Bound<K>)` | `Result<i32, Error>`: entries removed |
| TreeMap and TreeSet | `remove_range_by<Q,P>(lower: Bound<Q>, upper: Bound<Q>, policy)` | `i32` |
| TreeMap and TreeSet | `try_extract_range(lower: Bound<K>, upper: Bound<K>)` | `Result<TreeMap<K,V>, Error>` (sets: `Result<TreeSet<T>, Error>`) |
| TreeMap and TreeSet | `try_extract_range_by<Q,P>(lower: Bound<Q>, upper: Bound<Q>, policy)` | Same |
| TreeMap and TreeSet | `try_split_off(at: K)` | Keys `>= at` move to the result; smaller keys stay |

Each method selects exactly the entries that `range_bounds` or
`range_bounds_by` with the same arguments would traverse, with the same
bounds, the same InvalidRange rule and the same policy calls; no further
policy or `Ord` call follows. `try_split_off(at)` is
`try_extract_range(Included(at), Unbounded)`.

**Removal** deletes the selected entries from the back of the interval
towards its front and returns how many it removed. Like `clear`, it discards
keys and values shallowly and runs no destructor, so use it only when the
removed entries own nothing, or extract them instead. It never allocates or
frees: capacity is retained and freed nodes join the free list for later
inserts. Removal costs O(k log n) for k removed entries.

**Extraction** counts the interval, allocates one new owner of exactly that
capacity, copies the entries into it in order, links them as a balanced tree
in O(k), and only then removes them from the source. The new owner receives
the cleanup authority of every moved key and value, which the source gives
up; each nested owner is released exactly once by whichever owner holds it
last. An empty interval allocates nothing and returns an empty owner with
capacity 0. Failure is `Err(AllocationFailed)`, `Err(CapacityOverflow)` or,
for same-key bounds with upper strictly below lower, `Err(InvalidRange)`; every
failure leaves the source, its capacity, storage and cursors unchanged. The
source keeps its capacity after a successful extraction.

```lani
let upper: alloc::tree_map::TreeMap<i32, u64> = map.try_split_off(1000).unwrap();
let removed: i32 = map.remove_range(core::range::Bound::Excluded(10), core::range::Bound::Unbounded).unwrap();
```

A successful removal or extraction is an edit and invalidates cursors of the
source. Policies follow the navigation rules above.

## Evidence

Fixtures are under `tests/fixtures/stdlib_ordered_navigation`; see the
[direct](../tests/fixtures/stdlib_ordered_navigation/direct/README.md) and
[model](../tests/fixtures/stdlib_ordered_navigation/model/README.md) guides.
Two registered tests drive them:
`tests/stdlib_ordered_navigation_execution.rs` (contracts, interval edits and
four capability rejections) and
`tests/stdlib_ordered_navigation_model_execution.rs`.

The receipts below came from the prebuilt `laniusc` command-line compiler
(`--stdlib-root stdlib`, native Linux x86_64 output), one GPU job at a time.
The registered Rust tests type-check (`cargo check`) but were not executed
in this increment, because building their test binaries exceeds the
five-minute command limit; their expected summary and allocation count are
the values below.

- **Model.** 48 cases and 10,565 commands over TreeMap and TreeSet with
  i32-identity keys, including the i32 extremes and a reset/clear in the
  middle of cases. The oracle (a Python dict, sorted per query, with no tree)
  checks 1,005 same-key and 1,188 policy navigations, 815 same-key ranges
  (295 reversed InvalidRange) and 1,726 policy ranges, 20,923 cursor pulls
  of which 5,637 come from the back, and 2,878 snapshot entries. It also
  checks 329 range removals (1,601 entries) and 278 extractions and splits
  (1,106 entries): the removed count, the extracted entries in order, the
  remaining source, and the capacity rules (source capacity unchanged,
  extracted capacity exact, zero when empty). All 16 navigation hit/miss
  routes and all 36 bound-kind/empty range routes occur; 49 navigations use
  an Equal run of more than one key. Each of the 7,592 policy calls (2,467
  descents and 799 front checks), including those of removal and extraction,
  is checked as a lawful descent: every visited key is stored, each step
  narrows an open interval in the direction its answer implies, the final
  interval holds no stored key, the visit count respects the AVL bound, and
  one unchanged tree has one root. Nine host-only corruption controls
  (unstored, dropped, swapped, repeated and mis-roled calls; swapped, missing
  and re-stamped range items; truncated output) are each rejected.
  Three deliberately broken engines (strict upper search accepting Equal; the
  front check removed; removal stepping to the predecessor after each removal
  instead of before it) all fail the model.
- **Contracts.** Exact call counts on the perfect 15-key tree (four per
  descent, nine for a nonempty bounded range, five when the front check
  fails, zero for an empty map or two Unbounded ends), Included/Excluded
  equal points, reversed bounds, two-ended pulls, full-domain i32 intervals
  including MAX, InvalidRange precedence, TreeSet forms, and TextPrefix
  families over owned String sets and maps with neighbor queries. The
  fixture checks in-program that navigation leaves every owner field
  (storage pointer, capacity, used/length, root, free list) unchanged and
  that all twelve String owners are released exactly once. No tracer runs;
  an earlier one-time trace of the first fixture revision saw 17 mmap
  allocations, each released.
- **Interval edits.** `edits.lani` builds a 40,000-entry map and set, then
  lowers its own RLIMIT_AS soft limit to 1 MiB through `prlimit64`. The
  runtime allocator still serves small requests from memory it already
  holds, so the fixture first shows that a fresh 20,000-node owner is refused
  and then attempts only extractions of at least that size: range, policy
  range and split_off extraction all return AllocationFailed and leave every
  owner field and the full contents unchanged. In the same phase an empty
  extraction succeeds with capacity 0, reversed bounds give InvalidRange
  before anything else, and same-key and policy removals and navigation
  succeed with storage and capacity unchanged. After the limit is restored,
  extractions and splits of maps and sets have exact capacities and
  contents, the source keeps its capacity and refills without growth, a
  split owner accepts inserts and navigation, and eight String values moved
  across an extraction are each released exactly once. 0.96 s natively.
- **Capability rejections.** Four fixtures (missing comparator, query-first
  comparator, `range_bounds` without Ord, `last_at_most` without Ord) all
  fail with LNC0008. With the prebuilt compiler their primary label points to
  `stdlib/core/slice.lani:899` rather than the marked call line, exactly as
  the already-accepted borrowed-lookup negative fixtures now do with that
  compiler, so the registered test's label assertion was not confirmed here.
- **Regressions.** On these sources, `tree_map_basic`, `tree_map_types`,
  `owned_sets_contracts`, `owned_sets_types`, the three borrowed-lookup direct
  programs and the borrowed-lookup model (unchanged summary) all pass.

The [sorted word lookup](stdlib-look-words.md) application is the real
consumer: prefix families, neighbors and inclusive Text intervals, with four
registered groups (126 process cases).

Logs are under `target/claude-work/s1` in the authoring worktree. The finite
target is native Linux x86_64 CPU output; no GPU-device, other-target,
proof or automatic-lifetime claim follows.
