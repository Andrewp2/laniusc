# Borrowed collection point lookup

HashMap, TreeMap, HashSet and TreeSet accept a query type different from their
stored key type. The sixteen methods below search existing storage without
constructing an owned key. The [fixed plan](library-borrowed-lookup-plan.md)
defines this increment. All nine library groups and the 124-case migrated
application pass on native Linux x86_64 CPU output from the GPU compiler.
Earlier collection receipts keep their original source and API scope.

## Methods and bounds

All methods borrow the actual collection owner. `K` is the map key type,
`V` its value type, and `Q` the query type. Sets use their element type `T`
in place of `K`.

| Owner | Method | Result |
| --- | --- | --- |
| HashMap and TreeMap | `contains_key_by<Q,P>(query:Q, policy:&P)` | bool |
| HashMap and TreeMap | `get_by<Q,P>(query:Q, policy:&P)` | `Option<V>` |
| HashMap and TreeMap | `get_entry_by<Q,P>(query:Q, policy:&P)` | `Option<Entry<K,V>>` |
| HashMap and TreeMap | `remove_by<Q,P>(query:Q, policy:&P)` | `Option<Entry<K,V>>` |
| HashMap and TreeMap | `update_value_by<Q,P,M,R>(query:Q, policy:&P, update:&M)` | `Option<R>` |
| HashSet and TreeSet | `contains_by<Q,P>(query:Q, policy:&P)` | bool |
| HashSet and TreeSet | `get_by<Q,P>(query:Q, policy:&P)` | `Option<T>` |
| HashSet and TreeSet | `remove_by<Q,P>(query:Q, policy:&P)` | `Option<T>` |

Hash collections require `Q: core::hash::Hash<Q>` and
`P: core::function::Mapper<core::pair::Pair<K,Q>,bool>`. The Pair contains
the **stored key first, query second**. Tree collections require
`P: core::ordering::Comparator<K,Q>`, also with the stored key first.
Updates additionally require `M: core::function::Mapper<V,Pair<V,R>>`.

These methods add no K comparison/hash bound and no Q comparison bound.
The collection must still satisfy its original stored-key identity and order
invariants. Every stated bound applies even to an empty collection.
Existing same-key operations retain their bounds and signatures; insertion
still takes an actual K. Heterogeneous ordered bounds and ranges are separate
work because they need interval and query-order contracts.

## Query laws and exact calls

A query denotes at most one equivalence class of stored keys. Its policy
must agree with the identity used when those keys were inserted:

- **Hash lookup:** when the predicate matches a stored key, `Q::hash(query)`
  must equal that key's stored hash. Equal query hashes alone do not imply a
  match. Each operation hashes Q exactly once, including an empty collection.
  The predicate runs only for occupied slots with that exact cached hash.
  Probing stops at the first match or terminating empty slot, and remains
  bounded by the slot count.
- **Tree lookup:** comparison results across the stored order must form Less,
  optionally Equal, then Greater. The comparator runs once per visited node.
  Stored-less-than-query searches right; stored-greater-than-query searches
  left. An equality class must identify at most one stored key class.

These are caller preconditions, not runtime law checks. A case-insensitive
query over separately stored case-sensitive keys can merge distinct classes
and violate the contract. A policy cannot repair that mismatch by merely
returning the first key it finds.

