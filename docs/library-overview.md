# Standard and extended library overview

The [execution audit and portable foundation](stdlib-foundation.md) lists
the stdlib APIs verified on x86_64, their edge behavior, and the remaining
compiler and runtime dependencies.

The [standard and extended library roadmap](library-roadmap.md) tracks the
full scope and delivery requirements. New APIs follow the
[library conventions](library-api-conventions.md); the first
[owned UTF-8 String](stdlib-string.md) has executable native examples and
allocation-failure tests.
[Borrowed UTF-8 text](stdlib-text.md) provides subviews, splitting, scalar
iteration and hashing without copying.
The [byte stream APIs](stdlib-streams.md) provide shared reader/writer
contracts, owned byte buffers and native descriptor adapters.
The [generic hash map](stdlib-hash-collections.md) provides hashed lookup,
explicit allocation errors and returned displaced keys/values.
[Opt-in deep HashMap cloning](stdlib-clone-hash-map.md) now executes with
independent nested owners, typed key/value errors and allocation-failure cleanup.
[Opt-in recursive deque cloning](stdlib-clone-deque.md) also executes across
four groups, including ring-order models and owned-error rollback. [Opt-in deep heap cloning](stdlib-clone-binary-heap.md) also passes all five
native groups, including priority models and nested/owned-error failure cleanup.
[Opt-in deep TreeMap cloning](stdlib-clone-tree-map.md) also passes all five
native groups, including sorted staging, independent nested owners, typed
key/value rollback, allocation failures and zero-sized keys and values.
[Opt-in deep HashSet cloning](stdlib-clone-hash-set.md) and
[TreeSet cloning](stdlib-clone-tree-set.md) also execute with independent
String owners, representative-preserving models, typed failures and complete
cleanup at every allocation position reached by their focused fixtures.
[Scalar and structural clone implementations](stdlib-clone-values.md) compose
Option, Result and pairs with Strings and vectors, preserving exact scalar bits,
active payloads and typed rollback. Their five native groups pass after the
[empty-enum layout correction](compiler-empty-enum-layout.md).
The [shared iterator protocol](stdlib-iterators.md) connects ranges, views,
collections and text with borrowed adapters. A checked
[range dot-product program](stdlib-range-dot.md) composes zip, take, map
and enumeration, including arithmetic and output failures.
[Canonical slice cursors](stdlib-cursor-integration.md),
[text splits](stdlib-text-split-iterators.md) and
[heap iteration](stdlib-heap-iterators.md) use that same protocol.
[Selection, searches and folds](stdlib-iterator-selection.md) add lazy
filtering and typed short circuits. The [column-sum program](stdlib-column-sum.md)
combines text splitting, filtering, Result items and checked reduction.
[Lookahead and extrema](stdlib-iterator-lookahead.md) add a recoverable one-item
cache, relative position searches and explicit minimum/maximum tie policies.
The [column extrema program](stdlib-column-extrema.md) reports checked counts,
values and physical source rows, including input, allocation and output failures.
[Fallible collection](stdlib-iterator-transfer.md) transfers items into
vectors and deques with explicit progress and rejected-item recovery. The
[word sorter](stdlib-sort-words.md) collects borrowed text before sorting.
[Map, set and heap sinks](stdlib-iterator-collection-sinks.md) preserve
rejected items and stored representatives. The
[identifier index](stdlib-index-words.md) rejects duplicates and prints
ordered identifiers with their original positions.
[Owning Vec and Deque cursors](stdlib-owning-iterators.md) transfer items,
recover unconsumed storage and provide explicit nested cleanup.
[Hash map/set](stdlib-owning-hash.md), [ordered map/set](stdlib-owning-tree.md)
and [priority heap](stdlib-owning-heap.md) owning cursors now provide the same
explicit transfer, recovery and remaining-owner cleanup. Hash traversal is
unordered; ordered-tree and priority-heap pulls use the canonical removal
engines and take O(log n) per item. Their focused native models and owner
ledgers pass through the GPU compiler. The
[streaming word deduplicator](stdlib-unique-words.md) moves independent
Strings into an ordered set while reusing its batch allocation, then transfers
them through the set's owning cursor for publication and failure cleanup.
[Runtime formatting to byte writers](stdlib-format-write.md) validates
before publication and uses bounded scratch with explicit partial progress.
The [CSV report program](stdlib-format-report.md) composes it with numeric
parsing and buffered output.

