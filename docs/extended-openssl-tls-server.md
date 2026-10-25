# OpenSSL server TLS with explicit credentials

`ext::openssl_tls` adds a distinct `ServerContext` to the existing
[client TLS module](extended-openssl-tls.md). OpenSSL performs all credential
decoding, handshakes, encryption, record handling and shutdown. Server and
client sessions share the same stable buffers, nonblocking progress methods,
error capture and close/truncation state machine.

The implementation targets the [Linux x86_64/glibc native C profile](library-native-c.md)
with OpenSSL 3 `libssl` and `libcrypto`; the locally reviewed installation is
3.0.13. On 2026-10-25, all six native server groups passed 53 bounded
invocations in 5.98 seconds. The existing client verification regression also
passed all nine rejection cases after the role changes. These receipts cover
the native profile above; other targets and the broader security family
remain separate work.

## Server credentials and client authentication

```lanius
ext::openssl_tls::new_server(
    certificate_chain: core::slice::View<u8>,
    private_key: core::slice::View<u8>,
    passphrase: core::slice::View<u8>,
    client_authentication: ext::openssl_tls::ClientAuthentication,
    limits: ext::openssl_tls::Limits
) -> Result<ext::openssl_tls::ServerContext,ext::openssl_tls::Error>
```

Choose `ClientAuthentication::Unauthenticated` for a public server that does
not request a client certificate. Choose `Required(Trust)` to require a client
certificate verified against the supplied trust policy. The
[mutual-TLS guide](extended-openssl-mutual-tls.md) records its fresh-authentication
policy, exact native checks and separate execution receipts. Application
identity and authorization remain explicit application decisions. Optional
client certificates are not implemented. The client `Context` always requires
trust, DNS/IP identity verification and a peer certificate.

Supply a PEM certificate-chain path and PEM private-key path. The chain file
starts with the server leaf certificate followed by its intermediate issuers.
Provision the chain, key, file access and intended server identity explicitly.
Loading credentials and checking their key match does not establish a
client's trust decision, certificate validity period or reference-name match.
The connecting client must enforce those checks.

Both paths must be nonempty UTF-8 byte views without NUL and no longer than
`limits.path_bytes`. The wrapper validates limits, then the certificate path,
key path and passphrase, before any staging allocation or native credential
load. View metadata must be in range; the caller must physically back the
views and keep them readable during the factory call.

The passphrase is an explicit byte view, with length
`0..MAX_PASSPHRASE_BYTES` inclusive; the constant is 1,023. Bytes need not be
UTF-8 but cannot contain NUL. An empty view supplies an explicit empty
passphrase. It works with unencrypted keys and can also unlock a key encrypted
with an empty password; it does not mean every encrypted key must be rejected.
There is no implicit environment, terminal, stdin or password-prompt fallback.

