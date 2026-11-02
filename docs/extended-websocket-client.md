# WebSocket client

`ext::websocket_client` is a synchronous RFC 6455 client for `ws://` and
`wss://` URLs. It connects through the
[HTTP agent's connection layer](extended-http-agent.md#connections-for-upgrades),
so resolution, ordered connect attempts and verified TLS behave as they do
for `http://` and `https://`. The opening handshake, frame parsing and
encoding, fragmented messages, UTF-8 checks and close-code rules are the
existing [`ext::websocket`](extended-websocket.md) frame code, which the
servers also use, run with `Role::Client`. The Accept value is computed in
Lanius (`websocket::accept_into` over `ext::sha1`). permessage-deflate
(RFC 7692) comes from `ext::ws_deflate` over `ext::deflate` and
`ext::inflate`, with context takeover on or off for each side. The `wss://`
transport comes from OpenSSL 3 through the agent, so programs link `libssl`
and `libcrypto`, and they must ignore SIGPIPE.

## API

```lanius
pub fn default_options() -> Options;
pub fn connect(url: View<u8>, options: Options) -> Result<Client,Error>;

pub impl Client {
    pub fn send_text(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn send_binary(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn send_fragment(&self, fin: bool, opcode: i32, data: View<u8>) -> Result<i32,Error>;
    pub fn ping(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn pong(&self, data: View<u8>) -> Result<i32,Error>;
    pub fn receive(&self, timeout_ms: i32) -> Result<Message,Error>;
    pub fn close(&self, code: i32, reason: View<u8>) -> Result<i32,Error>;
    pub fn protocol(&self) -> Option<View<u8>>;
    pub fn is_open(&self) -> bool;
    pub fn is_secure(&self) -> bool;
    pub fn compressed(&self) -> bool;
    pub fn peer_close_code(&self) -> i32;
    pub fn destroy(&self) -> bool;
}
pub struct Message { kind: Kind, data: View<u8>, close_code: i32 }
pub enum Kind { Text, Binary, Ping, Pong, Close }
```

| Option | Default | Meaning |
| --- | --- | --- |
| `agent` | `http_agent::default_options()` | URL limits, connect options, `trust` and `tls` for `wss://` |
| `wire` | `websocket::default_limits()` | 16 MiB frames and messages, 65,536 fragments, HTTP head limits |
| `timeout_ms` | 30000 | Connecting plus the handshake; each send |
| `close_ms` | 2000 | Waiting for the peer's Close, then for its transport close |
| `protocols` | empty | Offered subprotocols, a comma-separated token list |
| `headers` | empty | Extra request fields, such as `Origin` or `Authorization` |
| `deflate` | false | Offer permessage-deflate, context takeover allowed both ways |
| `deflate_no_context` | false | With `deflate`: ask both sides to reset their context per message |

## Opening handshake

`connect` rejects a URL with a fragment (RFC 6455 section 3) and any scheme
other than `ws` or `wss`, then parses the URL as `http`/`https` with
[`ext::http_url`](extended-http-url.md). The request is a `GET` of the URL's
origin-form target with `Host` from the URL authority, a key made from 16
fresh bytes of the OS random source, version 13, the offered protocols and
the caller's fields. `websocket::encode_request` owns the handshake fields;
a caller field that names one fails with `InvalidRequest`.

The response head is read up to its blank line. Any other status than 101
fails with `Rejected(status)`. A 101 must pass `websocket::validate_response`
against the Accept value for this key: exactly one `Upgrade: websocket`, a
`Connection` list with `Upgrade`, the right `Sec-WebSocket-Accept`, at most
one syntactically valid `Sec-WebSocket-Extensions` field, and at most one
selected protocol that was offered. An extension is accepted only when
`deflate` offered one and the field selects exactly permessage-deflate with
valid parameters (see below). Otherwise `Handshake(error)`. Frame bytes that arrive with the head are kept.
`protocol()` returns the selected protocol.

## Frames and messages

Every outgoing frame is masked with a fresh four-byte key. Keys come from a
256-byte pool refilled from the OS random source, so the pool is read once
per 64 frames. `send_text` and `send_binary` send one frame each.
`send_fragment` sends one fragment: opcode 1 or 2 starts a message, 0
continues it, and `fin` ends it; Pings and Pongs may go between fragments.
The frame code enforces message state, text UTF-8 and the 125-byte control
limit before anything is sent. Lengths use the shortest encoding: 7 bits up
to 125 bytes, 16 bits up to 65,535, then 64 bits. `close` refuses a code an
endpoint may not send (anything outside 1000-1003, 1007-1014 and 3000-4999),
a reason over 123 bytes and a reason that is not UTF-8.

`receive(timeout_ms)` returns the next complete message, Ping, Pong or
Close. Fragments are assembled, and Pings and Pongs between them are
returned in arrival order. A Ping is answered with a Pong carrying the same
payload before it is returned. `Message.data` borrows the client's storage
until the next `receive` or `destroy`. A timeout returns `Timeout` and
leaves the client usable, over TLS too: TLS reads are attempted without
blocking and the socket is polled, so a quiet connection does not abort the
TLS stream.

Text is checked as UTF-8 as each fragment arrives, so a bad byte fails the
connection before the message ends; a code point may be split across
fragments.

If the server breaks the protocol, the client fails the connection as
section 7.1.7 asks. It sends Close 1007 for invalid UTF-8 text (in a message
or a Close reason), 1009 for a frame or message over the limits, 1011 when
memory runs out, and 1002 for anything else: framing violations such as a
masked server frame, reserved bits, reserved opcodes (3-7, 11-15),
fragmented or over-125-byte control frames, a continuation with no message,
a new message inside a fragmented one, a length not in its shortest form, or
a Close payload of one byte or with an invalid code. It then closes the
transport and returns `Wire(error)`. EOF without a Close returns `Eof`.

## permessage-deflate

With `deflate` the request carries
`permessage-deflate; client_max_window_bits`, and with `deflate_no_context`
also `client_no_context_takeover; server_no_context_takeover`. The response
must select exactly permessage-deflate with known, unduplicated parameters
(`ws_deflate::accepted`), and an accepted no-context offer must keep
`server_no_context_takeover`; otherwise `Handshake`. A response without the
extension leaves the connection uncompressed (`compressed()` is false).

| Side | Context takeover | Without it |
| --- | --- | --- |
| Sending | One level-1 encoder keeps its 32 KiB window across messages | The server sent `client_no_context_takeover`: the encoder restarts per message |
| Receiving | The inflater keeps the server's history | The server sent `server_no_context_takeover`: the inflater restarts per message |

`send_text` and `send_binary` compress every message into one frame with
RSV1 set: raw DEFLATE ended by a sync flush, without the `00 00 FF FF` tail
(an empty message is the single byte `00`). Text is checked as UTF-8 before
it enters the compressor. If the server limits `client_max_window_bits`
below 15, messages go out uncompressed, which the extension allows; the
encoder always uses a 32 KiB window. `send_fragment` and control frames are
never compressed. With context takeover, a compressed message that fails to
compress or to send leaves the two contexts out of step, so the transport is
closed.

A received message with RSV1 on its first frame is assembled, then inflated
with the tail appended, up to `wire.message_bytes`. RSV1 on a continuation
or control frame, or when the extension was not negotiated, is a 1002
failure. A message that inflates past the limit fails with 1009 (a
compression bomb costs at most the limit), data that does not inflate fails
with Close 1007 and `Inflate`, and inflated text that is not UTF-8 fails
with 1007. Any server window size is accepted.

## Closing

- **Peer first.** When a Close arrives, `receive` sends a Close with the
  same status code (no reason, or no payload if the peer sent none), waits
  up to `close_ms` for the server to close the transport, closes it (with
  TLS close_notify) and returns the Close message. Its code is also in
  `peer_close_code()`. Later sends and receives return `Closed`.
- **Client first.** `close(code, reason)` sends Close with that code and
  reason (no payload when `code` is negative). It then receives until the
  peer's Close, discarding data and answering Pings, and closes the
  transport as above. It returns the peer's close code.

`destroy` releases everything and closes an open transport without a Close
frame.

| Error | When |
| --- | --- |
| `InvalidRequest` | bad options, header or protocol list, or a send the frame state does not allow |
| `BadUrl`, `Url(kind)`, `UnsupportedScheme` | the URL has a fragment, does not parse, or is not ws/wss |
| `Connect(error)` | the agent's connect or TLS failure (see [its errors](extended-http-agent.md#deadlines-limits-and-errors)) |
| `Rejected(status)`, `Handshake(error)` | a non-101 status, or an invalid 101 |
| `Io(error)`, `Timeout` | transport failure; a receive or send deadline |
| `Eof` | the transport ended without a Close |
| `Wire(error)` | the server broke the frame protocol |
| `Closed` | the close handshake is done or the connection failed |
| `Inflate` | a compressed message did not inflate (Close 1007 was sent) |
| `Entropy`, `AllocationFailed`, `Clock` | resource failures |

## Sample

[`ws_cat`](../sample_programs/library/ws_cat.lani) connects to one URL and
runs a script from stdin:

```text
ws-cat [--cacert FILE] [--protocol LIST] [-H 'Name: value']... [--timeout MS]
       [--max-message N] [--deflate|--deflate-no-context] URL < SCRIPT
```

Script lines are `send text|binary DATA`, `gen text|binary N`,
`frag text|binary K DATA`, `fragping K DATA` (K text fragments with a Ping
between each), `ping DATA`, `recv [MS]` and `close [CODE [REASON]]`. DATA uses
`\xHH` and `\\` escapes. The output starts with `open secure=S protocol=P` (plus ` deflate=1` when
permessage-deflate was negotiated),
then one line per received message (`KIND LENGTH FNV1A32 DATA`, with DATA
only up to 200 bytes), `close CODE REASON` for a peer Close, `closed CODE`
after `close`, `timeout` for a receive that timed out, and `error NAME` (exit
status 1) on failure.

## Executed evidence

`tests/extended_websocket_client_execution.rs` compiles `ws_cat` with
`libssl` and `libcrypto` and runs
[`oracle.py`](../tests/fixtures/extended/websocket_client/oracle.py). The
host has no `websockets` package, so the server is a minimal RFC 6455 echo
server on Python asyncio (standard library only): plain, and TLS with a test
root and server certificate generated per run with the `openssl` CLI. Its
permessage-deflate side is Python's `zlib` (raw DEFLATE, `Z_SYNC_FLUSH`),
with a fresh compressor or decompressor per message for a side without
context takeover, so a client that kept its context fails to inflate. Query
flags on the URL choose the server's extension response. Each case checks
the client's exact output and exit status and what the server saw. Every
client frame must be masked, with RSV1 only on the first frame of a
compressed data message, mask keys must not repeat, lengths must use the
shortest encoding, and the server checks fragment and opcode sequences,
compressed sizes, close codes and handshake fields.

| Group | Cases | Covers |
| --- | --- | --- |
| ws | 50 | text, binary and empty messages; 1 MiB and 70,000-byte messages; lengths 0, 1, 125, 126, 127, 65,535, 65,536 and 65,537 both ways with their 7/16/64-bit encodings; fragmented sends; Pings between fragments; received fragments with an interleaved Ping; a code point split across fragments; server Ping answered; client Ping; server-initiated Close 1001 and 3000 with a UTF-8 reason; client Close 4000 with a reason; Close without a code; a frame in the same read as the 101; subprotocol selection; Origin and Authorization fields; receive timeout then reuse; failures with the server's view of the client's Close: masked server frame, fragmented Ping and Pong, 126-byte Ping, continuation first, new message inside a fragmented one, opcodes 3 and 11, a non-minimal length, RSV bits (all 1002), Close codes 1005 and 999 and a one-byte Close (1002), invalid UTF-8 in a Close reason, in a first fragment before the message ends and across a fragment boundary (1007), oversized message (1009); refused before sending: Close codes 1005, 1006, 1015 and 999, a 124-byte reason, a non-UTF-8 reason, a 126-byte Ping, invalid UTF-8 text, an oversized message; EOF without Close; 403 rejection; wrong Accept; unoffered protocol; URL fragment; http scheme |
| wss | 52 | the same 50 over TLS, plus an untrusted certificate and the `localhost` DNS identity with SNI |
| deflate | 21 | negotiation and RSV1 use; context takeover both ways (a repeated 256-byte message shrinks to under a quarter both ways); `client_no_context_takeover` from the server (its fresh inflater accepts every message); `server_no_context_takeover`; the no-context offer; a no-context offer answered without `server_no_context_takeover` (handshake error); `client_max_window_bits=10` (sent uncompressed); `server_max_window_bits=10`; 1 MiB, 70,000, 100,001, 3, 0, 50,000 and twice 256 bytes through one context (the encoder's window slides after unaligned flushes; the empty message is one byte); compressed fragments received; fragments sent uncompressed; Ping/Pong unchanged; a declined offer; an extension that was not offered and an unknown parameter (handshake errors); a 2 MB inflation over a 100,000-byte limit (1009); corrupt data (1007, `Inflate`); inflated invalid UTF-8 (1007); RSV1 on a continuation and on a Ping (1002); invalid text refused before compression |

```text
websocket-client-ws cases=50 frames=65
websocket-client-wss cases=52 frames=65
websocket-client-deflate cases=21 frames=49
```

All three groups take about 8 seconds together. `ext::ws_deflate` itself
also passes `deflate_oracle.py` against `zlib` (8 cases, including context
takeover for both roles across 64 KiB window slides), and the server side
(`ws_echo_server`) still passes its 86-case oracle with the new encoder.

## Limits of this version

- No redirects of the opening request, no proxies and no cookies.
- Fragmented sends are never compressed, and the compressor cannot use a
  window under 15 bits, so a server that limits it gets uncompressed
  messages.
- Synchronous: one operation at a time, with no background Ping handling;
  Pings are answered when `receive` reads them.
- A message is buffered whole, up to `wire.message_bytes` (after
  inflation for compressed messages).
