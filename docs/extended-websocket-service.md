# WebSocket service

`ext::websocket_service` serves many RFC 6455 sessions on one
`std::event` (epoll) loop. A session starts as a request on an
[`ext::http_service`](extended-http-service.md) server: `Hub.upgrade`
validates it with the [`ext::websocket`](extended-websocket.md) frame code,
answers 101, detaches the socket from the HTTP server and serves frames from
then on. permessage-deflate (RFC 7692) comes from `ext::ws_deflate`, the
same code the [WebSocket client](extended-websocket-client.md#permessage-deflate)
uses.

The handshake Accept value comes from
[`openssl_websocket::accept_into`](extended-openssl-websocket.md), which
delegates the RFC 6455 digest to OpenSSL 3. Even a plain WebSocket service
requires `--native-link --native-library crypto`; `libssl` is not required
for this service. The wire/frame module has no native crypto dependency.

## API

```lanius
pub fn default_options() -> Options;
pub fn hub(options: Options) -> Result<Hub,Error>;

pub impl Hub {
    pub fn upgrade(&self, server: &http_service::Server, slot: i32, protocol: Option<View<u8>>) -> Result<i32,Error>;
    pub fn poll(&self, deadline: time::Deadline) -> Result<i32,Error>;
    pub fn next(&self) -> Option<Message>;
    pub fn data(&self, message: Message) -> View<u8>;
    pub fn send(&self, session: i32, opcode: i32, data: View<u8>) -> Result<i32,Error>;
    pub fn send_text(&self, session: i32, data: View<u8>) -> Result<i32,Error>;
    pub fn send_binary(&self, session: i32, data: View<u8>) -> Result<i32,Error>;
    pub fn ping(&self, session: i32, data: View<u8>) -> Result<i32,Error>;
    pub fn close(&self, session: i32, code: i32, reason: View<u8>) -> Result<i32,Error>;
    pub fn watch(&self, fd: i32) -> Result<i32,Error>;
    pub fn external(&self) -> bool;
    pub fn compressed(&self, session: i32) -> bool;
    pub fn is_open(&self, session: i32) -> bool;
    pub fn peer(&self, session: i32) -> net::SocketAddr;
    pub fn active(&self) -> i32;
    pub fn stats(&self) -> Stats;
    pub fn destroy(&self);
}
pub struct Message { session: i32, kind: Kind, start: i32, length: i32, code: i32 }
pub enum Kind { Text, Binary, Closed }
```

| Option | Default | Meaning |
| --- | --- | --- |
| `limits` | `websocket::default_limits()` with 1 MiB frames and messages | Frame and message limits, also after inflation |
| `deflate` | true | Accept permessage-deflate offers |
| `deflate_no_context` | false | This side resets its compression context per message |
| `sessions` | 256 | Open sessions at once (`Full` beyond) |
| `output_bytes` | 8 MiB | Unsent bytes a session may hold before `send` returns `Backlog` |
| `idle_timeout_ms` | 300000 | Silence before the server starts a close (0 for none) |
| `close_timeout_ms` | 5000 | Bound on the closing handshake |
| `compress_min` | 64 | Shorter messages are sent uncompressed |

`poll` waits once (until the deadline or a session's own timeout), does the
reads, writes and timeouts, and returns how many messages `next` can hand
out. Payload views from `data` stay valid until the following `poll`. Pings
get Pongs, fragmented messages are reassembled, text is checked as UTF-8,
and protocol errors close the session with 1002, 1007 or 1009. A `Closed`
message carries the peer's code, 1005 when it sent none, the server's code
when it failed the session, or 1006 when the transport ended without a
Close. `watch` adds another descriptor, such as the HTTP server's own epoll
descriptor, so one wait covers both.

## Upgrade failures

`Hub.upgrade` validates the request and selected protocol before computing
Accept. A checked-helper failure returns
`Accept(openssl_websocket::Error)`, including provider rejection and an
unexpected digest size. It leaves the connection in its HTTP slot, writes
no 101 response and publishes no WebSocket session. The caller can still
send an HTTP error response; `ws_echo_server` maps this failure to 500.

## permessage-deflate

`upgrade` accepts the first permessage-deflate offer whose parameters parse
(`ws_deflate::negotiate`):

- The server keeps context takeover: one level-1 encoder keeps its 32 KiB
  window across a session's messages, so a repeated message is a few bytes.
  It resets per message when the client offered
  `server_no_context_takeover`, or always with `deflate_no_context`
  (`ws_deflate::negotiate_no_context`), and then the response carries
  `server_no_context_takeover`.
- A `server_max_window_bits=N` in the offer is kept in the response, and the
  encoder then matches no farther back than 2^N bytes (N from 8 to 15).
- `client_no_context_takeover` is kept in the response. Received messages
  inflate with a 32 KiB history whatever the client's window.

Messages of at least `compress_min` bytes are compressed. With context
takeover a message that fails to compress or to frame leaves the client's
inflater out of step, so that session fails with 1011.

## Sample and historical executed evidence

[`ws_echo_server`](../sample_programs/library/ws_echo_server.lani) echoes
messages on `GET /ws` and relays them to every session on `GET /chat`.
`--no-deflate` declines permessage-deflate and `--deflate-no-context` makes
the server reset its context per message.

The following groups predate the checked OpenSSL Accept migration and
retain their earlier source scope. The
[current migration receipts](extended-openssl-websocket.md#current-caller-migration)
record the changed upgrade and sample failure paths separately.

[`echo_oracle.py`](../tests/fixtures/extended/websocket_service/echo_oracle.py)
drives it with a hand-written RFC 6455 peer
([`peer.py`](../tests/fixtures/extended/websocket_service/peer.py)) that can
send frames with any bits, masks and lengths: handshake, echo sizes,
Ping/Pong, fragmentation, an Autobahn-style list of framing errors, UTF-8,
close codes, limits, broadcast, many sessions, leftover bytes after the
upgrade, and permessage-deflate against Python's `zlib`. The deflate cases
inflate the server's replies with one `zlib` decompressor for a whole
session (context takeover: a repeated 3,000-byte random message comes back in
under 100 bytes), with a fresh one per message after
`server_no_context_takeover` or `--deflate-no-context`, and with a 9-bit
window after `server_max_window_bits=9`.

```text
ws-service cases=89
```

[`deflate_oracle.py`](../tests/fixtures/extended/websocket_service/deflate_oracle.py)
checks `ext::ws_deflate` alone against `zlib`: compression with and without
context takeover for both roles, windows of 8, 9, 10, 12 and 15 bits (a
`zlib` inflater with that window accepts every message, and a match reaches
1,500 bytes back only from 11 bits), inflation of sync-flushed and final
peer messages, corrupt and oversized input, and offer negotiation.

```text
ws-deflate cases=9
```

## Limits of this version

- One thread; a session's messages are buffered whole, up to
  `limits.message_bytes`.
- A compressing session holds about 500 KiB of encoder state from its
  first compressed message, plus a 32 KiB inflate history.
