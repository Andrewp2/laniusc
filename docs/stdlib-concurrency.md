# Workers, atomics, synchronization and channels

`std::atomic`, `std::sync`, `std::channel`, `std::steal`, `std::parallel`,
`std::par` and `std::worker` run parallel work on Linux x86_64/glibc. Programs must be native-linked with libatomic:

```sh
target/release/laniusc --native-link --native-library atomic --stdlib-root stdlib \
  sample_programs/library/parallel_word_count.lani -o target/stdlib-work/pwc
```

## Execution model: workers are forked processes

The compiler has no checked C callback entry yet (see the
[concurrency admission audit](library-concurrency-dependencies.md)), so
`pthread_create` cannot receive a Lanius start routine and `std::thread`
stays unbound. Without a callback, a worker is instead a `fork` of the caller.
`Pool::spawn` returns twice: `Role::Parent(index)` in the caller and
`Role::Child(index)` in the new worker. The child continues in the same
function and must end with `std::worker::finish(status)`. That call
`_exit`s without returning through the parent's frames or exit path.

```lani
let role: std::worker::Role = pool.spawn().unwrap();
let child: bool = match (role) { std::worker::Role::Child(i) -> true, std::worker::Role::Parent(i) -> false };
if (child) { return std::worker::finish(work(jobs, results)); }
```

Only memory in a `std::sync::Region` is shared. A Region is a
`MAP_SHARED|MAP_ANONYMOUS` mapping created before the workers. Each worker
gets a private copy-on-write snapshot of everything else, such as locals,
heap owners and files. That snapshot is a feature: a worker can read the
parent's input buffers with no synchronization. But a worker's writes to
ordinary memory are never seen by anyone else.

The scope rules are explicit:

- Map the Region and create every primitive before spawning the workers that
  use it. A Region address is then valid in every worker.
- Only the creating process allocates from or unmaps a Region, and only after
  `join_all` has joined every worker.
- `Pool::destroy` returns `Err(Unjoined)` while any worker is unjoined.
- A worker must not use its copy of the `Pool`.

`join` decodes the wait status as `Exit::Code(0..255)` or `Exit::Signal(n)`.
`join_all` returns a `Summary` with the joined count, the failed count and
the first failure. Each worker joins once; a second join is
`Err(AlreadyJoined)`.

## Atomics and orders

`std::atomic::Atomic32` and `Atomic64` borrow an aligned 4- or 8-byte word.
Their operations are `load`, `store`, `swap`, `fetch_add`, `fetch_sub`,
`fetch_and`, `fetch_or`, `fetch_xor` and `compare_exchange`, all through
GCC libatomic.

Orders are per-operation enums, so a C11-invalid order cannot be written:

| Operation | Order type | Values |
| --- | --- | --- |
| `load` and the compare-exchange failure order | `Load` | Relaxed, Acquire, SeqCst |
| `store` | `Store` | Relaxed, Release, SeqCst |
| Read-modify-write and the compare-exchange success order | `Ordering` | Relaxed, Acquire, Release, AcqRel, SeqCst |

There is no Consume order and no standalone fence; libatomic exports no
fence symbol.

`compare_exchange` is strong, so it never fails spuriously. It returns
`Exchange::Swapped(previous)` or `Exchange::Failed(actual)`. The native
profile does not admit C `_Bool`, so the declaration discards the result as
void, which is ABI-compatible on System V x86-64. Success is then recovered
exactly from the caller-local expected slot: libatomic rewrites that slot
only on failure, and only with a value different from the expected one.

The address must be nonzero, aligned and valid for the whole use. Every
concurrent access to the word must be atomic. Region allocations are 64-byte
aligned, which satisfies both word sizes.

## Futexes, deadlines and blocking primitives

`futex_wait`, `futex_wait_until` and `futex_wake` use the shared futex
operations, not the process-private ones, because workers are separate
processes. A wait returns `Woken`, `Changed` (the word already differed),
`Interrupted` or `TimedOut`, so callers recheck their condition. A
`Deadline` is an absolute `CLOCK_MONOTONIC` instant from `now()` or
`deadline_after_ms(0..=86400000)`. Deadline waits use `FUTEX_WAIT_BITSET`,
so a retry loop never extends the deadline.

