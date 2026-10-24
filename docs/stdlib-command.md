# Commands on Linux

`std::command` launches real executables on native Linux x86_64, using `std::linux`. It requires Linux 5.11 or newer with `close_range(..., CLOSE_RANGE_CLOEXEC)` enabled. Other targets and restricted kernels are unsupported; an unavailable syscall is a reported child setup failure. Request preparation, child setup and lifecycle management are implemented in Lanius.

## Request and startup

Construct `request(program, arguments, environment)` and optionally change its fields before `spawn`. `arguments` must contain at least `argv[0]`; it is independent of `program`. All strings are raw bytes, including empty arguments and non-UTF-8 paths. Program, cwd, arguments, and environment entries must contain no NUL. Program and cwd must be nonempty. Environment entries must have a nonempty key followed by `=`; empty values, duplicate keys, and supplied order are preserved.

The request borrows every view and its physical backing until `spawn` returns. Views validate nonnegative start/length and checked logical endpoints; callers supply valid physical backing. `spawn` copies all strings and pointer tables before `fork`, so these inputs can be destroyed after it returns. Copies of an owner alias one resource: do not independently close or reap copies.

`Child` and `Environment` must originate from this API. Their PID/cache/descriptor/Vec fields are library-maintained ownership state: do not forge owners or mutate those fields directly, even though the current language exposes record fields. Configure `Request` fields and use owner methods instead.

`Search::Exact`, the default, passes the program directly to `execve`. `EnvironmentPath` searches the first `PATH=` entry of the supplied child environment only when the program contains no slash. Missing PATH is `MissingPath`. Empty components search the child's working directory; relative components are relative to that directory. No system default PATH is inserted. EACCES takes priority when all candidates fail with EACCES/ENOENT/ENOTDIR; any other exec error stops the search. ENOEXEC is reported, with no implicit shell fallback.

`spawn` returns `Result<Spawn, Failure>`:

| Result | Ownership and certainty |
| --- | --- |
| `Err(Failure)` | Validation, allocation, descriptor preparation, or fork failed. No child was created; all library-owned resources have been released. |
| `Spawn::Child(Child)` | Fork succeeded; the startup channel reached EOF without a record. `startup()` is `Unconfirmed`. The caller owns the child and must reap it. |
| `Spawn::Failed(FailedStart)` | A valid child setup/exec error record was received. Owned pipes are closed, the child has been reaped, and both `failure` and actual `status` are returned. |
| `Spawn::Unknown(UnknownStart)` | Startup read/protocol or failure-reaping failed. `child.startup()` is `Unknown`; the returned child owner must be canceled/reaped or retried. A recoverable wait failure retains its PID. |

EOF is deliberately **not proof that exec occurred**. It can also mean that child setup was killed or that reporting failed. The kernel can kill a process after exec has passed its recoverable failure point. A later exit status cannot retrospectively distinguish every such case. A child that successfully runs an executable and exits 127 is an ordinary `Child`; a reported exec error has a separate `Failed` result. The channel protocol is an internal 16-byte magic/stage/errno/checksum record over a blocking `pipe2(O_CLOEXEC)` pipe. Partial writes/reads and EINTR are handled; a short/corrupt record is unknown, never a successful-exec claim.

`Failure` exposes `kind`, `stage`, and positive Linux `errno` (zero for library validation/allocation errors). Stages distinguish validation, allocation, descriptors, fork, close-range, redirect, directory, exec, startup read/protocol, wait, signal, close, and environment capture. Failed child setup normally exits 127, but `FailedStart.status` records what wait actually observed.

## Standard streams and descriptors

Each of `stdin`, `stdout`, and `stderr` accepts:

| `Stdio` | Child behavior |
| --- | --- |
| `Inherit` | Duplicate the corresponding parent descriptor, preserving a closed stream as closed. |
| `Closed` | Close that descriptor in the child. |
| `Null` | Read from or write to `/dev/null`. |
| `Borrowed(fd)` | Duplicate a valid caller-owned FD; the caller keeps ownership. |
| `Pipe` | Connect a new pipe; the child owner holds the parent's endpoint. |

All borrowed sources are checked before internal FDs are opened. Sources and pipe endpoints are normalized to FD ≥3 with CLOEXEC; child `dup3` installs streams at 0/1/2. Swapping stdout and stderr is cycle-safe, including when a parent standard stream is closed. Duplicates share the kernel open file description, offsets and status flags. The caller must not close, reuse, or change source FDs during `spawn`.

