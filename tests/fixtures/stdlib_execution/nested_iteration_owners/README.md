# Nested iterator ownership and failure fixtures

## Status

All four direct host-oracle groups pass against the same retained native
executable. The root ran the serialized compiler/native gates; no native, Cargo
or GPU execution was performed by the fixture author. The `core::iter` source is
`7256a39462db691ece403a6d9a409947f7fafa7919783be474d510f1bf63ce3c`.
The separate public scalar smoke receipts establish their own narrower cases.

The first lifecycle gate failed before native emission on source `ff7df4af`:
GPU parser stack-effect code 4/detail -4, followed by a host fallback label on a
concrete Mapper trait argument. Separating generic closing angles did not change
the failure. Reductions identified the unsupported applied `where` subject
`Make<J>:Mapper<...>`; the canonical grammar requires a bare identifier there.
The corrected helper borrows its caller-owned concrete mapper through a bare
generic `M` bound, preserving the same owning types, callback lifetime and
behavior. That correction passed parsing, then failed source-pack typechecking
at an inferred generic cursor result (`found.is_none()` in `deep_inner`). The
accepted fixture uses explicit `J` cursor locals and canonical Option result
annotations, reinstalling the actual mutated cursor before reuse or retirement.
These are fixture source corrections; no compiler change or arbitrary generic
type limitation is claimed. Native source admission succeeded. The first native
oracle attempt then exposed a harness count error: lazy flat-map retirement
failure constructs two inners, whereas flatten prebuilds three. The corrected
independent model preserves every strict live-map/fd, callback and fault check.
The
original source, minimal rejected/accepted pair and receipts are preserved in the
[compiler-state isolation](../../stdlib_compiler_state/nested_iteration_owners/README.md).

The oracle's **41 CPU controls** pass separately: 17 unchanged full-width source
ledger controls and 24 callback-phase/fault-binding/model controls. These are
harness checks and do not establish Lanius execution.

## Scope

`probe.lani` calls the real `try_flatten` and `try_flat_map` APIs. Each inner owns
either a `Vec<String>::IntoIter` or a physically wrapped
`Deque<String>::IntoIter`, plus a separate five-byte scratch allocation. Items
contain a NUL, UTF-8 `é`, and a supplementary scalar. Retirement and mapper errors
own a separate five-byte String with a NUL and non-ASCII data. Allocation failure
uses a distinct, allocation-free fault value.

The fourteen healthy lifecycle profiles cover both backends and both adapters:
complete traversal, partial retirement failure, early `take_active` and resume,
plus flat-map partial-construction failure. They check:

- Lazy construction, dormant close, no polling after closure or emitted error,
  and active `try_finish` rejection without losing the active owner.
- Empty inner retirement and actual scratch/backing releases before another
  outer acquisition, through an independent row/callback schedule.
- A returned partially retired inner whose mutated step is retained, scratch is
  already freed, and backing is still owned. Recovery retires that actual value.
- Explicit deep cleanup of the remaining owning outer cursor. Consumed inner
  slots are not destroyed through stale backing aliases.
- First output and owned error remaining readable after inner/outer cleanup,
  followed by explicit single release and inert repeated destroy calls.
- Flat-map failure after constructing and freeing a temporary allocation; that
  callback cleans its own partial construction before returning the error.
- Early recovery followed by construction of a later inner. Every reached
  allocation during that resumed mapper is included in its own OOM campaign;
  an earlier held output survives the later failure.

The [semantic action-schedule and generic-shape models](../../stdlib_foundation/nested_iteration/README.md)
live separately. This fixture focuses on real resource ownership.

## Native boundary and fault evidence

The accepted target is **Linux x86_64**, compiled by the GPU compiler to a native
CPU executable. This is not GPU-kernel execution or portable host acceptance.
Required tools are Python 3, strace with `--kill-on-exit` and syscall injection,
objdump, and readable Linux `/proc` maps/fd state.

The host oracle imports the unchanged raw allocator instruction verifier from
`temp_file/ledger.py` through `extended/archive_source/ledger.py`. Each source
allocation/free must have an exact verified raw-image syscall site, full-width
address, expected flags (`0x22`, or separately verified historical `0x62`), and
exact requested release length. Unknown sites, repeated frees and outstanding
owners fail. No named-ELF or low-address-only fallback is used.

Four acknowledged frames stop the real process at setup, stopped traversal,
after deep cleanup with only held output/error Strings, and after all releases
before exit. Actual `/proc` mappings and descriptor sets are inspected while the
child is alive. The third frame's live requested maps must be exactly the
reported output/error String capacities. The final frame requires no source
owners, no remaining source mappings and only descriptors 0, 1 and 2. Process
exit is not counted as cleanup.

