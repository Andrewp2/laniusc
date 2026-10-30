# Scoped map value updates

[`alloc::hash_map::HashMap<K,V>`](../stdlib/alloc/hash_map.lani) and
[`alloc::tree_map::TreeMap<K,V>`](../stdlib/alloc/tree_map.lani) expose
`update_value` for changing an existing value while preserving its stored key.
The [implementation plan](library-map-update-plan.md) fixes the contract.
All seven new library gates and four application groups/103 native cases pass
on the finite native Linux x86_64 profile. Earlier map and clone receipts retain their original API and source
scope.

The current Mapper path is `core::function::Mapper`. The
[lazy-outcome migration](stdlib-lazy-outcomes.md) records a selected current
regression separately; earlier receipts below keep their original source scope.

## API and lookup behavior

Both methods use the existing `core::function::Mapper` and `core::pair::Pair`:

```text
update_value<M,R>(&self, key:K, update:&M) -> Option<R>
    where M: Mapper<V,Pair<V,R>>
```

HashMap additionally requires its ordinary `K: Hash<K>` and `K: Eq<K>` bounds;
TreeMap requires `K: Ord<K>`. There is no comparison or cloning bound on V or R.
These are methods on the canonical map owners, with no separate entry handle
or callback protocol.

| Lookup | Callback | Map change | Return |
| --- | --- | --- | --- |
| Missing key | Never called | None | `None` |
| Present key | Exactly one `update.apply(stored_value)` | Install `Pair.first` in the same entry | `Some(Pair.second)` |

There is one ordinary lookup. On a present key, the callback receives a shallow
copy of V. On normal return, the map stores the returned V **before** returning
R to the caller. The exact stored representative key survives even when the
query key is an equivalent but distinct value. The query key remains the
caller's responsibility; the operation neither adopts nor destroys it.

HashMap retains its cached hash and bucket state. TreeMap retains its node
links, heights and free list. Both retain entry count, capacity and backing
allocation. After lookup, the map performs no additional key hash, equality or
ordering call, allocation, release, insertion, removal or rebalance. Callback
effects and key-operation effects retain their own contracts. These effect
limits apply to map-owned work: lawful user key operations may themselves
allocate, release resources or record observations, just as the mapper may.

`try_insert` still replaces the complete key/value entry and returns the
displaced pair. `update_value` never inserts a missing key. A caller that wants
to insert on absence must handle `None` and perform an ordinary checked
insertion, including its allocation and ownership outcomes.

## Borrowed-query updates

`update_value_by<Q,P,M,R>(query, policy, update)` extends the same value
reinstall contract to a distinct query type. The
[borrowed lookup guide](stdlib-borrowed-lookup.md) specifies the hash or tree
policy bounds and laws. All search-policy calls finish before the update
callback starts; a miss makes no update call. A hit preserves the exact stored
key and installs the latest V even when R is an error. The query remains
caller-owned and must stay valid throughout the operation, including when it
borrows backing reachable through V. The update must not invalidate that
backing. All nine borrowed-lookup library groups pass, including actual
String/Text owner tests and ordinary-error updates. The earlier receipts here
retain their same-key API/source scope.

### Current regression and representation scope

The shared-search migration exposed an overly strict assertion in the older
map-update fixture: a whole-allocation byte snapshot rejected changes in the
unused upper 32 bits of a u32 cached-hash storage word. A native diagnostic
preserved all logical keys, values, pointers and callback observations. Those
unused bits are not part of the update contract; retaining a cached u32 hash
does not promise identical inactive storage bytes.

The corrected fixture compares every public logical entry after each update,
checks each entry's `get_entry` findability and key callback-context identity,
and retains owner metadata, exact callback checks and the two-allocation
ledger. That focused regression
passes 1/1 in 5.84s at fixture `1c29664e`, recorded in
`target/stdlib-work/borrowed-lookup-regression-updates-semantic.log`.
The earlier failed run took 6.50s and is retained in
`borrowed-lookup-regression-updates.log`. This corrects the observer without
changing production code. The original finite representation observations
below retain their historical source scope.

## Value ownership and errors

The caller lends the callback exclusive authority over the stored V for the
duration of the call. The callback must return the latest valid V descriptor
in `Pair.first` on **every normal return**. Growing a String or Vec can relocate
its backing; returning the old descriptor would leave invalid storage in the
map. A callback that grows a child String inside a Vec must also reinstall that
child descriptor in the Vec before returning the Vec.

