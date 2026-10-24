# Standard and extended libraries

The goal is a complete, usable standard library and a broad extended library,
implemented in Lanius. This document tracks the whole scope. Completing the first
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
| Fundamental values | Option, Result, ordering, comparison, hashing, cloning, explicit errors | Generic Option/Result execute; partial equality/order are distinct from total equality/order, with explicit total float keys. Some generic forwarding and record extraction compositions remain compiler dependencies; clone and ownership consolidation remain |
| Numbers | Every primitive width, checked/wrapping/saturating arithmetic, conversions, bit operations, floating-point utilities | Canonical primitive-width arithmetic, bits and conversion policies execute; seven obsolete number/byte helper modules are removed and their ordinary consumers migrated. Pointer widths explicitly describe x86_64. Binary32/binary64 bit, rounding, square-root, decimal and precision-formatting APIs execute, as do full-range binary64 elementary functions with documented accuracy evidence. Native floats use partial comparison with explicit total keys. Represented two-word values remain an explicit separate API |
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic algorithms and counted View values execute, including subviews, checked mutations and cursors; initial physical counts still require compiler length projection |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | Inherent slice/text/hash-map cursors execute; shared protocol dispatch hits an imported-generic compiler dependency; adapters and collection integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed String, borrowed Text, scalar/word iteration, join/repeat, integer/float conversion, caller-buffer Display, runtime format strings and owned formatting execute. Alignment counts scalars and numeric precision rounds exact binary values. Optional extended modules provide Unicode 17 full casing, normalization, default word/grapheme boundaries and an explicit terminal width policy. Richer format controls and collation remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings, raw views and stable chunked arenas with generic typed allocations execute; layout and ownership consolidation remain |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Borrowed-owner alloc Vec, deque and bitset, inline generic Vec/Eq Set, hash/tree maps and sets, and min/max heaps execute. Owned sets include representative ownership and all four fallible algebra operations through shared map engines. Silent-failure legacy map/set/text owners are retired. The protected std::vec/heap migration and deep ownership consolidation remain |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, stdin/stdout/stderr, errors | Shared traits, cursors, owned sinks, descriptor/file adapters and reusable multi-descriptor readiness execute. Polling preserves old publication on errors and uses explicit observed deadlines. Generic buffered adapters remain a compiler routing dependency |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Owned files and paths, lexical operations, checked mutations, configurable/relative opens, seek, metadata, sync, duplication, raw directory iteration and bounded anchored walking execute on native Linux. The directory report exercises filters, metadata and staged output. Automatic owner destruction and broader platform support remain |
| Processes and environment | Arguments, environment, working directory, subprocesses, pipes, exit status | Raw-byte snapshots, explicit argv/environment/PATH/cwd, fork/exec, redirected files, owned pipes, cached waits and child signaling execute on the documented single-threaded Linux profile. Bounded concurrent stdin/stdout/stderr capture preserves partial progress, startup certainty and child ownership across errors. Process groups and concurrent spawn policy remain |
| Time and randomness | Duration, instant, system time, deadlines, deterministic generators, OS entropy | Typed nanosecond arithmetic, calendars, native clocks, deadline waits, deterministic generators, sampling/shuffle and checked OS entropy execute. Optional TZif/POSIX zones provide conversion and ambiguity candidates; four extended continuous distributions have bounded generic sampling. Additional clocks and discrete distributions remain |
| Networking | Addresses, sockets, TCP, UDP, resolution, deadlines, explicit host errors | Numeric IPv4/IPv6 and CIDR values, owned TCP/UDP, polling, deadlines, options and half-close execute via the Linux boundary. Optional DNS transport queries explicit numeric servers with correlated UDP/TCP fallback. Real TCP/DNS programs exercise transfers. Old std::net declarations remain unbound; system resolver/NSS/interface policy, TLS and higher-level clients/servers remain |
| Concurrency | Threads, joining, synchronization, atomics, channels, cancellation | Current thread module is contract-only; runtime prerequisites remain |
| Development | Assertions, test runner, property helpers, benchmarks, diagnostics, API docs | Nontrapping checks, explicit source suites, filters, seeded properties, injected/native-clock benchmarks and a bounded native compiler/run driver execute. Selective, relocatable source bundles use the existing package resolver and verify inventory hashes. Automatic compiler discovery/runtime registration, binary SDK distribution and complete API reference work remain |

## Extended library scope

Each entry needs a public API, executable implementation, examples, failure
tests, target support, and relevant performance evidence.

| Family | Deliverables |
| --- | --- |
| Data formats | JSON, CSV, TOML, binary serialization, schema/validation utilities |
| Text and parsing | Unicode properties and normalization, regex, lexers, parser utilities, diff and patch |
| Files and packaging | Globs, directory walking utilities, compression, archives |
| Network protocols | URL handling, HTTP client/server, WebSockets, DNS, TLS integration |
| Storage | Database interfaces, SQLite integration, key-value storage |
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
algorithms and cryptographic uses remain separate work.

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
large-shape accuracy profiles are explicit; discrete laws remain work.
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
bounded UTF-8 records with counts, numbering and inversion. Wider regex syntax,
replacement/split conveniences and lexers remain. [Text parsing cursors](extended-parse.md)
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
wire bytes. It provides no socket client/server, TLS or HTTP/2 implementation;
those protocol and binding requirements remain on the full roadmap.

