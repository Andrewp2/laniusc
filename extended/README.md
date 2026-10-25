# Extended library

Optional libraries live under this source root and use the `ext` namespace.
They are implemented in Lanius and import the standard library through its
ordinary modules. Add this root only when an application needs an extended
module:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/csv_normalize.lani -o /tmp/csv-normalize
```

The compiler binary must already be built. Paths above are relative to the
repository root. An application imports the CSV module with `import ext::csv;`.
The [generated declaration index](../docs/api/README.md#ext) lists public
signatures and source locations; the guides below describe runtime contracts.
Declaration inventory does not establish execution or complete semantic docs.

| Module | Working surface | Execution evidence |
| --- | --- | --- |
| [`ext::hmac_sha256`](ext/hmac_sha256.lani), [`ext::hkdf_sha256`](ext/hkdf_sha256.lani) | Incremental keyed MACs, extract/expand key derivation, explicit lifecycle and output limits, caller storage | x86_64 Linux; [RFC vectors, state ownership and failure contracts](../docs/extended-hmac-hkdf.md), [streaming key-derivation program](../docs/extended-derive-key.md) |
| [`ext::hmac_sha384`](ext/hmac_sha384.lani), [`ext::hkdf_sha384`](ext/hkdf_sha384.lani) | Full 48-byte MACs and PRKs, streaming/reset, extract/expand through counter 255, explicit limits and caller output | x86_64 Linux; [930 independent commands and an ordinary composition program](../docs/extended-hmac-hkdf-sha384.md), including full output bytes, copied state, zero digest tails and atomic rejection. [Selected-hash TLS schedules](../docs/extended-tls-schedule.md) also execute. |
| [`ext::chacha20_poly1305`](ext/chacha20_poly1305.lani) | IETF authenticated encryption/decryption with full tags, checked views and authenticate-before-output behavior | x86_64 Linux; [RFC vectors, independent models, mutation rejection and ordinary consumer](../docs/extended-chacha20-poly1305.md) |
| [`ext::aes_gcm`](ext/aes_gcm.lani) | AES-128/192/256 GCM with general byte IVs, full detached tags, copied keys and authentication before plaintext writes | x86_64 Linux; [1,022 independent protocol commands and an ordinary consumer](../docs/extended-aes-gcm.md), including NIST vectors, counter wrap, mutations and bounds. [TLS records](../docs/extended-tls-record.md) separately admit AES-128-GCM/SHA-256 and AES-256-GCM/SHA-384. |
| [`ext::x25519`](ext/x25519.lani) | Fixed-storage scalar multiplication, canonical coordinates and all-zero shared-result rejection | x86_64 Linux; [RFC vectors, libsodium/field models, encodings and iteration evidence](../docs/extended-x25519.md) |
| [`ext::p256`](ext/p256.lani) | Fixed-storage SEC1 validation/conversion, public keys, raw ECDH and ECDSA/SHA-256 verification | x86_64 Linux; [1,288 protocol commands and an ordinary consumer](../docs/extended-p256.md), including NIST/RFC anchors, affine/OpenSSL comparisons, exceptional group cases and rejection behavior. [TLS group integration](../docs/tls-group-integration-plan.md) also executes; ECDSA certificate/signature integration remains pending. |
| [`ext::ed25519`](ext/ed25519.lani) | Deterministic pure Ed25519 keys/signatures, canonical encodings and explicit subgroup verification policy | x86_64 Linux; [all five focused native groups](../docs/extended-ed25519.md), including RFC vectors, independent signing, adversarial points and byte mutations |
| [`ext::signature`](ext/signature.lani) | Owned Ed25519/P-256/RSAE public keys, strict SPKI and scheme classification, shared verification allowances | x86_64 Linux; [719 protocol commands and a four-vector consumer](../docs/extended-signature.md), with independent OpenSSL verification, full guards, malformed encodings and budget boundaries. Certificate-path and TLS dispatch integration remain separate work. |
| [`ext::rsa`](ext/rsa.lani) | Bounded 2048–4096-bit public verification, SHA-256 PKCS#1 v1.5 and PSS with salt 32, strict RSAE keys/identifiers and explicit work budgets | x86_64 Linux; [620 protocol commands and an ordinary consumer](../docs/extended-rsa.md), including NIST/OpenSSL comparisons, the 2049-bit PSS boundary, padding/DER/metadata rejection and copied keys. Certificate/TLS integration remains separate. |
| [`ext::der`](ext/der.lani) | Borrowed canonical TLV framing, typed values, checked cursors and atomic caller-buffer writes | x86_64 Linux; [1,824 model/certificate commands and an ordinary consumer](../docs/extended-der.md). Certificate schema and trust policy remain separate. |
| [`ext::x509`](ext/x509.lani) | Borrowed certificate structure, Names, algorithms, selected extensions and shared parse/work budgets | x86_64 Linux; [690 model/OpenSSL commands and an ordinary consumer](../docs/extended-x509.md). Signature, path, identity, time and trust validation remain separate. |
| [`ext::service_identity`](ext/service_identity.lani) | Explicit DNS/IP references, ASCII DNS/wildcard matching and complete SAN traversal with shared work budgets | x86_64 Linux; [1,592 protocol commands and an ordinary consumer](../docs/extended-service-identity.md). No CN fallback, implicit lookup or trust decision. |
| [`ext::x509_path`](ext/x509_path.lani) | Ordered Ed25519 server paths, explicit anchors, inclusive UTC validity, usage/CA/path constraints and copied validated leaf keys | x86_64 Linux; [160 model/OpenSSL commands and an ordinary consumer](../docs/extended-x509-path.md), plus [84 certificate-verifier cases](../docs/extended-verify-certificate.md). Restricted offline profile; normalized DN matching, path building, name constraints, certificate policies and revocation remain unsupported. |
| [`ext::tls_hash`](ext/tls_hash.lani), [`ext::tls_suite`](ext/tls_suite.lani) | Selected SHA-256/SHA-384 streams, owned digest snapshots, three TLS 1.3 suite identities and copied ordered policies | x86_64 Linux; [1,634 protocol commands and an ordinary consumer](../docs/extended-tls-hash.md), with independent full-byte hashes, streaming copies, explicit limits, policy validation and zero allocations. [Connected SHA-384 execution](../docs/extended-tls-tcp.md) also passes. |
| [`ext::tls_framing`](ext/tls_framing.lani) | Caller-backed incremental record/handshake framing, exact consumed prefixes, backpressure and poisoned-state recovery | x86_64 Linux; [7,760 model actions, an ordinary consumer and the full 16,777,215-byte handshake body](../docs/extended-tls-framing.md). Framing retains opaque types/versions; connection policy owns their legality. |
| [`ext::tls_handshake`](ext/tls_handshake.lani) | Borrowed TLS 1.3 frames, typed body codecs and shared iterator cursors | x86_64 Linux; [1,396 model commands and an ordinary consumer](../docs/extended-tls-handshake.md). Negotiation, connection ordering and authentication policy remain separate. |
| [`ext::tls_negotiation`](ext/tls_negotiation.lani) | Independent X25519/P-256 group and ordered three-suite policy selection, HRR/CH2 rules, SNI/ALPN and atomic extension writers | x86_64 Linux; [1,692 model commands and quota probes plus a six-flow consumer](../docs/extended-tls-negotiation.md), with returned-byte witnesses, full writer snapshots and zero allocations. Connection ordering, transcript and key epochs remain owned by the connection engine. |
| [`ext::tls_authentication`](ext/tls_authentication.lani) | Ordered Ed25519 server-flight authentication with SHA-256/SHA-384 transcripts and Finished; copied peer key only after success; terminal failure latching | x86_64 Linux; [232 protocol cases, 716 observations and four ordinary flows](../docs/extended-tls-authentication.md), including full owned CV contexts, source-buffer retirement, copies, retry/budget boundaries and a long chain. Authentication remains one connection checkpoint. |
| [`ext::tls_schedule`](ext/tls_schedule.lani), [`ext::tls_transcript`](ext/tls_transcript.lani) | Typed SHA-256/SHA-384 key schedules, Finished/exporter/resumption derivation, complete-frame transcripts and HRR rewriting | x86_64 Linux; [232 protocol commands, 1,040 transcript actions, 12 RFC anchors and an ordinary consumer](../docs/extended-tls-schedule.md). Full 12,240-byte SHA-384 output executes; callers enforce connection checkpoints. |
| [`ext::tls_record`](ext/tls_record.lani) | TLS 1.3 AES-128-GCM/SHA-256, AES-256-GCM/SHA-384 and ChaCha20-Poly1305/SHA-256 records with typed secrets, directional state and key-use limits | x86_64 Linux; [308 ChaCha, 220 AES-128 and 220 AES-256 protocol commands, plus two ordinary consumers](../docs/extended-tls-record.md), with zero allocations. The [earlier compilation comparison](../docs/library-foundation-performance.md#explicit-record-suites-and-aes-gcm-integration) covers AES-128 integration; [connected SHA-384 execution](../docs/extended-tls-tcp.md) also passes. |
| [`ext::tls_connection`](ext/tls_connection.lani) | Portable client/server handshake and record engine with selected SHA-256/SHA-384, authenticated checkpoints, output acknowledgments, KeyUpdate, half-close and quotas | x86_64 Linux; [154 scripted cases and an ordinary consumer](../docs/extended-tls-connection.md) cover all three suites, X25519/P-256 with Ed25519, late hash binding, retry, fragmented Finished and explicit entropy/work/exporter boundaries. |
| [`ext::tls_tcp`](ext/tls_tcp.lani) | Owned nonblocking TCP adapter with shared host budgets, observed deadlines, bounded entropy and explicit cleanup | x86_64 Linux; [122 native transport cases](../docs/extended-tls-tcp.md), including actual OpenSSL peers, 1 MiB pressure streams, owner/fault paths and operation-budget resumption; [80 exchange-program cases](../docs/extended-tls-exchange.md). Broader signature algorithms and PKIX remain work. |
| [`ext::csv`](ext/csv.lani) | Incremental UTF-8 decoding, reusable packed records, whole tables, borrowed/copied fields and canonical encoding | x86_64 Linux; [contracts and tests](../docs/extended-csv.md) |
| [`ext::json`](ext/json.lani) | Parse/build owned documents, query nodes, encode compact JSON with exact number text | x86_64 Linux; [contracts and tests](../docs/extended-json.md) |
| [`ext::cli`](ext/cli.lani) | Borrowed raw-byte argument parser, short groups, exact long names, required/optional values and structured errors | x86_64 Linux; [contracts and tests](../docs/extended-cli.md) |
| [`ext::config`](ext/config.lani) | Owned strict JSON sources, bounded file loading, borrowed typed queries and explicit shallow precedence | x86_64 Linux; [contracts and tests](../docs/extended-config.md) |
| [`ext::settings`](ext/settings.lani), [`ext::settings_env`](ext/settings_env.lani) | Borrowed typed JSON/TOML/binding overlays, exact JSON numbers, provenance and owned allowlisted environment bindings | x86_64 Linux; [contracts, inspection program and failure tests](../docs/extended-settings.md) |
| [`ext::log`](ext/log.lani) | Severity filters, borrowed typed records and atomic caller-buffer preparation of JSON log records | x86_64 Linux; [contracts, delivery and tests](../docs/extended-log.md) |
| [`ext::glob`](ext/glob.lani) | Compiled raw-byte patterns, ASCII classes/case rules, recursive components and bounded matches with caller scratch | x86_64 Linux matcher and path-filter application tests; [contracts and evidence](../docs/extended-glob.md) |
| [`ext::percent`](ext/percent.lani) | Checked raw-byte component percent encoding/decoding, caller buffers, in-place conversion and atomic errors | x86_64 Linux; [contracts and tests](../docs/extended-percent.md) |
| [`ext::uri`](ext/uri.lani) | Strict borrowed RFC 3986 URI-reference parsing, exact encoded component views, IPv4/IPv6/IPvFuture syntax and explicit limits | x86_64 Linux; [contracts and tests](../docs/extended-uri.md), [component application](../docs/extended-uri-component.md) |
| [`ext::uri_resolve`](ext/uri_resolve.lani) | Owned strict RFC 3986 resolution and recomposition, linear dot-segment removal, final-output limits and explicit allocation errors | x86_64 Linux; [contracts and tests](../docs/extended-uri-resolve.md), [resolution program](../docs/extended-uri-resolve-program.md) |
| [`ext::deflate`](ext/deflate.lani) | Allocation-free raw DEFLATE encoding with fixed Huffman LZ77, stored-block fallback, caller scratch and atomic output failures | x86_64 Linux; [contracts, tests and measurements](../docs/extended-deflate.md) |
| [`ext::inflate`](ext/inflate.lani) | Allocation-free raw DEFLATE decoding with stored/fixed/dynamic blocks, history limits and explicit prefix progress | x86_64 Linux; [contracts and tests](../docs/extended-inflate.md) |
| [`ext::compression`](ext/compression.lani) | Owned raw/zlib/gzip encoding and checked decoding, concatenated gzip, output limits and allocation cleanup | x86_64 Linux; [contracts and tests](../docs/extended-compression.md), [binary application](../docs/extended-compress-bytes.md) |
| [`ext::tar`](ext/tar.lani) | Borrowed POSIX ustar metadata/data and atomic caller-buffer multi-member writing, checked headers/padding/footer and raw byte paths | x86_64 Linux; [contracts and tests](../docs/extended-tar.md), [TAR/gzip application](../docs/extended-tar-bytes.md) |
| [`ext::zip`](ext/zip.lani) | Bounded classic single-disk ZIP metadata, checked stored/DEFLATE member extraction and deterministic owned multi-member writing | x86_64 Linux; [contracts and tests](../docs/extended-zip.md), [binary application](../docs/extended-zip-bytes.md) |
| [`ext::cbor`](ext/cbor.lani) | Allocation-free iterative CBOR wire events, full-width integers and float bits, definite/indefinite structures, strict text, caller scratch and atomic encoding | x86_64 Linux; [contracts and tests](../docs/extended-cbor.md), [checked ZIP manifest](../docs/extended-zip-manifest.md) |
| [`ext::schema`](ext/schema.lani) | Explicit JSON Schema 2020-12 profile, exact decimal comparisons, local references, combinators and structural checks | x86_64 Linux; [profile, limits and tests](../docs/extended-schema.md) |
| [`ext::toml`](ext/toml.lani) | Typed TOML 1.1 parsing, queries and deterministic encoding | x86_64 Linux; [official corpus and contracts](../docs/extended-toml.md) |
| [`ext::big_uint`](ext/big_uint.lani), [`ext::big_int`](ext/big_int.lani) | Owned arbitrary precision integer arithmetic, division, radix conversion, shifts and bit operations | x86_64 Linux; [unsigned](../docs/extended-big-uint.md), [signed](../docs/extended-big-int.md) |
| [`ext::decimal`](ext/decimal.lani) | Finite arbitrary precision decimal arithmetic, explicit rounding and lawful numeric keys | x86_64 Linux; [contracts and tests](../docs/extended-decimal.md) |
| [`ext::statistics`](ext/statistics.lani) | Streaming moments, covariance, linear fits, compensated sums, norms and quantiles | x86_64 Linux; [numerical contracts and tests](../docs/extended-statistics.md) |
| [`ext::distributions`](ext/distributions.lani) | Normal, exponential, gamma and beta densities, paired tails and bounded generic sampling | x86_64 Linux; [accuracy profiles and tests](../docs/extended-distributions.md), [CSV sampling program](../docs/extended-sample-distribution.md) |
| [`ext::discrete_distributions`](ext/discrete_distributions.lani) | Bernoulli, binomial, geometric and Poisson masses, paired/log tails and bounded generic sampling | x86_64 Linux; [domains, numerical profiles and tests](../docs/extended-discrete-distributions.md), [count simulation program](../docs/extended-sample-counts.md) |
| [`ext::linalg`](ext/linalg.lani) | Strided and owned matrices, products, pivoted LU and Householder QR least squares | x86_64 Linux; [numerical contracts and tests](../docs/extended-linalg.md) |
| [`ext::geometry`](ext/geometry.lani) | Exact full-i32 planar predicates, segments, rings and convex hulls; finite floating vectors and affine transforms | x86_64 Linux; [contracts and reference tests](../docs/extended-geometry.md), [CSV hull program](../docs/extended-shape-hull.md) |
| [`ext::regex`](ext/regex.lani) | Bounded ordered Pike matching, captures, greedy/lazy repetition and Unicode properties | x86_64 Linux; [supported syntax and tests](../docs/extended-regex.md) |
| [`ext::parse`](ext/parse.lani) | Borrowed UTF-8 parsing cursors, locations, spans, checkpoints and atomic scanners | x86_64 Linux; [contracts and models](../docs/extended-parse.md) |
| [`ext::diff`](ext/diff.lani), [`ext::patch`](ext/patch.lani) | Shortest byte-line scripts, unified encoding, strict parsing and exact staged application | x86_64 Linux; [diff](../docs/extended-diff.md), [patch](../docs/extended-patch.md) |
| [`ext::unicode_normalize`](ext/unicode_normalize.lani) | NFC/NFD/NFKC/NFKD with Unicode 17 tables | x86_64 Linux; [official conformance tests](../docs/extended-unicode-normalize.md) |
| [`ext::unicode_graphemes`](ext/unicode_graphemes.lani) | Unicode 17 default extended grapheme segmentation | x86_64 Linux; [official conformance tests](../docs/extended-unicode-graphemes.md) |
| [`ext::unicode_words`](ext/unicode_words.lani) | Unicode 17 default word boundaries | x86_64 Linux; [official conformance tests](../docs/extended-unicode-words.md) |
| [`ext::unicode_sentences`](ext/unicode_sentences.lani) | Unicode 17 default sentence boundaries, byte spans and bounded allocation-free cursors | x86_64 Linux; [official corpus and independent rule model](../docs/extended-unicode-sentences.md), [CSV/framed application](../docs/extended-text-sentences.md) |
| [`ext::unicode_lines`](ext/unicode_lines.lani) | Full Unicode 17 default line opportunities and mandatory breaks | x86_64 Linux; [official corpus and contracts](../docs/extended-unicode-lines.md) |
| [`ext::unicode_lines_wrap`](ext/unicode_lines_wrap.lani) | Owned greedy wrapping over legal grapheme boundaries and explicit terminal widths | x86_64 Linux; [policy, models and application](../docs/extended-text-wrap.md) |
| [`ext::unicode_case`](ext/unicode_case.lani) | Full root, Turkic and Lithuanian casing and folding with contextual rules | x86_64 Linux; [contracts and tests](../docs/extended-unicode-case.md) |
| [`ext::terminal`](ext/terminal.lani) | Explicit Unicode 17 scalar/grapheme display-width policy, ambiguous-width settings and control rejection | x86_64 Linux; [policy and source vectors](../docs/extended-terminal.md) |
| [`ext::table`](ext/table.lani) | Bounded rectangular UTF-8 tables with alignment, borders and checked owned output | x86_64 Linux; [contracts and models](../docs/extended-table.md) |
| [`ext::progress`](ext/progress.lani) | Allocation-free atomic rendering for known, unknown, zero and exceeded totals | x86_64 Linux; [contracts and tests](../docs/extended-progress.md) |
| [`ext::http`](ext/http.lani) | HTTP/1 heads, framing, chunk extensions/trailers, incremental boundary scanning and checked encoding | x86_64 Linux; [wire profile and tests](../docs/extended-http.md), [allocation-free cursor contracts](../docs/extended-http-cursor.md). Final canonical parsing validates framing candidates. |
| [`ext::http_client`](ext/http_client.lani) | One bounded cleartext HTTP/1.1 exchange with an explicit numeric endpoint, owned response and checked body decoding | x86_64 Linux; [deadlines, limits, ownership, fetch program and failure tests](../docs/extended-http-client.md). TLS, automatic resolution/redirects and pooling remain separate work. |
| [`ext::http_server`](ext/http_server.lani) | One staged cleartext HTTP/1 connection with stable request views, explicit 100 Continue, checked final response and bounded close/drain | x86_64 Linux; [deadlines, quotas, ownership, local service and peer/fault tests](../docs/extended-http-server.md). Keepalive, worker scheduling, TLS and upgrade/tunnel handoff remain separate work. |
| [`ext::dns`](ext/dns.lani) | Binary DNS names, validated compression, complete QUERY sections, common RDATA, EDNS and checked packet writing | x86_64 Linux offline processing; [profile, limits, models and program](../docs/extended-dns.md). Host resolution remains separate. |
| [`ext::dns_client`](ext/dns_client.lani) | Explicit numeric-server UDP queries, fixed retry windows, correlated TCP fallback and owned validated responses | x86_64 Linux; [transport profile, query application and loopback/fault tests](../docs/extended-dns-client.md). System resolver/NSS policy remains separate. |
| [`ext::websocket`](ext/websocket.lani) | RFC 6455 handshakes, role masking, frames, fragmented messages, control/close state and checked encoding | x86_64 Linux offline processing; [contracts, independent oracles and program](../docs/extended-websocket.md). Socket/TLS transport remains separate. |
| [`ext::kv`](ext/kv.lani) | Owned arbitrary-byte key/value storage, atomic mutations and canonical checked snapshots | x86_64 Linux; [models, file program and persistence limits](../docs/extended-kv.md). Crash durability and concurrent transactions require host services. |
| [`ext::timezone`](ext/timezone.lani) | Owned TZif v1–v4, supported POSIX footer rules, historical offsets and complete local-time candidates | x86_64 Linux; [coverage, ambiguity, limits and command-line tool](../docs/extended-timezone.md). Leap-bearing files and unsupported annual rule streams fail explicitly. |
| [`ext::image`](ext/image.lani) | Owned straight RGBA8 pixels, strided views, crop, rotation, flips, blit and source-over | x86_64 Linux; [pixel and ownership contracts](../docs/extended-image.md) |
| [`ext::png`](ext/png.lani) | All standard PNG color/depth inputs, Adam7, filters and checked RGBA8 output/encoding | x86_64 Linux; [PNG profile and interoperability tests](../docs/extended-png.md) |
| [`ext::audio`](ext/audio.lani) | Owned interleaved finite samples, checked edits, gain/mix/clip, metrics and mono conversion | x86_64 Linux; [numeric and ownership contracts](../docs/extended-audio.md) |
| [`ext::wave`](ext/wave.lani) | PCM8/16/24/32, IEEE float and ordinary extensible WAVE decoding; checked canonical encoding | x86_64 Linux; [format and conversion contracts](../docs/extended-wave.md) |
| [`ext::signal`](ext/signal.lani) | Finite complex arithmetic, FFT/inverse, windows, full convolution and spectral bins | x86_64 Linux; [numerical/resource contracts](../docs/extended-signal.md), [WAVE spectrum program](../docs/extended-wave-spectrum.md) |

The [seal-bytes application](../docs/extended-seal-bytes.md) passes 137 native
cases, including allocation/I/O failures, full 1 MiB seal/open and shared
call-budget checks. The
[pinned compiler comparison](../docs/library-foundation-performance.md#authenticated-bytes-key-exchange-and-tls-records)
records measured crypto and large-library workloads and their limits. The
portable connection and TCP adapter now have separate evidence above; their
restricted algorithm and trust profile does not establish general TLS/PKIX
interoperability.

The [signing application](../docs/extended-sign-bytes.md) passes 128 native
cases, including full 1 MiB sign/verify and resource/I/O failures. The
[composed authentication flight](../docs/extended-tls-auth-foundation.md) passes
18 cases and 720 output fields across both layouts and eight tamper scenarios.
It verifies a real certificate's self-signature and authentication checkpoints
inside a fixed fixture. The later [ordered-path](../docs/extended-x509-path.md)
and [connection](../docs/extended-tls-connection.md) gates separately exercise
their documented trust and reusable state-machine profiles.
The [certificate inspector](../docs/extended-certificate-info.md) passes 50
native cases for parsed metadata, complete reports, failures and resource caps.

Generated Unicode table modules are implementation data rather than separate
APIs. Their source versions and regeneration commands are recorded by the
corresponding module guides. All execution evidence above concerns native
x86_64 Linux programs produced by the GPU compiler; user GPU kernels and other
targets have not been verified.

The complete scope and dependency order are
tracked in the [library roadmap](../docs/library-roadmap.md). [Selective source
distribution](../docs/library-distribution.md) uses the existing package resolver.
Package publishing,
other formats and protocols, and additional targets remain separate work.
