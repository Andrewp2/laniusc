# Lazy map updates and insertion

[`alloc::hash_map::HashMap<K,V>`](../stdlib/alloc/hash_map.lani) and
[`alloc::tree_map::TreeMap<K,V>`](../stdlib/alloc/tree_map.lani) add a scoped
operation that updates an existing value or constructs a missing entry.
Existing keys keep their stored representative. A missing entry is built only
when needed; validation or storage failures return that candidate intact.

All six library gates pass on Linux x86_64: five runtime tests and one group
of five capability rejections. The migrated application passes four groups /
104 native cases, with two existing insertion regressions separate. Earlier
map-update receipts retain their original source scope.

## API and outcomes

Both maps expose the same method shapes, using their own `Entry`, `Error` and
`UpdateError` types:

```text
try_update_or_insert<F,M,R,E>(query:K, initialize:&F, update:&M)
    -> Result<Option<R>,UpdateError<K,V,E>>

try_update_or_insert_by<Q,P,F,M,R,E>(query:Q, policy:&P, initialize:&F, update:&M)
    -> Result<Option<R>,UpdateError<K,V,E>>

F: Producer<Result<Entry<K,V>,E>>
M: Mapper<V,Pair<V,R>>

UpdateError<K,V,E> {
    Initialize(E),
    KeyMismatch(Entry<K,V>),
    Storage(Error,Entry<K,V>)
}
```

`Producer` and `Mapper` are the borrowed, statically dispatched traits in
`core::function`. Creating a producer is eager; calling its `produce` method
is lazy. The producer returns the complete key/value entry, so a borrowed
query can find an existing owned key without first allocating a replacement.
There is no comparison, cloning or destruction bound on V, R or E.

| Path | Callbacks | Result and ownership |
| --- | --- | --- |
| Key exists | Update once; no initialization | Install the returned V and return `Ok(Some(R))` |
| Key missing; initialization fails | Initialize once; no update | Return `Err(Initialize(E))`; map unchanged |
| Key missing; candidate fails validation | Initialize once; no update | Return `Err(KeyMismatch(candidate))`; map unchanged |
| Key missing; storage fails | Initialize once; no update | Return `Err(Storage(cause,candidate))`; map unchanged |
| Key missing; insertion succeeds | Initialize once; no update | Map adopts candidate; return `Ok(None)` |

The query is an observation, not the entry being transferred. Only the
producer's candidate is adopted on insertion. On a hit, the operation shares
the [scoped update contract](stdlib-map-updates.md): it preserves the exact
stored key, cached hash or tree links, count, capacity and backing allocation.
Map-owned work makes no allocation on that path. All search calls finish before
the updater starts, and its latest V is installed before R returns.

In particular, `R = Result<T,UserError>` is independent of the outer Result.
`Ok(Some(Err(error)))` means the occupied update returned an error after its
latest value was installed. It does not roll back callback effects. A vacant
entry's initial value is the producer's value; the updater does not run on it.

On a miss, initialization and candidate validation finish before any map
reservation or publication. Each outer error preserves the original entries,
count, capacity and backing. A successful insertion may grow or rebuild map
storage. The query search location is reused; this is not a second
replacement-capable insertion after a failed lookup.

## Keys and borrowed queries

The same-type methods require ordinary map keys: `K: Hash<K> + Eq<K>` for
HashMap and `K: Ord<K>` for TreeMap. The `_by` methods retain those K bounds and
also require:

| Map | Borrowed-query bounds | Candidate validation |
| --- | --- | --- |
| HashMap | `Q: Hash<Q>`, `P: Mapper<Pair<K,Q>,bool>` | Candidate hash equals query hash, then policy accepts candidate/query |
| TreeMap | `P: Comparator<K,Q>` | Policy compares candidate/query as `Equal` |

The policy receives the stored or candidate key first and the query second.
HashMap hashes the query once, including for an empty table. It hashes a
candidate only after successful initialization. A detected hash mismatch
short-circuits the candidate equivalence check. Same-type candidate checks
use the corresponding natural key operations.

The [borrowed lookup laws](stdlib-borrowed-lookup.md) still apply. Query
identity, key identity and hashes must remain stable throughout the call.
Every matching key must hash like its query. A query identifies one natural
key equivalence class, and all policy observations must agree with that class.

Insertion also requires that the candidate belongs at the saved query
location. For TreeMap, comparison of **every stored key** against the query
must have the same ordering as comparison against the produced key. A policy
that returns `Equal` for the candidate can still violate this law elsewhere.
`KeyMismatch` reports the finite candidate check; it does not certify an
arbitrary policy or establish its consistency with natural key operations.

No exact comparison-count guarantee is added. Search, initialization and
candidate validation may call user operations with their own costs and lawful
observations. Ordinary map invariants and policy laws remain prerequisites.

## Owners and callback obligations

