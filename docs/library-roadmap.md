# Standard and extended libraries

The goal is a complete, usable standard library and a broad extended library,
with Lanius interfaces and explicit native bindings for host and third-party
services. This document tracks the whole scope. Completing the first
milestone does not complete the goal.

## Dependency layers

| Layer | Owns | May depend on |
| --- | --- | --- |
| `core` | Values, borrowed views, algorithms, codecs | Compiler intrinsics with explicit target contracts |
| `alloc` | Allocators and owned portable data structures | `core`, allocator bindings |
| `std` | Application interfaces and host services | `core`, `alloc`, explicit host bindings |
| `ext` | Larger optional libraries | The layers above and declared extended-library dependencies |

Allocation-backed collections use `alloc` with explicit failure contracts.
The earlier map, set, byte-vector and UTF-8 owners have been removed after
migrating their consumers. The heap migration has a compiler dependency; the
old `std::vec` path also remains part of the verified compiler's extraction
contract. Do not add
forwarding modules solely to preserve internal paths. Extended modules can use
an additional source root in this repository;
package distribution is a separate deliverable.

## Standard library scope

| Family | Required contents | Executable state and remaining work |
| --- | --- | --- |
| Fundamental values | Option, Result, ordering, comparison, hashing, cloning, explicit errors | Generic Option/Result execute; partial equality/order are distinct from total equality/order, with explicit total float keys. Explicit TryClone/Destroy protocols, String implementations and opt-in exact scalar/Option/Result/Pair compositions execute with typed errors and manual memory-owner release. True empty Infallible errors retain the existing enum tag layout; nested owners and typed rollback pass executable tests. Some generic forwarding and record extraction compositions remain compiler dependencies; automatic ownership and implicit derive/move/drop remain |
| Numbers | Every primitive width, checked/wrapping/saturating arithmetic, conversions, bit operations, floating-point utilities | Canonical primitive-width arithmetic, bits and conversion policies execute; seven obsolete number/byte helper modules are removed and their ordinary consumers migrated. Pointer widths explicitly describe x86_64. Binary32/binary64 bit, rounding, square-root, decimal and precision-formatting APIs execute, as do full-range binary64 elementary functions with documented accuracy evidence. Native floats use partial comparison with explicit total keys. Represented two-word values remain an explicit separate API |
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic algorithms and counted View values execute, including subviews, checked mutations and cursors; initial physical counts still require compiler length projection |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | The shared fused Iterator<T> protocol executes for canonical slice/chunk/window cursors, full-domain i32 ranges, fixed-capacity Vec/Set, owned Vec/deque/heap/hash/tree map/set cursors, bitsets, Text bytes/scalars and text splits. Borrowed take/chain/map/zip/filter/filter_map/skip/take_while/skip_while, checked u64 enumeration, searches, boolean consumers and ordinary/fallible left folds execute with explicit effects and shallow cleanup. Recoverable one-item lookahead, relative/MAX position search and ordinary/custom extrema execute with explicit first-minimum/last-maximum tie policies. Bounded fallible transfer collects into fixed/owned Vec, deque, hash/tree maps and sets, and Min/Max heaps, returning rejected items and accepted-prefix progress. Map/set sinks reject duplicates while preserving stored representatives. Separate native models cover cursor state, selection/copy/callback order, short circuits, transfer recovery and source resumption; owner traces check allocation behavior. Range-dot, window-report, column-sum/extrema, word-sort and identifier-index programs exercise composition and errors. Owning Vec/deque/hash/tree map/set and heap cursors transfer cleanup authority, retain exhausted backing until explicit finish, and recover valid remaining collections in O(1), with explicit nested cleanup. Hash traversal is unordered; tree and heap priority pulls use O(log n) removal. The unique-word application now publishes through the TreeSet owning cursor. Further adapters/consumers, replacement sinks, other owning cursor families and language for-loop integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed String, borrowed Text, scalar/word iteration, join/repeat, integer/float conversion, caller-buffer Display, runtime format strings and owned formatting execute. Alignment counts scalars and numeric precision rounds exact binary values. Optional extended modules provide Unicode 17 full casing, normalization, default word/grapheme boundaries and an explicit terminal width policy. Runtime formats also render to generic byte writers through bounded caller scratch, with preflight validation, exact accepted-prefix failures and a direct-call limit. Richer format controls and collation remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings, raw views and stable chunked arenas with generic typed allocations execute. [Fallible View cloning](stdlib-clone.md) constructs independent String/user-record memory owners and releases completed destination elements on error. Layout consolidation, compiler-enforced lifetimes and automatic destruction remain |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Borrowed-owner alloc Vec, deque and bitset, inline generic Vec/Eq Set, hash/tree maps and sets, and min/max heaps execute. Owned sets include representative ownership and all four fallible algebra operations through shared map engines. Explicit TryClone/Destroy View cloning now composes through nested Vec types with independent owners, typed error layers and recursive cleanup. Opt-in deep HashMap cloning executes with independent nested owners and typed key/value failure cleanup; opt-in recursive deque cloning also executes with logical ring and owned-error rollback coverage. Opt-in deep heap cloning also executes with Min/Max priority and nested/owned-error failure coverage. Opt-in deep TreeMap cloning also executes with sorted staging, independent nested owners, typed key/value rollback and empty/zero-sized coverage. Existing inherent collection clone methods retain shallow entry/key/value copies. Silent-failure legacy map/set/text owners are retired. Opt-in deep HashSet and TreeSet cloning also execute with typed rollback and representative-preserving models. The protected std::vec/heap migration, additional owner compositions and automatic ownership remain |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, stdin/stdout/stderr, errors | Shared traits, cursors, owned sinks, descriptor/file adapters and reusable multi-descriptor readiness execute. Polling preserves old publication on errors and uses explicit observed deadlines. Imported/nested generic Read/Write transport passes native contracts and checked cache reuse. Fixed-capacity buffered adapters execute with read-ahead/pending handoff, explicit finish/discard, partial-I/O and allocation failures, nested composition and a binary-copy application. Runtime writer formatting shares these contracts and leaves flush/finish explicit |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Owned files and paths, lexical operations, checked mutations, configurable/relative opens, seek/resize, metadata, sync, duplication, raw directory iteration and bounded anchored walking execute on native Linux. Bounded copying checks descriptor capabilities and inode aliases before truncation, preserves progress on error and tests actual EOF even for zero-size pseudo-files. Real copy and directory-report applications check output and cleanup. Automatic owner destruction and broader platform support remain |
| Processes and environment | Arguments, environment, working directory, subprocesses, pipes, exit status | Raw-byte snapshots, explicit argv/environment/PATH/cwd, fork/exec, redirected files, owned pipes, cached waits and child signaling execute on the documented single-threaded Linux profile. Bounded concurrent stdin/stdout/stderr capture preserves partial progress, startup certainty and child ownership across errors. Process groups and concurrent spawn policy remain |
| Time and randomness | Duration, instant, system time, deadlines, deterministic generators, OS entropy | Typed nanosecond arithmetic, calendars, native clocks, deadline waits, deterministic generators, sampling/shuffle and checked OS entropy execute. Optional TZif/POSIX zones provide conversion and ambiguity candidates; four continuous and four discrete distributions have bounded generic sampling and explicit numerical domains. Additional clocks and distribution families remain |
| Networking | Addresses, sockets, TCP, UDP, resolution, deadlines, explicit host errors | Numeric IPv4/IPv6 and CIDR values, owned TCP/UDP, polling, deadlines, options and half-close execute via the Linux boundary. Optional DNS transport queries explicit numeric servers with correlated UDP/TCP fallback; bounded cleartext HTTP/1 client and staged server connections use explicit transport, deadlines and resource limits. Real TCP/DNS/fetch/local-service programs exercise transfers. Checked native C calls, OpenSSL digests and client TLS with peer verification execute. Client TLS requires explicit peer trust/identity, borrowed nonblocking sockets and caller deadlines/SIGPIPE policy; the TLS stream/HTTPS application executes 62 cases across four groups with numeric endpoints, explicit trust/identity, deadlines and manual cleanup. Server TLS and a bounded HTTPS service execute through OpenSSL. Client credential contexts and required fresh client-chain verification execute in 107 cases across six groups; prepared-context transport and real mutual-TLS HTTPS modes execute another 109 cases across four groups. Unauthenticated public service remains an explicit policy. Application identity/authorization, broader certificate APIs, system resolver/NSS/interface policy, concurrent server scheduling, keepalive and broader client policies remain; old std::net declarations remain unbound |
| Native libraries | Checked C signatures, ordinary ELF linking, process startup and explicit library owners | The Linux x86_64/glibc profile executes integer/pointer/f32/f64/void calls with up to 32 total parameters, independent SSE/GPR banks, ordinary ELF objects and CRT startup. OpenSSL EVP digest contexts and a binary stdin hashing program execute with dynamic libcrypto.so.3. SQLite database/prepared-statement owners and a persistent binary key/value program execute with system SQLite, including typed values, transactions, real persistence/locking, native and staging-allocation failures, and a measured bulk workload. Native entry/package builds spool original/replay payloads and execute above the resident aggregate threshold; source snapshots/global metadata still grow and descriptor CLI modes remain unsupported. OpenSSL client TLS with peer verification executes with 34 cases across four groups. Server TLS also executes with 53 focused cases; mutual TLS adds 107 cases across six groups using shared native credential loading and explicit required-peer policy. Callbacks, variadics, aggregate C layouts, foreign thread entry, standalone encryption/signature and broader certificate-trust APIs remain |
| Concurrency | Threads, joining, synchronization, atomics, channels, cancellation | Current thread module is contract-only; runtime prerequisites remain |
| Development | Assertions, test runner, property helpers, benchmarks, diagnostics, API docs | Nontrapping checks, explicit source suites, filters, seeded properties, injected/native-clock benchmarks and a bounded native compiler/run driver execute. Selective, relocatable source bundles use the existing package resolver and verify inventory hashes. A generated declaration reference links signatures, bounds, source locations and reviewed contract guides. Automatic compiler discovery/runtime registration, binary SDK distribution and complete semantic API documentation remain |

