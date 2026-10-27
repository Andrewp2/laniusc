# Replacement sink owners and reached failures

## Current status

All five full resource/fault groups now pass as **direct Python oracle** runs
against one retained native Linux x86_64 ELF. They cover **219 group cases**,
including overlapping baselines and four explicitly unreached denial controls,
with **183 individually reached OOMs**. Exact scopes are recorded below.

The small **actual stdlib** ownership composition in `admission.lani` compiled
and executed successfully on native Linux x86_64. The root ran both commands;
the fixture author ran no Cargo, GPU or native Lanius commands.

- Source: `7b7f5c987c66f0eac602aed6beaa5d0de0b1ab83e78094d30f4a137ac7a52ad4`.
- Logs under `target/stdlib-work/`: `replacement-owners-admission-first.log` and
  `replacement-owners-admission-native-first.log`.
- ELF `replacement-owners-admission.elf`:
  `b61732428d71c00683784d97ae5789724eb58f611347c41c4a6fe86feafafd7c`.

That receipt covers an actual `TreeMap<Key,String>` at full capacity, an owning
Entry input cursor, a conforming displaced sink with an independently owned
String error, and `Undelivered` progress including the current commit. It checks
the new key/value remain stored, the complete old key/value are returned, and
the source remainder is intact, then explicitly cleans all owners. It has no
native allocation ledger and establishes no fault campaign or other facade.

The full `probe.lani` is also admitted and accepted. Its first
compile-only attempt (`d7456086`) failed before native emission on an ambiguous
unqualified `InvalidCapacity` pattern: both imported map Error types export
that variant. Log: `replacement-full-owners-admission-first.log`. The candidate
now qualifies each pattern with its concrete defining module. This is a fixture
name correction, with no compiler or behavior change claimed. The qualified
candidate (`b3ff91c1`) then failed LNC0075 because public `Payload<T>::make`
returned private `BuildError`; log `replacement-full-owners-qualified-errors.log`.
The final source adds `pub` to that fixture enum. The two failed source admission
attempts emitted no full executable; they changed no ownership behavior. The
corrected source (`86a0d81e`) compiled successfully, recorded in
`replacement-full-owners-public-error.log`. No production or compiler change was
needed. Independent review found no material issue in the final probe, oracle or
driver.

The **45 CPU controls** pass separately: 17 unchanged trusted live-ledger controls
and 28 phase, provenance, and independent owner-model controls. They do not
establish native library execution.

## Full fixture contract

The full probe calls the real `try_replace_up_to` and all four real facade
implementations: HashMap, TreeMap, HashSet, and TreeSet. Map entries independently
own key-representative and value Strings. Set representatives independently own
their String. Logical key identity ignores representative metadata; hashing is
deliberately collision-heavy and ordering uses logical identity. Every String's
eight bytes include a NUL, UTF-8 `é`, and a supplementary scalar, and are checked
while their real owners remain alive.

A test forwarding sink brackets **one** actual facade call with `R/r`; it has no
replacement algorithm, rollback, parallel storage or owner clone. The displaced
`D/d` sink uses a separate owning Vec, rejecting before retaining on a logical
history limit or actual Vec growth failure. A logical rejection owns an
independent five-byte error String. Error-String OOM has a distinct allocation
cause and keeps the complete old item recoverable.

Four profiles per facade execute:

1. Initially absent keys and repeated identities, with enough distinct keys to
   reach actual replacement-storage growth and to retain an accepted old prefix.
2. Repeated replacement with an initially unallocated displaced collector.
3. Replacement at the actual reported full collection capacity, with history
   reserved first. The transfer phase must perform **no mmap**. One denial armed
   after the baseline's final allocation remains explicitly unreached, rather
   than being counted as OOM evidence.
4. Logical history rejection after an earlier successful delivery. New data stay
   committed, complete old data and the owned error remain outside history, and
   the unconsumed source remains recoverable.

Every profile also performs a zero-quota call under `C/c`, requiring no source,
replacement or delivery callback, no native work, zero progress and no EOF probe.
Actual transfers use `u64::MAX` without narrowing the quota.

