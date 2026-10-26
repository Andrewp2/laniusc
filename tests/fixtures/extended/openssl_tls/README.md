# Native OpenSSL TLS execution fixtures

These fixtures test `ext::openssl_tls` through the native C profile. Production
TLS, certificate verification and record protection execute in OpenSSL. Python
`ssl` is an independent test peer backed by its own OpenSSL connection state.
The OpenSSL CLI generates all ephemeral keys and signs all test certificates.
No key material is committed.

The test plan covers explicit CA trust, DNS/IP reference identities, separate
DNS SNI, certificate expiry and chain/purpose failures, protocol floors,
nonblocking retry states, byte layout/staging, authenticated close versus
unexpected EOF, shutdown and explicit handle cleanup. All connections use
loopback addresses; each child, server wait and caller operation loop has a
finite limit. Certificate generation and peer self-checks can run on the CPU;
the root agent serializes compiler and GPU execution gates.

The policy follows the OpenSSL 3.0 contracts:

- [Peer verification](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0/doc/man3/SSL_CTX_set_verify.pod)
  requires explicit `SSL_VERIFY_PEER`; defaults do not reject an untrusted peer.
- [Reference identity checks](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0/doc/man3/SSL_set1_host.pod)
  require a nonempty expected identity. SNI alone supplies no verification.
- [I/O errors](https://docs.openssl.org/3.0/man3/SSL_get_error/) require immediate
  same-thread classification after the operation and a previously clear error
  queue. Either I/O direction can need read or write readiness. OpenSSL 3
  treats transport EOF without `close_notify` as a fatal TLS error.
- [Write retries](https://docs.openssl.org/3.0/man3/SSL_write/) retain the same
  arguments and staged bytes while pending.
- [Shutdown](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0/doc/man3/SSL_shutdown.pod)
  distinguishes sent-but-incomplete from complete; a zero return does not call
  `SSL_get_error`. Fatal TLS errors prohibit further shutdown I/O.

Execution claims await the actual library and native gates. A successful peer
self-check alone establishes the fixture behavior, not the Lanius wrapper.
