# URL connector boundary tests

Status: the native-linked probe compiled, and both finite direct executable
groups passed: 12 admission cases and eight failure/cleanup cases. Rust test
registration is implemented; these direct receipts do not claim a Rust-libtest
pass.

The fixture calls the real `ext::url_connect::connect_until` implementation.
It checks a bounded TCP connector independently of HTTP and TLS. The native
target is Linux x86_64; the GPU is used to compile the Lanius producer, not to
execute its host socket operations.

## Finite groups

`admission` passed 12 cases: expired deadline, checked deadline-add overflow,
unnormalized deadline, zero/oversized result and attempt limits, zero or
unnormalized attempt duration, socket-call budgets zero/one, and numeric-family
mismatch. These cases must publish no attempted endpoint and issue no native
resolver or socket call. Armed test DNS inputs expose accidental lookup; the
URL backing remains alive until explicit destruction.

`failures` passed eight cases: numeric refusal, a live socket with only its
reserved cleanup credit remaining, ordered DNS stopped at the attempt cap,
ordered DNS exhaustion, `EAI_SYSTEM` with saved errno, another EAI error with
zero system errno, successful numeric connection with idempotent close, and a
reached failed close. The DNS observer supplies four backed entries in the
order `.2`, `.1`, `.3`, `.1`; all are refused for the exhaustion test. No
external DNS is used. The observer is the existing test-only
`../url_client/resolver_observer.c`, not a production resolver implementation.

The close fault is bound to the observed baseline close ordinal and verified
source instruction/fd generation. `strace` skips that close with `EIO`; the
fixture confirms the primary refusal and secondary cleanup error. Its sole
test-only raw repair closes the actual fd reported by the host trace, after
the connector has retired its own token. That repair is marked separately and
does not count as production cleanup success.

## Accepted direct receipts

The executed producer was
`82c8ad978dd8390f53c9cc0888e81d361318dede090fc27b59d81ad84ceea163`;
the oracle was
`f8405ba902d2480c19a21084e28db78d6e7fc8f06ed5dd463a87d91c4d678c8d`.
The native ELF was
`78e0979ed1a2e78a2648f678dee8fa151188c70d517e81a44086ac2bd963cbfe`.
Evidence under `target/stdlib-work/`:

- `url-connect-probe-match-arm-retry.log`: successful compilation after a
  fixture syntax correction to expression match arms.
- `url-connect-admission-first.log`: exit zero, 12 cases; trace directory
  `/tmp/url-connector-admission-82qawloo`.
- `url-connect-failures-first.log`: exit zero, eight cases; trace directory
  `/tmp/url-connector-failures-qikporjw`.

The reached-close case recorded source `close(3)` returning injected `EIO` at
post-IP `0x4639bf`, bound to baseline close ordinal three. Its report retained
primary `ECONNREFUSED` and secondary cleanup `EIO`. A separately marked test
repair then closed fd three at post-IP `0x4641da`; explicit URL destruction
and the final live checkpoint preceded process exit. The ordinary numeric
success case also observed one successful close followed by an idempotent
false return. Source/fd checkpoints and physical call counters passed in
both groups. Separately, 16 CPU policy controls passed; that count is not
added to the executable case counts.

## Commands

Use a native-linked producer compiled from `probe.lani`, with `stdlib` and
`extended` source roots and no SSL/crypto libraries. Each root command is run
with its normal shared build lock and timeout below two minutes.

```sh
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC tests/fixtures/extended/url_client/resolver_observer.c -o OBSERVER.so -ldl
python3 -B tests/fixtures/extended/url_connect/oracle.py admission LINKED_PROBE OBSERVER.so
python3 -B tests/fixtures/extended/url_connect/oracle.py failures LINKED_PROBE OBSERVER.so
```

The Rust test target is `extended_url_connect_execution`; its two filters are:

- `connector_rejects_invalid_limits_deadlines_and_family_before_attempting_an_endpoint`
- `connector_bounds_ordered_fallback_preserves_resolver_errors_and_retires_failed_sockets`

## Observation boundary

The test transport is eight little-endian request words plus URL bytes, then
three 320-byte metadata reports with host ACKs: before connection, after the
connector result, and after explicit destruction. Fixed report fields include
typed failure/last-attempt details, physical call counters and selected fd.
At each ACK the oracle compares full syscall observation to actual `/proc`
file descriptors and source mappings. It binds socket generations, requires
one live attempt at a time, and checks zero owners before the final ACK.

The shared exact native-image authority and existing source-allocation ledger
are reused unchanged. Loader/libc allocations are separate. The oracle's
`controls` mode mutates only this fixture's phase, fd and physical-counter
checks; CPU controls are not evidence that the Lanius producer executes.

These cases do not establish interruption of synchronous NSS, arbitrary clock
fault handling, allocation-failure coverage, other platforms or GPU host-service
execution. Connected HTTP/TLS behavior is covered by the separate URL-client
fixtures.
