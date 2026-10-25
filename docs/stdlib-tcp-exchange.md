# Bounded binary TCP exchange

`sample_programs/library/tcp_exchange.lani` is a complete native consumer of
`std::socket`, checked numeric address parsing, owned byte vectors, portable
streams and the monotonic clock. It sends one bounded binary input, closes the
connection's write half, then reads the response through EOF.

```sh
laniusc --stdlib-root stdlib sample_programs/library/tcp_exchange.lani -o tcp-exchange
./tcp-exchange 127.0.0.1:9000 < request.bin > response.bin
./tcp-exchange '[::1]:9000' 5000 1048576 < request.bin > response.bin
```

The peer must consume the request through the write-half EOF and provide a
finite response. The program performs these phases sequentially. Bytes are
opaque: NUL, non-UTF-8 data and empty input or response are supported. The tool
does not add application framing, text encoding or a terminator.

## Arguments and outcomes

```text
tcp-exchange ADDRESS [TIMEOUT_MS [MAX_BYTES]]
```

ADDRESS is a numeric `core::net::SocketAddr`: dotted decimal IPv4 with a port,
or bracketed IPv6 with a port and optional numeric scope identifier. Hostnames
are rejected. TIMEOUT_MS defaults to 5000 and accepts unsigned decimal values
from 0 through 60000. MAX_BYTES defaults to 1048576 and accepts 0 through
16777216. Leading zeros are accepted; signs, whitespace, overflow and empty
numeric arguments are rejected. At most three arguments and 256 argument
bytes are snapshotted. `--help` as the sole argument prints usage.

| Exit status | Meaning |
| --- | --- |
| 0 | Complete response reached EOF and checked stdout output succeeded |
| 2 | Invalid arguments, argument limits, input limit or response limit |
| 3 | Stdin, clock, socket, deadline, close or stdout failure; also zero send progress |
| 4 | Argument snapshot, input vector or response vector allocation failed |

Error statuses carry no diagnostic bytes. The first failure is preserved when
cleanup also fails; a close failure after an otherwise successful exchange
returns status 3 before stdout begins.

## Deadline, staging and ownership

Arguments are validated first. Stdin is read completely into an owned byte
vector before any socket is created. Reading one byte beyond MAX_BYTES is
enough to reject the input; no prefix is sent. Stdin and stdout are outside the
network deadline and may block according to their descriptor behavior.

One absolute monotonic deadline is created after stdin finishes. The program
creates a nonblocking socket, connects, sends all input with explicit partial
progress, shuts down writing and receives until EOF. Every socket helper uses
that same deadline. The application checks it between sends and after every
successful receive, before accepting bytes or EOF, so progress cannot renew
the timeout. These are monotonic clock observations between syscalls, not an
OS guarantee that scheduling or a syscall returns before the deadline. A late
successful receive or EOF returns status 3 without publishing the response.
Timeout zero creates an already-expired deadline and returns status 3. An
initial nonblocking connect attempt can still occur. Timeout does not undo
bytes already sent.

The complete response is staged in a separate owned vector. Every append is
checked against the same MAX_BYTES limit before mutation. The socket is closed
before stdout publication. Input, network, allocation and response-limit
failures publish no response prefix. Checked stdout writes may themselves
partially succeed before a later host failure; that returns status 3.
At startup this Linux x86_64 executable selects BrokenPipe Ignore through
[`std::signal`](stdlib-signals.md), so a closed stdout pipe becomes a checked
EPIPE and cleanup still runs.

MAX_BYTES limits each logical byte stream independently. Vectors grow
geometrically and may reserve more than their current length; socket and stream
calls use bounded 1024-byte scratch buffers. There is one active owner per
vector, argument snapshot and socket descriptor. Every success and error path
destroys the owned buffers and closes any created socket exactly once.

## Integration evidence

`tests/stdlib_tcp_exchange_execution.rs` drives the actual Lanius executable
against independent Rust loopback peers. Peers verify request bytes and the
write-half EOF, then send separately supplied response bytes in fragments.
Coverage includes IPv4 and IPv6, binary and empty data, one-MiB input and output,
partial transfer loops, malformed arguments, logical caps, refused connection
and a response whose fragments exceed the original shared deadline. A focused
syscall-delay regression checks successful byte receives and EOF that arrive
after that deadline.

Allocation denial is injected at every allocation reached by a real exchange.
Host errors, interrupted and temporarily unavailable operations, zero progress
and stdout failure are injected separately. Native traces track every socket
descriptor and match allocation releases by both address and size. All peer and
child waits are bounded. Reference peers and fault tools are test code; the
application and its I/O behavior are implemented in Lanius.

The original three integration groups passed with the canonical signal helper.
The anonymous-pipe checks passed for help and completed network output. The
focused delayed-receive regression passed after the deadline boundary
correction. Logs are in `target/stdlib-work/tcp-exchange/`.
