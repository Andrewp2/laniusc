# Unix stream IPC and socket pairs

The full library goal remains open. This increment fills the missing local
byte-stream family using existing Linux socket, descriptor and I/O contracts.
Existing TCP/UDP APIs remain the Internet-address family; do not add a Unix
case to their IP address enum or label Unix streams as TCP.

## Public surface in std::socket

```text
UnixAddress = Pathname(core::path::Path) | Abstract(core::slice::View<u8>)
UnixStream { handle:i32 }
UnixPair { first:UnixStream, second:UnixStream }
unix_stream(nonblocking:bool) -> Result<UnixStream,core::io::Error>
unix_pair(nonblocking:bool) -> Result<UnixPair,core::io::Error>
unix_from_owned_handle(handle:i32) -> Result<UnixStream,core::io::Error>
```

UnixStream methods:

```text
borrow() -> &UnixStream
is_open() -> bool
raw_handle() -> Option<i32>
take_handle() -> Option<i32>
close() -> Result<i32,Error>
try_clone() -> Result<UnixStream,Error>
is_nonblocking() -> Result<bool,Error>
set_nonblocking(enabled:bool) -> Result<i32,Error>
bind(endpoint:UnixAddress) -> Result<i32,Error>
listen(backlog:i32) -> Result<i32,Error>
connect(endpoint:UnixAddress) -> Result<i32,Error>
accept(nonblocking:bool) -> Result<UnixStream,Error>
shutdown(direction:Shutdown) -> Result<i32,Error>
send(input:View<u8>) -> Result<i32,Error>
receive(output:View<u8>) -> Result<i32,Error>
wait_ms(readable:bool,writable:bool,milliseconds:i32) -> Result<Ready,Error>
wait_until(readable:bool,writable:bool,deadline:Deadline) -> Result<Ready,Error>
send_until(input:View<u8>,deadline:Deadline) -> Result<i32,Error>
receive_until(output:View<u8>,deadline:Deadline) -> Result<i32,Error>
```

Implement core::io::Read and Write, including flush. Reuse existing Shutdown,
Ready, I/O errors and counted views. No new allocator, host extern, compiler,
runtime ABI or proof source. The owner identifies AF_UNIX/SOCK_STREAM, with
connection/listener state checked by the host. Address queries, Unix datagrams,
seqpacket, credentials and ancillary descriptor passing remain separate work.

## Host and ownership contracts

Creation, pair acquisition and accept atomically request CLOEXEC and the
selected nonblocking mode. accept's argument controls the child; listener
mode controls whether an empty accept may block. Accept uses null peer-address
pointers and publishes its new owner directly, with no fallible decoding.
Adoption requires exclusive ownership of a live Unix stream descriptor; it
checks a nonnegative number without validating family, state or flags.

Copies alias one cleanup authority. take_handle invalidates the wrapper and
transfers that authority; clone uses F_DUPFD_CLOEXEC and creates another
descriptor for the same endpoint/open description. Duplicates share status
flags and shutdown effects; pair endpoints have independent descriptions.
close invalidates before one host attempt, reports errors and never retries;
closing an already retired wrapper succeeds without a call. Closed I/O gives
Host(9), including zero-length operations. No automatic drop is implied.

socketpair uses syscall 53 and packed two-i32 output initialized to -1. Only
exact-zero status plus two distinct nonnegative descriptors publishes both
owners together. No fallible setup follows acquisition. The real Linux kernel
guarantees unchanged output on failure. Malformed invented kernel outputs are
InvalidCount; do not close arbitrary integers from such outputs. Positive
counts/statuses must be checked at full i64 width before narrowing.

connect performs one attempt and acknowledges only exact-zero completion.
Propagate Interrupted, WouldBlock and other host errors. In particular AF_UNIX
EAGAIN must not become Connection::InProgress or readiness-based success.
After a failed host connect, close before making a fresh connection attempt.
No Unix connect_until is introduced by copying the IP pending-connect policy.

## Address contract

Use Linux x86_64 sockaddr_un: two-byte AF_UNIX family and 108 path bytes,
packed in aligned stack storage. Pathname accepts 1..107 raw non-NUL bytes,
adds one terminator and supplies exactly 3+length bytes. Abstract accepts
0..107 arbitrary bytes after one zero namespace marker and also supplies
3+length bytes. Embedded and trailing abstract NUL bytes remain significant;
an empty abstract name is not the family-only autobind request. `@` has no
special interpretation. This is a Linux address profile, not a portable
108-byte pathname guarantee.

Validate View start/length arithmetic and name limits before backing access.
Recheck every borrowed pathname byte for NUL at the host-call boundary, even
when Path construction previously passed. Preserve actual input stride and
start, and copy into stack storage before the syscall. Malformed logical
metadata performs no host call; physical backing/lifetime remain caller
preconditions and overclaims can trap. No allocation or caller-byte mutation.
Malformed logical metadata, rejected name limits and pathname NUL return
InvalidInput. Unix methods, including trait Read/Write and wait_until, reject
a closed owner with Host(9) before other validation or clock access. Existing
IP method error precedence remains unchanged.

