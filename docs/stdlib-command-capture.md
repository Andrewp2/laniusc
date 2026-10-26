# Bounded command capture

`std::command_capture` communicates concurrently with the stdin/stdout/stderr pipes of one `std::command::Child`. It is native Linux x86_64 code, using concrete `std::file::File`, `std::file_ops`, `std::poll::PollSet`, and CLOCK_MONOTONIC operations. The command module's Linux 5.11+, single-thread, manual-owner and outside-reaper restrictions apply. It does not create a shell, thread, event-loop service, or generic forwarding adapter.

## API and ownership

```text
communicate(child: &Child, input: View<u8>, limits: Limits,
            deadline: core::time::Deadline) -> Result<Output, Failure>
```

The input is immutable borrowed raw bytes for the whole call; no UTF-8 or NUL restriction applies. Logical view endpoints are checked; callers provide valid physical backing. A nonempty input requires a still-owned child stdin pipe. Unpiped stdout/stderr are represented by `NotPiped`, not by an assertion that the child's stream produced no data.

`Output` owns `stdout` and `stderr` byte vectors, the actual terminal `ExitStatus`, and `Progress`. A nonzero child exit or signal death is an ordinary capture result. `Progress.startup` preserves `command`'s `Unconfirmed`/`Unknown` certainty; capture never upgrades error-channel EOF to proof of exec.

`Failure` owns the captured prefixes, `Progress`, optional `Overflow { stream, byte }`, a primary `cause`/`stage`, and the first additional `cleanup_error`, if any. Destroy either result once using its `destroy()` method. Views borrow those owners. Copies alias allocations; do not independently destroy copies or forge/mutate owner fields. `Limits` is caller configurable; `Child` internals stay library maintained.

Preflight checks view/limits/input availability, deadline, SIGPIPE policy, and all allocations, followed by another clock/deadline check. Any preflight failure has `progress.acquired == false` and leaves every child endpoint unchanged. It returns empty vectors; its progress describes observations made by this call, not all prior child history.

After preflight, the function transfers all still-owned endpoints using `take_stdin/stdout/stderr`. On either result, every acquired endpoint is closed exactly once. A post-acquisition failure therefore cannot resume communication; its prefixes and counts are available for inspection, while **the caller still owns the Child and must explicitly cancel/reap or retry waiting**. The library never kills, blocks in `wait()`, detaches, or installs a reaper. `Progress.status` may contain a terminal observation while `Progress.reaped` remains false: capture now retains the unreaped leader while descendants hold pipes. The [process-group guide](stdlib-command-groups.md) explains why that anchor matters for cancellation. A child reaped before entry retains its existing cached status; observed ECHILD follows `command`'s permanent PID invalidation policy.

`input_written` counts bytes accepted by successful kernel writes, not bytes the child proved it read. Input states distinguish `NotAcquired`, `NotPiped`, `Sending`, `Sent`, `PeerClosed`, and `ClosedOnError`. EPIPE is a normal `PeerClosed` result: stop sending, close stdin, continue capturing both outputs and waiting for status. The returned count can be shorter than input. Other write failures and a zero count for a positive write are errors.

Stream states distinguish `NotAcquired`, `NotPiped`, `Reading`, `Eof` and `ClosedOnError`. `Eof` means an actual zero read was observed; closing after failure does not manufacture EOF. `stdout_read`/`stderr_read` count confirmed successful reads, including an overflow sidecar byte. Invalid host counts are errors; confirmed earlier progress remains available, but a violated host count contract cannot establish what that faulty operation actually transferred.

## Concurrent I/O and deadlines

The function sets O_NONBLOCK on each acquired pipe endpoint while preserving its append flag and other status bits through `file_ops`. These are exclusively owned command-pipe endpoints: no external aliases, concurrent flag changes, close/reuse, or forged replacement descriptors are allowed. Status flags are shared with duplicate FDs; the API closes endpoints rather than restoring flags on an external alias. The child's opposite pipe endpoint has its own open file description.

One fixed-capacity PollSet monitors all three streams. Each round rotates stream priority and performs at most one ready operation per stream, each transferring at most the File adapter's 1024 bytes. This lets large stdin, stdout and stderr advance together. EINTR/WouldBlock on data I/O and EINTR on poll return to the bounded loop. Flag/query errors are returned explicitly. POLLNVAL and invalid adapter/kernel results are errors.

Readable, HUP and ERR events prompt nonblocking reads. HUP can coexist with unread data; only read 0 closes a read stream as EOF. A write-end HUP/ERR prompts a safe-policy nonblocking write, allowing EPIPE to establish `PeerClosed`. Per-stream byte order is preserved; no total ordering between stdout and stderr is promised.