`C/c` brackets adapter construction and requires no native calls or callbacks.
`T/t` brackets traversal; `K/k` brackets explicit recovery. Source allocations
inside these phases are allowed only within the `M/m` mapper or `R/r` retirement
callback. Thus the adapter itself may not allocate. Actual source/consumer
markers and exact phase nesting are checked against stderr and the syscall log.

Each OOM group first records the actual baseline executable's reached source
allocations. It denies every such allocation with one
`inject=mmap:error=ENOMEM:when=N` option. The reached run must retain the entire
baseline source allocation prefix, exact instruction pointer, arguments,
per-syscall ordinal and callback phase; it must have exactly that one injected
failure and no later allocation. Every denial must return the typed allocation
status and reach all pre-exit release checkpoints. No synthetic returned object,
duplicate injection option or output-memory poke is used.

The flatten OOM profile includes setup construction and the owned retirement
error for both backends. Its healthy early resume allocates nothing after setup.
Flat-map sweeps all four profiles for each backend, including allocations during
resumed construction and partial mapper failure. Counts are derived from the
actual receipts below.

## Current native receipts

These are **direct Python oracle** executions against the unchanged retained
`target/stdlib-work/nested-public-owners.elf`, SHA-256
`3d99ec693eee833df297e5201e992210761845707a21ce00f7d176bc58b7d32c`.
It was emitted by the Rust driver's GPU compiler call from source `e92ee3b8`,
then retained from `/tmp/laniusc_nested_iteration_owners_probe_449613_0`.

| Group | Accepted group cases | Individually reached ENOMEM denials | Log under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| lifecycle | 14 | 0 | `nested-owners-lifecycle-lazy-count-retry.log` |
| flatten-oom | 30 | 28 | `nested-owners-flatten-oom-first.log` |
| flatmap-oom-vec | 56 | 52 | `nested-owners-flatmap-vec-oom-first.log` |
| flatmap-oom-deque | 56 | 52 | `nested-owners-flatmap-deque-oom-first.log` |

Total scope is **156 group cases**, including overlapping healthy baselines and
**132 individually reached OOMs**. This is not cumulative execution counting:
earlier failed attempts and repeated baselines are not added to it. No duration
is inferred for these direct commands. Evidence directories are respectively
`/tmp/nested-owners-lifecycle-mc0e0zf2`,
`/tmp/nested-owners-flatten-oom-1awbbr7d`,
`/tmp/nested-owners-flatmap-oom-vec-y400i345`, and
`/tmp/nested-owners-flatmap-oom-deque-rh94jqd9`.

The Rust driver built and compiled the actual probe, then its native lifecycle
attempt failed the old lazy/eager counter assertion; the mixed attempt is
`nested-owners-lifecycle-typed-cursors.log` (8.66 seconds). The root reused that
exact ELF for all accepted direct groups after the oracle-only correction.
**Four passing Rust library tests are not claimed.** The two earlier parser
rejections and the later source-pack typecheck rejection emitted no executable.

## Focused commands

The root runs the four filters separately with `--exact --nocapture`, or can
reuse the admitted executable directly with the corresponding Python group:

```text
stdlib_nested_iterator_ownership_execution
  nested_owners_recover_actual_partial_state_before_explicit_release
  flatten_every_reached_owner_allocation_failure_releases_before_exit
  flat_map_vec_every_reached_allocation_including_resume_is_recoverable
  flat_map_wrapped_deque_every_reached_allocation_including_resume_is_recoverable

python3 -B tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py lifecycle ELF
python3 -B tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py flatten-oom ELF
python3 -B tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py flatmap-oom-vec ELF
python3 -B tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py flatmap-oom-deque ELF
```

Each child is bounded to eight seconds, each Python group to 75 seconds, and each
Rust oracle wrapper to 85 seconds. Compiler admission is a separate root gate.

CPU checks, without compiling or executing Lanius:

```sh
python3 -B tests/fixtures/stdlib_execution/nested_iteration_owners/oracle.py controls
```

## Frozen inputs

| Input | SHA-256 |
| --- | --- |
| `probe.lani` | `e92ee3b894a6ce93eafed81a217ef9f04dd5dcf610239ea1c8cb503a608fdfc4` |
| `oracle.py` | `eb37f1429b6b5496b2b301bf2d960647062a490c62241ad9277de5cc9414ae31` |
| Rust driver | `4038e6c3b57075171a40358e13c2a9d6545857d935538c60e588ca676c0f47af` |

No destructor-on-drop, alias-safe manual owner copies, shared-cursor concurrency,
or effects beyond these finite profiles are claimed. The API transfers cleanup
authority explicitly; owners left in the outer cursor remain the caller's
responsibility.
