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

## Execution status

The first source checkpoint is ready for the parent's serialized native gate.
No native execution result is claimed here yet. CPU checks cover C syntax,
Python syntax, exact source literal byte lengths, Rust formatting, and nine
source-ledger controls. Further real backpressure, buffered plaintext,
multiple-session, fatal and allocation cases remain under construction.
