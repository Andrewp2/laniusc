# Borrowed collection lookup: owners and finite scale

All three native resource groups passed on the finite profile below.
Independent read-only source, ledger and scope
review passed at the frozen identities below; no native commands were run by
the reviewer. Three registered resource groups complement the direct
capability/branch tests and independent
state model. These fixtures target Linux x86_64 CPU programs emitted by the GPU
compiler; they do not claim GPU-device execution or automatic borrowing.

## Selectors

- `hash_borrowed_queries_preserve_and_transfer_real_string_and_value_owners`
- `tree_borrowed_queries_preserve_and_transfer_real_string_and_value_owners`
- `borrowed_point_queries_reuse_fixed_scratch_and_check_every_large_collection_value`

The driver is `tests/stdlib_borrowed_lookup_resources_execution.rs`. Each
artifact passes the existing strict ELF and shared jump-validation admission
before `strace` observes its complete syscall stream. Root alone runs native
and compiler commands; fixture authoring and review do not establish runtime
acceptance.

## Actual String/Text and nested-owner lifetimes

Each of `hash.lani` and `tree.lani` constructs an actual String-key map and set.
The two stored `bravo` Strings have independent allocations. The map value is
an owned `Pair<Vec<u8>,String>`. The query is a distinct `Text` borrowing the
middle five bytes of a separately allocated nine-byte Vec, with two guard bytes
on either side. The shared `alloc::string::TextKey` policy operates on that
nonzero-offset Text; no owned query String is constructed.

Present and missing getters check the exact stored String and value backing
pointers and every payload byte. Missing updates never invoke the callback.
All nine query backing bytes, including guards, are rechecked after calls.
Borrowed getter results become inactive before update or removal.

The selected update explicitly reserves new capacities in both nested value
owners, appends bytes, and returns the latest descriptors with an ordinary
`Err(71)` result. Its `B`/`b` markers isolate its own allocation and release
effects from collection search and descriptor installation. The callback runs
once, the map retains the exact stored key and table, and later lookup obtains
the new value descriptors despite the error result. Query backing is disjoint
from the modified value and remains live throughout the call. This is not an
allocation failure test: query operations do not allocate, and there is no
fabricated query OOM campaign or rollback claim.

Removal returns the actual map key/value and stored set key. Query backing is
destroyed immediately after these calls, followed by the two empty collection
tables. Only returned owners remain when the fixture validates and publishes
all twenty result bytes. Each returned owner is explicitly destroyed once.
Getters never acquire duplicate cleanup authority.

Each owner group observed nine matched allocations/releases, four phases with
no host effects, one effectful update callback and twenty exact output bytes.
The removal phase changes collection membership while making no allocation or
release; the term “no host effects” does not mean no in-memory mutation.

## Finite scale without incidental per-key allocations

`scale.lani` exercises hash and tree maps at 4,096 and 16,384 entries. Stored keys
are multiword scalar records with a full-width stamp; values are full-width
integers. Distinct Query values borrow six numeric Text bytes inside one guarded
twelve-byte scratch owner and carry only a borrowed instrumentation context.
The query buffer is reused only after each synchronous call returns.

Each of the 40,960 stored entries is fetched and fully checked, then paired with
a missing query. The hash profile uses compatible numeric hashes: exactly one
query hash per call, one successful predicate per stored entry, and no predicate
on the distinct cached hashes of missing keys. The AVL profile checks a finite
comparison bound of 32 times the entry count across its hit/miss pairs. This is
an observable safeguard against a linear scan with comparator calls, not a
proof of a general asymptotic or throughput guarantee.

The complete returned stamp/value stream is compared against an independent
Rust arithmetic oracle: 655,360 bytes across four cycles and 81,920 point
queries. Each cycle has one pre-reserved collection allocation, one query
buffer and one exact output buffer. It makes no new allocation during query
execution. Query and table owners are released before publishing the independent
output buffer. Observed totals are twelve matched allocations/releases and
eight phases with no host effects. Native timing includes process, tracing,
setup, lookup, checking, output and cleanup, and is reported separately from
compilation. No broad compiler or engine performance claim follows.

