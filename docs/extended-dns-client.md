# DNS transport

`ext::dns_client` sends one standard DNS question to an explicit numeric
nameserver using `ext::dns` and `std::socket`. It supports IPv4 and IPv6,
UDP retries, and one bounded TCP fallback. Production code is Lanius.
The existing native socket, clock, and entropy bindings currently execute
on Linux x86-64; this module adds no host bindings.

This is an optional extended library. It does not add a dependency from
`std` to `ext`. It does not consult NSS, `getaddrinfo`, `/etc/resolv.conf`,
search domains, or a host resolver. It does not chase CNAMEs, cache answers,
convert IDNA, verify DNSSEC, authenticate a nameserver, or implement TLS.
A valid DNS error response, including NXDOMAIN or SERVFAIL, is a successful
transport result whose `Message.rcode()` the caller must inspect.

## API and ownership

```lanius
pub enum Mode { UdpOnly, UdpThenTcp, TcpOnly }
pub enum Id { Random, Fixed(i32) }
pub enum Transport { Udp, Tcp }
pub struct Question {
    name: core::slice::View<u8>,
    qtype: i32,
    qclass: i32,
    dnssec: bool,
    id: Id,
}
pub fn question(name: core::slice::View<u8>, qtype: i32) -> Question;
pub fn default_options() -> Options;
pub fn query_until(
    server: core::net::SocketAddr,
    question: Question,
    options: Options,
    deadline: core::time::Deadline,
) -> core::result::Result<Response,Failure>;
```

`question` selects class IN, no DO bit, and `Id::Random`. Its name is a
borrowed, uncompressed, root-terminated wire name, including the final zero
byte. Labels preserve arbitrary bytes; the 63-byte label and 255-byte total
name limits still apply. Question type and class are checked unsigned
16-bit values. AXFR and IXFR are explicitly unsupported because they can
require multiple messages. Queries set RD, and optionally EDNS version zero
and DO, through the existing `ext::dns::query` writer.

The caller keeps the question's physical backing alive and unchanged until
`query_until` returns. Counted views may have nonzero starts and arbitrary
valid physical strides. Negative or overflowing logical ranges are rejected;
physical storage size, layout, and lifetime remain the caller's contract.

`Response` owns one final `alloc::vec::Vec<u8>` allocation. `as_view()` borrows
the exact response bytes, without a TCP length prefix. `message()` returns a
validated borrowed `ext::dns::Message`; its names, records, and RDATA borrow
the same owner. The retained message is constructed only after the final
byte buffer is stable. No growth, resize, or byte mutation follows validation.
Returning or moving a shallow descriptor does not move its heap storage.

Keep one active manual owner. Do not mutate `Response.bytes`, replace its
storage, or independently destroy a copied descriptor. Do not use message
views after `response.destroy()`. `destroy()` releases the byte owner; it
does not release the caller's question. Every error releases all internal
buffers and attempts to close each owned socket once. No response view is
published on error.

For example, with an already constructed canonical name `wire_name`, a
numeric `server`, and a caller-owned deadline:

```lanius
let q: ext::dns_client::Question =
    ext::dns_client::question(wire_name,1);
let result: core::result::Result<ext::dns_client::Response,
    ext::dns_client::Failure> = ext::dns_client::query_until(
        server,q,ext::dns_client::default_options(),deadline);
// Handle result.is_err() before unwrapping in an application.
let response: ext::dns_client::Response = result.unwrap();
let message: ext::dns::Message = response.message();
let rcode: i32 = message.rcode();
// Inspect borrowed questions and records while response is alive.
response.destroy();
```

## Correlation and supported response profile

Each UDP attempt creates a fresh connected, nonblocking socket. The kernel
selects its local address and ephemeral port and filters the connected peer;
`receive_from`'s reported address and port must also equal `peer_addr()`.
Connecting pins the local route/address for the outstanding query, avoiding
an unconnected wildcard socket's missing destination-address information.
Source port unpredictability depends on the host stack, its configuration,
and any NAT. A fresh socket does not guarantee a distinct port.

`Id::Random` takes the low 16 bits of an OS entropy draw without modulo bias.
Entropy errors are returned, with no weaker fallback. Each retry draws again.
`Id::Fixed(0..65535)` is an explicit override for callers and reproducible
experiments; it provides weak correlation only. Neither mode authenticates
DNS data. DO and AD bits are not DNSSEC verification.

Before acceptance or fallback, a response must have QR set, QUERY opcode,
the current ID, exactly one complete question, the same question type/class,
and a label-aware name match with ASCII letters folded case insensitively.
Other bytes remain exact. Wrong or incomplete envelopes are discarded under
shared packet, byte, and work limits. In particular, a matching ID with TC
and a missing or different question cannot initiate TCP.