| Primitive | Contract |
| --- | --- |
| `Mutex` | Exchange-based three-state futex lock: `lock`, `try_lock`, `lock_until`, `unlock`. `unlock` of an unlocked mutex is `Err(NotLocked)`; `lock_until` past its deadline is `Err(TimedOut)` without ownership. Not reentrant or owner-checked |
| `Condvar` | Sequence futex. `wait` and `wait_until` release the mutex, sleep and always reacquire it before returning, including on `TimedOut`. Spurious returns are possible. `has_waiters`, read under the mutex, lets a notifier skip the wake syscall |
| `Once` | `begin` returns `Run` to one caller at a time, and `Done` after `complete`. `abandon` returns the Once to new and wakes the sleepers, one of which then gets `Run`. Calling `complete` or `abandon` with nothing running is `Err(InvalidState)` |
| `Lazy64` | A Once plus a value. `get_or_begin` returns `Ready(value)` or `Run`; the runner calls `publish(value)` or `abandon` |
| `Barrier` | Reusable for a fixed party count; `wait` returns true for exactly one party per generation |

None of these primitives poisons. Every failure is an explicit `Error`
value, such as `Host(errno)`, `TimedOut`, `NotLocked` or `InvalidState`.
There is no robust-futex recovery either: a worker that exits or is killed
while holding a lock leaves it locked. Condvar and barrier sequences are
32-bit, so a sleeper could miss exactly 2^32 notifications.

## Bounded MPMC channel

`std::channel::bounded<T>(region, capacity)` stores a FIFO ring of `T`
messages, with capacity 1 to 1,048,576, in the Region. `T` is copied by
value into Region storage, so it must be a plain value: scalars, enums, and
records or arrays of them. A pointer or owner inside `T` means something to
the receiver only if it points into a shared Region; a heap owner would name
the sender's private copy. One futex mutex orders
every operation. That gives three guarantees:

- No message is lost or duplicated.
- Each sender's messages arrive in send order.
- A message delivered before a disconnection report is never discarded.

| Operation | Result |
| --- | --- |
| `send` / `try_send` / `send_until` / `send_timeout_ms` | `Ok`, or `Full(v)`, `TimedOut(v)`, `Disconnected(v)`, `Sync(e)`. A rejected message is returned to the caller |
| `recv` / `try_recv` / `recv_until` / `recv_timeout_ms` | `Ok(v)`, or `Empty`, `TimedOut`, `Disconnected`, `Sync(e)` |
| `Sender::close` / `Receiver::close` | Remaining count of that side; `Err(NoEndpoint)` when none is open. The last close wakes every waiter on the other side |

Endpoints are counted in shared memory, not owned by handle values. A fork
copies every handle, so the counts are what carry ownership:

- Register each endpoint with `open_sender` or `open_receiver` before
  spawning the worker that uses it.
- Whichever process uses an endpoint closes it exactly once.
- Senders get `Disconnected` once every receiver has closed.
- Receivers drain the queued messages, then get `Disconnected` when the
  queue is empty and every sender has closed.

A channel with no registered sender reports `Disconnected` at once.

## Work-stealing queues

`std::steal::queues<T>(region, workers, capacity)` gives each of up to 1,024
workers its own bounded deque of up to 1,048,576 tasks in the Region, each
guarded by its own futex mutex:

- `push(me, task)` adds to the bottom of `me`'s deque. A full deque returns
  `PushError::Full(task)`, so the caller can run that task inline.
- `next(me)` pops `me`'s newest task (LIFO). If that deque is empty, it
  steals the oldest task (FIFO) from the next nonempty deque after `me`.
- `done(me)` marks one taken task complete. `Err(NotPending)` if no task was
  pending.