## Exact resource accounting and finite scope

The complete syscall ledger rejects host effects within marked query/check
phases and permits post-construction allocation/release only inside the selected
update callback or explicit final cleanup. Full-width allocation addresses,
requested extents and live generations are recorded; overlap, duplicate or
unknown releases, and wrong extents fail. Every output syscall requires exactly
the independent result owners to remain live. Release completion is observed
before exit rather than inferred from process status.

Packed backing sizes come from explicit source requests: owner setup reserves
5, 3, 4, 5 and 9 bytes; the callback's Vec reserve adds five to length three for
capacity eight, while String reserves a minimum of twelve. Scale scratch is
twelve bytes and output capacity is exactly `16 * count` bytes. Private map and
set table reservations are recorded as observations of their actual allocation
requests, then matched exactly at release. The tests assert table identity,
logical contents and public capacities without inventing a fixed private slot
or node ABI size promise.

The source exercises manual single-owner cleanup and synchronous query
lifetimes. It does not simulate misuse of stale borrows, provide automatic
destruction, inject unreachable query allocation failures, or establish all
possible callback schedules. The direct/model suites separately cover exact
method bounds, hash/collision/tombstone paths and comparator visitation.

## Accepted native receipt

Root's `target/stdlib-work/borrowed-lookup-resources.log` completed with exit 0:
three passed, zero failed in 13.62 seconds at the frozen identities below.
All three groups passed on their first native invocation; there was no retry
or allocation-denial campaign.

| Group | Exact maps/releases | No-host-effect phases | Complete output | Compile time | Native time |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hash map/set owned representatives | 9 / 9 | 4 | 20 bytes | 3.241884 s | 0.006544 s |
| Tree map/set owned representatives | 9 / 9 | 4 | 20 bytes | 3.401179 s | 0.006635 s |
| Four finite scale cycles | 12 / 12 | 8 | 655,360 bytes | 6.660651 s | 0.288895 s |

Both owner groups preserved the query backing and exact stored representatives,
installed both changed nested value descriptors despite the ordinary `Err(71)`
result, and published only after query and collection retirement. This result
is a callback policy return, not a reached allocation failure or query OOM.
The exact release ledger and every output-byte check passed.

Observed private reservations were 704/320 bytes for the hash map/set owner
group and 448/256 for the tree map/set owner group. Scale map reservations were
327,680 and 1,310,720 bytes for the 4,096/16,384-entry hash profiles, and 262,144
and 1,048,576 bytes for the corresponding tree profiles. These are receipts from
the current implementation, not asserted ABI or public capacity promises.
Each observed address and requested extent was matched at explicit cleanup.

Native timings include process, tracing, setup, query work, checks, publication
and cleanup; they are separate from compilation. The finite scope and excluded
performance, lifetime-enforcement and GPU-device claims above remain unchanged.

## Frozen identities

- Driver: `ecc3bbd63c858e2ee417c9cfe9a7503478ce66b19d556eccacb9e0733fc2c8b5`
- `hash.lani`: `a7dfb861eb58711e949ab9012fe84a6994877b331d9e704ceb54d653f4e19a16`
- `tree.lani`: `0cec017817aa51ce378e069c713a309c4976e03b99679c14830fe73a770a85d9`
- `scale.lani`: `d30eb8ebbf547f323914b4d29711dad9918c8eacf8eedc7426ff6926355aa656`
- `fixture/support.lani`: `53cc92e23f54135541cc8ed8cbbdc0942852de32f5ed4a867633bf457658aaa8`
- `fixture/scale.lani`: `2b6bb2747d70b2504371b1371340e870d7aad032cb8177a34bcffb0fc10c1d63`
