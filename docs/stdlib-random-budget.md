# Shared random-source draw budgets

`core::random` adds a borrowed Source64 adapter that shares one draw allowance
across existing samplers, fills, choices and shuffles. It does not add parallel
bounded versions of those APIs. The [fixed contract](library-random-budget-plan.md)
has accepted direct/model/owner/application gates on the finite native Linux
x86_64 profile. The full standard and extended library goal stays open.

## API and exact charging

```text
Error::DrawLimit
draw_budget(limit:u64) -> DrawBudget
DrawBudget.borrow() -> &DrawBudget
DrawBudget.remaining() -> u64
budgeted<R>(source:&R, budget:&DrawBudget) -> Budgeted<R> where R:Source64
Budgeted<R>.borrow() -> &Budgeted<R>
impl<R:Source64> Source64 for Budgeted<R>
```

Construction and inspection make no draw and acquire no resource. Before each
adapter `draw`, inspect its referenced budget. At zero, return DrawLimit without
calling the source. Otherwise subtract one **before** forwarding one draw and
return that exact Result, including its error. Rejected words and failed source
calls spend quota. Zero and u64::MAX are valid limits; decrement cannot underflow.

One counter can span several operations and adapters. Copying an adapter shares
its source/counter references; copying DrawBudget creates an independent copy
of its current remaining count. No operation implicitly resets, refills or
rolls back a counter. Nested adapters each charge the counter they encounter:
an inner exhaustion can spend outer quota without reaching the ultimate source.
Using the same counter at both layers can therefore charge it twice.

Keep the source and counter live while adapters borrow them. Aliases must not
mutate their state or destination during a call; borrowing does not enforce
exclusive access or thread safety. Use the public factories/inspection methods;
overwriting a live counter through public fields violates that discipline.

## What the bound covers

The quota counts delegated Source64 calls. It does not bound one source call's
duration, internal host calls, recursion or memory. A source may block or never
return. The adapter itself allocates, polls, sleeps and closes nothing.

In particular, one OsRandom draw can perform several getrandom attempts under
its existing policy. The separate [bounded entropy API](stdlib-entropy-bounded.md)
counts host attempts. A draw quota does not change entropy flags or retries and
is not a deadline, cancellation facility or host-call allowance.

The ordinary [samplers](stdlib-randomness.md#generic-sampling) retain their
unlimited rejection policy when passed an ordinary source. Supplying Budgeted
selects an explicit source-call policy while reusing those same implementations.

## Errors, no-draw cases and confirmed progress

Sampler admission still precedes any requested draw. Invalid bounds/ranges keep
their existing errors even with zero quota. `below(_,1)`, singleton intervals,
valid empty fill/shuffle/choose and singleton shuffle/choice spend no draw.
Boolean and unit-float samplers request one word; full-width integer ranges do
likewise. Other ranges can reject several words before accepting one.

| Operation | Effect when a draw fails, including DrawLimit |
| --- | --- |
| Scalar sampler or choose | Preserve the exact source error; no fallback value. Choose returns a shallow Option<T>, without clone or cleanup transfer. |
| `fill` | Preserve earlier initialized bytes; `Failure.completed` counts that prefix in bytes. The failing draw writes nothing. Unused bytes from a successful final word are discarded. |
| `shuffle` | Preserve completed suffix swaps, including self-swaps; `Failure.completed` counts steps, not draws. Rejection/failure during the next step makes no swap for that step. The whole view remains a shallow permutation. |

Shuffle and choose now revalidate negative start/length and overflowing
`start + length` before empty/singleton handling, source access or element access.
Malformed views return Bounds; shuffle reports completed zero. Fill retains
its offset/count/sum checks. These logical checks establish no physical bounds.
Keep backing initialized/live, preserve native strides and outside guards, and
retain one explicit cleanup authority per actual owner. A chosen shallow value
is not an independent owner to release. The source must not alias or mutate
the destination while sampling.

## Sampling and bias

The existing range engine rejects words below `2^64 mod bound`, then reduces
accepted words modulo bound. This is the low-remainder rejection method
described by the [PCG author](https://www.pcg-random.org/posts/bounded-rands.html).
Given independent uniform words and a fixed, value-independent available draw
count, every returned rank remains uniform conditional on success. Exhaustion
returns an error, with no biased modulo/zero fallback. Adversarial/dependent
sources or value-dependent caller policies have no such uniformity guarantee.

Shuffle retains descending Fisher–Yates, the reverse-index form of the
[NIST algorithm](https://xlinux.nist.gov/dads/HTML/fisherYatesShuffle.html).
Budget exhaustion does not roll back its earlier steps or imply that a partial
shuffle has the distribution of a completed one. Deterministic models and
threshold counterexamples test behavior; statistical smoke is not a proof of
uniformity. No cryptographic algorithm or security guarantee is added.

## Application, evidence and targets

The [`sample_integers SEED BOUND COUNT DRAW_LIMIT` program](stdlib-sample-integers.md)
uses the public adapter and sampler with checked decimal arguments. It retains
all sample values before publication, then formats bounded output batches and
releases its Vec after success/failure. Sampling failure publishes nothing;
output failure can leave a confirmed prefix. All four registered groups pass:
model 32, budget 19, CLI 36 and I/O 11, totaling 98 distinct native cases.

| Receipt in `target/stdlib-work/` | Accepted scope |
| --- | --- |
| `random-budget-admission-first.log` | One test/5.20s: rejection, success on the last draw, copied-adapter exhaustion and a new-counter boolean. Full syscall trace contains only process entry/exit. |
| `random-budget-existing-contracts.log` | One selected existing rejection/generic/float-boundary contract test/6.25s; five old tests filtered. |
| `random-budget-direct-first.log` | Two tests/8.14s: six-scenario native contracts and one marked Source64 capability rejection; admission filtered. Contract trace contains only entry/exit. |
| `random-budget-model-first.log` | One test/8.50s: 7,130 cases/57,040 actions, ten operations/two byte layouts/five adapter arrangements, seed `0xb0d6e0261101`; first attempt passes. |
| `random-budget-owners-first.log` | One test/7.61s: 41 actual mappings/exact releases, seven no-host-call phases, nested owners/zero-sized values and native/packed stride checks. |
| `random-budget-sample-app-first.log` | Four tests/7.59s: all 98 native application cases on app `f63a7350`. |

The [direct fixture](../tests/fixtures/stdlib_foundation/random_budget/README.md)
executes random source `7f1bf385`. The [independent model](../tests/fixtures/stdlib_foundation/random_budget_model/README.md)
checks exact source calls/index, remaining counters, scalar/float bits, errors,
fill/shuffle progress and complete byte states, including shared/copied and
same-/separate-budget nesting. The [owner fixture](../tests/fixtures/stdlib_foundation/random_budget_owners/README.md)
checks complete nested String/Vec payloads, shallow choice aliases, prefix/suffix
progress, zero-sized Unit and surrounding byte guards. All mappings have exact
address/extent releases; this is finite observation, not automatic ownership.
All five new library tests pass across separate receipts, with the selected
existing test kept separate. No broader old-suite/GPU/performance rerun is
claimed. Historical receipts do not establish these additions or the new
malformed-View admission behavior.

The accepted profile is native Linux x86_64 CPU output from the GPU compiler.
Direct GPU execution, other targets, automatic lifetimes/ownership and formal
verification remain unverified. Production is Lanius; no compiler, ABI or host
binding change belongs to this increment.
