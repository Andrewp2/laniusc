# Scoped map update resource gates

Driver: `tests/stdlib_map_update_resources_execution.rs`.
Contract: `docs/library-map-update-plan.md`.

Both resource selectors have accepted native receipts at the frozen hashes
below.

## Native receipts

Root ran `tests/stdlib_map_update_resources_execution.rs` in
`target/stdlib-work/map-update-resources.log`: 2/2 selectors passed in
11.28 seconds after a 2.15-second Rust build, with successful native exits.
The selectors executed two baselines and four denial/recovery processes:

| Map | Baseline backing | Reached callback denials | Successful allocations / exact releases per process |
| --- | ---: | --- | ---: |
| HashMap | 832 bytes | `mmap` 8 / site 0; `mmap` 9 / site 1 | 10 / 10 |
| TreeMap | 512 bytes | `mmap` 8 / site 0; `mmap` 9 / site 1 | 10 / 10 |

Each denial execution observed the current valid Pair installed before the
error returned and completed recovery in the same process. Baselines and
recovery paths verified the separate owned error and displaced value after
map destruction. The exact complete output, representative keys, backing
identity, callback boundaries and explicit releases passed their assertions.
These observations cover the two selected growth sites per map and ordinary
returns; they are not an exhaustive callback or allocation-site campaign.

## Two selected owner lifecycles

- `hash_map_updates_preserve_owned_descriptors_and_recover_callback_allocation_failures`
- `tree_map_updates_preserve_owned_descriptors_and_recover_callback_allocation_failures`

Both producers use `fixture/owners.lani` and the same actual owned value:
`Pair<Vec<u8>, String>`. The maps retain one stored key, while the caller owns
an equivalent query key with a different representative tag, different text
and a distinct allocation. Equality/hash/order depend only on the rank.
Missing-key update must leave the mapper untouched.

The Grow mapper first pushes a byte into a full three-byte Vec, changing its
descriptor to length four and capacity six. It then appends seven UTF-8 bytes
to a full four-byte String, changing that descriptor to length and capacity
eleven. It returns those current owners in Pair.first and intentionally
returns `Result::Err` containing a separately allocated eleven-byte diagnostic
String in Pair.second. The caller verifies complete value contents and the
updated descriptors through the map before using any returned diagnostic.

The replacement mapper installs two previously reserved owners and returns
the complete displaced Pair. It performs no allocation or destruction. The
caller checks that the stored key representative and map allocation remain
unchanged, retires the map, its installed key/value and the independent query
key, and then checks the displaced Vec, displaced String and diagnostic
String again. Those three owners are explicitly released afterward.

Every run publishes the complete stored/query key bytes, replacement bytes,
displaced bytes and diagnostic bytes; the Rust driver compares all 51 bytes
with an independent expected output.

## Reached callback failures

Each selector runs one successful baseline and two narrow allocation-denial
cases. Failure sites are selected from allocations actually reached inside
the baseline Grow callback:

1. The initial Vec growth. The original Vec and String remain installed.
2. The subsequent String growth. The newly grown Vec and original String must
   remain installed together in the map despite the returned Result error.

The injected `ENOMEM` must be reached at the selected baseline `mmap` ordinal.
The driver compares the entire normalized allocation/release prefix before
denial and rejects any additional effect after that failed reservation in the
callback. Each process explicitly retries. The callback skips a stage that
already succeeded, produces the complete final value and independent owned
error, then continues through replacement and cleanup. The error-allocation
site is not part of this focused campaign.

## Effect and layout accounting

The complete syscall trace distinguishes initial setup, pure observations,
the enclosing update call, callback entry/exit and explicit caller cleanup.
No allocation or release is allowed in update_value outside its callback.
Callback effects are expected and are not mislabeled as map allocation.
The stored key, query key, replacement owners and map backing cannot be
released during callbacks. Pure observation phases allow no host calls.
Each present update has exactly one marked callback.

The seven setup allocations have source-derived extents:

| Owner | Bytes |
| --- | ---: |
| Stored key text | 10 |
| Query key text | 9 |
| Initial Vec payload | 3 |
| Initial String payload | 4 |
| Replacement Vec payload | 2 |
| Replacement String payload | 4 |
| HashMap table / TreeMap nodes | 832 / 512 |

The key has five native words: two scalar fields plus String's three-word Vec.
The Pair value has six words, making Entry eleven words. HashMap's Slot adds
an enum tag and cached hash, giving thirteen words times eight buckets:
`13 * 8 * 8 = 832` bytes. TreeMap's Node adds five link/height/free fields,
giving sixteen words times four reserved nodes: `16 * 8 * 4 = 512` bytes.
These use `core::mem`'s eight-byte native record words; scalar i32 packing
does not pack i32 fields inside records. Payload u8 storage remains packed.

The ledger retains full 64-bit addresses and exact extents, rejects overlapping
live allocations, unknown/double releases and incorrect release extents, and
requires every owner to retire before the final marker. After map destruction
it requires exactly the displaced Vec, displaced String and separate error
to remain live. Each complete baseline or denial/recovery run expects ten
successful allocations and ten explicit releases. Cleanup is observed before
process exit.

## Target and finite scope

ELF x86-64 admission and the shared complete jump validator precede execution.
Each selector has one baseline plus two failure/recovery native invocations,
each bounded to twelve seconds. Initial runtime evidence is Linux x86-64 CPU
programs from the GPU compiler. This does not establish device execution,
automatic lifetimes, unwind recovery, reentrant callbacks or formal proofs.
Collision/tree mutation schedules and broad value models belong to the
separate direct/model gates; this resource suite isolates ownership transfer,
descriptor replacement and callback allocation failures.

## Frozen hashes

- Driver:
  `338f444e7618acca9eacf9732734839d0976f943bf08677fbdede36b65edc925`
- `hash.lani`:
  `d9555f336bd4ed84fb31c6a3f3e4ae44784f580b13bd695437d6b11eea449fb9`
- `tree.lani`:
  `12ba2f59e897684108847b1bfda1c90106e8ba0ed419744f5a6959e17dd203fe`
- `fixture/owners.lani`:
  `44fea5b8dd38cd4e6164d159d9ff507e76c99bb29701d02709037edb52b927df`