The consistency requirements follow the primary
[Rust HashMap](https://doc.rust-lang.org/std/collections/struct.HashMap.html#method.get),
[BTreeMap](https://doc.rust-lang.org/std/collections/struct.BTreeMap.html#method.get)
and [hashbrown Equivalent](https://docs.rs/hashbrown/latest/hashbrown/trait.Equivalent.html)
references. Lanius uses explicit borrowed policies and shallow values; it
does not adopt Rust's Borrow, move or automatic-drop rules.

## Returned values and mutation

| Operation | Miss | Hit and cleanup authority |
| --- | --- | --- |
| Presence | false | true; no ownership transfer |
| Getter | None | A shallow copy of the stored value or representative; nested backing remains borrowed |
| Removal | None | The actual stored entry/element, with its cleanup responsibility transferred to the caller |
| Value update | None, no update callback | One callback; install `Pair.first`, then return `Some(Pair.second)` |

The query is never stored, substituted for a representative or destroyed.
A getter's returned key is the stored K, even when Q has a different type or
backing. Finishing a query borrow does not retire stored backing; returned
shallow copies need that backing to remain valid through their later use.
Conversely, a borrowed getter result creates no second cleanup owner.

All search-policy calls finish before removal or the value-update callback
starts. `update_value_by` preserves the actual key, cached hash, structure,
length, capacity and backing. It follows the existing
[scoped update contract](stdlib-map-updates.md): return the latest valid V
descriptor on every normal callback return, including when R is `Result::Err`.
The error does not request rollback. The callback accounts for displaced
owners; the collection never calls an implicit destructor.

Removal reuses the existing tombstone/AVL deletion path, including its cursor
invalidation and retained-capacity rules. End affected old borrows and cursors
before mutation. In particular, an update must not invalidate query backing
through an alias into V while the operation is active.

## Borrowing, effects and work

Keep query, policy, collection and referenced backing live and stable through
the operation. Search policies observe shallow operands only for their call.
They must not mutate either operand's represented contents, reenter or mutate
the collection, destroy resources, or retain borrowed operand descriptors
after the call. Independent instrumentation may record observations.

Collection-owned lookup work allocates, clones and destroys nothing and makes
no host call. User hashing, comparison and update callbacks retain their own
effects and cost. Their instrumentation or allocation does not make the
collection search itself an allocator. No unwind recovery, automatic borrowing
or destructor behavior is supplied.

Hash lookup has expected constant probe work with suitable hashes and
worst-case O(buckets) work. Removing the last entry also clears tombstones in
O(buckets). AVL search and removal take O(log n) structural work. Exclude
operand-copy and user callback cost from those bounds. A query imposes no
deadline on a callback and supplies no collision-resistance guarantee.

Same-key operations and the new methods share one probing engine and one AVL
point-search engine. The natural tree adapter preserves the old underlying
`lt(query,stored)` call first, then `lt(stored,query)` if needed; this differs
from counting one explicit custom comparator call per visited node. Sets use
the map-owned KeyStorage bridges; those internal bridges are not application
APIs or an erased-container interface.

## Querying owned Strings with Text

`alloc::string::TextKey {}` is a reusable zero-sized policy with `borrow()`.
It implements both `Mapper<Pair<String,Text>,bool>` and
`Comparator<String,Text>`, using `String.as_text()` and Text equality/order.
Text already hashes exactly the same bytes as String, including embedded NUL.
The identity is case-sensitive UTF-8 byte equality; order is unsigned byte
lexicographic order, with a shorter equal prefix first. There is no
normalization, locale collation or case folding.

Given a valid borrowed Text named `query` and an owned String set `words`:

```lani
let policy: alloc::string::TextKey = alloc::string::TextKey {};
let present: bool = words.contains_by<core::text::Text,alloc::string::TextKey>(
    query, policy.borrow());
```

The policy owns no text or query storage. Obtain a Text through its normal
checked constructors or an existing valid String's `as_text()`; preserve its
physical backing and lifetime obligations. Querying does not create a String,
validate forged Text metadata or acquire cleanup authority over either operand.

## Real program and acceptance

The [streaming word deduplicator](stdlib-unique-words.md) validates each complete
token as borrowed Text, searches its committed TreeSet through TextKey and
then scans at most 63 pending owned Strings. Only a token absent from both
receives an independent String. A scalar counter preserves flushes after
every 64 completed tokens, including skipped duplicates; EOF flushes a final
partial window even when it contains no new owned word. Full UTF-8 validation
still precedes every duplicate decision and publication still follows EOF.

The migrated application passes one registered test in 9.24s:
124 native cases, comprising 48 fixed cases and 76 reached representative
allocation denials. Repeated single-word and three-word workloads preserve
the complete allocation-request sequence across read and batch boundaries.
This current receipt is separate from the earlier 126-case application;
the application guide records its six-syscall observer and finite scope.

Tiny registered admission passes one native test in 6.57s
(`target/stdlib-work/borrowed-lookup-admission.log`). It executes all sixteen
methods with distinct Key/Query types, compound values and an ordinary
Result-error update. Source prefixes are hash_map `71eaba30`, hash_set
`57bc87c0`, tree_map `0580aa43`, tree_set `b8db6d37` and string `1507bdda`;
admission `c30d51ae` and driver `6068937d` identify the tested fixture.
A separate 1.42s Rust build prepared four test targets; compilation alone is
not runtime evidence.

The direct contract test also passes (1/1, 6.63s,
`target/stdlib-work/borrowed-lookup-contracts.log`) with exact stored
representatives, callback effects, tombstones, removal and reuse. Its fixture
is `2a4f8783` and driver `6103cdba`.

The [direct fixture guide](../tests/fixtures/stdlib_borrowed_lookup/direct/README.md)
records all five accepted direct groups: three native programs and two
capability-rejection groups covering seven hash and six tree fixtures. Their
mixed invocation (`borrowed-lookup-types-bounds.log`, 10.19s)
passed those two groups but failed the positive type fixture at an authored
call to nonexistent `with_capacity`. That fixture was corrected to the existing
constructor and reserve APIs. Its next attempt failed before
runtime with `LNC0027` on one receiver's distinct Mapper applications
(`borrowed-lookup-types-fixed.log`, 3.71s). A separate update-policy receiver
preserves the public bounds. A third attempt failed before runtime at an
unqualified `Equal` variant (3.80s); explicit ordering patterns are a fixture
authoring correction. The final generic/TextKey type test passes 1/1 in 6.78s
with six exact allocations/releases (`borrowed-lookup-types-qualified.log`,
fixture `96c6cf09`, final driver `420bfc6b`). The dispatch restriction is the
[existing same-receiver dependency](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md),
separate from the constructor authoring mistake. The workaround changes no
public query bound and makes no compiler-repair claim.

The [independent history model](../tests/fixtures/stdlib_borrowed_lookup/model/README.md)
passes 1/1 in 7.06s (`target/stdlib-work/borrowed-lookup-model.log`):
36 cases and 3,456 actions cover all sixteen APIs and all 32 hit/miss routes,
including 1,815 queries, 44 updates, 24 error-valued update receipts, 350
removals and 18,759 entries in complete state snapshots. Search observations
check lawful hash filtering and narrowing tree intervals without fixing a
bucket order or AVL shape. Its 23 host-only corruption controls remain
separate from native execution.

All three [owner/scale groups](../tests/fixtures/stdlib_borrowed_lookup/resources/README.md)
pass together in 13.62s (`target/stdlib-work/borrowed-lookup-resources.log`).
Each map family uses actual String keys and a distinct borrowed Text query,
checks the ordinary-error update and transferred owners after query backing
is retired, and matches nine allocations/releases, four phases without host
effects and twenty output bytes. The scale group checks every returned value
across 4,096/16,384-entry hash and tree maps: 81,920 queries, 655,360 output
bytes, twelve allocations/releases and eight phases without host effects.
Its traced native process takes 0.288895s, including setup, checks, publication
and cleanup; this is a finite correctness observation, not a lookup benchmark.

Three selected existing regressions also pass on these sources: hash-map
collision/generic contracts (15.00s), tree-map contracts (15.14s), and owned-set
width/owner contracts (16.56s). Their logs are
`borrowed-lookup-regression-{hash,tree,sets}.log` under `target/stdlib-work`.
The selected existing map-update regression terminated by signal (6.50s,
`borrowed-lookup-regression-updates.log`) because its old whole-allocation
snapshot compared unused upper bits of cached u32 hash words. A native
diagnostic preserved all logical semantics, pointers and callback effects.
The [map-update guide](stdlib-map-updates.md#current-regression-and-representation-scope)
records the observer correction; its focused retry passes 1/1 in 5.84s
(`borrowed-lookup-regression-updates-semantic.log`, fixture `1c29664e`).
Thus all four selected existing regressions pass, separate from the new API
groups.

All nine new library groups pass: five direct groups, one independent model
and three owner/scale groups. Seven execute native positive programs; two
check thirteen capability rejections. The current application and four
selected existing regressions have separate receipts. The accepted target is
native Linux x86_64 CPU output from the GPU compiler. No GPU-device, other-target,
formal-proof or automatic-lifetime claim follows. Historical map/set/String
and unique-words receipts are not evidence for the new signatures or reduced
duplicate-copy allocation count. The full library goal remains open.