The first question must use the canonical uncompressed name representation:
there is no earlier completed name it could refer to under `ext::dns`'s
compression policy. This library deliberately requires one question even
where a general TCP DNS peer might omit it. This is a narrower correlation
profile than accepting an ID-only response.

A correlated nontruncated UDP message and every complete correlated TCP message must
pass the complete existing DNS parser: all sections, typed RDATA extents,
compression bounds, EDNS validation, and no trailing bytes. A correlated
malformed complete response terminates the operation. Unrelated traffic does
not consume a full-message parse allowance.

A correlated UDP TC response or locally truncated datagram triggers one TCP
fallback in `UdpThenTcp`. The bounded header/question scan does not trust
possibly cut answer/RDATA bytes. A cut question is discarded. A datagram's
reported full length above the declared response cap fails instead of
bypassing that cap through fallback. `UdpOnly` returns `Truncated` after
correlated truncation. TCP responses with TC return `Truncated`; there is no
second fallback or hidden EDNS downgrade.

TCP uses a dedicated connection. It coalesces the two-byte big-endian length
and query before sending, advances through partial sends, then reads exactly
two prefix bytes and exactly the declared body. Lengths below 12 and lengths
above the declared cap fail before allocating the body. Early EOF reports
the phase-local completed byte count. A complete response is accepted without
waiting for EOF, a half-close, or a following frame. This one-query interface
does not implement connection pooling or pipelining.