## Extended library scope

Each entry needs a public API, executable implementation, examples, failure
tests, target support, and relevant performance evidence.

| Family | Deliverables |
| --- | --- |
| Data formats | JSON, CSV, TOML, binary serialization, schema/validation utilities |
| Text and parsing | Unicode properties and normalization, regex, lexers, parser utilities, diff and patch |
| Files and packaging | Globs, directory walking utilities, compression, archives |
| Network protocols | URL handling, HTTP client/server, WebSocket request/frame processing, DNS and client TLS with peer verification through OpenSSL; TLS stream/HTTPS executes with numeric endpoints and explicit trust/deadlines/manual ownership; server TLS, required mutual TLS and bounded health/echo HTTPS modes execute; concurrent scheduling, application authorization and broader orchestration remain open |
| Storage | Database interfaces; executable [SQLite integration](extended-sqlite.md), [persistent binary key/value application](extended-sqlite-kv.md) and key-value snapshots; broader database/storage interfaces remain |
| Security | Native-library cryptographic digests, encryption, signatures, certificate trust and TLS; OpenSSL EVP digests, verified client/server TLS and mutual TLS execute with explicit trust and manual owners; standalone encryption/signature APIs, application identity/authorization and broader certificate policy remain open |
| Mathematics | Big integers, decimal arithmetic, statistics, linear algebra, geometry |
| Application utilities | CLI parsing, logging, configuration, tables, progress reporting |
| Media | Image codecs, pixel operations, audio codecs and signal utilities |

The [compiled byte-glob module](extended-glob.md) and its streaming path-filter
application execute on x86_64 Linux, including recursive components, explicit
work limits, raw byte paths and allocation/I/O failures. [Raw directory iteration
and anchored walking](stdlib-directory.md) now execute separately, with a
filtered directory-report program and explicit traversal budgets.

[Checked filesystem mutations](stdlib-filesystem.md) provide allocation-free
creation/removal of one directory, file unlinking and renaming over existing
host bindings. These operations retain Linux errors and do not recursively
traverse paths.

[Borrowed URI parsing](extended-uri.md), [component percent coding](extended-percent.md)
and a [component-extraction application](extended-uri-component.md) execute on
x86_64 Linux. Parsing validates generic RFC 3986 syntax while preserving encoded
spelling; decoding is an explicit later operation.
[Owned URI resolution and recomposition](extended-uri-resolve.md), including
RFC dot-segment removal, execute with a [command-line resolver](extended-uri-resolve-program.md).
Scheme-specific URL handling and network protocols remain separate work.

[Raw DEFLATE encoding](extended-deflate.md), [raw decoding](extended-inflate.md)
and [owned zlib/gzip containers](extended-compression.md) execute with a
[binary stdin/stdout application](extended-compress-bytes.md). The decoder
accepts stored, fixed and dynamic trees; the fast encoder selects fixed Huffman
LZ77 or smaller stored blocks. Gzip headers, concatenation and checksums are
validated. [Adler-32](stdlib-adler32.md) provides the portable zlib checksum.
Preset dictionaries and resumable codec state remain separate work.
Native and compiler performance is recorded in
[compression performance](extended-compression-performance.md).

[POSIX ustar archives](extended-tar.md) and
[classic single-disk ZIP archives](extended-zip.md) provide executable archive
profiles: metadata, member data, multi-member writing and explicit format,
capacity, checksum and resource failures. Binary
[TAR/gzip](extended-tar-bytes.md) and [ZIP](extended-zip-bytes.md) applications
exercise creation, listing and exact member reads; ZIP also exposes complete
payload verification. They do not perform filesystem extraction. GNU/PAX TAR
extensions, ZIP64, encrypted and multi-disk ZIP remain unsupported and report
explicit errors. [Archive compilation evidence](extended-archive-performance.md)
and the application docs record target support and scale measurements.

[CBOR wire events](extended-cbor.md) provide binary serialization for all major
types, full-width integer arguments, exact float bits, tags, arbitrary map keys
and definite/indefinite structures. The iterative codec uses caller scratch,
strict UTF-8 and explicit resource bounds. A [ZIP manifest program](extended-zip-manifest.md)
checks all archive payloads, then emits CBOR with exact raw byte names.
CBOR application schemas and tag-specific semantics remain separate work.
The [foundation compilation measurements](library-foundation-performance.md)
record executable import workloads for arenas, network values, CBOR, floating
conversion, exact decimal numbers and JSON validation.

[JSON validation](extended-schema.md) implements a documented JSON Schema
2020-12 profile with exact numbers, structural equality, local references,
combinators, objects, arrays and Unicode scalar lengths. Unsupported keywords,
dialects and reference forms fail explicitly. The
[json-check program](extended-json-check.md) validates a file-supplied schema
against stdin, with resource, allocation and I/O failure evidence.
[Borrowed decimal numbers](stdlib-decimal-number.md) retain arbitrary coefficient
and exponent precision for comparison/integer/divisibility behavior.
[Owned unsigned integers](extended-big-uint.md) and
[signed integers](extended-big-int.md) supply arbitrary precision arithmetic,
radix conversion, division, shifts, bitwise operations, powers and GCD, with
explicit limits, ownership and allocation failures. A
[streaming calculator](extended-bigcalc.md) executes twenty operations across
multiple radices. [Owned finite decimals](extended-decimal.md) add arbitrary
precision coefficients, quantum-preserving exact arithmetic, explicit rounding,
precision-limited division, conversions and lawful numeric keys. A
[CSV ledger](extended-decimal-ledger.md) calculates rounded line subtotals,
taxes and running totals without binary floating point. Signed decimal zeros,
NaNs/infinities, transcendental decimal functions, additional number-theory
algorithms remain separate work.

[Statistics](extended-statistics.md) provides checked streaming moments,
covariance/correlation, simple linear fits, compensated sums, scaled norms and
all nine standard sample-quantile formulas. [Linear algebra](extended-linalg.md)
provides counted strided matrices, owned matrices, products, pivoted LU and
Householder QR least squares, with explicit numerical and resource limits.
The [numerical CSV analyzer](extended-data-analyze.md) combines both libraries
for summaries and optional multiple regression. These are binary64 APIs;
weighted/higher moments, advanced decompositions and sparse matrices remain
work. [Normal, exponential, gamma and beta distributions](extended-distributions.md)
add densities, paired tails and bounded generic sampling, with a
[CSV sampling program](extended-sample-distribution.md). Their ordinary and
large-shape accuracy profiles are explicit.
[Bernoulli, binomial, geometric and Poisson laws](extended-discrete-distributions.md)
add masses, paired/log tails and bounded generic sampling, with a
[count simulation program](extended-sample-counts.md). Only Bernoulli claims
an exact dyadic law; the other samplers have explicit finite-grid numerical
contracts, and ordinary/large evaluator accuracy profiles remain separate.
Geometry, elementary functions and signal algorithms
are documented below.

[Owned bitsets and counted views](stdlib-bitset-owned.md) add checked bit/range
edits, searches, shifts, set algebra, cursors and explicit allocation failures.
The [prime sieve](stdlib-primes.md) exercises them through twenty million
candidates. Calendar values also supply lawful comparison/hash traits for
generic ranges, sorting and collection keys; civil ordering and offset
representation equality have separate documented contracts.

[Unicode 17.0.0 properties](stdlib-unicode.md) cover the full code point range
for the documented property set and simple/default/Turkic scalar mappings.
[NFC/NFD/NFKC/NFKD normalization](extended-unicode-normalize.md) and
[default extended grapheme segmentation](extended-unicode-graphemes.md)
execute with static generated tables and official conformance corpora. A
[text-normalization program](extended-text-normalize.md) handles bounded UTF-8
stdin and optional scalar/grapheme statistics, including binary NUL and
allocation/I/O failures. [Default word boundaries](extended-unicode-words.md)
and [full root/Turkic/Lithuanian casing](extended-unicode-case.md) now execute,
including original-input context and default title boundaries. A
[casing program](extended-text-case.md) exposes lower/upper/title/fold over
bounded UTF-8. [Default sentence boundaries](extended-unicode-sentences.md) and
[default line opportunities](extended-unicode-lines.md) now pass the complete
versioned official corpora. [Sentence reporting](extended-text-sentences.md) and
[greedy terminal wrapping](extended-text-wrap.md) exercise them in real programs.
Locale-sensitive collation, dictionary segmentation and shaping remain work.

