# Scoped stacks

`std::scope` is phase S0 of
[the scoped-stacks design](memory-scoped-stacks-design.md): Goose-style
stacks as a library, with explicit marks and no compiler support.

A `Stack` is one reservation with two ends:

- **Low end.** Packed `u8` and `i32` values grow up from the bottom.
- **High end.** Every other `T` grows down from the top. That is the
  direction its raw view runs: `core::mem::typed_slice_from_storage` puts
  element zero at the top of its storage.

Allocating is a bump. Releasing to a mark is two stores. The newest growable
on each end extends in place, without copying. A second allocation on the
same end stops that growable: its next push fails with `NotOnTop` (rule R4).

Executable evidence covers **x86_64 Linux using the GPU compiler**. Wasm and
other hosts have not been established.

## API

```text
Error { InvalidCapacity, AllocationFailed, Exhausted, InvalidMark, NotOnTop, Destroyed }
Mark { low: usize, high: usize }
Stats { capacity: usize, used: usize, peak: usize }
Stack                          one reservation; copies alias it
Scratch = Stack                a frame scratch, reset once per frame
Grow<T>                        a growable array on T's end
Soa2<A, B>, Soa3<A, B, C>      columns of one fixed capacity

new(capacity: usize) -> Result<Stack, Error>   capacity a nonzero multiple of 8
Stack.borrow() -> &Stack
Stack.is_live() -> bool
Stack.mark() -> Mark
Stack.release(mark: Mark) -> Result<bool, Error>
Stack.reset()
Stack.used() -> usize
Stack.stats() -> Stats
Stack.destroy()

alloc_slice<T>(stack: &Stack, count: i32, fill: T) -> Result<View<T>, Error>
copy_slice<T>(stack: &Stack, input: View<T>) -> Result<View<T>, Error>
place<T>(stack: &Stack, value: T) -> Result<ptr, Error>

grow<T>(stack: &Stack) -> Grow<T>
push<T>(stack: &Stack, values: &Grow<T>, item: T) -> Result<i32, Error>
view<T>(stack: &Stack, values: Grow<T>) -> View<T>
Grow.borrow() -> &Grow<T>
Grow.len() -> i32

soa2<A, B>(stack: &Stack, capacity: i32) -> Result<Soa2<A, B>, Error>
soa3<A, B, C>(stack: &Stack, capacity: i32) -> Result<Soa3<A, B, C>, Error>
Soa2.push(a, b) -> bool, Soa3.push(a, b, c) -> bool, len() -> i32
fields first, second, third: the columns
```

## Rules

- **Releasing.** `release(mark)` frees everything allocated after `mark` on
  both ends. A mark that is no longer reachable, because the stack was
  released past it, fails with `InvalidMark`. Nothing stops a view from
  outliving its mark; phase S1's root check adds that.
- **Reservation.** The region is reserved once, from `alloc::allocator`,
  and the system commits pages on first touch. Running out is `Exhausted`;
  the stack never grows or moves. That is what keeps views and `place`
  addresses stable.
- **Alignment.** Low-end allocations start on 8 bytes. High-end sizes are
  multiples of 8.
- **Peak.** `peak` is the most bytes in use. It is measured at releases,
  resets and `stats`, the only places use can fall.
- **Struct of arrays.** `Soa2` and `Soa3` are explicit column groups. A
  `Soa<T>` over a record's fields needs field reflection, which the compiler
  does not have yet.

## Measurements

The benchmarks are in `benchmark_artifacts/scoped_stacks_s0`. Each workload
has three versions:

- today's `Vec` or one allocation per node;
- `alloc::arena`, with doubling buffers that copy when they grow;
- `std::scope`.

The tests: `tests/stdlib_scope_execution.rs` runs
`tests/fixtures/stdlib_scope/semantics.lani`. It covers both ends, in-place
growth, `NotOnTop`, release and stale marks, exhaustion, peak, `place`, `Soa2`,
`Scratch` and use after `destroy`.
