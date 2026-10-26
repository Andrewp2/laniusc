# Raw native TLS duplex fixtures

The consumer imports `ext::openssl_tls`, links the real OpenSSL 3 libraries,
and executes as a Linux x86_64 native ELF. The Rust driver validates the linked
ELF before execution. Python's `ssl.MemoryBIO` supplies independent native
OpenSSL peers; the existing certificate generator supplies ephemeral fixtures.
No test implements TLS records or cryptography.

## Evidence boundaries

The `causal` group withholds every response until the complete request arrives.
The consumer first receives a real read `WantRead`, retains that read request,
then writes the request. Passing requires progress without waiting for the
readable event that the peer deliberately cannot produce yet. TLS 1.2 and
TLS 1.3, with and without ciphertext fragmentation, are separate cases.

The `notification` group uses TLS 1.3. The peer authenticates the client's
`close_notify` before sending a binary body. The consumer must retain that
application data and reach authenticated EOF. Repeated `shutdown_write` calls
after confirmed `Sent` must perform no native shutdown call. This is a raw TLS
contract; it does not define an HTTP request-body cancellation policy for
TLS 1.2.

The `rare-wants` group **injects** one write `WANT_READ` or read `WANT_WRITE`.
These controls test uncommon wrapper states and opposite-direction progress;
they do not establish that this local network naturally produces those states.
The subsequent successful reads and writes go through native OpenSSL. A
pending write's original caller buffer is changed before retry; the observer
checks the owned native pointer, bytes, length, and count cell across retries.
The observer never manufactures a positive write result or byte count.

Each initial case also exercises failed `SSL_CTX_up_ref`, two successful
retains, closed-owner rejection, and a session whose original and retained
context owners are all destroyed before handshake. Native session references
must keep the context alive. TLS cleanup must leave the caller-owned socket
open until its explicit close.

## Observer ownership

`observer.h` is the test-only ABI, also available for read-only reuse by the
HTTPS batch fixture. Each SSL has its own ordinal, forced error, operation
counters, pending buffers, lengths, byte copy and count pointers. Session
ordinals start at zero. `duplex_test_arm_next` transfers its one future control
into the next successful SSL allocation; it does not retain shared retry state.

Stable write checking is always enabled. Strict read staging checking is
optional: a native observer cannot see a wrapper-only `quiesce_read`. The raw
consumer enables strict checking and clears its observer reservation only after
the public quiesce operation succeeds. An adapter that quiesces internally
leaves strict checking disabled. Its read state must be tested through its own
public contract.

`resources.py` classifies exact emitted mmap/munmap instruction sites through
the existing ELF allocation-site recognizer. Loader, CRT, libc and OpenSSL
mappings are outside the source allocation ledger. Source releases must match
one live owner, length, generated release site and successful return; repeated
or unowned low-address releases fail the ledger. CPU mutation controls test
the classifier without running the product.

## Additional runtime states

`edges.lani` and `edge_oracle.py` keep the additional groups separate from the
initial consumer. Each group covers TLS 1.2 and TLS 1.3:

- `backpressure`: the peer withholds application reads until a real native
  write `WANT_WRITE`. While it is pending, reads and replacement writes must
  fail without native I/O. The caller changes its original input; retries must
  use the same owned native pointer, length, count cell and byte sequence.
- `buffered`: the peer sends one native application record and withholds all
  further output. A 32-byte read leaves 992 bytes in `SSL_pending`; a zero-time
  socket probe must have no readable event. Further immediate reads must drain
  the buffered plaintext before the peer sends its close alert.
- `owners`: two SSL owners stage distinct requests, with one explicitly
  injected write `WANT_READ` each. The second owner's retry and peer
  acknowledgement precede the first owner's retry. Both original inputs are
  changed, and the observer validates each owner's stable native arguments.
- `failures`: explicitly injected fatal read, write and shutdown results retain
  the exact operation phase and native diagnostic, destroy the SSL owner and
  clear reservations. A separate real cut-record transport EOF must report
  truncation without delivering unauthenticated plaintext. The borrowed socket
  remains live until its caller closes it.
- `shutdown`: full `shutdown()` retries explicitly injected `WANT_READ` and
  `WANT_WRITE`. A separate case reaches a real `WANT_READ` after local `Sent`,
  while the peer withholds its alert. Calls continue to bidirectional
  completion; they do not substitute local notification success for it.

`allocations.lani` exercises a finite constructor lifecycle without TLS I/O.
The campaign targets all five reached source allocations: trust-path staging,
identity staging, read storage, write storage and independent count cells.
Every injection binds the actual mmap ordinal, generated instruction site and
requested size to its baseline prefix. Successful source releases and the
native context/session ledger must balance before process exit. Native loader,
libc and OpenSSL allocations are outside this source ownership claim.

## Execution status

On Linux x86_64 with native OpenSSL 3, the parent's serialized runtime gates
accepted these current-source groups on 2026-10-26:

| Receipt under `target/stdlib-work/` | Result | Scope |
| --- | --- | --- |
| `openssl-tls-duplex-initial-groups-first.log` | exit 0; 3 groups; 6.43 s | causal 4, notification 2, injected rare WANT controls 4 |
| `openssl-tls-duplex-five-edge-groups-first.log` | exit 0; 5 groups; 6.20 s | full shutdown 6, fatal/truncation 8, buffered plaintext 2, real backpressure 2, two owners 2 |

| `openssl-tls-duplex-source-allocations-first.log` | exit 0; 1 group; 7.36 s | baseline plus five reached source-allocation failures; nine ledger controls |

These are 36 executed cases across all nine current groups. Legacy profile
regressions remain pending. CPU checks pass for C syntax, Python
syntax, exact literal/explicit array lengths, Rust formatting, and nine
source-ledger mutation controls. No GPU execution target is claimed: the GPU
compiler generates each native linked x86_64 consumer, which then executes
against the host OpenSSL libraries.

The driver is `tests/extended_openssl_tls_duplex_execution.rs`. The six additive
test filters are frozen while their acceptance receipts are collected:

```text
real_write_backpressure_exclusively_retries_owned_bytes_and_native_arguments
one_native_record_drains_buffered_plaintext_without_fd_readiness
two_ssl_owners_preserve_distinct_staged_writes_across_reverse_retries
native_read_write_shutdown_failures_and_real_truncation_release_owners
full_shutdown_retries_real_and_injected_wants_until_bidirectional_completion
every_reached_tls_source_staging_allocation_failure_releases_native_and_source_owners
```

Use `cargo test --locked --test extended_openssl_tls_duplex_execution --no-run`
to build the driver, then run an exact filter with `--nocapture --test-threads=1`
under the repository's serialized GPU gate. Each shell command must remain
under two minutes. The allocation campaign has its own linked consumer and can
be accepted separately from the five edge groups.
