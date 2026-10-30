# Borrowed lookup history model

This fixture calls all sixteen borrowed point-lookup methods on the real
HashMap, TreeMap, HashSet and TreeSet modules. The Python program is a test
oracle only. The focused native gate passed; the host controls below are separate and do
not execute Lanius.

## Independent reference and observations

The semantic reference is a dictionary from logical identity to the complete
stored representative and value. It does not implement buckets, tombstones,
AVL nodes, rotations or the library's search algorithm. Each history combines
existing insertion, representative replacement, clearing and refilling with
borrowed contains/get/entry/update/remove calls. Map insertion replaces the
entry; duplicate set insertion returns the supplied key and retains the old
representative, while set `try_replace` replaces it.

The stored key has an identity, a full-width representative stamp and a hash
profile. The differently shaped query encodes the identity with an offset,
has an independent full-width tag, and implements Hash without Eq or Ord.
Policies receive the stored key first. Map values include a u64, Option<bool>
and a signed array. Stateful updates return a new value and a compound
Result receipt. An Err receipt must still install the new value.

Every action emits its complete result, all query-hash/comparison/update
events, cumulative callback counts, allocation/structural metadata, and every
stored key/value. Tree iteration must be sorted; hash iteration is compared
as complete contents, without fixing bucket order. Every snapshot checks
exhaustion again. The final snapshot precedes explicit destruction of the
single live collection owner. The keys and values contain no nested owners.

Search observations are checked against contract constraints, rather than an
exact predicted path:

- Each hash query hashes its complete Q exactly once, including on an empty
  collection. Equality receives only current representatives with the same
  cached hash, never revisits an entry, and ends at the exact matching stored
  representative on a hit.
- Tree comparison receives current representatives in narrowing ordered
  intervals, without revisiting nodes; the finite path is bounded by
  `2 * ceil(log2(n + 1))`. Nonempty searches call a comparator. A hit ends at
  its exact representative. No particular AVL shape is required.
- Comparisons stop before the selected update callback. The callback runs
  once on a hit and zero times on a miss. Every input, installed value,
  receipt and stateful ordinal is checked. Read/update/missing-remove calls
  preserve allocation and structural metadata. Successful removal and clear
  retain allocation; growth factors and internal post-removal shape are not
  predicted.

Both hash profiles collide: one constant hash and one three-class hash,
including hash zero. Six insertion histories use ascending, descending,
balanced, alternating-end and two seeded shuffled orders. The mandatory
prefix exercises every API on empty collections, then hits/misses, removals,
reinsertion, representative replacement, clear/reuse and Err-valued updates.
A reproducible mixed tail extends each history to 96 actions. Tree histories
are not duplicated across irrelevant hash profiles.

## Fixed scope

Seed: `0xb0770261120`. The 36 cases contain:

- 3,456 actions, 1,815 borrowed queries, 1,228 query-hash calls;
- 575 query hits and 1,240 misses;
- 44 update callbacks, 203 missing updates and 24 Err receipts;
- 350 successful removals and 18,759 entries across complete snapshots;
- four collection families, sixteen APIs and all 32 API hit/miss routes.

The input is a strict little-endian binary action stream. The producer uses
bounded 3,840-byte input and 4,096-byte output staging, with full eight-byte
pointer observations written through aligned typed pointer slots. Each case
has at most 96 actions and keys in 0..30. One native child handles the entire
batch; its timeout is 75 seconds and the Rust oracle harness has 90 seconds.
Exact callback path lengths, and therefore native transcript byte length,
may differ between valid implementations.

## Host verifier controls

The following host-only command passed in 0.83 seconds:

```sh
python3 -B tests/fixtures/stdlib_borrowed_lookup/model/oracle.py controls
```

Two synthetic admissible search policies are accepted, including distinct
hash comparison/iteration orders and distinct balanced search trees. All
23 corruption controls are rejected: sixteen altered event/result/state
fields, a non-Boolean iterator-presence marker, four coherent semantic mutations (lost Err update, substituted query
representative, retained removed entry and duplicate-set representative
replacement), truncated output and trailing output. The first synthetic
transcript contains 1,959,656 bytes. This is verifier sensitivity evidence,
not compiler or collection runtime evidence.

## Native gate and target limits

Accepted selector:

```sh
cargo test --test stdlib_borrowed_lookup_model_execution borrowed_lookup_matches_representatives_queries_updates_and_full_state -- --exact --nocapture
```

The native gate passed 1/1 in 7.06 seconds. The receipt is
`target/stdlib-work/borrowed-lookup-model.log`; its complete fixed summary
matches all counts above. The accepted producer, oracle and driver hashes
are listed below.

The driver uses the shared GPU compiler helpers, requires a Linux x86_64
executable, runs that executable on the CPU, and demands status zero, empty
stderr, a complete valid transcript and the exact fixed summary. This does
not claim collection execution on a GPU device, universal generic coverage,
formal verification or memory-safety enforcement. The separate direct and
resource gates cover actual String/Text owners, library allocation behavior,
invalid bounds and additional generic forwarding. Query consistency laws,
physical backing, operand stability, lifetime and single-owner cleanup
remain caller obligations.

Frozen sources accepted by the native gate:

- `model.lani`: `ea32a125674a02fb2663991b5126a8b7ec164e2380c6e3dafc91ea4768790c28`
- `oracle.py`: `f36431b3104c67bd97671a879ed334a08da8058d1129d10c9d235b64d0b19569`
- Rust driver: `a06527295be159b4abcc77535bc62a7fa77a51b43d9a50d8d4063f3a6ef30561`
