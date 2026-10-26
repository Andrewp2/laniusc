# Basic iterator sources and stepping

`core::iter` provides empty, single-item and repeating sources, plus a borrowed
stepping adapter. They implement the existing [fused iterator protocol](stdlib-iterators.md)
in portable Lanius. The sources and adapter allocate nothing and invoke no
implicit clone, move or destruction operation.

| Factory | Returned type | Behavior |
| --- | --- | --- |
| `empty<T>()` | `Empty<T>` | Every pull returns `None` |
| `once<T>(value:T)` | `Once<T>` | First pull returns `Some(value)`; later pulls return `None` |
| `repeat<T>(value:T)` | `Repeat<T>` | Every pull returns `Some(value)` |
| `step_by<I,T>(source:&I,step:u64)` | `Result<StepBy<I,T>,StepError>` | Yield the first item, then every `step`th item; requires `I:Iterator<T>` |

All four returned types provide `borrow()` for adapters and consumers. Import
`core::iter` for their `Iterator<T>::next(&self)` implementations. Empty needs
no seed value, including when `T` is a compound or zero-sized type. Once and
Repeat preserve nested Option and Result values as ordinary items: yielding
`Some(None)` does not end the outer iterator.

## Pull order and exhaustion

`step_by` rejects zero with `StepError::Zero`. Construction, including this
error, makes no source calls. Every nonzero `u64` is accepted without narrowing.

The first `next()` makes one source call and returns its result. It does not
skip ahead after yielding. Each later `next()` discards `step - 1` successful
items, then pulls the next result. For example, step three over `0..9` yields
0, 3 and 6. After the first result, the upstream cursor is at 1; after the
second, it is at 4.

The first upstream `None`, whether seen while skipping or while requesting a
result, ends that adapter permanently. It makes no further upstream calls.
Thus `u64::MAX` over a three-item source yields its first item, then ends after
at most the remaining two successful pulls and one EOF probe. Step one forwards
each item without discarding any.

Stepping uses the shared `next` protocol, so its work is proportional to the
items it skips. It cannot promise constant-time movement for an arbitrary
source. Over an infinite source, a large step can require a large amount of
work. Put `Take` **before** stepping to bound successful upstream pulls:

```lani
let source: core::iter::RangeI32 = core::iter::range_i32_inclusive(
    core::range::range_inclusive(-3,8));
let bounded: core::iter::Take<core::iter::RangeI32,i32> =
    core::iter::take<core::iter::RangeI32,i32>(source.borrow(),12);
let selected: core::iter::StepBy<core::iter::Take<core::iter::RangeI32,i32>,i32> =
    core::iter::step_by<core::iter::Take<core::iter::RangeI32,i32>,i32>(bounded.borrow(),3).unwrap();
// selected yields -3, 0, 3, 6, then None.
```

Take after stepping limits returned samples; each sample can still require many
upstream calls. An upstream implementation can also do its own unbounded work
inside a single `next()`.

## Copies, references and cleanup authority

Copying Once forks its current availability. Two copies made before its first
pull can each yield the stored value. A copy made after that pull is already
exhausted. References to the same Once share its one-item state. Empty copies
remain empty. Repeat copies continue yielding their stored shallow value.

Copying StepBy copies its first-pull and exhausted flags while retaining a
reference to the same upstream cursor. Two copies made before any pull each
take one item on their own first pull. A copy made after the first pull starts
with skipping on its next pull. Their calls consume one shared upstream
sequence, and each active copy can observe EOF once before latching its own
terminal state. References to the same adapter share all of its state.

Items are shallow copies. Array and record value fields follow the language's
ordinary copy rules; slices, references and nested memory-owner handles still
refer to their original backing. Keep that backing, the upstream cursor and
any mapper alive while they can be used. Public state fields do not authorize
resetting an exhausted cursor or forging adapter invariants.

Once does not establish a new cleanup authority when the cursor or item is
copied. Repeat cannot safely repeat a transferred memory owner unless the
application retains a separate cleanup authority and treats every yielded
handle as an alias. Release the original owner once, after all aliases have
finished being used. Stepping discards skipped shallow values without calling
Destroy. An owning source may have transferred those items, so the application
must account for their cleanup; destroying only the source's remainder cannot
recover discarded owners.

## Sampling a bounded range

[`sample_every.lani`](../sample_programs/library/sample_every.lani) is a complete
command-line program. It accepts:

```text
sample_every START END STEP INPUT_LIMIT
```

START and END are inclusive signed `i32` bounds. STEP is a nonzero `u64`.
INPUT_LIMIT is a `u64` at most 1,000,000 and limits the prefix consumed from the
range before stepping. Reversed bounds and a zero input limit are empty. The
program uses checked decimal parsing, RangeI32, Take, StepBy, checked decimal
formatting and `write_all`.

For `sample_every -3 8 3 12`, the samples are -3, 0, 3 and 6:

```csv
count,sum
4,6
```

For `sample_every 2 20 3 12`, only the prefix 2 through 13 is eligible, yielding
2, 5, 8 and 11 (`count=4`, `sum=26`). Even the full `i32` range with
`STEP=18446744073709551615` and `INPUT_LIMIT=8` consumes at most eight successful
upstream values and returns only its first sample.

Exit codes are 0 for success, 2 for invalid arguments, 3 for host/output errors
and 4 for argument-allocation failure. The argument snapshot has one explicit
owner, which main destroys after processing on every return path. At most one
million `i32` values contribute to the sum, so all intermediate sums fit `i64`.

## Verification scope

All three execution groups now have passing receipts on native Linux x86-64
through the production GPU compiler. The focused gate is:

```sh
cargo test --test stdlib_iterator_sources_execution -- --test-threads=1
```

| Run evidence | Result | Reported duration |
| --- | --- | --- |
| Source contracts group | Passed | 6.28 seconds |
| `iterator-sources-model-program.log` | All 14,433 model commands passed; the accompanying sample group failed on the test driver's output redirection, so this two-group run failed overall | 10.12 seconds |
| `iterator-sources-program-current.log` | Sample group passed after the driver redirection fix, including the failing-output case | 5.51 seconds |

The corrected sample run closes that gate; the earlier two-group run remains a
mixed result. These receipts cover the tested native Linux x86-64 profile.

[`stdlib_iterator_sources_execution.rs`](../tests/stdlib_iterator_sources_execution.rs)
checks concrete compound and zero-sized items, mapper composition, lazy
construction, zero-step rejection, huge steps over short sources, leaf forks,
adapter forks and shared references. Its native binary protocol is compared
with an independent mathematical model over all short call/copy schedules.
The source contracts trace one String allocation and its sole explicit release,
including repeated and discarded aliases.

The sample program is compared with an arithmetic progression model for normal,
reversed and extreme bounds, zero limits and `u64::MAX` steps. It also checks
invalid arguments and a failing output descriptor. The test driver compiles
three entry programs and keeps the existing strict executable jump validation.

These APIs use the familiar [empty](https://doc.rust-lang.org/std/iter/fn.empty.html),
[once](https://doc.rust-lang.org/std/iter/fn.once.html),
[repeat](https://doc.rust-lang.org/std/iter/fn.repeat.html) and
[step_by](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.step_by)
sequence definitions as references. Lanius fixes the lazy pull timing, returns
a checked error for zero, and follows its own shallow-copy cleanup rules.