The child marks **all** descriptors ≥3 CLOEXEC with `close_range`; only its installed standard streams survive exec. Existing parent descriptors and their flags stay unchanged. There is no arbitrary extra-FD inheritance in this API. Setup uses fixed child stack storage and raw syscalls, with no allocation, libc callbacks, unwinding, or Lanius host calls between fork and exec/exit. The copied current stack continuation is required; clone/new stacks/vfork are outside this implementation.

`take_stdin`, `take_stdout`, and `take_stderr` transfer an optional `std::file::File` owner out of the child. Close each transferred file once. `close_pipes` consumes all still-owned endpoints, attempts every close, and reports the first error. Linux close is attempted once and ownership is invalidated even on error; retrying could close a reused descriptor.

`wait()` consumes/closes still-owned stdin and ignores that close error. It **does not drain stdout or stderr**. Drain/take/close output pipes before a blocking wait as appropriate. Writing all stdin before reading a child's large stdout, or reading two large output pipes sequentially, can deadlock on backpressure. This module does not yet provide multi-pipe `communicate`, buffering, deadlines, or asynchronous I/O. `try_wait()` neither closes nor drains pipes.

## Waiting and signals

`wait()` and `try_wait()` use wait4 for this positive PID only. `try_wait()` returns `None` while running. A terminal result is cached: subsequent waits return the same `ExitStatus`, `id()` becomes `None`, and `signal` is rejected. `ExitStatus` provides the raw Linux status, optional exit code, optional terminating signal, and core-dump bit.

EINTR is retried. Observed ECHILD permanently invalidates PID ownership and returns `LostChild`; later signaling is rejected, preventing a reused PID from being signaled. Other wait failures retain the child for retry. Never discard a live `Child`: there is no automatic destructor, background reaper, or detached mode. There is no pidfd; the precondition against outside reaping is essential until a wait observes termination/ECHILD.

`signal(0..64)` targets the owned positive child PID, including signal 0's permission/existence check. `cancel_and_wait()` closes all still-owned pipes, ignores their close errors, sends SIGKILL to the direct child, and waits; ESRCH still proceeds to wait. A different kill/wait error retains ownership for retry. Descendants/process groups are not canceled. SIGKILL cannot guarantee an immediate return from an uninterruptible kernel operation.

`ChildSigpipe::Default`, the request default, restores **only SIGPIPE's disposition** in the child. `Inherit` leaves it untouched. The signal mask and other dispositions are inherited according to exec rules, including ignored dispositions. This is useful when the parent uses `std::signal` Ignore for checked writes: ordinary child programs still get conventional SIGPIPE behavior by default. It does not construct a wholly default signal environment or unblock a blocked SIGPIPE.

Call from a single-threaded process with no asynchronous user handlers, concurrent descriptor/environment changes, external waiters, SIGCHLD Ignore, or SA_NOCLDWAIT. Those interactions require a separate process-wide synchronization policy. Observed ECHILD is safe even when this precondition was violated. The library does not install SIGCHLD handlers or mutate the parent's SIGPIPE disposition.

## Limits and environment capture

Defaults are 4096 arguments (including argv[0]), 4096 environment entries, 65536 bytes per string, 1048576 bytes of packed string storage, and 256 PATH candidates. Negative limits/invalid view metadata are `Bounds`; exceeded quotas are `Limit`. The string limit excludes its trailing NUL. Packed storage includes NULs, a separate program copy, arguments, environment, cwd and all derived PATH candidates. Search candidates are checked against both string and aggregate limits before allocation.

Preparation allocates exactly three owners: `4*ceil(packed_bytes/4)` string bytes, `8*(argc+envc+2)` pointer-table bytes, and `4*path_count` offset bytes, plus allocator overhead. All arithmetic is checked in widened integers before narrowing. Validation/copy work is bounded by the supplied counts and string/storage limits; PATH prefix scanning and copying are bounded by the scanned PATH plus generated candidates. These are allocation/input bounds, not a CPU-time or syscall-duration deadline. Kernel pathname/executable processing can block.

`snapshot_environment(limits)` returns an owned `Environment`; `as_view()` borrows it and `destroy()` frees it. It uses the raw variable map exposed by `std::env`, verifies lengths/read counts, and fails on detected inconsistencies; it cannot detect every same-length mutation. No environment mutation is allowed during capture. Explicit request environments preserve duplicate values exactly; this convenience snapshot resolves duplicate keys to the first visible value exposed by the host lookup API. Capture temporarily allocates key scratch, two lengths per entry, packed entry bytes (without NULs), and one View per entry. Its aggregate entry-byte limit excludes NULs; a later spawn counts its own NULs and copies.