[System hostname and service resolution](stdlib-resolve.md) now wraps libc
`getaddrinfo` on Linux x86_64/glibc, with explicit ASCII input, family,
TCP/UDP and flag policies. It copies native order and duplicates into owned
socket-address values; unsupported shapes and result limits fail atomically.
The [resolve-host program](stdlib-resolve-host.md) formats those values without
opening a connection. All four library groups and five application groups pass
through separate native receipts; the
[verification guide](stdlib-resolve-testing.md) records independent libc,
malformed-result, limit and reached-allocation coverage.
Lookup blocks in NSS/libc. Local byte/result limits do not impose native memory
quotas, a lookup deadline or DNS authentication.

[Child process groups](stdlib-command-groups.md) add explicit creation,
confirmed signaling authority and non-reaping exit observation. The original
unreaped leader anchors the group ID; final reaping or lost-child evidence
revokes that authority. Pipe capture can retain an observed status while
draining descendant-held pipes, then perform the final reap. The
[run-group supervisor](stdlib-run-group.md) adds explicit TERM/grace/KILL policy
and reports incomplete cleanup. Five API groups and five application groups
pass across separate receipts; the supervisor covers 53 cases.
Descendants can escape a group, and deadlines do not guarantee kernel-stuck
processes become reapable; these APIs do not provide process-tree containment.

[Resumable cleartext HTTP exchanges](extended-http-client.md) expose owned
Prepared request staging and caller-driven Exchange steps. All five direct
[Exchange groups](extended-http-exchange-testing.md) pass across separate
receipts, covering 83 cases; the same engine also passes all six synchronous
client regression groups (188 cases).
[Bounded HTTP batches](extended-http-batch.md) schedule several numeric-endpoint
connections using one thread and reusable polling, with input-order outcomes,
one common deadline, manual response owners, logical pending/retained byte
caps and explicit operation/work allowances. All seven batch groups pass
across separate receipts, including consecutive begin failures followed by
a valid queued job without a blocking poll that delays admission. The [fetch-many program](extended-fetch-many.md) composes bounded CSV
jobs, the batch scheduler and an ordered Stored ZIP, validating all requests
before sockets and staging the archive before stdout. All five application
groups pass across separate receipts, including 59 reached allocation failures
and a 64-job scale control with at most four active sockets. Logical retention
caps do not bound allocator capacity, temporary candidates or process RSS.
Resumable TLS scheduling and executable worker threads remain part of the full
goal; the [concurrency admission audit](library-concurrency-dependencies.md)
records their separate compiler/runtime boundaries. These execution receipts
cover native Linux x86-64 CPU programs built by the GPU compiler.

