# Owning ordered-map and ordered-set cursors

**Accepted on native Linux x86-64 using the GPU compiler**, with all four
groups passing on 2026-10-25. Five compilation jobs produced five strict-checked
ELF programs and five native process runs. This establishes the tested native
profile; it does not establish Wasm or GPU execution of user programs.

`alloc::tree_map::TreeMap<K,V>` and `alloc::tree_set::TreeSet<T>` can transfer
their backing and live entries into explicit owning cursors. The cursor owns
the unconsumed entries and the current valid tree. Each successful pull
transfers one stored representative to its caller. Nothing is cloned or
destroyed implicitly.

## Surface and ownership transfer

```lanius
TreeMap<K,V>.take_iter() -> alloc::tree_map::IntoIter<K,V>
TreeSet<T>.take_iter() -> alloc::tree_set::IntoIter<T>
```

`take_iter` borrows and resets the actual source owner to empty with zero
capacity, while the cursor receives its allocation, entries, root, initialized
region and free list. The source can be reused immediately without affecting
the cursor. End borrowed source keys, values and cursors before this transfer.
Other shallow source descriptors become stale; the operation does not reset
those aliases or create another cleanup authority.

| Cursor operation | Contract |
| --- | --- |
| `borrow()` | Reference to the actual cursor owner |
| `remaining()` | Current number of unconsumed entries |
| `capacity()` | Current reserved node count, including backing retained after exhaustion |
| `is_empty()` | Whether no entries remain |
| `next()` | Transfer the smallest remaining entry/key, or None |
| `next_back()` | Transfer the largest remaining entry/key, or None |
| `try_finish()` | Some(Remaining(n)) while entries remain; otherwise release backing, disarm and return None |
| `take_remaining()` | Transfer the current valid TreeMap/TreeSet in O(1), then disarm the cursor |

Map pulls yield `Option<alloc::tree_map::Entry<K,V>>`. Set pulls yield
`Option<T>`. Front and back consume the same current tree and cannot yield its
middle entry twice. None is fused. Exhaustion leaves the backing allocated;
only successful finish, recovery followed by owner release, or an explicit
deep-release helper ends that ownership obligation.

Each module defines its own `IntoIterError { Remaining(i32) }`. Rejected finish
does not consume an entry, free storage, change capacity or invalidate the
current tree. Once empty, finishing frees backing and resets the cursor.
Repeated finish on that same disarmed cursor returns None and releases nothing
again. Taking or recovering an empty reserved owner is supported: it transfers
the retained capacity too. Recovery from a disarmed cursor yields an empty
zero-capacity collection.

The cursor operations have no key Ord/Eq, clone or Destroy bound. Construction
or insertion may need ordering, but endpoint removal follows established tree
links. A generic consumer needs only the ordinary Iterator bound:

```lanius
impl<K,V> Iterator<Entry<K,V>> for alloc::tree_map::IntoIter<K,V>
impl<T> Iterator<T> for alloc::tree_set::IntoIter<T>
```

Import `core::iter` to select the shared `next` protocol. Keep one active
owning cursor descriptor; copying it cannot fork cleanup authority or create
two independent positions.

## Canonical tree state and costs

Map cursors contain the canonical `TreeMap<K,V>` owner. Set cursors own the
existing nongeneric `KeyStorage` through the same typed shared-engine boundary
as TreeSet. Cursor pulls delegate to existing `pop_first` and `pop_last`
operations, including their ordinary AVL repair and free-list updates. There
is no copied Node layout, raw schema cast, extra balancing algorithm or second
allocation implementation.

Each successful pull takes O(log n) tree work for the current n entries. A full
drain therefore takes O(n log n), plus whatever the caller does with yielded
owners. Pulls perform no allocation, comparison, cloning or leaf release.
Metadata access, taking the source, rejected finish and recovery take O(1).
Successful finish of an empty cursor releases its one backing allocation.

Recovery transfers the actual current root, links, initialized region, holes,
free list and capacity in O(1). It does not compact or rebuild nodes. The
recovered collection can immediately use ordinary insertion, replacement,
lookup, removal, reservation and traversal under those operations' usual
bounds. Node reuse and further AVL balancing remain the shared engine's work.

Container counts and byte limits are unchanged. Empty cursors allocate
nothing themselves. A pre-reserved empty owner retains its backing through
take and recovery. Zero-sized keys/values still require structural node
metadata; a lawful zero-sized key has only one equivalence class.

## Yielded owners and fallible sinks

