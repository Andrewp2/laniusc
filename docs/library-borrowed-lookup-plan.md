# Borrowed collection point lookup

This increment lets a query type differ from the stored key type without
constructing an owned key. The full standard and extended library goal remains
open. At the start of this increment, hash/tree maps and sets accepted only
the stored type, while `unique_words` allocated a String for every token
before duplicate rejection.
The new boundary belongs in the existing collection search engines.

## Public surface

Add these methods to both HashMap and TreeMap:

- `contains_key_by<Q,P>(query:Q, policy:&P) -> bool`
- `get_by<Q,P>(query:Q, policy:&P) -> Option<V>`
- `get_entry_by<Q,P>(query:Q, policy:&P) -> Option<Entry<K,V>>`
- `remove_by<Q,P>(query:Q, policy:&P) -> Option<Entry<K,V>>`
- `update_value_by<Q,P,M,R>(query:Q, policy:&P, update:&M) -> Option<R>`

Add `contains_by`, `get_by` and `remove_by` to both sets with the same query
arguments. Set `get_by` and `remove_by` return `Option<T>`. These sixteen
methods reuse the existing map-owned KeyStorage bridges. No set gets an
independent search or balancing implementation.

Hash methods require `Q:core::hash::Hash<Q>` and
`P:core::function::Mapper<core::pair::Pair<K,Q>,bool>`. The pair contains the
stored key first and query second. Tree methods require
`P:core::ordering::Comparator<K,Q>`, also stored first. Update methods require
`M:core::function::Mapper<V,core::pair::Pair<V,R>>`. New query methods need no
additional K or Q comparison capabilities; existing same-key methods retain
their current bounds. All required bounds apply even to an empty collection.

Add `alloc::string::TextKey {}` with `borrow()` and implementations of both
query policies for `String,core::text::Text`. Reuse `String.as_text()` and
Text equality/order; Text already hashes exactly the same bytes as String.
This is case-sensitive UTF-8 byte identity, including embedded NUL, without
normalization. Collections remain generic; no String-specific overloads.

Ordered bounds/ranges need additional interval/query-order contracts and
remain separate. Insertion still takes an actual K. This increment adds no
projection/Borrow trait, new hash algorithm, hash-query protocol or aliases.

## Laws, effects and ownership

Every query denotes at most one stored key equivalence class. If a hash
predicate matches, the query hash must equal the stored key's hash. Tree
comparisons must partition the stored ordering as Less, optionally Equal,
then Greater. Policies must remain consistent with the collection's original
key identity/order. These laws are preconditions, not dynamically validated.
Broader case-insensitive equality over case-sensitive stored keys violates
the contract when it merges distinct key classes.

Each hash query hashes Q exactly once, including an empty collection. It
checks equivalence only for occupied slots with the exact cached hash, and
stops at the first match or terminating empty slot. Each tree query calls the
comparator once per visited node. Comparisons finish before an update callback
or removal starts. Instrumentation may observe calls, but policies must not
mutate/reenter the collection, change either operand's represented contents,
destroy resources, or retain borrowed operand descriptors beyond the call.
Query, policy and referenced backing remain live and stable throughout the
operation. An update must not invalidate query backing through a value alias.

Lookup adds no allocation, clone, cleanup or host call. A miss returns
false/None and never invokes the update callback. A hit invokes update once
and reinstalls its returned V even when R is an error; it preserves the actual
stored key and cached hash. Callback effects and explicit value-owner
replacement follow the existing update contract, without rollback/unwind.

Getters return shallow borrowed copies of the stored representative. Removal
returns the actual stored key/value and transfers its cleanup responsibility;
it never substitutes or destroys the query. End affected old borrows/cursors
before mutation. Collection storage and nested resources keep manual, single
cleanup authority. No automatic borrowing or destruction is claimed.

Reuse one probing engine and one AVL point-search engine. Existing same-key
queries adapt to them. A private natural tree adapter retains the existing
query-first `lt(query,stored)` call order, then `lt(stored,query)` when needed.
Reuse index-based update/removal helpers and preserve all unrelated ordering,
growth, cursor and storage behavior. Hash search is expected constant bucket
work under suitable hashes and worst-case O(buckets), excluding query hashing
and policy work (Text hashing reads the query bytes); removing the last entry
still clears tombstones in O(buckets). AVL search/removal is O(log n), excluding
callback cost. No broad throughput claim follows.

The consistency laws follow the primary
[Rust HashMap](https://doc.rust-lang.org/std/collections/struct.HashMap.html#method.get),
[BTreeMap](https://doc.rust-lang.org/std/collections/struct.BTreeMap.html#method.get)
and [hashbrown Equivalent](https://docs.rs/hashbrown/latest/hashbrown/trait.Equivalent.html)
contracts. Lanius uses its existing explicit callback policies and shallow
values; this does not adopt Rust's Borrow, move or automatic-drop behavior.

## Real consumer

Migrate `unique_words` to validate a complete token as borrowed Text, query
the committed TreeSet using TextKey, and scan the at-most-63 pending Strings.
Only a novel token gets an independent String. Keep 64 completed-token batch
windows with a scalar counter, so duplicate suppression does not postpone
flush boundaries. Preserve grammar, input limit, statuses, complete validation
before publication, exact sorted output, owner transfer and I/O recovery.
Allocation failures at eliminated duplicate-copy sites intentionally disappear.

## Acceptance

- Tiny native admission of the new generic calls across all four collections.
- Direct semantics for all sixteen methods, exact stored representatives,
  collisions/tombstones, missing/empty queries, AVL removal/reuse, compound
  queries/values, generic forwarding and precise invalid-bound diagnostics.
- Independent state model of mixed existing insertions and new queries,
  updates, removals/reinsertions; full key/value/state and callback observations.
- Actual owned String queries and removals with distinct borrowed Text backing,
  no library allocation in query phases, full backing identities, explicit
  cleanup and finite scale observations. Callback failure remains a callback
  policy, not fabricated query OOM behavior.
- Existing unique_words output/I/O/failure model preserved; repeated words and
  a fixed repeated vocabulary crossing read/batch boundaries must allocate no
  more owned keys than the first distinct vocabulary pass. Reached allocation
  denials follow the new baseline, without preserving obsolete counts.
- Focused old map/set regressions for shared search/mutation behavior; current
  guides and generated reference keep historical evidence separately scoped.

Root serializes compiler/native/Cargo commands under
`target/stdlib-work/library-gpu.lock`, with each outer command capped at 100
seconds. Acceptance targets Linux x86_64 CPU output from the GPU compiler.
No compiler/IR/ABI/extractor/proof, protected std::vec/core::mem/test harness,
root README or human policy edits. Missing compiler support gets a minimal
reproduction and dependency record. No Rust/Python library implementation,
cryptographic primitive, production JSON transport or Wasm dependency is added.
