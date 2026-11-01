# Child resource usage

`std::command` reports kernel resource usage through
[wait4](https://man7.org/linux/man-pages/man2/wait4.2.html) and
[getrusage](https://man7.org/linux/man-pages/man2/getrusage.2.html), using raw
system calls with a stack `struct rusage`; no allocation. Execution is verified
on **Linux x86_64 CPU output from the GPU compiler** under the
[child-process profile](stdlib-command.md) (single-threaded, no outside waiters).

## Usage values

`Usage` holds the fields Linux maintains:

| Field | Meaning |
| --- | --- |
| `user`, `system` | CPU time as `core::time::Duration`, microsecond granularity |
| `max_rss_kib` | Peak resident set size in KiB |
| `minor_faults`, `major_faults` | Page faults without and with I/O |
| `block_input`, `block_output` | Filesystem I/O in 512-byte units |
| `voluntary_switches`, `involuntary_switches` | Context switches from blocking and from preemption |

`cpu()` returns `user + system`, saturating only beyond the Duration range. The
other rusage fields are always zero on Linux and are omitted. The kernel
apportions one CPU total between user and system time; the split is an
estimate, the sum is exact to the microsecond.

## Reaping with usage

```lanius
Child::wait_with_usage() -> Result<Reaped,Failure>
Child::try_wait_with_usage() -> Result<Option<Reaped>,Failure>
```

`Reaped` holds `status: ExitStatus` and `usage: Usage`. The usage of a reaped
child includes everything its own terminated descendants accumulated, as long
as the child (or its descendants) waited for them; it does not include orphans
reaped by someone else. That differs from
[`std::host_clocks::Clock::ProcessCpuOf`](stdlib-host-clocks.md), which counts
only the process's own threads.

`wait_with_usage()` closes any still-owned stdin like `wait()`, blocks, and
retries EINTR. `try_wait_with_usage()` makes one wait4(WNOHANG) call: `None`
while the child runs, and EINTR as a failure with errno 4. Both record the
terminal status exactly like `wait()` and `try_wait()`, so later plain waits
return the cached status. Usage exists only at the reap itself: after any plain
wait has reaped the child, both return `AlreadyReaped`. A prior non-reaping
`observe_exit()` or `try_observe_exit()` does not consume it. ECHILD revokes
ownership with `LostChild`, as for the other waits. If the kernel record
were malformed (negative values or microseconds out of range), the status is
still cached and the call fails with `Host` errno 5.

## Process, children and thread totals

`resource_usage(UsageTarget)` calls getrusage: `Process` for this process
(all threads), `Children` for every descendant this process has waited for
(cumulative; `max_rss_kib` is the largest single child's peak), and `Thread`
for the calling thread. Errors are `Host` failures at `Stage::Wait`.

## Application: child-usage

[`sample_programs/library/child_usage.lani`](../sample_programs/library/child_usage.lani)
runs one program, reaps it with `wait_with_usage()` and writes one record on
stderr:

```sh
laniusc --stdlib-root stdlib sample_programs/library/child_usage.lani -o child-usage
./child-usage -- make -j4
./child-usage --format tsv -- sh -c 'exit 3'
```

`child-usage [--format json|tsv] -- PROGRAM [ARG...]` parses arguments, spawns
and maps statuses exactly like
[time-command](stdlib-host-clocks.md#application-time-command). The JSON keys,
in order, are `pid`, `status`, `code`, `signal`, `user_ns`, `system_ns`,
`cpu_ns`, `max_rss_kib`, `minor_faults`, `major_faults`, `block_input`,
`block_output`, `voluntary_switches`, `involuntary_switches` and
`children_cpu_ns`. The last is getrusage(RUSAGE_CHILDREN) after the reap, which
equals `cpu_ns` because the program reaps exactly one child. TSV writes a header
line and one row, with `-` for null. Exit status is the child's code or 128 plus
its signal; 125 for child-usage failures, 126 for a program that cannot be
executed and 127 for one that is not found.

## Evidence

`tests/stdlib_child_usage_execution.rs` runs three groups. On the current
source they were executed directly as the same compiled programs and oracle
commands:

- **contracts** (`tests/fixtures/stdlib_child_usage/contracts.lani`), a
  self-checking program: zero children totals before any reap;
  `try_wait_with_usage()` returning `None` for a running child, then a blocking
  usage reap; `AlreadyReaped` after the usage reap and after a plain wait; a
  usage reap after `observe_exit()`; children totals covering both reaped
  children; and thread CPU at most process CPU.
- **cli** (39 cases): help, eight malformed argument lists, ENOENT, EACCES,
  exit codes 0/2/255, signals 9/15, TSV, and stdout passthrough with the
  child's stderr ahead of the report. Every record checks key order, integer
  microsecond times and `cpu_ns == user_ns + system_ns == children_cpu_ns`.
- **usage** (42 cases): a busy child's `cpu_ns` is within 2 µs below and
  100 ms above its own final `process_time_ns()`, in JSON and TSV; a shell's
  usage includes its reaped busy child (at least 249 ms); touching 64 MiB gives
  `max_rss_kib` of at least 65,536 and within 16 MiB of Python's own
  `os.wait4` for the same script, against a much smaller `true`; twenty 2 ms
  sleeps give at least twenty voluntary switches; and on ext4 writing 8 MiB
  with fsync gives at least 16,384 output blocks, while rereading it after
  `POSIX_FADV_DONTNEED` gives at least 16,384 input blocks and no output.
