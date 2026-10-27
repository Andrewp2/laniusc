# Connected URL client verification

Status: plain/DNS/TLS producers, independent peers and the registered driver are implemented;
compilation and runtime acceptance are pending root's serialized gates. The
root-owned `public_smoke.lani` has its own separate admission receipt.

`plain_probe.lani URL EXPECTED_SELECTED_INDEX` performs a canonical POST with a
four-byte binary body from a nonzero view. It reports three fixed 128-byte
little-endian metadata frames and waits for `+` after each: URL-owned before the
call, response/URL-owned after the exchange, and explicitly released before
exit. These frames are test transport only.

```sh
python3 -B tests/fixtures/extended/url_client/oracle.py plain PATH_TO_LINKED_PROBE
```

The finite two-case plain group uses independent loopback peers: fixed and
chunked/interim responses. It checks exact Host spelling (including a leading
zero in the explicit port), unchanged origin-form target/escapes/dot segments,
omitted fragment, binary request and decoded response body. Full syscall
observation binds the sole raw socket/connect, both peer proofs, nonblocking
query, sends/receives and explicit successful close to the selected fd. The
peer rejects a second connection. The shared linked-ELF/exact-runtime verifier and unchanged live source
ledger check full-width requested allocations and actual `/proc` owners at
ACK checkpoints, including zero source mappings/fds before final ACK. Native
loader/libc maps are separate from source owners; this is native Linux x86_64,
not a user GPU kernel test.

Registered Rust filter:
`numeric_url_preserves_host_target_binary_body_and_selected_socket_without_reconnect`.
The driver uses native linking without SSL/crypto libraries for this plain
producer. No acceptance count is claimed until the actual gate passes.

## DNS and TLS groups (runtime pending)

`resolver_observer.c` includes the unchanged historical resolver ABI observer
with renamed exports. Its new test-only mode returns four physically backed,
ordered IPv4 loopback entries: refused `.2`, live `.1`, unused `.3` and a
non-adjacent duplicate `.1`, preserving the requested numeric service. Actual
native `G`/`F` ownership witnesses remain; an additional `U` records the chosen
host/profile. No external DNS or production resolver change is used.

```sh
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC tests/fixtures/extended/url_client/resolver_observer.c -o OBSERVER.so -ldl
python3 -B tests/fixtures/extended/url_client/dns_oracle.py PLAIN_LINKED_PROBE OBSERVER.so
python3 -B tests/fixtures/extended/url_client/tls_oracle.py TLS_LINKED_PROBE OBSERVER.so
```

The DNS group has one proposed case. It checks selected ordinal1/attempts2,
exact preserved Host/target/body, release before fallback, and two peer proofs
on the selected fd **generation**, including fd reuse. The TLS group has eight
proposed cases across native TLS1.2/1.3: numeric IP with no SNI, original DNS
with SNI, rejected mismatching DNS before HTTP bytes, and authenticated HTTP
truncation after the complete request. The latter failures must never open a
third endpoint or replay the request. OpenSSL creates certificates and performs
TLS; existing certificate and MemoryBIO peer helpers are reused unchanged.

Both groups use `connected.py` for the three ACKs and strict source cleanup.
The shared `tests/fixtures/native_c/source_allocations.py` recognizes complete
fixed runtime blocks, verifies every instruction extent, tracks exact `.22` or
`.62` allocator sites, and excludes the CRT bootstrap/native heap. Its named
fallback is empty. Every decoded image syscall is partitioned into exact
source/runtime sites or paired raw-entry/CRT bootstrap exceptions; observed
unknown image sites fail, including two-byte calls at executable ends. The
existing linked-ELF validator keeps its original public
return/CLI behavior. The unchanged Source ledger rejects unknown source maps
and frees. CPU checks are separate from any native acceptance: six existing
validator tests, nine new shared-authority tests, and 12 URL causal/wire
controls pass. No connected native group has passed yet in this document.

Registered additional filters:

- `dns_url_preserves_nss_order_retires_refused_endpoint_and_adopts_one_selected_fd`
- `url_tls_verifies_original_dns_or_ip_and_never_replays_after_tls_or_http_failure`

The real fetch program has its own separately owned fixtures and receipts.
