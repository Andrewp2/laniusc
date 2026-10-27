# Ordinary nested iterator owners

## Current acceptance

All **eight direct Python-driven native cases passed on their first attempt**
against one retained Linux x86_64 executable. They exercise the real ordinary
`Flatten` and `FlatMap` adapters with owned String items and a retirement policy
whose error type is the true empty `core::clone_values::Infallible` enum.

The root compiled `probe.lani` successfully on its first attempt, recorded in
`target/stdlib-work/infallible-nested-owners-admission-first.log`. It then ran the
unchanged oracle against that ELF:

```text
Log: target/stdlib-work/infallible-nested-owners-lifecycle-first.log
Evidence: /tmp/infallible-nested-owners-zvsp_l7g
PASS infallible-nested-owners cases=8 reached-oom=0
```

These are direct oracle receipts. The new Rust wrapper builds successfully with
`--no-run` in **1.75s**, recorded in
`target/stdlib-work/infallible-nested-owner-driver-build-first.log`. The emitted
driver is
`target/stdlib-build/debug/deps/stdlib_infallible_nested_ownership_execution-791d7d990cccd244`.
That build does not execute its registered test; no registered native rerun is
claimed. The **25 CPU controls** passed separately:
17 unchanged trusted source-ledger controls plus eight owner-partition and
post-setup allocation controls. Those controls establish no native execution.
The fixture author ran no Cargo, GPU compiler or native Lanius commands.

## Finite ownership cases

The eight cases are the product of these choices:

| Dimension | Choices |
| --- | --- |
| Inner storage | Actual `Vec::IntoIter<String>` or physically wrapped `Deque::IntoIter<String>` |
| Adapter | `Flatten` or `FlatMap`, yielding plain `String` items |
| Lifecycle | Exhaust directly, or stop with an active inner, take it, drain and retire it, then resume the remaining outer source |

Setup constructs three inner owners before traversal: an empty inner and two
three-item inners. Each owns collection backing and separate scratch storage.
Each row also owns an independent label String. The Deque has a nonzero head and
two physical spans; its logical item order is checked. Every output contains a
NUL, UTF-8 `é` and a supplementary scalar, and all bytes and item order are
checked while the actual String owner is alive.

The FlatMap mapper consumes a prebuilt row, releases its label and returns the
actual inner owner. It does not allocate or assume that fallible construction
succeeded. The retirement policy releases exhausted inner scratch and backing,
then returns `None`; it cannot construct an `Infallible` error. Setup has its own
fallible allocation path outside these ordinary APIs. This increment adds no
setup OOM campaign and makes no allocation-failure acceptance claim.

Construction, dormant `take_active`, and a zero-quota `take` run in a marked
scope with no source, inner, mapper or retirement effects. Repeated terminal
polls and finish calls are inert. In the early-stop case, `try_finish` rejects
the active inner without changing it or polling the outer source. `take_active`
then transfers the actual remaining cursor and closes the original adapter.
The consumer drains and retires that owner before constructing a new adapter
on the same remaining outer source. No consumed item slot is cleaned again.

The first emitted String stays owned by the consumer while all inner owners,
labels and outer backing are released. The consumer checks its bytes again,
then explicitly releases it. The old accepted Try-adapter fixtures and fault
receipts remain separate and unchanged.

## Live checkpoints and native accounting

Each process blocks for a host ACK at four live checkpoints:

| Phase | Actual live source allocation partition |
| --- | --- |
| 0 | 16 setup allocations: outer backing; three inner backings, scratch owners and labels; six String payloads |
| 1, full traversal | Outer backing plus the consumer's held String: two allocations |
| 1, early stop | Outer backing, active and untouched inner backing/scratch, six payloads including the held output, and the untouched label: 12 allocations |
| 2 | Only the held eight-byte String |
| 3 | No source allocations or nonstandard descriptors before exit is permitted |

Requested backing sizes come from public capacities and `sizeof`, rather than a
hardcoded ABI width. The oracle imports the unchanged accepted Try-owner helper
and its strict TempFile raw ELF verifier and full-width Source ledger. Each
allocation and free must match a verified instruction site, exact arguments and
live allocation length. Both verified `0x22` and historical `0x62` mmap profiles
are supported by that shared machinery. Unknown sites, unmatched frees and
unexpected host work fail the gate.

An additional ordinary-path check requires the entire source allocation-attempt
prefix to remain identical to setup at every later checkpoint and after exit.
Thus no new mmap is permitted during construction, traversal, mapper calls,
retirement or early recovery. Actual releases remain required. Independent
event-order checks require the empty inner's scratch and backing to be freed
before acquiring the next outer row. Live `/proc` maps and descriptors are
checked at each ACK, including absence of every admitted source mapping before
the final ACK permits process exit.

The accepted target is Linux x86_64 CPU execution emitted by the GPU compiler.
This is finite ownership and allocation evidence, with no user-program GPU,
performance, automatic destruction, shared-cursor concurrency or OOM claim.
Requirements are Python 3, strace with `--kill-on-exit`, objdump and readable
`/proc` mapping/descriptor state.

## Focused commands

The Rust driver is `tests/stdlib_infallible_nested_ownership_execution.rs` and
has one exact filter:

```text
ordinary_nested_owned_strings_retire_and_resume_without_allocating
```

The root can reuse the admitted ELF without recompiling:

```sh
python3 -B tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/oracle.py target/stdlib-work/infallible-nested-owners.elf
```

CPU-only controls:

```sh
python3 -B tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/oracle.py controls
```

Each child is limited to eight seconds, the Python group to 75 seconds and the
Rust wrapper to 85 seconds. Root serializes compiler and native execution.

## Frozen inputs

| Input | SHA-256 |
| --- | --- |
| Compiled and executed probe | `0a8aa0d46aa5e6673932b5e1e5f659babea505669c92d409c888356d8f2a1ee8` |
| Final `probe.lani` | `5bed1e45cf9e3d376dbc8a3ba60bda1413b5d1a14e28387f9da6fd241f3e13ed` |
| `oracle.py` | `7f7c77c89a7e72a9dc964530c854a502c5fa5750a4c3d22952b166f700438aac` |
| Rust driver | `ac80d317124d56836cbe5b1ae5fafca3248daa3d65bda360b71bad4fdabe1131` |
| `core::iter` | `5034fbac8a84b1499af18fbaf2963d54da4452e633413d33804b154e1a108a64` |
| `core::clone_values` | `f9761733b3a6762df0acff003e503f1601e6953fa7fedf40044d07b3b2ed9545` |
| `target/stdlib-work/infallible-nested-owners.elf` | `530cbe74ff82c8e6e7fd1148f7ff0bdf16d91b9d2736fb9e298e155dc2b34a0d` |

Final staging removed exactly one trailing ASCII space from the policy declaration
on line 221. The compiled and executed form is retained as
`target/stdlib-work/infallible-nested-owners-accepted-0a8aa0d4.lani`. The final
source differs only by that byte; the oracle, ELF and runtime receipts are
unchanged, and no execution of the final byte form is claimed.

The direct native log records no duration, so none is inferred. The full eight
cases are the accepted group scope, rather than a claim about every owning type
or a cumulative total that includes the separate CPU controls.