Terminal observation and EOF are independent. The loop uses non-reaping `try_observe_exit()` while draining after the direct child exits, because descendants may retain the pipes. If all pipes close first, it continues observing until a terminal status or deadline/error, polling negative placeholder FDs while no pipes remain. Once every acquired stream is closed and status is known, one charged `try_wait()` performs the final nonblocking reap. EINTR returns to the same deadline/budget loop. A valid final status returns success immediately, with `Progress.reaped = true`; no fallible clock or budget check follows that irreversible step. A final status mismatch is an explicit failure with `reaped = true`. The library never signals descendants or a process group.

The deadline is an absolute, normalized `core::time::Deadline` in CLOCK_MONOTONIC's domain. The same deadline is retained across interruptions. Clock observations are made around poll and between I/O operations; a reversed clock is an error. Each poll uses the lesser of remaining time (rounded up to milliseconds) and 50 ms, so child status is periodically checked even without pipe events. Observed expiry discards late readiness and returns `Deadline` with captured progress. Scheduling, syscall completion and fixed cleanup can overrun the timestamp: this is an observation-based deadline, not a hard real-time completion guarantee. A prior spawn/error-channel handshake is outside this function.

## Limits and work

Defaults are 16 MiB input, 16 MiB stdout, 16 MiB stderr, and 1048576 abstract operations. Negative byte limits, invalid view metadata, invalid deadline nanoseconds, or impossible vector capacities are rejected. Each output is preallocated to its requested maximum; no heap growth occurs after endpoint acquisition.

An exact output cap needs an EOF probe. At a full cap, one further byte is requested. A zero read succeeds as EOF. A byte causes `OutputLimit` or `ErrorLimit`, with that byte retained in `Failure.overflow`; its stream's vector remains at the cap and its read count includes the byte. No consumed overflow byte is discarded. Since the call immediately fails at the first excess byte, total successful output reads are bounded by the two caps plus one byte. A zero cap accepts an empty stream and detects a nonempty one the same way.

Requested heap storage is:

```text
(max_stdout_bytes + max_stderr_bytes) * size_of<u8>()
+ PollSet(3).requested_bytes()
```

The wide sum above excludes allocator/OS overhead, caller-owned input and fixed stack staging. PollSet owns two allocations; the outputs own at most two more. Zero capacities need no corresponding allocation. Allocation failures before acquisition free all successful allocations and preserve child endpoints.

The operation counter charges each explicit capture clock read, signal-policy query, constructor call (PollSet once and each output vector once), status-flags query, set-status call, poll, `try_observe_exit`, final `try_wait`, read and write attempt. EINTR/WouldBlock data attempts, interrupted polls and interrupted nonblocking waits count. A fresh observation performs one waitid(WEXITED|WNOHANG|WNOWAIT); the final reap performs one wait4(WNOHANG). Cached observations need no new syscall but still spend the abstract call charge. Capture handles EINTR while retaining deadline/budget checks. A `set_status` call internally queries flags and sets them. Thus this is an **abstract operation budget**, not a literal syscall/instruction count. Adapter data copies are at most 1024 bytes per charged read/write; byte-processing work is bounded by those attempts and accepted output lengths. At most three once-only endpoint closes, plus destruction of fixed owners, occur outside the budget so exhaustion cannot skip cleanup. Close errors are never retried.

Primary close errors retain the operation's stage (`Input`, `Output`, `ErrorOutput`, or initial `Close`). On abort, all remaining closes are attempted, with their first error in `cleanup_error`. The original cause keeps priority. A successful result has no unreported close error.

## Explicit SIGPIPE policy

With nonempty input, preflight queries `rt_sigaction(SIGPIPE, NULL, old, 8)` and requires SIG_IGN. Default/custom dispositions are rejected as `SigpipeNotIgnored`. A merely blocked SIGPIPE is insufficient because it can become pending and later terminate the process. The function changes neither disposition nor signal mask.

The caller must explicitly install Ignore if it wants to send input, and keep that disposition stable for the call. This relies on the single-thread/no asynchronous handler/no disposition-mutation contract. It does not pretend a default-policy pipe write will reliably return EPIPE. Empty input only closes stdin and needs no SIGPIPE query. `command::ChildSigpipe::Default` independently restores the child's disposition during launch; ignoring it in the parent does not force ignored SIGPIPE on ordinary children.

## Capture CLI

`sample_programs/library/capture_command.lani` provides:

```sh
capture-command -- /usr/bin/sort -u < input.txt
capture-command --timeout-ms 500 --max-stdout-bytes 1048576 -- /bin/sh -c 'cat; printf summary >&2'
```

