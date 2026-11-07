# Native thread ownership and failures

`std::thread` is the canonical native-thread API. Its Lanius implementation
calls glibc's pthread functions and the existing Linux syscall boundary.
It replaces the old service-8 declarations and the separate `std::pthread`
module; the old module path and `join_id` are removed.

The implementation targets native-linked Linux x86_64/glibc CPU programs.
Native acceptance of this consolidation is pending. Earlier pthread tests
do not establish the new failure and ownership contracts. GPU-device
execution, other targets, formal verification and compiler-enforced
lifetimes are outside this increment.

## Public interface

```text
Error {
    Host(i32), System(std::linux::Error),
    InvalidInput, Joined, UnexpectedResult
}
SpawnFailure {
    cause: Error,
    cleanup_error: Option<i32>,
    started: Option<Thread>
}

spawn(entry: ptr, arg: ptr) -> Result<Thread, Error>
spawn_with_stack(entry: ptr, arg: ptr, bytes: usize)
    -> Result<Thread, SpawnFailure>

Thread.borrow() -> &Thread
Thread.id() -> u64
Thread.is_joined() -> bool
Thread.join() -> Result<ptr, Error>

current() -> u64
yield_now() -> Result<i32, Error>
available_parallelism() -> Result<i32, Error>

MIN_STACK_BYTES: usize = 16384
```

`Host(code)` preserves a pthread return code, which is a positive error
number under the host contract. It is not a negated syscall result or an
`errno` lookup. `System(cause)` preserves the error returned by `std::linux`.
`InvalidInput` rejects a null entry or a nonzero stack size below the local
minimum. `Joined` rejects a second join through an already retired owner.
`UnexpectedResult` rejects an invalid successful syscall result.

## Creating a thread