R is independent of that reinstall operation. In particular, choosing
`R = Result<T,E>` does not turn an error into rollback:

| Callback result | Installed value | Method result |
| --- | --- | --- |
| `Pair { first: latest, second: Ok(value) }` | `latest` | `Some(Ok(value))` |
| `Pair { first: latest, second: Err(error) }` | `latest` | `Some(Err(error))` |

A callback may preserve a value after a failed allocation, return a changed
valid value with an error, or replace V and return its displaced owner as R.
An owned error or other independent resource returned in R belongs to the
caller. R may instead borrow the installed value if its normal lifetime rules
are respected. Such aliases do not create another cleanup owner.

No implicit `Destroy` is called on the old V, new V, query key or R. The callback
must account for any value it displaces and must not retain duplicate cleanup
authority over the installed value. Deep destruction is appropriate only for
maps whose entries are independent owners under the relevant protocols; see
[HashMap clone/cleanup](stdlib-clone-hash-map.md) and
[TreeMap clone/cleanup](stdlib-clone-tree-map.md).

Changing a key's equality, hash or ordering meaning still requires transferring
the entry out and reinserting it afterward. Growing a value through a shallow
copy from `get` or iteration remains invalid when it leaves the stored
descriptor stale; use the scoped update or transfer the entry out first.

## Borrowing and callback obligations

End existing value borrows and cursors before updating. Keep the actual map,
mapper, key backing and callback context alive and stable throughout the call.
The callback must not access, reenter, mutate or destroy this map through any
alias. It must not change stored-key hash/equality/order through shared backing.
These obligations also apply when R reports a recoverable error.

The update offers no automatic lifetime checking, exclusive-borrow enforcement,
unwinding recovery or panic cleanup. A callback that does not return normally
does not reach the value reinstall. Forged map state, invalid backing and
violating callbacks remain outside the map contract. Explicit owner cleanup
continues to be required after ordinary success and failure paths.

## Costs and dependencies

| Map | Work, excluding key operations, value copies and callback work |
| --- | --- |
| HashMap | One ordinary lookup: expected O(1), worst linear in bucket count; constant reinstall |
| TreeMap | One O(log n) lookup; constant reinstall |

Only a present entry invokes the mapper. Map-owned lookup and reinstall work
need no temporary allocation or host service. Key hashing/equality/ordering and
mapper callbacks may allocate, release resources or call host services under
their own contracts; this API imposes no wall-time bound on those calls.
Existing map capacity and allocation
limits remain unchanged because the update creates no entry or storage.

The implementation stays inside each map module and uses its existing lookup
and storage operations. The initial verification target is Linux x86_64 CPU
output from the GPU compiler. Other hosts, GPU device programs, automatic
ownership and formal verification remain separate. No compiler or ABI change
is part of this increment.

