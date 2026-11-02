# Native threads: `std::pthread`

`std::pthread` starts and joins threads with glibc's `pthread_create` and
`pthread_join`. A Lanius function is the start routine. A non-generic
`fn name(arg: ptr) -> ptr` named as a value is a `ptr` to its C entry (see
[C callbacks](language-ergonomics.md#c-callbacks)). That entry loads R15
with the process vector, so a thread body can use the runtime's services.
Threads coordinate with `std::sync`'s futex `Mutex` and `Condvar` and with
`std::atomic` words. Programs are native-linked with libatomic:

```sh
target/release/laniusc --native-link --native-library atomic --stdlib-root stdlib \
  tests/fixtures/stdlib_execution/concurrency/threads.lani -o target/stdlib-work/threads
```

```lani
fn add_range(task: ptr) -> ptr { /* sum task's range into task */ return task; }

let thread: std::pthread::Thread = std::pthread::spawn(add_range, task).unwrap();
let done: ptr = thread.join().unwrap();   // add_range's return value
```

| Call | Effect |
| --- | --- |
| `spawn(entry, arg)` | Start `entry(arg)` on a new thread with glibc's default 8 MiB stack |
| `spawn_with_stack(entry, arg, bytes)` | The same with a stack of `bytes` (at least `MIN_STACK_BYTES`, 16 KiB) |
| `Thread::join()` | Wait for the thread and return its entry's result. A second join is `Error::Joined` |
| `Thread::id()`, `join_id(id)` | The pthread id, and a join by id for callers that keep ids in shared memory |
| `current()` | The calling thread's pthread id |
| `yield_now()` | `sched_yield` |
| `available_parallelism()` | The CPUs in this thread's affinity mask (`sched_getaffinity`), at least 1 |

`Error::Host(code)` carries pthread's error number: EAGAIN when the process
is out of threads or memory, EINVAL, or EDEADLK when a thread joins itself.
A null entry and a stack below the minimum are `Error::InvalidInput`.

## Rules

- **Join before main returns.** `crt_entry` unmaps the process vector when
  `main` returns, so any thread still running a Lanius function after that
  would fault.
- **The entry's type is not checked.** The name is only a `ptr`, so passing
  a function of another signature is undefined. Use exactly
  `fn (ptr) -> ptr`.
- **An exit or a trap on any thread ends the process.** The runtime exits
  with `exit_group` (syscall 231): `std::process::exit`, a failed bounds
  check (status 101) and allocation failure all end every thread, as they
  would in a one-thread program.
- **Heap allocation is allowed in thread bodies.** The runtime allocator is
  thread-safe: each thread allocates from and frees into its own pool
  ([runtime allocator](runtime-allocator.md)). A thread may still prefer to
  work in memory the caller prepared, such as a `std::sync::Region`, a
  `std::uring` buffer or a Vec, to avoid per-thread arenas.
- **Generic code goes through a wrapper.** An entry must be non-generic, so
  generic work is reached through a one-line wrapper that names the type:
  `fn crew(arg: ptr) -> ptr { return std::par::crew_entry<i64>(arg); }`.
- **Rebuilding locks from pointers.** `std::sync::mutex_at(word)` and
  `std::sync::condvar_at(words)` rebuild a Mutex or Condvar inside a thread
  from words the caller zeroed: 8 bytes for a Mutex and 16 for a Condvar,
  8-aligned. These are the same shared-futex primitives the forked workers
  use. Within one process a private futex would save the kernel's shared-key
  lookup; that optimization is not taken.

`std::thread` still holds the older unbound service-8 declarations, which
the compiler's admission diagnostics recognize by path, so the working API
has its own module.

## Checks

`tests/fixtures/stdlib_execution/concurrency/threads.lani` prints one line
per check and exits 0 when all pass. Three runs gave identical output, in
about 1.7 s each.

| Check | Invariant |
| --- | --- |
| `sum.1` … `sum.16` | A sum of 1,000,003 u64 values split over 1, 2, 3, 8 and 16 threads equals the serial sum |
| `counter` | 8 threads × 20,000 Mutex-guarded plain increments give exactly 160,000 |
| `queue.taken`, `queue.sum_ok`, `queue.split` | 2 producers × 20,000 values pass through an 8-slot queue (one Mutex, `not_empty`/`not_full` Condvars) to 2 consumers. All 40,000 values are taken once, their sum is exact, and the consumers' counts add up to 40,000 |
| `join.pairs`, `join.second_refused` | 1,000 sequential spawn/join pairs each return their argument + 8, and a second join is refused |

`tests/fixtures/stdlib_execution/concurrency/thread_exit.lani` covers
termination. With `exit`, the worker calls `std::process::exit(7)` and the
process exits with status 7. With `trap`, the worker writes past the end of a slice and the
process exits with status 101. With `none`, the process exits 0. Before the
runtime used `exit_group`, all three modes exited 0.

`tests/fixtures/stdlib_execution/concurrency/thread_alloc.lani` checks heap
allocation in thread bodies, in the same format. Ten runs passed, in 1.1 to
2.8 s each.

| Check | Invariant |
| --- | --- |
| `churn.1`, `churn.4`, `churn.16` | 1, 4 and 16 threads each run 20,000 random alloc, realloc and free steps over 64 tagged slots (1 to 3,000 bytes, every 16th 40,000). Fresh blocks read as zero, live blocks keep their tag, realloc keeps the common prefix, and the error count is 0 |
| `cross.taken`, `cross.bad`, `cross.main` | 2 producers allocate 40,000 tagged blocks and pass them through a 16-slot Condvar queue to 2 consumers, which verify and free them, while main allocates 2,000 more |
| `spawn.pairs` | 1,000 sequential spawn/join pairs whose bodies allocate, check zeroing and free |

## Thread pools: std::pool

`std::pool` builds on `std::pthread` and the thread channels
([Ring and Mpsc](stdlib-concurrency.md#thread-channels-ring-mpsc-and-select)).
A thread runs one fixed, non-generic entry, so each generic operation is
reached through a one-line wrapper that names its types:

```lani
fn workers(arg: ptr) -> ptr { return std::pool::serve<Job>(arg); }
fn triple(arg: ptr) -> ptr { return std::pool::map_entry<i64, i64, Affine3>(arg); }
```

| Call | Effect |
| --- | --- |
| `scoped(entry, args, count, stride)` | Run `entry(args + i * stride)` on `count` threads (1 to 1,024) and join them all before returning, so the threads may use anything the caller owns. If a spawn fails, the threads already started are joined and the error is returned |
| `pool<T>(workers, capacity, entry)` | Start 1 to 256 workers running `serve<T>`. Each receives a `T: Task` from a Ring of `capacity` slots and calls `run()` |
| `Pool::submit(task)` / `try_submit(task)` | Queue a task; `submit` waits while the queue is full, `try_submit` returns `Ok(false)` |
| `Pool::wait()` / `wait_timeout_ms(ms)` | Wait until every submitted task has finished; the timed form returns `Ok(false)` if time runs out first |
| `Pool::completed()`, `submitted()`, `total()` | Counts, and the sum of every finished task's `run()` result |
| `Pool::shutdown()` | Finish the queued tasks, join the workers and free the pool |
| `map(workers, input, output, mapper, grain, entry)` | `output[i] = mapper.apply(input[i])` |
| `reduce(workers, input, identity, fold, combine, grain, entry)` | Fold each chunk, then combine the chunk results in index order: `combine` must be associative, not necessarily commutative |
| `scan(workers, data, identity, combine, grain, entry)` | In-place inclusive prefix scan in two passes |

`map`, `reduce` and `scan` start `workers - 1` threads for the call. The
caller works as the last thread, and every thread is joined before the call
returns. Threads take `grain`-sized chunks from an atomic counter; `grain`
of 0 or less picks `length / (8 * workers)`, at least 2,048. Task, mapper
and folder values are copied by value into the pool's memory, so they must
be plain values.

Only the pool's owner thread submits and waits. A task returns an `i64`
that the pool adds up. For a result per task, the task can send it back
through a channel; the fixture's `Square` task sends `key * key` to an
`Mpsc<i64>` that the owner receives from.

### Pool checks

`tests/fixtures/stdlib_execution/concurrency/thread_pool.lani` prints one
line per check and exits 0 when all pass; it runs in about 0.2 s.

| Check | Invariant |
| --- | --- |
| `scoped.*` | 8 scoped threads sum disjoint ranges of 1,000,003 values to the serial sum; a count of 0 is refused |
| `pool.*` | 10,000 tasks through 4 workers: each runs once (completed count, `total()` and an atomic side counter agree), then a second batch of 1,000 after `wait()` |
| `pool.try_*` | With its one worker held on a gate, a 2-slot pool accepts 2 or 3 of 6 `try_submit` calls; `wait_timeout_ms(20)` times out, and after the gate opens `wait` finishes every accepted task |
| `pool.replies*` | 1,000 tasks send `key * key` through an Mpsc: 1,000 replies, sum 332,833,500, none extra |
| `map.*`, `reduce.*`, `scan.*` | `3x + 1` over 1,000,003 values, a sum, an order-sensitive polynomial hash, and prefix sums (grain 1,000 and automatic) all equal the serial results |
| `edge.*` | Empty input and one worker |

### Pool against std::par

`tests/fixtures/stdlib_execution/concurrency/pool_bench.lani` runs map
(`3x + 1`), reduce (a sum) and scan (a prefix sum) over 10,000,000 i64 with
grain 65,536 at 8 workers, through `std::pool` (threads) and `std::par`
(forked workers on `std::steal`). Three interleaved rounds, ms, load average
45 to 50:

| Operation | std::pool | std::par |
| --- | ---: | ---: |
| map | 31–39 | 33–37 |
| reduce | 10–12 | 13–17 |
| scan | 23–35 | 31–39 |

Every run printed the same check values for both. Threads skip the fork and
the shared-region setup, which shows most in reduce, the shortest operation.

## Small copies

The x86 backend used to copy every aggregate with `rep movsq`. Its start-up
cost (about 30 cycles on Zen 3) made a one-word enum argument copy cost
more than the work around it: `Atomic64::load`, which passes its order enum
by value, took 29 ns. Small values now copy through registers:

- A copy of one to three words loads every word into RCX, RSI and RDI
  before any store, which is overlap-safe without the direction test the
  `rep movsq` body needs (`plan_memmove_tail` in
  `shaders/codegen/lir/x86/instruction_plan.slang`).
- A native parameter of up to eight words moves into its fresh frame cell
  word by word through RAX (`safety_emit.slang`; `parameter_values.slang`
  sizes it).

Larger copies still use the shared `rep movsq` body.
`tests/fixtures/stdlib_execution/concurrency/small_copy_bench.lani` runs 10M
iterations of each kernel; its build has 6 `rep movsq` sites and prints
checksum 58592112. Times are the minimum over 15 runs at load average 1.5,
in ms (2026-11-02):

| Kernel | ms |
| --- | ---: |
| one-word record through a call | 39 |
| two-word record | 139 |
| three-word record | 82 |
| `Option<i64>` returns | 144 |
| three-word record copies between array slots | 142 |
| three-word enum through a call | 266 |

The thread channels from `channel_bench.lani` (best of 5): Ring fan-in of
1 × 1,000,000 takes 259 ms and 4 × 500,000 takes 563 ms.

## std::par on threads

`std::par::sort_unstable_threads` and `sort_stable_threads` run the same
phases as the forked sorts, with `workers - 1` pthreads as the crew. The
crew threads start once per sort, wait on the phase futex between phases
and exit on the stop word. The caller passes the crew entry for its element
type. See
[parallel sorting](stdlib-concurrency.md#parallel-sorting-map-reduce-and-scan)
for the oracle and benchmark. The threaded stable sort used to burn about
1.6x the CPU of the forked one. Record stores from a stack temporary ran as
backward `rep movsq` copies whenever a thread stack was mapped below the
data. Copies now run backward only when the ranges overlap, and both crews
use the same CPU time.
