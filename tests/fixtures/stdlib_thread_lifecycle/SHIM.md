# Shared real-pthread fault probe

`thread_probe.c` is test-only C interposition around real glibc pthreads.
Compile it with `cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -c`, pass the
absolute object path in `NativeLinkOptions.objects`, and include `dl` in
`libraries` (`atomic` is also needed by callers using `std::sync`). No preload
or compiler-startup interception is used.

The main test thread configures and inspects the probe. Each non-faulted
creation calls the real `pthread_create` and retains its actual `pthread_t`.
A small C trampoline can hold selected creation attempts before entering the
Lanius callback. Successful joins call the real `pthread_join`; injected join
failures leave the actual thread and its join authority untouched.

All signatures below use C `int` / Lanius `i32`, except identities use
`uint64_t` / `u64`. Configuration calls return zero or a positive errno.

| Function | Meaning |
| --- | --- |
| `thread_probe_reset()` | Clear counters, faults and gates, only if every created thread has been joined; otherwise `EBUSY` |
| `thread_probe_fail(kind, ordinal, errno)` | Fail exactly that future absolute call ordinal once; one rule per kind. `(kind,0,0)` clears a rule without resetting live owners |
| `thread_probe_calls(kind)` | Wrapper call count |
| `thread_probe_created()`, `thread_probe_joined()`, `thread_probe_live()` | Successful creations, successful joins, and unjoined real owners |
| `thread_probe_created_id(index)` | Actual ID in successful creation order; index is zero-based |
| `thread_probe_join_attempt(index)` | ID supplied to that join attempt, including failures; index is zero-based |
| `thread_probe_event_count()` | Number of recorded wrapper returns |
| `thread_probe_phase(number)` | Optional direct-fixture diagnostic checkpoint; returns zero and prints a `thread-phase` counter snapshot only when tracing is enabled |
| `thread_probe_event_kind(index)`, `thread_probe_event_ordinal(index)`, `thread_probe_event_result(index)`, `thread_probe_event_id(index)` | Exact call sequence, positive error numbers and identities |
| `thread_probe_hold_create(ordinal)` | Hold that future creation attempt before its Lanius entry |
| `thread_probe_wait_ready(ordinal)` | Wait on a futex condition until its trampoline is ready; three-second monotonic deadline |
| `thread_probe_release(ordinal)` | Release that creation attempt's gate |
| `thread_probe_entered(ordinal)`, `thread_probe_exited(ordinal)` | Whether the real worker has entered or returned from its Lanius callback |
| `thread_probe_stack_size()` | Actual calling pthread stack extent (`u64`) from glibc attribute queries; zero on host query failure; query cleanup bypasses the fault wrappers |

Call kinds are **init=1, setstack=2, create=3, destroy=4, join=5**. Ordinals
start at one and count attempts, including injected failures. Successful
creation indexes and event indexes start at zero. At most 256 creation
attempts and 2,048 events/joins are accepted between resets; exceeding these
fixed test limits exits the process. Invalid getters return `-1` for counts
or zero for identities. `live` means unjoined ownership, not that a worker
has not finished; a held, ready worker with `entered==0` supplies stronger
live-worker evidence.

Init, setstack, create and join faults skip the real call. Destroy faults
call the real attribute destructor first, then replace its successful return
with the injected code. This tests error propagation without making the
probe itself leak attributes. A real destroy error takes precedence over the
synthetic code. Two rules can be active together, such as create2+join1 or
setstack1+destroy1. Retrying a failed join naturally advances its ordinal.

With `LANIUS_THREAD_PROBE_TRACE=1`, each wrapper return also writes one line
to stderr:

```text
thread-probe NAME ORDINAL RESULT ID
```

`NAME` is `init`, `setstack`, `create`, `destroy` or `join`; result is zero or
a positive errno. Create success and every join include the actual pthread
ID as unsigned decimal; other records use zero. The trace is observational:
it is not a foreign implementation of any library operation. Loader, glibc,
probe and source allocations still need separate attribution in resource
gates. Pool/par tests share the existing native source-site verifier rather
than counting all process mappings as Lanius owners.

Unmodified application fixtures can configure the same one-shot faults at
startup with `LANIUS_THREAD_PROBE_FAIL_INIT`, `_SETSTACK`, `_CREATE`, `_DESTROY`
or `_JOIN`. Each value has the exact form `ORDINAL:POSITIVE_ERRNO`, for example
`LANIUS_THREAD_PROBE_FAIL_CREATE=2:11` and
`LANIUS_THREAD_PROBE_FAIL_JOIN=1:16`. Invalid values exit with status 198.
`thread_probe_reset()` clears these rules along with explicit configuration.