End prior map borrows and cursors before either method. Keep the actual map,
callback contexts and query backing alive through lookup, callback execution
and candidate validation. All callbacks, including key operations and the
initializer, must not access or reenter this map through an alias, destroy it,
or change key identity. They must not invalidate query backing while the call
still needs it. These obligations are manual.

The updater receives exclusive authority over the stored V for its call and
must return the latest valid descriptor in `Pair.first` on every normal
return. It must account for any displaced owner. An R that borrows the installed
value is subject to that value's lifetime and creates no second cleanup owner.

The initializer must clean up partial work before returning an error, or
transfer that work through E. A successful initializer transfers one complete
candidate: to the map on success, or to the caller inside `KeyMismatch` or
`Storage`. The caller may retry with or destroy a rejected candidate. Producer
contexts must not keep duplicate cleanup authority over that same entry.

The operations do not call `Destroy`, clone keys or values, or clean up returned
errors. They supply no automatic borrow checking, panic/unwind cleanup or
rollback when user code does not return normally. The unchanged-map guarantee
does not undo side effects in callback contexts or external resources.

## Costs, limits and targets

Costs below exclude user key operations, callbacks and value-copy costs:

| Map | Existing key | Missing key |
| --- | --- | --- |
| HashMap | One expected O(1) lookup; worst O(bucket count) | Same search plus candidate check and insertion; table rebuild/growth can take O(bucket count) |
| TreeMap | One O(log n) lookup and constant value reinstall | One O(log n) search plus insertion/rebalancing; storage growth copies O(n) nodes |

Existing map capacity and allocation limits remain in force. The methods use
the current collection and allocator engines and add no host-service binding.
User callbacks can allocate or call host services under their own contracts;
the API imposes no wall-time bound on them.

The verification target is Linux x86_64 CPU output from the GPU compiler.
Accepted checks are listed below. GPU-device execution, other
hosts, enforced lifetimes and formal proofs remain outside this increment.
No compiler, runtime or ABI repair is part of the implementation.

## Consumer and verification

The [word-concordance program](stdlib-word-concordance.md) is the real consumer:
its initializer constructs a positions vector for a new word, while its updater
appends to an existing vector. The caller captures the distinct-word admission
decision before the map call, so an existing word can still be updated at the
limit without the initializer accessing the map.

Receipts are under `target/stdlib-work/`; names below share the prefix
`lazy-map-`. Rust build times are separate from test execution.

| Receipt suffix | Result and scope |
| --- | --- |
| `direct.log`, `contracts-accepted.log` | Three library gates accepted across two runs: native callback/key/candidate contracts; native nested Option, array and zero-sized shapes; and five compile-negative capability fixtures. The initial three-test run passed shapes and capabilities but rejected an untyped fixture fallback literal (9.21 s); the corrected contracts fixture passed in 6.85 s. |
| `model-complete.log` | One test passed in 6.48 s: 32 cases / 5,920 actions against an independent dictionary model, including 1,879 insertions, 1,015 updates, 318 initialization errors, 1,084 mismatches and 550 callback error reports. |
| `hash-owners-final.log`, `tree-owners.log` | One test per map passed in 7.86 s and 7.85 s. Each covers one baseline and four reached allocation denials, with four successful recoveries and balanced source owners. |
| `hash-regression.log`, `tree-regression.log` | Two existing ordinary-insertion tests passed separately in 14.76 s and 16.35 s after both operations began sharing their vacant insertion tail. |

The model includes 2,104 natural-query and 2,192 borrowed-query operations;
786 occupied calls ignore a deliberately bad initializer. It compares 90,439
snapshot entries with seed `0x6a90261106`. Its 15 host controls pass separately.
Initial model/resource fixtures used invalid nonterminating match blocks;
rewriting those fixture expressions did not change the library or compiler.
The new-suite Rust build took 9.60 s; the existing-regression build took 9.66 s.

The application passes four Rust tests / 104 native cases: 28 independent
output cases, 12 admission cases, seven limit cases and 57 allocation/I/O/attempt
cases, including 38 reached allocation failures. The
[application receipt](stdlib-word-concordance.md#current-migration-and-historical-verification)
records timings and scope. Its historical standalone examples remain separate.

The owner probes use String keys, borrowed Text queries and values containing
an owned Vec and String. They check full-map hits without initialization or
map allocation, owned initialization errors, intact rejected candidates and
same-process retry. Each map's four denials target candidate key, vector, label
and table-growth allocations derived from its baseline trace. Storage failure
retries with the returned candidate itself. These are finite reached sites,
not an exhaustive allocation-failure campaign.

Source-allocation traces use the current runtime verifier and
`LANIUS_ALLOC=mmap`; verified native and CRT mappings remain outside source-owner
claims. Fourteen observer controls pass, including the current CRT terminal
cleanup distinction; host controls alone do not establish Lanius behavior.
Final resource-fixture corrections made null-pointer fields explicitly typed;
no production library, runtime or compiler change was needed after the initial
implementation freeze.
