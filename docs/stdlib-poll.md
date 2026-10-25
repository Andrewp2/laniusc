# Descriptor readiness

`std::poll` provides a reusable readiness set for x86_64 Linux file, pipe and
socket descriptors. It uses the native `poll` syscall through `std::linux`.
Production packing, validation, time arithmetic and ownership are Lanius.

## API

```lanius
pub struct Request { handle: i32, events: u32 }
pub struct Readiness { bits: u32 }
pub fn new(capacity: i32) -> Result<PollSet, Error>;

// PollSet methods; all waits borrow the one active owner.
capacity() -> i32;
len() -> i32;
requested_bytes() -> usize;
readiness(index: i32) -> Option<Readiness>;
as_view() -> View<Readiness>;
poll_ms(requests: View<Request>, milliseconds: i32) -> Result<i32, Error>;
poll_until(requests: View<Request>, deadline: Deadline, maximum_attempts: u32)
    -> Result<i32, Error>;
destroy();
```

`new` accepts capacities from zero through `MAX_CAPACITY` (1,048,576).
It makes at most two allocations: packed `i32` scratch cells and typed
`Readiness` publication storage. A failed second allocation releases the first.
Both buffers are initialized once. Waits never allocate or grow them.
`requested_bytes` reports their requested sizes using actual
`core::mem::size_of<i32>()` and `size_of<Readiness>()`, excluding allocator and
OS bookkeeping. Capacity zero needs no allocation and supports timer waits.
The kernel also limits the number of entries to the process's `RLIMIT_NOFILE`;
a library-valid count can therefore produce `Io(Host(22))`.

Before the first successful wait, `len()` is zero. After success it equals
the request count. The returned integer counts entries with nonzero flags,
rather than flags or unique descriptors. Duplicate handles are allowed and
each record contributes independently. `readiness` returns `None` outside the
published range. `borrow()` supplies a reference for helpers.

For a `File` or `Socket`, obtain a borrowed handle from its `raw_handle()` and
place that handle in a request. Keep its owner alive and open throughout the
wait. PollSet never duplicates, closes, adopts or changes flags on a descriptor.

## Flags and I/O

Requests accept the following bits, combined with `|`:

| Constant | Value | Meaning |
| --- | ---: | --- |
| `READABLE` | 1 | A read may proceed, including EOF |
| `PRIORITY` | 2 | Exceptional/urgent input |
| `WRITABLE` | 4 | Some output may proceed |
| `READ_CLOSED` | 8192 | Stream peer closed its write side |

Zero requests no ordinary events. It can still return exceptional status.
Unsupported request bits, including output-only status bits, are `Bounds`.
Negative handles are ignored and publish zero. An invalid nonnegative handle
publishes `INVALID` for its entry, alongside other entries' normal results.

Output `bits` preserves all 16 `revents` bits, including unknown bits.
`Readiness` has `any`, `readable`, `priority`, `writable`, `read_closed`,
`error`, `hangup` and `invalid` predicates. Additional output constants are
`ERROR` (8), `HANGUP` (16), and `INVALID` (32). These statuses may appear
without being requested. `READ_CLOSED` is distinct from full `HANGUP`.

Readiness is advisory. Prefer nonblocking descriptors, attempt the I/O, and
handle `WouldBlock`, EOF, short transfers and errors. A large blocking write
can still block after `WRITABLE`. `HANGUP` can coexist with readable buffered
bytes: drain the pipe/socket and recognize EOF from a successful zero-byte
read. Polling does not change `O_NONBLOCK` or install signal dispositions.

## Timeouts, deadlines and EINTR

`poll_ms` makes exactly one poll call: `-1` waits indefinitely, zero probes,
and positive values request relative milliseconds. Values below `-1` fail
before the syscall. EINTR returns `Io(Interrupted)`; it is not retried.
An empty request list still makes that call, preserving poll timer semantics.

`poll_until` uses an absolute `core::time::Deadline` from `CLOCK_MONOTONIC`.
Construct it from `std::clock::monotonic_now()` using the `core::time` helpers.
The fractional nanoseconds must be normalized below one billion. Other clock
origins and forged/mutated timestamp fields are caller errors. This clock
excludes system suspend time.

