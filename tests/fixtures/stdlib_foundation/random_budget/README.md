# Shared random draw-budget direct contracts

All three registered direct tests passed across two commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/random-budget-admission-first.log` | One admission test and native process | 5.20s |
| `target/stdlib-work/random-budget-direct-first.log` | Two tests: one native six-scenario contract process and one marked LNC0008 rejection; admission filtered | 8.14s |

Root ran the compiler, Cargo and native commands. Independent model, owner and
application gates are separate from these finite direct receipts.

`admission.lani` rejects one below-bound sample, accepts on the last available
draw, observes exhaustion through a copied adapter without another source call,
and uses a new shared-source budget for a boolean sample. Both accepted native
processes passed strict x86_64 ELF checks and full syscall tracing: only process
entry and exit occurred, with no allocation or other host services.

`contracts.lani` has six finite scenario functions. The direct counter cases
check zero/one/u64::MAX budgets; shared and copied adapters; independent copied
budgets; distinct-budget and same-budget nested adapters; and decrement-before-
delegation through a source that observes the counter during its call. Source
errors spend budget and retain their exact enum and Host payload.

All six scalar samplers have literal result and source-error controls, including
full signed/unsigned ranges, zero/half/maximum unit floats, exact rejection
thresholds, powers of two, last-draw acceptance and rejection-only exhaustion.
No-draw operations retain a zero budget. Shuffle/choose malformed View metadata
rejects before source calls or backing access; valid empty and singleton paths
retain their no-draw behavior. Fill tests verify exact initialized prefixes and
explicit resumption through both actual byte strides. Shuffle failures retain
only completed suffix steps, including self-swaps, and perform no failed-step
swap. Subsequent choose calls share the remaining budget.

A marked negative fixture rejected with LNC0008 at construction with a non-Source64
type, including when the requested budget is zero.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `524fffcbb5e9806b9d23e8e90b07f429fdc2d6e8468ce22a685a98aba32f4aff` |
| `contracts.lani` | `8a9bd9df54b0de2ab7ae96daff464b62db18d3a9f051678e9862b8fbaf726391` |
| `negative_missing_source.lani` | `54f7c4e6c157105a0e0b0cd5795b8949d06635de61bf74c3cf2e194b3c4b15c9` |
| `stdlib/core/random.lani` | `7f1bf3857137cd610a23d69a3d6d3e0bdfb4df62d5d4e0fc160f811460cdf09b` |

```text
cargo test --test stdlib_random_budget_execution shared_random_draw_budget_executes_last_draw_acceptance_and_exhaustion_admission -- --exact
cargo test --test stdlib_random_budget_execution shared_random_budgets_execute_scalar_counter_metadata_and_partial_mutation_contracts -- --exact
cargo test --test stdlib_random_budget_execution random_budget_adapter_requires_an_actual_source64_capability -- --exact
```

Accepted target scope is native Linux x86_64 CPU execution of GPU-compiler output.
GPU device execution and formal correctness are unclaimed. These deterministic
contracts make no statistical or cryptographic guarantee.
