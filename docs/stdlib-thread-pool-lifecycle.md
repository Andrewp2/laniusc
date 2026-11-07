# Thread pool ownership and synchronous operations

`std::pool` composes [native threads](stdlib-threads.md), bounded channel
storage and plain-value work. It has two lifetime models: a task pool can
retain its resources after a failed join; a synchronous borrowed operation
must finish every join before returning. The implementation now stores actual
`std::thread::Thread` owners and records each successful join.

All six focused gates pass: 74 native cases exercise lifecycle, allocation,
synchronization and ordered results, with separate observer controls. The
supported target is Linux x86_64/glibc with native linking and `libatomic`.
Other targets, compiler-enforced lifetimes/data-race safety and formal proofs
remain unsupported or unverified. Historical pool performance measurements
do not establish the repaired lifecycle behavior.

## Public contracts

```text
Error = InvalidInput | SizeOverflow | AllocationFailed | Closed
      | CounterOverflow | Thread(std::thread::Error)
      | Channel(std::channel::Error) | Sync(std::sync::Error)

Task.run(&self) -> i64
CreateFailure<T> { cause:Error, pending:Option<Pool<T>> }
pool<T>(workers:i32, capacity:i32, entry:ptr)
    -> Result<Pool<T>,CreateFailure<T>> where T:Task
serve<T>(arg:ptr) -> ptr where T:Task

Pool.borrow() -> &Pool<T>
Pool.is_open() -> bool
Pool.workers() -> Result<i32,Error>
Pool.submitted() -> Result<i64,Error>
Pool.completed() -> Result<i64,Error>
Pool.total() -> Result<i64,Error>
Pool.submit(task:T) -> Result<i32,Error>
Pool.try_submit(task:T) -> Result<bool,Error>
Pool.wait() -> Result<i32,Error>
Pool.wait_timeout_ms(milliseconds:i64) -> Result<bool,Error>
Pool.shutdown() -> Result<bool,Error>

scoped(entry:ptr, args:ptr, count:i32, stride:usize) -> Result<i32,Error>
```

`map`, `map_entry`, `reduce`, `reduce_entry`, `scan` and `scan_entry` keep their
existing generic signatures. They consume borrowed `std::parallel::Shared<T>`
descriptors, not ownership of their backing. The caller supplies a non-generic
`fn(ptr)->ptr` entry wrapper naming the exact generic work:

```text
fn workers(arg:ptr) -> ptr { return std::pool::serve<Job>(arg); }
fn mapper_entry(arg:ptr) -> ptr {
    return std::pool::map_entry<Input,Output,Mapper>(arg);
}
```

An entry pointer is a raw C callback boundary. A nonnull pointer is not proof
of its signature, wrapper body or generic arguments. The caller must supply
the correct executable entry. These functions do not create a typed callback
or lifetime guarantee in the compiler.

## Task pool construction and retirement

Task pools accept 1 through 256 workers. Queue capacity obeys `std::channel`'s
power-of-two ring limits. Construction validates arguments and allocation
sizes before using storage. Every failed source allocation releases earlier
storage and returns an error. Channel failures remain `Error::Channel`,
including the channel constructor's own allocation and size errors.

If a spawn fails after earlier workers started, construction closes the
sender and tries to join every started worker. It returns the spawn error in
`CreateFailure.cause`. When every join succeeds, all storage is released and
`pending` is `None`. Otherwise `pending` contains the actual closing pool,
including its unjoined thread owners and every allocation workers can access.
The primary spawn error is retained; the initial cleanup join error has no
separate field. The caller must retry `pending.shutdown()` until successful
or terminate the process safely. Dropping the descriptor does not clean it up.

`shutdown()` closes the sender once, allowing normally executing workers to
drain queued jobs. It attempts every remaining join once and remembers each
success in the corresponding `Thread` value. It returns the first join error
after attempting the others. On error it frees no pool, ring or thread-owner
storage. A later call joins only workers whose joins have not yet succeeded.
Allocation sizes use the original thread capacity, independently of how many
threads started or remain unjoined.

Once all joins succeed, shutdown destroys the ring and all pool storage, then
invalidates the calling owner. It returns `Ok(true)` for that retirement and
`Ok(false)` on later calls. `is_open()` means backing still exists: it remains
true while a failed shutdown is pending. It does not mean submissions remain
permitted.

There is one controller and one active cleanup authority. The controller must
serialize all pool methods, including queries, waits and shutdown. Copied
descriptors alias the same storage; a copy grants no independent ownership or
permission for simultaneous operations. All task-referenced caller storage
must stay alive until the associated work completes, and through any pending
shutdown or construction recovery. All threads must be joined before `main`
returns and retires the process runtime state.

## Submission, counters and results

`submit` blocks while the queue is full and returns `Ok(0)` after acceptance.
`try_submit` returns `Ok(false)` when full and leaves its caller's plain-value
task copy unaccepted. Errors are explicit. Once shutdown begins, submissions
and both wait methods return `Error::Closed` without entering the queue.

`workers` reports the number of successfully started workers, including joined
workers whose closing pool has not retired. `submitted`, `completed` and
`total` are snapshots. All four queries remain available during a pending
shutdown; all return `Error::Closed` after retirement without touching freed
storage. Read results before a successful shutdown if they are needed later.

Lifetime accepted submissions cannot exceed `MAX_SUBMITTED`, which is
`i64::MAX`. The next attempt returns `CounterOverflow` before queue publication.
Unaccepted attempts roll back their provisional count. Completed counts
therefore remain representable and never exceed accepted submissions.
Task result aggregation deliberately adds modulo 2^64 and interprets the bits
as signed `i64`; it is not checked arithmetic. Counts and results have distinct
overflow policies.

