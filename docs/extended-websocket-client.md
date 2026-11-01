# WebSocket client

`ext::websocket_client` is a synchronous RFC 6455 client for `ws://` and
`wss://` URLs. It connects through the
[HTTP agent's connection layer](extended-http-agent.md#connections-for-upgrades),
so resolution, ordered connect attempts and verified TLS behave as they do
for `http://` and `https://`. The opening handshake, frame parsing and
encoding, fragmented messages, UTF-8 checks and close-code rules are the
existing [`ext::websocket`](extended-websocket.md) frame code, which the
servers also use, run with `Role::Client`. The Accept value is computed by
[`ext::openssl_websocket`](extended-openssl-websocket.md). Programs link
`libssl` and `libcrypto` and must ignore SIGPIPE.

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
`Connection` list with `Upgrade`, the right `Sec-WebSocket-Accept`, no
extensions, and at most one selected protocol that was offered. Otherwise
`Handshake(error)`. Frame bytes that arrive with the head are kept.
`protocol()` returns the selected protocol.

## Frames and messages

Every outgoing frame is masked with a fresh four-byte key. Keys come from a
256-byte pool refilled from the OS random source, so the pool is read once
per 64 frames. `send_text` and `send_binary` send one frame each.
`send_fragment` sends one fragment: opcode 1 or 2 starts a message, 0
continues it, and `fin` ends it; Pings and Pongs may go between fragments.
The frame code enforces message state, text UTF-8 and the 125-byte control
limit before anything is sent.

`receive(timeout_ms)` returns the next complete message, Ping, Pong or
Close. Fragments are assembled, and Pings and Pongs between them are
returned in arrival order. A Ping is answered with a Pong carrying the same
payload before it is returned. `Message.data` borrows the client's storage
until the next `receive` or `destroy`. A timeout returns `Timeout` and
leaves the client usable, over TLS too: TLS reads are attempted without
blocking and the socket is polled, so a quiet connection does not abort the
TLS stream.

If the server breaks the protocol, the client fails the connection as
section 7.1.7 asks. It sends Close 1007 for invalid UTF-8 text, 1009 for a
frame or message over the limits, and 1002 for anything else: unmasked
framing violations such as a masked server frame, reserved bits, bad
opcodes, bad control frames or bad close payloads. It then closes the
transport and returns `Wire(error)`. EOF without a Close returns `Eof`.

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
| `Entropy`, `AllocationFailed`, `Clock` | resource failures |

## Sample

[`ws_cat`](../sample_programs/library/ws_cat.lani) connects to one URL and
runs a script from stdin:

```text
ws-cat [--cacert FILE] [--protocol LIST] [-H 'Name: value']... [--timeout MS]
       [--max-message N] URL < SCRIPT
```

Script lines are `send text|binary DATA`, `gen text|binary N`,
`frag text|binary K DATA`, `fragping K DATA` (K text fragments with a Ping
between each), `ping DATA`, `recv [MS]` and `close [CODE [REASON]]`. DATA uses
`\xHH` and `\\` escapes. The output starts with `open secure=S protocol=P`,
then one line per received message (`KIND LENGTH FNV1A32 DATA`, with DATA
only up to 200 bytes), `close CODE REASON` for a peer Close, `closed CODE`
after `close`, `timeout` for a receive that timed out, and `error NAME` (exit
status 1) on failure.

## Executed evidence

`tests/extended_websocket_client_execution.rs` compiles `ws_cat` with
`libssl` and `libcrypto` and runs
[`oracle.py`](../tests/fixtures/extended/websocket_client/oracle.py). The
host has no `websockets` package, so the server is a minimal RFC 6455
implementation on Python asyncio: plain, and TLS with a test root and server
certificate generated per run with the `openssl` CLI. Each case checks the
client's exact output and exit status and what the server saw. Every client
frame must be masked with RSV bits clear, mask keys must not repeat, and the
server checks fragment and opcode sequences, close codes and handshake
fields.

| Group | Cases | Covers |
| --- | --- | --- |
| ws | 24 | text, binary and empty messages; 1 MiB and 70,000-byte messages; fragmented sends; Pings between fragments; received fragments with an interleaved Ping; server Ping answered; client Ping; server-initiated Close 1001; Close without a code; a frame in the same read as the 101; subprotocol selection; Origin and Authorization fields; receive timeout then reuse; masked server frame (1002); invalid UTF-8 (1007); RSV bits (1002); oversized message (1009); oversized send refused; EOF without Close; 403 rejection; wrong Accept; unoffered protocol; URL fragment; http scheme |
| wss | 26 | the same 24 over TLS, plus an untrusted certificate and the `localhost` DNS identity with SNI |

```text
websocket-client-ws cases=24 frames=38
websocket-client-wss cases=26 frames=38
```

Both groups take about 3 seconds together.

## Limits of this version

- No extensions (permessage-deflate is refused by the frame code), no
  redirects of the opening request, no proxies and no cookies.
- Synchronous: one operation at a time, with no background Ping handling;
  Pings are answered when `receive` reads them.
- A message is buffered whole, up to `wire.message_bytes`.