[Regular expressions](extended-regex.md) execute a documented UTF-8 dialect
using ordered Pike matching, with captures, greedy/lazy repetition, scalar
classes and Unicode 17 properties. Unsupported syntax fails explicitly. A
[streaming search program](extended-text-grep.md) compiles once and processes
bounded UTF-8 records with counts, numbering and inversion. Wider regex syntax
and additional replacement interfaces remain.
[Bounded splitting and replacement](extended-regex-text.md) now provide
borrowed fields, independent literal/numeric-template output and conservative
aggregate VM allowances through the existing matcher. Six focused native
groups pass, including 288 independent reference cases, 89 edge tables,
allocation-failure cleanup and a binary rewrite CLI.
[Reusable lexical scanning](extended-lexer.md) now shares the regex engine's
anchored longest-prefix mode. It validates each input once, returns borrowed
tokens, chooses the earlier rule for equal longest spans and rejects
nonprogress, unmatched input and exhausted caps explicitly. Five native groups
pass through separate receipts, including 576 independent model cases, 63
edge tables and all 120 allocation failures reached by the fixtures. Scratch
is allocated per probe; competing patterns can rescan suffixes, so callers
retain explicit input, search-call and reserved-work limits.
The [CSV-rules lexer application](extended-lex-scan.md) composes CSV decoding,
compiled rules, borrowed tokens, hash counters and staged bounded output. Its
five native groups pass through separate receipts, including both modes over
124 independent grammar inputs, all 60 reached allocation-failure positions,
exact I/O fault injections and a 4,096-token cost observation. The retained
[generic Read context dependency](library-context-inference-dependencies.md)
has a rejected unannotated reduction and an executed explicitly typed control.
[Text parsing cursors](extended-parse.md)
provide checked locations, spans, checkpoints and atomic bounded scanners.
The [integer expression calculator](extended-expr-calc.md) combines them with
inline stacks, checked arithmetic and runtime formatting.

[Shortest line edit scripts](extended-diff.md) and
[strict unified patches](extended-patch.md) compare arbitrary bytes and apply
changes exactly in memory, with explicit trace/work limits, conflicts and owner
cleanup. The [file comparison and patch program](extended-text-patch.md) emits,
applies and checks single-file patches through real files and stdin/stdout.
Filesystem patch orchestration and additional diff granularities remain.

[Runtime format strings and owned formatting](stdlib-format-strings.md) add
typed positional/named arguments, scalar fill/alignment/truncation, signed radix
controls and exact [float precision formatting](stdlib-float-precision.md).
Unsupported syntax fails explicitly. [Inline collections](stdlib-fixed-capacity.md)
now use explicit Full/Bounds/absence outcomes, return displaced elements and
use lawful full equality for sets. Borrowed free functions preserve symbolic
element and capacity parameters. Imported method lookup with symbolic capacity
has a reduced compiler dependency and successful controls. [Owned sets](stdlib-owned-sets.md)
now execute through shared map owner-state boundaries; the older nested wrapper
failure is preserved separately from the production support claim.
A general Display-to-owned-String helper also remains excluded after a minimal
compiler failure; typed owned formatting executes independently. The
[dependency record](library-dependencies.md) preserves the exact contexts.

[Native 64-bit and pointer-sized integers](stdlib-native-integers.md) provide
checked, wrapping and saturating arithmetic, division, shifts, bits and all
integer-width conversion policies. Native tests compare 84,100 cases with each
independent Rust/i128 and Python bigint reference and check 54 strict traps.
The [source test workflow](stdlib-development.md) adds explicit suites,
nontrapping checks, deterministic properties and actual benchmark measurement.
It does not claim compiler discovery or trap recovery. The repository's
stdlib-heavy workload generator now uses the same borrowed collection APIs;
default, string-heavy and directed record mixes execute against its model.

[Collection consumer migration](stdlib-legacy-collections.md) removes ten
silent-failure owner/specialization modules and moves fifteen programs to
checked alloc owners or bounded storage. The [standard library entry guide](../stdlib/README.md)
and [extended module index](../extended/README.md) expose current module paths.

[Exact planar geometry](extended-geometry.md) handles full-i32 predicates,
segments, rings and hulls, with finite floating vector/affine utilities. A
[CSV hull program](extended-shape-hull.md) exercises exact topology and area.
[Terminal width policy](extended-terminal.md), [tables](extended-table.md) and
[progress rendering](extended-progress.md) supply bounded Unicode-aware output;
a [CSV table program](extended-csv-table.md) integrates them. Width is an explicit
policy rather than a universal terminal measurement.

[Image buffers](extended-image.md) and [PNG codecs](extended-png.md) provide
checked RGBA operations, all standard input color/depth combinations, Adam7,
filters, CRC/order validation and RGBA8 encoding. A
[PNG transformation program](extended-image-tool.md) exercises crop, rotation
and flips. [Finite audio](extended-audio.md) and [WAVE codecs](extended-wave.md)
provide PCM/IEEE/extensible conversion, exact mean/DC/mono behavior, scaled RMS
and checked signal operations through a [WAVE program](extended-wave-tool.md).
[Signal processing](extended-signal.md) adds checked complex values, radix-2
FFT/inverse, windows, convolution and spectral bins. The
[WAVE spectrum program](extended-wave-spectrum.md) combines downmixing, optional
FIR smoothing and windowed FFT into CSV. Color management, other image/audio
formats, playback and additional signal algorithms remain work.

[HTTP/1 wire processing](extended-http.md) implements requests/responses,
framing, chunk extensions/trailers, exact boundaries and checked writers. Its
[offline message program](extended-http-message.md) validates and decodes real
wire bytes. An [allocation-free incremental cursor](extended-http-cursor.md)
finds boundaries without retaining views into growing storage. The
[connected HTTP/1.1 client and fetch program](extended-http-client.md) compose
it with numeric-address sockets, owned responses, one deadline and explicit
byte/work/I/O limits. Canonical parsing validates each selected response;
informational responses and early final replies retain exact association and
progress. A [staged HTTP/1 server connection](extended-http-server.md), accepted
at `493d4e87`, handles one request and one closing final response per connection,
with immutable published head/body views, explicit 100 Continue, checked Date
and response staging, one deadline, quotas and half-close/drain cleanup. Its
real local health/echo service accepts numeric IPv4/IPv6 endpoints and bounded
sequential connections. Independent peers and injected resource/host failures
exercise framing, early rejection, binary bodies and owner cleanup. A separate
[HTTPS service](extended-https-server.md) now composes the same codec with
OpenSSL server TLS, shared buffered streams, bounded acceptance and one absolute
deadline per connection slot. Automatic resolution/redirects, connection pooling, server keepalive/concurrent
scheduling, upgrades/tunnels and HTTP/2 remain work.

[DNS wire processing](extended-dns.md) validates binary names, compression,
QUERY sections, common RDATA and EDNS, with bounded complete message writing.
[WebSocket processing](extended-websocket.md) provides RFC 6455 request processing,
role masking, fragmented UTF-8, control/close state and frame generation.
Both have real offline programs and independent interoperability/failure tests;
host resolution and their protocol-specific TLS/transport orchestration remain
separate work.
The [owned socket API](stdlib-sockets.md) and [TCP exchange program](stdlib-tcp-exchange.md)
provide executable numeric-address TCP/UDP transport independently.
[DNS transport](extended-dns-client.md) now adds explicit-server queries, fresh
connected UDP attempts, fixed retry windows, full-question correlation and one
framed TCP fallback, with a real DNS query program. Independent loopback peers,
late-success deadline tests and allocation/host faults verify the implemented
profile. This supplies neither system resolver/NSS policy nor DNS authentication.

[Byte key/value storage](extended-kv.md) provides atomic owned mutations and
canonical CRC-checked snapshots. Its file program stages replacements through
a caller-provided disposable sibling path. Its crash durability, locking and
transaction contracts remain open. A separate native
[SQLite adapter](extended-sqlite.md) and
[persistent binary key/value application](extended-sqlite-kv.md) now execute on
Linux x86_64/glibc, including real database files, transactions, write locks and
explicit native failure recovery. Their
[staging allocation gate](extended-sqlite-allocation.md) verifies all four
reached packing failures and exact mapping release.
[Persistent indexed ZIP snapshots](extended-archive-index.md) now compose
ZIP and SQLite: the archive-index program imports, lists, gets and exports exact
saved bytes. Its seven native groups cover binary names/keys, duplicate names,
independent snapshot owners, complete CRC preflight, pinned catalog validation,
explicit uncertain transaction outcomes, limits and allocation/native faults.
Filesystem extraction and broader archive formats remain work.

[Narrow primitive integers](stdlib-narrow-integers.md) now match the canonical
native-width policy families, with exhaustive byte arithmetic and independent
big-integer references. [Elementary binary64 functions](stdlib-math.md) include
full-range argument reduction and explicit IEEE behavior, checked against
high-precision independent references. These are Lanius implementations, with
licensed algorithm provenance retained in source.

