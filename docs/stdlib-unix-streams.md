# Unix byte streams and socket pairs

This guide specifies the [Unix-stream increment](library-unix-stream-plan.md)
in `std::socket`. Production source is frozen; pair admission, direct
contracts, address peers, effect/fault gates and the real application pass.
Selected IP and real TCP-application regressions pass separately. This finite
native Linux x86_64 increment is accepted; a narrow generic Result-chain
compiler boundary is retained.
Earlier [IP socket receipts](stdlib-sockets.md#executable-evidence) do not
establish this added surface or its shared-transport refactor. The full
standard/extended library goal remains open.

Unix streams are local AF_UNIX/SOCK_STREAM endpoints, distinct from the
numeric-address TCP/UDP `Socket` family. No Unix case is added to
`core::net::SocketAddr`, `Family` or `Kind`. A byte stream supplies neither
message boundaries nor an application framing protocol.

## Public values and creation

```text
UnixAddress = Pathname(core::path::Path) | Abstract(core::slice::View<u8>)
UnixStream { handle: i32 }
UnixPair { first: UnixStream, second: UnixStream }
unix_stream(nonblocking: bool) -> Result<UnixStream, Error>
unix_pair(nonblocking: bool) -> Result<UnixPair, Error>
unix_from_owned_handle(handle: i32) -> Result<UnixStream, Error>
```

`Error` here means `core::io::Error`. Addresses borrow caller storage; the
stream owns only its descriptor. `unix_stream` creates an unconnected owner.
`unix_pair` returns two connected unnamed endpoints, each with an independent
open description and cleanup authority. Both directions can carry bytes.
There is no pair-wide automatic cleanup; close or transfer each endpoint.

Creation, pair acquisition and accept request CLOEXEC and the selected
nonblocking mode atomically. `unix_from_owned_handle` rejects a negative
number but does not inspect family, type, connection state or flags. Its
caller must exclusively own a live Unix-stream descriptor. Adoption does not
duplicate a descriptor or set CLOEXEC.

Pair acquisition uses Linux syscall 53 with a packed two-i32 output block
initialized to -1. Only exact-zero status and two distinct nonnegative
descriptors publish the pair together; no fallible setup follows acquisition.
The [host contract](https://www.man7.org/linux/man-pages/man2/socketpair.2.html)
leaves that output unchanged on failure. Malformed invented output gives
`InvalidCount`; arbitrary integers from it are not closed as trusted owners.
All returned statuses/counts are checked at full i64 width before narrowing.

## Borrowed address contract

The chosen Linux x86_64 layout uses a two-byte AF_UNIX family and 108 name
bytes in aligned packed stack storage. The API supplies these exact lengths:

| Address | Caller bytes | Encoded name | Syscall address length |
| --- | --- | --- | --- |
| `Pathname(path)` | 1..107 non-NUL bytes | Bytes followed by one NUL | `3 + length` |
| `Abstract(view)` | 0..107 arbitrary bytes | One zero namespace marker, then the bytes | `3 + length` |

The pathname bytes need no UTF-8 decoding or normalization. Every pathname
byte is rechecked for NUL at bind/connect, even if `Path` construction already
passed. The input View's start, length and addition bounds and the name limit
are checked before backing access. Reads preserve its actual stride and start;
the syscall receives a stack copy. Rejection changes no caller byte and makes
no host call. Physical backing, live storage and stable input during the call
remain caller preconditions; a physical overclaim can trap.

Embedded/trailing abstract NULs remain significant. An empty abstract name
still contains its namespace marker; it is not the family-only autobind
request. `@` has no prefix meaning in either variant. The 108-byte layout and
abstract namespace are Linux choices, not a portable Unix pathname guarantee.
See [unix(7)](https://man7.org/linux/man-pages/man7/unix.7.html).

Bind never unlinks or replaces an existing pathname; close never unlinks a
bound pathname. The application separately manages path lifetime, directories
and permissions. Abstract names have no filesystem permission policy and
disappear after the last socket reference closes. Address queries, Unix
datagrams, seqpacket, credentials and ancillary descriptor passing are not
implemented by this increment.

## Public method inventory

All 19 inherent methods belong to `UnixStream`. `Ready`, `Shutdown` and
`Deadline` reuse the existing socket/time contracts. Together with the three
constructors and three trait members, these add 25 public functions/methods
to the module's earlier 35, giving 60 source-defined entries. This inventory
does not establish execution of every entry.

| Method | Result / behavior |
| --- | --- |
| `borrow()` | `&UnixStream`; borrows the same owner |
| `is_open()` | `bool`; tests wrapper state |
| `raw_handle()` | `Option<i32>`; borrowed descriptor number |
| `take_handle()` | `Option<i32>`; invalidates the wrapper and transfers its authority |
| `close()` | `Result<i32,Error>`; invalidates first, then one close attempt |
| `try_clone()` | `Result<UnixStream,Error>`; new CLOEXEC duplicate of the same endpoint |
| `is_nonblocking()` | `Result<bool,Error>`; reads shared status flags |
| `set_nonblocking(enabled)` | `Result<i32,Error>`; changes that flag, preserving unrelated flags |
| `bind(endpoint)` | `Result<i32,Error>`; validates/copies one borrowed Unix address, then one bind |
| `listen(backlog)` | `Result<i32,Error>`; requires nonnegative backlog; host controls queue/state |
| `connect(endpoint)` | `Result<i32,Error>`; one connect, acknowledges only exact-zero completion |
| `accept(nonblocking)` | `Result<UnixStream,Error>`; explicit child mode and CLOEXEC; no peer-address decoding |
| `shutdown(direction)` | `Result<i32,Error>`; Read/Write/Both shutdown without closing |
| `send(input)` | `Result<i32,Error>`; one staged transfer of at most 1,024 bytes |
| `receive(output)` | `Result<i32,Error>`; one staged transfer/EOF, confirmed prefix only |
| `wait_ms(readable,writable,milliseconds)` | `Result<Ready,Error>`; one poll, 0 probe/-1 indefinite |
| `wait_until(readable,writable,deadline)` | `Result<Ready,Error>`; readiness under one absolute deadline |
| `send_until(input,deadline)` | `Result<i32,Error>`; immediate attempt, then deadline-bounded readiness/retry |
| `receive_until(output,deadline)` | `Result<i32,Error>`; immediate attempt, then deadline-bounded readiness/retry |

The `core::io::Read` and `Write` implementations additionally expose `read`,
`write` and `flush`. They use the same descriptor transport and ordinary
[stream helper contracts](stdlib-streams.md); exact/all helpers can fail after
a confirmed prefix. `flush` reports no library buffer on a live wrapper. It
does not acknowledge delivery, peer consumption or durability.

### Ownership and connection state

Copying a wrapper aliases one cleanup authority. `take_handle` retires that
wrapper and transfers the descriptor; a caller must not also close a stale
copy. `try_clone` uses F_DUPFD_CLOEXEC to create another descriptor for the
same endpoint/open description. Duplicates share nonblocking flags, queues
and shutdown effects. Pair endpoints have independent status flags. There
is no automatic destructor, borrow checker or concurrent-mutation guarantee.

Close invalidates before one host attempt and never retries, including EINTR.
A repeated close on the retired wrapper returns zero without a host call.
An error leaves the wrapper retired; it must not be reused to close a possibly
reassigned number. This follows the explicit
[Linux close policy](https://www.man7.org/linux/man-pages/man2/close.2.html).
Operations requiring a live descriptor report `Host(9)` on a retired wrapper,
including zero-length I/O. Inspection/transfer methods instead return the
closed state or `None` as listed above.

The host checks whether an owner is connected, listening or otherwise usable.
The accept argument selects the child mode; the listener's mode determines
whether an empty accept can block. Accept supplies null peer-address pointers
and returns the child directly, with no post-acquisition address decoder or
`AcceptFailure` cleanup envelope. See
[accept4](https://man7.org/linux/man-pages/man2/accept.2.html).

Connect makes one attempt and propagates `Interrupted`, `WouldBlock` and
other errors. In particular, AF_UNIX EAGAIN does not become IP
`Connection::InProgress` or readiness-based success. After a failed host
connect, close before creating a fresh connection attempt. No Unix
`connect_until` is supplied. The
[connect host contract](https://www.man7.org/linux/man-pages/man2/connect.2.html)
distinguishes AF_UNIX EAGAIN and leaves failed socket state unspecified.

## Transfer, readiness and failure

Send/receive share the IP stream's private descriptor engines: packed 1,024-byte
stack staging, complete logical View admission and full-width count guards.
No library operation allocates heap storage. Send uses MSG_NOSIGNAL; receive
copies only a valid confirmed prefix after checking the host result. Errors
and rejected logical metadata leave output unchanged, even if a real host
receive already consumed bytes before returning a malformed injected count.
Physical source/destination access remains the caller's responsibility.

Ordinary send/receive make one host call, do not retry EINTR and can return
short progress. A live valid empty View returns zero without a transfer;
zero from a nonempty receive is EOF. Repeated aggregate calls must advance
only by confirmed progress. These byte streams add no message framing.

Until transfers use per-attempt MSG_DONTWAIT, including on blocking owners.
They make an initial operation attempt before waiting; an immediately ready
operation can therefore succeed with an already expired deadline. Subsequent
WouldBlock/Interrupted paths reuse the same absolute deadline. They return
one transfer/EOF, not full-buffer completion. Aggregate callers retain that
deadline and check expiry between successful partial transfers.

`wait_ms` rejects values below -1 and reports readable, writable, hangup,
error and timeout separately. Readiness is a hint; another alias can consume
it. `wait_until` retries interruption and rounded/capped poll windows while
checking monotonic time and expiry before each retry. An expired wait returns
timed_out without polling. Host scheduling can overshoot; this is no hard
real-time or cancellation guarantee.

Malformed logical addresses/Views and negative backlog use `InvalidInput`.
Unix descriptor operations check closed-owner `Host(9)` first, including
trait read/write before logical range checks. EINTR/EAGAIN map to
`Interrupted`/`WouldBlock`, other native errno to `Host(code)`, malformed positive host results to
`InvalidCount` and transfer deadline expiry to `Host(110)`. Guard failures
are explicit; no silent fallback or success is introduced. Kernel errors
can follow real state effects, and copying does not grant rollback.

## Application and verification status

The [unix-request program](stdlib-unix-request.md) reads bounded binary input
through EOF, uses one explicit pathname/abstract namespace and exchanges big-endian
length-prefixed messages. It uses one connected-workflow deadline, stages the
complete admitted response, closes before publication and retains manual
buffer/argv cleanup. All four registered application groups pass 84 process
cases: model 24 in 8.49s (`target/stdlib-work/unix-stream-app-model-first.log`),
then CLI 19, I/O 24 and rejection 17 in 21.50s
(`target/stdlib-work/unix-stream-app-boundaries-first.log`). Two real
five-second deadline cases keep the peer connection open until the client
returns. The [application guide](stdlib-unix-request.md) owns the detailed
framing, fault and cleanup scopes.

One registered native pair-admission test passes in 7.30s:
`target/stdlib-work/unix-stream-admission-first.log`. It creates one real
pair, exchanges binary bytes in both directions using nonzero View offsets,
preserves surrounding sentinels and closes both owners explicitly. Repeated
close leaves the wrappers retired and makes no extra host call. See the
[direct fixture guide](../tests/fixtures/stdlib_foundation/unix_stream/README.md)
for the producer and selected command. This small gate does not establish
the full method, address or failure surface.

Frozen production source is [stdlib/std/socket.lani](../stdlib/std/socket.lani),
SHA-256 `44f6739da9be0aa5d28c97dee2c905bca157e237df91c34a0ee6790909c06ccb`.
The broader direct contract gate passes one test in 8.11s:
`target/stdlib-work/unix-stream-direct-final.log`. Its amended producer
retains generic Read/Write bounds and uses typed Result locals before
unwrapping. The first producer failed compilation at an immediate generic
`.unwrap()` call with `LNC0027`, before native execution. The
[socket-free reproduction/control](../tests/fixtures/stdlib_foundation/unix_stream/generic_result_chain/README.md)
is independently confirmed: an explicit ignored positive-test run in
`target/stdlib-work/unix-stream-generic-result-chain-control.log` takes 4.67s
and has one chained test failure at `chained.lani:14`, plus one passing native
typed-local control. The control checks the returned count and an actual
memory effect with the same generic bound. The mixed command is not a green
gate. The [dependency ledger](library-dependencies.md) records this exact
method-chain boundary; no compiler repair or broad generic failure is implied.

The named-address gate passes one test in 6.90s:
`target/stdlib-work/unix-stream-address-first.log`. Its 90 probes comprise
52 independent pathname/abstract peer cases, 36 boundary/lifetime cases and
two actual full-backlog controls. The
[address fixture guide](../tests/fixtures/stdlib_foundation/unix_stream_address/README.md)
records both actual byte layouts, namespace/name boundaries, significant NULs,
pathname mutation rechecks and path/abstract lifetime behavior. Two genuine
host controls observe EAGAIN and no connection despite writable poll readiness
and zero SO_ERROR. This is finite host/address evidence, separate from pair
admission and scripted syscall failures.

The logical-bounds/no-host and real descriptor-lifecycle tests pass in the
initial mixed `target/stdlib-work/unix-stream-effects-first.log` command
(13.15s); that command also has a fault-harness failure and is not wholly
green. The bounds phase rejects malformed/null-backed metadata and mutated
pathnames without any host call. The lifecycle test observes a real pair and
duplicate, transfer/adoption, shared versus independent flags, surviving
duplicates and exactly three actual descriptor closes.

The final fault-only test passes in 8.40s:
`target/stdlib-work/unix-stream-effects-fault-accepted.log`. It checks 63
schedules: 13 genuine baselines and 50 reached injections. All wrappers
retire once; three skipped-close schedules leave actual descriptors until
process exit, so those attempts are not counted as executed kernel closes.
Full-width injected results and native `InvalidCount` remain required. The
driver corrections accept only the exact scheduled strace compatibility
warning and parse hexadecimal F_GETFL results; no Lanius source changed.
The earlier fault-only attempt failed that hex parser. The
[effect fixture guide](../tests/fixtures/stdlib_foundation/unix_stream_effects/README.md)
owns exact trace policies and the failed/accepted harness scopes. These finite
observations do not establish general cleanup under arbitrary host failures.

Three selected existing IP tests pass in 10.93s:
`target/stdlib-work/unix-stream-ip-regressions.log`. They execute TCP/UDP
ownership, options, half-close and trait I/O; IPv4/IPv6 full datagrams,
strides and truncation; and repeated readiness/EAGAIN/interruption under
absolute deadlines. Internet connect-EAGAIN and malformed-accept tests were
filtered; their earlier receipts remain historical. This selected regression
scope does not establish new Unix behavior.

The selected real TCP-application regression passes one test in 8.86s:
`target/stdlib-work/unix-stream-tcp-app-regression.log`. Six independent-peer
exchanges cover IPv4 and IPv6 with payload lengths 0, 257 and 1,048,576.
They check complete request, Write half-close and response, including multiple
staged calls for the large case. Three other TCP-application tests were
filtered; this is not a full application-suite rerun.

All six new library tests, four Unix application groups and the selected
regressions are accepted across their separate receipts. The finite profile
is Linux x86_64 CPU output from the GPU compiler on the tested local filesystem
and Linux abstract namespace. No direct
GPU-device, other-platform, formal-verification or automatic-lifetime claim
is made. This adds no compiler, ABI, native extern or new host service; it
uses the existing Linux syscall binding.