Options stop at `--` or the first program; subsequent child options are raw argv bytes. The runner snapshots the bounded parent environment and searches its PATH for bare programs. It stages bounded binary stdin before spawning, then pipes all three streams. Argument capture is limited to 4120 arguments/1 MiB; input/output options cap at 64 MiB each, operation budget at 1000000000, timeout and cleanup grace at one day. Defaults are the library limits, a 10-second capture timeout and a separate 1-second cleanup grace. Only separate option values are accepted.

The timeout covers `communicate`; it excludes stdin staging (which can block), spawn's startup handshake, and final output publication. Completed stdout/stderr are staged before either is published. Each stream's bytes are preserved, but publication is not a transaction: a checked write can leave a prefix. Both publication writes are attempted, owners are destroyed, and any output/diagnostic failure returns 125. Parent SIGPIPE Ignore is installed before allocation so real closed output pipes reach checked error handling.

On capture failure no captured prefix is published; stderr reports numeric stage/reason, errno and confirmed byte counts. Reason values are Bounds 1, InputLimit 2, OutputLimit 3, ErrorLimit 4, WorkLimit 5, Deadline 6, InputUnavailable 7, SigpipeNotIgnored 8, AllocationFailed 9, InvalidResult 10, Io 11, Poll 12, Clock 13 and Wait 14. CLI stages are arguments 1, stdin staging 2, startup 3, capture 4, publication 5. Startup reported/unknown failures use reasons 15/16.

After failure, the CLI explicitly closes still-owned child pipes, sends SIGKILL to the **direct child only**, and attempts nonblocking reaping for the separate grace (at most 10000 iterations, sleeping up to 10 ms). It reports `cleanup-incomplete pid=N` if PID ownership remains at exit, and preserves the first cleanup error. `cleanup-errno=5` is the generic fallback when an error has no native errno (for example, a reversed clock); it is not necessarily a kernel EIO. A kernel-stuck child cannot be guaranteed dead/reaped by a deadline. After the CLI exits, an unreaped child is reparented by the OS; the exited caller cannot later reap it. The library's returned Child ownership is preserved for a continuing caller, whereas a CLI exit necessarily ends that caller.

Capture expiry returns 124. Other runner/capture/I/O failures return 125. Reported startup ENOENT/ENOTDIR returns 127; other reported setup failures return 126. Ordinary child codes are returned unchanged, signal death as 128+signal, after complete capture. No extra diagnostic accompanies an ordinary child nonzero exit. As with the library, an intentional early stdin close can still yield the child's ordinary exit result; that result does not promise every staged stdin byte was accepted.

## Sources and verification

Primary semantics: Linux [poll](https://man7.org/linux/man-pages/man2/poll.2.html), [pipes](https://man7.org/linux/man-pages/man7/pipe.7.html), [write](https://man7.org/linux/man-pages/man2/write.2.html), [sigaction](https://man7.org/linux/man-pages/man2/sigaction.2.html), and the linked command module sources. The selector communication structure was compared with [CPython 3.14.0 subprocess](https://github.com/python/cpython/blob/v3.14.0/Lib/subprocess.py); production behavior is Lanius.

`tests/stdlib_command_capture_execution.rs` executes native admission, owner/progress contracts and the independent Python oracle. Peers fill both output pipes before reading large seeded binary input, test exact/zero caps, early input closure, EOF before exit, and cached child exit with descendant-held pipes. Fault tests cover all four capture allocations, flags, signal query, clocks, poll/data interruption and errors, invalid results, observation/final-wait and close errors, with parent mappings/FD/reaping ledgers. Every injected fault must match its actual syscall, ordinal and error or result. Real broken stdout/stderr pipes exercise cleanup. Injected close EIO models Linux's ownership-ending error contract (the tracer skips the real syscall) and forbids a retry. The deliberate incomplete-reaping model discloses its PID; the independent test harness adopts and reaps that exact child after CLI exit, rather than claiming the CLI did so.

After changing capture to retain its unreaped leader until final stream
completion, both existing groups have separate passing receipts:

| Receipt under `target/stdlib-work/` | Scope | Elapsed |
| --- | --- | ---: |
| `command-group-capture-contracts-first.log` | Concrete admission and ownership/progress fixtures | 8.62 s |
| `command-group-capture-oracle-first.log` | Real capture CLI, independent binary peers and resource/host-fault oracle | 10.84 s |

The oracle now traces waitid and checks both observation EINTR/EIO and final
wait4 EINTR/EIO. Its injection checks require the actual syscall ordinal and
requested errno or synthetic result. These receipts cover native Linux
x86_64 execution through the GPU compiler; the new group-specific cases have
their own acceptance record.