The wrapper allocates terminated copies of both paths and the passphrase,
including a non-null one-byte copy for an empty passphrase. Before either PEM
file is loaded, it sets a null password callback and the non-null staged
passphrase as OpenSSL userdata. OpenSSL's documented PEM convention consumes
that string directly, avoiding its interactive default. The same setup covers
the unusual case of an encrypted PEM certificate. The 1,023-byte cap fits the
audited OpenSSL PEM password buffer without truncating the supplied string.
[OpenSSL's PEM argument contract](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0.13/doc/man3/PEM_read_bio_PrivateKey.pod)
and its [default callback implementation](https://raw.githubusercontent.com/openssl/openssl/openssl-3.0.13/crypto/pem/pem_lib.c)
define this behavior.

OpenSSL loads the chain, loads the private key and checks that the certificate
and key match. A mismatch can be reported while loading the key or by the
explicit consistency check. On success and every native failure path, the
wrapper detaches password userdata before wiping its complete staged password
with `OPENSSL_cleanse` and freeing staging. The context never retains a pointer
to released Lanius password storage. The caller still owns its original
passphrase bytes and must manage their lifetime and erasure. OpenSSL owns the
loaded native key; this wrapper neither exports key bytes nor implements PEM
decryption.

## Protocol policy and scope

Both roles use a fixed minimum of TLS 1.2, disable compression and
renegotiation, and explicitly clear `SSL_OP_IGNORE_UNEXPECTED_EOF`. OpenSSL's
configured algorithms, providers and other native policy otherwise apply.
The wrapper does not lower OpenSSL's security level. TLS versions below 1.2
are not admitted.

This server profile loads one credential pair per factory call. It offers no
SNI-based credential selection, application verification/password callbacks,
ALPN negotiation, optional client certificates, live credential mutation or
foreign-thread entry. Native OpenSSL configuration and session-resumption
behavior are not replaced by a custom TLS implementation. Broader server and
certificate-trust policy remains separate work.

The existing `Limits` shape is shared with client sessions. `path_bytes` bounds
each staged path and `io_bytes` bounds each stable session I/O buffer.
`identity_bytes` and `verify_depth` retain their existing validation ranges,
but `Unauthenticated` performs no client identity or certificate-chain
verification. `Required(Trust)` applies the configured verification depth and
native client-certificate purpose, with the separate policy described above.
The passphrase cap is separate and fixed.

These caps do not limit PEM file size, native credential parsing, handshake
memory/work or elapsed time in a native call. Credential loading can perform
ordinary filesystem I/O. The progress API does not impose a connection count,
total transfer quota or deadline; callers supply those policies.

## Context, session and descriptor ownership

`ServerContext` provides:

| Method | Contract |
| --- | --- |
| `borrow()` | Borrow the one active context owner |
| `is_open()` | Whether its native context reference remains live |
| `io_bytes()` | The exact configured staging cap for sessions and stream queues |
| `session(fd)` | Create a server `Session` for an already connected nonblocking socket |
| `destroy()` | Release this context reference and invalidate the actual owner; repeated calls do nothing |

The caller accepts connections, establishes an explicit SIGPIPE policy,
keeps the descriptor nonblocking and owns its eventual close. `session(fd)`
rejects a negative descriptor before native effects and rejects a destroyed
context. It creates SSL, allocates the shared reader/writer/count storage,
attaches OpenSSL's borrowed socket BIO and selects the native accept state.
It neither accepts from a listener nor changes descriptor flags.
[OpenSSL documents the client/server handshake roles](https://docs.openssl.org/3.0/man3/SSL_set_connect_state/).

`SSL_new` retains its native context reference. The caller may destroy the
`ServerContext` owner after session creation while that session continues.
The session does not borrow the Lanius context record or retain its password
staging. Credentials must be loaded before publishing the context; do not edit
context/session fields or use inactive shallow copies. The owners and their
operations are not concurrent or reentrant.

`session.role()` reports `Role::Server`; client factories report
`Role::Client`. Role is factory-selected state, not a supported way to alter
an existing session's policy. Calling `session.destroy()` abandons TLS, frees
SSL and cleanses stable I/O staging, while leaving the borrowed descriptor
open. The caller closes it afterward. Destruction does not implicitly perform
or promise graceful shutdown.

## Shared nonblocking progress and close policy

Server sessions use the existing methods and outcome enums:

| Method | Outcomes |
| --- | --- |
| `handshake()` | `Handshake::{Complete,WantRead,WantWrite}` |
| `read_into(output)` | `Read::{Data(count),Closed,WantRead,WantWrite}` |
| `write(input)` / `retry_write()` | `Write::{Complete(count),WantRead,WantWrite}` |
| `shutdown()` | `Shutdown::{Complete,Sent,WantRead,WantWrite}` |

Each progress operation makes at most one TLS I/O call. Poll according to the
returned WANT, including a write needing readability or a read needing
writability, under caller-controlled attempts and deadlines. A server
handshake uses `SSL_do_handshake` in accept state. A successful native handshake
opens this unauthenticated-client session without requiring a peer certificate.
Client-role handshakes still require both a successful verification result and
a peer certificate after their mandatory DNS/IP checks.

Read and write retries retain the original staging pointers and request
lengths. Pending writes retry only through `retry_write()`; caller bytes can
be released after the initial copy. Only one application operation may be
pending. Successful native counts are checked before copyout or completion.
See the [client guide's shared Session contract](extended-openssl-tls.md#read-and-write-retry-buffers)
for exact retry, empty-I/O and confirmed-progress rules.

`Read::Closed` means an authenticated TLS `close_notify` was received, not that
the client supplied an authenticated identity. The state becomes `PeerClosed`.
Transport EOF without that notification is `Cause::Truncated`. A fatal native
error makes the session `Failed` and releases its TLS resources; no shutdown
is attempted afterward.

`shutdown()` is available only without pending application I/O. Native return
zero means the local notification was sent (`Sent`), not that both directions
completed. Retry shutdown under readiness/deadline policy until `Complete`,
or explicitly abandon. Application I/O remains disabled while closing.
The shared [closure and error-ordering contract](extended-openssl-tls.md#eof-and-shutdown)
is unchanged.

## Error phases

The new phases are `Certificate`, `PrivateKey`, `Passphrase` and `KeyMatch`.
Existing `Context`, `Policy`, `Session`, `Attach`, `Handshake`, `Read`, `Write`
and `Shutdown` phases retain their roles. Local errors use existing causes:
`InvalidLimits`, `Bounds`, `Limit`, `Nul`, `Utf8` or `AllocationFailed`.
Passphrases have no UTF-8 requirement. Native credential failures use
`Cause::Native` and capture the first queued OpenSSL code before cleanup;
private-key mismatch may appear as `PrivateKey` or `KeyMatch`.

The shared I/O path clears the OpenSSL queue and errno before each operation,
captures errno immediately afterward, and calls `SSL_get_error` before any
other OpenSSL function on failure. Server-side failures do not relabel an
unauthenticated client's absence as certificate-verification failure.

Native credential behavior follows the official
[certificate/key loading and consistency contract](https://docs.openssl.org/3.0/man3/SSL_CTX_use_certificate/)
and [server verification modes](https://docs.openssl.org/3.0/man3/SSL_CTX_set_verify/).
No callback, compiler, IR, ABI or artifact-version extension is required.

## Native execution receipts

[`tests/extended_openssl_tls_server_execution.rs`](../tests/extended_openssl_tls_server_execution.rs)
compiles the production Lanius wrapper and
[server protocol fixture](../tests/fixtures/extended/openssl_tls_server/protocol.lani)
once per Rust test process. The linked ELF passes the dedicated native-link
validator and declares OpenSSL 3 `libssl` and `libcrypto` dependencies. A real
Python `ssl` client exchanges native TLS records over a connected nonblocking
socketpair. OpenSSL performs certificate verification, handshakes, encryption
and record construction on both sides. Private keys are generated at runtime;
no test key is stored in the repository.

| Group | Executed cases |
| --- | --- |
| Verified transfer | 10: binary lengths 0, 1, 255, 1,024, 1,025 and 16,385; stack, Vec and packed byte views with offsets; TLS 1.2 and 1.3; DNS and IP identity verification; complete intermediate chain with a client trusting only the root. Clients install no certificate. |
| Credentials | 14 invocations, including ten local validation assertions: unencrypted and explicitly encrypted keys; successful encrypted-key transfer; missing, malformed and directory paths; mismatched key; wrong and empty passphrases; invalid limits, view metadata, UTF-8, NUL and password length. |
| Verification and endings | 9: client rejection of wrong DNS, wrong IP and untrusted issuer; TLS 1.1 rejection; abrupt EOF after one or 1,025 plaintext bytes; a cut native-generated record with no plaintext copyout; local shutdown and received `close_notify` with an observed `PeerClosed` state. |
| Stable retries | 1: a 524,288-byte exchange forces native WANT_WRITE before the client reads and WANT_READ before it sends. The caller mutates original write bytes after WANT; the peer still receives the original bytes. Read retries change destination layout, retain request size and reject unrelated pending operations without another native I/O call. |
| Native faults | 12 injected boundaries: server method, context acquisition, minimum-version configuration, certificate load, key load, key-match check, SSL acquisition, descriptor attachment, handshake, read, write and shutdown. Each preserves the diagnostic phase and releases acquired context/session owners. |
| Staging allocation | 7 runs: one baseline and all six reached allocation failures across terminated certificate path, key path, empty password, reader, writer and count storage. Each failure reports the expected local phase and balances every successful staged mapping by exact address and requested length. |

Exchange fixtures destroy their `ServerContext` owner before every handshake,
exercising OpenSSL's retained native reference.
Native observers require zero escaped context/session owners and no duplicate
release. Each invocation verifies that Session cleanup or constructor failure
leaves the borrowed descriptor live, then explicitly closes it once. Dirty
error queues precede TLS progress calls. Read failure and WANT paths preserve
output guards, and fatal failures complete without a subsequent shutdown attempt.

Credential invocations hold stdin open without sending bytes. Before either
native PEM loader runs, the observer requires a null password callback and
non-null password userdata, including for an empty passphrase. At `SSL_new`
and external `SSL_CTX_free`, it requires that userdata has been cleared. These
checks exercise the mechanism that prevents both prompting and retained
pointers into released staging, independently of terminal availability.

The native observer delegates successful calls to OpenSSL; its injected errors
exercise wrapper cleanup rather than replace TLS. The mapping ledger covers
Lanius staging allocations, not every allocation inside OpenSSL. The cases are
finite evidence for the stated paths, rather than exhaustive TLS or credential
format coverage. They do not establish mutual TLS, listener/service behavior,
other OpenSSL releases, other native targets, Wasm, or GPU execution of user
programs. Each progress sequence uses a five-second polling deadline and a
finite step bound; subprocess and compiler gates have outer timeouts.

The durable server gate passed 6/6 with all 53 invocations in 5.98 seconds:
`target/stdlib-work/openssl-tls-server-native-current.log`. After the shared
Session role change, the existing client negative gate passed 1/1 with nine
trust, identity, certificate-validity/purpose/chain and legacy-protocol
rejections in 5.98 seconds:
`target/stdlib-work/openssl-tls-client-policy-server-regression.log`.
That regression independently retains mandatory client authentication of the
server.

The focused server gate, after the required compiler build, is:

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_openssl_tls_server_execution -- --nocapture --test-threads=1
```