[Checked native C calls](library-native-c.md) execute on Linux x86_64/glibc
through ordinary ELF objects, the system C linker and libc startup.
[OpenSSL digest contexts](extended-openssl-digest.md) provide streaming
SHA-256, SHA-512, SHA3-256 and SHA3-512 through `libcrypto`; the
[hashing program](extended-openssl-hash.md) hashes bounded binary stdin.
All cryptographic operations use the native library. C `f32`/`f64` calls also
execute with independent SSE/GPR banks and up to 32 total scalar parameters.
An owned [SQLite adapter](extended-sqlite.md) and
a [persistent binary key/value program](extended-sqlite-kv.md) execute
through system SQLite on Linux x86_64/glibc, including typed values, transactions,
persistence, locking and failure tests. Their guides record the execution
evidence and measured bulk workload. [Persistent indexed ZIP snapshots](extended-archive-index.md)
compose ZIP and SQLite with atomic catalog replacement, independent snapshot
owners, binary names/keys and explicit uncertain transaction outcomes. The
application passes all seven native groups, including allocation/native faults
and a measured 1,024-entry workload. [Client TLS with peer verification](extended-openssl-tls.md)
executes through OpenSSL 3 `libssl`/`libcrypto`, with 34 cases across four groups
covering peer identity/trust, binary transfers, closure/truncation and stable
nonblocking retries. It uses manual context/session owners and a borrowed
nonblocking socket with explicit caller deadlines and SIGPIPE policy. The
[TLS stream adapter and HTTPS application](extended-https-fetch.md) execute
62 cases across four groups on Linux x86_64, covering stream progress,
verification/HTTP failures, limits and binary response framing. The application
uses a numeric endpoint, explicit trust/peer identity, bounded deadlines and
manual socket/TLS/buffer cleanup. [Server TLS](extended-openssl-tls-server.md)
also passes six native groups and 53 cases, including credential validation,
stable retries and native/allocation cleanup. The explicit unauthenticated
server policy remains available. [Mutual TLS](extended-openssl-mutual-tls.md)
adds required client-chain verification and client credentials through OpenSSL,
with 107 cases across six groups. Required authentication disables resumption
and checks each fresh peer; certificate verification does not assign an
application principal or authorization. Standalone encryption/signature APIs
and certificate trust APIs outside TLS remain work. The
[bounded HTTPS health/echo service](extended-https-server.md) passes 106 cases
across four groups using the shared TLS stream and canonical HTTP codec.
[Prepared client contexts and mutual-TLS HTTPS modes](extended-https-mutual-tls.md)
add 109 process cases across four groups. The client can present an explicit
certificate/key pair while still verifying the server; the service can require
client certificates from an explicit CA file before processing HTTP.
The [remaining native prerequisites](library-native-integration-prerequisites.md)
record those boundaries. Native linking now spools opaque original/replay
sections and supports source packs above one resident unit, while source
snapshots and global metadata still grow with the program. TCP/UDP sockets and
[bounded OS entropy](stdlib-entropy-bounded.md) are also available.
[DER](extended-der.md) and
[X.509 structure parsing](extended-x509.md) provide data inspection; they
do not verify signatures, certificate trust or TLS peers.

Optional modules use the [`extended` source root](../extended/README.md).
[`ext::csv`](extended-csv.md) and [`ext::json`](extended-json.md)
include executable normalizers, generated round trips and allocation-failure
coverage.
[Reusable CSV records and bounded stream writing](extended-csv-write.md)
share the canonical encoder, preflight the complete record and retain exact
accepted-prefix progress. The [column rewrite program](extended-csv-rewrite.md)
selects, repeats and reorders fields while reusing decoder and record storage;
its five native groups cover independent output models, limits, I/O and
allocation failures, plus a 4,096-row resource control. The
[reduced compiler dependencies](library-context-inference-dependencies.md)
retain original failing expressions beside native passing controls.

[Regex splitting and replacement](extended-regex-text.md) reuse the existing
matcher and capture cursor, with borrowed fields, owned literal/template
output and explicit search/output bounds. Six native groups cover independent
reference cases, Unicode and empty-match tables, every reached allocation
failure and a binary stdin/stdout rewrite program. Search work is a
conservative reservation of per-search VM allowances, not a total CPU or I/O
budget.

[Reusable lexical scanning](extended-lexer.md) selects the longest anchored
regex span at each position, with declaration-order ties, borrowed UTF-8
tokens and explicit progress, call and work limits. It shares the canonical
regex engine and validates each input once. Five native groups pass through
separate receipts, including 576 independent model cases, 63 edge tables and
all 120 allocation failures reached by the focused fixtures. Probes still
allocate matcher scratch, and competing patterns can rescan input; this is
not an allocation-free or whole-input linear-time claim.
The [CSV-rules lexer program](extended-lex-scan.md) emits staged token spans or
per-kind counts through bounded native I/O. Its five groups pass, including
124 grammar inputs in both modes, all 60 allocation-failure positions across
the two output modes, injected I/O failures and a measured 4,096-token run.

The [CSV report application](csv-report.md) combines streams, UTF-8 text,
checked decimal parsing, generic collections, CSV and JSON to validate and
group records with executable failure coverage.
