# Map, set and heap collection

Five more owned collections implement the shared
[`core::iter::TrySink<T,E>` protocol](stdlib-iterator-transfer.md). Maps and
sets reject duplicates explicitly; heaps accept every item, including equal
values. The existing insertion methods retain their own documented behavior.

These implementations execute on **x86_64 Linux** in native CPU programs built
by the GPU compiler. The focused gates below passed on **2026-10-24**. This does
not establish user-program GPU execution or other platforms.

## Destinations and errors

| Destination | Iterator item | Sink error | Acceptance |
| --- | --- | --- | --- |
| `alloc::hash_map::HashMap<K,V>` | `alloc::hash_map::Entry<K,V>` | `alloc::hash_map::SinkError` | Insert an absent key |
| `alloc::tree_map::TreeMap<K,V>` | `alloc::tree_map::Entry<K,V>` | `alloc::tree_map::SinkError` | Insert an absent key |
| `alloc::hash_set::HashSet<T>` | `T` | `alloc::hash_map::SinkError` | Insert an absent element |
| `alloc::tree_set::TreeSet<T>` | `T` | `alloc::tree_map::SinkError` | Insert an absent element |
| `alloc::binary_heap::BinaryHeap<T>` | `T` | `alloc::binary_heap::Error` | Push with the owner's selected Min/Max order |

Each map module defines:

```lani
pub enum SinkError { Duplicate, Storage(Error) }
```

The sets already expose their corresponding map engine's storage error; they
also share that engine's sink error. `Storage` preserves the original checked
insertion error. Heap collection uses its existing error type directly.

Hash keys/elements require both `Hash<T>` and `Eq<T>` with the exact item type.
Tree keys/elements and heap items require `Ord<T>`. Map values have no added
comparison, hashing, clone or destruction requirement. The two existing map
`Entry` types remain distinct; a mapper can explicitly convert between them.

## Duplicate policy

A map sink rejects any key equal to an existing key, even if their values are
equal. It preserves **both** the stored key and value, including the stored
key's representative metadata. A set sink preserves its existing equal
representative and rejects the incoming one. These outcomes return
`Some(SinkError::Duplicate)` from `try_accept`.

Duplicate rejection makes no collection storage allocation or replacement. It
still wins when the collection is full or a further allocation would fail. The
existing
collection length, capacity, contents and outstanding valid views/cursors
remain unchanged. No item is silently replaced or discarded by this policy.

A heap accepts equivalent items as separate entries. It preserves multiplicity;
the heap's existing ordering determines removal order. Equal items have no
promised stable order.

## Progress and recovery

`try_transfer_up_to` is unchanged. Each accepted insertion advances this call's
count; the first rejection returns `TransferError { accepted, rejected, error }`
without another source call. `rejected` contains the full supplied map Entry
or set/heap item. Earlier accepted entries remain in the destination. Existing
entries are not included in the returned count.

On `Duplicate`, callers can retain or release the incoming item, report the
conflict, or remove the existing entry and retry the incoming item explicitly.
Removed entries transfer their cleanup authority according to the existing
collection contract. On `Storage`, callers can retry the returned item before
resuming the source. The source has already consumed that item in either case.

Zero quota touches neither object. Reaching the quota makes no extra EOF probe;
only an observed `None` sets `exhausted = true`. The quota counts immediate
source `next()` calls, not work within adapters, comparisons, hashing or the
allocator. `u64::MAX` is a valid quota, with no overflowing count or `limit + 1`.

All inputs, errors, stored entries and returned entries use ordinary shallow
copies. No sink implicitly clones or destroys nested owners. Keep one cleanup
authority per resource and release nested owners exactly once. A rejected
independent String owner remains with the caller; a rejected borrowed String
alias is not another owner to destroy.

## Key laws, lifetimes and cost

