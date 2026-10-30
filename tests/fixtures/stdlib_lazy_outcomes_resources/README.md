# Lazy outcome owner and effect witnesses

Both native resource groups passed after the header-only repair recorded below.
Independent read-only source and ledger review passed, including a separate
review of the exact module header repair. Review did not run the compiler or
native programs. These are two registered resource groups, with two
baseline executions and one selected callback failure execution. They complement
the direct branch/type table and finite composition model; they do not repeat
all nineteen APIs.

## Selectors

- `lazy_outcomes_transfer_nested_owners_and_leave_discarded_resources_to_the_caller`
- `lazy_outcomes_return_callback_allocation_failure_owners_for_same_process_retry`

The driver is `tests/stdlib_lazy_outcomes_resources_execution.rs`. It requires
native Linux x86_64 output from the GPU compiler, `strace`, and the existing
shared strict ELF/jump admission helpers. It does not execute library code on a
GPU device.

## Ownership observations

`owners.lani` starts with six independent owners, each containing a real
`Pair<Vec<u8>,String>`. A selected `Option.map` callback takes the first owner's
sole cleanup authority, constructs independent replacement backing, destroys
the input, and returns the new owner inside a Result. A selected `Result.map_err`
callback takes and destroys a second owner and returns its scalar identifier.
All older descriptor aliases remain inactive after authority transfer.

Five pure observation phases cover:

- An eager owner fallback that is unused by `map_or` and still needs explicit
  caller cleanup, while the selected owner keeps its original backing.
- A rejected `filter` payload plus all four Boolean predicates. The callback
  checks every payload byte and both backing pointers without mutating or
  retaining the payload; only an external call counter changes.
- Skipped Mapper and Producer implementations that would allocate a genuine
  temporary and return an ordinary error if called. Their call counter stays
  zero, and the retained successful owner remains usable.
- Selected zero-sized callback objects with zero-sized input, exact return
  values, and complete final byte/identity checks for all remaining owners.
- The independently returned output after all unrelated owners are retired.

The unused eager fallback and rejected predicate payload are deliberately
destroyed by the caller. They are not silently dropped by the library.

`failure.lani` drives a selected `Result.and_then` callback. The callback first
allocates an eight-byte Vec, then a twelve-byte String. Only the second reached
callback allocation is denied. On that ordinary error return, the callback
destroys its partial Vec and returns the original owner inside `Failure`.
The same process checks every original byte, length, capacity and full-width
backing identity, then transfers that returned owner into a retry. Success
retires the original input and returns an independent replacement. Both the
baseline and recovery publish all twenty replacement bytes after input
retirement and then explicitly destroy the result once.

This is a callback allocation-failure test. The outcome library itself does not
allocate; there is no fabricated library OOM campaign, implicit rollback, or
automatic destruction claim. The callback's first allocation failure branch is
implemented but is not part of the selected fault campaign.

## Effect ledger and source-derived extents

All marker-delimited pure phases reject every intervening syscall. The complete
`trace=all` ledger permits allocations only during initial owner construction
or inside a selected callback's own `B`/`b` markers. Releases likewise occur only
inside selected callbacks or explicit caller cleanup. Library dispatch before
and after the callback cannot allocate or release resources.

Each owner uses `Vec<u8>::with_capacity(8)` and `String::from_utf8` with twelve
bytes. `Vec<u8>` backing is packed one byte per element, and String uses its
packed Vec backing. Thus reservations are exactly 8 and 12 bytes; the containing
Pair and Owner values do not introduce heap allocations. This comes from the
constructors and storage contract, not observed allocator page sizes or a
guessed C record layout.

The ledger retains full-width addresses and requested extents, rejects overlap
and duplicate/unknown/wrong-extent releases, and checks exact live owner sets
at callback return and every publication. The allocation denial is selected
from the baseline's reached callback sites, and its complete normalized effect
prefix must match that baseline. Partial result cleanup is checked before the
failure returns. Cleanup completion is observed before process exit rather
than inferred from a successful exit status.

## Accepted native receipt

Root's `target/stdlib-work/lazy-outcomes-resources-retry.log` completed with exit
0: two passed, zero failed in 7.71 seconds at the frozen identities below. This
is two registered groups comprising two baseline processes and one selected
callback-denial process.

| Native execution | Exact maps/releases | Pure phases | Complete output | Native time |
| --- | ---: | ---: | ---: | ---: |
| Selected transforms, discarded owners and skipped callbacks | 14 / 14 | 5 | 20 bytes | 0.006557 s |
| Allocation callback baseline | 4 / 4 | 1 | 20 bytes | 0.006568 s |
| Reached second callback allocation denial and same-process retry | 5 / 5 | 2 | 20 bytes | 0.004426 s |

The positive group observed two effectful callbacks. The failure execution
reached `mmap` ordinal 4, released its partial result before returning the
original owner, invoked the callback exactly once more for recovery, and
released every successful allocation exactly once. The full source and output
checks and exact live owner sets passed; no additional library allocation or
release occurred around the callbacks.

Compilation took 1.881552 seconds for `owners.lani` and 5.805240 seconds for
`failure.lani`; the denial reused the compiled artifact. Native times include
process, strace, setup, checks, publication and cleanup. These small finite
resource witnesses establish no broad performance or GPU-device execution
claim. The initial failed compile below is history, not an extra accepted group.

## Frozen source identities

- Driver: `00f9b586222f0b57dee3a70e3140852b6a9fb560c90a14ad6a6df2470c6f2de8`
- `owners.lani`: `42d17417bef6ac2e9c20e5bba0481d1097dfe7cd1fe1b361944be6deff6ccb8e`
- `failure.lani`: `5038b0023abdc4275b3894faa99f55da543361624a5c45958cee9f8dcc8a01ea`
- `fixture/owners.lani`: `4de144f825b3003c0db98646f0523193fe99ea4a1fd0eda45902f72dad495304`

## Attempt history

The first root run, `target/stdlib-work/lazy-outcomes-resources.log`, ended with
exit 101: zero passed and two failed in 4.49 seconds. Both entry fixtures lacked
the `module app::main;` header before their imports and failed with LNC0016 at
`fn main` (`owners.lani:9:1`, `failure.lani:5:1`). No native resource program ran,
so that attempt supplies no runtime acceptance.

The repair adds only the missing module declaration to each entry fixture,
matching the already accepted imported-fixture convention. Driver, support
module, callback bodies, owner operations, allocation expectations and effects
remain unchanged. Original producer hashes were `583aa584` and `b16df227`;
the repaired complete hashes are recorded above. This is a test fixture syntax
error, not a compiler implementation change.