A task is pending from `push` until `done`. Push children before calling
`done` for their parent, so the pending count can reach zero only when all
work has finished. `next` then returns `Finished` to every worker. An idle
worker reads a wake epoch before scanning and sleeps on that epoch's futex
only after the scan finds nothing. A push after the read changes the epoch,
so the sleep cannot miss it. The last `done` wakes every sleeper.

`stats(w)` reports how many tasks worker `w` executed and how many it stole.
Seed tasks with `push` before spawning. A seeded task may go on any deque; a
running worker pushes only to its own. The deque mutex orders a task's
Region writes before the thief that takes it. The deques are lock-based, not
a lock-free Chase–Lev design.

## Cancellation and deadlines

`std::sync::Token` is a cooperative cancellation flag in a Region:

- `cancel()` is sticky and wakes every `wait_until` sleeper. It returns
  whether this call was the one that cancelled.
- `cancel_at(deadline)` arms an absolute monotonic deadline; set it before
  sharing the token. `is_cancelled()` latches the cancellation the first
  time a check sees that deadline has passed. A failed clock read counts as
  cancelled.
- `wait_until(deadline)` sleeps until the token is cancelled (`Ok(true)`) or
  the given deadline passes (`Ok(false)`), whichever comes first.

Each `std::steal::Queues` owns a token, with these rules:

- `Queues::cancel()` also wakes idle workers. With a deadline armed by
  `cancel_at`, idle workers sleep no later than that deadline.
- After cancellation, `push` returns `PushError::Cancelled(task)`.
- `next` drains the worker's own deque and returns `Next::Cancelled`.
  Drained tasks are counted in `discarded()` and are no longer pending.
- Tasks already taken still finish and call `done`.
- Once every worker has returned and been joined, the pool has drained
  cleanly: pushed tasks equal executed plus discarded, and
  `pending_count()` is 0.

For hard stops, `std::worker::Pool` has two calls:

- `join_until(index, deadline)` returns `Err(TimedOut)` and leaves the
  worker unjoined. It polls every millisecond.
- `signal_all(signal)` signals every unjoined worker, for example SIGKILL
  (9) after a cooperative deadline. Those workers still need `join`.

## Parallel slice operations

`std::parallel` runs slice operations on worker processes over
`Shared<T>`, a typed array in a Region. A `Plan(region, workers, chunk,
token)` sets the shape: 1 to 256 workers claim `chunk`-element pieces from a
shared counter, so faster workers take more. Callbacks are statically
dispatched trait values, copied into each worker.

| Operation | Contract |
| --- | --- |
| `for_each(plan, length, &body)` | `ChunkBody::run(start, end)` for every chunk. A nonzero status cancels the token and returns `Failed(status)` |
| `map(plan, input, output, &mapper)` | `output[i] = mapper.apply(input[i])` through `core::function::Mapper` |
| `reduce(plan, input, partials, identity, &fold, &combine)` | Folds each chunk from `identity` with a `core::iter::Folder`, then combines the chunk results in chunk order. `combine` must be associative with `identity` as its unit; it need not be commutative |
| `scan(plan, data, partials, identity, &combine)` | In-place inclusive scan (prefix sum) in two parallel passes: chunk totals, then each chunk rescans from the combined total of the chunks before it |
| `merge_sort(plan, data, scratch)` | Stable for `T: core::cmp::Ord<T>`. Workers sort the chunk runs, then each round merges adjacent pairs of runs in parallel. Later rounds have fewer pairs, so the final merge is serial. Returns the round count |

A cancelled token (by `cancel`, `cancel_at` or a failing chunk) stops new
claims. The call then returns `Err(Cancelled)` or `Err(Failed(n))`, and the
outputs are partly written. A cancelled token stays cancelled, so use a
fresh token for each plan you want to rerun.

## Parallel sorting, map, reduce and scan

`std::par` runs sorts, `map`, `reduce` and `scan` as tasks on a `std::steal` pool. A
`Plan(region, workers, grain)` holds the pool's deques (1,024 tasks per
worker) and a target task size. Each phase seeds its tasks round-robin over
the deques, forks the workers, and they pop, steal and run tasks until
nothing is pending. If a phase would need more tasks than the deques hold,
the grain grows to fit.

