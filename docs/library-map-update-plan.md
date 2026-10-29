# Scoped map value updates

The full standard/extended-library goal remains open. At `3313f946`, map
lookups return shallow copies and insertion replaces both key and value.
Growing an owned value therefore requires removal and reinsertion to avoid
leaving a stale descriptor inside the map. This increment supplies one scoped
value transformation on both HashMap and TreeMap, preserving key identity and
map structure.

## Contract and architecture

Both maps expose:

```text
update_value<M,R>(&self, key:K, update:&M) -> Option<R>
    where M: core::iter::Mapper<V,core::pair::Pair<V,R>>
```

HashMap retains its Hash/Eq key bounds; TreeMap retains Ord. Reuse the existing
Mapper and Pair protocols. No new callback trait, occupied/vacant handle,
implicit insertion or compatibility alias is needed. Existing whole-entry
insertion remains a distinct operation that intentionally replaces the key.

Perform one ordinary key lookup. Missing returns None without calling the
mapper. Present calls the mapper exactly once with the shallow V, then stores
Pair.first in that same entry before returning Some(Pair.second). Preserve the
exact stored key, cached hash, links/heights/free-list state, entry count,
capacity and table/node allocation. The map performs no allocation, release,
extra hash/equality/order call, insertion, removal or rebalance after lookup.
User key hashing/comparison and mapper work can have their own effects,
including allocation. Those effects are separate from map-owned work; no
wall-time bound is introduced.

The caller lends exclusive authority over that stored value to the callback.
Return its latest valid descriptor in Pair.first on every normal return,
including when R is a Result error. There is no rollback or implicit Destroy.
The callback may replace V and return the displaced owner as R, or grow a
nested owner and return a separate result. It must not retain duplicate cleanup
authority over the installed V. R can own separate resources or borrow the
installed value under its normal lifetime; aliases are not additional owners.
The query key stays caller-owned even when equivalent to a stored key.

End previous value borrows and cursors before updating. During the callback,
do not access, reenter, mutate or destroy the map through any alias, and do not
change key equality/hash/order through shared backing. Keep the map, mapper,
key backing and callback context alive and stable. No automatic lifetime
checking or unwind/panic recovery is claimed. Invalid/forged map states remain
outside the existing map contract.