Rust's [occupied hash entry](https://doc.rust-lang.org/std/collections/hash_map/struct.OccupiedEntry.html)
and [occupied ordered entry](https://doc.rust-lang.org/std/collections/btree_map/struct.OccupiedEntry.html)
separate value mutation from removal of the key/value pair. Lanius uses an
explicit returned descriptor to restore an owner after a scoped transformation;
its contract does not supply Rust's borrow checking or a complete Entry API.

## Consumers and verification status

The increment migrates [lex_scan](../sample_programs/library/lex_scan.lani)
frequency updates and adds [word_concordance](stdlib-word-concordance.md),
which groups words into `TreeMap<Text,Vec<u64>>` values and appends zero-based
byte positions. Words use the six ASCII whitespace bytes; keys borrow immutable
validated UTF-8 input and each positions vector is a separate manual owner.
The bounded program emits words in byte order with tab-separated position
lists, using fixed scratch rather than an output String.

The initial generic both-map admission passed one test in 7.64 seconds, with
a separate 2.97-second Rust build. It includes compound V/R shapes and verifies
that returning a Result error still installs the updated value. The receipt is
`target/stdlib-work/map-update-admission.log`; production hashes at that receipt
start `259e6440` (HashMap) and `fc671134` (TreeMap).

The migrated `lex_scan` existing selector
`real_cli_uses_csv_priority_maximal_spans_and_deterministic_kind_counts` passed
one test in 11.27 seconds, with a separate 2.35-second build. Its existing scope
covers 124 grammar inputs in both modes plus longest-match, tie, Unicode, CSV
and EOF boundaries. The receipt is `target/stdlib-work/map-update-lex-scan-regression.log`
at application source hash `00eb9813`; it is a selected regression, not a new
map-update model or an additional aggregate case count.

Two selected existing map regressions also pass against the new source:

| Existing selector | Test time | Separate Rust build | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `hash_map_models_collisions_and_executes_generic_payloads` | 16.64 s | 2.09 s | `map-update-hash-regression.log` |
| `tree_map_contracts_execute` | 16.09 s | 1.79 s | `map-update-tree-regression.log` |

Each passed one test. Together with `lex_scan`, these are three selected old
selectors with separate receipts; they do not add to the new API gate count.

All four direct groups are now accepted across separate runs: three execute
native programs and one checks five negative Mapper/key capability fixtures.
The [direct fixture guide](../tests/fixtures/stdlib_map_update/README.md)
records exact representative keys, one-lookup callback transcripts, logical
map contents and backing preservation, arrays, bool and zero-sized V/R shapes.
Its original concrete storage snapshots were finite observations, not a
portable inactive-byte guarantee; the current regression section above records
the corrected observer. The
mixed first direct run passed shapes and capability groups but failed to
compile the contracts fixture at an inferred tree constructor (LNC0006), taking
9.06 seconds after a 1.76-second build. Explicit constructor type arguments
fixed only that fixture; its focused retry passed one test in 6.88 seconds after
a 0.19-second build. Receipts are `map-update-direct.log` and
`map-update-contracts-revised.log` under `target/stdlib-work/`. Neither map
production source changed.

The [independent operation model](../tests/fixtures/stdlib_map_update_model/README.md)
passed one test in 6.90 seconds, with a
separate 1.60-second build, in `target/stdlib-work/map-update-model.log`.
Its 72 cases compare complete contents, representative keys and callback
events across 7,896 actions: 3,128 callbacks, 1,472 missing updates, 728 Result
errors, 884 present-None outcomes and 111,960 snapshot entries. It covers both
map families, two payload shapes and three hash modes with seed
`0x6a90261111`. These finite observations do not impose constraints on unrelated
user callback effects.

Both [live-owner resource gates](../tests/fixtures/stdlib_map_update_resources/README.md)
passed in 11.28 seconds after a 2.15-second Rust build, recorded in
`target/stdlib-work/map-update-resources.log`. Each map executes one baseline
and two reached callback-growth denials, at mmap ordinals 8 and 9: two baselines
and four fault/recovery processes total. Every process has ten successful
allocations and ten exact releases. The fixtures grow actual `Pair<Vec<u8>,String>`
values, verify the latest descriptor is installed before a Result error returns,
then recover in the same process. Separate owned errors and displaced values
remain usable after map destruction. This covers the two selected growth sites
per map; it is not an exhaustive callback-allocation campaign.

Thus all seven new library groups pass: three direct native groups, one group
of five capability rejection fixtures, one independent native model and two
native resource groups.

The [word-concordance application guide](stdlib-word-concordance.md) records
four accepted groups totaling 103 native process cases:

| Application group | Cases | Test time | Separate Rust build | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | ---: | --- |
| Independent output model | 28 | 7.12 s | 1.68 s | `map-update-concordance-model.log` |
| Argument/UTF-8 admission | 12 | 7.50 s | 0.19 s | `map-update-concordance-admission.log` |
| Input/distinct-word limits | 6 | 42.56 s | 0.19 s | `map-update-concordance-limits.log` |
| Allocation/I/O failures | 57 | 23.11 s | 0.19 s | `map-update-concordance-io.log` |

Each row is one registered test. The I/O group includes 38 reached allocation
failures. Its guide separates actual limit tests from the defensive 8 MiB
output ceiling, which is unreachable under the admitted 1 MiB input limit.
The standalone compiler command also exits 0 with an empty
`map-update-concordance-cli-build.log`; both examples pass with exact 18/21
output bytes, status 0 and empty stderr, recorded in
`map-update-concordance-cli-examples.log` under the same receipt directory.
Those examples do not add to the 103 cases.

All eleven new registered groups are accepted across these separate runs.
The three selected old regressions and standalone examples retain their own
scopes. This completes the selected map-update increment, with user-program
GPU execution, other targets, enforced lifetimes and formal proofs still
separate; the whole library goal remains open.
