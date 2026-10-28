# Borrowed WebSocket server handshake contracts

The pure `contracts.lani` producer drives `websocket_upgrade::Server<T>` through
a deterministic Lanius `Read`/`Write` transport. It imports no sockets, TLS,
clocks, entropy or native crypto. Provider Accept values are fixed RFC example
data; this fixture does not implement a cryptographic algorithm.

Six top-level scenario functions exercise finite states and fault/quota loops:

- No-trait construction/destruction; invalid limits and retryable/inactive state
  errors without transport calls.
- Stable copied request metadata; policy pauses with no writes; independent
  staged response bytes survive mutation of caller fields, Accept and protocol.
- Short writes, Interrupted, WouldBlock and blocked inner flush never replay
  accepted prefixes. Ready is published only after flush. Conversion is
  transactional and creates the server frame role over the same borrowed inner.
- One-byte request reads with a 512-work cursor cap; offered protocol and
  reserved-field checks remain retryable with no output.
- Response caps immediately below/at the selected response length; policy can
  retry with a smaller no-protocol response after cap rejection.
- Malformed/truncated requests, captured trailing bytes, read/work/call caps,
  invalid I/O counts, WriteZero and Host(55) failures are typed and sticky.
  Saved counters and completed phase prefixes survive replay with no more I/O.

## Executable acceptance

On Linux x86_64, the complete producer compiled successfully and ran to exit
zero with empty stdout/stderr on its first admission. All **six top-level
scenario functions** ran in one process, including the finite fault/quota loops.
These are direct executable receipts, not six separate process runs or a Rust
libtest runtime result.

Local logs under `target/stdlib-work/`:

- `websocket-server-contracts-compile-first.log`: compile exit 0.
- `websocket-server-contracts-native-first.log`: raw executable exit 0.
- `websocket-server-driver-build-first.log`: the server and echo Rust integration
  drivers built successfully with `--no-run` in 2.18 seconds. This checks
  registration and types; no Rust libtest runtime was executed.

Accepted SHA256 values:

| Artifact | SHA256 |
| --- | --- |
| `contracts.lani` | `44292f1171d1f68bf2925d5b907cfd75e6f6301e98da1badaf57a382994b1fc1` |
| `websocket_upgrade.lani` | `cae295960cc78dee04a097f2a67febc0c46ea4ca4fa1de5b4a8d191b5034b5d1` |
| Shared `http.lani` | `5d49571691ee7f01adc7a782842a59825276b5f012febba249b8f0702ef08591` |
| Raw executable | `79996579684d80b3625fd2391e4ef642b759b91dd0d2e02eec059f9d5fe30902` |

The Rust registration emits and runs a raw x86_64 executable without native
linking. Its build-only receipt is separate from direct executable acceptance.
No allocation-failure injection, actual connected
server, user-program GPU behavior or formal ownership proof is claimed by this
fixture. Its response cap scenarios exercise the current shared HTTP encoder;
they do not establish all shared encoder size-arithmetic cases.