[DNS wire processing](extended-dns.md) validates binary names, compression,
QUERY sections, common RDATA and EDNS, with bounded complete message writing.
[WebSocket processing](extended-websocket.md) provides RFC 6455 handshakes,
role masking, fragmented UTF-8, control/close state and frame generation.
Both have real offline programs and independent interoperability/failure tests;
host resolution, TLS and protocol transport orchestration remain separate work.
The [owned socket API](stdlib-sockets.md) and [TCP exchange program](stdlib-tcp-exchange.md)
provide executable numeric-address TCP/UDP transport independently.
[DNS transport](extended-dns-client.md) now adds explicit-server queries, fresh
connected UDP attempts, fixed retry windows, full-question correlation and one
framed TCP fallback, with a real DNS query program. Independent loopback peers,
late-success deadline tests and allocation/host faults verify the implemented
profile. This supplies neither system resolver/NSS policy nor DNS authentication.

[Byte key/value storage](extended-kv.md) provides atomic owned mutations and
canonical CRC-checked snapshots. Its file program stages replacements through
a caller-provided disposable sibling path. Crash durability, locking,
transactions, SQLite and the persistent indexed-archive application remain.

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
API references remain open.

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
   HTTP, URLs, cancellation and synchronization. Acceptance applications:
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
- The language implementations remain Lanius. Rust/Python may drive tests;
  they do not implement library behavior. No JSON transport or Wasm dependency
  is introduced as a substitute for native library execution.

## Current work

- Branch: `codex/stdlib`, based on `441e66f9`.
- Current milestone: the explicit native Linux syscall boundary, owned TCP/UDP
  sockets and signal dispositions; configurable files, metadata, raw directory
  iteration and bounded walking; complete default Unicode sentence/line
  boundaries and terminal wrapping; typed settings and four continuous
  distributions. Real programs, independent models/conformance corpora,
  allocation/descriptor/I/O failure checks and source reviews are recorded per
  guide. Numeric helper consolidation removes seven obsolete modules.
  Subprocesses and a real command runner now pass focused native lifecycle and
  fault gates; startup EOF is explicitly Unconfirmed and ambiguous outcomes
  retain a child owner. Seventeen ordinary collection/output samples now use
  checked APIs and real closed-pipe cleanup. The heap view boundary constructs
  directly from initialized owner state; original failed source is preserved.
  These APIs execute as x86_64 Linux programs produced by the GPU compiler;
  user GPU kernels and other targets are unverified. Threads, TLS, SQLite,
  generic adapter composition and final distribution/reference work remain.
- Preceding milestone: canonical narrow integers, full-range binary64 elementary
  functions, generic owned hash/tree sets, TZif time zones, DNS and WebSocket
  wire processing, byte key/value snapshots, signal processing and selective
  source distribution. Five new native programs and four migrated set consumers
  exercise real behavior. Independent models, malformed-input/resource cases,
  allocation/I/O faults and independent source reviews are recorded per guide.
  Supported execution remains x86_64 Linux output from GPU compilation. The
  [host prerequisite audit](library-host-prerequisites.md) names missing services;
  sockets/processes/threads, SQLite, generic adapter composition and final
  distribution/reference/completion work remain.
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
  Host sockets and name/interface resolution remain runtime prerequisites.
- Paths: [`core::path` and `alloc::path`](stdlib-paths.md) separate borrowed Unix
  paths and owned buffers from host filesystem services. Component cursors,
  names/extensions, ancestors, prefixes, comparison/hash, joins, atomic edits
  and explicit lexical normalization execute. Tests cover 633 reference pairs,
  4,014 modeled edits, aliased inputs, allocation/write failures, large batches
  and a raw-byte path-joining program. Existing mixed-separator/Windows byte
  rules moved to `core::path_rules` with callers. Direct malformed View-record
  construction has a compiler reproduction and an executable control. Host
  metadata and directory enumeration still block the directory-report application.
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
  forms. Environment adapters, reusable schemas and TOML sources remain.
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
  See [extended-csv.md](extended-csv.md). Incremental decoding now shares the same parser; row construction remains.
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
  valid physical backing; shared generic iterator dispatch remains a compiler
  dependency with a minimal reproduction and executable controls.
- Next foundation work: shared iterator and buffered I/O composition, remaining
  streaming format interfaces, protected Vec/heap migration and numeric/manual
  ownership consolidation. Owned hash/tree sets now execute, and silent-failure
  legacy map/set owners have been removed with their consumers migrated.
  Completing the integration application does not complete the first phase.
- Text composition: [join, repeat and word splitting](stdlib-text-composition.md)
  execute with atomic, alias-safe appends, checked sizes and one-allocation
  construction. An executable whitespace normalizer combines borrowed words,
  owned strings, vectors, streams and decimal argument parsing. Generated models,
  capacity overflow and every observed allocation failure are covered.
  For 65,536 parts, paired native runtime is 75.73 ms for join versus 116.36 ms
  for repeated appends; whole-program allocation calls fall from 19 to 2.
  Generic buffered stream adapters hit the same module-context implementation
  routing limitation as iterator consumers; the minimal Write reproduction and
  successful controls are recorded in the compiler dependency list.
- Owned files: [File and Path](stdlib-files.md) execute read/create/append,
  generic stream operations, explicit close and ownership transfer on x86_64
  Linux. Tests check binary and non-UTF-8 data, descriptor reuse, path bounds,
  all acquisition/transfer/close failure paths and absence of heap allocation.
  The file-concatenation application closes inputs on errors and preserves bytes.
  Buffered I/O, complete paths and filesystem runtime extensions remain.
- The older [execution audit](stdlib-foundation.md) remains historical evidence;
  its top-level checkpoints do not establish this branch's current behavior.