## Checkpoints and recovery

The process waits for host ACK at five points:

| Phase | Live ownership checked |
| --- | --- |
| 0 | Fully constructed source, destination and history, before transfer |
| 1 | Stopped initial transfer: exact committed prefix, current new representative, accepted history, returned incoming/old owner, error and source remainder |
| 2 | Pending owner successfully resolved before resuming source; final destination/history, exhausted source backing and original owned error |
| 3 | All collection/source backing released; only one transferred complete old item and the original error remain |
| 4 | All source owners released before ACK permits exit |

On `Rejected`, the incoming item is retried once per bounded recovery iteration.
On `Undelivered`, only delivery of the old item is retried; replacement is not
repeated. Earlier owned error storage remains live through later recovery OOM.
The fixture explicitly retains the old item on a failed collector retry, then
retries before the source can resume. Recovery is bounded to 16 iterations for
the finite inputs and each campaign injects one failure.

After successful redelivery, the old failure/local descriptor has no cleanup
authority. Phase 3 obtains the original Undelivered old item by an actual
`history.pop()` transfer matched to its recorded representative, then releases
other history owners. It never cleans a stale failure alias. For a successful
profile or precommit failure, it similarly retains an actual popped old owner.

Setup OOM cleans every partial owner before even phase 0 is acknowledged. The
remaining frames explicitly show that empty state; no constructor failure is
silently treated as a successful transfer.

## Native accounting and finite scope

The oracle composes the unchanged TempFile raw ELF verifier and archive Source
live ledger. Every source allocation/free must match an exact verified syscall
site, full-width address, requested size and flags (`0x22`, or independently
verified historical `0x62`). Unknown allocation sites and unmatched releases
fail. Live owner roles, public item `sizeof`, source/history capacities and
reported complete owner rows are checked at each stop. Final source mappings
and all nonstandard descriptors must already be absent in `/proc` before exit.

The independent queue/dictionary model compares complete representatives, values,
source position, accepted old-item order, failure tag and wide progress. A
precommit failure must return the incoming owner unchanged. Failed delivery
must include the current commit and return the **old** owner, with the new owner
in the actual map/set. Callback order must stop immediately on failure.

OOM campaigns deny each actual reached baseline mmap position, separately per
facade. Every reached denial is tied to the exact source IP, complete arguments,
syscall ordinal, phase and callback role, with the entire preceding allocation
prefix unchanged. There is exactly one injected failure. Setup denial allows no
later allocation; runtime denial allows legitimate later **K-phase R/D recovery
allocations**, with the same strict native provenance and complete owner checks.
It does not apply an incorrect no-later-allocation rule to successful retry.

The receipt separates setup construction, replacement growth, displaced growth,
owned-error construction and recovery growth. Each category must actually be
reached. A failing replacement or displaced-growth callback must preserve the
live native allocation set from just before that callback. Full-capacity healthy
replacement avoids growth. The current receipts establish these finite cases.

The accepted target is Linux x86_64 CPU execution emitted by the GPU compiler.
Requirements: Python 3, strace with `--kill-on-exit` and injection, objdump, and
readable `/proc` maps/fd state. No user-program GPU execution, automatic drop,
shared-cursor concurrency, arbitrary host or broad performance claim is made.

## Current direct native receipts

Every group below used unchanged full source `86a0d81e` and oracle `e10ee099`,
against `target/stdlib-work/replacement-full-owners.elf`, SHA-256
`e62aeff43f5d2d4b211adc363cc482b157b7c012d1187e703dddd65f49c0f896`.
Logs are under `target/stdlib-work/`; the direct logs contain no elapsed time,
so no duration is inferred.

| Group | Group cases | Reached OOMs | Log |
| --- | ---: | ---: | --- |
| lifecycle | 20 | 0 | `replacement-owners-lifecycle-first.log` |
| hash-map-oom | 63 | 59 | `replacement-owners-hash-map-oom-first.log` |
| tree-map-oom | 57 | 53 | `replacement-owners-tree-map-oom-first.log` |
| hash-set-oom | 41 | 37 | `replacement-owners-hash-set-oom-first.log` |
| tree-set-oom | 38 | 34 | `replacement-owners-tree-set-oom-first.log` |