A yielded map Entry transfers both its key and value. A yielded set key is
the stored representative, including payload content not used for ordering.
The caller can release it, move it into another container, or mutate it as the
active owner. An independently owned yielded resource remains valid after the
remaining cursor is released. Transfer preserves only the cleanup authority
the source actually held: it does not extend borrowed lifetimes or repair
self-references into storage that will be released.

The shared `core::iter::try_transfer_up_to` works with these cursors and
ordinary fallible sinks. On rejection, the source has consumed the rejected
item, the sink has retained only the accepted prefix, and the returned error
contains the rejected owner. Recover or release that owner separately before
resuming. Resumption begins with the next unconsumed tree entry. A quota-ending
success does not poll again and does not imply observed source exhaustion.

Source cursors and sinks must own independent storage. An insertion rejected
as a duplicate must not retain the supplied owner; existing map/set sink
representative rules remain unchanged. Remaining-owner cleanup cannot recover
an item already yielded, rejected by a sink, or discarded by an adapter.
Ignoring such a transferred owner can leak its resources.

## Explicit deep cleanup

The existing opt-in clone modules add these helpers:

```lanius
alloc::clone_tree_map::destroy_tree_map_iter<K,V>(
    owner: &alloc::tree_map::IntoIter<K,V>)
    where K: Destroy<K>, V: Destroy<V>

alloc::clone_tree_set::destroy_tree_set_iter<T>(
    owner: &alloc::tree_set::IntoIter<T>)
    where T: Destroy<T>
```

Each helper recovers and disarms the actual cursor, then delegates to the
existing deep collection release. It releases only remaining entries and their
backing, with no clone or comparison bound. This takes O(n) canonical traversal
plus leaf Destroy costs. It does not repeatedly pop nodes or consult a finish
error to reclaim the owner. Repeating the helper on the same disarmed cursor
is harmless.

Every remaining key/value must be one distinct active memory owner for its
Destroy contract. If entries merely borrow nested resources, drain their
descriptors and use ordinary finish/recovery with separate original-owner
cleanup instead. Leaf Destroy must finish without allocation, panic or
reportable failure, and must not mutate the collection reentrantly.

There is no automatic Drop, finalizer, implicit cloning, compiler-enforced
uniqueness or cleanup after a trap. By-value aliases stay inactive after an
owner is transferred. Resources with fallible close need their own lifecycle
protocols.

## Native acceptance evidence

`tests/stdlib_owning_tree_execution.rs` compiles against the production stdlib
and `tests/fixtures/stdlib_foundation/owning_tree/` user root. Four passing groups
cover five positive native programs and retain the unchanged strict common
x86 ELF checker:

- Typed contracts mix front/back pulls, holes, spare capacity, stored
  representatives, source reuse, rejected finish, O(1) recovery, recovered
  insert/remove/rebalancing, retained empty capacity, repeated disarm, imported
  Iterator consumers, keys without Ord, and empty/ZST cases. Exactly eight
  explicit backing reservations are expected; cursor operations add none.
- String keys/values transfer independently, survive remaining-owner cleanup,
  and grow only through the caller's actual yielded owner. The two entries
  check 18 and 11 allocation generations with exact address/length balance.
  The helper-only entry performs no caller finish-result projection.
- Map and set sinks reject duplicate supplied owners while preserving their
  accepted prefix. Resumption consumes the exact remaining entry; rejected
  Strings stay valid after source/sink cleanup and are released last. Each
  phase has six explicit initial allocations and no allocating cursor or sink
  steps.
- A 192-operation map/set model starts with holes in capacity-512 owners,
  mixes pops, rejected finish, recovery and reinsert/remove, and checks 32
  complete ordered recovery snapshots plus all final representatives against
  Rust BTreeMap. Only the two initial reservations may allocate. The CPU
  schedule check retains at least 145 keys during the mixed loop; exhaustion
  and final finish are checked by its last drain.

All five programs passed the asserted live-address/request-length ledgers:
51 allocation generations in total, with every owner released exactly once.
The model's only allocations are its two initial backing reservations;
cursor pulls, rejected finish, recovery, and edits within recovered capacity
add none.

The accepted receipts are under `target/stdlib-work/`:

| Receipt | Scope | Elapsed |
| --- | --- | ---: |
| `owning-tree-contracts-first.log` | Typed contract group: one native entry, including no-Ord and empty/ZST paths | 5.77 s |
| `owning-tree-owners-model-transfer.log` | Three remaining groups: two String-owner entries, rejected transfer/resume, and the paired ordered model | 15.02 s |

These durations include compilation and checks, not isolated cursor-operation
benchmarks. The executable model verifies 192 paired map/set steps and 32
complete ordered recovery snapshots per engine. The receipts establish the
library family and its focused fixtures; application migration gates retain
their own scope and receipts.