| Operation | Contract |
| --- | --- |
| `sort_unstable(plan, data, scratch)` | Splits `data` into runs (the power of four at or above twice the workers, so the merge round count is even) and sorts each run with an introsort: ninther pivots, Hoare partitioning, insertion below 24 elements and a heapsort fallback. Merge rounds then merge adjacent runs into `scratch` and back. Equal keys may reorder. Returns the phase count |
| `sort_stable(plan, data, scratch)` | Same shape, but each run uses a bottom-up merge sort (insertion on 32-element blocks) through the run's own range of `scratch`. Every merge takes the left run on ties, so equal keys keep their input order |
| `map(plan, input, output, &mapper)` | `output[i] = mapper.apply(input[i])` in grain-sized stolen tasks. Returns the task count |
| `reduce(plan, input, partials, identity, &fold, &combine)` | Each task folds its range from `identity` into `partials[task]`. The parent then combines those results in task order, so `combine` must be associative but need not be commutative. `partials` needs `ceil(length / grain)` slots |
| `scan(plan, data, partials, identity, &combine)` | In-place inclusive scan: `data[i]` becomes the combination of `data[0..=i]` in index order. Pass 1 folds each task's range into `partials[task]`. The parent turns those into exclusive prefixes in task order, and pass 2 rescans each range from its prefix. Same `combine` and `partials` rules as `reduce`. Returns the task count |

A sort keeps one crew of workers for all of its phases. The calling process
is steal worker 0 and forks `workers - 1` children once. For each phase it
seeds tasks, bumps a futex phase word and works through them as worker 0;
the phase is over when `next` reports nothing pending. The children exit
when the sort sets a stop word. The run sorts call `T::lt` directly rather
than through `core::slice`, whose `Comparator` path costs about three times
as much per comparison (measured below).

Merges are parallel within a round, too. Each pair merge is cut into
grain-sized output pieces at merge-path (co-rank) boundaries, found by binary
search. Every worker therefore shares even the last round, which merges the
two halves of the whole array. `scratch` must be as long as `data`; if the
round count is odd, a parallel copy moves the result back. Errors are
`InvalidPlan`, `LengthMismatch`, `Failed` (a worker exited nonzero or work
was left pending), `Steal`, `Sync`, `Worker` and `Thread`.

### Threaded sorts

`sort_unstable_threads(plan, data, scratch, entry)` and
`sort_stable_threads(...)` run the same phases with a crew of `workers - 1`
[`std::pthread`](stdlib-threads.md) threads instead of forked children. The
threads share the caller's address space, so nothing is forked and nothing
is copied. A thread's start routine must be a non-generic `fn (ptr) -> ptr`,
so the caller passes a one-line entry for its element type:

```lani
fn key_crew(arg: ptr) -> ptr { return std::par::crew_entry<i64>(arg); }
std::par::sort_unstable_threads(plan, keys, spare, key_crew).unwrap();
```

The entry must instantiate `crew_entry` with the `T` of that sort. Each
worker's record (plan, data, scratch, index) sits in the plan's crew area.
The crew threads start once per sort and are all joined before it returns.
`par_sort.lani` modes 10 and 11 run these two sorts. The model oracle now
covers 12 modes, 4,320 runs over 8 seeds, with 0 mismatches.

Fork and thread crews on 10M i64 keys, in ms, at 8 workers, interleaved.
The load average was 24–27 from other jobs, so read the ranges, not single
runs:

| Sort | Forked crew | Thread crew |
| --- | --- | --- |
| unstable, i64 | 504–964 | 469–541 |
| stable, (key, index) records | 1,996–2,335 | 2,968–3,779 |

On 2M keys, again in ms, the two crews are equal at 1 worker. From 2
workers up, the unstable thread sort is 8–15% faster and the stable thread
sort is 1.4–1.5x slower:

