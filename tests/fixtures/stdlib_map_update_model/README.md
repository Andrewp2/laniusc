# Independent scoped map-update model

`model.lani` runs one bounded binary batch through the actual HashMap and
TreeMap. `oracle.py` keeps an ordinary Python dictionary of full entries;
it contains no bucket probing, tombstone handling, AVL rotations or tree
lookup implementation. Every action is followed by an immediate query and
the complete native iterator contents. Hash iteration order is deliberately
unconstrained; duplicate keys are rejected. Tree iteration must be ordered.

The corpus has **72 cases**, **7,896 actions**, **3,128 present callbacks**,
**1,472 missing updates**, **728 installed updates returning Result::Err**,
**884 present updates returning Option::None** and **111,960 observed entries**.
Seed: `0x6a90261111`. Nine operation schedules are instantiated for two value
shapes. HashMap receives three stable hash policies (all keys collide,
three hash groups, distributed hashes); TreeMap receives each schedule once
per shape. Repeating hash policies on the tree would add no useful coverage.

## Behavior observed

- Insert, equivalent-key replacement, remove, update, clear and observation;
  empty and singleton states; ascending, descending and balanced insertion
  histories; removals from root/interior/leaf positions, reinsertion and
  tombstone reuse; seeded mixtures at five key-domain sizes.
- Full-width query stamps differ on every action. Updates retain the stored
  representative, while replacement insertion returns the old representative
  and installs the new one. Removed and replaced entries are compared fully.
- Scalar `V=u64` with `R=Option<u64>` distinguishes outer missing from
  `Some(None)`. Compound V contains `u64`, `Option<bool>` and `[i32;3]`;
  compound Result success/failure payloads retain old/new V and full-width
  callback data. An Err result does not undo the installed value.
- Callback order, count, input value, chosen new value and return value are
  recorded exactly. The reference tracks a single ordinal across insert,
  remove and clear operations. Missing keys cannot cause a callback.
- The producer checks unchanged public map allocation/count/capacity and
  map-specific structural metadata around each update. It also requires a
  second exhausted iterator pull to return None. Private node fields and
  allocator effects have separate focused contract/resource tests.

Callbacks borrow only their own context/output buffer. They never access the
map. These finite tests do not establish automatic borrow checking, physical
lifetimes, nonaliasing, ownership safety for arbitrary values or formal proof.
Selected owned values and reached allocation failures belong to the separate
resource gate.

## Protocol and bounds

There are at most 31 live logical keys and 192 actions per case. Input is
strict little-endian raw binary with fixed five-word case/action headers;
there is no JSON transport. The producer uses 7,680 bytes of action backing
and a 4,096-byte output staging buffer. Output includes every array lane and
optional/result discriminant. The verifier rejects malformed tags, duplicate
entries, missing/truncated/trailing records, nonzero native status and stderr.
One native process handles all cases, with a 75-second child deadline inside
the Rust harness's 90-second reference deadline. Root bounds each outer gate
to 100 seconds.

## Evidence

Host-only controls passed: **17 deliberate corruptions rejected**, including
omitted/extra callbacks, wrong ordinals/input/new values, nested optional
confusion, Err rollback, changed key representatives, callback count changes,
lost/duplicate entries, wrong ordered iteration and array-lane corruption.
The accepted synthetic output is 5,915,556 bytes. These controls exercise the
verifier; they are not native compiler/runtime evidence.

Native gate passed: **1/1 in 6.90 seconds**, with a separate **1.60-second
Rust build**, exit status 0. Root recorded the complete expected summary in
`target/stdlib-work/map-update-model.log`:

```text
map-updates cases=72 actions=7896 callbacks=3128 missing=1472 result_errors=728 some_none=884 snapshot_entries=111960 families=2 shapes=2 hash_modes=3 seed=0x6a90261111
```

Tested SHA-256 sources:

- Producer: `e5bf7b705180ded6f7b4801e50c077df28e45fd6a9f6615a519e81621664d75b`
- Oracle: `3b5b1338700288bca9798debdb34b9b218ae60824853347e614122a3a7244ce2`
- Driver: `a8278f71d92cfe4fb7b49f41f4d4de442a0bcd2d167d0781837f6c614b850e33`

Focused selector:

```text
cargo test --test stdlib_map_update_model_execution map_updates_match_dictionary_contents_representatives_and_callback_events -- --exact --nocapture
```

This receipt is Linux x86_64 CPU execution of an ELF produced by the
GPU compiler. No GPU device execution, other platform or proof claim is made.