Lifecycle is 16 healthy facade/profile combinations plus four explicit
full-capacity controls with an armed but unreached allocation denial. The four
OOM groups each include four overlapping healthy baselines. Their actual reached
denials divide as follows:

| Facade | Setup | Replacement growth | Displaced growth | Owned-error construction | K-phase recovery growth |
| --- | ---: | ---: | ---: | ---: | ---: |
| HashMap | 53 | 2 | 2 | 1 | 1 |
| TreeMap | 47 | 2 | 2 | 1 | 1 |
| HashSet | 31 | 2 | 2 | 1 | 1 |
| TreeSet | 28 | 2 | 2 | 1 | 1 |

The sum is **183 individually reached OOMs**. The **219 group cases** are the
scope of these accepted groups, not a count of unique scenarios or cumulative
attempts including the earlier source failures. The small admission program and
the separate 45 CPU controls are not added to that group count. All K-phase
recovery denials actually executed; later successful recovery allocations were
checked with the strict ledger.

Evidence directories, in table order:

```text
/tmp/replacement-sinks-lifecycle-02xs8rjs
/tmp/replacement-sinks-hash-map-oom-xe6r7fwv
/tmp/replacement-sinks-tree-map-oom-ej46apb4
/tmp/replacement-sinks-hash-set-oom-4hzxsuv0
/tmp/replacement-sinks-tree-set-oom-hxwshcwa
```

These receipts establish direct Python-driven native acceptance. **Five passing
Rust tests are not claimed**; the Rust driver is a separate wrapper/build gate.
It and the application driver build together in 3.42s with `--no-run`, recorded
in `target/stdlib-work/replacement-app-owner-driver-build-first.log`. That
shared build does not execute either driver's registered tests.

## Focused gates

The Rust driver has five exact filters:

```text
complete_replacement_owners_survive_recovery_and_release_before_exit
hash_map_replacement_and_history_each_reached_allocation_is_recoverable
tree_map_replacement_and_history_each_reached_allocation_is_recoverable
hash_set_representative_and_history_each_reached_allocation_is_recoverable
tree_set_representative_and_history_each_reached_allocation_is_recoverable
```

The root may reuse the admitted full ELF without recompilation:

```sh
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py lifecycle ELF
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py hash-map-oom ELF
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py tree-map-oom ELF
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py hash-set-oom ELF
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py tree-set-oom ELF
```

Each child is limited to eight seconds, each Python group to 75 seconds and the
Rust wrapper to 85 seconds. Root serializes all compiler/native execution.

CPU-only controls:

```sh
python3 -B tests/fixtures/stdlib_execution/replacement_sinks/oracle.py controls
```

## Frozen full inputs

| Input | SHA-256 |
| --- | --- |
| `probe.lani` | `86a0d81ecf0377ec4a788ac603f9f89cfb1f5fd0ff86c28c88e82fd656112c7c` |
| `oracle.py` | `e10ee099eef08286d4e3da8ed0577ed09d9e823308448f3ecaf58499a6c8c9bc` |
| Rust driver | `07caae3f50e49da7fc73bef630a179b5fdaf44b4240d2456b5e8df114363eb0e` |

The production inputs for these receipts are:

| Module | SHA-256 |
| --- | --- |
| `core::iter` | `a6fc9e0d63c55088c66eb70d33b425a224d4672c4cd32743cfcad3639bac79af` |
| `alloc::hash_map` | `f3e6b36340c74402bbdb970619800b85e3c70980b529d8f3bae3602afca91095` |
| `alloc::tree_map` | `01904e6481ceb83c025990b832e755f3eb8c6e7b9ddf71db04d951f63faed02c` |
| `alloc::hash_set` | `eeba04ae4a8f6cef1469c67269f5dcb3c6eefa30632cebda9d0fdf595979f3d0` |
| `alloc::tree_set` | `bd3cec1c95ceb32ef46909a3c2b533187967e5138c33690b7928cdf8750212ee` |