These choices follow [RFC 1035 transport framing](https://www.rfc-editor.org/rfc/rfc1035.html#section-4.2),
[RFC 5452 response matching](https://www.rfc-editor.org/rfc/rfc5452.html#section-9.1),
[RFC 7766 TCP framing and correlation](https://www.rfc-editor.org/rfc/rfc7766.html#section-6.2.3),
and [RFC 6891 EDNS payload limits](https://www.rfc-editor.org/rfc/rfc6891.html#section-6.2.3).
The test oracle uses dnspython 2.7.0; its `dns.query` implementation was also
consulted for exact TCP reads and correlation before truncation fallback.

## Deadlines, retries, and limits

The caller supplies one absolute monotonic deadline. Preparation, entropy,
all UDP attempts, TCP fallback, validation, close, and publication use that
same deadline. Clock observations reject reversals. Checks surround network
calls, including successful final receives, and follow parsing and close.
These are observations between library/syscall operations, not a realtime
OS scheduling guarantee. Existing socket/entropy helpers can perform internal
retries before control returns; the transport checks the deadline on return.

A successful UDP send starts one fixed response window, ending at the earlier
of the global deadline and send time plus `retry_ms`. Junk packets, partial
progress, and readiness notifications do not renew that window. Only a window
expiry starts another UDP attempt. Host errors, malformed correlated replies,
and resource limits fail immediately. Every old socket is closed before the
next attempt. The TCP fallback uses the current query and ID, consumes the
remaining global budget, and is attempted only once. TCP errors do not restart
UDP or create a retry cascade.

| Option | Default | Contract |
| --- | ---: | --- |
| `mode` | `UdpThenTcp` | `UdpOnly`, `UdpThenTcp`, or `TcpOnly` |
| `attempts` | 2 | 1–8; counts UDP attempts, or one direct TCP query |
| `retry_ms` | 2000 | 1–60000; fixed UDP receive window |
| `udp_payload` | 1232 | 0 omits OPT and receives up to 512; otherwise 512–65507 |
| `response_bytes` | 65535 | 512–65535; DNS body cap, independent of TCP's prefix |
| `datagrams` | 64 | Positive total received datagrams, including junk and empty packets |
| `received_bytes` | 4194304 | Positive total wire bytes observed; TCP prefix and full truncated UDP lengths count |
| `work` | 16777216 | Cumulative conservative work allowance; never reset between attempts |
| `wire` | `ext::dns::default_limits()` | Nested message, record, name, pointer, option, parse/output work limits |

1232 is this module's conservative EDNS policy default. The advertised UDP
payload must fit the actual receive buffer and not exceed `response_bytes`.
The portable `std::socket` UDP cap is 65507 even though the DNS/TCP message
cap is 65535. A TCP response can therefore be larger than any supported UDP
datagram. TCP-only mode retains the configured EDNS query behavior.

The nested DNS message cap must cover `response_bytes`; its output cap must
be 282–65535 to cover the largest supported single-question query. The nested
record limit must be positive; its name cap is 1–255 and other counts/work
must be nonnegative. Inconsistent options fail before network activity.

The cumulative work accounting charges the canonical input name, every
received byte plus one per read/datagram, a fixed 32 per envelope, and the
scanned label extents. It reserves the full configured `wire.work` allowance
before each query encoding and before the one complete-response validation.
This conservative reservation can reject a small message when the configured
cumulative budget is smaller than a parser allowance; it does not silently
reset or promise an exact CPU-instruction count. Network wait loops are bounded
by deadline observations; packet/byte/work caps bound packet processing.

`Stats` reports attempts, received datagrams, discarded envelopes, received
bytes, and charged work. Kernel-filtered packets are not reported as library
discards. The response size excludes TCP's two-byte frame prefix.

## Failures

`Failure` contains a typed `cause`, `Stage`, accumulated `Stats`, and an
optional secondary socket-close error. Causes distinguish invalid options,
unsupported transfer queries, allocation, clock/entropy/socket errors, DNS
validation errors with offsets, timeout, packet/byte/work/response limits,
correlation, truncation, invalid frame length, and early EOF. Stages distinguish
preparation, entropy, opening, connecting, sending, receiving a UDP packet,
receiving the TCP prefix/body, validating, and closing. EOF counts are relative to the prefix or body read in progress.

The original transfer/validation failure remains primary if close also fails.
A close failure after an otherwise good response discards the response.
In UDP-only mode, already-known truncation remains primary if close fails;
exhausting all UDP response windows reports timeout in the receive stage,
with any final close error retained as secondary. A close failure on an earlier
expired window remains the primary close error and prevents another attempt.
The socket owner is invalidated before the one close attempt, following the
existing `std::socket` close contract; failed close is never retried.

## Query application

`sample_programs/library/dns_query.lani` provides a real bounded query CLI:

```text
dns-query 127.0.0.1:5353 example.com --type 1
dns-query '[::1]:5353' example.com --mode tcp --raw
dns-query 127.0.0.1:5353 - --wire-name --dnssec <name.wire
```

ADDRESS is numeric with an explicit port. NAME uses literal byte labels
separated by dots; a final dot is allowed and `.` is root. No backslash escape,
Unicode normalization, or IDNA is applied. `--wire-name` requires NAME `-` and
reads at most 255 canonical binary name bytes from stdin through EOF.

Options are `--type`, `--class`, `--id`, `--timeout`, `--attempts`, `--retry`,
`--udp-size`, `--max-bytes`, `--max-packets`, `--max-received`, `--max-work`,
`--max-records`, `--max-output`, `--mode udp|tcp|auto`, `--raw`, `--wire-name`,
and `--dnssec`. Numeric values use checked unsigned decimal. Duplicate options
use the last value. The argument snapshot caps 40 tokens and 8192 bytes.
Timeout defaults to 5000 ms and caps at 60000 ms; its absolute network deadline
starts after argument/name input. Stdin reading itself has no clock timeout.
Output defaults to a 262144-byte cap, adjustable through `--max-output` up to
1048576. `--raw` writes the exact DNS response; the default deterministic report
includes transport statistics, header/RCODE, canonical hexadecimal question
names, and typed records. IDs vary unless explicitly fixed.

The entire raw response or report is staged before stdout. Preparation,
validation, and limit failures emit no stdout. A later host write error can
follow already written bytes. All staged owners are still released. The CLI
selects process-wide SIGPIPE Ignore before allocating or writing, so closed
stdout/stderr pipes take the checked error path. Signal setup failure is quiet.

Exit statuses are 0 success, 2 argument/name syntax, 3 transport/protocol/
configuration/resource-limit failure, 4 allocation failure, and 5 stdin/stdout/
stderr or signal-policy failure. Diagnostics name the cause and stage and
include attempts/packet counts; a secondary close error is marked. RCODE
errors remain successful reports.

## Focused verification

`tests/extended_dns_client_execution.rs` compiles the native public API and
application. The native fixture uses a counted native byte array with a
nonzero start and physical byte stride, validates borrowed records, and then
destroys the response owner. The test-only Python oracle runs independent IPv4
and IPv6 loopback peers using dnspython 2.7.0. It covers binary names, case
folding, IDs/questions/sources, TC and local truncation, retry windows, RCODEs,
EDNS, fragmented framing, no-EOF completion, malformed/partial frames, and a
60000-byte opaque RDATA response. No external nameserver is needed.

Strace tests fail every reached allocation on UDP, TCP, and fallback paths;
exercise socket/connect/send/receive/poll/close/clock/entropy failures, EINTR,
late successful datagram and final TCP-body reads, and validation plus close
failure. They match every successful mmap with an unmap at the same address and
requested length, and check every owned socket
gets a close attempt. CLI tests cover short writes, EIO/EINTR, stdin errors,
`/dev/full`, actual anonymous broken stdout/stderr pipes, signal setup failure,
and no partial output on protocol/limit errors.

The independent test dependency lives only in an ignored virtual environment:

```sh
python3 -m venv target/stdlib-work/dns-oracle-venv
target/stdlib-work/dns-oracle-venv/bin/python -m pip install dnspython==2.7.0
```

Run this focused execution target under the repository's shared GPU scheduling
lock and native compiler timeout policy. No resolver or Python parser is used
by production code.
