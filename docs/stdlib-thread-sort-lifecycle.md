# Threaded sort lifetime

`std::par::sort_unstable_threads` and `sort_stable_threads` run the existing
work-stealing sort phases with `workers - 1` native pthreads. The caller does
work as worker zero. This is a Linux x86-64/glibc API; compile with native
linking and `atomic`. It does not run on a GPU. The GPU compiler can compile
the Lanius program to the native target, which is different from executing
pthread services on the GPU.

The caller supplies a non-generic entry function for the exact element type:

```lanius
fn key_crew(argument: ptr) -> ptr {
    return std::par::crew_entry<i64>(argument);
}
// plan, data and scratch come from a live std::sync::Region.
let result = std::par::sort_unstable_threads(plan, data, scratch, key_crew);
```

The plan, data and scratch must remain live and exclusively assigned to the
sort until it returns. Data and scratch must be separate, correctly aligned
storage with equal nonnegative lengths and enough space for the element type.
The entry must call `crew_entry<T>` for that same type. A raw pointer does not
encode that requirement, and the current compiler does not enforce these
ownership and aliasing rules. The comparator must implement a consistent
ordering and be safe to call concurrently. Worker zero and every started
worker may invoke it.

## Completion and failure

Each successful spawn stores an actual `std::thread::Thread` owner. Storage
uses `size_of<Thread>()`, separate from the argument records. Successful
joins write the joined owner state back to its slot; cleanup never reconstructs
ownership from a numeric thread ID.

| Outcome | Behavior |
| --- | --- |
| Empty or singleton input | Returns zero phases without starting workers; a null entry is allowed |
| One worker | Runs on the caller; no entry function is invoked |
| All phases and joins succeed | Returns the phase count; stable sorting preserves original order among equal keys |
| Spawn fails | Starts no sort phase, publishes stop, wakes and joins every worker already started, then returns the original `Thread` error; input remains unchanged |
| Task/worker reports failure | Stops and joins the whole started crew before returning an ordinary error; data may already have changed |
| A join fails | Panics immediately, before returning to caller-owned backing; does not retry or claim that worker was retired |
| A phase or stop wake fails after publication | Panics before joining or returning; a sleeping worker cannot safely be abandoned |
| A crew wait returns a hard error | The threaded worker panics; normal changed/interrupted wait outcomes recheck phase and stop |

On the native target, `core::panic::panic` calls `assert(false)`, whose assertion
instruction raises SIGILL and terminates the process, including its threads.
This differs from the runtime's `exit_group` bounds/trap path. The lifetime
policy depends on process termination rather than unwinding. Failed joins
retain join authority in the `Thread` object, but this synchronous API cannot
return that authority while its worker still borrows caller data. Process
termination is deliberate; it is not ordinary cleanup or a promise that every
join succeeded. The OS reclaims remaining mappings at exit.

Admission rejects workers outside `1..=256`, a nonpositive grain, a negative
input length, unequal scratch length, an argument record larger than its
reserved slot, and a null entry when workers would start. The plan constructor
returns allocation/capacity errors from its Region. A failed construction can
consume Region bump capacity; the caller still owns and must unmap the Region.
Plan and Shared fields are currently public, so callers can forge invalid
storage. Numeric checks do not validate arbitrary pointers or allocation extents.

Sort range endpoints clamp before addition, merge widths double only within
the remaining bound, and ceiling division avoids adding the divisor to the
length. Co-rank indices and heapsort child arithmetic avoid intermediate
overflow. These changes preserve the admitted nonnegative `i32` length range;
they add no smaller artificial length cap. They also apply to the shared fork
sort phases. The fork mechanism and public ABI are unchanged, and its existing
hard futex-error handling has not been redesigned here.

## Focused acceptance gate

The gate is `tests/stdlib_thread_sort_lifecycle_execution.rs`, with fixtures in
`tests/fixtures/stdlib_thread_sort_lifecycle`. It builds one native Lanius
program, linking the shared real-pthread fault probe and a small test-only C
seccomp helper. Sorting and ownership logic remain in Lanius. Python supplies
inputs, compares values with its independent stable sort, and checks process
and syscall observations.

The prepared finite gate covers 38 normal cases, 12 admission cases, one
worker-result error, and 10 fault/capacity cases. Normal cases include empty
and singleton arrays, duplicate keys, signed extrema, multiple worker counts,
stable records with original indices, maximal grain, and representative fork
regressions. Admission includes the full `i32` positive length reaching the
null-entry check without touching forged backing; this is not a successful
sort of a two-billion-element allocation.

Fault cases cover first and later create failures; first and later join
failures with the failing worker held before its Lanius entry; partial startup
followed by join failure; phase/stop wake errors; a hard worker wait error;
Region mmap failure; and insufficient Region capacity. The hard-wait case
reuses the opaque argument observed from a completed real crew, then starts a
new real pthread in the idle phase. It does not duplicate the private Crew
layout. Seccomp denial matches the exact control-word address and futex
operation; unrelated pthread futexes remain available.

Eleven cases trace every participating TID and classify syscall sites using
the shared native source-authority verifier. Ordinary paths require exact
source Region extents to be released and each actual pthread ID to be joined
once. Fail-closed paths require no return marker, a terminal SIGILL, and the
Region still owned until termination. A marker is emitted
before any post-return fixture assertion, so an unsafe library return followed
by an assertion cannot pass as a successful fail-closed test. Each subprocess
has a seven-second limit; timeout cleanup kills its process group and traced
descendants. The oracle has an 80-second outer bound.

Native acceptance is pending the root agent's run. Source review and host-side
syntax checks are not runtime evidence. This finite gate does not prove all
interleavings, all comparator implementations, successful full-`i32` allocations,
fork fault recovery, or performance. No new GPU execution or performance claim
is made by this cleanup.