Tasks, mappers, folders and accumulator values are plain values. The pool does
not destroy nested owners, free pointers stored in tasks, cancel jobs or
detach workers. Callback bodies must preserve their referents, avoid data
races, and return normally. A callback that never returns can prevent waits
and joins from completing.

## Waiting and synchronization failures

`wait` returns after all work accepted before the call completes.
`wait_timeout_ms` accepts 0 through 86,400,000 milliseconds and returns
`Ok(false)` if that deadline expires before completion. Timeout does not cancel
work or release any task backing. Hard futex and clock errors return
`Error::Sync`; a wait error also leaves all jobs and pool ownership intact.

The completion notification uses a nonwrapping three-state word: idle (0),
armed (1) and notified (2). For each attempt, the sole controller stores armed,
rechecks the completed count against its fixed submitted snapshot, then waits
on the word only if work remains. A worker publishes its result and completion,
then changes armed to notified with compare-and-exchange and wakes the waiter
only when that transition succeeds. Additional completions coalesce in state
2. Every wait return, timeout and error clears the state before returning or
trying again.

All arm, count-recheck, completion and notification operations use sequentially
consistent atomics. Completion ordered before the count recheck is observed
there. Completion ordered after the recheck must see an earlier arm: its
notification changes the expected futex word or wakes an already sleeping
waiter. A delayed notification can cause a harmless extra wake after rearming.
No finite epoch counter can wrap into a missed notification. This argument
requires one controller/waiter; it does not permit concurrent waits on copied
pool descriptors.

An unexpected worker receive error panics rather than silently losing accepted
work. A futex wake error after committing a completion also panics. The channel
uses the same failure policy for wake errors after queue/endpoint changes.
Those states cannot honestly be reported as an unaccepted task, and ignoring
them could strand a sleeper. Recoverable wait errors are separate: they clear
the notification state and return the actual synchronization error.

## Synchronous borrowed work

`scoped` runs `entry(args + i*stride)` for `count` threads, with count from 1
through 1024. It admits multiplication and final-address addition before any
thread starts. `args` may be null if the entry permits it; zero stride is also
allowed when the entry can safely share that argument. The caller supplies the
physical extent, alignment and synchronization of every referenced object.
Successful return reports the number of started threads. A spawn error joins
all previously started threads before returning `Error::Thread`.

Map, reduce and scan accept 1 through 256 workers, counting the caller. Empty
input returns zero chunks or the reduction identity without allocation or
spawning. A one-worker call runs entirely on the caller and may pass a null
entry. Nonempty calls requesting more workers require a nonnull matching entry.
Positive grain selects that chunk width; nonpositive grain uses
`max(2048, length / (8*workers))`. Chunk count and endpoints are derived without
overflowing signed element indices.

Each call admits nonnegative lengths, typed storage extents, address arithmetic
and all scratch allocations before modifying output or spawning workers.
Owned storage uses eight-byte alignment and checked positive-`isize` extents;
deallocation uses the exact allocated byte size. Input descriptors must still
refer to genuinely live, aligned storage with their claimed typed capacity.
Arithmetic admission cannot validate an arbitrary fabricated pointer.

Map requires equal input/output lengths and rejects overlapping nonempty byte
ranges, including same-storage in-place mapping. It preserves the input and
writes every output element. Aliases hidden inside mapper/value pointers are
still the caller's responsibility. Reduce folds each chunk from the identity,
then combines chunk results in index order. Its combine operation must be
associative with that identity; commutativity is not required. Scan is an
in-place inclusive scan: it folds chunks, forms their exclusive prefixes on
the caller, then rescans each chunk from its prefix. The scan operator must
obey the same associativity and identity requirements.

A failed worker spawn reduces parallelism for map, reduce and scan. The caller
and any started workers still claim and finish every chunk, so successful
return guarantees full results. This fallback does not convert allocation or
argument errors into success. Scan joins the first crew before preparing the
second pass and preserves this rule for both crews.

For all synchronous borrowed operations, every started thread must be joined
before normal return, including ordinary errors. A failed join leaves that
quiescence unproved. The function attempts the remaining joins, then panics
before freeing work storage or returning into caller cleanup. It does not
retry indefinitely, detach the thread, pretend it joined, or return an error
that would allow the caller to free still-borrowed memory. Task pools instead
return retained ownership because their control block outlives the failed
shutdown call.

On native x86_64, `core::panic::panic` calls `assert(false)` and raises SIGILL.
This process termination does not unwind or use the runtime's separate
`exit_group` bounds/trap path.

## Evidence boundary

The independent fixtures in `tests/fixtures/stdlib_thread_pool_lifecycle`
cover construction rollback, pending construction/shutdown recovery,
successful-join state across retries, exact source allocation extents, closed
queries, complete synchronous results under spawn fallback, allocation errors,
wait/clock failures and synchronous join-failure termination before caller
cleanup. A real parallel-checksum program exercises the map composition.
All six tests in `stdlib_thread_pool_lifecycle_execution` pass in 17.57 seconds.
The five native groups cover 18 model cases, 23 admission cases, seven retained-owner
lifecycle cases, 21 resource cases and five synchronous-failure traps. The
separate observer gate checks 39 accepted/rejected trace shapes, including
instruction-pointer-prefixed signal and exit records. These finite tests do
not prove every interleaving or enforce the caller's ownership obligations.
