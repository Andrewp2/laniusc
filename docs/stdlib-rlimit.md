# Resource limits

`std::rlimit` reads and changes Linux resource limits with
[prlimit64](https://man7.org/linux/man-pages/man2/prlimit.2.html). That one
system call covers getrlimit, setrlimit and prlimit for this process or
another one. Resources are typed, values are full 64-bit, and the module
allocates nothing. Execution is verified on **Linux x86_64 CPU output from the
GPU compiler**.

| Function | Effect |
| --- | --- |
| `get(resource)` | The calling process's limit |
| `set(resource, limit)` | Replace it; returns the previous limit |
| `get_for(pid, resource)` | Another process's limit (pid >= 1) |
| `set_for(pid, resource, limit)` | Replace another process's limit; returns the previous one |

A `Limit` has `soft` (the enforced value) and `hard` (the ceiling for
`soft`). `limit(soft, hard)` builds one, `with_soft(n)` keeps the hard limit,
and `unlimited()` is RLIM_INFINITY (all ones), tested by `soft_unlimited()`
and `hard_unlimited()`. A soft limit above the hard limit is `InvalidLimit`
before the call. An unprivileged process can lower its hard limit, but cannot
raise it again without CAP_SYS_RESOURCE (`Host(1)`, EPERM). Lower only the
soft limit unless the change is meant to be permanent.

| `Resource` | RLIMIT | Unit |
| --- | --- | --- |
| `CpuSeconds` | CPU (0) | seconds of CPU time; SIGXCPU at soft, SIGKILL at hard |
| `FileSize` | FSIZE (1) | bytes per file; SIGXFSZ when exceeded |
| `Data` | DATA (2) | bytes of data segment and private mappings |
| `Stack` | STACK (3) | bytes |
| `Core` | CORE (4) | bytes of core file |
| `ResidentSet` | RSS (5) | bytes (not enforced by current kernels) |
| `Processes` | NPROC (6) | processes for the real user ID |
| `OpenFiles` | NOFILE (7) | one more than the highest descriptor number |
| `LockedMemory` | MEMLOCK (8) | bytes |
| `AddressSpace` | AS (9) | bytes of virtual memory |
| `Locks` | LOCKS (10) | file locks |
| `PendingSignals` | SIGPENDING (11) | queued signals |
| `MessageQueueBytes` | MSGQUEUE (12) | bytes in POSIX message queues |
| `Nice` | NICE (13) | ceiling 20 - n for the nice value |
| `RealtimePriority` | RTPRIO (14) | realtime priority |
| `RealtimeMicros` | RTTIME (15) | microseconds of realtime CPU without blocking |

`number(resource)` gives the RLIMIT number. Limits are inherited across fork
and exec, so setting one before `std::command::spawn` applies it to the child.
`set_for` changes a running child instead, which races with whatever the child
does first after exec. Use it for an unreaped child, whose PID cannot have been
reused.

## Errors

| `Error` | Meaning |
| --- | --- |
| `Host(errno)` | EPERM (1) when raising a hard limit or changing another user's process, ESRCH (3) when there is no such process, EINVAL (22) for example OpenFiles above `/proc/sys/fs/nr_open` |
| `Bounds` | `pid < 1` for `get_for` or `set_for` |
| `InvalidLimit` | Soft limit above the hard limit |
| `InvalidResult` | Unexpected system call result |

## Evidence

The signal contracts program, `tests/fixtures/stdlib_signals/contracts.lani`
(run by `tests/stdlib_signal_delivery_execution.rs`), also checks this module:

- `InvalidLimit` before the call
- a soft OpenFiles limit of 3 making the next pipe fail with EMFILE
- a child shell reporting the inherited soft limit 40 through `ulimit -n`
- the restored limit admitting pipes again
- raising the hard limit returning EPERM unless the process is privileged
- `set_for` on a sleeping child, returning the inherited limit and leaving
  this process's limit unchanged
- `Bounds` for pid 0, and ESRCH once the child is reaped

The [supervise](stdlib-signals.md#application-supervise) program applies
`--max-open-files` with `set`. Its oracle checks the child's soft and hard
limits through a shell probe.
