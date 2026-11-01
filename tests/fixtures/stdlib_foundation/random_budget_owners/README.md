# Shared random budgets with real owners and byte strides

The registered gate passed compiler/native acceptance on its first execution:
one test in 7.61 seconds, recorded in
`target/stdlib-work/random-budget-owners-first.log`. Root performed all
executable commands. The accepted trace observed 41 mappings, 41 exact releases,
seven pure phases, three owner reports and two complete stride reports.
This fixture checks the public borrowed budget adapter through existing
shuffle, choose, fill and rejection sampling operations, following the
[draw-budget contract](../../../../docs/library-random-budget-plan.md).
Scripted words are test data; this is neither a generator implementation nor
a statistical test of uniformity or cryptographic suitability.

## Actual nested owners

Ten generic `Record<Pair<Leaf>>` values include an eight-element selected View
and two untouched outer guards. Every record owns two UTF-8 Strings and two
Vec<u64> buffers. Strings include NUL and multibyte UTF-8; numeric payloads
include values above 2^63 and near u64::MAX. Forty distinct nested buffers and
one outer record backing give **41 actual owners**.

The fixture snapshots all nested pointers and capacities. Every ownership
check compares complete IDs, serials, lengths, capacities, String bytes and
numeric payloads. All ten IDs must remain present exactly once after both
successful and failed shuffles, including the untouched guard IDs. There are
no Clone or Destroy implementations for these generic records. Temporary
shallow values do not acquire another cleanup authority.

`choose` returns a shallow copied record. The fixture changes a numeric value
through that copy's existing Vec backing and verifies the original owner slot
observes the same change. The allocation pointer, length and capacity remain
unchanged. The copied choice is never independently destroyed. Final slot
traversal releases every String/Vec exactly once and the record backing last.

## Seven pure phases

| Phase | Contract exercised |
| --- | --- |
| 1 | Two adapters share one two-draw budget. Shuffle accepts one step, rejects the next word and exhausts without another source call; choose through the second adapter remains exhausted. |
| 2 | A complete eight-element shuffle uses exactly its last allowed draw. Subsequent choose cannot silently reset the budget. Self-swaps count as completed steps. |
| 3 | After one successful swap and a rejected word, the source returns Host(-90210). That failed call spends budget, leaving one draw for a successful choose and shallow alias update. |
| 4 | Empty/singleton owned ranges require no draw even with a zero budget and a source that traps if called. |
| 5 | Three zero-sized Unit elements have actual native stride zero; shuffle consumes exactly two draws, exhausted choose fails, and singleton choose still requires no draw. |
| 6 | Native descending-byte fill checks limit/error prefixes, successful split fills and shared exhaustion. |
| 7 | Packed ascending bytes repeat the same fill checks from an unaligned base+1, including all surrounding physical guards. |

The fill phases check three sequences on each actual backing. A one-draw
ten-byte request initializes exactly eight bytes before DrawLimit. Two
successful five-byte fills share one two-draw budget and discard unused word
bytes rather than carrying them into the next operation. A source error on
the second draw leaves the exact first eight bytes initialized and spends
budget; rejecting the final available word then exhausts without another
source call. All sixteen logical destination bytes and packed outer guards
are checked. Zero-count fill at offset i32::MAX makes no source/backing access.

These tests intentionally create a fresh budget for each independent phase
or fill scenario. Within each sequence the same borrowed counter spans all
operations and rejection attempts; it is never reset per sampling/shuffle
step. Adapter and source lifetimes remain explicit caller obligations.

## Independent observations and host effects

Three 64-byte reports contain actual shuffle permutations, source-call counts,
remaining budgets, completed suffix positions and the chosen ID. The host
model computes thresholds as exact `2^64 mod bound` using u128, independently
of the production wrapping-negation expression. It checks each permutation
against both a scripted Fisher-Yates model and literal ID sequences.

Two 80-byte reports carry the final complete native/packed byte buffers plus
progress and source counts. Host expectations derive the error-prefix bytes
with `u64::to_le_bytes` and compare every sentinel. CPU-only controls checked
the three owner permutations, four literal word/byte vectors and the two
nonzero rejection thresholds. The full randomized operation-sequence model
and scalar sampler coverage belong to separate gates.

The registered driver requires genuine x86_64 ELF and shared strict jump
admission, traces all syscalls, and rejects every host service inside P/p.
Outside those phases it permits only process entry/exit, explicit markers,
the five bounded reports and the actual mapping/release lifecycle. Each
mapping address and extent must match one successful release, all 41 owners
must retire, and the outer record backing must be last. D is accepted only
after cleanup is complete. This is a finite fixture ledger, not an automatic
resource checker or general ownership proof.

A 20-second native lifecycle deadline bounds the test, not arbitrary source
draw duration. Accepted executable scope is finite Linux x86_64 CPU output
from the GPU compiler. GPU-device execution, arbitrary source behavior,
thread safety, automatic borrowing/ownership and formal correctness are
unclaimed. No compiler, runtime, ABI or production crypto code is changed.

| Executed source | SHA-256 |
| --- | --- |
| `owners.lani` | `91c350361f7ca202faac83fe28f603e422754f5e7ea67d724d24ef2eb202aa8d` |
| Rust driver, tested before formatting | `52d51d992930ace8f9c2c4c0de77959713ff291af9785672b50ceb142390780a` |

```text
cargo test --test stdlib_random_budget_owner_execution budgeted_random_operations_preserve_nested_owners_aliases_strides_and_exact_progress -- --exact
```
