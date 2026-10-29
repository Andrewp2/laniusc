# Extended library

Optional libraries live under this source root and use the `ext` namespace.
They are implemented in Lanius and import the standard library through its
ordinary modules. Add this root only when an application needs an extended
module:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --stdlib-root stdlib --source-root extended \
  sample_programs/csv_normalize.lani -o /tmp/csv-normalize
```

The compiler binary must already be built. Paths above are relative to the
repository root. An application imports the CSV module with `import ext::csv;`.
The [generated declaration index](../docs/api/README.md#ext) lists public
signatures and source locations; the guides below describe runtime contracts.
Declaration inventory does not establish execution or complete semantic docs.

[OpenSSL digest contexts](../docs/extended-openssl-digest.md) execute SHA-256,
SHA-512, SHA3-256 and SHA3-512 through the [native C profile](../docs/library-native-c.md)
on Linux x86_64/glibc. The [hashing program](../docs/extended-openssl-hash.md)
uses that binding for binary stdin. Sensitive operations belong to established
native libraries; Lanius handles the interface, byte layout and ownership.
C `f32`/`f64` calls execute through independent SSE/GPR banks. An owned
[SQLite adapter](../docs/extended-sqlite.md) and
[persistent binary key/value program](../docs/extended-sqlite-kv.md) execute
through system SQLite on the same Linux x86_64/glibc profile, including typed
values, transactions, persistence, locks and explicit failure recovery.
OpenSSL [verified client TLS](../docs/extended-openssl-tls.md),
[server TLS](../docs/extended-openssl-tls-server.md) and
[mutual TLS](../docs/extended-openssl-mutual-tls.md) execute on their documented
native profiles, including the selected peer-trust policies. Standalone
encryption/signature wrappers and broader certificate policy remain work; see
the [remaining native prerequisites](../docs/library-native-integration-prerequisites.md).
Raw DER/X.509 parsing supplies schema inspection independently.

| Module | Working surface | Execution evidence |
| --- | --- | --- |
| [`ext::openssl_digest`](ext/openssl_digest.lani) | Owned OpenSSL 3 EVP contexts for streaming SHA-256, SHA-512, SHA3-256 and SHA3-512; checked byte views, output buffers, errors and cleanup | Linux x86_64/glibc with dynamic `libcrypto.so.3`; [2,124 digest cases and 12 native failure modes](../docs/extended-openssl-digest.md), [bounded stdin hashing program](../docs/extended-openssl-hash.md). Other security wrappers remain work. |
| [`ext::sqlite`](ext/sqlite.lani) | Native SQLite database and prepared-statement owners, strict typed values, copied text/blobs, transactions, limits, errors and cleanup | Linux x86_64/glibc with system SQLite; [558 typed cases, 640 model commands, 21 native failure modes and a measured bulk workload](../docs/extended-sqlite.md), [four staging allocation failures](../docs/extended-sqlite-allocation.md), [persistent binary key/value program](../docs/extended-sqlite-kv.md). |
| [`ext::der`](ext/der.lani) | Borrowed canonical TLV framing, typed values, checked cursors and atomic caller-buffer writes | x86_64 Linux; [1,824 model/certificate commands and an ordinary consumer](../docs/extended-der.md). Certificate schema and trust policy remain separate. |
| [`ext::x509`](ext/x509.lani) | Borrowed certificate structure, Names, algorithms, selected extensions and shared parse/work budgets | x86_64 Linux; [690 model/OpenSSL commands and an ordinary consumer](../docs/extended-x509.md). Schema inspection only; no signature, path or trust verification. |
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
| [`ext::graph`](ext/graph.lani) | Canonical integer directed adjacency, sorted unique neighbors, idempotent input edges, checked work/size admission and manual owners | Eight library tests and four dependency-order groups/183 cases pass on native Linux x86_64 CPU output; [graph contracts and finite evidence](../docs/extended-graph.md) retain the finite target scope. |
| [`ext::graph_algorithms`](ext/graph_algorithms.lani) | Shortest-hop FIFO BFS with explicit path absence; Min-heap Kahn ordering or Cycle | Eight library tests and four dependency-order groups/183 cases pass on native Linux x86_64 CPU output; [query, tie, work and ownership contracts](../docs/extended-graph.md) retain separate model/resource/application scopes. |
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
| [`ext::http_server`](ext/http_server.lani) | One staged cleartext HTTP/1 connection with stable request views, explicit 100 Continue, checked final response and bounded close/drain | x86_64 Linux; [deadlines, quotas, ownership, local service and peer/fault tests](../docs/extended-http-server.md). [Server TLS](../docs/extended-openssl-tls-server.md) has separate native receipts; keepalive, worker scheduling and upgrade/tunnel handoff remain separate work. |
| [`ext::dns`](ext/dns.lani) | Binary DNS names, validated compression, complete QUERY sections, common RDATA, EDNS and checked packet writing | x86_64 Linux offline processing; [profile, limits, models and program](../docs/extended-dns.md). Host resolution remains separate. |
| [`ext::dns_client`](ext/dns_client.lani) | Explicit numeric-server UDP queries, fixed retry windows, correlated TCP fallback and owned validated responses | x86_64 Linux; [transport profile, query application and loopback/fault tests](../docs/extended-dns-client.md). System resolver/NSS policy remains separate. |
| [`ext::websocket`](ext/websocket.lani) | RFC 6455 request validation/encoding, Base64 keys, role masking, frames, fragmented messages, control/close state and checked encoding | x86_64 Linux offline processing; [contracts, independent oracles and program](../docs/extended-websocket.md). Portable response verification and [OpenSSL Accept generation](../docs/extended-openssl-websocket.md) have separate finite receipts; [borrowed upgrade](../docs/extended-websocket-upgrade.md) and [frame transport](../docs/extended-websocket-stream.md) compose through separate modules. |
| [`ext::kv`](ext/kv.lani) | Owned arbitrary-byte key/value storage, atomic mutations and canonical checked snapshots | x86_64 Linux; [models, file program and persistence limits](../docs/extended-kv.md). Crash durability and concurrent transactions require host services. |
| [`ext::timezone`](ext/timezone.lani) | Owned TZif v1–v4, supported POSIX footer rules, historical offsets and complete local-time candidates | x86_64 Linux; [coverage, ambiguity, limits and command-line tool](../docs/extended-timezone.md). Leap-bearing files and unsupported annual rule streams fail explicitly. |
| [`ext::image`](ext/image.lani) | Owned straight RGBA8 pixels, strided views, crop, rotation, flips, blit and source-over | x86_64 Linux; [pixel and ownership contracts](../docs/extended-image.md) |
| [`ext::png`](ext/png.lani) | All standard PNG color/depth inputs, Adam7, filters and checked RGBA8 output/encoding | x86_64 Linux; [PNG profile and interoperability tests](../docs/extended-png.md) |
| [`ext::audio`](ext/audio.lani) | Owned interleaved finite samples, checked edits, gain/mix/clip, metrics and mono conversion | x86_64 Linux; [numeric and ownership contracts](../docs/extended-audio.md) |
| [`ext::wave`](ext/wave.lani) | PCM8/16/24/32, IEEE float and ordinary extensible WAVE decoding; checked canonical encoding | x86_64 Linux; [format and conversion contracts](../docs/extended-wave.md) |
| [`ext::signal`](ext/signal.lani) | Finite complex arithmetic, FFT/inverse, windows, full convolution and spectral bins | x86_64 Linux; [numerical/resource contracts](../docs/extended-signal.md), [WAVE spectrum program](../docs/extended-wave-spectrum.md) |

The [certificate inspector](../docs/extended-certificate-info.md) reports
parsed schema metadata with explicit input, work and output limits. It computes
no cryptographic fingerprint and makes no trust decision.

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
