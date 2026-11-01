# Workers, atomics, synchronization and channels

`std::atomic`, `std::sync`, `std::channel` and `std::worker` run parallel
work on Linux x86_64/glibc. Programs must be native-linked with libatomic:

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

`std::channel::bounded(region, capacity)` stores a FIFO ring of `u64`
messages, with capacity 1 to 1,048,576, in the Region. One futex mutex orders
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

[`tests/stdlib_concurrency_execution.rs`](../tests/stdlib_concurrency_execution.rs)
compiles the stress fixture and both samples through
`compile_entry_to_x86_64_with_native_link`. It then makes three checks:

- Three stress runs produce the exact summary lines.
- The pipeline output matches a computed sum of squares.
- The word count matches a sequential oracle on generated inputs of 0, 1,
  65,535, 65,536, 65,537 and 3,000,000 bytes.

## Not provided

- In-process threads: `std::thread` remains unbound until the compiler has
  checked callback entry.
- Thread-local storage, cancellation and join deadlines.
- Robust or owner-checked locks, and fairness or starvation bounds.
- Generic channel payloads; messages are `u64` words. Larger values go in
  Region storage, with indices sent over the channel.
- Sharing heap owners, files or sockets between workers. These are private
  snapshots after `spawn`, and closing a descriptor in one worker leaves the
  others' copies open.
- Using these modules without `--native-link --native-library atomic`.