Hash/Eq/Ord implementations must obey their existing collection laws and return
stable answers throughout an operation. They may count calls, but must not
change a key's hash/equality/order, mutate the destination reentrantly or
invalidate key backing. Stored keys must remain lawful and stable for their
entire residence in the collection. Concurrent mutation is unsupported.

Map sinks first query membership, then call the existing checked insertion for
an absent key. Under these laws, successful insertion cannot displace an entry;
an assertion traps if it nevertheless does. This is not a recoverable Duplicate
result after a replacement. The original insertion bodies are unchanged.
Set sinks reuse their existing duplicate-preserving insertion. Heap sinks reuse
checked push. The separate heap backing-vector migration remains a
[compiler dependency](library-dependencies.md).

For an absent map key, collection adds one membership lookup to the existing
insertion. Hash lookup is expected constant time with a suitable hash and can
be linear under collisions; tree lookup is logarithmic. Growth retains the
underlying collection's existing allocation and relocation cost. Heap push is
logarithmic after capacity is available. Hashing/comparison costs depend on the
key and are not bounded by the transfer quota.
User hashing/comparison implementations retain their own documented effects,
including any allocation; the storage-allocation guarantees above refer to
the collection machinery.

Source backing must remain valid across destination edits and later item uses.
Do not collect from a cursor borrowing that destination, even when capacity is
already reserved. Successful edits invalidate its existing views/cursors under
the collection's ordinary rules. Keep backing borrowed by stored or rejected
items and errors alive until their last use. Lanius does not enforce these
lifetime rules or provide automatic destruction.

The [identifier-index program](stdlib-index-words.md) demonstrates composition:
text words, checked enumeration and mapping produce ordered-map entries with
their original positions; duplicates fail before any output is published.

## Verification

The accepted gates used compiler source checkpoint
`61284e3a58debbb74615631cf8fdd29e04b4e0d0` plus the five collection sink additions.
No compiler, shader, IR, ABI, extractor, proof or core iterator changes were
needed. Existing insertion bodies and the heap backing-vector choice were
preserved. Rust supplies independent test models and orchestration; library and
application behavior is implemented in Lanius.

| Gate | Accepted evidence | Time | Local log under `target/stdlib-work/iterator-collection-sinks-admission/` |
| --- | --- | --- | --- |
| Typed values and owners | One strict checked ELF/native execution; nested/wide/array values, generic keys, distinct old/incoming String owners and exactly 11 balanced allocations | 8.49 s | `typed-contracts-final.log` |
| Independent model | One strict checked ELF/native execution; 640 scenarios and 5,760 bounded transfers across four unique-key destinations and both heap orders | 8.58 s | `models-final.log` |
| Hash map failures | One strict checked ELF; baseline, three separately denied/recovered growth allocations and two full-capacity duplicate cases | 7.27 s | `hash-map-faults.log` |
| Hash set failures | One strict checked ELF; baseline, three denied/recovered growth allocations and two full-capacity duplicate cases | 7.07 s | `hash-set-faults.log` |
| Tree map failures | One strict checked ELF; baseline, four denied/recovered growth allocations and two full-capacity duplicate cases | 7.24 s | `tree-map-faults.log` |
| Tree set failures | One strict checked ELF; baseline, four denied/recovered growth allocations and two full-capacity duplicate cases | 7.34 s | `tree-set-faults.log` |
| Heap failures | One strict checked ELF; baseline and four denied/recovered growth allocations with complete contents and priority checks | 7.48 s | `heap-faults.log` |
| Exact trait bounds | Six source-local LNC0008 rejections for missing/wrong Hash, Eq, Ord, Entry and error identities | 5.28 s | `bounds.log` |
| [Identifier index](stdlib-index-words.md) | One strict checked ELF; 65 native cases, including all 12 observed input/map allocation-failure positions | 9.15 s | `application.log` |

