# Owned native sockets

`std::socket` supplies executable TCP and UDP over numeric IPv4/IPv6 addresses.
Address values, parsing and formatting come from `core::net`. Socket ownership,
address packing, staging, errors and deadline loops are implemented in Lanius;
the only new native boundary is [the explicit Linux syscall binding](stdlib-linux.md).
Verified execution is x86_64 Linux. This is not a DNS resolver, TLS session,
HTTP client/server or a claim of user GPU execution.

## Creation and ownership

`create(Family::{Ipv4,Ipv6}, Kind::{Tcp,Udp}, nonblocking)` returns
`Result<Socket,core::io::Error>`. New and accepted descriptors, and `try_clone`
duplicates, have close-on-exec set atomically. IPv6 availability and default
dual-stack behavior remain host policy; `Setting::Ipv6Only` makes the requested
policy explicit before binding. Cross-family endpoints return `InvalidInput`.
IPv4-mapped IPv6 addresses must be supplied explicitly as IPv6 values.

Each Socket is one manual descriptor owner. Copying its record aliases that
owner; it does not duplicate the descriptor. `borrow` yields a reference;
`is_open`, `family`, `kind` and `raw_handle` expose state. Do not close or adopt a
borrowed raw handle. `take_handle` closes the owner logically and transfers its
descriptor to the caller. `from_owned_handle` adopts an exclusively owned live
socket, with family/kind supplied as caller preconditions; it only rejects a
negative number. It does not inspect arbitrary descriptors or change their flags.

`close` invalidates first and attempts the host close once. Even an error leaves
the owner closed; never retry a possibly reused descriptor. Repeated close on
the same reset owner returns zero. `try_clone` creates a new CLOEXEC descriptor,
but both descriptors refer to the same socket: queues, shutdown, socket options
and open-file status flags are shared. Closing one duplicate leaves the other
live. There is no automatic destructor or thread-safety guarantee.

## Connection and endpoint operations

| Operation | Contract |
| --- | --- |
| `bind(address)` | One host bind; port zero requests an assigned port. |
| `local_addr()`, `peer_addr()` | Validate returned family/length and decode address, port and IPv6 scope. IPv6 flow information is not represented by `core::net`. |
| `listen(backlog)` | TCP only; nonnegative backlog, with kernel queue limits. |
| `accept(nonblocking)` | TCP only; returns `Accepted { socket, peer }`. The new descriptor's nonblocking policy is explicit. Malformed peer metadata closes the new descriptor before returning an error. |
| `connect(address)` | `Connected` or `InProgress` for EINPROGRESS/EALREADY. Internet EAGAIN remains `WouldBlock`; it is not fabricated progress. |
| `connect_until(address, deadline)` | Requires nonblocking mode, waits for completion, consumes SO_ERROR and checks the peer endpoint. Timeout is `Host(110)`. |
| `shutdown(Read\|Write\|Both)` | Requests the corresponding host half/full shutdown without closing the owner. |
| `take_error()` | Consumes/reset SO_ERROR and returns `Option<positive errno>`. Reading it through another duplicate affects this socket too. |

After a failed or timed-out connection attempt, close the owner before starting
a new connection; a timeout does not cancel a pending connect. Do not change
nonblocking flags through any alias during `connect_until`. Readiness is a hint,
not a reservation, and does not by itself prove a connection succeeded.

## Stream and datagram I/O

`send(View<u8>)` and `receive(View<u8>)` are TCP operations. They make one host
attempt and transfer at most 1,024 bytes, adapting native/strided caller slices
through packed stack storage. Positive short progress is returned explicitly;
nonempty receive returning zero is EOF. Empty TCP views return zero without a
host transfer. The `core::io::Read`/`Write` implementations use the same paths;
the existing `read_exact`, `write_all` and copy contracts apply. On nonblocking
sockets these ordinary operations may return `WouldBlock` after a prefix.

`send_until` and `receive_until` perform an immediate nonblocking attempt, then
retry readiness/interruption under the supplied absolute deadline. They return
one transfer/EOF, not a full-buffer guarantee. Aggregate callers must keep the
same deadline and check expiry between successful partial transfers. Each I/O
attempt uses MSG_DONTWAIT, including on a normally blocking descriptor. Socket
sends use MSG_NOSIGNAL so EPIPE is an error rather than a SIGPIPE termination.
An error preserves caller buffers; a successful send may already have exposed
bytes to the peer. `flush` checks an open TCP owner and reports no pending
library buffer; it promises neither peer delivery nor acknowledgement.