Bind never unlinks or overwrites an existing path. Close never unlinks a bound
path. Applications separately manage pathname lifetime and permissions, ideally
in their own directory. Abstract names disappear after the last socket
reference; filesystem permission policy does not apply to that namespace.

## Shared transport boundary

Factor the existing private packed stream send/receive engines by descriptor;
both public owner types use the same 1,024-byte staging, logical validation,
full-word transfer checks, prefix copying and MSG_NOSIGNAL behavior. Keep the
IP Socket's existing datagram rejection and error precedence. Reuse private
flag and readiness helpers where this avoids duplicate policies, preserving
existing IP contracts. Owner wrappers invalidate before invoking close.

send/receive make one host call, do not retry EINTR, and may transfer a prefix.
Valid zero-length calls on a live stream return zero without host access.
receive publishes only a valid confirmed prefix after the host result is
checked; errors/rejected logical views leave the output untouched. Native
physical backing remains a precondition. flush acknowledges absence of a
library buffer, without promising delivery or durability.

The until methods retain the existing one absolute deadline and per-call
MSG_DONTWAIT policy, including their initial operation attempt before waiting.
No new throughput, device-execution or automatic-lifetime claim is introduced.

## Real program: unix_request

CLI is `unix_request path|abstract NAME`, or sole --help/-h. Name is the raw
argv byte string for that explicit namespace; it cannot contain argv NUL.
Capture at most two arguments/128 total bytes. Validate address limits before
network effects. Read at most 1,048,576 stdin bytes through EOF before opening
the socket; input calls are limited to 8,192 including Interrupted and EOF.

Connect one nonblocking stream, send a four-byte big-endian u32 payload length
and the complete binary input, then shutdown Write. Receive one response in
the same format, with payload at most 1,048,576 bytes. Require response EOF;
reject truncation, excessive size and trailing data before stdout. Use public
endian, socket and ordinary I/O APIs. Use one common five-second monotonic
deadline for the connected workflow and at most 8,192 public network transfer
calls; inner readiness retries follow that same deadline. This is separate
from the raw host-attempt count. Never retry a failed connect or replay bytes.
Because the public until methods attempt transfer before waiting, the app
also checks expiration between every successful partial network transfer.

Stage the whole response, close the socket once, then publish only the binary
response payload. Explicitly release every buffer/argv owner on all paths.
Output permits 8,192 calls, diagnostics eight and help 64; SIGPIPE is ignored
for stdout. Socket sends additionally retain MSG_NOSIGNAL. An output failure
can publish a confirmed prefix; prepublication failures publish nothing.

Statuses: 0 success/help; 2 CLI/input-size/attempt bounds; 3 stdin/argv host
failure; 4 allocation; 5 stdout/SIGPIPE setup; 6 socket/connect/network/
framing/deadline/close failure; 7 unexpected internal codec/buffer failure.
Diagnostic is `unix_request: operation failed\n`, preserving primary status if
it fails. App author fixes help bytes before oracle acceptance. Input call
budgets do not impose a wall-clock deadline on blocking stdin.

## Acceptance

- Tiny native pair admission, then direct all-public-method behavior with real
  binary transfers, nonzero offsets, both actual byte strides, >1,024 bytes,
  zero requests, EOF, half-close, closed states and generic Read/Write helpers.
- Separate-process independent host peers for both pathname and abstract
  namespaces, boundary lengths and significant abstract NULs. Verify pathname
  persistence and existing-name refusal, plus revalidation after mutation.
- Explicit malformed/null Views, no host effects on logical rejection, no
  heap services inside library workflows, exact full-width result guards and
  one close per acquired descriptor. Observe transfer/clone/flag independence,
  CLOEXEC and invalidation after close errors.
- Empty accept, full-backlog nonblocking connect, receive/send WouldBlock,
  Interrupted and selected syscall failures, with reached injections and real
  state effects distinguished. Do not fabricate successful transfer counts.
- Real framed application against independent Python peers, model/boundaries,
  deadlines, reached allocation failures and cleanup, response admission and
  confirmed output-prefix behavior. Python is test-only.
- Selected existing IP socket contracts and a real TCP consumer after sharing
  transport engines. Keep source inventory distinct from runtime receipts.
- Root alone serializes every compiler/native/Cargo command under the existing
  lock; each command is below two minutes. Other agents may run static or CPU
  host probes. Preserve root README, AI_POLICY and CONTRIBUTING.

Primary references: [unix(7)](https://man7.org/linux/man-pages/man7/unix.7.html),
[socketpair(2)](https://www.man7.org/linux/man-pages/man2/socketpair.2.html),
[connect(2)](https://www.man7.org/linux/man-pages/man2/connect.2.html),
[accept(2)](https://man7.org/linux/man-pages/man2/accept.2.html) and
[close(2)](https://www.man7.org/linux/man-pages/man2/close.2.html).