[TOML 1.1.0](extended-toml.md) supplies owned typed documents and deterministic
encoding, with the complete versioned official valid/invalid corpus and resource
failure evidence. A [normalizer/checker](extended-toml-normalize.md) preserves
types, exact temporal fractions, negative zero and unknown offsets. Configuration
overlays include a [common typed settings facade](extended-settings.md) over
JSON, TOML and explicit/environment bindings. It preserves exact JSON numbers,
TOML types, shallow replacement and provenance without copying the input trees.
[Calendar values](stdlib-calendar.md) provide checked Gregorian day/ordinal/ISO
week arithmetic, RFC 3339 parsing/formatting and explicit SystemTime conversion.
[TZif time zones](extended-timezone.md) add historical offsets, supported POSIX
future rules and complete local-time ambiguity candidates with an inspection
and conversion program. Leap-bearing files and overlapping annual rule streams
fail explicitly; certified leap-second placement needs separate data/services.

[Selective source distribution](library-distribution.md) copies only the package
resolver's reachable closure, retains notices and verifies a sorted hash
inventory. Relocation tests delete the original source package and execute the
bundled calculator. Binary SDK installation, registry publishing and complete
semantic API documentation remain open. The
[generated declaration reference](library-api-reference.md) now inventories all
standard/extended source modules with deterministic source links and reviewed
guide mappings. Its unregistered-guide list makes documentation gaps visible;
it performs no compilation or execution verification.

For external formats and algorithms, use their primary specifications and
published conformance vectors. Choose exact versions and formats when starting
each family. Host and third-party integrations need explicit dependency and
availability contracts; do not substitute success-shaped placeholders.

## Delivery sequence

1. **Text and data foundation.** Packed byte buffers, owned UTF-8 strings,
   text operations, parsing, formatting, writer/reader contracts, hash maps,
   CSV and JSON. Acceptance application: read CSV, validate and group records,
   then emit JSON, including malformed-input and I/O failure cases.
2. **Everyday programs.** Iterators, remaining collections, files and paths,
   arguments, configuration, logging, clocks and randomness. Acceptance
   application: a directory report with filters and structured output.
3. **Connected programs.** Runtime bindings for sockets, processes and threads;
   HTTP, URLs, cancellation and synchronization. Native C ABI/linking support
   precedes established-library TLS and database bindings. Acceptance applications:
   a bounded concurrent downloader and a local HTTP service.
4. **Storage and packaging.** Database integration, key-value storage,
   compression, archives, binary serialization and schemas. Acceptance
   application: a persistent indexed archive with checked round trips.
5. **Text, mathematical and media libraries.** Complete the remaining extended
   families with representative applications and their conformance suites.
6. **Distribution and completion audit.** Document installation and imports,
   verify selective dependencies, target support and compile-time scaling,
   and audit every row above against executable evidence.

Families can proceed independently once their dependencies have working
contracts. A compiler defect should have a minimal reproduction and an affected
API list; unrelated library work can continue.

[Checked C ABI calls and native linking](library-native-c.md) now execute on
Linux x86_64/glibc. [OpenSSL EVP digest contexts](extended-openssl-digest.md)
and the [binary stdin hashing program](extended-openssl-hash.md) use that profile
for SHA-256, SHA-512, SHA3-256 and SHA3-512. Native libraries perform all
sensitive operations; no Lanius, Rust or Python production implementation of
the cryptographic algorithms is introduced. C `f32`/`f64` calls now execute
with independent SSE/GPR register banks, exact IEEE transport and mixed
32-parameter stack/alignment coverage. An owned
[SQLite adapter](extended-sqlite.md) and
[persistent binary key/value program](extended-sqlite-kv.md) execute through
system SQLite, with typed values, transaction models, persistent files, native
locks and failure cleanup. Their guides record the completed gates and the
measured 32,768-insert/indexed-read workload.
[Client TLS with peer verification](extended-openssl-tls.md) now executes through OpenSSL 3,
with 34 cases across four groups for trust/identity, binary transfer,
closure/truncation and stable retries. [Server TLS](extended-openssl-tls-server.md)
also passes six groups and 53 cases, including explicit unauthenticated-client
policy, credential loading and native/allocation failure cleanup. Mandatory
client trust/identity rejection still passes after introducing session roles.
[Mutual TLS](extended-openssl-mutual-tls.md) now adds 107 cases across six
groups: client credentials, required fresh client-chain verification, purpose,
trust, stable retries and native/allocation cleanup. Required servers disable
resumption; certificate verification does not assign application principals or
permissions. Standalone encryption and signature APIs, and certificate trust
APIs outside TLS remain work. The
[TLS stream/HTTPS application](extended-https-fetch.md) also executes 62 cases
across four groups on Linux x86_64, using numeric endpoints, explicit trust and
identity, deadline/resource limits and manual owner cleanup. The
[prepared-context connector and mutual-TLS HTTPS modes](extended-https-mutual-tls.md)
add 109 process cases across four groups, including real client/server pairs
and failures before HTTP publication. The
[remaining native prerequisites](library-native-integration-prerequisites.md)
include callbacks and foreign threads. Native entry/package linking now spools
opaque sections and executes above one resident unit, while source snapshots
and global metadata remain resident. TCP/UDP,
OS entropy and noncryptographic CRC/Adler/FNV are also available.

## Completion requirements

- Public APIs perform their documented work. Unsupported operations fail
  explicitly and are excluded from executable support claims.
- Bounds, overflow, invalid encoding, allocation failure, partial I/O and
  resource lifetime have documented behavior and runtime tests.
- Tests import the real modules, compile Lanius programs, and execute them.
  Type checking alone is insufficient. Collection tests compare operation
  sequences with a reference model; format tests include malformed inputs.
- Every family has a real application using several of its modules.
- Target support is recorded per module. The initial executable target is
  x86_64 Linux; Wasm claims need separate execution evidence. Running the
  compiler on a GPU does not establish user-program GPU execution.
- Measure relevant operations and representative large-library compile
  workloads with the repository's performance tools. Keep each command below
  two minutes and avoid unrelated GPU test reruns.
- Portable algorithms and library interfaces use Lanius. Host and third-party
  services use explicit native bindings with executable ABI/linking contracts.
  Rust/Python may drive tests; JSON transport, subprocess serialization and Wasm
  bridges do not establish native library integration.

## Current work

- Branch: `codex/stdlib`; the full library goal remains open.
- [Anchored longest-prefix matching and reusable lexers](extended-lexer.md)
  pass five native groups through separate receipts: full-context model cases,
  assertion/capture/error tables, construction/input caps and exact owner
  cleanup at all 120 allocation failures reached by the fixtures. Ordinary
  regex matching retains its prior semantics; both existing groups pass again
  in 9.70 s. The [CSV-rules lexer program](extended-lex-scan.md) passes all five
  groups: its 124-input/two-mode matrix in 8.40 s, error/scripted-I/O/resource
  groups in 14.16 s, and both 30-position OOM campaigns plus I/O faults in
  8.36 s. The 4,096-token run made 36,887 allocations with balanced releases;
  reusable matcher scratch remains a useful performance improvement. Fixture
  and harness corrections preserve exact syntax-error offsets and bounded
  failure-path allocation cleanup. The app uses explicit I/O result types;
  the reduced inference failure remains documented, with no compiler changes.
- [Regex split/replacement adapters and stdin rewrite CLI](extended-regex-text.md)
  pass six focused groups through separate GPU-compile/native receipts. The
  existing Matches cursor supplies captures and empty-match progress. Tests
  cover 288 independent nonempty reference cases across checked axes and three
  layouts, 89 explicit edge tables, all 77 reached library allocation failures,
  24 CLI cases, all 43 reached CLI allocation failures and four I/O schedules.
  Output owners and borrowed fields have explicit manual lifetimes; aggregate
  search work reserves VM allowances rather than counting all CPU work.
- [Reusable CSV construction and bounded stream writing](extended-csv-write.md)
  execute through the shared canonical encoder, with complete preflight,
  accepted-prefix errors and explicit output/write-attempt limits. All five
  groups pass via separate receipts, including six staged-growth allocation
  failures and 4,096 allocation-free record reuses. The
  [column rewrite program](extended-csv-rewrite.md) also passes five groups:
  62 independent output cases, 88 limit cases, 11 real I/O cases, scripted
  production-helper scenarios and allocation/resource controls. Its 4,096-row
  run retains the one-row allocation count and peak storage. The
  [compiler dependencies](library-context-inference-dependencies.md) preserve
  failing unannotated result contexts and nested/literal matching beside
  passing controls; no compiler source changed in this batch.
- Accepted client TLS profile: [ext::openssl_tls](extended-openssl-tls.md) uses
  OpenSSL 3 `libssl`/`libcrypto` for all TLS and sensitive operations. Fifteen
  verified transfer/identity cases pass in 18.56 s; seven closure/truncation
  and three stable-retry cases pass in a shared 18.01 s run whose separate
  legacy verification fixture initially failed. After correcting the test
  peer's fatal-alert flush and establishing a real TLS 1.1 CPU control, all
  nine verification-rejection cases pass independently in 16.73 s. Production
  TLS source is unchanged across those gates. The guide records each receipt,
  mandatory trust/identity, borrowed nonblocking sockets, manual ownership,
  caller deadlines and SIGPIPE policy. This covers 34 cases across four groups,
  with no single all-green suite receipt claimed. The
  [TLS stream/HTTPS application](extended-https-fetch.md) passes all four groups
  in 14.44 s: 4 stream, 14 verification/HTTP-failure, 26 limit and 18 binary/
  framing cases, recorded in `target/stdlib-work/https-fetch-execution-current.log`.
  Numeric endpoints, explicit trust/identity, deadlines and manual ownership
  remain the supported scope. Server TLS and the HTTPS service have separate
  passing gates below; mutual TLS has since advanced in its separate gates.
  The full security family remains open.
