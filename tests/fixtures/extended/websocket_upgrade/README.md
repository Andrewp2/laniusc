# WebSocket upgrade execution fixtures

These fixtures cover the HTTP upgrade wire boundary. They do not implement or
claim a connected WebSocket client/server transport.

- `contracts.lani` executes response validation and encoding against the public
  `ext::websocket` API. It includes the RFC accept value, protocol selection,
  mixed case and OWS, repeated Connection fields, trailing first-frame handoff,
  both native negative-stride and packed byte layouts, 34 malformed response
  cases, bounds/caps, caller-header rejection and round trips.
- `accept_probe.lani` batches calls to `ext::openssl_websocket::accept_into`.
  Its test-only protocol is documented at the start of the source. The input
  nonce/key and output buffers use nonzero offsets, both stride layouts and
  overlapping storage. Failure output must remain unchanged.
- `oracle.py` compares 310 cases with CPython `_sha1` and Base64. Positive cases
  execute real OpenSSL, including the RFC sample and deterministic nonces
  covering every byte value. Twenty-four optional injected cases check provider
  failure, unexpected digest sizes (including full-width `0x100000014`), early
  key/capacity errors and atomic output.
- `fault_interposer.c` only injects errors in `EVP_Q_digest`; ordinary calls
  delegate to the real OpenSSL symbol. It contains no digest implementation.

The Rust driver is `tests/extended_websocket_upgrade_execution.rs`. It compiles
one freestanding pure contract program and one native-linked OpenSSL program.
## Accepted execution receipts

The following focused executions passed on Linux x86_64:

- Pure contracts source `9aa3dcb0` compiled successfully and its freestanding
  executable `939ed1f2fa23edf065a8373eeba9f7790f78e58049b9f63f656f071c4e51b54d`
  exited zero with empty output. The receipts are
  `target/stdlib-work/websocket-upgrade-contracts-compile-first.log`,
  `websocket-upgrade-contracts-native-first.log` and
  `websocket-upgrade-contracts-native-first.trace` in the same directory.
- Native accept probe source `3781b81a`, OpenSSL helper `2c0baac5`, oracle
  `8f6b7b6e` and shim `fd9c3912` passed 310 differential/guard cases and 24
  injected failure cases. Both byte layouts and overlap were exercised. The
  full-width unexpected-size value `0x100000014` was preserved and failed calls
  left caller storage unchanged. The workload used four native processes: one
  ordinary batch and three injected batches. The executable hash is
  `d321f8982056572733564cdc8d9d723eb2f8ef50077986a99fb303cf2024559d`;
  `target/stdlib-work/websocket-upgrade-accept-native-first.log` records both
  passing summaries. Its compile receipt is
  `target/stdlib-work/websocket-upgrade-accept-compile-first.log`.
- The upgrade and companion application Rust integration drivers built with
  `--no-run` in 2.09 seconds. The receipt is
  `target/stdlib-work/websocket-upgrade-driver-build-first.log`. This is a driver
  build receipt; the executable behavior above was checked through direct runs.

These are finite wire/parser, digest integration and atomic-output checks. They
make no allocation-failure coverage, connected transport or exhaustive resource
cleanup claim.

Direct native comparison after compiling `accept_probe.lani` with `--native-link
--native-library crypto`:

```sh
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC \
  tests/fixtures/extended/websocket_upgrade/fault_interposer.c \
  -o target/stdlib-work/websocket-upgrade-fault.so -ldl -lcrypto
python3 -B tests/fixtures/extended/websocket_upgrade/oracle.py \
  target/stdlib-work/websocket-upgrade-accept.elf \
  --shim target/stdlib-work/websocket-upgrade-fault.so
```

Host execution support is Linux x86_64 with OpenSSL 3 for the native accept
producer. The pure API does not require OpenSSL. These tests establish no GPU
runtime behavior or formal proof.