| Workers | Unstable, fork | Unstable, threads | Stable, fork | Stable, threads |
| --- | --- | --- | --- | --- |
| 1 | 324 | 352 | 1,396 | 1,391 |
| 2 | 250 | 226 | 764 | 1,080 |
| 4 | 130 | 120 | 567 | 790 |
| 8 | 74 | 63 | 301 | 463 |

The stable slowdown is user time: 18–19 s of CPU against 11.7 s forked,
with fewer page faults (127k against 243k). Both crews run the same code on
the same shared arrays, so the extra cycles look like threads contending on
something processes keep private while sorting two-word records. A probe of
record-returning calls (`target/claude-work/s4/thr/scale.lani`) gave exact
results and showed no record-specific slowdown, so the cause is still open.
The forked sorts stay the default.

## Samples

[`parallel_word_count.lani`](../sample_programs/library/parallel_word_count.lani)
is a parallel `wc`. It prints `lines words bytes` for up to 64 MiB of stdin
as follows:

1. The parent reads stdin into a Region.
2. It queues 64 KiB job indices on a 16-slot channel.
3. Four workers count their jobs and reply on a result channel.

A word starts at a non-space byte whose predecessor is a space or the input
start, so jobs need no boundary alignment. On an 11 MB generated file it
printed `1348185 2083687 10649247`, the same as `wc`, in 0.075 s wall time
(0.24 s CPU). It also matched `wc` on an empty input and on a source file.

[`channel_pipeline.lani`](../sample_programs/library/channel_pipeline.lani)
runs a three-stage pipeline:

1. The parent emits 1..=200000.
2. Three workers square the values.
3. One worker sums the squares modulo 10^9.

The pipeline shuts down stage by stage through disconnection. It prints
`200000 666700000`, which matches a Python oracle, in 0.71 s. Before
`Condvar::has_waiters` let channels skip idle wake syscalls, the same run
took 2.45 s.

[`parallel_quicksort.lani`](../sample_programs/library/parallel_quicksort.lani)
sorts 2,000,000 pseudo-random `i64` values in a Region with eight workers.
Each task partitions its span, pushes the smaller side and keeps the larger
one; spans of at most 4,096 values sort sequentially. The parent then checks
that the values are ordered and are a permutation of the input (sum and xor
unchanged), and prints `sorted 2000000`. One run executed 848 tasks with 242
steals. The whole program, including generation and checking, took 0.25 s
with eight workers and 0.80 s with one. Twenty runs passed.

[`parallel_grep.lani`](../sample_programs/library/parallel_grep.lani) is a
fixed-string grep: `parallel_grep PATTERN < input` prints matching lines in
input order, with `grep -F -e` exit codes. Eight `for_each` workers scan
64 KiB chunks and mark each matching line's first byte in a shared flag
array. The parent then prints the flagged lines, writing each run of
adjacent matches in one call. Output and exit status matched GNU `grep -F -e` in 28 of 28 cases. Those
cases crossed seven patterns (including empty, absent and space-containing
ones) with four inputs: a 7 MB file of 400,000 random lines without a
trailing newline, a small file with empty lines, the 11 MB word-count file
and an empty input. Twenty further runs on the 7 MB file were identical. Workers
now search with [`core::search`](stdlib-search.md) and record per-chunk
match summaries. The same comparison then passed 133 of 133 cases,
including a 49 MB text corpus. The search guide records timings against GNU
grep: 3–7x faster than the first naive version, and still 2–7x slower than
GNU grep.

## Stress receipts

[`stress.lani`](../tests/fixtures/stdlib_execution/concurrency/stress.lani)
checks exact invariants on a 16-CPU laptop. Its groups are:

