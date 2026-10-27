# Connected socket adoption

Status: the public UDP-rejection smoke, connected HTTP case and eight focused
rejection/cleanup cases are accepted on native Linux x86-64. TLS adoption is
outside this fixture's current scope.

## Direct runtime acceptance

The frozen probe compiled and both direct oracle groups passed on their first
root attempts. Logs are under `target/stdlib-work/`:

| Receipt | Accepted scope |
| --- | --- |
| `url-adoption-probe-compile-first.log` | Compile exit 0, empty diagnostic log |
| `url-adoption-connected-first.log` | 1 real HTTP case, same fd generation, pre-exit zero owners |
| `url-adoption-failures-first.log` | 8 cases, 1 reached close EIO, all 8 pre-exit zero-owner barriers |

Exact SHA-256 identities:

```text
HTTP   1eb1991348a79ae1ba22f822eeb5cc98d6f2da06ff16a3e2cf44f5d0abe91612
probe  611a6c270671dc796b8a4ebfa65452cda7860a45ceaf2ad8bc849239198a8c74
oracle 152789cfb57f5dba5e8d36377705dadbedfa3b63e463f023f05711e28c13b6e5
ledger d12f36129e9647e98c8991ac34f517b88d2899182b77c608acd5d5caa8e12e32
driver 5539e7d127909f9f2842bdfc0fe054577b1d428845540df8c45675611dca3a83
ELF    addec849ff3ac9b43424ef70e69eec9dbba64cd3142e3070a252d4b967c6bb2c
```

These are direct compiler/native/Python receipts, not passing registered Rust
runtime tests. The accepted scope is plain HTTP adoption; it establishes no
TLS adoption, native-linked resolver or GPU-kernel execution behavior.

## Public admission receipt

On HTTP source `1eb1991348a79ae1ba22f822eeb5cc98d6f2da06ff16a3e2cf44f5d0abe91612`,
`public_smoke.lani` (`3816d4b421b8eeb4b233f0da975b4ef54dfa229e21eb537f70d9fc969574b7db`)
compiled and executed on its first root attempt:

- `target/stdlib-work/url-adoption-public-compile-first.log`: compile exit 0.
- `target/stdlib-work/url-adoption-public-native-first.{trace,log}`: native exit
  0, empty output, full syscall observation.
- Emitted ELF SHA-256:
  `11edbb9a187f12c7ae948c44d52914b8863d451b01bb36c44145862289579d56`.

This is direct public API admission and UDP rejection/owner-consumption
behavior. It does not establish connected positive behavior, the full strict
owner campaign, TLS behavior or passing registered Rust tests. The GPU compiler
emits a native Linux x86-64 program executed on CPU; no GPU kernel execution
is claimed.

## Focused behavior

`probe.lani` uses actual `http_client::Prepared`, `Socket.take_handle` through
the production adopter and the canonical `Exchange.run` engine. A real TCP
socket is created and connected in the native child before adoption. No
connected fd is inherited by strace. The independent loopback peer checks
HTTP method, target, authority, framing and binary body through h11, then
supplies a binary HTTP response.

- `success`: one connected nonblocking TCP socket. Its same fd generation must
  reach actual request/response I/O. Adoption cannot open, connect, send,
  receive or poll. No extra listener connection is accepted.
- `failures`: unconnected TCP, already-closed socket, connected blocking TCP,
  UDP metadata, inactive Prepared, expired original deadline and one-call
  adoption I/O quota. Assert exact typed cause/stage/native detail/counters,
  both inputs inactive and explicit cleanup before exit.
- The eighth failure case injects EIO at the baseline-bound unconnected
  socket close. Primary ENOTCONN must remain primary and EIO secondary. The
  injected syscall does not physically close: the fixture exposes that live
  descriptor at its checkpoint, then performs one explicitly marked test-only
  raw repair. Library tokens stay retired and library close is never retried.

Three stdout/ACK checkpoints bind observed metadata and resources before
adoption, after adoption and before final exit. A successful adoption retains
its Prepared allocations under the Exchange; failed adoption releases them.
Final source/native fd owners must be zero while the process is still blocked
on the host ACK, not merely after process teardown. Terminal replay runs in an
empty native-work epoch and cannot reopen/reconnect or republish a response.

`ledger.py` observes every syscall, admits only raw-image syscall sites, tracks
socket fd generations, separates skipped-close physical ownership from logical
retirement, and binds the close injection to its actual IP/ordinal/fd/generation
and causal call prefix. The raw ELF scanner and full-width source allocation
authority are reused unchanged from TempFile through `archive_source/ledger.py`.
Both admitted mmap flags 0x22/0x62 retain their verified source identities;
there is no MAP_32BIT-only or whole-process-map ownership shortcut. No new
compiler, native glue or protocol implementation is introduced.

CPU-only `python3 -B oracle.py --self-test` currently passes 11 synthetic fd/
phase/causal-prefix ledger controls; Python AST and diff checks pass. These
controls start no native child/compiler and do not establish runtime behavior.

## Reproduction commands

Use root's usual outer command bound below 100 seconds:

```sh
cargo test --test extended_url_adoption_execution public_adoption_consumes_udp_socket_and_prepared_on_rejection -- --exact --nocapture
cargo test --test extended_url_adoption_execution connected_socket_generation_reaches_real_http_wire_without_reconnect -- --exact --nocapture
cargo test --test extended_url_adoption_execution invalid_socket_prepared_deadline_and_cleanup_failures_retire_both_inputs -- --exact --nocapture
```

The actual probe ELF can be reused without recompilation through
`python3 -B oracle.py PROBE_ELF success` or `... PROBE_ELF failures`.
The Rust writer uses the shared complete function-jump ELF validator.
Failure diagnostics remain in the printed temporary evidence directory.
Preserve accepted counts, source/ELF identities and failed-attempt
classifications with any later runtime results.