UDP uses separate whole-message operations:

- `send_to(view,address)` stages and sends exactly one datagram, including an
  empty datagram. Inputs above `MAX_DATAGRAM = 65,507` return `LimitExceeded`.
- `receive_from(view)` consumes one datagram and returns
  `Datagram { peer, copied, full_length }`. MSG_TRUNC retains the full reported
  length; `is_truncated()` compares it with copied bytes. Empty destination
  views still consume a datagram, and a zero-length datagram is not EOF.
- A destination larger than the common payload cap receives at most that cap;
  excess bytes are discarded by the kernel and reflected in `full_length`.
  Lengths above 65,535 or malformed endpoint metadata return `InvalidCount`.
  A datagram may already have been consumed when validation fails; caller
  output remains unchanged until the complete reply has been validated.

The cap is a common non-jumbogram IPv4/IPv6 policy. Smaller path MTUs, socket
buffers and other network errors remain real host results. No fragmentation,
delivery, retransmission or message-authentication guarantee is added by UDP.

## Options, readiness and failure behavior

`option`/`set_option` support ReuseAddress, KeepAlive, NoDelay, ReceiveBuffer,
SendBuffer and Ipv6Only. Boolean setters accept only 0/1; buffer requests must
be positive. KeepAlive/NoDelay require TCP, and Ipv6Only requires IPv6. Buffer
getters return kernel accounting values, which Linux may double relative to a
request. `is_nonblocking` and `set_nonblocking` use fcntl and preserve unrelated
status flags; changes affect duplicate handles.

`wait_ms(readable,writable,milliseconds)` makes one poll attempt. Zero probes;
-1 waits indefinitely; smaller negatives are invalid. `Ready` exposes readable,
writable, hangup, error and timed_out separately. A hung-up socket can still
have readable bytes. Invalid descriptors are errors, not a timeout.
`wait_until` uses the monotonic clock, rounds remaining fractions up to
milliseconds, caps long host requests and retries EINTR. It checks expiry
before every retry, including when another alias repeatedly consumes readiness.
An already expired deadline returns timed_out without polling. Clock reversal
or malformed host results return `InvalidCount`; host scheduling can overshoot
a requested timeout, so this is not a real-time scheduling guarantee.

Errors use `core::io::Error`: malformed view/options/kind/family are
`InvalidInput`, closed owners use `Host(9)`, EINTR/EAGAIN become
`Interrupted`/`WouldBlock`, other native errno remains `Host(code)`, and deadline
expiry is `Host(110)`. Logical view bounds are checked before access. Initial
physical backing, lifetime and immutability/exclusive output access remain
caller preconditions. No operation allocates heap storage. TCP staging uses
1 KiB, UDP staging 64 KiB of stack per transfer, plus small address/argument
blocks. Preserve sufficient stack space; the API supplies no stack exhaustion
recovery. Low-level operations do not retry host errors implicitly.

## Executable evidence

`tests/stdlib_socket_execution.rs` has five passing native groups:

- TCP/UDP endpoints, CLOEXEC cloning/adoption, shared nonblocking flags,
  options, trait I/O, EOF/half-close, deadlines and manual descriptor cleanup.
- Both IP families with exact 65,507-byte datagrams, offset/strided views,
  empty/truncated messages and invalid logical metadata.
- Injected Internet connect EAGAIN preserving its error.
- A readable socket with every receive forced to EAGAIN, a writable socket
  with every send interrupted, and continuously interrupted poll. All stop
  at their original deadline and close every owner.
- A real accepted descriptor followed by corrupted output address length:
  the new descriptor is closed before the decode error is returned.

Syscall traces track every socket/accept/duplicate descriptor through one close
and deny claims of heap-free behavior if mmap/munmap occurs. The
[TCP exchange application](stdlib-tcp-exchange.md) adds independent loopback
peers, fragmented/large traffic and real application failure/cleanup evidence.

Primary host contracts: Linux man-pages for [socket](https://man7.org/linux/man-pages/man2/socket.2.html),
[connect](https://man7.org/linux/man-pages/man2/connect.2.html),
[accept](https://man7.org/linux/man-pages/man2/accept.2.html),
[receive](https://man7.org/linux/man-pages/man2/recv.2.html), and
[poll](https://man7.org/linux/man-pages/man2/poll.2.html).