The method checks the clock initially and after each completed poll call.
It rounds positive remaining fractions up to milliseconds and caps each
request at `i32::MAX`. It retains the original deadline across interrupted
and zero-ready calls, recomputing the remaining interval each time. Only
poll's EINTR is retried; `WouldBlock`, kernel memory errors and clock errors
are returned immediately. A clock EINTR is a clock error, without a retry.

`maximum_attempts` bounds actual poll calls, including interrupted calls.
An initially expired deadline succeeds with zero readiness even when the
attempt budget is zero; an unexpired deadline with zero budget returns
`Limit`. A successful zero-ready call before observed expiry retries until
expiry, readiness or the attempt limit. There is no intermediate publication.
Clock reads are bounded by one initial read plus one per attempted poll.

After a successful poll, the whole result is validated before another clock
read. If that read observes deadline expiry, **all entries publish zero and
the method returns `Ok(0)`**, including when poll itself reported readiness.
A backwards clock or clock failure preserves the earlier publication.
This is a rule about observed times, not a real-time return guarantee: kernel
timeout rounding, scheduling and tracing can delay execution beyond a deadline.

## Atomicity, manual ownership and limits

On every validation, host, clock, result or attempt-limit error, published
length and readiness values remain unchanged. Previously borrowed publication
views remain valid through such errors. Scratch contents can change.
A successful wait replaces the publication and invalidates all earlier views,
including after a shorter request list or zero-ready timeout. Readiness values
copied out as scalars remain ordinary values. Destroy invalidates all views.

The library validates nonnegative, nonoverflowing view start/length metadata,
capacity and every request mask before host access. Actual physical backing,
alignment and lifetime of a view are caller preconditions. All output records
are validated before any publication: unchanged descriptor/events fields,
zero `revents` for negative descriptors, a count in range, and exact agreement
between that count and nonzero records. Unknown output flag bits are preserved.
Malformed results report `InvalidResult`, even if a clock might later expire.

These rules are manual invariants, not enforced private fields, lifetimes or
exclusive borrows. Copies of a PollSet alias its allocations: maintain exactly
one active owner and call `destroy()` after its last use. Use values created
by `new`; leave its fields and both Vecs' storage/length/capacity under library
control. Do not forge owners or mutate borrowed publication storage. Request
storage must not alias scratch or publication storage, and neither it nor
the set may be mutated concurrently during a wait. Keep every requested
descriptor open and assigned to the same resource for the call; concurrent
close/reassignment is outside the contract and Linux readiness semantics.

Each attempted wait does O(request count) packing and validation; publication
does another O(request count) pass. Construction and destruction are O(capacity)
initialization and O(1) deallocation respectively. `poll_until` adds at most
`maximum_attempts` such polls, with checked bounded time arithmetic.

Errors are `Bounds`, `Capacity`, `AllocationFailed`, `InvalidResult`, `Limit`,
`Io(core::io::Error)` or `Clock(std::clock::Error)`. Constructor allocation
denial is `AllocationFailed`; kernel ENOMEM remains `Io(Host(12))`.
EINTR/EAGAIN from poll map to `Io(Interrupted)`/`Io(WouldBlock)`; other errno
values remain positive `Io(Host(errno))`. There is no signal-mask-changing
`ppoll`, cancellation, owned-FD registration or implicit retry in `poll_ms`.

## Evidence and sources

Native tests execute GPU-compiled x86_64 Linux Lanius. Fixtures check packed
two-record layout; pipes, buffered HUP and socket half-close; duplicate,
negative and invalid handles; zero-size waits; metadata/flag bounds; saved
views; allocation denial/cleanup; errno and malformed-result injection;
absolute deadlines, late readiness, clock faults/backwards readings, EINTR
and exact attempt counts. An independent Python `select.poll` oracle compares
raw flags for real pipe/socket/file states and thousands of duplicate records.
Python is test-only and does not implement a library operation.

The layout, flags and kernel behavior follow Linux
[`poll(2)`](https://man7.org/linux/man-pages/man2/poll.2.html) and
[`clock_gettime(2)`](https://man7.org/linux/man-pages/man2/clock_gettime.2.html).
The direct syscall boundary was also compared with
[musl's poll wrapper](https://git.musl-libc.org/cgit/musl/tree/src/select/poll.c).