`entry` must be the C entry of a non-generic Lanius function with exactly
the signature `fn(ptr) -> ptr`, or an equivalent valid native callback.
The compiler supplies such an entry when a supported free function is used
as a value; the pointer itself carries no checked function signature.
`arg` may be null if the entry accepts it. A successful creation starts a
joinable thread and returns its sole join authority. The worker can run
before `spawn` returns. Its pointer result becomes available through `join`.
[Callback entry contract](language-ergonomics.md#c-callbacks)

`spawn` passes null attributes to `pthread_create` and does not initialize
or destroy an attribute object. The default stack follows the host's
configuration, including the process-start stack limit. It is not fixed at
8 MiB. [Linux thread creation](https://man7.org/linux/man-pages/man3/pthread_create.3.html)

`spawn_with_stack(..., 0)` delegates to that same default path. For a nonzero
size, local validation rejects values below `MIN_STACK_BYTES` before any
host call. Passing the local minimum check does not guarantee acceptance:
glibc still checks the requested stack and creation resources.

The custom-stack path owns one private attribute object for the duration
of the call. It initializes that object, sets its stack size, attempts
creation, and then attempts attribute destruction exactly once. Failed
initialization skips both subsequent setup and destruction. Destruction
after successful initialization occurs even if setting the size or creating
the thread failed. Attribute destruction does not stop an already created
thread. [Attribute lifecycle](https://man7.org/linux/man-pages/man3/pthread_attr_init.3.html)

Successful creation and destruction return `Ok(thread)`. Every failure below
returns `Err(SpawnFailure)` with these fields:

| Outcome | `cause` | `cleanup_error` | `started` |
| --- | --- | --- | --- |
| Local validation or initialization fails | `InvalidInput` or `Host(init_code)` | `None` | `None` |
| Stack setup or creation fails; destruction succeeds | `Host(primary)` | `None` | `None` |
| Stack setup or creation fails; destruction also fails | `Host(primary)` | `Some(destroy_code)` | `None` |
| Creation succeeds; destruction fails | `Host(destroy_code)` | `None` | `Some(actual_thread)` |

An error from `spawn_with_stack` therefore does **not** always mean that no
thread started. Recover `failure.started`, keep the argument backing alive,
and join that owner before releasing its backing or returning from main.
Discarding the failure without inspecting `started` discards a possible join
obligation. `SpawnFailure` has no implicit destructor.

A reported destruction error records one failed native cleanup attempt; it
does not assert that native attribute cleanup completed. The object is not
exposed as a retry owner. Linux documents that attribute initialization and
destruction currently succeed for valid objects. Test-injected failures
exercise the wrapper's error and thread-ownership paths; they must not be
described as universal native-resource recovery.

## Joining and borrowed backing

`Thread` has one active cleanup authority. Copying its value or retrieving it
from another container does not create a second authority. Move that
authority logically: stop using the old copy, or reinstall the mutated value
after calling `join` on a temporary copy. In particular, a copy's `joined`
field does not update other copies. Do not fabricate owners from thread IDs,
join through external APIs, or join the same thread concurrently.

`join` waits for termination and returns the worker's pointer result. On
success it marks the owner joined. A later call returns `Joined` without
another native join. On a host error it leaves the owner unjoined and
returns `Host(code)`; the caller retains the owner and the backing obligation.
There is no automatic retry, detachment, cancellation or destruction.

Only a successful join establishes that the thread has terminated and
permits release of memory it could still access. A failed join must not be
treated as equivalent cleanup. The worker's returned pointer can itself
refer to separately owned storage; joining neither frees nor validates it.
[Linux join contract](https://man7.org/linux/man-pages/man3/pthread_join.3.html)

`Thread.id()` and `current()` expose the selected glibc profile's pthread
identity. It is not a Linux TID. An ID is an observation, not an owner, and
the host can reuse it after a thread's lifetime. There is no `join_id`
factory. Store actual `Thread` values when retaining join obligations.

Keep every worker's argument, shared storage and callback code valid until
termination is established. Coordinate shared access through the existing
atomic and synchronization contracts. Raw pointers do not supply a borrow
checker or a data-race check. All Lanius worker threads must finish before
language main returns because the runtime process context is then unmapped.
Runtime exits and traps terminate the process, not just the calling worker.
[Runtime context and allocator](runtime-allocator.md#threads)

The thread module itself requires native linking against glibc. Programs
using `std::atomic`, thread channels or synchronization also need their
documented native libraries, including libatomic where required.

## Scheduling and affinity

`yield_now` makes one `sched_yield` syscall. A zero result becomes `Ok(0)`;
a syscall error becomes `System(cause)`, and any other result becomes
`UnexpectedResult`. It never discards an error or retries implicitly. A
successful yield is not a synchronization operation or a fairness guarantee.

`available_parallelism` counts the set bits in the calling thread's CPU
affinity mask. It makes one raw `sched_getaffinity` syscall with 128 bytes of
backing. Unlike the libc wrapper, the raw syscall returns the number of
bytes written. The implementation checks that count in its original `i64`
form: only 1 through 128 is admitted before any indexing or narrowing.
An empty population also returns `UnexpectedResult`.

This bounded mask represents at most 1024 CPU IDs. A kernel requiring a
larger mask can return EINVAL, surfaced as
`Error::System(std::linux::Error::System(22))`. No fallback count of one is
invented. A successful count is an observation of affinity, not a fixed
worker count or a guarantee of future CPU availability.
[Linux affinity interface](https://man7.org/linux/man-pages/man2/sched_getaffinity.2.html)

## Admission and executable evidence

The public operations are ordinary Lanius functions over existing C and
Linux bindings. They do not use the former `extern "lanius_std"` thread
declarations. The compiler's old no-run service-8 diagnostic catalog remains
a separate metadata dependency; it does not describe this implementation.
No compiler, IR, runtime, proof or ABI change is part of this module move.

Acceptance must establish default/custom-stack success, callback identity,
join state, local rejection before host calls, the attribute outcome table,
recovery of a real started thread after destruction failure, and retained
join authority after a reached join failure. Scheduling and affinity checks
must include host errors and invalid successful results. Caller tests must
separately establish that pool and parallel operations retain or retire
worker-accessible backing correctly.

Native receipts will be recorded after the serialized compiler and runtime
gates complete. Source inspection alone is not executable acceptance.
