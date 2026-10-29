# Shared random-source draw budgets

## Purpose and boundary

Make source-call limits composable across the existing random samplers, byte
fills and shuffles. A borrowed Source64 adapter owns no source and no resources.
The same budget can span multiple operations and adapters. Keep the existing
unlimited source interface available for callers that intentionally accept its
rejection-loop policy; this is a separate policy, without forwarding aliases or
duplicate bounded versions of every sampling function.

This increment also rejects malformed logical View metadata in shuffle and
choose before source calls or element access. It changes library code, focused
tests, one real program and documentation only. Compiler, ABI and proof changes
are outside this increment. No cryptographic algorithm is introduced.

## API and contracts

```text
Error::DrawLimit
draw_budget(limit:u64) -> DrawBudget
DrawBudget.borrow() -> &DrawBudget
DrawBudget.remaining() -> u64
budgeted<R>(source:&R, budget:&DrawBudget) -> Budgeted<R> where R:Source64
Budgeted<R>.borrow() -> &Budgeted<R>
impl<R:Source64> Source64 for Budgeted<R>
```

Before each delegated draw, inspect the shared budget. At zero, return DrawLimit
without calling the source. Otherwise decrement once before delegation and
preserve its exact Result, including errors. Rejected samples and failed source
calls spend budget; operations that need no draw spend none. u64::MAX is valid
and decrement cannot underflow. The adapter does not reset a budget per sample
or shuffle step. Copying an adapter shares its source/budget references; copying
a DrawBudget makes a separate counter. No implicit refill, reset or rollback.

The source and counter outlive adapters and calls. Aliases must not interfere
with the counter, source state or destination during a call; borrowing alone
does not enforce this. A source call may block or fail to return. The counter
bounds delegated calls, not their duration, internal host calls, recursion or
memory use. Nested adapters may each spend one of their own budgets before an
inner failure. No thread-safety or automatic ownership claim is made.

Use existing rejection sampling unchanged: discard words below 2^64 mod bound,
then reduce accepted words. The [PCG author's discussion](https://www.pcg-random.org/posts/bounded-rands.html)
describes this low-remainder method. Given independent uniform words and a
fixed, value-independent available draw count, each returned rank remains
uniform conditional on success. Exhaustion returns an error with no biased
fallback. No uniformity claim is made for adversarial/dependent sources or
value-dependent caller policies. The existing descending Fisher-Yates shuffle
is the reverse-index equivalent of the [NIST algorithm](https://xlinux.nist.gov/dads/HTML/fisherYatesShuffle.html).
Its completed suffix counts swaps, including self-swaps, not draws. A failed
step makes no swap; earlier steps remain a shallow whole-value permutation.

Shuffle and choose reject negative start/length or overflowing start+length
with Bounds, before empty/singleton handling or source access. Shuffle failure
reports completed=0. Physical backing, actual native bounds, lifetime and alias
discipline remain caller obligations. Choose still returns a shallow Option<T>.
Fill retains its checked offset/count admission and exact initialized prefix.

## Acceptance

1. Direct native tests cover zero/one/MAX budget, errors, rejection exhaustion,
   success on the last allowed draw, repeated calls, shared/copied/nested
   adapters, all scalar samplers, fill prefix, shuffle suffix and choose.
2. Independent scripted/model tests check actual call counts, remaining budget,
   exact returned values/errors and destination state across operation sequences.
   Threshold endpoints, full signed/unsigned ranges, powers of two and biased
   fallback counterexamples are required. No statistical smoke proves uniformity.
3. Nested-owner and stride tests check whole shallow permutations, guards,
   zero-sized payloads, native and packed byte destinations, and no host calls
   inside pure sampling phases. Owner release accounting remains explicit.
4. A bounded seeded sampling CLI uses the public adapter, decimal parsing,
   checked storage and explicit output failure policy. Tests cover normal,
   boundary, draw exhaustion, allocation and I/O cases with no output before
   input admission and sampling succeed.
5. Run selected existing randomness contracts after changing shared source.
   Linux x86_64 native execution via the GPU compiler is the initial supported
   receipt; this does not establish GPU execution of user programs.

All compiler/native runs are root-owned, serialized and under two minutes per
command. Agents may edit their assigned paths and run bounded CPU-only oracle
checks. Runtime claims are pending until root inspects successful receipts.