- Accepted [opt-in deep HashMap cloning](stdlib-clone-hash-map.md): four native
  groups pass on Linux x86_64 through the GPU compiler. The independent nested
  owner contract passes in 7.46 s; the remaining three groups pass in 11.71 s,
  including 14 reached allocation failures, 18 owned key/value errors, six
  identity changes, two defensive cleanup cases, collisions/tombstones and
  empty/zero-sized paths. Ordinary inherent methods retain their shallow
  policy. [Recursive deque cloning](stdlib-clone-deque.md) also passes four
  native groups: contracts in 7.80 s and three model/failure groups in 12.28 s,
  covering 379 logical cases, 13 nested allocation failures, six owned-error
  paths and 33 owned-error allocation failures. [Deep heap cloning](stdlib-clone-binary-heap.md)
  passes all five native groups: contracts in 5.96 s and four model/failure
  groups in 12.01 s, including Min/Max priorities, empty/zero-sized values,
  13 typed allocation failures, 16 owned-error paths and all 96 reached
  owned-error allocations. [Deep TreeMap cloning](stdlib-clone-tree-map.md)
  passes all five active native groups: the contract group in 9.83 s and four
  prerequisite/construction/failure groups in 13.47 s, with the manual probe
  ignored. Coverage includes sorted staging, independent String/Vec owners,
  transfer/reset, empty/zero-sized values, 15 reached clone-allocation failures,
  12 owned key/value errors and three changed-key cases. Two general compiler
  fixes restore local nominal layout through canonical identity and preserve
  checked aggregate widths when fields are zero-sized. The
  [dependency record](library-dependencies.md) describes the exact mechanisms;
  unrelated generic replay reproductions have not been revalidated.
- Accepted [OpenSSL server TLS](extended-openssl-tls-server.md): six groups
  pass 53 cases in 5.98 s, covering credentials and encrypted passphrases
  without prompting, context references, stable retries, closure/truncation,
  12 native fault boundaries and all six reached staging allocations.
  The existing mandatory client trust/identity/protocol gate still passes
  nine cases in 5.98 s. [Shared TLS streams and HTTPS service](extended-https-server.md)
  pass all four server groups: 28 verified exchange cases in 7.17 s and
  78 limit/failure/stream cases in 10.87 s. The existing HTTPS client passes
  all 62 cases again in 13.90 s after the shared ownership change. The service
  uses numeric endpoints, one absolute deadline per sequential connection slot,
  the canonical HTTP codec and an explicit unauthenticated-client TLS policy.
  Mutual TLS has since advanced in separate library and application gates;
  keepalive and concurrent scheduling remain work.
- Accepted [mutual TLS](extended-openssl-mutual-tls.md): six library groups
  execute 107 cases across separate receipts. Native OpenSSL verifies client
  chains/purpose/possession, required servers disable resumption and both roles
  check peer presence after native completion. Shared credential loading
  supports explicit passphrases without prompting. The existing nine-case
  client rejection group and all 53 server cases still pass. The
  [prepared client connector and HTTPS credential modes](extended-https-mutual-tls.md)
  execute 109 process cases across four groups: eight borrowed-context cases
  in 6.21 s and the other 101 cases in 15.23 s. TLS 1.3 local completion is not
  treated as proof that the remote endpoint accepted a client certificate.
  All cryptographic operations use OpenSSL; application principals,
  authorization and broader security interfaces remain work.
- Accepted [scalar and structural cloning](stdlib-clone-values.md): all five
  groups pass in 19.37 s, covering fourteen scalar types, exact IEEE bit
  transport, nested Option/Result/Pair/String/Vec owners, active-only callbacks,
  minimal bounds, 18 callback scenarios, 14 owned errors, all 45 reached
  allocation failures and four actual-call rejections. The
  [empty-enum layout repair](compiler-empty-enum-layout.md) aligns three GPU
  producers with the existing one-word enum tag ABI. The six paired reductions
  and separate raw-stride assertions pass, and four inhabited structural
  controls pass; no separate callee-layout fallback was introduced.
- Accepted deep set ownership: [HashSet](stdlib-clone-hash-set.md) passes
  three native groups in 15.05 s, including 557 sequence/failure/identity cases,
  six owned errors and all 39 reached allocation failures. [TreeSet](stdlib-clone-tree-set.md)
  passes its contract group in 9.61 s and four model/failure/selection groups
  in 10.73 s, including a 512-state ordered model, observable O(n log n)
  construction, nine reached allocation failures and owned-error rollback.
  Both preserve independent String owners and reuse the existing shared map
  engines. Ordinary set methods retain their shallow ownership policy.
- Accepted [persistent indexed ZIP snapshots](extended-archive-index.md):
  the 56-case ownership/binary-name matrix passes in 8.27 s; six remaining
  groups pass in 17.16 s, including 30 corruption cases, 40 limit cases,
  nine native recovery cases, all 29 import and 23 read allocation positions,
  and scripted short I/O. The 1,024-entry workload expands to 8 MiB and saves
  an 8,005,812-byte ZIP: import takes 1.385 s, and count/list/seven gets/export
  take 4.422 s in this one measured run. These are application process times,
  including decompression, validation and native persistence, rather than
  isolated SQLite lookup timings. Dedicated schema, ordinal/raw-byte names,
  all-entry import CRC checks and uncertain transaction recovery are explicit.
- Accepted native object storage: original and generic replay section bytes
  spool privately, exact original admission facts remain intact, and ELF export
  streams one payload at a time. A two-file 6 MiB source pack executes in one
  group in 3.86 s, including private C calls through imported generics, direct
  file output and output-limit preservation. Eighteen exporter/linker CPU tests
  pass in 0.94 s; three storage, two atomic-output and two new facts/metadata
  tests also pass. The combined host build takes 35.42 s. The
  [native guide](library-native-c.md) records receipts and response/diagnostic/
  output limits. Source snapshots and global metadata still grow with the
  program; explicit source-pack descriptor CLI modes remain unsupported.
- Accepted SQLite milestone: the owned [adapter](extended-sqlite.md) and
  [persistent binary key/value application](extended-sqlite-kv.md) execute on
  Linux x86_64/glibc through system SQLite. Lanius supplies interface, staging,
  limits, errors and explicit cleanup. Four ordinary library groups pass in
  14.92 s, including 558 typed-value cases and 640 model commands; all 21 native
  failure modes pass in one group in 9.03 s. The
  [staging allocation gate](extended-sqlite-allocation.md) passes one group in
  8.60 s: baseline plus failures at all four reached path/SQL/text/blob staging
  requests, with retries and mapping/native-owner ledgers. Five application
  groups pass in 17.54 s, covering 99 oracle cases plus scripted stream checks.
  The compiled bulk run performs 32,768 inserts and 32,768 indexed selects in
  51.798074 ms, excluding GPU compilation, with SQLite reporting a 545,848-byte
  allocation high-water mark. Independent aggregate/index checksums match. The
  linked guides record receipts and the metric's limits; the full library goal
  remains open.
- Current accepted C ABI extension: `f32`/C `float` and `f64`/C `double`
  transport through independent SSE8/GPR6 banks, with up to 32 total scalar
  parameters. The native float gate passes one group in 8.03 s, covering exact
  IEEE bits including NaN payloads, mixed register/stack arguments and alignment,
  imported generic replay and live SSE clobbers. Four declaration-contract
  groups pass in 9.77 s, and the eight existing integer/pointer execution groups
  pass in 10.55 s. Two native C semantic-interface CPU tests pass in 0.00 s after
  a 42.45 s test build, checking binding identity/signature round-trip and forged
  or unsupported profile rejection. The compiler build completed in 46.71 s. The
  [native C guide](library-native-c.md) records receipts. Existing scalar IDs
  and ABI metadata represent the extension without an artifact version change.
- Earlier accepted native milestone: [checked C declarations and native linking](library-native-c.md)
  execute on Linux x86_64/glibc, including scalar normalization, register/stack
  arguments through 32 parameters, imported generic replay and CRT startup.
  [OpenSSL EVP digests](extended-openssl-digest.md) and the
  [hashing program](extended-openssl-hash.md) execute with dynamic `libcrypto.so.3`.
  The four focused gates pass 3 declaration groups, 8 native-call groups,
  4 digest groups covering 2,124 cases plus 12 failure modes, and 3 application
  groups. Semantic interface v17 and x86 object v4 require rebuilt artifacts.
  File-backed native linking, callbacks, foreign thread entry, TLS, encryption,
  signatures, certificate trust and SQLite wrappers remained open at that
  checkpoint; the SQLite, client TLS and native storage milestones above supply
  their later execution evidence.
  The full library goal remains open.