The independent host model uses finite queues, logical group identities and
explicit stored representatives. Constant hashes force collisions. Snapshots
compare the full retained key/value payloads before recovery, full rejected
items, source position/call counts and caller-retained values after each
transfer. Recovery either saves the rejected item or removes/saves the stored
representative and retries the incoming item before resuming. A final
conservation check accounts for every original representative. Heap snapshots
compare canonical multisets; final pop checks compare priority order and full
payloads while allowing unspecified tie order. Quotas include zero, exact,
larger and `u64::MAX`; both empty and prepopulated destinations execute.

Typed contracts use identity-only generic keys with distinguishable nested
payloads and six independent String owners. They exercise duplicate rejection
after a successful prefix, manual recovery, generic source/sink forwarding,
wide arrays and Option/Result variants. Heap backing is transferred from Min
to Max without creating a second owner. A syscall ledger requires six String
allocations, then five collection allocation/release pairs, then the six String
releases in creation order. Addresses and requested lengths must match exactly.

The five fault fixtures each start with existing entries and deny every observed
later growth allocation once. They check exact wrapped allocation errors,
unchanged contents/capacity/old cursors, intact rejected compound payloads and
successful retry before source resumption. Across those fixtures, all 18 growth
positions recover. Four full-capacity duplicate cases also run with the next
allocation denial armed: no further storage allocation occurs, so this
particular denial is intentionally unreached. Other fault injections must be
reached. The five fault gates together execute 31 native processes.

### Fixture corrections

The initial typed fixture incorrectly expected hash reserve(2) to provide
capacity two. The implementation starts with eight buckets, providing capacity
four. A diagnostic copy trapped in the first hash-map case, matching the false
assertion. The final fixture captures reported capacity, requires at least two
slots, and checks it remains unchanged. Logical length assertions and tree/heap
expectations were preserved. The separate fault fixtures check actual full
capacity; this typed hash example uses less than full capacity.

The model initially exposed a private output helper through a public test-only
trait (LNC0075). Making the trait private then required matching private impls
(LNC0021). Both diagnostics were correct; the local observation trait and its
five impls are now private. No oracle, payload or production behavior changed.
The initial sources and logs are retained locally as `contracts-initial.lani`,
`driver-initial.rs.txt`, `typed-contracts.log`, `contracts-stages.lani`,
`typed-stages.log`, `model-initial.lani`, `models.log`,
`model-private-trait.lani` and `models-private-trait.log` under the admission
directory. They are historical diagnostics, excluded from accepted gate counts.

### Reproduction

Build the focused drivers from the repository root:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --locked --test stdlib_iterator_collection_sink_execution \
  --test stdlib_iterator_collection_sink_faults \
  --test stdlib_iterator_collection_sink_bounds \
  --test stdlib_index_words_execution --no-run
```

The actual builds were `build-faults-bounds-application.log` (1.73 s, three
targets) and `build-models.log` (1.59 s, model/typed target). Run each gate
separately with the shared lock and under two minutes. For example:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_iterator_collection_sink_execution-03808ba4bc6d16ee \
  --exact collection_sink_sequences_match_independent_duplicate_and_heap_models \
  --nocapture
```

Use the same driver with
`--exact typed_collection_sinks_preserve_duplicate_payloads_and_owner_lifetimes`
for typed contracts. The five fault tests in
`stdlib_iterator_collection_sink_faults-6b18e1adaf2d120d` were each selected
separately with `--exact`; their source names identify the tested engine.
The bounds driver was
`stdlib_iterator_collection_sink_bounds-3acf035d57a158b3 --test-threads=1 --nocapture`.
The application driver was
`stdlib_index_words_execution-cfcdf43f6a84744e --nocapture`.
Cargo can change executable hashes on rebuild; use its printed paths. A shared
lock timeout returns 75 without running the gate.

No throughput or cross-compiler performance claim is made from these gate
durations. The application checks 2,048-key reverse and 4,096-key permuted
workloads. The new map sink performs two lookups for an absent key, as described
above; existing insertion algorithms and compiler kernels were not changed.