| Group | Workers and load | Exact result |
| --- | --- | --- |
| Relaxed `fetch_add` | 8 workers x 200,000 | 1,600,000; a failing compare-exchange reports that value, then a successful one stores 9 |
| Mutex-protected load/store increments | 8 workers x 50,000 | 400,000 (any lost update would show a missing exclusion); then `NotLocked`, `try_lock` and `lock_until` → `TimedOut` |
| `Lazy64` race after a barrier | 16 workers | 1 initializer run; 16 workers see 4242; Once abandon/retry/complete edges |
| Barrier | 8 workers x 200 rounds | 200 leaders |
| Channel, capacity 64 | 6 producers x 20,000 to 4 consumers | 120,000 received; per-sender count 20,000 and sequence sum 199,990,000; 0 FIFO violations; 4 consumers ended on Disconnected |
| Channel, capacity 1 | 16 producers x 5,000 to 8 consumers | 80,000 received; exact per-sender counts and sums; 0 FIFO violations; 8 ends |
| Channel, capacity 7 | 1 producer x 50,000 to 12 consumers | 50,000 received; 0 FIFO violations; 12 ends |
| Channel edge cases | Single process | 12 checks: Empty, TimedOut, Full(7), TimedOut(8), Disconnected(9) in both directions, delivery after the last sender closes, and close underflow |

A FIFO violation is any consumer receiving a sequence from one sender that
is not greater than the previous sequence it received from that sender.
Per-sender counts and sums are accumulated in the Region.

One stress run takes about 2.8 s; the capacity-1 group dominates. These
runs all passed in the session that wrote this guide:

| Program | Runs |
| --- | --- |
| Stress fixture, before the capacity-1 and 1x12 groups were added | 30 |
| Stress fixture, all groups | 20 |
| Channel pipeline | 20 |
| Word count on the 11 MB file | 20 |

[`steal.lani`](../tests/fixtures/stdlib_execution/concurrency/steal.lani)
covers struct payloads and work stealing; 20 of 20 runs passed:

| Group | Workers and load | Exact result |
| --- | --- | --- |
| Four-field record channel, capacity 3 | 8 producers x 10,000 to 4 consumers | 80,000 received; 0 torn records (a checksum field and a tag per record); 0 FIFO violations |
| Binary task tree over 2^18 leaves | 1 worker | 524,287 tasks; every leaf ran exactly once; 0 deque overflows; leaf sum 34,359,607,296 |
| Same tree | 8 workers | Same exact counts; at least one steal is required (535, 271, 209 and 567 in four runs) |
| 20,000 tasks seeded on worker 0 | 8 workers | 20,000 tasks; index sum 199,990,000; full-deque push returns its task; steals equal tasks run by workers 1–7 (17,403 to 18,203 per run, all seven stealing) |

Steal counts vary with scheduling and go to stderr; stdout holds only the
exact lines.

[`parallel.lani`](../tests/fixtures/stdlib_execution/concurrency/parallel.lani)
covers slice operations and cancellation. All 20 runs passed with
byte-identical stdout; one run takes about 0.6 s.

| Group | Load | Exact result |
| --- | --- | --- |
| `for_each` | 1,000,003 indices, chunk 4,096, 8 workers | 245 chunks; every index visited exactly once |
| `map` | Squares of 1,000,003 values | 1,000,003 exact |
| `reduce` | Sum, and a non-commutative polynomial hash at chunk 977 | Sum 500,002,500,003; hash and scale equal the serial fold |
| `scan` | Prefix sum of 1..1,000,003, chunk 4,093 | 1,000,003 exact triangular numbers |
| `merge_sort` | 1,000,003 keys in 0..999 with original indices, chunk 8,192 | Sorted; stable (equal keys keep index order); key checksum unchanged; 8 rounds |
| Failing chunk | Chunk 3 returns 7, 4 workers | `Failed(7)`, token cancelled, no index visited twice, later chunks skipped (12,288 of 1,000,003 indices touched in one run) |
| Deadline | 100,000 slow chunks with a 40 ms deadline | `Cancelled` in about 43 ms after 64 chunks |
| Steal pool cancelled by a worker | Unbounded task tree; one worker cancels after 20,000 leaves | pushed == executed + discarded, pending 0, all 8 workers returned `Cancelled` (one run: 40,315 pushed, 40,160 executed, 155 discarded) |
| Steal pool cancelled by deadline | Same tree, 30 ms deadline | Same balance; 8 `Cancelled` workers |
| Joins | A worker waiting on a token; a second worker blocked forever | `join_until` returns `TimedOut` after 20 ms, then a clean join after `cancel`; `signal_all(9)` sends 1 signal and the join decodes `Signal(9)` |

