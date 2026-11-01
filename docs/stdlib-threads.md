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

`tests/fixtures/stdlib_execution/concurrency/thread_alloc.lani` checks heap
allocation in thread bodies, in the same format. Ten runs passed, in 1.1 to
2.8 s each.

| Check | Invariant |
| --- | --- |
| `churn.1`, `churn.4`, `churn.16` | 1, 4 and 16 threads each run 20,000 random alloc, realloc and free steps over 64 tagged slots (1 to 3,000 bytes, every 16th 40,000). Fresh blocks read as zero, live blocks keep their tag, realloc keeps the common prefix, and the error count is 0 |
| `cross.taken`, `cross.bad`, `cross.main` | 2 producers allocate 40,000 tagged blocks and pass them through a 16-slot Condvar queue to 2 consumers, which verify and free them, while main allocates 2,000 more |
| `spawn.pairs` | 1,000 sequential spawn/join pairs whose bodies allocate, check zeroing and free |

## std::par on threads

`std::par::sort_unstable_threads` and `sort_stable_threads` run the same
phases as the forked sorts, with `workers - 1` pthreads as the crew. The
crew threads start once per sort, wait on the phase futex between phases
and exit on the stop word. The caller passes the crew entry for its element
type. See
[parallel sorting](stdlib-concurrency.md#parallel-sorting-map-reduce-and-scan)
for the oracle and benchmark.