Rust's [occupied hash entry](https://doc.rust-lang.org/std/collections/hash_map/struct.OccupiedEntry.html)
and [occupied ordered entry](https://doc.rust-lang.org/std/collections/btree_map/struct.OccupiedEntry.html)
separate mutable value access from key removal/replacement. Lanius expresses
that responsibility through a scoped value/result transformation because its
current owner model needs updated descriptors restored explicitly. This is
not a claim of Rust borrow checking or a complete Entry handle API.

## Implementation and consumers

Keep each method inside its map module so it can use existing lookup and
storage operations directly. No separate map engine or raw public handle.
Use explicit typed extraction if generic Option/Result shorthand has a known
compiler dependency. Missing support gets a minimal reproduction; do not
change compiler/IR/ABI/extractor/proofs to absorb it here.

Migrate the existing lex_scan frequency update to HashMap.update_value without
changing its externally visible behavior. Add word_concordance: read bounded
UTF-8 input, group ASCII-whitespace-delimited words in a TreeMap<Text,Vec<u64>>,
append zero-based byte positions through update_value, then emit words in byte
order as word<TAB>comma-separated-positions<LF>. Keys borrow immutable input;
position vectors are independent manual owners. No argument is accepted.

Application limits: 1 MiB input, 16,384 input read attempts, 65,536 distinct
words and 8 MiB output. Validate complete input and compute output length before
stdout. Output uses bounded scratch, preserves confirmed prefixes on I/O error,
and has a global 131,072 direct-write-attempt allowance. Count Interrupted
attempts, retry only Interrupted, reject WouldBlock/zero/invalid successful
counts, and explicitly ignore SIGPIPE. Status 0 success, 2 invalid input or
limits, 3 I/O, 4 allocation. Quiet errors; all owned vectors, map storage and
input are released on ordinary terminal paths. Do not add an output String.

The 8 MiB output cap is defensive under these input limits: at most
ceil(N/2) words can fit in N input bytes, positions need at most seven decimal
digits, distinct key bytes sum to at most N and punctuation adds at most three
bytes per occurrence. The resulting loose bound is 6 MiB at the input cap.
Test reachable input/distinct-word limits and large output expansion; do not
claim a real-program rejection at the unreachable output cap.

## Verification and boundaries

Start with one tiny generic executable using both maps and a compound V/R
shape. Focused contracts cover absent/present calls, exact representative keys,
collisions/tombstones/tree mutations before updates, value replacement,
callback state/results and unchanged map structure. Use negative capability
checks only for the new Mapper/key constraints.

An independent bounded operation model compares full map contents and callback
events across insert/remove/update sequences. Resource tests use actual owned
String/Vec values, force descriptor-changing growth, preserve updated owners on
Result::Err, recover separate owned errors/displaced values and inject reached
callback allocation failures. Full-width allocation ledgers distinguish map
storage from callback-owned resources. Check meaningful generic shapes rather
than multiplying redundant cases.

The real program receives exact-output, boundary and reached fault tests.
Run selected existing map and lex_scan regressions affected by the change, not
broad GPU/performance campaigns. Root alone runs compiler/Cargo/native commands
serially under target/stdlib-work/library-gpu.lock, each outer command bounded
to 100 seconds. Agents may run host-only oracle controls.

Eight roles: hash implementation, tree implementation/lex_scan migration,
direct admission/contracts, independent model, ownership/fault tests, real
program/tests, docs/metadata and independent review. Root integrates, runs,
generates the reference, commits and pushes. Preserve root README, AI_POLICY,
CONTRIBUTING, protected std::vec/core::mem and tests/common. Initial execution
evidence is Linux x86_64 CPU output from the GPU compiler; device programs,
other hosts, automatic ownership and formal verification remain separate.

## Accepted increment

The implementation and finite Linux x86_64 execution gates are accepted.
The full standard/extended-library goal remains open.

| Gate | Accepted evidence |
| --- | --- |
| Direct API groups | Three native groups plus one capability group with five compile rejections; compound, array, bool and zero-sized V/R shapes execute |
| Independent operation model | 72 cases, 7,896 actions, 3,128 callbacks and 111,960 complete-snapshot entries across both maps |
| Owned-value resources | Two baselines plus four reached callback-growth allocation denials; latest descriptors remain installed and retries succeed in the same process |
| Word concordance | Four groups, 103 native cases: 28 model, 12 admission, six limits and 57 I/O/resource cases, including 38 reached allocation failures |
| Selected existing regressions | HashMap contracts, TreeMap contracts and lex_scan counts/span behavior each pass separately |
| Standalone program | CLI compilation and both guide examples pass with exact 18/21-byte output, status zero and empty stderr |

The first direct run passed shapes and capability checks but could not compile
the contracts fixture's inferred chained tree constructor (LNC0006). Explicit
`with_capacity<Key,u64>` arguments fixed the fixture; the focused retry passed.
No map production or compiler change was needed for that correction. The
existing broader generic-shorthand dependencies retain their separate scope.

Receipts and exact test selectors live in the
[map guide](stdlib-map-updates.md),
[direct fixture guide](../tests/fixtures/stdlib_map_update/README.md),
[operation-model guide](../tests/fixtures/stdlib_map_update_model/README.md),
[resource guide](../tests/fixtures/stdlib_map_update_resources/README.md) and
[application guide](stdlib-word-concordance.md). Raw logs are under
`target/stdlib-work/map-update-*.log`. The final file manifest is
`target/stdlib-work/map-update-final.sha256`.

The frozen HashMap, TreeMap, lex_scan and concordance source hashes start
`259e6440`, `fc671134`, `00eb9813` and `5013630d`, respectively. The tests execute
CPU programs produced by the GPU compiler; they do not establish GPU device
execution, other host targets, automatic ownership or formal verification.
Callback exclusivity, valid returned descriptors and manual cleanup remain
caller obligations. No protected source, compiler, IR, ABI, extractor or proof
file changes are part of this increment.