[`par_sort.lani`](../tests/fixtures/stdlib_execution/concurrency/par_sort.lani)
reads a mode, a worker count and n i64 keys, then writes back the result.
[`par_oracle.py`](../tests/fixtures/stdlib_execution/concurrency/par_oracle.py)
compares every mode with a Python model:

- the sorts with `sorted()`;
- the stable sorts with a stable sort by key, where the original indices must
  match exactly;
- `map` element by element;
- `reduce` with a wrapping sum plus an ordered polynomial hash.

The shapes are random full-range keys, all-equal keys, sorted, reversed, four
distinct values, organ pipe, sawtooth, i64 extremes and dense duplicates.
The scan modes compare running prefixes: a wrapping u64 sum, and the
composition of affine maps `x -> a*x + b` mod 1,000,000,007, which is not
commutative. They use a 997-element grain, so even small inputs split into
many tasks. Sizes run from 0 to 300,000 keys, with 1 to 13 workers. Eight
seeds covered every mode: 3,003 runs before `scan` existed and 3,600 runs
after, with 0 mismatches.

On 10,000,000 random i64 keys, the laptop (16 hardware threads, shared
with other agents' jobs) timed the sort alone, as the runner measures it.
C++ is `g++ 13.3 -O2` on the same binary keys, also timing the sort alone.
Each row is three rounds of a benchmark that waits for a load average
below 10, then runs the Lanius and C++ binaries interleaved.

| Sort | Workers | Time |
| --- | --- | --- |
| C++ `std::sort` | 1 | 577–689 ms |
| C++ `std::stable_sort` | 1 | 775–859 ms |
| C++ `__gnu_parallel::sort` (OpenMP) | 8 | 118–179 ms |
| `std::par::sort_unstable` | 1 | 1.36–1.42 s |
| `std::par::sort_unstable` | 8 | 306–373 ms |
| `std::par::sort_unstable` | 16 | 239–369 ms |
| `std::par::sort_stable` on (key, index) | 8 / 16 | 1.39 / 1.25 s |
| `core::slice::sort_unstable` | 1 | 7.1–9.2 s |
| `core::slice::sort_stable` on (key, index) | 1 | 27.9 s |
| GNU `sort -n --parallel=8` on the same keys as text | 8 | 6.6 s |

At 8 workers `std::par::sort_unstable` takes about half as long as C++
`std::sort`. It takes 2.3–2.8 times as long as `__gnu_parallel::sort`. The
GNU times include parsing and printing 203 MB of text, written to a file.
Every `std::par` output matched `core::slice`'s byte for byte, and GNU's
once converted.

Where the time goes, from a timing build at 8 workers (368–482 ms in all
with its own printing):

| Step | Time |
| --- | --- |
| Forking 7 children, once | 17–18 ms |
| Run sorts (16 runs of 625,000 keys) | 256–356 ms |
| Four merge rounds | 17–31 ms each, 77–92 ms in all |
| Stop and join | 15–26 ms |

The changes that got here:

- The direct `T::lt` run sort cut the run phase from 943 ms to 314 ms.
- One crew for all phases removed 30–39 ms of fork stagger per phase. Each
  fork copies the page tables of the parent's large input buffers.
- Carrying both merge heads in locals reloads one element per output
  instead of three. That halved each merge round and cut the stable sort
  from 1.98 s to 1.39 s at 8 workers.
- Carrying the stopped scan values into the partition swap made the
  single-threaded sort about 6% faster.

Two alternatives to the four merge rounds were measured and are not used:

- A single multiway merge. Regular-sample splitters cut the output into
  pieces, and each piece merges 16 runs through a loser tree. Its merge
  phase took 135 ms. Four two-way rounds took 165–185 ms then, and take
  77–92 ms with carried heads. End to end the multiway version took
  361–645 ms, against 296–392 ms for the four rounds in the same runs.
  Per level, the tree's local-array traffic costs more than a two-way merge
  step.
- A sample sort with 63 splitters, block counts, a stable scatter and
  splitter-equal buckets. It took 399–545 ms, against 319–378 ms for the
  four rounds in the same runs. Classifying every key twice (count, then
  scatter) took 90–100 ms and 120 ms, more than the merges it replaces.

What is left is per-core speed: the run sorts are 70–75% of the time. One
thread takes 1.36–1.42 s against C++'s 0.6 s. In the generated code, each
slice access reloads the slice's base, length and stride from the stack,
checks bounds and multiplies the index by the stride. A loop of two slice
loads and an `i64` compare costs 4.4 ns per iteration, against 0.74 ns for
the empty loop. Calling `T::lt` instead of `<` adds only 0.8 ns. Closing the
gap to `__gnu_parallel::sort` needs cheaper slice access in the compiler,
not a different parallel decomposition.

`scan` on the same 10,000,000 keys:

| Scan | Workers | Time |
| --- | --- | --- |
| Sequential wrapping u64 prefix sum | 1 | 115 ms |
| `std::par::scan` u64 sum | 1 / 8 / 16 | 99 / 100 / 127 ms |
| `std::par::scan` affine composition | 1 / 8 / 16 | 626 / 209 / 197 ms |

The sum is limited by memory bandwidth: two passes over 80 MB give no gain
from more workers. The affine scan does a few modular multiplies per element
and runs 3.0x faster at 8 workers. All worker counts produced
byte-identical output.

`core::slice::sort_unstable` pays about 19 ns per comparison through
`core::ordering::Comparator`, where `compare` returns an `Ordering` value
that `is_less` then tests. A direct `T::lt` costs 6 ns. The
50,000,000-compare microbenchmark took 966 ms against 303 ms. That is why
`std::par` sorts its runs itself.

[`tests/stdlib_concurrency_execution.rs`](../tests/stdlib_concurrency_execution.rs)
compiles the four fixtures and four samples through
`compile_entry_to_x86_64_with_native_link`, then checks:

- Three stress runs produce the exact summary lines.
- The pipeline output matches a computed sum of squares.
- The word count matches a sequential oracle on generated inputs of 0, 1,
  65,535, 65,536, 65,537 and 3,000,000 bytes.
- Three runs of the stealing fixture produce its exact lines.
- The quicksort prints `sorted 2000000`.
- The parallel fixture produces its exact lines.
- The grep matches GNU `grep -F` on generated inputs.
- Every `par_sort` mode, the scans included, matches a Rust model on
  random, five-valued, all-equal, sorted, reversed, empty and one-key
  inputs.

These test wrappers are checked at merge time; this session ran the same
programs directly.

## Compiler limitation found

A `match` on a generic enum bound by an outer `match` arm fails with
`LNC0047`, "generic type instantiation reached a compiler boundary":

```lani
enum Wrap<T> { Full(T), Other }
struct Span { lo: i64 }
let r: core::result::Result<i32, Wrap<Span>> = core::result::Err(Wrap::Full(Span { lo: 3 }));
let v: i64 = match (r) { core::result::Err(e) -> match (e) { Wrap::Full(s) -> s.lo, _ -> -1 }, core::result::Ok(x) -> -2 };
```

Matching `r.unwrap_err()` directly compiles and returns 3. The stealing
fixture uses that form.

## Not provided

- In-process threads: `std::thread` remains unbound until the compiler has
  checked callback entry.
- Thread-local storage, preemptive cancellation and unwinding: cancellation
  is cooperative, apart from `signal_all`.
- Robust or owner-checked locks, and fairness or starvation bounds.
- Channel or task payloads that own private memory; payloads are copied by
  value.
- Lock-free deques, and task priorities or affinity.
- Sharing heap owners, files or sockets between workers. These are private
  snapshots after `spawn`, and closing a descriptor in one worker leaves the
  others' copies open.
- Using these modules without `--native-link --native-library atomic`.