- Raw [DER](extended-der.md) and [X.509 structure parsing](extended-x509.md)
  remain useful schema inspection tools. The
  [certificate inspector](extended-certificate-info.md) reports schema metadata without a cryptographic fingerprint or trust decision.
- [Bounded nonblocking entropy](stdlib-entropy-bounded.md) retains one charged
  getrandom attempt per read, explicit partial progress and shared attempt
  budgets. Socket, polling and clock contracts remain separate.
- Previous milestone: runtime formatting to generic byte writers, using the
  existing parser/renderer, bounded scratch, complete preflight before output,
  exact confirmed failure progress and explicit call budgets. Independent
  models, preflight/failure/nested-buffering gates and the real
  [CSV report](stdlib-format-report.md) execute on native x86_64 Linux. The
  preceding owning Vec/Deque cursors transfer cleanup authority and recover
  original storage; their compiler replay dependency remains recorded. The
  complete library goal still includes the remaining families and prerequisites
  listed above.
- Earlier host/integration milestone: the explicit native Linux syscall boundary, owned TCP/UDP
  sockets and signal dispositions; configurable files, metadata, raw directory
  iteration and bounded walking; reusable descriptor readiness and explicit-server
  DNS transport; complete default Unicode sentence/line boundaries and terminal
  wrapping; typed settings and four continuous plus four discrete distributions.
  Real programs, independent models/conformance corpora,
  allocation/descriptor/I/O failure checks and source reviews are recorded per
  guide. Numeric helper consolidation removes seven obsolete modules.
  Subprocesses and a real command runner now pass focused native lifecycle and
  fault gates; startup EOF is explicitly Unconfirmed and ambiguous outcomes
  retain a child owner. Concurrent pipe capture adds byte/work/deadline limits
  and retained failure progress; nonblocking waits make one host attempt.
  Incremental HTTP framing, a connected cleartext client and staged server
  connections now compose owned socket transport, strict final parsing and
  checked binary body publication. The bounded local health/echo service was
  accepted at `493d4e87`; server keepalive/concurrent scheduling and TLS remain.
  Range overlap requires total ordering, with partial-order membership retained.
  Raw host thunks preserve native-width sizes/counts/capacities and validate
  allocator alignments. A private length-derived GPU dispatch emits every
  runtime byte, including the relocated syscall and assertion tail.
  Seventeen ordinary collection/output samples now use
  checked APIs and real closed-pipe cleanup. The heap view boundary constructs
  directly from initialized owner state; original failed source is preserved.
  These APIs execute as x86_64 Linux programs produced by the GPU compiler;
  user GPU kernels and other targets were unverified. Threads, TLS, SQLite,
  generic adapter composition and final distribution/reference work remained
  open at that checkpoint.
  A generated declaration reference covers the current source inventory;
  semantic guide gaps stay explicit. Native thread-entry, memory-ordering and
  remaining foreign-call prerequisites have a separate [boundary guide](library-native-integration-prerequisites.md).
- Preceding milestone: canonical narrow integers, full-range binary64 elementary
  functions, generic owned hash/tree sets, TZif time zones, DNS and WebSocket
  request/frame processing, byte key/value snapshots, signal processing and selective
  source distribution. Five new native programs and four migrated set consumers
  exercise real behavior. Independent models, malformed-input/resource cases,
  allocation/I/O faults and independent source reviews are recorded per guide.
  Supported execution remains x86_64 Linux output from GPU compilation. The
  [host prerequisite audit](library-host-prerequisites.md) names missing services;
  sockets/processes/threads, SQLite, generic adapter composition and final
  distribution/reference/completion work remained open at that checkpoint.
- Preceding milestone: native 64-bit/pointer integers; Lanius source test/property/
  benchmark workflow; legacy collection/text consumer migration; exact geometry;
  terminal tables/progress; PNG/image and WAVE/audio utilities; HTTP/1 wire codec.
  Six real applications integrate these families. Independent reviews found
  and corrected PNG unknown-chunk handling, HTTP 205/CONNECT rules, exact audio
  cancellation and Runner failure-state latching. All target claims remain
  native x86_64 Linux; the whole roadmap, host/database services and distribution
  were still incomplete at that checkpoint; current support is recorded above.
- Preceding formatting/parsing milestone: exact float precision, typed runtime
  format strings and owned String/byte results, inline Vec/Eq Set with explicit
  outcomes and symbolic-capacity borrowed APIs, checked parsing cursors,
  shortest line scripts and strict unified patches. The expression calculator
  and file comparison/patch application exercise these modules with reference,
  resource, allocation and I/O failure evidence. The original nested owned set
  wrappers remain preserved as compiler reproductions; current production sets
  use the shared map boundary described above. A generic
  owned Display convenience also remains outside production: primitive-only
  callers expose a context-sensitive native-layout compiler failure.
- Preceding collections/mathematics milestone: owned/counted bitsets with a
  prime sieve, calendar comparison/hash and collection integration, arbitrary
  precision finite decimals with a CSV ledger, statistics and matrix algorithms
  with a numerical CSV analysis/regression program. Independent models,
  numerical edge cases, aliasing, allocation/I/O failures and measured native
  workloads are recorded in the guides above. The whole scope remains open.
- Preceding configuration/text milestone: TOML 1.1 documents and normalization,
  UTF-8 regular-expression search and a streaming grep program, Gregorian/RFC
  3339 calendar values, and complete Unicode 17 default word boundaries and
  full casing with a command-line converter. Each module/application guide
  names its executable target, contracts, limits and tests. These additions do
  not complete the whole scope above; no compiler/runtime implementation is
  supplied as a library substitute.
- Preceding numeric/text milestone: complete basic BigUint/BigInt arithmetic and
  a calculator; Unicode 17 property/scalar mappings, all four normalization
  forms, default extended grapheme clusters and a normalization program.
  [Comparison contracts](stdlib-comparison.md) reject native float keys/sorts
  and provide bit-preserving total wrappers. New source and data generators
  are committed with executable model/conformance/failure evidence; no compiler,
  runtime, ABI, shader, extractor or proof implementation changed. This is
  progress toward the full scope above, not whole-library completion.
- Scope and API conventions: recorded in this document and
  [library-api-conventions.md](library-api-conventions.md).
- Packed owned UTF-8 string: the first implementation and three executable
  test groups pass on x86_64 Linux, including allocation fault injection and a
  text-processing program. See [stdlib-string.md](stdlib-string.md) for exact
  coverage and remaining String operations.
- Compiler and runtime prerequisites: [library-dependencies.md](library-dependencies.md).
- Floating values: [`core::f32` and `core::f64`](stdlib-floats.md) execute exact
  encoding transfer, classification, signs, neighboring values, total comparison,
  integral rounding and correctly rounded square root. Strict clamping traps
  for invalid bounds; checked and explicit-fallback forms are available.
  [`core::float_decimal`](stdlib-float-decimal.md) parses both widths with exact
  nearest-even rounding and formats shortest round-trip decimal using caller
  scratch. `core::fmt` exposes both widths through Display and atomic appends.
  The [streaming normalizer](stdlib-float-normalize.md) exercises conversion,
  square root, generic formatting, bounded byte records and native streams.
  Native bitwise, halfway, exponent, allocation and I/O tests pass. Elementary
  functions, lawful partial/total float comparison and typed owned formatting
  have since advanced as described above; generic owned Display composition
  and numeric consumer consolidation remain.
- Exact decimal validation: [`core::decimal_number`](stdlib-decimal-number.md)
  implements strict JSON-number parsing, exact comparisons/integer queries and
  divisibility with counted work. Two runtime groups compare 2,525 reference
  pairs, including 8,192-digit inputs; independent review checked 832 additional
  native pairs. [`ext::schema`](extended-schema.md) compiles a supported
  JSON Schema profile into indexes borrowing the immutable JSON owner, then
  validates with caller scratch and no allocation. Its broader vocabulary,
  external schema registries and standard output formats remain explicit future
  work. The full standard/extended library goal remains open.
- Arenas: [`alloc::arena`](stdlib-arena.md) provides stable chunked storage,
  explicit retained/chunk limits, reset/reuse, clear, destruction and generic
  typed value/slice copies using the existing native layout contract. Tests
  exercise all primitive widths, nested records/enums, zero-sized values,
  modeled allocation sequences, allocation failures and large reuse batches.
  The [streaming word-count application](stdlib-arena-words.md) stores each
  distinct byte key once and retains stable views in a generic ordered map.
  Current supported alignment is 1, 2, 4 or 8; over-aligned layouts need a
  pointer/alignment operation recorded in the dependency inventory.
- Network values: [`core::net`](stdlib-net.md) executes strict address/socket
  parsing, RFC 5952 formatting, wire octets, full-width comparison/hashing and
  every CIDR prefix width. The [address filter](stdlib-address-filter.md) uses
  these values with native streams and explicit resource limits. URI parsing
  now reuses these IP parsers; all six existing URI runtime groups pass.
  Numeric TCP/UDP sockets now execute through [`std::socket`](stdlib-sockets.md).
  System resolver/NSS and interface policy remain open.