## Executable runner

`sample_programs/library/run_command.lani` is a real command runner:

```sh
run-command --status -- /usr/bin/sort -r
run-command --clear-env --env PATH=/bin:/usr/bin --env MODE=fast --cwd /tmp -- sh -c 'printf "%s\n" "$MODE"'
run-command --stdin input.txt --stdout output.txt --stderr errors.txt -- /usr/bin/sort
run-command --append --stdout output.txt -- /bin/echo more
```

Options stop at the first program (or `--`), so child options are passed verbatim. Only separate option values are accepted. `--env KEY=VALUE` repeats up to 128 times; the last value for a key wins and overrides captured parent entries. `--clear-env` starts empty. A bare program then needs an explicit PATH. Argument capture is capped at 4352 arguments/1 MiB; the library request limits above still apply. Override-key comparisons are bounded by 128 times the captured environment/override bytes. All arguments and environment entries remain raw bytes.

`--stdin FILE`, `--stdout FILE`, `--stderr FILE` open files in the **parent's** current directory; `--cwd` changes only the child directory. Outputs truncate unless `--append` is present. Opens can create/truncate files even if startup later fails. Child output streams directly; it is not staged or atomic. No shell interprets text unless the selected executable is itself a shell.

The runner installs parent SIGPIPE Ignore before argument allocation, allowing checked diagnostic writes and cleanup on a real closed output pipe. Child policy defaults to restoration and can be changed with `--sigpipe inherit`. `--status` writes `startup=unconfirmed exit=N` or `signal=N` to stderr after reaping. Ordinary child exit codes are returned unchanged; signal death maps to 128+signal. Reported missing executable/ENOTDIR returns 127; other reported child setup/exec failures return 126. Runner/argument/environment/I/O/unknown-startup failures return 125. Ordinary child nonzero exits do not produce a runner error diagnostic.

Unknown startup is canceled/reaped. A recoverable wait failure is retried during cleanup before the runner discards ownership; cleanup can block, as ordinary wait can. Persistent host failure to permit waiting cannot provide a finite cleanup guarantee. Checked status/diagnostic write failure returns 125 after cleanup. SIGPIPE setup failure returns 125 before allocation without attempting another diagnostic.

Parent redirection owners are each closed once after spawn. Every close is attempted; the first close error becomes stage 13/exit 125 after an ordinary child has been reaped. An earlier spawn/setup/unknown failure keeps diagnostic priority. Open-failure cleanup also closes all already-opened owners while preserving the earlier open failure. Close is never retried.

## Sources and verification

The implementation follows Linux [fork](https://man7.org/linux/man-pages/man2/fork.2.html), [execve](https://man7.org/linux/man-pages/man2/execve.2.html), [pipe2](https://man7.org/linux/man-pages/man2/pipe.2.html), [dup3](https://man7.org/linux/man-pages/man2/dup.2.html), [close_range](https://man7.org/linux/man-pages/man2/close_range.2.html), [wait4/waitpid](https://man7.org/linux/man-pages/man2/waitpid.2.html), [kill](https://man7.org/linux/man-pages/man2/kill.2.html), and [close](https://man7.org/linux/man-pages/man2/close.2.html). The CLOEXEC error-channel design was compared with [Rust 1.90's Unix process implementation](https://github.com/rust-lang/rust/blob/1.90.0/library/std/src/sys/process/unix/unix.rs); this API exposes the otherwise ambiguous EOF explicitly.

Focused native tests cover real fork/exec/wait and failed exec, cached status, binary pipes, PATH/cwd/environment, descriptor swaps and closed streams, child SIGPIPE policies, ECHILD invalidation, malformed requests and limits. Independent Python subprocess peers and strace fault/FD/allocation/reaping ledgers exercise the runner and startup ambiguity. The test sources are `tests/stdlib_command_execution.rs` and the `command*` fixtures under `tests/fixtures/stdlib_foundation`.

The injected close-EIO regression checks error reporting and a single close attempt. Since strace injection skips the actual syscall, its ledger models Linux's documented ownership-ending close-error contract; it does not claim that the injected syscall physically released the FD. Real closed stdout/stderr pipes exercise SIGPIPE handling without that model.
