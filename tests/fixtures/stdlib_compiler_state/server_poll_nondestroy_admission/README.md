# Concrete server helpers without an error destructor bound

This focused control calls the actual plain and TLS `serve_until` facades with
`max_accepted = 0` and a custom `ManualError` that has no `Destroy`
implementation. Both return their actual typed empty reports. No handler is
called, descriptor accepted or poll attempted; the caller's real nonblocking
listener and OpenSSL ServerContext remain open throughout both calls.

The control checks all empty-service counters and initially empty report
capacity. It then reserves actual capacity in each report's public outcomes
Vec, checks that it still contains no elements, and releases that storage
through `Vec.destroy`, twice. This explicitly frees owned storage without
requiring an element destructor or inventing one for `ManualError`. The
listener, context and argument snapshot are released before return.

Compile `main.lani` with `--stdlib-root stdlib --source-root extended` and native
`ssl`/`crypto` libraries. Run the resulting executable with certificate-chain
and private-key file paths as its two arguments. The credentials must be
compatible, unencrypted PEM files; test infrastructure creates them through
OpenSSL. Expected output is empty stdout/stderr and exit zero.

`tests/extended_server_poll_nondestroy_execution.rs` provides this bounded gate.
Its certificate setup and executable linking are test infrastructure, not
library implementations. This checks generic admission and the empty-service
runtime path, not HTTP transfer, TLS handshake, nonempty error cleanup or
concurrency. The combined fixture links OpenSSL because it imports the TLS
facade; the production plain facade has no TLS dependency.

The root's bounded compile/native gate passes in 21.84 seconds:
`target/stdlib-work/server-poll-nondestroy-runtime-first.log`, exit zero with
empty stdout/stderr. The retained native executable is
`/tmp/server_poll_nondestroy_native_234768_0`. This accepts both concrete empty
helpers with no application-error destructor bound and the explicit cleanup
above; it does not extend the scope to nonempty error disposal or TLS transfer.