- Paths: [`core::path` and `alloc::path`](stdlib-paths.md) separate borrowed Unix
  paths and owned buffers from host filesystem services. Component cursors,
  names/extensions, ancestors, prefixes, comparison/hash, joins, atomic edits
  and explicit lexical normalization execute. Tests cover 633 reference pairs,
  4,014 modeled edits, aliased inputs, allocation/write failures, large batches
  and a raw-byte path-joining program. Existing mixed-separator/Windows byte
  rules moved to `core::path_rules` with callers. Direct malformed View-record
  construction has a preserved compiler reproduction and a
  [descriptor-adjustment repair](library-dependencies.md). Host metadata,
  directory walking and the [directory-report application](stdlib-directory.md)
  now execute.
- Time: [`core::time` and `std::clock`](stdlib-time.md) execute normalized
  durations, full-width signed Unix timestamps, monotonic instants, deadlines
  and generic waits with injected or native clocks. Five test groups cover 400
  wide-reference arithmetic cases, simulated interrupts/reversals/long waits,
  native timespec/status fault injection, collection integration, large batches
  and a scheduled JSON-record program. Relative waits preserve the original
  deadline, round up to milliseconds and split requests at the native i32 limit.
  A generic Deadline-factory composition has a reduced compiler reproduction
  and two successful controls; shipped APIs retain their generic interface.
  Other clocks, cancellation and legacy migration remain; optional TZif zones
  now execute as described above.
- Randomness: [`core::random` and `std::entropy`](stdlib-randomness.md) execute
  xoshiro256++ generation, seed/state restoration, jumps, unbiased integer
  sampling, fixed-grid floats, byte filling, generic choice/shuffle and checked
  host entropy. Six focused groups compare author-derived vectors, modeled
  sequences, generic payloads, large batches, injected host/allocation failures
  and a binary-safe line-shuffling program. Generation and sampling allocate
  nothing; shuffle uses the caller's storage. Native timing for 1,048,576 raw
  draws is about 46 ms, including a checksum. A nested allocation factory needs
  an explicit type, with failing reproduction and two executable controls.
  Additional distributions and legacy randomness consolidation remain; this
  milestone does not complete the time/randomness family.
- Owned vector: [`alloc::vec`](stdlib-vec.md) provides explicit allocation and
  bounds errors, removed-value transfer, atomic self-extension, shallow clone,
  resizing, sorting and counted views. Four execution groups include 6,000
  modeled edits, generic payloads, zero-sized entries, allocation failures and
  checked-index panics. String, streams, CSV/JSON and three reporting/text
  programs use it. The old vector remains for the verified compiler, legacy
  consumers and the heap migration's separate compiler dependency.
- Owned deque: [`alloc::deque`](stdlib-deque.md) replaces the old std module and
  its unchanged-owner failure convention. It executes both-end edits, rotations,
  borrowed views/cursors, alias-safe extension, split and clone. A 6,000-command
  model, generic payloads, allocation denial and ten migrated programs pass on
  x86_64 Linux. Large FIFO workloads perform 262,144 pop/push pairs at 4,096 and
  65,536 entries with one allocation each and no further allocation attempts.
- Ordered map: [`alloc::tree_map`](stdlib-tree-map.md) executes generic lookup,
  replacement/removal, bounds, ranges, both-ended cursors, clone and linear
  construction from sorted entries. Eight test groups cover a 6,000-command
  reference model, allocation failures, generic payloads, 32,768-key adversarial
  insertion orders and a sorted word-count program. Building from 65,536 sorted
  entries uses 65,535 key comparisons and about 32 ms whole-program CPU time,
  versus 1,966,082 comparisons and 312 ms for repeated insertion. The old
  insertion-ordered linear map has since been removed with its consumers
  migrated. Ordered sets now share this tree engine.
- CLI and host arguments: [`ext::cli` and `std::args`](extended-cli.md) execute
  borrowed option parsing and owned raw-byte argument snapshots. Eight test
  groups cover schema errors, 96 generated command lines, allocation failures,
  32,768-argument lists and a streaming file-checksum application with injected
  I/O errors. Parsing makes no allocations after capture; two snapshot
  allocations suffice at both 4,096 and 32,768 arguments. Higher-level CLI help,
  subcommands remain; logging executes as documented below.
- Configuration: [`ext::config`](extended-config.md) executes strict JSON object
  sources, bounded file loading, typed borrowed queries and explicit shallow
  overlays with source indices. The checksum application combines configuration
  files and CLI overrides. Eight groups cover generated layers, numeric limits,
  every observed allocation failure and host errors. JSON now also exposes
  borrowed text/key queries and exact i64/u64 conversion of decimal/exponent
  forms. [Typed settings](extended-settings.md) now provide JSON/TOML layers and
  explicit environment bindings. Configuration-specific validation and discovery
  policy remain separate.
- Formatting and logging: [`core::fmt`](stdlib-formatting.md) composes integers
  in bases 2–36, Text, scalars, booleans and custom Display implementations into
  caller-backed buffers with measurement and sticky append errors.
  [`ext::log`](extended-log.md) filters and prepares complete typed JSON records
  before any output. The checksum application combines both with configuration
  and CLI settings. Seven groups cover 746 integer reference cases, 67 quoted
  text round trips, record bounds, every observed application allocation/I/O
  failure and allocation-free batches of 8,192 records. Four existing checksum
  groups still pass. A combined generic log-and-write facade exposes a runtime
  compiler defect; it is outside production imports with a reproduction and
  controls. Preparing records and then calling write_all executes.
- Extended CSV: parsing, independent field copies and canonical encoding execute
  on x86_64 Linux, including generated tables, borrowed field views and allocation fault injection.
  See [extended-csv.md](extended-csv.md). Incremental decoding shares the same
  parser; [reusable row construction and bounded stream writing](extended-csv-write.md)
  now execute through the same canonical byte cursor. The
  [column rewrite application](extended-csv-rewrite.md) composes those pieces
  with explicit global input/output/work/call bounds and manual cleanup.
- Shared I/O: portable Read/Write traits, exact/all/copy operations, slice
  cursors, owned byte buffers and native descriptor adapters have execution
  coverage. CSV uses these streams. See [stdlib-streams.md](stdlib-streams.md).
- Extended JSON: iterative parsing/building/encoding, exact number text,
  queries and independent string copies execute on x86_64 Linux, including
  generated trees, limits and allocation fault injection. See
  [extended-json.md](extended-json.md).
- Integer text conversion: [decimal](stdlib-decimal.md) parsing, indexed digit
  access and checked buffer formatting execute for all ten native integer types,
  including i64/u64/isize/usize. Bounds, overflow and insufficient capacity have
  explicit errors. Text methods, owned String construction/appends and native
  output use these conversions; the window-report example now writes i64 sums
  directly. Reference cases and allocation/I/O faults pass on x86_64 Linux.
  With 4,096 samples and width 64, paired native application runtime falls from
  2,539 to 131 ms versus the previous two-word sum output.
- Hash map: [`alloc::hash_map`](stdlib-hash-collections.md) executes generic
  lookup, replacement/removal, reserve, shrink, clone and iteration, including
  collision models and allocation failures. String and all integer widths
  implement hashing. Production HashSet now shares this engine through its
  owner-state boundary; the earlier nested wrapper is retained separately as
  a compiler reproduction.
- Binary heap: [`alloc::binary_heap`](stdlib-binary-heap.md) executes min/max
  queues, linear bulk construction, root replacement, allocation-safe reserve,
  shrink, clone, aliased extension and sorted ownership transfer. Five test
  groups cover generic payloads, 12,000 modeled operations, zero-sized values,
  allocation failures and a top-scores program. For 65,536 records, bulk
  construction uses 131,040 comparisons and about 24 ms native runtime versus
  917,522 comparisons and 117 ms for repeated insertion, with one allocation
  in each path. This does not establish GPU user-program execution.
- CSV-to-JSON integration: the [report application](csv-report.md) validates
  schemas and integers, groups records, checks totals and emits JSON. Native
  tests cover generated records, all allocation failures and partial I/O.
  It now uses the hash map; paired measurements improve the 1,024-group case
  from about 694 ms to 307 ms. The report now uses incremental input and
  packed reusable record buffers.
- Borrowed text: [core::text::Text](stdlib-text.md) executes validation, checked
  subviews, comparison/search, scalar and split iteration, hashing and decimal
  parsing without copying. String and CSV expose borrowed views. The report
  copies each distinct group name once, and reads other fields directly. Paired
  native measurements show 232→175 ms for 4,096 records/64 groups and
  303→269 ms for 4,096 records/1,024 groups before the streaming migration.
- Streaming CSV: one decoder handles complete tables and chunked input,
  including split UTF-8/quotes/CRLF, explicit EOF, sticky errors, resource limits
  and owned record transfer. A syscall-traced 4,096-record run allocates nothing
  after warm-up. The grouping report now retains only current-record buffers
  and group data during input. Paired native runtime falls from 173 to 26 ms
  for 4,096 records/64 groups; peak live allocation request sizes fall from
  779 KB to 99 KB. See [extended-csv.md](extended-csv.md) and [csv-report.md](csv-report.md).
- Borrowed slices: [View and cursors](stdlib-slice-views.md) execute with checked
  logical bounds, overlapping copies, chunks/windows and iteration from either
  end. A 6,388-command model checks stateful behavior. The window-report example
  combines parsing and owned vectors with borrowed windows and exact statistics,
  including allocation and I/O failure coverage. Initial counts still require
  valid physical backing. Shared generic iteration now has separate execution
  evidence through the module below; the older reproductions remain historical.
- [Buffered I/O composition](stdlib-buffered.md) now has its own runtime
  admission: five compiled programs and eighteen native executions cover
  nested readers/writers, confirmed partial progress, every constructor
  allocation failure and actual EPIPE failures during copying and final flush.
  The fixed-capacity buffers require explicit cleanup and preserve their
  confirmed unread/pending ranges on errors; no automatic ownership is implied.
- [Shared iteration](stdlib-iterators.md) now executes through one fused
  protocol, slice and finite i32 range cursors, borrowed take/chain and bounded
  consumption. Seven compilation jobs produce five checked native executables
  and two intended bound rejections. Native models cover 6,602 cases, including
  copy/interleaving semantics and full-domain range skips without enumerating
  billions of items. A nested View-result layout failure remains captured;
  the library uses one direct metadata construction and checked validation path.
  The [range-statistics application](stdlib-range-stats.md) walks the real range
  and take implementations, with one compilation serving 41 native cases:
  full endpoints, million-item quotas, strict arguments and exact cleanup on
  allocation, signal-policy and output errors.
- [Collection, Text and bitset cursors](stdlib-collection-iterators.md) now
  implement that protocol. Three native executables check 408 collection model
  commands, allocation-free byte/scalar/bit views and shallow String ownership.
  Vec and Text byte factories retain their original native-stride views.
- [Mapping, pairing and checked enumeration](stdlib-iterator-adapters.md) now
  compose through the same protocol. Three checked native executables cover
  compound callback results, 1,008 call-order model commands, explicit shallow
  cleanup and an index-overflow trap; three intended rejections check exact
  item bounds. The [range-dot application](stdlib-range-dot.md) adds 67 native
  cases for real zip/take/map/enumerate composition, million-pair inputs,
  checked prefix arithmetic and allocation/output failures.
- [Canonical slice cursors](stdlib-cursor-integration.md) now share one forward
  protocol and backward state across checked factories, borrowed owners and
  fixed-capacity helpers. Two focused native gates include 126 independent
  chunk/window model commands; the migrated window-report program passes 30
  native cases. [Text splits](stdlib-text-split-iterators.md) add two native
  gates with 1,042 model records. [Heap iteration](stdlib-heap-iterators.md)
  adds two accepted native gates with 42 multiset/adapter records and explicit
  String-owner cleanup. No compiler or ABI changes were needed.
- [Selection, searches and folds](stdlib-iterator-selection.md) add five lazy
  adapters plus six consumers using exact typed callbacks. Independent native
  models check 960 selection/copy commands and 714 consumer commands. The
  [column-sum program](stdlib-column-sum.md) validates a selected text column
  and sums checked prefixes before publication. Its focused cases include
  input bounds, malformed values, allocation failures and actual EPIPE.
  A [shared assignment context repair](compiler-iterator-assignment-context.md)
  retains compound call results and preserves previously accepted type facts.
- [Fallible collection](stdlib-iterator-transfer.md) adds a typed sink protocol
  and bounded transfer into fixed vectors, owned vectors and deques. Errors
  retain the accepted prefix and return the rejected item for recovery. Native
  evidence covers 236 independent scenarios with 2,124 stateful actions, all
  eight observed Vec/deque growth-denial positions, compound items/errors and
  exact shallow cleanup. The [word sorter](stdlib-sort-words.md) adds 51 native
  cases, including all 12 observed allocation-failure positions. Further
  collection policies, owning cursor families and automatic destruction remain.
- [Map, set and heap collection](stdlib-iterator-collection-sinks.md) extends
  that protocol to five owned collection types. Unique-key rejection preserves
  old representatives and returns incoming items; heap collection preserves
  Min/Max order and multiplicity. Independent native models cover 640 scenarios
  and 5,760 bounded transfers; all 18 observed growth-denial positions recover.
  Typed String-owner checks, full-capacity duplicates and six exact trait-bound
  rejections pass. The [identifier index](stdlib-index-words.md) adds 65 native
  cases with original word positions, duplicate errors and exact cleanup.
  Replacement/displaced-owner collection policies, other owning cursor families
  and automatic destruction remain work.
- [Owning Vec and Deque cursors](stdlib-owning-iterators.md) now transfer
  storage and item cleanup authority, share front/back traversal, reject an
  early finish without mutation and recover the remainder with its original
  allocation. Independent models cover 352 scenarios and 1,056 recovery rounds.
  Typed and helper-only callers check explicit nested destruction, including
  zero-sized values; every observed destination-growth and source-reuse failure
  recovers. The [streaming word deduplicator](stdlib-unique-words.md) reuses its
  batch allocation across 126 native cases, including 79 allocation denials.
  A reduced finish-result replay dependency remains recorded; helpers use
  canonical empty-owner recovery and destruction. No compiler source changed.
- [Owning hash map/set](stdlib-owning-hash.md),
  [ordered map/set](stdlib-owning-tree.md) and [heap](stdlib-owning-heap.md)
  cursors now transfer cleanup authority and recover their canonical remaining
  collection in O(1). Exhaustion retains backing until explicit finish or
  cleanup; deep helpers release only remaining owners with minimal Destroy
  bounds. Independent native models cover 5,368 hash cases, 192 paired ordered
  steps and 32 snapshots per engine, and 144 priority cases. Address/length
  ledgers check actual owner release. Tree and heap pulls use their existing
  O(log n) removal engines. The word deduplicator now publishes through the
  TreeSet owning cursor and still passes its 126 native cases. Explicit types
  avoid a [reproduced hash insertion context dependency](library-context-inference-dependencies.md);
  the original expression remains a compiler dependency.
- [Streaming runtime formatting](stdlib-format-write.md) now writes through
  generic byte writers using bounded scratch and the existing format grammar.
  Complete preflight precedes output; failures preserve confirmed progress and
  direct call budgets bound Interrupted retries. Native byte/progress models
  cover 960 commands, with independent preflight/error and nested-buffer gates.
  The [CSV report](stdlib-format-report.md) passes 81 native cases, including
  23 representative allocation denials and exact output limits.
- [Iterator lookahead and reductions](stdlib-iterator-lookahead.md) now execute
  with an explicit recoverable cache, nested optional items, relative/MAX
  position search and first-minimum/last-maximum tie policies. Four library
  groups pass in the initial 15.67 s run, including 1,280 cache schedules,
  320 extrema models, 180 position models, exact owner releases and a checked
  overflow-order witness. The [column extrema program](stdlib-column-extrema.md)
  passes its separate 24-case group in 6.51 s after correcting two strace
  harness mistakes; all four reached allocation failures and real output
  injections are checked. No production source changed during those retries.
- Next foundation work: further iterator adapters and consumers, additional
  streaming interfaces, protected Vec/heap migration and numeric/manual
  ownership consolidation. Owned hash/tree sets now execute, and silent-failure
  legacy map/set owners have been removed with their consumers migrated.
  Completing the integration application does not complete the first phase.
- [Nested Vec memory owners](stdlib-nested-clone.md) now use explicit generic
  TryClone/Destroy implementations and the existing clone engine at each level.
  Six native executables cover three levels, aliases, empty/ZST values, owner
  transfer, ten allocation-failure positions and eight owned-error index/stage
  cases. Four source-local rejections cover missing imports/prerequisites and
  contradictory error types. Ordinary shallow collection methods retain their
  policy; other owned collections and automatic lifetime safety remain work.
- Text composition: [join, repeat and word splitting](stdlib-text-composition.md)
  execute with atomic, alias-safe appends, checked sizes and one-allocation
  construction. An executable whitespace normalizer combines borrowed words,
  owned strings, vectors, streams and decimal argument parsing. Generated models,
  capacity overflow and every observed allocation failure are covered.
  For 65,536 parts, paired native runtime is 75.73 ms for join versus 116.36 ms
  for repeated appends; whole-program allocation calls fall from 19 to 2.
  The earlier generic buffered-stream routing failure remains preserved in the
  compiler dependency list. Implementation-application transport and buffered
  adapters now pass separate native gates. Shared slice/range iteration has
  since passed its own admission, followed by collection, Text scalar/byte and
  bitset integration. Split cursors, selection, folds and bounded collection
  have since advanced as recorded above; further adapters and consumers remain.
- Owned files: [File and Path](stdlib-files.md) execute read/create/append,
  generic stream operations, explicit close and ownership transfer on x86_64
  Linux. Tests check binary and non-UTF-8 data, descriptor reuse, path bounds,
  all acquisition/transfer/close failure paths and absence of heap allocation.
  The file-concatenation application closes inputs on errors and preserves bytes.
  Buffered I/O, owned paths and filesystem extensions have since advanced as
  recorded above; automatic owner destruction and other target bindings remain.
- The older [execution audit](stdlib-foundation.md) remains historical evidence;
  its top-level checkpoints do not establish this branch's current behavior.
